import 'stadium.dart';
import 'player.dart';
import 'league_rules.dart';

class LineupEntry {
  String playerId;
  String position;
  LineupEntry({required this.playerId, required this.position});

  Map<String, dynamic> toJson() => {'playerId': playerId, 'position': position};
  factory LineupEntry.fromJson(Map<String, dynamic> json) => LineupEntry(playerId: json['playerId'], position: json['position']);
}

class Team {
  int year;
  String id;
  String name;
  String shortName;
  String initialName;
  String league; // 'CL' or 'PL'
  String stadiumId = ''; // 本拠地の球場（Stadium.byId。'' は初期値＝Stadium.defaultFor(id)）
  String get homeStadium => stadiumId.isNotEmpty ? stadiumId : Stadium.defaultFor(id);
  String prefecture = ''; // 本拠地の所在地（都道府県）。'' は本拠地の球場の所在地
  String get homePrefecture => prefecture.isNotEmpty ? prefecture : Stadium.byId(homeStadium).prefecture;
  Map<String, dynamic> parkMods = {}; // 本拠地の改修（terrace・wall・turf）。Stadium.modded を見る
  int parkWorkYear = 0; // 最後に球場を改修したオフ（その年の 11 月〜翌 2 月で 1 回）
  Stadium get park => Stadium.modded(homeStadium, id, parkMods);
  int uniformColor = 0; // ユニフォーム・球団の色（0＝並び順の色）
  String logoText = ''; // 胸のロゴ（英語のチーム名）。'' は初期値（固有12は下の表、ほかは1文字の名前）
  static const _logos = {'P0': 'Falcons', 'P1': 'Breakers', 'P2': 'Oceans', 'P3': 'Ravens', 'P4': 'Bisons', 'P5': 'Leopards', 'C0': 'Titans', 'C1': 'Jaguars', 'C2': 'Flares', 'C3': 'Orcas', 'C4': 'Gryphons', 'C5': 'Wyverns'};
  String get logo => logoText.isNotEmpty ? logoText : (_logos[id] ?? (initialName.isNotEmpty ? initialName : (shortName.isNotEmpty ? shortName : name)));
  
  List<Player> players; 
  List<String> roster1G;
  List<String> _rotation;       // 先発枠（常に9枠を保持し、先頭 rotationCount 枠を使う。空枠は ''）
  List<String> get rotation => _rotation;
  set rotation(List<String> v) => _rotation = _fixed(v, maxRotation);
  int rotationCount;            // 先発ローテの人数（4〜9）
  List<String> winningPattern;  // 勝利の方程式3枠（[7回, 8回, 9回]、空枠は ''）
  int rotationIndex;            // 次に先発する rotation の枠番号（試合確定ごとに進む）
  List<LineupEntry> lineup;
  bool useDH;
  List<String> active26;        // 今日のベンチ入り（refreshActive26 で毎日作り直す）
  List<String> manualBenchOut;  // ユーザーが選んだベンチ外（先発ローテ以外）
  List<String> protectList;     // FA の人的補償のプロテクト（31人。空なら自動で上位31人）
  List<String> springCamp;      // 春季キャンプ（1軍キャンプ）に連れていく選手（最大50人）。空なら始まるときに自動で選ぶ
  List<String> autumnCamp;      // 秋季キャンプに連れていく選手（最大30人）。空なら始まるときに自動で選ぶ
  List<String> thirdPriority;   // 3軍戦で優先して出す選手（3軍監督のオーダーより先に入れる）
  List<String> thirdLineup;     // 3軍の打順（自分で組むとき。出られない選手の分は3軍監督が埋める）
  bool thirdAuto;               // 3軍の打順を3軍監督にまかせる

  // ===== 2軍のオーダー（2軍戦は1軍と同じ日程・同じ対戦チームの2軍と行う。介入できるのはオーダーのみ） =====
  bool farmAuto;                 // true=自動で組む（怪我・疲労を見て毎日組み直す）
  List<LineupEntry> farmLineup;  // 手動のときの打順（9人。位置は 捕・一・二・三・遊・左・中・右・DH）
  List<String> farmRotation;     // 手動のときの先発ローテ（最大5枠。空枠は ''）
  int farmRotationIndex;         // 次に先発する2軍の枠番号
  static const int farmRotationSize = 8; // 2軍の先発枠の初めの人数（スタミナの少ない投手も先発で使えるよう多めに）
  static const int farmRotationMin = 4, farmRotationMax = 12;
  int farmRotationCount;        // 2軍の先発ローテの人数（4〜12）

