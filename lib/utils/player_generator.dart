import 'dart:math';
import '../engine/velo.dart';
import '../engine/pitch_catalog.dart';
import '../engine/fielding_gen.dart';
import '../models/player.dart';
import '../models/team.dart';
import 'name_pool.dart';
import 'player_traits.dart';

// 新規チームの自動生成。
//  - チーム名はランダム
//  - 選手の能力は平均60（OVR平均60）、年齢は平均27
//  - 構成: 投手35名 + 野手8ポジション×4名 = 67名。守備適性は全位置60、メインポジションを明示
//  - 投手の変化球は ストレート・スライダー・カーブ・フォーク の4種（Playerの初期値）

final Random _rnd = Random();

const _places = ['札幌', '仙台', '東京', '横浜', '名古屋', '大阪', '京都', '神戸', '広島', '福岡', '那覇', '金沢', '新潟', '静岡', '岡山', '熊本', '長野', '高松'];
const _nicknames = ['ライオンズ', 'ホークス', 'ドラゴンズ', 'スパークス', 'ブレイブス', 'サンダース', 'フェニックス', 'ウルブズ', 'コメッツ', 'ファルコンズ', 'バイソンズ', 'オーシャンズ', 'ジェッツ', 'タイガース', 'マリナーズ', 'ナイツ'];

double _gauss() {
  final u1 = 1.0 - _rnd.nextDouble();
  final u2 = _rnd.nextDouble();
  return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
}

/// 平均mean・標準偏差sdの整数能力（20〜99に収める）
int _stat(double mean, double sd) => (mean + _gauss() * sd).round().clamp(20, 99);

String _id(int n) => 'P_${DateTime.now().microsecondsSinceEpoch}_$n';

const _allPositions = ['捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手'];

/// 生成年(year)時点の年齢から、来歴・プロ年数・生年月日を決める
void _setAge(Player p, int age, int year) {
  p.age = age;
  if (age <= 22) {
    p.draftType = 'A'; // 高卒ドラフト（1年目19歳）
  } else {
    p.draftType = ['A', 'B', 'B', 'C'][_rnd.nextInt(4)];
  }
  final base = p.draftType == 'A' ? 19 : (p.draftType == 'B' ? 23 : p.draftCustomAge);
  p.proYears = max(1, age - base + 1);
  final month = (1 + _rnd.nextInt(12)).toString().padLeft(2, '0');
  final day = (1 + _rnd.nextInt(28)).toString().padLeft(2, '0');
  p.birthDate = '${year - age}-$month-$day';
}

Player _basePlayer({required bool isPitcher, required int index, required String mainPos, required int year, required int number}) {
  final age = (27 + _gauss() * 4).round().clamp(19, 40);
  final bats = ['R', 'R', 'L', 'S'][_rnd.nextInt(4)];
  final traj = [1, 2, 2, 2, 2, 2, 3, 3, 3, 4][_rnd.nextInt(10)];
  Player p;
  if (isPitcher) {
    final velNorm = _stat(60, 9);
    p = Player(
      id: _id(index),
      isPitcher: true,
      uniformNumber: number,
      mainPos: '投手',
      bats: bats,
      throws: _rnd.nextInt(4) == 0 ? 'L' : 'R',
      height: 170 + _rnd.nextInt(25),
      nationality: _rnd.nextInt(10) == 0 ? '海外' : '日本',
      trajectory: 1,
      contactLeft: _stat(30, 6), contactRight: _stat(30, 6), power: _stat(30, 6), run: _stat(40, 8),
      arm: _stat(60, 8), throwAccuracy: _stat(60, 8), catchSkill: _stat(60, 8), eye: _stat(30, 6), clutch: _stat(50, 8),
      fieldP: 60, fieldC: 60, field1B: 60, field2B: 60, field3B: 60, fieldSS: 60, fieldLF: 60, fieldCF: 60, fieldRF: 60,
      velocity: 120 + velNorm ~/ 2,
      pitchPower: _stat(60, 8), control: _stat(60, 8), stamina: _stat(60, 8), clutchPitching: _stat(60, 8),
      // pitches を渡さない → Player の初期値（ストレート・スライダー・カーブ・フォークの4種）
    );
  } else {
    final contact = _stat(60, 8);
    p = Player(
      id: _id(index),
      isPitcher: false,
      uniformNumber: number,
      mainPos: mainPos,
      bats: bats,
      throws: bats == 'L' && _rnd.nextBool() ? 'L' : 'R',
      height: 168 + _rnd.nextInt(25),
      nationality: _rnd.nextInt(10) == 0 ? '海外' : '日本',
      trajectory: traj,
      contactLeft: (contact + _gauss() * 3).round().clamp(20, 99), contactRight: (contact + _gauss() * 3).round().clamp(20, 99),
      power: _stat(60, 8), run: _stat(60, 8), arm: _stat(60, 8), throwAccuracy: _stat(60, 8), catchSkill: _stat(60, 8),
      eye: _stat(60, 8), clutch: _stat(60, 8),
      fieldP: 60, fieldC: 60, field1B: 60, field2B: 60, field3B: 60, fieldSS: 60, fieldLF: 60, fieldCF: 60, fieldRF: 60,
      velocity: 130, pitchPower: 20, control: 20, stamina: 20,
    );
  }
  _setAge(p, age, year);
  FieldingGen.apply(p, _rnd); // 守備適性（オールCではなく、本職の型に合わせる）
  if (isPitcher) p.pitches = PitchCatalog.generate(p, _rnd); // 持ち球は38種から
  assignTraits(p, _rnd); // 体力・回復力・怪我しにくさ・信頼・調子の波・成長タイプ・年俸
  Velo.liftNew(p); // 球速の基準（2026-11）：プロの水準に底上げ
  return p;
}

