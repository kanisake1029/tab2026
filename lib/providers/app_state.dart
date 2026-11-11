import 'dart:convert';
import '../engine/velo.dart';
import 'dart:io' show gzip;
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/app_database.dart';
import '../models/team.dart';
import '../models/player.dart';
import '../utils/schedule_generator.dart';
import '../utils/standings.dart';
import '../utils/initial_teams_data.dart';
import '../utils/initial_data_format.dart';
import '../engine/match_simulator.dart';
import '../engine/condition_engine.dart';
import '../engine/growth_engine.dart';
import '../engine/farm_engine.dart';
import '../engine/postseason.dart';
import '../engine/awards.dart';
import '../engine/coach_engine.dart';
import '../engine/career_engine.dart';
import '../engine/pre_career.dart';
import '../engine/league_history.dart';
import '../engine/record_query.dart';
import '../models/coach.dart';
import '../models/prospect.dart';
import '../engine/draft_engine.dart';
import '../engine/draft_wish.dart';
import '../engine/other_league_engine.dart';
import '../utils/name_pool.dart';
import '../models/other_league.dart';
import '../models/amateur.dart';
import '../engine/amateur_engine.dart';
import '../engine/amateur_season.dart';
import '../engine/amateur_scout.dart';
import '../engine/career_path.dart';
import '../engine/fielding_gen.dart';
import '../utils/name_data.dart';
import '../engine/roster_engine.dart';
import '../engine/transfer_engine.dart';
import '../utils/salary_utils.dart';
import '../utils/initial_state_store.dart';
import '../utils/player_generator.dart' show autoAssignTeam;
import '../utils/player_traits.dart';
import '../models/finance.dart';
import '../engine/finance_engine.dart';
import '../engine/pitch_catalog.dart';
import '../utils/grade_utils.dart';
import '../engine/foreign_engine.dart';
import '../engine/matchup_book.dart';
import '../engine/batting_splits.dart';
import '../engine/decision_rebuild.dart';
import '../ai/ai_facts.dart';
import '../ai/ai_writer.dart';
import '../ai/pregame_facts.dart';
import 'dart:math';
import '../engine/weather.dart';
import '../engine/facility_engine.dart';
import '../models/equipment.dart';
import '../models/league_rules.dart';
import '../models/stadium.dart';

part 'trade_scout_ops.dart';
part 'offseason_ops.dart';
part 'finance_ops.dart';
part 'camp_ops.dart';
part 'records_ops.dart';
part 'chronicle_ops.dart';
part 'weather_ops.dart';
part 'front_ops.dart';
part 'rules_ops.dart';
part 'other_ops.dart';
part 'amateur_ops.dart';
part 'contract_ops.dart';
part 'replay_ops.dart';
part 'number_ops.dart';

class AppState extends ChangeNotifier {
  List<Team> teams = [];
  String myTeamId = '';
  int startYear = 2026;
  late DateTime currentDate;
  List<Match> matches = [];
  List<Match> farmMatches = []; // 2軍の試合（matches と同じ番号・同じ日程・同じ対戦チーム）
  List<Match> thirdMatches = []; // 3軍の試合（2軍の試合がある日に12球団の総当たりで組む。結果は能力・調子で簡易計算）
  bool seasonFinished = false;  // シーズンの記録を締めた（全日程の終了〜年度の切り替えまでの一瞬だけ）か
  /// シーズンを終えた後のオフか（年度は全日程の終了で切り替わる。FA・契約更改などがあるオフ。1月1日まで）。ゲーム開始直後のオフは false
  bool offAfterSeason = false;
  List<Series> postseason = []; // クライマックスシリーズ・日本シリーズ（公式戦が終わると作る）
  List<Coach> coaches = [];     // 各球団のコーチと OB（teamId が null の人が OB 一覧）

  // ===== フェーズ4・5（ドラフト・移籍） =====
  List<Prospect> prospects = [];      // 次のドラフトの候補
  int draftDoneYear = 0;              // 指名を終えたドラフトの年
  int activeDraftYear = 0;            // 現役ドラフトを終えた年
  int prepDraftYear = 0;              // ゲーム開始直後のドラフトの前に、CPU 球団の戦力外を済ませた年
  List<String> scoutLog = [];         // スカウトの週報
  List<Map<String, dynamic>> tradeTips = []; // スカウトのトレード候補（毎月1日）
  bool _needTrim63 = false;
  bool _needHands = false; // 以前のセーブ：固有12の投打の左右を振り分ける
  bool _needFirsts = false; // 以前のセーブ：選手の「プロ初」の記録を、通算成績から済んだことにする
  bool _needApps = false;
  bool _needDecisions = false;
  bool _needRecords = false; // 以前のセーブ：今季の記録を実況ログから組み立て直す
  bool _careerV2 = false; // 推定の通算成績を作り直したか（先発・被安打・被本塁打などを足した版）

