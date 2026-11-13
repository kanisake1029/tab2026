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
part 'save_ops.dart';
part 'repair_ops.dart';

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
  /// 空の枠（「新しく始める」画面用）のときは、重い他リーグ・アマチュア生成とDB保存を「開始する」まで先送りする
  final bool deferWorldGen;

  AppState([AppDatabase? database, this.slot = 1, this.deferWorldGen = false]) : db = database ?? AppDatabase() {
    currentDate = DateTime(startYear - 1, 10, 31); // 監督就任は、1年目のドラフト会議（前年10月31日）から
    loadData();
  }

  // 初期データに末尾カンマ（不正なJSON）が含まれているため、読み込み前に取り除く（1回だけ処理してキャッシュ）
  static String? _cleanedInitialCache;
  static String _cleanJson(String s) => s.replaceAllMapped(RegExp(r',(\s*[\]}])'), (m) => m[1]!);

  List<Team> _initialTeams() {
    _cleanedInitialCache ??= _cleanJson(InitialTeamsData.jsonString);
    final ts = (jsonDecode(_cleanedInitialCache!) as List).map<Team>((t) => Team.fromJson(t, Player.fromJson)).toList();
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
  /// 画面に知らせる（拡張機能のファイルからも呼べるように）
  void notifyChanged() => notifyListeners();
  final Map<String, String> _savedProspectJson = {}; // 保存済みのドラフト候補のJSON（変わった候補だけ書き込む）
  final Map<String, int> _savedProspectSort = {};
  bool _legacyProspectKv = false; // 以前の形（kv の 'prospects'）が残っている。表に移したら消す
  String? _backupBeforeSave; // 次の保存の前に、いまのデータベースを控えに残す理由（ドラフト・年度替わり・契約更改の前）
  void _requestBackup(String label) => _backupBeforeSave ??= label;
  final Map<String, String> _savedTeamJson = {}; // 保存済みのチームJSON（変わったチームだけ書き込む）
  final Map<String, int> _savedTeamSort = {};
  final Set<int> _savedPlayed = {}; // 結果を保存済みの試合の番号
  final Set<int> _savedFarmPlayed = {}; // 結果を保存済みの2軍の試合の番号

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

  Map<String, String> _moveKv({bool withProspects = true}) => {
        if (withProspects) 'prospects': jsonEncode(prospects.map((p) => p.toJson()).toList()),
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

  /// はじめからにしたあとの最初の保存で、DB のこれまでの記録を消す
  bool _wipeHistory = false;

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
    _requestBackup('${startYear}年度の終わり（年度替わりの前）');
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
      if (deferWorldGen && _freshInitial) {
        notifyListeners();
      } else {
        updateAndSave();
      }
    }
  }

  /// ほかのプレイデータにある新規作成チームで、初期状態が無いもの：最初の顔ぶれを推定して初期状態にする
  /// テストでは端末のファイルが無いので、ほかの枠は見ない
  static bool scanOtherSlots = true;

  Future<void> _templatesFromOtherSlots() async {
    if (!scanOtherSlots) return;
    final prefs = await SharedPreferences.getInstance();
    final store = InitialStateStore.instance;
    final saved = await store.loadAll();
    for (final n in const [1, 2, 3]) {
      if (n == slot) continue;
      // 要約キャッシュ（および1番の旧形式）が無い空きスロットはDBを開かない
      if (prefs.getString('slotSummary_$n') == null && !(n == 1 && prefs.getString('teamsData') != null)) {
        continue;
      }
      AppDatabase? other;
      try {
        other = AppDatabase.forSlot(n);
        await templatesFromDb(other, saved).timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('templates from slot $n: $e');
      }
      try {
        await other?.close().timeout(const Duration(seconds: 2));
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