/// 選手リストからスタメン・先発6・勝利の方程式3・ベンチ入り26・1軍31を自動編成する
void autoAssignTeam(Team t) {
  const posKeys = ['捕', '一', '二', '三', '遊', '左', '中', '右'];
  final fielders = t.players.where((p) => !p.isPitcher).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
  final pitchers = t.players.where((p) => p.isPitcher).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));

  final used = <String>{};
  final lineup = <LineupEntry>[];
  for (var i = 0; i < 8; i++) {
    final c = fielders.firstWhere((p) => p.mainPos == _allPositions[i] && !used.contains(p.id), orElse: () => fielders.firstWhere((p) => !used.contains(p.id)));
    used.add(c.id);
    lineup.add(LineupEntry(playerId: c.id, position: posKeys[i]));
  }
  final dh = fielders.firstWhere((p) => !used.contains(p.id));
  used.add(dh.id);
  lineup.add(LineupEntry(playerId: dh.id, position: 'DH'));
  t.lineup = lineup;

  // 投手: 先発6（スタミナ重視で上位）、勝利の方程式3、控え4
  final starters = (List.of(pitchers)..sort((a, b) => (b.ovr + b.stamina ~/ 2).compareTo(a.ovr + a.stamina ~/ 2))).take(6).toList();
  final sid = starters.map((p) => p.id).toSet();
  final rest = pitchers.where((p) => !sid.contains(p.id)).toList();
  t.rotation = starters.map((p) => p.id).toList();
  t.winningPattern = [rest[2].id, rest[1].id, rest[0].id]; // 7回・8回・9回（9回が最も強い）
  t.rotationIndex = 0;
  t.rotationCount = 6;
  final pids = <String>{...t.activeRotation, ...t.winningPattern}..remove('');
  for (final p in rest) {
    if (pids.length >= 18) break;
    pids.add(p.id);
  }

  final fids = <String>{...lineup.map((l) => l.playerId)};
  final backupC = fielders.where((p) => p.mainPos == '捕手' && !fids.contains(p.id));
  if (backupC.isNotEmpty) fids.add(backupC.first.id);
  for (final p in fielders) {
    if (fids.length >= 13) break;
    fids.add(p.id);
  }
  // 1軍31人 = 投手18（先発6＋方程式3＋中継ぎ9）＋野手13。
  // 今日投げない先発5人が自動でベンチ外になり、ベンチ入りは投手13＋野手13になる
  final first = <String>{...pids, ...fids};
  for (final p in fielders) {
    if (first.length >= 31) break;
    first.add(p.id);
  }
  t.roster1G = first.toList();
  t.manualBenchOut = [];
  t.refreshActive26();
}

/// 新規チームを自動生成する（名前ランダム・OVR平均60・年齢平均27）
Team generateNewTeam({required int year, String league = ''}) {
  final players = <Player>[];
  var number = 1;
  for (var i = 0; i < 35; i++) {
    players.add(_basePlayer(isPitcher: true, index: i, mainPos: '投手', year: year, number: number++));
  }
  for (final pos in _allPositions) {
    for (var i = 0; i < 4; i++) {
      players.add(_basePlayer(isPitcher: false, index: players.length, mainPos: pos, year: year, number: number++));
    }
  }
  NamePool.assignTeam(players, _rnd);
  final place = _places[_rnd.nextInt(_places.length)];
  final nick = _nicknames[_rnd.nextInt(_nicknames.length)];
  final team = Team(
    id: 'T_${DateTime.now().millisecondsSinceEpoch}_${_rnd.nextInt(1000)}',
    name: '$place$nick',
    shortName: place,
    initialName: place.substring(0, 1),
    year: year,
    league: league,
    players: players,
  );
  autoAssignTeam(team);
  return team;
}

/// 後方互換: 選手リストのみ生成
List<Player> generateDummyTeamPlayers() => generateNewTeam(year: 2026).players;