  /// 推定の通算成績を作り直す（一度だけ）：新しい推定 ＋ ゲームの中で終わったシーズンの成績
  Future<void> _fixCareerEstimates() async {
    if (_careerV2) return;
    try {
      final rows = await (db.select(db.seasonRecords)..where((t) => t.kind.equals('player'))).get();
      final hist = <String, List<PlayerStats>>{};
      for (final r in rows) {
        final j = jsonDecode(r.json) as Map<String, dynamic>;
        if (j['stats'] is Map) hist.putIfAbsent(r.refId, () => []).add(PlayerStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)));
      }
      var n = 0;
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
        if (!p.careerEstimated) continue;
        final h = hist[p.id] ?? const <PlayerStats>[];
        final c = CareerEngine.estimate(p, doneSeasons: h.length);
        for (final st in h) {
          c.add(st);
        }
        p.career = c;
        n++;
      }
      _careerV2 = true;
      debugPrint('CAREER REBUILT: $n');
      saveData();
    } catch (e) {
      debugPrint('CAREER FIX ERROR: $e');
    }
  } // 以前のセーブ：今季の勝敗・セーブ・ホールド・自責点を今の規則で付け直す // 以前のセーブ：登板数・先発数を試合の記録から数え直す（読み込みの最後に行う）
  Map<String, String> _forecast = {};  // スカウトの指名予想（候補 ID → 「3球団1位（神・ラ・宮）」）
  String _forecastKey = '';
  List<FreeAgent> freeAgents = [];    // 自由契約の選手（戦力外・育成満了など）
  List<Map<String, dynamic>> monthlyMvps = []; // 今季の月間MVP
  Map<String, List<int>> monthSnap = {};         // 月の初めの成績（月間MVP の計算用）
  List<Map<String, dynamic>> retirees = [];      // 引退した選手の記録（通算成績・表彰。歴代記録と殿堂入りに使う）
  /// ドラフトの指名の記録（年 → 指名）。名前・順位・球団と、指名した時の選手のデータ
  Map<int, List<Map<String, dynamic>>> draftBook = {};
  /// 出来事の記録（年度 → 出来事）。今と前の年度だけメモリに置き、それより前は保存から読む
  Map<int, List<Map<String, dynamic>>> chronYears = {};
  int chronFirstYear = 0; // 出来事の記録を始めた年度
  String openingNumberDay = ''; // この日だけ、自球団の全員の背番号をすぐ変えられる（初期の背番号の扱い。背番号の変遷には変更として残さない）
  Map<String, (String, bool, Player)>? _rosterSnap; // 前回の所属（入団・退団の差分を取る）
  Map<String, (String, String, Coach)>? _coachSnap;
  /// お知らせの記録（暦年 → 「月/日 内容」新しい順）。過去3年分
  Map<int, List<String>> newsLog = {};
  List<Map<String, dynamic>> myCareer = [];      // 自分の戦績（年度ごと：球団・勝敗・順位・優勝）
  List<FaCase> faCases = [];          // FA 宣言した選手と各球団の条件
  List<Player> foreignPool = [];      // 海外の選手の一覧
  Set<String> foreignWatch = {};      // 自球団の海外担当が発掘した海外の選手（他リーグの選手 id。追い続ける）
  Set<String> renewSigned = {};       // 今年の契約更改が済んだ自球団の選手
  Map<String, int> renewTries = {};   // 契約更改で提示した回数
  List<CompCase> pendingComp = [];    // 自球団が選ぶ FA の補償
  /// 次のドラフトで使う補償の指名権（球団 ID → [1.5位の枠, 2.5位の枠]）。FA で A・B ランクの選手を失い、指名権を選んだ分
  Map<String, List<int>> compPicks = {};
  /// 次のドラフトの指名権の持ち主（トレードで動いた分）：'巡|元の球団' → 持ち主の球団
  Map<String, String> pickOwner = {};
  /// CPU 球団の方針（contend 優勝を狙う／middle 中間／rebuild 再建中）
  Map<String, String> teamPolicy = {};
  /// 球団ごとの、自球団と最後にトレードした日（同じ球団と続けて取引できないように）
  Map<String, String> lastTradeWith = {};
  /// 自球団の選手のポスティングの希望（選手 ID → 'ask' まだ決めていない／'ok' 認めた／'no' 認めなかった）
  Map<String, String> postingAsk = {};
  /// 提携枠（球団ごと。ポスティング・海外FA で選手が流出した分）
  List<Map<String, dynamic>> partnerSlots = [];
  /// 自球団の提携選手で、期間が終わって日本に残りたい選手（優先交渉）
  List<String> partnerStay = [];
  /// 育成テンダー（仕様書 6.1）：{pid, from, offers: {球団: 年俸}, match: 元の球団が支配下に上げる}
  List<Map<String, dynamic>> tenders = [];
  /// 他リーグ（MLB・マイナー・海外・独立リーグ）。保存は別（other_ops）
  OtherWorld? otherWorld;
  DateTime? _otherSavedAt;
  bool _otherForceSave = false;
  AmWorld? amWorld;                  // アマチュア球界（高校・大学・社会人）
  DateTime? _amSavedAt;
  bool _amForceSave = false;
  List<Map<String, dynamic>> ledger = []; // お金の出入り（契約金・補償・トレード。経営はフェーズ6）
  List<String> transactions = [];     // 入団・移籍・引退の記録（新しいものが先頭）
  bool autoMode = false;              // 自分の判断が要る場面（ドラフト・補償）もおまかせで進める（確認用）

  // ===== フェーズ6（球団経営） =====
  Map<String, TeamFinance> finances = {}; // 球団ID → 経営
  List<Sponsor> sponsorOffers = [];       // スポンサー候補（12月1日に更新）
  List<Consultant> consultants = [];      // 経営コンサルタント（teamId が空ならフリー）
  bool ownerFiring = true;                // オーナーによる解任あり
  bool fired = false;                     // 解任された（次の行き先を選ぶまで進めない）
  List<String> firedOffers = [];          // 解任後にオファーをくれた球団
  bool ronin = false;                     // 浪人中（1シーズン、試合に関わらず日付だけ進む。元の球団は CPU 監督）
  bool roninReturn = false;               // 浪人が明けて、監督の打診が届いた
  Map<String, int> lastRankOf = {};       // 前年の順位（オーナーの評価用）

  // ===== コーチ・OB =====
  /// 球団のコーチ（役職 → コーチ）
  /// リーグ（Aリーグ・Bリーグ）に入っている球団。未所属（リーグから外した球団）はドラフト・FA・補強などに加わらない
  List<Team> get leagueTeams => [for (final t in teams) if (t.league == 'CL' || t.league == 'PL') t];

  Map<String, Coach> staffOf(Team t) => {for (final c in coaches) if (c.teamId == t.id && c.role != null) c.role!: c};

  /// OB 一覧（どこにも所属していないコーチ候補）
  List<Coach> get obList => coaches.where((c) => c.teamId == null).toList();

  /// コーチがいなければ作る（各球団11人＋OB 野手30人・投手30人）
  void _ensureCoaches() {
    if (coaches.isNotEmpty) return;
    final r = Random(20261031);
    var n = 0;
    int nextId() => ++n;
    for (final t in teams) {
      coaches.addAll(CoachEngine.staffFor(t, r, nextId));
    }
    for (var i = 0; i < 60; i++) {
      final from = teams.isEmpty ? '' : teams[r.nextInt(teams.length)].id;
      final c = CoachEngine.generate(r, 'CO${nextId()}', pitcherBg: i >= 30, formerTeamId: from, age: 38 + r.nextInt(30));
      coaches.add(c);
    }
  }

  /// 選手の年俸を50万円単位にそろえる（初期データ・以前のセーブ。何度しても同じ）
  void _roundSalaries() {
    for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
      if (p.salary > 0 && p.salary % 50 != 0) p.salary = round50(p.salary);
    }
  }

  /// 新しく作ったチームなどに、コーチがいない役職があれば OB から埋める（足りなければ作る）
  void _fillStaff() {
    final r = Random(currentDate.millisecondsSinceEpoch);
    for (final t in teams) {
      final staff = staffOf(t);
      for (final role in CoachEngine.staffRoles) {
        if (staff.containsKey(role)) continue;
        final c = CoachEngine.generate(r, 'CO${DateTime.now().microsecondsSinceEpoch}${r.nextInt(9999)}', pitcherBg: CoachEngine.pitcherRole(role), formerTeamId: t.id, age: 40 + r.nextInt(25));
        c.teamId = t.id;
        c.role = role;
        coaches.add(c);
      }
    }
  }

  /// 打診（OB を役職に就ける）。いまのコーチは OB 一覧へ戻る。年俸は古巣なら目安どおり、他球団の OB は ×1.3
  ///  3軍の打撃・投手・守備走塁は何人でも雇える（いまのコーチはそのまま）。シーズン中の招聘は年俸が割高（×1.5。仮）
  void hireCoach(Team t, String role, Coach c) {
    if (!CoachEngine.multiRole(role)) {
      final cur = staffOf(t)[role];
      if (cur != null) {
        cur.teamId = null;
        cur.role = null;
        cur.seasonsWithTeam = 0;
      }
    }
    c.teamId = t.id;
    c.role = role;
    c.seasonsWithTeam = 0;
    c.salary = CoachEngine.isScout(role) ? CoachEngine.scoutSalary(c) : CoachEngine.askingSalary(c, t.id);
    if (!seasonFinished && matches.any((m) => m.isPlayed && _officialTypes.contains(m.matchType))) c.salary = ((c.salary * 1.5) / 10).round() * 10;
    _staffCache.clear();
    _thirdCache.clear();
    updateAndSave();
  }

  /// 3軍コーチを外す（OB 一覧へ）
  void releaseCoach(Coach c) {
    c.teamId = null;
    c.role = null;
    c.seasonsWithTeam = 0;
    _staffCache.clear();
    _thirdCache.clear();
    updateAndSave();
  }

  /// 球団の年度ごとの成績（終わったシーズン。古い順）：(年度, 記録の JSON)
  Future<List<(int, Map<String, dynamic>)>> teamHistory(String teamId) async {
    final rows = await (db.select(db.seasonRecords)..where((t) => t.refId.equals(teamId) & t.kind.equals('team'))).get();
    rows.sort((a, b) => a.season.compareTo(b.season));
    return [for (final r in rows) (r.season, jsonDecode(r.json) as Map<String, dynamic>)];
  }

  /// 全シーズンの選手の成績の記録（歴代記録用）：(年度, 球団ID, 名前, 1軍の成績)
  Future<List<(int, String, String, PlayerStats)>> allPlayerSeasons() async {
    final rows = await (db.select(db.seasonRecords)..where((t) => t.kind.equals('player'))).get();
    return [
      for (final r in rows)
        () {
          final j = jsonDecode(r.json) as Map<String, dynamic>;
          return (r.season, r.teamId, (j['name'] ?? '') as String, j['stats'] is Map ? PlayerStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)) : PlayerStats());
        }(),
    ];
  }

  /// 選手の年度別の成績（終わったシーズン。古い順）：(年度, 球団ID, 1軍の成績, 2軍の成績)
  Future<List<(int, String, PlayerStats, PlayerStats)>> playerHistory(String playerId) async {
    // 'pre'：推定の年度（開幕日に戻したときに「前からいた」ことにした外国人の1年目など。歴代記録には入れない）
    final rows = await (db.select(db.seasonRecords)..where((t) => t.refId.equals(playerId) & (t.kind.equals('player') | t.kind.equals('pre')))).get();
    rows.sort((a, b) => a.season.compareTo(b.season));
    return [
      for (final r in rows)
        () {
          final j = jsonDecode(r.json) as Map<String, dynamic>;
          PlayerStats st(String k) => j[k] is Map ? PlayerStats.fromJson(Map<String, dynamic>.from(j[k] as Map)) : PlayerStats();
          PlayerStats of(Map m, String k) => m[k] is Map ? PlayerStats.fromJson(Map<String, dynamic>.from(m[k] as Map)) : PlayerStats();
          final teams = j['teams'] is List ? List<String>.from(j['teams'] as List) : const <String>[];
          return [
            for (final sp in (j['splits'] is List ? j['splits'] as List : const []))
              if (sp is Map) (r.season, '${sp['team']}', of(sp, 'stats'), of(sp, 'farm')),
            (r.season, [...teams, r.teamId].join('/'), st('stats'), st('farm')),
          ];
        }(),
    ].expand((x) => x).toList();
  }

  // ===== ゲーム開始前の経歴（推定。年度別の成績・タイトル・節目） =====
  Future<Map<String, List<PreYear>>>? _preCache;
  /// ゲーム開始前の架空の歴史（歴代のタイトル・表彰）。preCareers を読んだあとに入る
  LeagueHistory? leagueHistory;
  Future<GameLogs>? _glogCache;
  String _glogKey = '';
  int _preCacheYear = -1;

  /// 全選手の、ゲーム開始前の年度別の経歴（推定）。選手 ID → 古い順
  Future<Map<String, List<PreYear>>> preCareers() {
    if (_preCache != null && _preCacheYear == startYear) return _preCache!;
    _preCacheYear = startYear;
    return _preCache = _buildPreCareers();
  }

  Future<Map<String, List<PreYear>>> _buildPreCareers() async {
    final rows = await (db.select(db.seasonRecords)..where((t) => t.kind.equals('player'))).get();
    final hist = <String, PlayerStats>{};
    final firstTeam = <String, (int, String)>{};
    var gameStart = startYear;
    for (final r in rows) {
      if (r.season < gameStart) gameStart = r.season;
      final j = jsonDecode(r.json) as Map<String, dynamic>;
      final h = hist.putIfAbsent(r.refId, () => PlayerStats());
      if (j['stats'] is Map) h.add(PlayerStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)));
      var team = r.teamId;
      final sp = j['splits'];
      if (sp is List) {
        for (final x in sp) {
          if (x is Map && x['stats'] is Map) h.add(PlayerStats.fromJson(Map<String, dynamic>.from(x['stats'] as Map)));
        }
        if (sp.isNotEmpty && sp.first is Map) team = '${(sp.first as Map)['team']}';
      }
      final ts = j['teams'];
      if ((sp is! List || sp.isEmpty) && ts is List && ts.isNotEmpty) team = '${ts.first}';
      final f = firstTeam[r.refId];
      if (f == null || r.season < f.$1) firstTeam[r.refId] = (r.season, team);
    }
    final players = <(Player, String)>[
      for (final t in teams) for (final p in t.players) (p, t.id),
      for (final fa in freeAgents) (fa.player, fa.fromTeamId),
    ];
    final out = <String, List<PreYear>>{};
    for (final (p, tid) in players) {
      final pre = PlayerStats()..add(p.career);
      final h = hist[p.id];
      final rest = h == null ? pre : _minusStats(pre, h);
      if (rest.games <= 0 && rest.pitchApps <= 0) continue;
      final entry = startYear - p.proYears + 1;
      final years = gameStart - entry;
      if (years <= 0 || p.joinedInGame) continue; // ゲーム開始後に入団した選手には、開始前の年度は無い（ありもしない年を推定しない）
      final team = firstTeam[p.id]?.$2 ?? tid;
      final ys = PreCareer.split(p, rest, gameStart - years, years, team);
      if (ys.isNotEmpty) out[p.id] = ys;
    }
    final real = <String>{for (final (p, _) in players) ...p.honors};
    final leagueOf = {for (final t in teams) t.id: t.league};
    final teamsOf = <String, List<String>>{};
    for (final t in teams) {
      if (t.league == 'CL' || t.league == 'PL') teamsOf.putIfAbsent(t.league, () => []).add(t.shortName.isNotEmpty ? t.shortName : t.name);
    }
    leagueHistory = LeagueHistory.build(out, {for (final (p, _) in players) p.id: p}, (id) => leagueOf[id] ?? '', teamsOf, real);
    for (final ys in out.values) {
      PreCareer.addMilestones(ys);
    }
    return out;
  }

  /// 以前の版の誤り（一度だけ）：ゲームの中で入団した選手に、開始前の推定の通算が足されていたら、
  ///  通算を「ゲームの中の年度別の記録（1軍）の合計」に戻す
  Future<void> _fixInGameCareers() async {
    if (await db.getKv('joinFixV1') == '1') return;
    final bad = [for (final t in teams) for (final p in t.players) if (p.careerEstimated && p.joinedInGame) p];
    if (bad.isNotEmpty) {
      final rows = await (db.select(db.seasonRecords)..where((t) => t.kind.equals('player'))).get();
      final hist = <String, PlayerStats>{};
      for (final r in rows) {
        final j = jsonDecode(r.json) as Map<String, dynamic>;
        final h = hist.putIfAbsent(r.refId, () => PlayerStats());
        if (j['stats'] is Map) h.add(PlayerStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)));
        final sp = j['splits'];
        if (sp is List) {
          for (final x in sp) {
            if (x is Map && x['stats'] is Map) h.add(PlayerStats.fromJson(Map<String, dynamic>.from(x['stats'] as Map)));
          }
        }
      }
      for (final p in bad) {
        p.career = PlayerStats()..add(hist[p.id] ?? PlayerStats());
        p.careerEstimated = false;
      }
      _preCache = null;
      debugPrint('CAREER FIX: ${bad.length} players joined in game');
    }
    await db.setKv('joinFixV1', '1');
  }

  /// a − b（0未満は0。守備位置ごとの値も）
  PlayerStats _minusStats(PlayerStats a, PlayerStats b) {
    final ja = a.toJson(), jb = b.toJson();
    final o = <String, dynamic>{};
    // 数・数の並び（ゾーン別など）・それらの表を、要素ごとに引く（0未満は0）
    dynamic minus(dynamic x, dynamic y) {
      if (x is int) return max(0, x - (y is int ? y : 0));
      if (x is List) {
        final yl = y is List ? y : const [];
        return [for (var i = 0; i < x.length; i++) minus(x[i], i < yl.length ? yl[i] : 0)];
      }
      if (x is Map) {
        final ym = y is Map ? y : const {};
        return {for (final e in x.entries) e.key: minus(e.value, ym[e.key])};
      }
      return x;
    }

    ja.forEach((k, v) {
      if (v is int) o[k] = minus(v, jb[k]);
      if (v is Map) {
        final m = minus(v, jb[k]) as Map;
        m.removeWhere((_, x) => x is int && x <= 0);
        o[k] = m;
      }
      if (v is List) o[k] = minus(v, jb[k]);
    });
    return PlayerStats.fromJson(o);
  }

  /// 以前のセーブ：同じ ID の選手が2球団にいたら直す。
  ///  ・同じ選手（名前と入団の記録が同じ）が二重に入っている → 1球団だけに残す（自球団 → ドラフトの記録の球団 → 先の球団）
  ///  ・別の選手が同じ ID を持っている（同じ年のドラフト候補が作り直されたときに起きた）→ 後の球団の選手に新しい ID を振る。
  ///    球団の中の打順・ローテ・登録などの ID もまとめて置き換える（選手はどこからも消さない）
  void _fixDuplicatePlayers() {
    // 同じ球団の中で2人が同じ ID：2人目に新しい ID（打順などの参照は1人目のまま）
    final used = <String>{for (final t in teams) for (final p in t.players) p.id};
    for (final t in teams) {
      final seen = <String>{};
      for (var i = 0; i < t.players.length; i++) {
        final p = t.players[i];
        if (seen.add(p.id)) continue;
        var n = 0;
        String nid;
        do {
          nid = '${p.id}_s${++n}';
        } while (used.contains(nid));
        used.add(nid);
        t.players[i] = Player.fromJson({...p.toJson(), 'id': nid});
        debugPrint('DUP IN TEAM: ${p.registeredName}（${t.name}） ${p.id} → $nid');
      }
    }
    // 自由契約の一覧の選手が、球団の選手と同じ ID：自由契約の選手に新しい ID
    for (var i = 0; i < freeAgents.length; i++) {
      final fa = freeAgents[i];
      if (!used.contains(fa.player.id)) {
        used.add(fa.player.id);
        continue;
      }
      var n = 0;
      String nid;
      do {
        nid = '${fa.player.id}_f${++n}';
      } while (used.contains(nid));
      used.add(nid);
      freeAgents[i] = FreeAgent(Player.fromJson({...fa.player.toJson(), 'id': nid}), fa.fromTeamId, fa.reason);
      debugPrint('DUP FREE AGENT: ${fa.player.registeredName} ${fa.player.id} → $nid');
    }
    final where = <String, List<Team>>{};
    for (final t in teams) {
      for (final p in t.players) {
        where.putIfAbsent(p.id, () => []).add(t);
      }
    }
    final allIds = where.keys.toSet();
    for (final e in where.entries.where((e) => e.value.length > 1)) {
      final ts = e.value;
      final p0 = ts.first.players.firstWhere((p) => p.id == e.key);
      final keep = ts.firstWhere((t) => t.id == myTeamId, orElse: () => ts.firstWhere((t) => transactions.any((l) => l.contains(' ${teamShort(t)} ${p0.draftInfo} ${p0.registeredName}')), orElse: () => ts.first));
      final kp = teams.firstWhere((x) => x.id == keep.id).players.firstWhere((p) => p.id == e.key);
      var n = 0;
      for (final t0 in ts.where((t) => t.id != keep.id)) {
        final t = teams.firstWhere((x) => x.id == t0.id); // 先に作り直した球団なら、その新しい方
        final p = t.players.firstWhere((x) => x.id == e.key);
        if (p.registeredName == kp.registeredName && p.draftInfo == kp.draftInfo) {
          RosterEngine.removePlayer(t, p);
          transactions.removeWhere((l) => p.draftInfo.isNotEmpty && l.contains(' ${teamShort(t)} ${p.draftInfo} ${p.registeredName}'));
          debugPrint('DUP SAME: ${p.registeredName} ${e.key} → ${keep.name}（${t.name}から外す）');
          continue;
        }
        String nid;
        do {
          nid = '${e.key}_r${++n}';
        } while (allIds.contains(nid));
        allIds.add(nid);
        final js = jsonEncode(t.toJson()).replaceAll('"${e.key}"', '"$nid"');
        final nt = Team.fromJson(jsonDecode(js) as Map<String, dynamic>, Player.fromJson);
        final i = teams.indexOf(t);
        teams[i] = nt;
        debugPrint('DUP NEW ID: ${p.registeredName}（${t.name}） ${e.key} → $nid');
      }
    }
  }

  /// 以前のセーブ：シーズン終了時の記録の保存が失敗していた（同じ ID の選手がいて、年度別の記録がまとめて書けなかった）。
  ///  オフシーズンの間（今季の成績がまだ選手に残っている間）なら作り直す：年度別の記録（選手・球団）・リーグの要約・表彰、表彰を選手の経歴へ。
  ///  所属は、シーズン終了時の球団（オフに移った選手は移籍の記録から元の球団、自由契約の選手は元の球団）。引退した選手の分は作れない
  Future<void> _repairLostSeasonRecords() async {
    final year = startYear;
    if (!seasonFinished || currentDate.year != year) return;
    try {
      if (await db.getKv('awards_$year') != null) return;
      final have = await (db.select(db.seasonRecords)..where((r) => r.season.equals(year))).get();
      if (have.any((r) => r.kind == 'player')) return;
      // シーズン終了時の所属（オフに動いた選手を元の球団へ）
      final byShort = {for (final t in teams) teamShort(t): t};
      String? endTeam(Player p) {
        for (final m in p.moves) {
          final mm = RegExp(r'^(\d{4})年(\d+)月\d+日 .+（←(.+)）$').firstMatch(m);
          if (mm == null) continue;
          if (int.parse(mm.group(1)!) == year && int.parse(mm.group(2)!) >= 10) return byShort[mm.group(3)!]?.id;
        }
        return null;
      }

      final snap = [for (final t in teams) Team.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>, Player.fromJson)];
      final snapById = {for (final t in snap) t.id: t};
      final real = {for (final t in teams) for (final p in t.players) p.id: p};
      // 作り直した球団の選手を、本物の選手に差し替える（成績・表彰を本物に書くため）
      for (final t in snap) {
        final ps = [for (final p in t.players) real[p.id] ?? p];
        t.players
          ..clear()
          ..addAll(ps);
      }
      for (final t in teams) {
        for (final p in t.players) {
          final e = endTeam(p);
          if (e == null || e == t.id || snapById[e] == null) continue;
          snapById[t.id]!.players.removeWhere((x) => x.id == p.id);
          snapById[e]!.players.add(p);
        }
      }
      for (final fa in freeAgents) {
        final t = snapById[fa.fromTeamId];
        if (t != null && !t.players.any((x) => x.id == fa.player.id)) t.players.add(fa.player);
      }
      // そのオフのドラフトの新人は、今季はいなかった
      for (final t in snap) {
        t.players.removeWhere((p) => p.draftYear == year && p.seasonStats.games == 0 && p.farmStats.games == 0);
      }

      final ranks = <String, int>{};
      final records = <String, List<int>>{};
      for (final lg in ['CL', 'PL']) {
        final st = computeStandings(snap, matches, lg, StandingsKind.official);
        for (var i = 0; i < st.length; i++) {
          ranks[st[i].team.id] = i + 1;
          records[st[i].team.id] = [st[i].w, st[i].l, st[i].d];
        }
      }
      final rows = <SeasonRecordsCompanion>[];
      for (final t in snap) {
        rows.add(SeasonRecordsCompanion.insert(
          season: year, kind: 'team', refId: t.id, teamId: t.id,
          json: jsonEncode({'name': t.name, 'league': t.league, 'wins': records[t.id]?[0], 'losses': records[t.id]?[1], 'draws': records[t.id]?[2], 'rank': ranks[t.id],
            'champion': champion?.id == t.id, 'manager': t.id == myTeamId ? 'あなた' : (staffOf(teamById(t.id) ?? t)['監督']?.name ?? '')}),
        ));
        for (final p in t.players) {
          rows.add(SeasonRecordsCompanion.insert(
            season: year, kind: 'player', refId: p.id, teamId: t.id,
            json: jsonEncode({'name': p.registeredName, 'age': p.age, 'ovr': p.ovr, 'pos': p.mainPosition, 'stats': p.seasonStats.toJson(), 'farm': p.farmStats.toJson(), 'teams': p.seasonTeams, 'splits': p.seasonSplits}),
          ));
        }
      }
      final summary = _leagueSummary(year);
      final awards = AwardsEngine.compute(
        year: year,
        teams: snap,
        matches: matches,
        previous: null,
        prevStats: const {},
        series: [for (final s in postseason) {'id': s.id, 'label': s.label, 'high': s.high, 'low': s.low, 'winner': s.winner, 'mvp': s.mvp, 'score': _seriesScore(s)}],
        allStarMvps: [for (final m in matches.where((m) => m.matchType == 'ALLSTAR')) if (m.boxScore?['mvp'] is String) m.boxScore!['mvp'] as String],
        championId: champion?.id,
      );
      await db.saveRecords(year, rows);
      await db.setKv('summary_$year', jsonEncode(summary));
      await db.setKv('awards_$year', jsonEncode(awards));
      // 表彰を選手の経歴へ（まだ書いていなければ）
      final before = {for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) p.id: p.honors.length};
      final already = teams.expand((t) => t.players).any((p) => p.honors.any((h) => h == '$year年 MVP' || h.startsWith('$year年 首位打者') || h.startsWith('$year年 本塁打王')));
      if (!already) _recordHonors(year, awards);
      final added = teams.expand((t) => t.players).fold<int>(0, (a, p) => a + p.honors.length - (before[p.id] ?? p.honors.length));
      _preCache = null;
      debugPrint('SEASON RECORDS REBUILT: $year rows=${rows.length} honors+$added');
      _addNews(['$year年の年度別成績・表彰の記録を作り直しました（保存に失敗していた分）']);
      updateAndSave();
    } catch (e, st) {
      debugPrint('SEASON REPAIR ERROR: $e $st');
    }
  }

  /// 同じ ID だった選手の年度別の記録を直す（新しい ID を振った選手：ID の後ろが _r1 / _s1 など）。
  ///  記録は年度・ID ごとに1行なので、2人のうち1人分しか残っていない。残っている行は名前でどちらの選手か分かるので、
  ///  ・新しい ID の選手の行だった → 新しい ID へ移す
  ///  ・もう1人の行が無い → シーズンが終わってから年度が変わるまで（今季の成績がまだ選手に残っている間）は、その成績から作る
  Future<void> _repairRenamedRecords() async {
    final renamed = [for (final t in teams) for (final p in t.players) if (RegExp(r'_[rs]\d+$').hasMatch(p.id)) (p, t)];
    if (renamed.isEmpty) return;
    final byId = {for (final t in teams) for (final p in t.players) p.id: (p, t)};
    final canRebuild = seasonFinished && currentDate.year == startYear; // 今季の成績がまだ残っている
    try {
      final rows = await (db.select(db.seasonRecords)..where((r) => r.kind.equals('player'))).get();
      final have = {for (final r in rows) '${r.season}|${r.refId}': r};
      String nameOf(SeasonRecord r) => '${(jsonDecode(r.json) as Map)['name'] ?? ''}';
      SeasonRecordsCompanion fromData(Player p, Team t) => SeasonRecordsCompanion.insert(
            season: startYear, kind: 'player', refId: p.id, teamId: t.id,
            json: jsonEncode({'name': p.registeredName, 'age': p.age, 'ovr': p.ovr, 'pos': p.mainPosition, 'stats': p.seasonStats.toJson(), 'farm': p.farmStats.toJson(), 'teams': p.seasonTeams, 'splits': p.seasonSplits}),
          );
      final out = <SeasonRecordsCompanion>[];
      for (final (p, t) in renamed) {
        final base = p.id.replaceFirst(RegExp(r'_[rs]\d+$'), '');
        final seasons = {for (final r in rows) if (r.refId == base) r.season};
        for (final season in seasons) {
          if (have['$season|${p.id}'] != null) continue; // 直してある
          final baseRow = have['$season|$base']!;
          final other = byId[base];
          if (nameOf(baseRow) == p.registeredName) {
            // 残っていたのはこの選手の行 → 新しい ID へ。もう1人の行は作り直す
            out.add(SeasonRecordsCompanion.insert(season: season, kind: 'player', refId: p.id, teamId: baseRow.teamId, json: baseRow.json));
            if (other != null && other.$1.registeredName != p.registeredName && season == startYear && canRebuild) out.add(fromData(other.$1, other.$2));
          } else if (season == startYear && canRebuild) {
            out.add(fromData(p, t)); // 残っていたのはもう1人の行 → この選手の行を作る
          }
        }
      }
      if (out.isEmpty) return;
      await db.upsertRecords(out);
      _preCache = null;
      debugPrint('RECORDS REPAIRED: ${out.length}');
    } catch (e, st) {
      debugPrint('RECORDS REPAIR ERROR: $e $st');
    }
  }

  /// 今の球団での今季成績（1軍。farm=true で2軍）：今季成績から、今の球団に来たときの分を引いたもの
  PlayerStats seasonPortion(Player p, {bool farm = false}) {
    final now = farm ? p.farmStats : p.seasonStats;
    final b = p.partBase[farm ? 'farm' : 'stats'];
    if (b is! Map) return now;
    return _minusStats(now, PlayerStats.fromJson(Map<String, dynamic>.from(b)));
  }

  /// 球団ごとの今季の選手成績（スコアラー）：その球団でプレーした分。今いる選手（今の球団での分）と、今季その球団にいて移った選手（その球団での分）。
  ///  level 0=1軍 1=2軍 2=3軍（3軍は今いる選手だけ）。戻り値の3つ目は「移った選手」
  List<(Player, PlayerStats, bool)> teamSeasonEntries(Team t, int level) {
    if (level == 2) return [for (final p in t.players) (p, p.thirdStats, false)];
    final farm = level == 1;
    PlayerStats partsAt(Player p) {
      final st = PlayerStats();
      for (final part in p.seasonParts.where((x) => x['team'] == t.id)) {
        final m = part[farm ? 'farm' : 'stats'];
        if (m is Map) st.add(PlayerStats.fromJson(Map<String, dynamic>.from(m)));
      }
      return st;
    }

    // 今いる選手（前にもこの球団にいて戻ってきた分も足す）
    final out = <(Player, PlayerStats, bool)>[for (final p in t.players) (p, seasonPortion(p, farm: farm)..add(partsAt(p)), false)];
    for (final p in [...teams.where((x) => x.id != t.id).expand((x) => x.players), ...freeAgents.map((f) => f.player)]) {
      final st = PlayerStats();
      for (final part in p.seasonParts.where((x) => x['team'] == t.id)) {
        final m = part[farm ? 'farm' : 'stats'];
        if (m is Map) st.add(PlayerStats.fromJson(Map<String, dynamic>.from(m)));
      }
      if (st.games + st.pitchApps > 0) out.add((p, st, true));
    }
    return out;
  }

  /// 通算成績（1軍）。シーズン中は通算（前年まで）＋今季。シーズンを締めた後（オフ）は今季の分も通算に入っているので足さない
  PlayerStats careerTotalOf(Player p) {
    final t = PlayerStats()..add(p.career);
    if (seasonFinished) return t;
    t.add(p.seasonStats);
    for (final sp in p.seasonSplits) {
      if (sp['stats'] is Map) t.add(PlayerStats.fromJson(Map<String, dynamic>.from(sp['stats'] as Map)));
    }
    return t;
  }

  /// 経験値の倍率（練習・試合とも）：コーチ × 設備（バイオメカニクス解析ラボ）× 転向（技巧派・職人）
  double _expMult(Team t, Player p, GrowthStat s) => _coachMult(t, p, s) * FacilityEngine.labMult(finOf(t).fac('bio'), s.key) * GrowthEngine.shiftPracticeMult(p, s.key);

  /// 試合の経験値の倍率：上の倍率 ＋ 2軍・3軍の選手は2軍監督・3軍監督の育成眼（×0.85〜1.15。練習と同じ）
  double _gameExpMult(Team t, Player p, GrowthStat s) {
    final real = teamById(t.id) ?? t;
    final farm = !real.roster1G.contains(p.id);
    final dev = farm ? 0.85 + (p.ikusei ? thirdDevEye(real) : farmDevEye(real)) / 100 * 0.3 : 1.0;
    return _expMult(real, p, s) * dev;
  }

  /// 練習効果の倍率（コーチの指導力・相性・人望）
  double _coachMult(Team t, Player p, GrowthStat s) {
    final staff = _staffCache[t.id] ??= staffOf(t);
    if (!p.ikusei) return CoachEngine.practiceMultiplier(p, s, t, staff);
    final third = _thirdCache[t.id] ??= {for (final r in CoachEngine.roles3G) r: staffListOf(t, r)};
    final n = _ikuseiCountCache[t.id] ??= t.players.where((x) => x.ikusei).length;
    return CoachEngine.practiceMultiplier(p, s, t, staff, third: third, ikuseiCount: n);
  }
  final Map<String, Map<String, List<Coach>>> _thirdCache = {};
  final Map<String, int> _ikuseiCountCache = {};

  /// 役職のコーチ（3軍の打撃・投手・守備走塁は複数人）
  List<Coach> staffListOf(Team t, String role) => [for (final c in coaches) if (c.teamId == t.id && c.role == role) c];

  /// 3軍コーチの人数
  int thirdCoachCount(Team t) => coaches.where((c) => c.teamId == t.id && CoachEngine.roles3G.contains(c.role)).length;

  /// 育成選手の人数の上限（仕様書 6.2。仮）：設備（バイオメカニクス解析ラボ）のレベルで決まる基本枠＋3軍コーチ1人あたり5人
  int ikuseiCap(Team t) => 12 + 3 * finOf(t).fac('bio') + 5 * thirdCoachCount(t);

  /// 3軍監督の育成眼（いなければ40）
  int thirdDevEye(Team t) {
    final c = (_staffCache[t.id] ??= staffOf(t))['3軍監督'];
    return c == null ? 40 : CoachEngine.devEye(c);
  }
  final Map<String, Map<String, Coach>> _staffCache = {};

  static bool isPostType(String t) => t == 'CS' || t == 'JS';
  static bool isSpecialType(String t) => isPostType(t) || t == 'ALLSTAR';
  /// 今季成績に入れない試合（ポストシーズン・オープン戦。オールスターは別に退避する）
  static bool _noStats(String t) => isPostType(t) || t == 'OPEN';

  /// 球団（オールスターの仮の球団IDなら、表示用の選抜チーム）
  Team? teamById(String id) {
    for (final t in teams) {
      if (t.id == id) return t;
    }
    if (id == 'PL_ALLSTAR') return Team(id: id, name: 'Bリーグ選抜', shortName: 'B選抜', initialName: 'B', league: 'PL');
    if (id == 'CL_ALLSTAR') return Team(id: id, name: 'Aリーグ選抜', shortName: 'A選抜', initialName: 'A', league: 'CL');
    return null;
  }
  static const farmIdxBase = 100000; // DB上で2軍の試合の番号に足す数

  List<Team> get plTeams => teams.where((t) => t.league == 'PL').toList();
  List<Team> get clTeams => teams.where((t) => t.league == 'CL').toList();

  final AppDatabase db;
  bool loaded = false;
  /// プレイデータの枠（1〜3）
  final int slot;

  AppState([AppDatabase? database, this.slot = 1]) : db = database ?? AppDatabase() {
    currentDate = DateTime(startYear - 1, 10, 31); // 監督就任は、1年目のドラフト会議（前年10月31日）から
    loadData();
  }

  // 初期データに末尾カンマ（不正なJSON）が含まれているため、読み込み前に取り除く
  static String _cleanJson(String s) => s.replaceAllMapped(RegExp(r',(\s*[\]}])'), (m) => m[1]!);

  List<Team> _initialTeams() {
    final ts = (jsonDecode(_cleanJson(InitialTeamsData.jsonString)) as List).map<Team>((t) => Team.fromJson(t, Player.fromJson)).toList();
    _raiseBody(ts);
    _slowVelocity(ts);
    _regenPitches(ts);
    _raiseClutch(ts);
    _shiftProYears(ts);
    _assignHands(ts.expand((t) => t.players));
    for (final p in ts.expand((t) => t.players)) {
      _fieldingIfDefault(p);
    }
    return ts;
  }

  /// 守備適性がオールC（初期値の60のまま）なら、本職の型に合わせて付け直す（選手の id で決まる）。二刀流の投手適性は残す
  bool _fieldingIfDefault(Player p) {
    final all = [p.fieldC, p.field1B, p.field2B, p.field3B, p.fieldSS, p.fieldLF, p.fieldCF, p.fieldRF];
    if (!all.every((v) => v == 60)) return false;
    final keepP = p.fieldP;
    FieldingGen.apply(p, Random(p.id.hashCode ^ 0x6f1));
    if (p.twoWay) p.fieldP = keepP;
    return true;
  }

  /// 固有12（初期データ）の投打の左右を振り分ける（初期データは全員が右投右打だったため）。
  ///  選手の id から決めるので、何度やっても同じ結果になる。割合は実際のプロ野球に近づける：
  ///  投手は約3割が左投げ。野手は右投右打55%・右投左打32%・左投左打10%・右投両打3%（捕手・二塁・三塁・遊撃は右投げ）
  void _assignHands(Iterable<Player> ps) {
    final orig = RegExp(r'^[CP]\d_P\d+$');
    const rightOnly = {'捕手', '二塁手', '三塁手', '遊撃手'};
    for (final p in ps) {
      if (!orig.hasMatch(p.id) || p.bats != 'R' || p.throws != 'R') continue;
      final x = Random(p.id.hashCode ^ 0x4a7d).nextDouble(), y = Random(p.id.hashCode ^ 0x1b3f).nextDouble();
      if (p.isPitcher) {
        p.throws = x < 0.30 ? 'L' : 'R';
        p.bats = p.throws == 'L' ? (y < 0.85 ? 'L' : 'R') : (y < 0.75 ? 'R' : (y < 0.98 ? 'L' : 'S'));
      } else {
        if (x < 0.55) {
          p.throws = 'R';
          p.bats = 'R';
        } else if (x < 0.87) {
          p.throws = 'R';
          p.bats = 'L';
        } else if (x < 0.97) {
          p.throws = rightOnly.contains(p.mainPosition) ? 'R' : 'L';
          p.bats = 'L';
        } else {
          p.throws = 'R';
          p.bats = 'S';
        }
      }
    }
  }

  /// 固有12（初期データ）の投手の球速を現実的に：160km 以上は各球団3人ほど、165km 以上は各リーグ1人。
  ///  球団内の速い順に並べ直して割り当てる（順位は変えない）。持ち球の球速も同じだけずらす
  void _slowVelocity(List<Team> ts) {
    final orig = RegExp(r'^[CP]\d_P\d+$');
    final changed = <Player, int>{};
    for (final t in ts) {
      final ps = t.players.where((p) => p.isPitcher && orig.hasMatch(p.id)).toList()
        ..sort((a, b) => b.velocity != a.velocity ? b.velocity.compareTo(a.velocity) : b.pitchPower.compareTo(a.pitchPower));
      final r = Random(t.id.hashCode ^ 0x5e1);
      for (var i = 0; i < ps.length; i++) {
        final int v;
        if (i == 0) {
          v = 162 + r.nextInt(3);
        } else if (i == 1) {
          v = 160 + r.nextInt(3);
        } else if (i == 2) {
          v = 160 + r.nextInt(2);
        } else {
          final q = ps.length <= 4 ? 0.0 : (i - 3) / (ps.length - 4);
          v = (159 - q * 21 + r.nextInt(3) - 1).round().clamp(136, 159);
        }
        changed[ps[i]] = ps[i].velocity;
        ps[i].velocity = v;
      }
    }
    // 各リーグで元々いちばん速かった投手だけ 165km 以上に
    for (final lg in const ['CL', 'PL']) {
      final cands = changed.keys.where((p) => ts.any((t) => t.league == lg && t.players.contains(p))).toList()
        ..sort((a, b) => changed[b]!.compareTo(changed[a]!));
      if (cands.isNotEmpty) cands.first.velocity = 165 + Random(lg.hashCode).nextInt(2);
    }
    changed.forEach((p, old) {
      final d = p.velocity - old;
      for (final x in p.pitches) {
        x.speed = (x.speed + d).clamp(70, 170);
      }
    });
  }

  /// 初期データのプロ年数は「前の年（開始の前年）のシーズン」のもの。開始の年は1年進める
  ///  （開始の年の新人は、ゲームの中のドラフト（前年10月31日）で入る。初期選手に開始の年が1年目の選手はいない）
  void _shiftProYears(List<Team> ts) {
    for (final t in ts) {
      for (final p in t.players) {
        p.proYears += 1;
        p.faService += 1;
      }
    }
  }

  /// 以前のセーブ（一度だけ）：初期選手のプロ年数を1年進める（ゲーム開始の年が1年目になっていた）
  bool _freshInitial = false; // 初期データから新しく始めた（プロ年数は初期データの時点で直してある）
  Future<void> _fixInitialProYears() async {
    if (await db.getKv('proYearFixV1') == '1') return;
    if (_freshInitial) return db.setKv('proYearFixV1', '1');
    final orig = RegExp(r'^[CP]\d+_P\d+$');
    var n = 0;
    for (final t in teams) {
      for (final p in t.players) {
        if (orig.hasMatch(p.id) && !p.joinedInGame) {
          p.proYears += 1;
          n++;
        }
      }
    }
    for (final fa in freeAgents) {
      if (orig.hasMatch(fa.player.id) && !fa.player.joinedInGame) fa.player.proYears += 1;
    }
    _preCache = null;
    debugPrint('PROYEARS FIX: $n');
    await db.setKv('proYearFixV1', '1');
  }

  void _raiseClutch(List<Team> ts) {
    for (final t in ts) {
      for (final p in t.players) {
        p.raiseClutchQuick();
      }
    }
  }

  /// 投手の持ち球を球種カタログから作り直す（初期データと、以前のセーブ。選手ごとに決まった乱数）
  void _regenPitches(List<Team> ts) {
    for (final t in ts) {
      for (final p in t.players) {
        if (!p.isPitcher) continue;
        p.pitches = PitchCatalog.generate(p, Random(p.id.hashCode * 31 + 7), starter: t.rotation.contains(p.id) || p.stamina >= 60);
      }
    }
  }

  /// 体力・回復力・怪我しにくさを今の基準に底上げする（初期データと、以前のセーブ）
  void _raiseBody(List<Team> ts) {
    for (final t in ts) {
      for (final p in t.players) {
        raiseBodyStats(p);
      }
    }
  }

  /// 外国人：以前のデータの一覧は新しい形（支配下120・育成60）で作り直し、球団にいる外国人には出身国と来日前の成績を付ける
  void _migrateForeign() {
    if (foreignPool.isNotEmpty && foreignPool.every((p) => p.origin.isEmpty)) {
      final y = currentDate.month >= 12 ? currentDate.year + 1 : currentDate.year;
      foreignPool = buildForeignPool(y);
    }
    for (final t in teams) {
      for (final p in t.players) {
        ForeignEngine.fillMissing(p, startYear);
      }
    }
  }

  /// 投手の持ち球が1つしかない古いデータに、標準の持ち球を入れる
  void _migratePitchers() {
    for (var team in teams) {
      for (var p in team.players) {
        if (p.isPitcher && p.pitches.length <= 1) {
          p.pitches = [
            Pitch(name: 'ストレート', breakLevel: 0, angle: 90, speed: p.velocity, ratio: 45, sharpness: 60, heaviness: 60),
            Pitch(name: 'スライダー', breakLevel: 60, angle: 180, speed: p.velocity - 15, ratio: 25, sharpness: 60, heaviness: 60),
            Pitch(name: 'カーブ', breakLevel: 60, angle: 135, speed: p.velocity - 30, ratio: 15, sharpness: 60, heaviness: 60),
            Pitch(name: 'フォーク', breakLevel: 60, angle: 90, speed: p.velocity - 20, ratio: 15, sharpness: 60, heaviness: 60),
          ];
        }
      }
    }
  }

  // ===== 保存（drift / SQLite。Web・Android・iOS で同じ） =====
  // 1球ごとの記録：自チームの試合は必ず、他球団の試合は設定（recordAllPitches）がオンのときだけ保存する
  bool recordAllPitches = false;
  List<PitchRowsCompanion> _pendingPitches = [];
  int? _compactSeasonPending; // 年が変わったら、前のシーズンを要約だけにする（保存のときに実行）

  // ===== 対戦成績（投手×打者。今季の公式戦の自球団の試合） =====
  final MatchupBook matchups = MatchupBook();
  bool matchupsReady = false;
  static const _officialTypes = {'LEAGUE', 'INTERLEAGUE'};

  /// 名前から選手の id を引く（その試合の球団の選手 → 見つからなければ12球団で名前が1人だけの選手）
  String? Function(bool home, String name) _idResolver(Match m) {
    final global = <String, String?>{};
    for (final t in teams) {
      for (final p in t.players) {
        global[p.registeredName] = global.containsKey(p.registeredName) ? null : p.id;
      }
    }
    final byTeam = <String, Map<String, String>>{};
    Map<String, String> teamMap(String tid) => byTeam.putIfAbsent(tid, () => {for (final p in (teams.where((t) => t.id == tid).firstOrNull?.players ?? const <Player>[])) p.registeredName: p.id});
    return (home, name) => teamMap(home ? m.homeTeamId : m.awayTeamId)[name] ?? global[name];
  }

  void _addMatchupGame(int idx, Iterable<PitchRec> recs) {
    if (idx < 0 || idx >= matches.length || !_officialTypes.contains(matches[idx].matchType)) return;
    matchups.addGame(idx, recs, _idResolver(matches[idx]));
  }

  /// 読み込んだあと：保存してある今季の1球ごとの記録から対戦成績を作る
  Future<void> loadMatchups() async {
    try {
      final rows = await db.loadSeasonPitches(startYear);
      final by = <int, List<PitchRec>>{};
      for (final r in rows) {
        by.putIfAbsent(r.matchIdx, () => []).add(PitchRec(paIndex: r.paIndex, pitchNo: r.pitchNo, battingHome: r.battingHome, batter: r.batter, pitcher: r.pitcher, result: r.result, outcome: r.outcome, balls: r.balls, strikes: r.strikes));
      }
      by.forEach(_addMatchupGame);
      if (await db.getKv('splitsV2') != '1') {
        _backfillSplits(rows);
        await saveData();
        await db.setKv('splitsV2', '1');
      }
    } catch (e) {
      debugPrint('MATCHUP LOAD ERROR: $e');
    }
    matchupsReady = true;
    notifyListeners();
  }

  /// 打者の詳しい成績（コース・打球方向・球種・球速）を、保存してある今季の1球ごとの記録から作る（一度だけ）。
  ///  1球ごとの記録が全試合そろうのは自球団の試合だけなので、自球団の選手だけ（他球団の選手はこれからの試合から数える）
  void _backfillSplits(List<PitchRow> rows) {
    final my = teams.where((t) => t.id == myTeamId).firstOrNull;
    if (my == null || seasonFinished) return;
    final mine = {for (final p in my.players) p.id: p};
    for (final p in mine.values) {
      p.seasonStats.spl.clear();
    }
    final last = <String, PitchRow>{};
    for (final r in rows) {
      if (r.matchIdx < 0 || r.matchIdx >= matches.length || !_officialTypes.contains(matches[r.matchIdx].matchType)) continue;
      final k = '${r.matchIdx}|${r.battingHome}|${r.paIndex}';
      final l = last[k];
      if (l == null || r.pitchNo >= l.pitchNo) last[k] = r;
    }
    final resolvers = <int, String? Function(bool, String)>{};
    var n = 0;
    for (final r in last.values) {
      final res = paResult(PitchRec(paIndex: r.paIndex, pitchNo: r.pitchNo, battingHome: r.battingHome, batter: r.batter, pitcher: r.pitcher, result: r.result, outcome: r.outcome, balls: r.balls, strikes: r.strikes));
      if (res == null) continue;
      final resolve = resolvers.putIfAbsent(r.matchIdx, () => _idResolver(matches[r.matchIdx]));
      final p = mine[resolve(r.battingHome, r.batter)];
      if (p != null) {
        BattingSplits.add(p.seasonStats, res, x: r.x, z: r.z, bats: r.batterHand, pitchName: r.pitchName, speed: r.speed, landX: r.landX, landY: r.landY);
        n++;
      }
      final pp = mine[resolve(!r.battingHome, r.pitcher)];
      if (pp != null) BattingSplits.add(pp.seasonStats, res, x: r.x, z: r.z, bats: r.batterHand, pitchName: r.pitchName, speed: r.speed, landX: r.landX, landY: r.landY, prefix: 'p');
    }
    debugPrint('SPLITS BACKFILL: $n');
  }

  /// 試合中の1球ごとの記録を PitchRec に
  static List<PitchRec> pitchRecs(Iterable<PitchEvent> evs) => [
        for (final e in evs) PitchRec(paIndex: e.paIndex, pitchNo: e.pitchNo, battingHome: e.battingHome, batter: e.batter, pitcher: e.pitcher, result: e.result, outcome: e.outcome, balls: e.balls, strikes: e.strikes),
      ];

  void _collectPitches(Match m, MatchResult result) {
    final s = result.session;
    if (s == null) return;
    if (!recordAllPitches && m.homeTeamId != myTeamId && m.awayTeamId != myTeamId) return;
    if (m.matchType == 'OPEN') return; // オープン戦はヒートマップ・対戦成績に数えない
    final idx = matches.indexOf(m);
    if (idx < 0) return;
    _addMatchupGame(idx, pitchRecs(s.pitchEvents));
    var seq = 0;
    for (final e in s.pitchEvents) {
      _pendingPitches.add(PitchRowsCompanion.insert(
        season: startYear, matchIdx: idx, seq: seq++, paIndex: e.paIndex, pitchNo: e.pitchNo, battingHome: e.battingHome,
        batter: e.batter, batterHand: e.batterHand, pitcher: e.pitcher, pitchName: e.pitchName, speed: e.speed,
        x: e.x, z: e.z, inZone: e.inZone, balls: e.balls, strikes: e.strikes, result: e.result, contact: e.contact,
        landX: Value(e.landX), landY: Value(e.landY), launch: Value(e.launch), fielder: e.fielder, outcome: e.outcome,
        playCode: e.playCode, breakDX: e.breakDX, breakDY: e.breakDY,
      ));
    }
  }

  bool _matchesReplaceAll = true; // 日程を作り直したとき、シーズンの試合を全部入れ替える
  Future<void> _saveQueue = Future.value(); // 保存は順番に1つずつ行う
  final Map<String, String> _savedTeamJson = {}; // 保存済みのチームJSON（変わったチームだけ書き込む）
  final Map<String, int> _savedTeamSort = {};
  final Set<int> _savedPlayed = {}; // 結果を保存済みの試合の番号
  final Set<int> _savedFarmPlayed = {}; // 結果を保存済みの2軍の試合の番号

  Future<void> loadData() async {
    try {
      final kv = await db.allKv();
      final teamJsons = await db.loadTeamJsons();
      if (teamJsons.isNotEmpty) {
        teams = teamJsons.map((s) => Team.fromJson(jsonDecode(s) as Map<String, dynamic>, Player.fromJson)).toList();
        _applyKv(kv);
        if (kv['bodyV2'] != '1') _raiseBody(teams); // 以前のセーブ：体力・回復力・怪我しにくさの基準が変わった
        if (kv['pitchV2'] != '1') _regenPitches(teams); // 以前のセーブ：持ち球を球種カタログで作り直す
        if (kv['traitV3'] != '1') _raiseClutch(teams); // 以前のセーブ：クイック・チャンス・ピンチの平均を60に
        if (kv['velV1'] != '1') _slowVelocity(teams); // 以前のセーブ：固有12の投手の球速を下げる
        if (kv['appsV1'] != '1') _needApps = true;
        if (kv['decV2'] != '1') _needDecisions = true;
        if (kv['recV1'] != '1') _needRecords = true;
        if (kv['handV1'] != '1') _needHands = true;
        if (kv['firstsV1'] != '1') _needFirsts = true;
        if (kv['roster63'] != '1') _needTrim63 = true; // 以前のセーブ：CPU 球団の支配下を63人に（読み込みの最後に行う）
        final rows = await db.loadMatchRows(startYear);
        if (kv['compactV1'] != '1') _compactSeasonPending = startYear - 1; // 以前のセーブ：過去のシーズンの実況・1球ごとの記録を消す
        matches = [for (final r in rows.where((r) => r.idx < farmIdxBase)) Match.fromJson(jsonDecode(r.json) as Map<String, dynamic>)];
        farmMatches = [for (final r in rows.where((r) => r.idx >= farmIdxBase)) Match.fromJson(jsonDecode(r.json) as Map<String, dynamic>)];
        _savedPlayed
          ..clear()
          ..addAll([for (var i = 0; i < matches.length; i++) if (matches[i].homeScore != null) i]);
        _savedFarmPlayed
          ..clear()
          ..addAll([for (var i = 0; i < farmMatches.length; i++) if (farmMatches[i].homeScore != null) i]);
        _matchesReplaceAll = false;
        if (matches.isEmpty) {
          _generateSchedule(keepDate: true);
        } else if (farmMatches.length != matches.length) {
          _buildFarmMatches(); // 2軍の日程が無い古いセーブ
          _matchesReplaceAll = true;
        }
        if (thirdMatches.isEmpty && farmMatches.isNotEmpty) _buildThirdMatches(); // 3軍の日程が無いセーブ（今日から先を作る）
      } else if (slot != 1 || !await _migrateFromPrefs()) { // 以前の保存（端末の設定）からの移しかえは、プレイデータ1だけ
        teams = _initialTeams();
        _freshInitial = true;
        weatherSeed = Random().nextInt(1 << 30);
        _applySeasonGames();
        _generateSchedule(keepDate: true);
      }
    } catch (e, st) {
      debugPrint('LOAD ERROR: $e\n$st');
      teams = _initialTeams();
      _freshInitial = true;
      _generateSchedule(keepDate: true);
    }
    _migratePitchers();
    _migrateForeign();
    if (_needHands) {
      _assignHands([...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]);
      _needHands = false;
    }
    _fixDuplicatePlayers();
    _fixCompOfFaSigned();
    // 以前のセーブ：今季の守備イニングを、守備位置ごとの先発試合数の割合で振り分ける（守備位置ごとの記録が無いため）
    for (final p in teams.expand((t) => t.players)) {
      final st = p.seasonStats;
      if (st.defOuts <= 0 || st.posOuts.isNotEmpty) continue;
      final g = {for (final e in st.posGames.entries) if (e.key != 'DH' && e.value > 0) e.key: e.value};
      final total = g.values.fold<int>(0, (a, b) => a + b);
      if (total == 0) continue;
      var left = st.defOuts;
      final keys = g.keys.toList()..sort((a, b) => g[b]!.compareTo(g[a]!));
      for (var i = 0; i < keys.length; i++) {
        final o = i == keys.length - 1 ? left : (st.defOuts * g[keys[i]]! / total).round();
        st.posOuts[keys[i]] = o;
        left -= o;
      }
    }
    // 独立リーグの球団名を、プロ球団に見えない名前に置き換える（入団経緯・ドラフト候補の出身とメモ）
    for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
      p.draftInfo = DraftEngine.renameIndep(p.draftInfo);
    }
    for (final pr in prospects) {
      pr.school = DraftEngine.renameIndep(pr.school);
      pr.memo = [for (final m in pr.memo) DraftEngine.renameIndep(m)];
    }
    // 入団時（固有12はゲーム開始時）の能力が無い選手：固有12は初期データ（ゲーム開始時と同じ処理をしたもの）から、
    // それ以外は今年の初めの能力で代わりにする
    if (teams.any((t) => t.players.any((p) => p.baseline.isEmpty))) {
      final init = {for (final t in _initialTeams()) for (final p in t.players) p.id: p};
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
        if (p.baseline.isNotEmpty) continue;
        final i = init[p.id];
        if (i != null) {
          p.baseline = GrowthEngine.abilities(i);
          p.baselineNote = 'ゲーム開始時';
        } else if (p.yearStart.isNotEmpty) {
          p.baseline = Map.of(p.yearStart);
          p.baselineNote = '$startYear年の初め';
        } else {
          p.baseline = GrowthEngine.abilities(p);
          p.baselineNote = '記録を始めたとき';
        }
      }
    }
    if (_needDecisions) {
      _rebuildDecisions();
      _needDecisions = false;
    }
    if (_needRecords) {
      rebuildSeasonRecords(); // 以前のセーブ：記録していなかった得点圏・連続記録など、エラーを安打にしていた分
      _needRecords = false;
      _matchesReplaceAll = true;
    }
    if (_needApps) {
      _recountApps();
      _needApps = false;
    }
    if (_needTrim63 && myTeamId.isNotEmpty) {
      _trimCpuRosters();
      _needTrim63 = false;
    }
    _ensureCoaches();
    _fillStaff();
    _ensureScoutNet(onlyEmpty: true); // スカウトが1人もいない球団（あとから作った球団など）にだけ置く
    for (final t in teams) {
      for (final p in t.players) {
        CareerEngine.estimateIfMissing(p);
      }
    }
    _roundSalaries();
    Player.showOpen = openPeriod;
    // 外国人・他リーグの選手：メインポジションが G1 のままなら、得意な位置をメインに
    for (final p in [
      ...teams.expand((t) => t.players).where((p) => p.nationality == '海外'),
      ...foreignPool,
      ...freeAgents.map((f) => f.player).where((p) => p.nationality == '海外'),
      ...?otherWorld?.allPlayers,
    ]) {
      FieldingGen.fixMainPos(p);
    }
    _ensureProspects();
    _ensureManagers();
    _ensureFinance();
    _syncFacilities();
    FarmEngine.devBonus = _farmDevBonus; // 2軍の自動スタメンに、2軍監督の育成眼で「育てる価値」を足す
    // 以前のセーブの記録の修復（今季の成績がまだ選手に残っている間に）→ 以前の方式（1月1日に年度更新）のオフなら、ここで年度を切り替える
    await _repairLostSeasonRecords();
    await _fixInGameCareers();
    await _fixInitialProYears();
    // 出身：日本人には都道府県、外国人は8か国（ベネズエラ・プエルトリコ → ドミニカ、カナダ → アメリカ）
    if (await db.getKv('originV2') != '1') {
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...foreignPool, ...prospects.map((x) => x.player)]) {
        if (p.nationality == '海外') {
          p.origin = switch (p.origin) { 'ベネズエラ' || 'プエルトリコ' => 'ドミニカ', 'カナダ' => 'アメリカ', _ => p.origin };
        } else if (p.birthplace.isEmpty) {
          p.birthplace = NamePool.prefecture(Random(p.id.hashCode));
        }
      }
      await saveData();
      await db.setKv('originV2', '1');
    }
    // 国内FA を8年に（以前は6年）：すでに日本人選手の扱いになった外国人選手は、そのままにする
    if (await db.getKv('fa8V1') != '1') {
      var lost = 0;
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
        if (p.faService >= 6 && p.faService < Player.faYears) {
          if (p.nationality == '海外') {
            p.faService = Player.faYears;
          } else if (!p.ikusei) {
            lost++;
          }
        }
      }
      if (lost > 0) _addNews(['制度の変更：国内FA 権の取得は8年になりました（以前は6年）。6〜7年の選手$lost人は、8年になるまで FA 宣言できません']);
      await saveData();
      await db.setKv('fa8V1', '1');
    }
    if (await db.getKv('sacRecountV2') != '1') {
      recountSacAndGidp();
      await saveData(); // 数え直した成績をすぐ保存する
      await db.setKv('sacRecountV2', '1');
    }
    await _repairRenamedRecords();
    await _loadOther(); // 他リーグ（なければ作る）
    for (final p in otherWorld?.allPlayers ?? const <Player>[]) {
      FieldingGen.fixMainPos(p); // 以前に作った他リーグの選手：メインポジションが G1 なら得意な位置に
    }
    await _loadAmateur(); // アマチュア球界（なければ作る）
    if (await db.getKv('fieldGenV1') != '1') {
      var n = 0;
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
        if (_fieldingIfDefault(p)) n++;
      }
      debugPrint('FIELDING REGEN: $n');
      await db.setKv('fieldGenV1', '1');
      if (n > 0) await saveData();
    }
    if (await db.getKv('fieldGenV2') != '1') {
      // 守備の基準を変えた：本職の底上げ（最低E45・多くはD〜B）と、守れる位置を増やす
      final r = Random(startYear * 7 + 3);
      var n = 0;
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...prospects.map((x) => x.player)]) {
        if (FieldingGen.upgrade(p, r)) n++;
      }
      debugPrint('FIELDING UPGRADE: $n');
      await db.setKv('fieldGenV2', '1');
      if (n > 0) await saveData();
    }
    if (await db.getKv('veloV2') != '1') {
      // 球速の基準を変えた（2026-11）：NPB 1軍は150km以上、プロ入りの高校生は140km台前半。アンダースローと160km以上はそのまま
      final seen = Set<Player>.identity();
      final pros = [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...foreignPool, ...?otherWorld?.allPlayers];
      final ama = [...prospects.map((x) => x.player), ...?amWorld?.players.map((x) => x.player)];
      for (final p in pros) {
        if ((!p.isPitcher && !p.twoWay) || !seen.add(p)) continue;
        Velo.setTo(p, Velo.lift(p.velocity, amateur: p.ikusei, slot: p.armSlot));
      }
      for (final p in ama) {
        if ((!p.isPitcher && !p.twoWay) || !seen.add(p)) continue;
        Velo.setTo(p, Velo.lift(p.velocity, amateur: true, slot: p.armSlot));
      }
      debugPrint('VELO V2: ${seen.length}');
      await saveData();
      await _saveAmateur();
      await _saveOther();
      await db.setKv('veloV2', '1');
    }
    if (await db.getKv('eyeV1') != '1') {
      // 選球眼の平均を60に（チャンス・ピンチと同じ基準）：NPB 12球団の野手の平均との差を、全員に足す
      final bats = [for (final t in leagueTeams) for (final p in t.players) if (!p.isPitcher) p];
      final mean = bats.isEmpty ? 60.0 : bats.fold<int>(0, (s, p) => s + p.eye) / bats.length;
      final d = (60 - mean).round();
      if (d > 0) {
        final seen = Set<Player>.identity();
        for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...foreignPool, ...?otherWorld?.allPlayers, ...prospects.map((x) => x.player), ...?amWorld?.players.map((x) => x.player)]) {
          if (p.isPitcher || !seen.add(p)) continue;
          p.eye = (p.eye + d).clamp(1, 99);
        }
        debugPrint('EYE V1: +$d (${seen.length})');
        await saveData();
        await _saveAmateur();
        await _saveOther();
      }
      await db.setKv('eyeV1', '1');
    }
    if (await db.getKv('fieldGenV3') != '1') {
      // 守備の技術（捕球・送球・肩力）の高い選手・守備職人型は、本職の守備適性もある程度高く
      final seen = Set<Player>.identity();
      var n = 0;
      for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player), ...foreignPool, ...?otherWorld?.allPlayers, ...prospects.map((x) => x.player), ...?amWorld?.players.map((x) => x.player)]) {
        if (p.isPitcher || !seen.add(p)) continue;
        if (FieldingGen.blendSkill(p, craftsman: CoachEngine.autoType(p) == '守備職人型')) n++;
      }
      debugPrint('FIELDING V3: $n');
      await saveData();
      await _saveAmateur();
      await _saveOther();
      await db.setKv('fieldGenV3', '1');
    }
    if (await db.getKv('scoutNetV1') != '1') {
      _ensureScoutNet(); // 地区担当・海外担当のスカウト（以前の「スカウト」は本拠地の地区担当に）
      await db.setKv('scoutNetV1', '1');
      await saveData();
    }
    if (seasonFinished && currentDate.year == startYear) {
      _rollover();
      _addNews(['年度の切り替えを「全日程の終了時」に変えたため、${startYear}年度に切り替えました（年齢・プロ年数＋1、今季の成績は通算へ）']);
    }
    if (_needFirsts) {
      _initFirsts();
      _needFirsts = false;
    }
    // 以前のセーブの修復：シーズン中やオフ宣言前の古いFAケースを破棄、または宣言日を過ぎていれば宣言
    if (!offAfterSeason && !seasonFinished) {
      faCases = [];
    } else if (offAfterSeason) {
      final declareDay = faDeclareDate(currentDate.year);
      if (currentDate.isBefore(declareDay)) {
        faCases = [];
      } else if (faCases.isNotEmpty && faCases.every((f) => f.result.isNotEmpty)) {
        faCases = []; // 前年の結果が残っている
      }
      ensureFaDeclaredIfNeeded();
    }
    _snapRosters(); // ここからの入団・退団を記録する
    if (newsLog.isEmpty && news.isNotEmpty) newsLog[currentDate.year] = List.of(news); // 以前のお知らせを、記録の始まりに
    loaded = true;
    notifyListeners();
    loadMatchups();
    _fixCareerEstimates();
    AiWriter.instance.load();
  }

  void _applyKv(Map<String, String> kv) {
    _applyChronKv(kv);
    if (kv['startYear'] != null) startYear = int.tryParse(kv['startYear']!) ?? startYear;
    _careerV2 = kv['careerV3'] == '1'; // 推定に守備の記録を足した版（v3）で作り直す
    if (kv['currentDate'] != null) currentDate = DateTime.parse(kv['currentDate']!);
    gameMode = kv['gameMode'] ?? 'auto';
    myTeamId = kv['myTeamId'] ?? '';
    recordAllPitches = kv['recordAllPitches'] == '1';
    try {
      monthlyMvps = [for (final e in (jsonDecode(kv['monthlyMvps'] ?? '[]') as List)) Map<String, dynamic>.from(e as Map)];
      monthSnap = {for (final e in (jsonDecode(kv['monthSnap'] ?? '{}') as Map).entries) e.key as String: List<int>.from(e.value as List)};
      retirees = [for (final e in (jsonDecode(kv['retirees'] ?? '[]') as List)) Map<String, dynamic>.from(e as Map)];
      draftBook = {for (final e in (jsonDecode(kv['draftBook'] ?? '{}') as Map).entries) int.parse(e.key as String): [for (final x in e.value as List) Map<String, dynamic>.from(x as Map)]};
      if (draftBook.isEmpty) _backfillDraftBook();
      myCareer = [for (final e in (jsonDecode(kv['myCareer'] ?? '[]') as List)) Map<String, dynamic>.from(e as Map)];
    } catch (_) {}
    seasonFinished = kv['seasonFinished'] == '1';
    offAfterSeason = kv['offAfter'] == '1';
    coaches = kv['coaches'] != null ? [for (final j in jsonDecode(kv['coaches']!) as List) Coach.fromJson(j as Map<String, dynamic>)] : [];
    postseason = kv['postseason'] != null ? [for (final j in jsonDecode(kv['postseason']!) as List) Series.fromJson(j as Map<String, dynamic>)] : [];
    news = kv['news'] != null ? List<String>.from(jsonDecode(kv['news']!) as List) : [];
    _applyMoveKv(kv);
  }

  /// ドラフト・移籍のデータを読む（kv にもバックアップにも同じ形で入れる）
  void _applyMoveKv(Map<String, dynamic> kv) {
    dynamic j(String k) {
      final v = kv[k];
      if (v == null) return null;
      return v is String ? jsonDecode(v) : v;
    }
    prospects = [for (final e in (j('prospects') as List? ?? [])) Prospect.fromJson(Map<String, dynamic>.from(e as Map))];
    draftDoneYear = int.tryParse('${kv['draftDoneYear'] ?? 0}') ?? 0;
    activeDraftYear = int.tryParse('${kv['activeDraftYear'] ?? 0}') ?? 0;
    prepDraftYear = int.tryParse('${kv['prepDraftYear'] ?? 0}') ?? 0;
    scoutLog = List<String>.from(j('scoutLog') as List? ?? []);
    tradeTips = [for (final e in (j('tradeTips') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    freeAgents = [for (final e in (j('freeAgents') as List? ?? [])) FreeAgent.fromJson(Map<String, dynamic>.from(e as Map))];
    faCases = [for (final e in (j('faCases') as List? ?? [])) FaCase.fromJson(Map<String, dynamic>.from(e as Map))];
    foreignPool = [for (final e in (j('foreignPool') as List? ?? [])) Player.fromJson(Map<String, dynamic>.from(e as Map))];
    foreignWatch = Set<String>.from(j('foreignWatch') as List? ?? const []);
    final rn = j('renewals') as Map?;
    renewSigned = Set<String>.from(rn?['s'] ?? const []);
    renewTries = {for (final e in ((rn?['t'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()};
    pendingComp = [for (final e in (j('pendingComp') as List? ?? [])) CompCase.fromJson(Map<String, dynamic>.from(e as Map))];
    compPicks = {for (final e in ((j('compPicks') as Map?) ?? {}).entries) '${e.key}': [for (final v in e.value as List) (v as num).toInt()]};
    pickOwner = Map<String, String>.from((j('pickOwner') as Map?) ?? {});
    teamPolicy = Map<String, String>.from((j('teamPolicy') as Map?) ?? {});
    lastTradeWith = Map<String, String>.from((j('lastTradeWith') as Map?) ?? {});
    postingAsk = Map<String, String>.from((j('postingAsk') as Map?) ?? {});
    partnerSlots = [for (final e in (j('partnerSlots') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    partnerStay = List<String>.from(j('partnerStay') as List? ?? []);
    tenders = [for (final e in (j('tenders') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    ledger = [for (final e in (j('ledger') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    transactions = List<String>.from(j('transactions') as List? ?? []);
    finances = {for (final e in ((j('finance') as Map?) ?? {}).entries) e.key as String: TeamFinance.fromJson(Map<String, dynamic>.from(e.value as Map))};
    for (final f in finances.values) {
      f.capacity = FinanceEngine.capacity; // ver1.0 は12球団とも同じ球場（以前のセーブも合わせる）
    }
    sponsorOffers = [for (final e in (j('sponsorOffers') as List? ?? [])) Sponsor.fromJson(Map<String, dynamic>.from(e as Map))];
    consultants = [for (final e in (j('consultants') as List? ?? [])) Consultant.fromJson(Map<String, dynamic>.from(e as Map))];
    ownerFiring = '${kv['ownerFiring'] ?? '1'}' != '0' && kv['ownerFiring'] != false;
    fired = '${kv['fired'] ?? '0'}' == '1' || kv['fired'] == true;
    firedOffers = List<String>.from(j('firedOffers') as List? ?? []);
    // 試合数（以前のセーブは 156 試合の日程なので 156）・天気の種（なければ作る）
    seasonGames = int.tryParse('${kv['seasonGames'] ?? ''}') ?? 156;
    LeagueRules.load(j('leagueRules') as Map<String, dynamic>?);
    weatherSeed = int.tryParse('${kv['weatherSeed'] ?? ''}') ?? Random().nextInt(1 << 30);
    rainoutCount = int.tryParse('${kv['rainouts'] ?? ''}') ?? 0;
    campProposals = [for (final e in (j('campProposals') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    makerCollabs = [for (final e in (j('makerCollabs') as List? ?? [])) Map<String, dynamic>.from(e as Map)];
    _applySeasonGames();
    ronin = kv['ronin'] == '1';
    roninReturn = kv['roninReturn'] == '1';
    if (ronin) autoMode = true; // 浪人中はドラフト・補償なども自動で進む
    lastRankOf = Map<String, int>.from((j('lastRank') as Map?) ?? {});
    thirdMatches = [for (final e in (j('thirdMatches') as List? ?? [])) Match.fromJson(Map<String, dynamic>.from(e as Map))];
  }

  Map<String, String> _moveKv() => {
        'prospects': jsonEncode(prospects.map((p) => p.toJson()).toList()),
        'draftDoneYear': '$draftDoneYear',
        'activeDraftYear': '$activeDraftYear',
        'prepDraftYear': '$prepDraftYear',
        'scoutLog': jsonEncode(scoutLog),
        'tradeTips': jsonEncode(tradeTips),
        'freeAgents': jsonEncode(freeAgents.map((f) => f.toJson()).toList()),
        'faCases': jsonEncode(faCases.map((f) => f.toJson()).toList()),
        'foreignPool': jsonEncode(foreignPool.map((p) => p.toJson()).toList()),
        'foreignWatch': jsonEncode(foreignWatch.toList()),
        'renewals': jsonEncode({'s': renewSigned.toList(), 't': renewTries}),
        'pendingComp': jsonEncode(pendingComp.map((c) => c.toJson()).toList()),
        'compPicks': jsonEncode(compPicks),
        'pickOwner': jsonEncode(pickOwner),
        'teamPolicy': jsonEncode(teamPolicy),
        'lastTradeWith': jsonEncode(lastTradeWith),
        'postingAsk': jsonEncode(postingAsk),
        'partnerSlots': jsonEncode(partnerSlots),
        'partnerStay': jsonEncode(partnerStay),
        'tenders': jsonEncode(tenders),
        'ledger': jsonEncode(ledger),
        'transactions': jsonEncode(transactions),
        'finance': jsonEncode({for (final e in finances.entries) e.key: e.value.toJson()}),
        'sponsorOffers': jsonEncode(sponsorOffers.map((s) => s.toJson()).toList()),
        'consultants': jsonEncode(consultants.map((c) => c.toJson()).toList()),
        'ownerFiring': ownerFiring ? '1' : '0',
        'fired': fired ? '1' : '0',
        'ronin': ronin ? '1' : '0',
        'roninReturn': roninReturn ? '1' : '0',
        'firedOffers': jsonEncode(firedOffers),
        'lastRank': jsonEncode(lastRankOf),
        'thirdMatches': jsonEncode(thirdMatches.map((m) => m.toJson()).toList()),
        'seasonGames': '$seasonGames',
        'leagueRules': jsonEncode(LeagueRules.toJson()),
        'weatherSeed': '$weatherSeed',
        'rainouts': '$rainoutCount',
        'campProposals': jsonEncode(campProposals),
        'makerCollabs': jsonEncode(makerCollabs),
      };
  final Map<String, String> _savedKv = {}; // 保存済みの kv（変わったものだけ書き込む）

  /// 以前の保存方式（SharedPreferences）のデータがあれば、DBへ移す。移せたら true
  Future<bool> _migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final teamsJson = prefs.getString('teamsData');
    if (teamsJson == null) return false;
    try {
      teams = (jsonDecode(teamsJson) as List).map((t) => Team.fromJson(t, Player.fromJson)).toList();
      _raiseBody(teams);
      if (prefs.getString('currentDate') != null) currentDate = DateTime.parse(prefs.getString('currentDate')!);
      gameMode = prefs.getString('gameMode') ?? 'auto';
      news = prefs.getStringList('news') ?? [];
      myTeamId = prefs.getString('myTeamId') ?? '';
      if (prefs.getString('matchesData') != null) {
        matches = (jsonDecode(prefs.getString('matchesData')!) as List).map((m) => Match.fromJson(m)).toList();
      } else {
        _generateSchedule(keepDate: true);
      }
      _buildFarmMatches();
      _matchesReplaceAll = true;
      await saveData();
      for (final k in ['teamsData', 'currentDate', 'gameMode', 'news', 'myTeamId', 'matchesData']) {
        await prefs.remove(k);
      }
      return true;
    } catch (e) {
      debugPrint('MIGRATE ERROR: $e');
      return false;
    }
  }

  /// はじめからにしたあとの最初の保存で、DB のこれまでの記録を消す
  bool _wipeHistory = false;

  Future<void> saveData() async {
    _writeSlotSummary();
    if (_wipeHistory) {
      _wipeHistory = false;
      await db.wipeHistory();
      _matchesReplaceAll = true; // 試合は今の日程で書き直す
    }
    _roundSalaries(); // 年俸は50万円単位
    await _maybeSaveOther(); // 他リーグは30日ごと・シーズンの区切りに
    await _maybeSaveAmateur(); // アマチュア球界は7日ごと・年度の区切りに
    if (loaded) _diffRosters(); // 入団・退団・コーチの就任と退任を記録する
    // 画面の状態をこの時点で固めてから、順に書き込む（連続して呼ばれても混ざらない）
    final changedTeams = <TeamRowsCompanion>[];
    for (var i = 0; i < teams.length; i++) {
      final js = jsonEncode(teams[i].toJson());
      if (_savedTeamJson[teams[i].id] != js || _savedTeamSort[teams[i].id] != i) {
        changedTeams.add(TeamRowsCompanion.insert(id: teams[i].id, sort: i, json: js));
        _savedTeamJson[teams[i].id] = js;
        _savedTeamSort[teams[i].id] = i;
      }
    }
    final teamIds = [for (final t in teams) t.id];
    _savedTeamJson.removeWhere((k, _) => !teamIds.contains(k));
    final season = startYear;
    final kv = <String, String>{
      'startYear': '$startYear',
      'currentDate': currentDate.toIso8601String(),
      'gameMode': gameMode,
      'recordAllPitches': recordAllPitches ? '1' : '0',
      'seasonFinished': seasonFinished ? '1' : '0',
      'offAfter': offAfterSeason ? '1' : '0',
      'postseason': jsonEncode(postseason.map((s) => s.toJson()).toList()),
      'coaches': jsonEncode(coaches.map((c) => c.toJson()).toList()),
      'myTeamId': myTeamId,
      'news': jsonEncode(news),
      'monthlyMvps': jsonEncode(monthlyMvps),
      'monthSnap': jsonEncode(monthSnap),
      'retirees': jsonEncode(retirees),
      'draftBook': jsonEncode({for (final e in draftBook.entries) '${e.key}': e.value}),
      'myCareer': jsonEncode(myCareer),
      'bodyV2': '1',
      'pitchV2': '1',
      'traitV3': '1',
      'velV1': '1',
      'roster63': '1',
      'appsV1': '1',
      'decV2': '1',
      'recV1': '1',
      'careerV3': _careerV2 ? '1' : '0',
      'handV1': '1',
      'compactV1': '1',
      'firstsV1': '1',
      'chronFirst': '$chronFirstYear',
      'openingNumbers': openingNumberDay,
      for (final y in [startYear - 1, startYear]) if (chronYears[y] != null) 'chron_$y': jsonEncode(chronYears[y]),
      for (final e in newsLog.entries) if (e.key >= currentDate.year - 2) 'news_${e.key}': jsonEncode(e.value),
      ..._moveKv(),
    };
    kv.removeWhere((k, v) => _savedKv[k] == v);
    _savedKv.addAll(kv);
    final pitchRows = _pendingPitches;
    _pendingPitches = [];
    final compact = _compactSeasonPending;
    _compactSeasonPending = null;
    final replaceAll = _matchesReplaceAll;
    _matchesReplaceAll = false;
    final allJson = <int, String>{};
    final allPlayed = <int, bool>{};
    final newJson = <int, String>{};
    final newPlayed = <int, bool>{};
    if (replaceAll) {
      for (var i = 0; i < matches.length; i++) {
        allJson[i] = jsonEncode(matches[i].toJson());
        allPlayed[i] = matches[i].homeScore != null;
      }
      for (var i = 0; i < farmMatches.length; i++) {
        allJson[farmIdxBase + i] = jsonEncode(farmMatches[i].toJson());
        allPlayed[farmIdxBase + i] = farmMatches[i].homeScore != null;
      }
      _savedPlayed
        ..clear()
        ..addAll([for (var i = 0; i < matches.length; i++) if (matches[i].homeScore != null) i]);
      _savedFarmPlayed
        ..clear()
        ..addAll([for (var i = 0; i < farmMatches.length; i++) if (farmMatches[i].homeScore != null) i]);
    } else {
      for (var i = 0; i < matches.length; i++) {
        if (matches[i].homeScore != null && !_savedPlayed.contains(i)) {
          newJson[i] = jsonEncode(matches[i].toJson());
          newPlayed[i] = true;
          _savedPlayed.add(i);
        }
      }
      for (var i = 0; i < farmMatches.length; i++) {
        if (farmMatches[i].homeScore != null && !_savedFarmPlayed.contains(i)) {
          newJson[farmIdxBase + i] = jsonEncode(farmMatches[i].toJson());
          newPlayed[farmIdxBase + i] = true;
          _savedFarmPlayed.add(i);
        }
      }
    }
    Future<void> write() async {
    try {
      await db.syncTeams(changedTeams, teamIds);
      for (final e in kv.entries) {
        await db.setKv(e.key, e.value);
      }
      if (pitchRows.isNotEmpty) await db.savePitches(pitchRows);
      if (compact != null) await db.compactSeason(compact);
      if (replaceAll) {
        await db.replaceMatches(season, allJson, allPlayed);
      } else if (newJson.isNotEmpty) {
        await db.upsertMatches(season, newJson, newPlayed);
      }
    } catch (e, st) {
      debugPrint('SAVE ERROR: $e\n$st');
      _pendingPitches.insertAll(0, pitchRows);
      _savedTeamJson.clear(); // 失敗したら、次は全部書き直す
      _savedKv.clear();
      _matchesReplaceAll = true; // 失敗したら、次は全部書き直す
    }
    }
    return _saveQueue = _saveQueue.then((_) => write());
  }

  // ===== バックアップ（セーブデータをファイルで書き出し・読み込み） =====
  static const _backupFormat = 'npb_pennant_save';

  /// 今のセーブ（チーム・日程・設定）を1つのJSON文字列にする
  String exportSaveJson() => jsonEncode({
        'format': _backupFormat,
        'version': 1,
        'startYear': startYear,
        'currentDate': currentDate.toIso8601String(),
        'gameMode': gameMode,
        'myTeamId': myTeamId,
        'news': news,
        'seasonFinished': seasonFinished,
        'offAfter': offAfterSeason,
        'postseason': postseason.map((s) => s.toJson()).toList(),
        'coaches': coaches.map((c) => c.toJson()).toList(),
        'teams': teams.map((t) => t.toJson()).toList(),
        'matches': matches.map((m) => m.toJson()).toList(),
        'farmMatches': farmMatches.map((m) => m.toJson()).toList(),
        ..._moveKv(),
      });

  /// バックアップを読み込んで置き換える。読めなければ false（今のデータは変えない）
  Future<bool> importSaveJson(String text) async {
    try {
      final d = jsonDecode(text) as Map<String, dynamic>;
      if (d['format'] != _backupFormat) return false;
      final newTeams = (d['teams'] as List).map((t) => Team.fromJson(t, Player.fromJson)).toList();
      final newMatches = (d['matches'] as List).map((m) => Match.fromJson(m)).toList();
      teams = newTeams;
      matches = newMatches;
      farmMatches = [for (final m in (d['farmMatches'] as List? ?? [])) Match.fromJson(m)];
      seasonFinished = d['seasonFinished'] as bool? ?? false;
      offAfterSeason = d['offAfter'] as bool? ?? false;
      postseason = [for (final j in (d['postseason'] as List? ?? [])) Series.fromJson(j as Map<String, dynamic>)];
      coaches = [for (final j in (d['coaches'] as List? ?? [])) Coach.fromJson(j as Map<String, dynamic>)];
      _applyMoveKv(d);
      _ensureCoaches();
      _fillStaff();
      for (final t in teams) {
        for (final p in t.players) {
          CareerEngine.estimateIfMissing(p);
        }
      }
      if (farmMatches.length != matches.length) _buildFarmMatches();
      startYear = d['startYear'] as int;
      currentDate = DateTime.parse(d['currentDate'] as String);
      gameMode = d['gameMode'] as String? ?? 'auto';
      myTeamId = d['myTeamId'] as String? ?? '';
      news = List<String>.from(d['news'] as List? ?? []);
      _migratePitchers();
      _roundSalaries();
      _ensureProspects();
      _ensureManagers();
      _ensureFinance();
      _syncFacilities();
      _matchesReplaceAll = true;
      notifyListeners();
      await saveData();
      return true;
    } catch (e) {
      debugPrint('IMPORT ERROR: $e');
      return false;
    }
  }

  /// 日程を作る。keepDate=true のときは今の日付を動かさない（ドラフトの日から始めるため）
  void _generateSchedule({bool keepDate = false}) {
    _matchesReplaceAll = true;
    matches = ScheduleGenerator.generateSeasonSchedule(startYear, teams, games: seasonGames);
    rainoutCount = 0;
    _buildFarmMatches();
    if (keepDate) return;
    var upcoming = matches.where((m) => m.date.isAfter(currentDate)).toList();
    if (upcoming.isNotEmpty) {
      upcoming.sort((a, b) => a.date.compareTo(b.date));
      currentDate = upcoming.first.date;
    } else {
      // Fallback if no schedule generated
      currentDate = DateTime(startYear, 3, 1);
    }
  }

  /// 2軍の日程：1軍と同じ日・同じ対戦チーム・同じホーム/ビジター（本来は3つのリーグに分かれるが、簡易化のため）
  void _buildFarmMatches() {
    farmMatches = [for (final m in matches) Match(homeTeamId: m.homeTeamId, awayTeamId: m.awayTeamId, date: m.date, matchType: m.matchType)];
    _buildThirdMatches();
    _savedFarmPlayed.clear();
  }

  // ===== 試合進行モード =====
  // 'auto'=自動試合 / 'simple'=簡易采配（継投・代打・守備交代） / 'manage'=采配（作戦も指示）
  String gameMode = 'auto';

  // ===== 試合数・天候（改修1）=====
  int seasonGames = 143; // 公式戦の試合数（120・143・156）。変えると次に作る日程から
  int weatherSeed = 0; // このセーブの天気の種
  int rainoutCount = 0; // 今季の雨天中止の数
  List<Map<String, dynamic>> campProposals = []; // キャンプでのコーチの提案（改修3）
  List<Map<String, dynamic>> makerCollabs = []; // 企画できるメーカーのコラボグッズ

  Future<void> setGameMode(String mode) async {
    gameMode = mode;
    notifyListeners();
    await saveData();
  }

  /// 今日の自チームの未消化試合（なければ null）
  Match? myMatchToday() {
    refreshAllBenches();
    // ダブルヘッダーの日は第1試合から
    final today = [for (final m in matches) if (DateUtils.isSameDay(m.date, currentDate) && !m.done && (m.homeTeamId == myTeamId || m.awayTeamId == myTeamId)) m]..sort((a, b) => a.dh.compareTo(b.dh));
    return today.firstOrNull;
  }

  /// 今日の自チーム以外の試合を自動で消化する
  void playOtherMatchesToday() {
    _ensureManagers();
    refreshAllBenches();
    final simulator = MatchSimulator();
    for (var m in matches.where((m) => DateUtils.isSameDay(m.date, currentDate)).toList()..sort((a, b) => a.dh.compareTo(b.dh))) {
      if (m.done) continue;
      if (m.homeTeamId == myTeamId || m.awayTeamId == myTeamId) continue;
      _simulateAndApply(simulator, m);
    }
    _playFarmToday();
  }

  /// 今日の2軍の試合を、まだ終わっていないものすべて計算する（1軍と同じ日程・同じ対戦チームの2軍）
  void _playFarmToday() {
    final sim = MatchSimulator();
    final appeared = <String, Set<String>>{}; // 今日の2軍の試合に出た選手（3軍戦のオーダーから外す）
    var anyFarm = false;
    for (var i = 0; i < farmMatches.length; i++) {
      final fm = farmMatches[i];
      if (isSpecialType(fm.matchType) || fm.homeScore != null) continue; // 2軍にポストシーズン・球宴はない
      if (!DateUtils.isSameDay(fm.date, currentDate)) continue;
      final h = teams.where((t) => t.id == fm.homeTeamId).toList();
      final a = teams.where((t) => t.id == fm.awayTeamId).toList();
      if (h.isEmpty || a.isEmpty) continue;
      try {
        final r = FarmEngine.play(sim, fm, h.first, a.first);
        if (r != null) {
          _applyFarmResult(fm, r, h.first, a.first);
          anyFarm = true;
          final ss = r.session;
          if (ss != null) {
            appeared.putIfAbsent(h.first.id, () => {}).addAll([...ss.homeAppeared, ...ss.homePitchers].map((x) => x.id));
            appeared.putIfAbsent(a.first.id, () => {}).addAll([...ss.awayAppeared, ...ss.awayPitchers].map((x) => x.id));
          }
        } else {
          debugPrint('FARM SKIP ${fm.date} ${FarmEngine.shortage(h.first)} / ${FarmEngine.shortage(a.first)}');
        }
      } catch (e, st) {
        debugPrint('FARM ERROR: $e\n$st');
      }
    }
    if (anyFarm) _playThirdTeam(appeared); // 2軍の試合がある日は3軍戦も行う
  }

  /// 2軍の試合結果を反映する。1球ごとの記録や実況は残さない（試合結果と個人成績だけ）
  void _applyFarmResult(Match fm, MatchResult result, Team home, Team away) {
    fm.boxScore = result.boxScore;
    fm.homeScore = result.homeScore;
    fm.awayScore = result.awayScore;
    fm.homeInningScores = result.homeInningScores;
    fm.awayInningScores = result.awayInningScores;
    fm.homeHits = result.homeHits;
    fm.awayHits = result.awayHits;
    fm.playByPlay = null;
    fm.pitchByPitch = null;
    fm.isPlayed = true;
    home.farmRotationIndex = (home.farmRotationIndex + 1) % home.farmRotationCount;
    away.farmRotationIndex = (away.farmRotationIndex + 1) % away.farmRotationCount;
    if (result.session != null) {
      _awardGameExp(result.session!, 0.5); // 2軍の試合の経験値（1軍の半分）
      final items = ConditionEngine.applyPostGame(result.session!, myTeam: myTeamId);
      final mine = teams.where((t) => t.id == myTeamId).map((t) => '${t.name}(2軍)').toList();
      _addNews(items.where((e) => mine.any((n) => e.contains(n))).toList());
    }
  }

  /// 対話式で進めた自チームの試合結果を反映して、1日進める
  void completeMyMatch(Match m, MatchResult result) {
    if (_liveOpen != null) _keepOpenStats(_liveOpen!); // オープン戦の成績として残す
    _liveOpen = null;
    if (_liveSnap != null) {
      _restoreStats(_liveSnap!); // ポストシーズン・オープン戦の成績は今季成績に入れない
      _liveSnap = null;
    }
    _applyResult(m, result);
    _progressPostseason();
    // ダブルヘッダーの第1試合なら、日付は進めずに第2試合へ（休みなし・疲れはそのまま）
    if (myMatchToday() == null) _advanceTo(currentDate.add(const Duration(days: 1)));
    updateAndSave();
  }

  void _simulateAndApply(MatchSimulator simulator, Match m) {
    if (m.matchType == 'ALLSTAR') {
      _playAllStar(simulator, m);
      return;
    }
    Team hTeam = teams.firstWhere((t) => t.id == m.homeTeamId);
    Team aTeam = teams.firstWhere((t) => t.id == m.awayTeamId);
    final snap = _noStats(m.matchType) ? _snapStats([hTeam, aTeam]) : null;
    final open = m.matchType == 'OPEN';
    if (open) _useOpenStats([hTeam, aTeam]);
    MatchResult result;
    try {
      result = simulator.simulateMatch(m, hTeam, aTeam);
    } catch (e, st) {
      debugPrint('SIMULATION ERROR: $e\n$st');
      if (snap != null) _restoreStats(snap);
      return;
    }
    if (open) _keepOpenStats([hTeam, aTeam]);
    if (snap != null) _restoreStats(snap); // ポストシーズン・オープン戦の成績は今季成績に入れない（オープン戦はオープン戦の成績へ）
    _applyResult(m, result);
  }

  /// お知らせ（怪我・登録抹消など）。新しいものが先頭
  List<String> news = [];

  void _addNews(List<String> items) {
    if (items.isEmpty) return;
    items = _withRealNames(items);
    _logNews(items);
    final d = '${currentDate.month}/${currentDate.day}';
    news.insertAll(0, items.map((e) => '$d $e'));
    if (news.length > 50) news = news.sublist(0, 50);
  }

  /// オリジナルの名前の選手は、お知らせで本名を（）に添える：「小川 力也（林田力也）が…」
  List<String> _withRealNames(List<String> items) {
    final orig = [for (final t in teams) for (final p in t.players) if (p.hasOriginalName) p]
      ..sort((a, b) => b.registeredName.length.compareTo(a.registeredName.length));
    if (orig.isEmpty) return items;
    return [
      for (var e in items)
        () {
          for (final p in orig) {
            final n = p.registeredName, i = e.indexOf(n);
            if (i < 0 || e.startsWith('（', i + n.length)) continue;
            e = '${e.substring(0, i + n.length)}（${p.realName}）${e.substring(i + n.length)}';
          }
          return e;
        }(),
    ];
  }

  /// 日付を進める（その日数ぶん体力が回復し、怪我の残り日数が減る）
  void _advanceTo(DateTime d) {
    final from = DateUtils.dateOnly(currentDate), to = DateUtils.dateOnly(d);
    final days = to.difference(from).inDays;
    if (to.year > from.year) {
      for (final p in teams.expand((t) => t.players)) {
        p.openStats = PlayerStats(); // 新しい年のオープン戦は0から
      }
    }
    ConditionEngine.advanceDays(teams, days);
    _staffCache.clear();
    _thirdCache.clear();
    _ikuseiCountCache.clear();
    _campEvents(from, to); // キャンプの開始・終了（人選と費用）
    GrowthEngine.advanceDays(teams, from, to, coach: _expMult, campMult: _campMult, devEye: (t, ik) => ik ? thirdDevEye(t) : farmDevEye(t));
    _dailyEvents(from, to);
    _otherAdvance(to); // 他リーグの毎日の試合（今日の前日まで）
    _amateurAdvance(to); // アマチュア球界（4月の年度の切り替え）
    currentDate = d;
    Player.showOpen = openPeriod; // 開幕前はオープン戦の成績を出す
    if (days > 0) _rainoutsOn(d);
    if (d.year > startYear) _startNewYear(); // 以前の方式：シーズンを締めずに年を越えた（1月1日の処理は毎日の行事の中）
  }

  /// 次に止まる日：次の試合、または日付の節目（10/31 ドラフト会議・1/1 年度更新）の早いほう
  DateTime _nextStop() {
    final d0 = DateUtils.dateOnly(currentDate);
    DateTime? best;
    for (final m in matches) {
      if (m.date.isAfter(d0) && (best == null || m.date.isBefore(best))) best = m.date;
    }
    // 試合のない期間（ドラフト明け〜開幕）は毎週月曜日に止まる（補強・練習の見直しのため）
    final monday = d0.add(Duration(days: (DateTime.monday - d0.weekday + 7) % 7 == 0 ? 7 : (DateTime.monday - d0.weekday + 7) % 7));
    for (final c in [DateTime(d0.year, 10, 31), DateTime(d0.year + 1, 1, 1), if (offAfterSeason) ..._offseasonStops(d0), if (_offPeriod(d0)) monday]) {
      if (c.isAfter(d0) && (best == null || c.isBefore(best))) best = c;
    }
    return best ?? d0.add(const Duration(days: 1));
  }

  /// 試合のない期間か（ドラフト会議の後〜その年の最初の試合の前）
  bool _offPeriod(DateTime d0) {
    if (matches.isEmpty) return true;
    final first = matches.map((m) => m.date).reduce((a, b) => a.isBefore(b) ? a : b);
    if (d0.isBefore(first)) return true; // 開幕（オープン戦）の前：年明けのキャンプなど
    return seasonFinished && draftDoneYear >= d0.year; // シーズンが終わり、ドラフト会議も済んだ
  }

  /// 「進める」ボタンに出す、次の止まる日の名前
  String nextStopLabel() {
    final s = _nextStop();
    if (matches.any((m) => DateUtils.isSameDay(m.date, s))) return '次の試合日（${s.month}/${s.day}）';
    if (s.month == 10 && s.day == 31) return 'ドラフト会議（10/31）';
    if (s.month == 11 && s.day == faDeclareDate(s.year).day) return 'FA 宣言（11/${s.day}）';
    if (s.month == 12 && s.day == 31) return 'FA 交渉の期限（12/31）';
    if (s.weekday == DateTime.monday && _offPeriod(DateUtils.dateOnly(currentDate))) return '次の月曜（${s.month}/${s.day}）';
    if (s.month == 12 && s.day == 1) return '契約更改（12/1）';
    if (s.month == 1 && s.day == 1) return s.year > startYear ? '年度更新・春季キャンプ（1/1）' : '春季キャンプ（1/1〜1/31）';
    return '${s.month}/${s.day}';
  }

  /// 試合のない時期の名前（春季キャンプ・オフシーズン）。試合のある日や、シーズン中の移動日は null
  String? offseasonLabel() {
    final d = DateUtils.dateOnly(currentDate);
    if (matches.any((m) => DateUtils.isSameDay(m.date, d))) return null;
    if (d.month == 1) return '春季キャンプ中（1/31まで）';
    if (matches.isEmpty) return null;
    final dates = matches.map((m) => m.date).toList()..sort();
    if (d.isBefore(dates.first)) return 'オフシーズン';
    if (d.isAfter(dates.last) && seasonFinished) return 'オフシーズン';
    return null;
  }

  /// 春季キャンプ中か（1月1日〜31日）
  bool get isCamp => currentDate.month == 1;

  /// 今季の登板数・先発数を、試合のボックススコア（先発が先頭）から数え直す。1軍は成績に入る試合、2軍は2軍の試合
  void _recountApps() {
    final global = <String, Player?>{};
    for (final t in teams) {
      for (final p in t.players) {
        global[p.registeredName] = global.containsKey(p.registeredName) ? null : p;
        for (final st in [p.seasonStats, p.farmStats]) {
          st.pitchApps = 0;
          st.starts = 0;
        }
      }
    }
    void count(Match m, bool farm) {
      final box = m.boxScore;
      if (box == null || m.homeScore == null) return;
      for (final side in ['home', 'away']) {
        final tid = side == 'home' ? m.homeTeamId : m.awayTeamId;
        final team = teams.where((t) => t.id == tid).firstOrNull;
        final rows = box['${side}Pitcher'];
        if (rows is! Map) continue;
        var first = true;
        for (final name in rows.keys) {
          final p = team?.players.where((x) => x.registeredName == name).firstOrNull ?? global[name];
          if (p != null) {
            final st = farm ? p.farmStats : p.seasonStats;
            st.pitchApps++;
            if (first) st.starts++;
          }
          first = false;
        }
      }
    }
    for (final m in matches) {
      if (!_noStats(m.matchType) && m.matchType != 'ALLSTAR') count(m, false);
    }
    for (final m in farmMatches) {
      count(m, true);
    }
  }

  /// 2軍監督の育成眼（いなければ40）
  int farmDevEye(Team t) {
    final c = (_staffCache[t.id] ??= staffOf(t))['2軍監督'];
    return c == null ? 40 : CoachEngine.devEye(c);
  }

  /// 監督の見立てる成長率（才能は見抜きやすく、向上心は見抜きにくい。育成眼が低いと大きく見誤る）
  double _perceivedRate(Coach? c, String seed, Player p, int eye) {
    final r = Random((c?.id ?? seed).hashCode ^ p.id.hashCode ^ 0x3d1);
    double g() => sqrt(-2.0 * log(1.0 - r.nextDouble())) * cos(2.0 * pi * r.nextDouble());
    final miss = (100 - eye) / 100.0;
    final tal = (p.talent + g() * miss * 12).clamp(1, 100), amb = (p.ambition + g() * miss * 50).clamp(1, 100);
    return Player.rateOf(tal, amb);
  }

  /// 1軍で抜擢する価値の上乗せ（OVR の点数）：監督の育成眼で、伸び盛りの若手（25歳以下）を見抜いて使う。
  ///  勝つための1軍なので、2軍ほど大きくはしない（最大 +6）
  double firstDevBonus(Team t, Player p) {
    if (p.age > 26) return 0;
    final c = (_staffCache[t.id] ??= staffOf(t))['監督'];
    final eye = c == null ? 40 : CoachEngine.devEye(c);
    final rate = _perceivedRate(c, t.id, p, eye);
    final youth = ((27 - p.age) / 6).clamp(0.0, 1.0);
    return (eye / 100 * (rate - 1.0) * 6 * youth).clamp(-3.0, 6.0);
  }

  /// 2軍で使う価値の上乗せ（OVR の点数）：2軍監督が見立てた成長率と若さから。
  ///  才能は見抜きやすく、向上心は見抜きにくい（育成眼が低いと大きく見誤る）。育成眼が高いほど育てる価値を重く見る
  double _farmDevBonus(Team t, Player p) {
    final c = (_staffCache[t.id] ??= staffOf(t))['2軍監督'];
    final eye = c == null ? 40 : CoachEngine.devEye(c);
    final rate = _perceivedRate(c, t.id, p, eye);
    final youth = ((27 - p.age) / 8).clamp(0.0, 1.0);
    final w = 0.3 + 0.7 * eye / 100;
    return (w * ((rate - 1.0) * 25 * youth + youth * 2)).clamp(-15.0, 18.0);
  }

  /// 今季の1軍の公式戦の勝利・敗戦・セーブ・ホールド・自責点を、実況ログから今の規則で付け直す（DecisionRebuild）。
  ///  ボックススコアの判定と自責点を書き換え、前の判定との差を選手の今季成績に反映する。救援勝利は数え直す
  void _rebuildDecisions() {
    final global = <String, Player?>{};
    for (final t in teams) {
      for (final p in t.players) {
        global[p.registeredName] = global.containsKey(p.registeredName) ? null : p;
        p.seasonStats.reliefWins = 0;
      }
    }
    void bump(PlayerStats st, String dec, int d) {
      switch (dec) {
        case '勝': st.wins += d; break;
        case '敗': st.losses += d; break;
        case 'S': st.saves += d; break;
        case 'H': st.holds += d; break;
      }
    }
    var changed = 0;
    for (final m in matches) {
      if (m.homeScore == null || !_officialTypes.contains(m.matchType)) continue;
      final home = teams.where((t) => t.id == m.homeTeamId).firstOrNull, away = teams.where((t) => t.id == m.awayTeamId).firstOrNull;
      if (home == null || away == null) continue;
      final r = DecisionRebuild.run(m, home, away);
      if (r == null) continue;
      for (final side in [true, false]) {
        final rows = m.boxScore![side ? 'homePitcher' : 'awayPitcher'];
        if (rows is! Map) continue;
        final team = side ? home : away;
        for (final e in rows.entries) {
          final name = e.key as String;
          final row = e.value as Map;
          final p = team.players.where((x) => x.registeredName == name).firstOrNull ?? global[name];
          final old = (row['dec'] ?? '') as String, neu = r.dec[(side, name)] ?? '';
          final oldEr = (row['er'] ?? 0) as int, newEr = r.er[side]?[name] ?? oldEr;
          if (p != null) {
            if (old != neu) {
              bump(p.seasonStats, old, -1);
              bump(p.seasonStats, neu, 1);
            }
            p.seasonStats.earnedRuns += newEr - oldEr;
            if (r.reliefWin == (side, name)) p.seasonStats.reliefWins++;
          }
          if (old != neu) changed++;
          if (neu.isEmpty) {
            row.remove('dec');
          } else {
            row['dec'] = neu;
          }
          row['er'] = newEr;
        }
      }
    }
    _matchesReplaceAll = true; // 書き換えたボックススコアを保存する
    debugPrint('DECISIONS REBUILT: $changed changed');
  }

  /// 1月1日の年度更新：全員が1つ歳をとり、新しいシーズンの日程ができる
  /// 以前の方式の年度更新（シーズンを締めずに年を越えたとき）：年度の切り替え＋1月1日の処理
  void _startNewYear() {
    _rollover();
    _newYearDay();
  }

  /// 1月1日（シーズン後のオフ）：FA の交渉を片付け、スポンサー契約の年数を進め、CPU 球団の1軍・2軍を組み直す
  void _newYearDay() {
    final after = offAfterSeason;
    _newYearCleanup();
    _newYearFinance(decrement: after); // 来季からのスポンサー契約は、ゲーム開始直後の年明けでも始まる
    if (!after) return;
    _cpuReassignAll();
    offAfterSeason = false;
  }

  /// 年度の切り替え（全日程が終わってシーズンを締めたとき）：全員が1つ歳をとり、プロ年数＋1、今季の成績を0に、新しい日程。
  ///  オフ（ドラフト・FA・契約更改）は新しい年度の出来事になる
  void _rollover() {
    _newYearCleanup();
    pendingComp = [];
    for (final p in [...teams.expand((t) => t.players), ...freeAgents.map((f) => f.player)]) {
      p.age += 1;
      p.proYears += 1;
    }
    for (final c in coaches) {
      c.age += 1;
    }
    _compactSeasonPending = startYear;
    monthlyMvps = [];
    monthSnap = {};
    startYear += 1;
    GrowthEngine.snapshotYearStart(teams); // 1年の成長の結果を出すため、年度の初めの能力を控える
    resetSeason(keepDate: true);
    _cpuReassignAll();
    _ensureManagers();
    offAfterSeason = true;
    _addNews(['${startYear}年度になりました。全員が1つ歳をとりました']);
  }

  /// 全チームの今日のベンチ入り26人を作り直す（先発ローテの自動ベンチ外を反映）
  void refreshAllBenches() {
    for (final t in teams) {
      if (t.roster1G.isNotEmpty) t.refreshActive26();
    }
  }

  void _applyResult(Match m, MatchResult result) {
    Team hTeam = teams.firstWhere((t) => t.id == m.homeTeamId);
    Team aTeam = teams.firstWhere((t) => t.id == m.awayTeamId);
    m.boxScore = result.boxScore;
    m.homeScore = result.homeScore;
    m.awayScore = result.awayScore;
    m.homeInningScores = result.homeInningScores;
    m.awayInningScores = result.awayInningScores;
    m.homeHits = result.homeHits;
    m.awayHits = result.awayHits;
    m.playByPlay = result.playByPlay;
    m.pitchByPitch = result.pitchByPitch;
    m.isPlayed = true;
    _gateRevenue(m);
    _collectPitches(m, result);
    if (AiWriter.instance.active && _officialTypes.contains(m.matchType) && (m.homeTeamId == myTeamId || m.awayTeamId == myTeamId)) {
      AiWriter.instance.write(AiFacts.game(m, hTeam, aTeam, context: AiPregame.contextText(this, m, hTeam, aTeam))); // 開発者版：自球団の試合の総評を AI が書いておく（文章と試合展開を PC に貯める）
    }
    hTeam.advanceRotation();
    aTeam.advanceRotation();
    if (result.session != null) _awardGameExp(result.session!, 1.0); // 試合に出た選手の経験値
    // 試合後の体力消費・モチベーション・怪我
    if (result.session != null) {
      final items = ConditionEngine.applyPostGame(result.session!, myTeam: myTeamId);
      // 自チームに関係するお知らせだけ残す
      final mine = teams.where((t) => t.id == myTeamId).map((t) => t.name).toList();
      _addNews(items.where((e) => mine.any((n) => e.contains(n))).toList());
    }
    hTeam.refreshActive26();
    aTeam.refreshActive26();
    if (_noStats(m.matchType)) return; // ポストシーズン・オープン戦は勝敗・守備記録に数えない
    if (result.session != null) {
      _collectFielding(hTeam, true, result.session!);
      _collectFielding(aTeam, false, result.session!);
      _gameRecords(result.session!); // 猛打賞・完封・連続記録・節目など
    }

    if (result.homeScore > result.awayScore) {
      hTeam.wins++;
      aTeam.losses++;
      _managerWin(hTeam, m.date);
    } else if (result.homeScore < result.awayScore) {
      hTeam.losses++;
      aTeam.wins++;
      _managerWin(aTeam, m.date);
    } else {
      hTeam.draws++;
      aTeam.draws++;
    }
  }

  void playNextDay() {
    if (fired) return; // 解任された：次の行き先を選ぶまで進めない
    if (draftPending) {
      if (!autoMode) return; // ドラフト会議を済ませるまで進めない
      runAutoDraft();
    }
    if (activeDraftPending) {
      if (!autoMode) return; // 現役ドラフトを済ませるまで進めない
      runActiveDraft(null);
    }
    if (autoMode && pendingComp.isNotEmpty) {
      for (final c in List.of(pendingComp)) {
        _resolveCompAuto(c, offseasonYear);
      }
      pendingComp.clear();
    }
    _ensureManagers();
    _progressPostseason();
    List<Match> todaysMatches = matches.where((m) => DateUtils.isSameDay(m.date, currentDate)).toList()..sort((a, b) => a.dh.compareTo(b.dh));
    
    if (todaysMatches.isEmpty) {
      if (seasonOver && !seasonFinished) return; // 先にシーズンの記録を締める
      _advanceTo(_nextStop());
      updateAndSave();
      return;
    }

    refreshAllBenches();
    final simulator = MatchSimulator();
    for (var m in todaysMatches) {
      if (m.done) continue;
      _simulateAndApply(simulator, m);
    }
    _playFarmToday();
    _progressPostseason();

    _advanceTo(currentDate.add(const Duration(days: 1)));
    updateAndSave();
  }

  /// 年齢・プロ年数は固定のまま、生年月日だけを開始年に合わせて再計算する（月日は維持）
  void _applyStartYear(Player p) {
    final parts = p.birthDate.split('-');
    final md = parts.length >= 3 ? '${parts[1]}-${parts[2]}' : '04-01';
    p.birthDate = '${startYear - p.age}-$md';
  }

  /// 固有12球団（ID が T_ で始まらないチーム）を `initial_teams_data.dart` と同じ形式のDartソースに書き出す。
  /// 守備適性は全位置60、生年月日は 2026 − 年齢（月日は維持）に正規化して出力する。
  String exportInitialDataSource() {
    final fixed = teams.where((t) => !t.id.startsWith('T_')).toList();
    final copies = fixed.map((t) {
      final c = Team.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>, Player.fromJson);
      for (final p in c.players) {
        p.fieldP = 60; p.fieldC = 60; p.field1B = 60; p.field2B = 60; p.field3B = 60;
        p.fieldSS = 60; p.fieldLF = 60; p.fieldCF = 60; p.fieldRF = 60;
        final parts = p.birthDate.split('-');
        final md = parts.length >= 3 ? '${parts[1]}-${parts[2]}' : '04-01';
        p.birthDate = '${2026 - p.age}-$md';
        p.seasonStats = PlayerStats();
        // 初期データは以前の基準で持つ（読み込むときに raiseBodyStats で底上げする）ので、ここで戻しておく
        p.maxEnergy = (p.maxEnergy - 300).clamp(1, 1000);
        p.recovery = (p.recovery - 30).clamp(1, 99);
        p.durability = (p.durability - 20).clamp(1, 99);
        p.energy = p.maxEnergy;
        p.injuryDays = 0; p.injuryName = ''; p.injurySeverity = 0;
      }
      c.wins = 0; c.losses = 0; c.draws = 0; c.rotationIndex = 0;
      return c;
    }).toList();
    return initialTeamsSource(copies.map((t) => t.toJson()).toList());
  }

  /// 固有12球団の選手を初期データの状態に戻す（移籍・入団は残さない）。
  ///  リーグの組み合わせ（設定で入れ替えた球団）はそのまま残す。新規作成チームも残す
  ///  球団ごとに「初期状態」が保存してあればその状態から（新規作成チームは作ったときの状態）
  Future<void> resetToInitialTeams() async {
    final leagueOf = {for (final t in teams) t.id: t.league};
    final store = InitialStateStore.instance;
    final saved = await store.loadAll();
    // 以前に作った球団で初期状態が無いもの：最初の顔ぶれを移籍の記録から推定して、初期状態にする
    for (final t in teams.where((t) => t.id.startsWith('T_') && !saved.containsKey(t.id)).toList()) {
      final j = _guessInitial(t);
      await store.save(t.id, j);
      saved[t.id] = j;
    }
    final fresh = _initialTeams();
    final out = <Team>[
      for (final t in fresh) saved[t.id] != null ? _teamFromInitial(saved[t.id]!) : t,
      for (final e in saved.entries)
        if (!fresh.any((t) => t.id == e.key)) _teamFromInitial(e.value),
    ];
    for (final t in out) {
      final lg = leagueOf[t.id];
      t.league = lg ?? (t.id.startsWith('T_') ? '' : t.league);
    }
    teams = out;
    _ensureScoutNet(); // 新しく入った球団にもスカウト網
    resetSeason();
  }

  /// 空いたプレイデータで始めるとき：新規作成チーム（初期状態が保存してある球団）も、リーグ未所属で加える
  Future<void> addStoredTeams() async {
    await _templatesFromOtherSlots();
    final saved = await InitialStateStore.instance.loadAll();
    var added = false;
    for (final e in saved.entries) {
      if (!e.key.startsWith('T_') || teams.any((t) => t.id == e.key)) continue;
      final t = _teamFromInitial(e.value)..league = '';
      teams.add(t);
      added = true;
    }
    if (added) {
      _ensureScoutNet();
      updateAndSave();
    }
  }

  /// ほかのプレイデータにある新規作成チームで、初期状態が無いもの：最初の顔ぶれを推定して初期状態にする
  /// テストでは端末のファイルが無いので、ほかの枠は見ない
  static bool scanOtherSlots = true;

  Future<void> _templatesFromOtherSlots() async {
    if (!scanOtherSlots) return;
    final store = InitialStateStore.instance;
    final saved = await store.loadAll();
    for (final n in const [1, 2, 3]) {
      if (n == slot) continue;
      AppDatabase? other;
      try {
        other = AppDatabase.forSlot(n);
        await templatesFromDb(other, saved);
      } catch (e) {
        debugPrint('templates from slot $n: $e');
      }
      try {
        await other?.close();
      } catch (_) {}
    }
  }

  /// プレイデータ（保存）にある新規作成チームで、初期状態が無いものを推定して保存する（枠を消す前・ほかの枠から拾うとき）
  static Future<void> templatesFromDb(AppDatabase db, [Map<String, Map<String, dynamic>>? saved]) async {
    final store = InitialStateStore.instance;
    saved ??= await store.loadAll();
    final js = await db.loadTeamJsons();
    if (!js.any((x) => x.contains('"T_'))) return;
    final ts = [for (final x in js) Team.fromJson(jsonDecode(x) as Map<String, dynamic>, Player.fromJson)];
    final kv = await db.allKv();
    final sy = int.tryParse(kv['startYear'] ?? '') ?? 2026;
    for (final t in ts) {
      if (!t.id.startsWith('T_') || saved.containsKey(t.id)) continue;
      final j = _guessInitialIn(t, ts, const [], sy);
      await store.save(t.id, j);
      saved[t.id] = j;
    }
  }

  /// 初期データから新しく始めたプレイデータか
  bool get isFresh => _freshInitial;

  Team _teamFromInitial(Map<String, dynamic> j) => Team.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>, Player.fromJson);

  /// プレイデータの枠の一覧に出す要約（球団・日付・成績）
  Future<void> _writeSlotSummary() async {
    final t = myTeam;
    if (t == null || !loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('slotSummary_$slot', jsonEncode({'team': t.name, 'short': teamShort(t), 'date': currentDate.toIso8601String(), 'w': t.wins, 'l': t.losses, 'd': t.draws}));
    } catch (_) {}
  }

  /// 球団の今の状態を「初期状態」にする（新しいデータはこの状態から始まる）
  Future<void> saveInitialState(Team t) => InitialStateStore.instance.save(t.id, t.toJson());

  Future<void> removeInitialState(String teamId) => InitialStateStore.instance.remove(teamId);

  /// 初期状態の無い（以前に作った）球団：移籍の記録から最初の顔ぶれを推定する。
  ///  いまいる選手のうち、よそから来ていない・ゲーム中のドラフトで入っていない選手と、この球団から出ていった選手
  Map<String, dynamic> _guessInitial(Team t) => _guessInitialIn(t, teams, freeAgents.map((f) => f.player).toList(), startYear);

  static Map<String, dynamic> _guessInitialIn(Team t, List<Team> all, List<Player> extra, int startYear) {
    final short = teamShort(t);
    bool draftedInGame(Player p) => p.draftYear >= startYear - 1 && p.draftInfo.contains('ドラフト');
    final elsewhere = [
      for (final x in all) if (x.id != t.id) ...x.players,
      ...extra,
    ];
    final roster = <Player>[
      for (final p in t.players)
        if ((p.moves.isEmpty || p.moves.first.contains('（←$short）')) && !draftedInGame(p)) p,
      for (final p in elsewhere)
        if (p.moves.isNotEmpty && p.moves.first.contains('（←$short）')) p,
    ];
    final j = t.toJson();
    j['players'] = [for (final p in roster) p.toJson()];
    final c = Team.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>, Player.fromJson);
    for (final p in c.players) {
      p.moves = [];
    }
    autoAssignTeam(c);
    return c.toJson();
  }

  // ===== ポストシーズン（CS・日本シリーズ） =====
  Series? _series(String id) => postseason.where((s) => s.id == id).firstOrNull;

  /// シリーズの対戦成績（例：4勝2敗）
  String _seriesScore(Series s) {
    final (h, l, d, _) = s.tally(matches);
    return '${h}勝${l}敗${d > 0 ? '${d}分' : ''}${s.advantage > 0 ? '（アドバンテージ1勝を含む）' : ''}';
  }

  /// 保存した表彰を読む（無ければ null）
  Future<Map<String, dynamic>?> loadAwards(int year) async {
    if (lastReport?.year == year && lastReport!.awards.isNotEmpty) return lastReport!.awards;
    try {
      final s = await db.getKv('awards_$year');
      return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 公式戦が終わったらCSを作り、勝敗に応じて次の試合・次のシリーズを1試合ずつ足していく
  void _progressPostseason() {
    if (seasonFinished || !regularDone) return;
    if (postseason.isEmpty) _seedPostseason();
    for (final s in postseason) {
      final was = s.winner;
      if (s.settle(matches) && was.isEmpty) {
        final w = teamById(s.winner)!;
        final byName = {for (final p in w.players) p.registeredName: p};
        s.mvp = seriesMvp([for (final i in s.matchIdx) matches[i]], w, byName);
        _addNews(['${s.label}：${w.name}が勝ち抜け${s.stage == 'JS' ? '、日本一！' : ''}${s.mvp.isNotEmpty ? '（MVP ${s.mvp}）' : ''}']);
      }
    }
    for (final lg in ['CL', 'PL']) {
      final cs1 = _series('CS1_$lg'), csf = _series('CSF_$lg');
      if (cs1 != null && csf != null && cs1.winner.isNotEmpty && csf.low.isEmpty) csf.low = cs1.winner;
    }
    final c = _series('CSF_CL'), p = _series('CSF_PL');
    if (c != null && p != null && c.winner.isNotEmpty && p.winner.isNotEmpty && _series('JS') == null) {
      final plHome = startYear.isEven; // 本拠地の有利（第1・2・6・7戦）は年ごとに交互
      postseason.add(Series(id: 'JS', stage: 'JS', league: 'JS', high: plHome ? p.winner : c.winner, low: plHome ? c.winner : p.winner, winsNeeded: 4, maxGames: 8));
    }
    for (final s in postseason) {
      if (s.needsGame(matches)) _addSeriesGame(s);
    }
  }

  void _seedPostseason() {
    for (final lg in ['CL', 'PL']) {
      final st = computeStandings(teams, matches, lg, StandingsKind.official);
      if (st.length < 3) continue;
      postseason.add(Series(id: 'CS1_$lg', stage: 'CS1', league: lg, high: st[1].team.id, low: st[2].team.id, winsNeeded: 2, maxGames: 3));
      postseason.add(Series(id: 'CSF_$lg', stage: 'CSF', league: lg, high: st[0].team.id, winsNeeded: 4, advantage: 1, maxGames: 6));
    }
    _addNews(['公式戦が終了。クライマックスシリーズへ']);
  }

  void _addSeriesGame(Series s) {
    final n = s.matchIdx.length;
    var date = s.dateOf(n, startYear);
    final today = DateUtils.dateOnly(currentDate);
    if (date.isBefore(today)) date = today;
    final home = s.homeOf(n);
    final away = home == s.high ? s.low : s.high;
    matches.add(Match(homeTeamId: home, awayTeamId: away, date: date, matchType: s.matchType));
    farmMatches.add(Match(homeTeamId: home, awayTeamId: away, date: date, matchType: s.matchType)); // 番号をそろえるための空き（2軍は試合しない）
    s.matchIdx.add(matches.length - 1);
    _matchesReplaceAll = true;
  }

  // ===== 成績を一時的に退避（ポストシーズン・オールスターは今季成績に入れない） =====
  Map<Player, PlayerStats>? _liveSnap;

  Map<Player, PlayerStats> _snapStats(Iterable<Team> ts) => {
        for (final t in ts)
          for (final p in t.players) p: PlayerStats.fromJson(jsonDecode(jsonEncode(p.seasonStats.toJson())) as Map<String, dynamic>),
      };

  void _restoreStats(Map<Player, PlayerStats> snap) {
    snap.forEach((p, s) => p.seasonStats = s);
  }

  /// オープン戦の間だけ、今季成績の欄にオープン戦の成績（の写し）を入れて試合をする
  void _useOpenStats(Iterable<Team> ts) {
    for (final t in ts) {
      for (final p in t.players) {
        p.seasonStats = PlayerStats.fromJson(jsonDecode(jsonEncode(p.openStats.toJson())) as Map<String, dynamic>);
      }
    }
  }

  /// 試合が終わったら、今季成績の欄に積み上がった分をオープン戦の成績として残す
  void _keepOpenStats(Iterable<Team> ts) {
    for (final t in ts) {
      for (final p in t.players) {
        p.openStats = p.seasonStats;
      }
    }
  }

  /// オープン戦の期間（その年の公式戦の初日より前）か
  bool get openPeriod {
    DateTime? first;
    for (final m in matches) {
      if (m.matchType != 'LEAGUE' && m.matchType != 'INTERLEAGUE') continue;
      if (first == null || m.date.isBefore(first)) first = m.date;
    }
    return first != null && currentDate.isBefore(first) && matches.any((m) => m.matchType == 'OPEN');
  }

  /// 自チームのポストシーズンを対話式で始める前に呼ぶ
  void prepareLiveGame(Match m) {
    if (!_noStats(m.matchType)) return;
    final ts = teams.where((t) => t.id == m.homeTeamId || t.id == m.awayTeamId).toList();
    _liveSnap = _snapStats(ts);
    _liveOpen = m.matchType == 'OPEN' ? ts : null;
    if (_liveOpen != null) _useOpenStats(ts);
  }

  /// 対話式のオープン戦の両球団
  List<Team>? _liveOpen;

  /// 対話式の試合をやめたとき
  void cancelLiveGame() {
    if (_liveSnap != null) _restoreStats(_liveSnap!);
    _liveSnap = null;
    _liveOpen = null;
  }

  // ===== オールスター =====
  void _playAllStar(MatchSimulator sim, Match m) {
    final ranks = <String, int>{};
    for (final lg in ['CL', 'PL']) {
      final st = computeStandings(teams, matches, lg, StandingsKind.official);
      for (var i = 0; i < st.length; i++) {
        ranks[st[i].team.id] = i + 1;
      }
    }
    final home = buildAllStarTeam(m.homeTeamId, m.homeTeamId.startsWith('PL') ? 'PL' : 'CL', teams, ranks);
    final away = buildAllStarTeam(m.awayTeamId, m.awayTeamId.startsWith('PL') ? 'PL' : 'CL', teams, ranks);
    if (home.lineup.length < 9 || away.lineup.length < 9) return;
    final snap = _snapStats([home, away]);
    final energy = {for (final p in [...home.players, ...away.players]) p: p.energy};
    try {
      final r = sim.simulateMatch(m, home, away);
      m.boxScore = r.boxScore;
      m.homeScore = r.homeScore;
      m.awayScore = r.awayScore;
      m.homeInningScores = r.homeInningScores;
      m.awayInningScores = r.awayInningScores;
      m.homeHits = r.homeHits;
      m.awayHits = r.awayHits;
      m.playByPlay = r.playByPlay;
      m.pitchByPitch = r.pitchByPitch;
      m.isPlayed = true;
      final winner = r.homeScore >= r.awayScore ? home : away;
      final mvp = seriesMvp([m], winner, const {});
      if (mvp.isNotEmpty) m.boxScore!['mvp'] = mvp;
      _addNews(['オールスター：${away.name} ${r.awayScore} − ${r.homeScore} ${home.name}${mvp.isNotEmpty ? '（MVP $mvp）' : ''}']);
    } catch (e, st) {
      debugPrint('ALLSTAR ERROR: $e\n$st');
    } finally {
      _restoreStats(snap);
      energy.forEach((p, e) => p.energy = e);
    }
  }

  // ===== 守備の記録（ベストナイン・ゴールデングラブ用） =====
  static const _roleToPos = {'P': '投', 'C': '捕', '1B': '一', '2B': '二', '3B': '三', 'SS': '遊', 'LF': '左', 'CF': '中', 'RF': '右'};

  void _collectFielding(Team t, bool home, GameSession s) {
    final byId = {for (final p in t.players) p.id: p};
    // 先発出場の守備位置
    for (final l in t.lineup) {
      final p = byId[l.playerId];
      if (p == null) continue;
      p.seasonStats.posGames[l.position] = (p.seasonStats.posGames[l.position] ?? 0) + 1;
    }
    final sp = home ? s.homePitchers.firstOrNull : s.awayPitchers.firstOrNull;
    if (sp != null && !t.lineup.any((l) => l.position == '投')) sp.seasonStats.posGames['投'] = (sp.seasonStats.posGames['投'] ?? 0) + 1;
    // 打球の処理
    final lineup = home ? s.homeLineup : s.awayLineup;
    final byName = {for (final p in t.players) p.registeredName: p};
    for (final e in s.pitchEvents) {
      if (e.fielder.isEmpty || e.battingHome == home) continue; // 守っている側だけ
      Player? p;
      if (e.fielder == 'P') {
        p = byName[e.pitcher];
      } else {
        final pos = _roleToPos[e.fielder];
        final l = lineup.where((x) => x.position == pos).firstOrNull;
        if (l != null) p = byId[l.playerId];
      }
      if (p == null) continue;
      p.seasonStats.fieldChances++;
      if (e.outcome == 'アウト' || e.outcome == '併殺') p.seasonStats.fieldOuts++;
    }
    // 刺殺・補殺・失策・併殺（プレーの記号「6-4-3」から。1=投 2=捕 3=一 … 9=右）
    Player? atPos(String pos) {
      if (pos == '投') return byName[(home ? s.homePitcher : s.awayPitcher).registeredName];
      final l = lineup.where((x) => x.position == pos).firstOrNull;
      return l == null ? null : byId[l.playerId];
    }
    const numToPos = ['', '投', '捕', '一', '二', '三', '遊', '左', '中', '右'];
    for (final e in s.pitchEvents) {
      if (e.battingHome == home) continue; // 守っている側だけ
      if (e.errorBy.isNotEmpty) {
        final pos = _roleToPos[e.errorBy];
        if (pos != null) atPos(pos)?.seasonStats.errors++;
      }
      // 三振：捕手の刺殺
      if (e.result == '空振り' || e.result == '見逃し') {
        if (e.strikes == 2) atPos('捕')?.seasonStats.putouts++;
        continue;
      }
      if (e.outcome != 'アウト' && e.outcome != '併殺') continue;
      final nums = RegExp(r'[1-9]').allMatches(e.playCode).map((m) => int.parse(m.group(0)!)).toList();
      if (nums.isEmpty) {
        final pos = _roleToPos[e.fielder];
        // ゴロを内野手が捕ってアウト：一塁への送球（内野手の補殺・一塁手の刺殺）。一塁手自身なら単独の刺殺
        if (e.contact == 'ゴロ' && const {'P', '2B', '3B', 'SS'}.contains(e.fielder) && e.outcome == 'アウト') {
          if (pos != null) atPos(pos)?.seasonStats.assists++;
          atPos('一')?.seasonStats.putouts++;
          continue;
        }
        // フライ・ライナーの捕球：捕った野手の刺殺
        if (pos != null) atPos(pos)?.seasonStats.putouts++;
        continue;
      }
      final dp = e.outcome == '併殺';
      final involved = <Player>{};
      for (var i = 0; i < nums.length; i++) {
        final q = atPos(numToPos[nums[i]]);
        if (q == null) continue;
        involved.add(q);
        final last = i == nums.length - 1;
        if (last || e.playCode.endsWith('A')) {
          q.seasonStats.putouts++;
        } else {
          q.seasonStats.assists++;
          if (dp && i == 1) q.seasonStats.putouts++; // 併殺の中継（6-4-3 の 4）は二塁でもアウトを取っている
        }
      }
      if (dp) {
        for (final q in involved) {
          q.seasonStats.dpTurned++;
        }
      }
    }
    // 守備イニング：打席ごとに、その時点で守備位置に就いていた選手に付けた分（途中出場・守備位置の移動も含む）
    for (final e in s.posOuts.entries) {
      final p = byId[e.key];
      if (p == null) continue;
      e.value.forEach((pos, o) {
        p.seasonStats.posOuts[pos] = (p.seasonStats.posOuts[pos] ?? 0) + o;
        p.seasonStats.defOuts += o;
      });
    }
  }

  // ===== シーズンの終わり（年度更新） =====
  /// 公式戦・交流戦・オープン戦がすべて終わったか（オールスターは未実装なので数えない）
  bool get seasonOver => regularDone && postseasonDone;

  /// 公式戦・交流戦・オープン戦・オールスターがすべて終わったか
  bool get regularDone => matches.isNotEmpty && matches.every((m) => m.done || isSpecialType(m.matchType));

  /// 日本シリーズまで終わったか（ポストシーズンを作る前のセーブは、作らずに終わった扱い）
  bool get postseasonDone => postseason.any((s) => s.stage == 'JS' && s.winner.isNotEmpty) || (seasonFinished && postseason.isEmpty);

  /// 日本一の球団（未定は null）
  Team? get champion {
    final js = postseason.where((s) => s.stage == 'JS' && s.winner.isNotEmpty).firstOrNull;
    return js == null ? null : teamById(js.winner);
  }

  /// まだ終わっていない試合の内訳（確認用）：件数と、先頭の数試合
  String unplayedSummary() {
    final left = matches.where((m) => !m.done && m.matchType != 'ALLSTAR').toList()..sort((a, b) => a.date.compareTo(b.date));
    if (left.isEmpty) return '未消化なし';
    final first = left.take(3).map((m) => '${m.date.month}/${m.date.day} ${m.matchType} ${m.homeTeamId}-${m.awayTeamId}').join('、');
    return '未消化 ${left.length}試合：$first';
  }

  /// 年度更新の結果（画面に見せる用）
  SeasonReport? lastReport;

  /// シーズンを締めて次の年へ進める。
  /// 記録の保存 → 成長（試合経験・衰え）→ 年齢・プロ年数＋1 → 新しい日程。終わっていなければ null
  Future<SeasonReport?> finishSeason() async {
    if (!seasonOver || seasonFinished) return null;
    final year = startYear;

    // 球団の順位と成績（公式戦＋交流戦のみ。オープン戦は含めない）
    final ranks = <String, int>{};
    final records = <String, List<int>>{};
    for (final lg in ['CL', 'PL']) {
      final st = computeStandings(teams, matches, lg, StandingsKind.official);
      for (var i = 0; i < st.length; i++) {
        ranks[st[i].team.id] = i + 1;
        records[st[i].team.id] = [st[i].w, st[i].l, st[i].d];
      }
    }

    // 記録（選手ごと・球団ごと）をDBへ
    final rows = <SeasonRecordsCompanion>[];
    for (final t in teams) {
      rows.add(SeasonRecordsCompanion.insert(
        season: year, kind: 'team', refId: t.id, teamId: t.id,
        json: jsonEncode({'name': t.name, 'league': t.league, 'wins': records[t.id]?[0], 'losses': records[t.id]?[1], 'draws': records[t.id]?[2], 'rank': ranks[t.id],
          'champion': champion?.id == t.id, 'manager': t.id == myTeamId ? 'あなた' : (staffOf(t)['監督']?.name ?? '')}),
      ));
      for (final p in t.players) {
        rows.add(SeasonRecordsCompanion.insert(
          season: year, kind: 'player', refId: p.id, teamId: t.id,
          json: jsonEncode({'name': p.registeredName, 'age': p.age, 'ovr': p.ovr, 'pos': p.mainPosition, 'stats': p.seasonStats.toJson(), 'farm': p.farmStats.toJson(), 'teams': p.seasonTeams, 'splits': p.seasonSplits}),
        ));
      }
    }
    final summary = _leagueSummary(year);

    // 表彰（成長で能力が変わる前に、今季の成績で決める）
    Map<String, dynamic>? prevAwards;
    final prevStats = <String, Map<String, dynamic>>{};
    try {
      final pa = await db.getKv('awards_${year - 1}');
      if (pa != null) prevAwards = jsonDecode(pa) as Map<String, dynamic>;
      final rowsPrev = await (db.select(db.seasonRecords)..where((t) => t.season.equals(year - 1) & t.kind.equals('player'))).get();
      for (final r in rowsPrev) {
        final j = jsonDecode(r.json) as Map<String, dynamic>;
        if (j['stats'] is Map) prevStats[r.refId] = Map<String, dynamic>.from(j['stats'] as Map);
      }
    } catch (e) {
      debugPrint('PREV RECORD ERROR: $e');
    }
    _monthlyMvp('9・10月'); // 9・10月の月間MVP（シーズンの終わりに選ぶ）
    await db.setKv('monthlyMvp_$year', jsonEncode(monthlyMvps));
    final awards = AwardsEngine.compute(
      year: year,
      teams: teams,
      matches: matches,
      previous: prevAwards,
      prevStats: prevStats,
      series: [for (final s in postseason) {'id': s.id, 'label': s.label, 'high': s.high, 'low': s.low, 'winner': s.winner, 'mvp': s.mvp, 'score': _seriesScore(s)}],
      allStarMvps: [for (final m in matches.where((m) => m.matchType == 'ALLSTAR')) if (m.boxScore?['mvp'] is String) m.boxScore!['mvp'] as String],
      championId: champion?.id,
    );

    // 成長（試合経験＋衰え）
    final changes = GrowthEngine.endOfSeason(teams, year);
    _addNews([for (final c in changes) if (c.reverted && c.teamId == myTeamId) '${c.player.listName}に復調の兆し（${c.phase.label}に戻った）']);
    summary['avgOvrBatAfter'] = _avgOvr(false);
    summary['avgOvrPitAfter'] = _avgOvr(true);

    // 通算成績に今季の成績を足す
    for (final t in teams) {
      for (final p in t.players) {
        p.career.add(p.seasonStats);
        for (final sp in p.seasonSplits) {
          if (sp['stats'] is Map) p.career.add(PlayerStats.fromJson(Map<String, dynamic>.from(sp['stats'] as Map)));
        }
      }
    }
    // コーチ：在任年数＋1。1シーズン以上見たコーチは、本当の能力が分かる
    for (final c in coaches.where((c) => c.teamId != null)) {
      c.seasonsWithTeam++;
      if (!c.known && c.teamId == myTeamId) _addNews(['${c.role}コーチ ${c.name} の本当の指導力が分かりました']);
      c.known = true;
    }

    // 引退・FA の資格・CPU 球団の戦力外・監督の交代
    final retired = _processRetirements(year);
    _hallOfFameVote(year); // 殿堂入りの投票（引退から5年たった選手）
    _recordMyCareer(year, ranks, records, champion?.id);
    _processService();
    _cpuReleases(year);
    final changed = _managerChanges(ranks, year);
    if (ronin) _roninOffers(ranks, changed);
    final fin = _financeSeasonEnd(ranks, year);

    final standingsSnap = _standingsSnapshot(); // 順位表の詳細（年度を切り替えると試合が消えるので先に）
    // 記録を締めてオフシーズンへ（年齢・日程が変わるのは1月1日）
    reviewPolicies(); // CPU 球団の方針を、今季の順位と戦力の年齢で見直す
    seasonFinished = true;
    notifyListeners();
    await saveData();

    try {
      await db.saveRecords(year, rows);
      await db.setKv('summary_$year', jsonEncode(summary));
      await db.setKv('awards_$year', jsonEncode(awards));
      await db.setKv('standings_$year', jsonEncode(standingsSnap));
      _recordHonors(year, awards);
    } catch (e) {
      debugPrint('RECORD ERROR: $e');
    }
    // 記録を残したら、年度を切り替える（オフは新しい年度の出来事）
    _rollover();
    updateAndSave();
    return lastReport = SeasonReport(year: year, ranks: ranks, records: records, changes: changes, summary: summary, awards: awards, retired: retired, finance: fin);
  }

  double _avgOvr(bool pitchers) {
    var sum = 0, n = 0;
    for (final t in teams) {
      for (final p in t.players.where((p) => p.isPitcher == pitchers && t.roster1G.contains(p.id))) {
        sum += p.ovr;
        n++;
      }
    }
    return n == 0 ? 0 : sum / n;
  }

  /// リーグ全体の記録（能力の平均と得点・打率）。年々上がり続けていないか（インフレ）を確かめる
  Map<String, dynamic> _leagueSummary(int year) {
    var games = 0, runs = 0;
    for (final m in matches) {
      if (m.matchType == 'ALLSTAR' || m.homeScore == null) continue;
      games++;
      runs += m.homeScore! + m.awayScore!;
    }
    var ab = 0, h = 0, hr = 0;
    for (final t in teams) {
      for (final p in t.players) {
        ab += p.seasonStats.atBats;
        h += p.seasonStats.hits;
        hr += p.seasonStats.homeRuns;
      }
    }
    return {
      'year': year,
      'games': games,
      'runsPerTeamGame': games == 0 ? 0 : runs / (games * 2),
      'avg': ab == 0 ? 0 : h / ab,
      'hrPerTeamGame': games == 0 ? 0 : hr / (games * 2),
      'avgOvrBat': _avgOvr(false),
      'avgOvrPit': _avgOvr(true),
    };
  }

  /// シーズンの成績・体力などを戻して、新しい日程を作る。keepDate=false のときは前年10月31日（ドラフト会議）から始める
  void resetSeason({bool keepDate = false}) {
    matchups.clear(); // 対戦成績は今季の分だけ
    if (!keepDate) {
      // はじめから：ドラフト・移籍の途中経過も消す（チームの選手はそのまま）
      currentDate = DateTime(startYear - 1, 10, 31);
      draftDoneYear = 0;
      activeDraftYear = 0;
      prepDraftYear = 0;
      otherWorld = OtherLeagueEngine.generate(currentDate, currentDate.year); // 他リーグも作り直す
      _otherForceSave = true;
      amWorld = AmateurEngine.generate(amSchoolYear(currentDate), Random(currentDate.year * 17 + 3)); // アマチュア球界も作り直す
      _amForceSave = true;
      prospects = [];
      freeAgents = [];
      faCases = [];
      pendingComp = [];
      compPicks = {};
      pickOwner = {};
      teamPolicy = {};
      lastTradeWith = {};
      postingAsk = {};
      partnerSlots = [];
      partnerStay = [];
      tenders = [];
      foreignPool = [];
      foreignWatch = {};
      scoutLog = [];
      tradeTips = [];
      finances = {};
      sponsorOffers = [];
      lastRankOf = {};
      fired = false;
      firedOffers = [];
      // これまでの記録・お知らせも消す（球団・選手・コーチ・設定は残す）
      news = [];
      newsLog = {};
      transactions = [];
      ledger = [];
      monthlyMvps = [];
      monthSnap = {};
      retirees = [];
      draftBook = {};
      chronYears = {};
      chronFirstYear = startYear;
      myCareer = [];
      renewSigned = {};
      renewTries = {};
      ronin = false;
      roninReturn = false;
      lastReport = null;
      leagueHistory = null;
      _preCache = null;
      _wipeHistory = true; // 保存のときに、DB のこれまでの年度の記録・試合・1球ごとの記録を消す
      for (final p in [...teams.expand((t) => t.players)]) {
        p.openStats = PlayerStats();
        p.moves = [];
        p.hitStreak = 0;
        p.hitStreakBest = 0;
        p.playStreak = 0;
        p.playStreakBest = 0;
        p.streaks = {};
      }
    }
    seasonFinished = false;
    postseason = [];
    for (var t in teams) {
      t.wins = 0;
      t.losses = 0;
      t.draws = 0;
      t.rotationIndex = 0;
      t.farmRotationIndex = 0;
      for (var p in t.players) {
        p.seasonStats = PlayerStats();
        p.farmStats = PlayerStats();
        p.thirdStats = PlayerStats();
        p.seasonTeams = [];
        p.seasonSplits = [];
        p.seasonParts = [];
        p.partBase = {};
        p.energy = p.maxEnergy; p.injuryDays = 0; p.injuryName = ''; p.injurySeverity = 0; p.motivation = 50;
        _applyStartYear(p);
      }
      if (t.roster1G.isNotEmpty) t.refreshActive26();
    }
    _generateSchedule(keepDate: true);
    if (!keepDate) {
      _roundSalaries();
      _ensureProspects();
      _ensureManagers();
      _ensureFinance();
    }
    updateAndSave();
  }

  bool _deferSave = false; // まとめて進めている間は、保存と画面更新を最後の1回にする

  void updateAndSave() {
    if (_deferSave) return;
    notifyListeners();
    saveData();
  }

  /// シーズンの終わりまで、全試合を自動で進める（確認用）。保存と画面更新は最後に1回だけ
  Future<void> playUntilSeasonEnd() async {
    _deferSave = true;
    final wasAuto = autoMode;
    autoMode = true; // ドラフト・補償もおまかせ
    try {
      var guard = 0;
      while (!seasonOver && guard++ < 400) {
        playNextDay();
        if (guard % 10 == 0) await Future<void>.delayed(Duration.zero); // 画面が固まらないよう、ときどき手を休める
      }
    } finally {
      _deferSave = false;
      autoMode = wasAuto;
    }
    notifyListeners();
    await saveData();
  }
}

/// 年度更新の結果
class SeasonReport {
  final int year;
  final Map<String, int> ranks; // 球団ID → リーグ内の順位
  final Map<String, List<int>> records; // 球団ID → [勝, 敗, 分]（リセット前の成績）
  final List<GrowthChange> changes;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> awards; // 表彰（AwardsEngine の結果）
  final List<String> retired; // 自球団の引退選手
  final FinanceResult? finance; // 自球団の収支とオーナーの評価
  SeasonReport({this.finance, required this.year, required this.ranks, required this.records, required this.changes, required this.summary, this.awards = const {}, this.retired = const []});
}