  int wins;
  int losses;
  int draws;

  static const int maxRotation = 9;
  static const int minRotation = 4;
  static const int benchSize = 26;
  static const int winningPatternSize = 3;

  Team({
    required this.id,
    this.year = 2026,
    required this.name,
    required this.league,
    this.shortName = '',
    this.initialName = '',
    List<Player>? players,
    List<String>? roster1G,
    List<String>? rotation,
    List<String>? winningPattern,
    int rotationCount = 6,
    int rotationIndex = 0,
    List<LineupEntry>? lineup,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.useDH = true,
    List<String>? active26,
    List<String>? manualBenchOut,
    List<String>? protectList,
    List<String>? springCamp,
    List<String>? autumnCamp,
    List<String>? thirdPriority,
    List<String>? thirdLineup,
    this.thirdAuto = true,
    this.farmAuto = true,
    List<LineupEntry>? farmLineup,
    List<String>? farmRotation,
    this.farmRotationIndex = 0,
    this.farmRotationCount = farmRotationSize,
  })  : players = players ?? [],
        farmLineup = farmLineup ?? [],
        farmRotation = farmRotation ?? [],
        roster1G = roster1G ?? [],
        _rotation = _fixed(rotation, maxRotation),
        rotationCount = rotationCount.clamp(minRotation, maxRotation),
        rotationIndex = rotationIndex % rotationCount.clamp(minRotation, maxRotation),
        winningPattern = _fixed(winningPattern, winningPatternSize),
        active26 = active26 ?? [],
        manualBenchOut = manualBenchOut ?? [],
        protectList = protectList ?? [],
        springCamp = springCamp ?? [],
        autumnCamp = autumnCamp ?? [],
        thirdPriority = thirdPriority ?? [],
        thirdLineup = thirdLineup ?? [],
        lineup = lineup ?? [];

  static List<String> _fixed(List<String>? src, int n) {
    final out = List<String>.from(src ?? const []);
    while (out.length < n) { out.add(''); }
    return out.length > n ? out.sublist(0, n) : out;
  }

  /// 今日の先発投手のid（空枠は次の有効な枠まで進める。なければ null）
  String? get todaysStarterId {
    for (var i = 0; i < rotationCount; i++) {
      final id = rotation[(rotationIndex + i) % rotationCount];
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  /// 使用中の先発枠（先頭 rotationCount 枠）
  List<String> get activeRotation => rotation.sublist(0, rotationCount);

  /// 先発が登板したので次の枠へ進める
  void advanceRotation() {
    rotationIndex = (rotationIndex + 1) % rotationCount;
  }

  /// 先発ローテの人数を変える（4〜7）。外れた枠の投手はローテから外す
  void setRotationCount(int n) {
    n = n.clamp(minRotation, maxRotation);
    if (n < rotationCount) {
      for (var i = n; i < maxRotation; i++) { rotation[i] = ''; }
    }
    rotationCount = n;
    rotationIndex %= rotationCount;
    autoFillPitchingStaff();
    refreshActive26();
  }

  /// 先発枠・勝利の方程式3枠の空きを、1軍投手のOVR順で自動補充する
  void autoFillPitchingStaff() {
    final ids = roster1G.isNotEmpty ? roster1G : active26;
    final pool = players.where((p) => p.isPitcher && ids.contains(p.id)).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final used = <String>{...activeRotation.where((e) => e.isNotEmpty), ...winningPattern.where((e) => e.isNotEmpty)};
    Player? take() {
      for (final p in pool) { if (!used.contains(p.id)) { used.add(p.id); return p; } }
      return null;
    }
    for (var i = 0; i < rotationCount; i++) { if (rotation[i].isEmpty) { final p = take(); if (p != null) rotation[i] = p.id; } }
    // 方程式: 空いている枠を、9回(抑え)→8回→7回の順に強い投手から埋める
    for (final i in [2, 1, 0]) { if (winningPattern[i].isEmpty) { final p = take(); if (p != null) winningPattern[i] = p.id; } }
  }

  // ===== ベンチ入り（26人）の自動決定 =====
  /// 直近で refreshActive26 が自動でベンチ外にした選手（UI表示用）
  List<String> autoBenchOutRotation = [];   // 今日投げない先発
  List<String> autoBenchOutFill = [];       // 手動の不足分を自動で補った選手

  /// 今日投げない先発を、次回登板が近い順に並べたもの
  List<String> get restingStarters {
    final today = todaysStarterId;
    final out = <String>[];
    for (var i = 1; i < rotationCount; i++) {
      final id = rotation[(rotationIndex + i) % rotationCount];
      if (id.isNotEmpty && id != today && !out.contains(id)) out.add(id);
    }
    return out;
  }

  /// 1軍のうちベンチ外にしなければならない人数
  int get benchOutNeeded => (roster1G.length - benchSize).clamp(0, 999);

  /// 今日のベンチ入り26人を作り直す。
  /// 1) 今日投げない先発を自動でベンチ外（多すぎる分は登板が遠い順にベンチへ残す）
  /// 2) 残り枠はユーザーの手動ベンチ外  3) なお足りなければ控えの OVR の低い順に自動で補う
  void refreshActive26() {
    final pmap = {for (final p in players) p.id: p};
    roster1G.removeWhere((id) => !pmap.containsKey(id));
    manualBenchOut.removeWhere((id) => !roster1G.contains(id) || activeRotation.contains(id));
    final need = benchOutNeeded;
    final today = todaysStarterId;
    final protected = <String>{
      ...lineup.map((l) => l.playerId),
      ...winningPattern.where((e) => e.isNotEmpty),
      if (today != null) today,
    };

    // 1) 今日投げない先発をベンチ外に。人数があふれたら（7人ローテ）明後日の先発をロング要員としてベンチに残す
    final resting = restingStarters.where((id) => roster1G.contains(id) && !protected.contains(id)).toList();
    final order = resting.length >= 2 ? [resting[0], ...resting.sublist(2), resting[1]] : resting;
    autoBenchOutRotation = order.take(need).toList();
    final out = <String>{...autoBenchOutRotation};

    // 2) 手動ベンチ外（スタメン等になった選手は選択から外す）。必要な人数を超えて選んでもよい（ベンチ入りが26人より少なくなる。
    //    控えを自動で起用されないようにするため）。ただし、ベンチの投手は今日の先発を含めて6人は残す
    manualBenchOut.removeWhere((id) => protected.contains(id));
    out.addAll(manualBenchOut);
    int benchPitchers() => roster1G.where((id) => !out.contains(id) && pmap[id]!.isPitcher).length;
    for (final id in manualBenchOut.reversed.toList()) {
      if (benchPitchers() >= 6) break;
      if (pmap[id]!.isPitcher) out.remove(id);
    }

    // 3) 不足分の自動補充（控え捕手は最低1人残す）
    autoBenchOutFill = [];
    if (out.length < need) {
      bool isCatcher(Player p) => !p.isPitcher && p.mainPosition == '捕手';
      final cands = roster1G.where((id) => !out.contains(id) && !protected.contains(id)).map((id) => pmap[id]!).toList()
        ..sort((a, b) => a.ovr.compareTo(b.ovr));
      for (final p in cands) {
        if (out.length >= need) break;
        if (isCatcher(p)) {
          final benchCatchers = roster1G.where((id) => !out.contains(id) && !lineup.any((l) => l.playerId == id)).map((id) => pmap[id]!).where(isCatcher).length;
          if (benchCatchers <= 1) continue;
        }
        out.add(p.id);
        autoBenchOutFill.add(p.id);
      }
    }

    // 外国人枠（ベンチ入りの上限はリーグ規定。初期は4人）: 超過した外国人をベンチ外にし、代わりに日本人をベンチへ戻す
    bool isForeign(String id) => pmap[id]!.foreignSlot;
    final foreignIn = roster1G.where((id) => !out.contains(id) && isForeign(id)).toList();
    final cap = LeagueRules.benchCap(999); // 外国人のベンチ入りの上限（リーグ規定。廃止なら制限なし）
    if (foreignIn.length > cap) {
      final extra = foreignIn.where((id) => !protected.contains(id)).toList()..sort((a, b) => pmap[a]!.ovr.compareTo(pmap[b]!.ovr));
      // 戻す候補: 自動補充 → 先発ローテ（登板が遠い順）→ 手動 の順で、日本人
      final back = [
        ...autoBenchOutFill.reversed,
        ...autoBenchOutRotation.reversed,
        ...manualBenchOut.reversed,
      ].where((id) => !isForeign(id)).toList();
      for (final id in extra.take(foreignIn.length - cap)) {
        if (back.isEmpty) break;
        final b = back.removeAt(0);
        out.remove(b);
        autoBenchOutFill.remove(b);
        autoBenchOutRotation.remove(b);
        out.add(id);
        autoBenchOutFill.add(id);
      }
    }

    active26 = roster1G.where((id) => !out.contains(id)).toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'year': year,
      'name': name,
      'shortName': shortName,
      'initialName': initialName,
      'league': league,
      if (stadiumId.isNotEmpty) 'stadium': stadiumId,
      if (prefecture.isNotEmpty) 'pref': prefecture,
      if (parkMods.isNotEmpty) 'parkMods': parkMods,
      if (uniformColor != 0) 'uniColor': uniformColor,
      if (logoText.isNotEmpty) 'logo': logoText,
      if (parkWorkYear != 0) 'parkWorkYear': parkWorkYear,
      'players': players.map((p) => p.toJson()).toList(),
      'roster1G': roster1G,
      'rotation': rotation,
      'rotationCount': rotationCount,
      'winningPattern': winningPattern,
      'rotationIndex': rotationIndex,
      'lineup': lineup.map((l) => l.toJson()).toList(),
      'wins': wins,
      'losses': losses,
      'draws': draws,
      'useDH': useDH,
      'active26': active26,
      'manualBenchOut': manualBenchOut,
      if (protectList.isNotEmpty) 'protectList': protectList,
      'springCamp': springCamp,
      'autumnCamp': autumnCamp,
      'thirdPriority': thirdPriority,
      'thirdLineup': thirdLineup,
      'thirdAuto': thirdAuto,
      'farmAuto': farmAuto,
      'farmLineup': farmLineup.map((l) => l.toJson()).toList(),
      'farmRotation': farmRotation,
      'farmRotationIndex': farmRotationIndex,
      if (farmRotationCount != farmRotationSize) 'farmRotN': farmRotationCount,
    };
  }

  factory Team.fromJson(Map<String, dynamic> json, Function playerFromJson) {
    // 旧セーブ（setup/closer/closer2）からの移行: 7回=closer2、8回=setup、9回=closer
    List<String>? pattern = json['winningPattern'] != null ? List<String>.from(json['winningPattern']) : null;
    pattern ??= [json['closer2'] ?? '', json['setup'] ?? '', json['closer'] ?? ''].map((e) => '$e').toList();
    final team = Team(
      id: json['id'],
      year: json['year'] ?? 2026,
      name: json['name'],
      shortName: json['shortName'] ?? '',
      initialName: json['initialName'] ?? '',
      league: json['league'],
      players: (json['players'] as List).map((p) => playerFromJson(p) as Player).toList(),
      roster1G: List<String>.from(json['roster1G'] ?? []),
      rotation: List<String>.from(json['rotation'] ?? []),
      winningPattern: pattern,
      rotationCount: json['rotationCount'] ?? 6,
      rotationIndex: json['rotationIndex'] ?? 0,
      lineup: (json['lineup'] as List?)?.map((l) => LineupEntry.fromJson(l)).toList() ?? [],
      wins: json['wins'] ?? 0,
      losses: json['losses'] ?? 0,
      draws: json['draws'] ?? 0,
      useDH: json['useDH'] ?? true,
      active26: List<String>.from(json['active26'] ?? []),
      manualBenchOut: List<String>.from(json['manualBenchOut'] ?? []),
      protectList: List<String>.from(json['protectList'] ?? []),
      springCamp: List<String>.from(json['springCamp'] ?? []),
      autumnCamp: List<String>.from(json['autumnCamp'] ?? []),
      thirdPriority: List<String>.from(json['thirdPriority'] ?? []),
      thirdLineup: List<String>.from(json['thirdLineup'] ?? []),
      thirdAuto: json['thirdAuto'] ?? true,
      farmAuto: json['farmAuto'] ?? true,
      farmLineup: (json['farmLineup'] as List?)?.map((l) => LineupEntry.fromJson(l)).toList() ?? [],
      farmRotation: List<String>.from(json['farmRotation'] ?? []),
      farmRotationIndex: json['farmRotationIndex'] ?? 0,
      farmRotationCount: ((json['farmRotN'] ?? farmRotationSize) as num).toInt().clamp(farmRotationMin, farmRotationMax),
    );
    team.stadiumId = json['stadium'] ?? '';
    team.prefecture = json['pref'] ?? '';
    team.parkMods = Map<String, dynamic>.from(json['parkMods'] ?? {});
    team.uniformColor = json['uniColor'] ?? 0;
    team.logoText = json['logo'] ?? '';
    team.parkWorkYear = json['parkWorkYear'] ?? 0;
    team.autoFillPitchingStaff();
    if (team.roster1G.isNotEmpty) team.refreshActive26();
    return team;
  }
}
