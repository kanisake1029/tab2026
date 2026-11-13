import 'dart:math' show max;
// 能力値を指定したチーム同士で試合を大量に回して、バランスを数値で確認するツール。
// セーブデータには一切触れない（メモリ上で専用チームを作るだけ）。
// 実行: dart run tool/balance_sim.dart [試合数] [ホーム野手の能力値=60] [アウェイ投手の能力値=60]
//   例) dart run tool/balance_sim.dart 143 80 60  → 全能力80の野手 vs 全能力60の投手（ホーム野手の1人あたり成績を表示）
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';

int _traj = 2; // ホーム野手の弾道（traj=N で変更）
int _base = 65; // 基準OVR（一軍同士=65前後をNPB平均に校正）。args に base=NN で変更
String _only = 'all'; // 'all' 以外なら、その能力(power/contact/eye/run/field)だけ指定値にして他は60
int? _powerOv;
int _v(String attr, int lv) => attr == 'power' && _powerOv != null ? _powerOv! : (_only == 'all' || _only == attr || (_only == 'defense' && const {'field', 'catch', 'run', 'arm', 'throw'}.contains(attr))) ? lv : _base;

Player _fielder(String id, int lv) => Player(
      id: id, isPitcher: false, lastName: id,
      trajectory: _traj, contactLeft: _v('contact', lv), contactRight: _v('contact', lv), power: _v('power', lv), run: _v('run', lv),
      arm: _v('arm', lv), throwAccuracy: _v('throw', lv), catchSkill: _v('catch', lv), eye: _v('eye', lv), clutch: _v('clutch', lv),
      fieldP: _v('field', lv), fieldC: _v('field', lv), field1B: _v('field', lv), field2B: _v('field', lv), field3B: _v('field', lv),
      fieldSS: _v('field', lv), fieldLF: _v('field', lv), fieldCF: _v('field', lv), fieldRF: _v('field', lv),
    );

String _pitchSet = 'std';
List<Pitch>? _customPitches(int v, int lv) {
  switch (_pitchSet) {
    case 'knuckle': return [Pitch(name: 'ナックル', breakLevel: 100, angle: 270, speed: 105, ratio: 100, sharpness: 100, heaviness: 100)];
    case 'extreme': return [Pitch(name: '魔球', breakLevel: 999, angle: 33, speed: 400, ratio: 50, sharpness: 999, heaviness: 100), Pitch(name: '超スロー', breakLevel: -50, angle: 500, speed: 20, ratio: 50, sharpness: -10, heaviness: 0)];
    case 'single': return [Pitch(name: 'ストレート', breakLevel: 0, angle: 90, speed: v, ratio: 100, sharpness: lv, heaviness: lv)];
    case 'empty': return [];
    case 'zero': return [Pitch(name: 'ゼロ', breakLevel: 0, angle: 0, speed: v, ratio: 0, sharpness: lv, heaviness: lv)];
  }
  return null;
}

Player _pitcher(String id, int lv) {
  final v = 120 + lv ~/ 2; // velocityNorm = (v-120)*2 → 60で150km/h, 80で160km/h
  return Player(
    id: id, isPitcher: true, lastName: id,
    velocity: v, pitchPower: lv, control: lv, stamina: lv,
    clutchPitching: lv, spinAxis: 45,
    run: 60, arm: 60, throwAccuracy: 60, catchSkill: 60, fieldP: 60,
    pitches: _customPitches(v, lv) ?? [
      Pitch(name: 'ストレート', breakLevel: 0, angle: 90, speed: v, ratio: 45, sharpness: lv, heaviness: lv),
      Pitch(name: 'スライダー', breakLevel: lv, angle: 180, speed: v - 15, ratio: 25, sharpness: lv, heaviness: lv),
      Pitch(name: 'カーブ', breakLevel: lv, angle: 135, speed: v - 30, ratio: 15, sharpness: lv, heaviness: lv),
      Pitch(name: 'フォーク', breakLevel: lv, angle: 90, speed: v - 20, ratio: 15, sharpness: lv, heaviness: lv),
    ],
  );
}

Team _team(String id, int batLv, int pitLv) {
  const positions = ['中', '二', '遊', '一', '三', '左', '右', '捕', 'DH'];
  final players = <Player>[];
  final lineup = <LineupEntry>[];
  for (var i = 0; i < 9; i++) {
    final p = _fielder('$id-B$i', batLv);
    players.add(p);
    lineup.add(LineupEntry(playerId: p.id, position: positions[i]));
  }
  final sp = _pitcher('$id-P', pitLv);
  players.add(sp);
  return Team(id: id, name: id, league: 'CL', players: players, lineup: lineup, rotation: [sp.id]);
}

void main(List<String> rawArgs) {
  final args = <String>[];
  for (final a in rawArgs) { if (a.startsWith('base=')) { _base = int.parse(a.substring(5)); } else if (a.startsWith('traj=')) { _traj = int.parse(a.substring(5)); } else if (a.startsWith('cut=')) { MatchSimulator.cutBase = double.parse(a.substring(4)); } else if (a.startsWith('fpt=')) { MatchSimulator.firstPitchTake = double.parse(a.substring(4)); } else if (a.startsWith('fb=')) { MatchSimulator.foulBase = double.parse(a.substring(3)); } else if (a.startsWith('ce=')) { MatchSimulator.contactEase = double.parse(a.substring(3)); } else { args.add(a); } }
  if (args.length > 3) _only = args[3];
  if (args.length > 4) _pitchSet = args[4];
  if (args.length > 5) _powerOv = int.parse(args[5]); // パワーだけ別の値にする
  final games = args.isNotEmpty ? int.parse(args[0]) : 200;
  final homeBat = args.length > 1 ? int.parse(args[1]) : _base;
  final awayPit = args.length > 2 ? int.parse(args[2]) : _base;
  final sim = MatchSimulator(applyForm: false);
  MatchSimulator.startStats();
  int aAb = 0, aH = 0;
  int hAb = 0, hH = 0, hHr = 0, hBb = 0, hSo = 0, pEr = 0, pOuts = 0, pSo = 0, pBb = 0;
  int runs = 0, hits = 0, ab = 0, hr = 0, so = 0, bb = 0, pitches = 0, pa = 0;
  int extra = 0, draws = 0;
  final hitTypes = <String, int>{'ヒット': 0, 'ツーベース': 0, 'スリーベース': 0, 'ホームラン': 0};

  for (var g = 0; g < games; g++) {
    final home = _team('H', homeBat, _base), away = _team('A', _base, awayPit);
    final m = Match(homeTeamId: 'H', awayTeamId: 'A', date: DateTime(2026, 4, 1), matchType: 'regular');
    final r = sim.simulateMatch(m, home, away);
    runs += r.homeScore + r.awayScore;
    hits += r.homeHits + r.awayHits;
    if (r.homeScore == r.awayScore) draws++;
    for (final line in r.pitchByPitch) {
      pitches++;
      if (line.contains('スリーベース')) hitTypes['スリーベース'] = hitTypes['スリーベース']! + 1;
      else if (line.contains('ツーベース')) hitTypes['ツーベース'] = hitTypes['ツーベース']! + 1;
      else if (line.contains('ホームラン')) hitTypes['ホームラン'] = hitTypes['ホームラン']! + 1;
      else if (line.contains('ヒット') || line.contains('内野安打')) hitTypes['ヒット'] = hitTypes['ヒット']! + 1;
    }
    for (final t in [home, away]) {
      for (final p in t.players) {
        final s = p.seasonStats;
        if (!p.isPitcher) { ab += s.atBats; hr += s.homeRuns; so += s.strikeouts; bb += s.walks; }
      }
    }
    for (final p in home.players.where((p) => !p.isPitcher)) { final s = p.seasonStats; hAb += s.atBats; hH += s.hits; hHr += s.homeRuns; hBb += s.walks; hSo += s.strikeouts; }
    for (final p in away.players.where((p) => !p.isPitcher)) { aAb += p.seasonStats.atBats; aH += p.seasonStats.hits; }
    final ap = away.players.firstWhere((p) => p.isPitcher).seasonStats; pEr += ap.earnedRuns; pOuts += ap.inningsPitched; pSo += ap.pitcherStrikeouts; pBb += ap.pitcherWalks;
    if (r.homeInningScores.length > 9 || r.awayInningScores.length > 9) extra++;
  }
  pa = ab + bb;
  String f(num v, [int d = 2]) => v.toStringAsFixed(d);
  print('==== オール$_base バランス検査（$games試合） ====');
  print('1試合あたり 得点 ${f(runs / games / 2)} / 安打 ${f(hits / games / 2)} / 本塁打 ${f(hr / games / 2)}  (1チーム)');
  print('1試合あたり 三振 ${f(so / games / 2)} / 四球 ${f(bb / games / 2)}  (1チーム)');
  print('打率 ${f(hits / (ab == 0 ? 1 : ab), 3)}   1打席あたり球数 ${f(pitches / (pa == 0 ? 1 : pa))}');
  print('安打内訳 $hitTypes');
  final d = MatchSimulator.debugStats; final sw = d['swings'] ?? 1; final pt = d['pitches'] ?? 1;
  print('ボール球率 ${f((d['ballPitches'] ?? 0) / pt * 100, 1)}% / ボール球スイング率 ${f((d['ballSwings'] ?? 0) / (d['ballPitches'] ?? 1) * 100, 1)}% / ゾーン内スイング率 ${f((d['zoneSwings'] ?? 0) / (d['zonePitches'] ?? 1) * 100, 1)}%');
  print('スイング中: 空振り ${f((d['whiffs'] ?? 0) / sw * 100, 1)}% / ファウル ${f((d['fouls'] ?? 0) / sw * 100, 1)}% / インプレー ${f((d['inplay'] ?? 0) / sw * 100, 1)}%');
  print('打球別 安打率(BABIP): ' + ['ゴロ', 'ライナー', 'フライ', 'ポップフライ'].map((t) => '$t ${d['bip_$t'] ?? 0}本/${f((d['hit_$t'] ?? 0) / (d['bip_$t'] ?? 1) * 100, 0)}%').join(' / '));
  String pct(String a, String b) => '${f((d[a] ?? 0) / max(1, d[b] ?? 0) * 100, 0)}%';
  print('併殺 ${f((d['dp'] ?? 0) / games / 2)} / 内野安打 ${f((d['infieldHit'] ?? 0) / games / 2)} / 走塁死(送球) ${f((d['runnerThrownOut'] ?? 0) / games / 2)} / 犠飛 ${f((d['sacFly'] ?? 0) / games / 2)}  (1チーム1試合)');
  print('単打で二塁走者生還 ${pct('r2ScoredOnSingle', 'r2OnSingle')} / 単打で一塁走者三塁へ ${pct('r1ToThirdOnSingle', 'r1OnSingle')} / 二塁打で一塁走者生還 ${pct('r1ScoredOnDouble', 'r1OnDouble')}');
  print('打たれたイニングの投球（スタミナ1.5倍）の割合 ${f((d['staminaRoughedPitches'] ?? 0) / pt * 100, 1)}%');
  print('引き分け $draws / イニング配列が9超え $extra / アウェイ先発の平均投球回 ${f(pOuts / games / 3, 2)}');
  if (homeBat != _base || awayPit != _base) {
    final pa = hAb + hBb;
    print('【ホーム野手 能力$homeBat 1人あたり（143試合換算）】 打率 ${f(hH / hAb, 3)} / 本塁打 ${f(hHr / games / 9 * 143, 1)} / 四球 ${f(hBb / games / 9 * 143, 0)} / 三振 ${f(hSo / games / 9 * 143, 0)} / 打席 ${f(pa / games / 9 * 143, 0)}  出塁率 ${f((hH + hBb) / pa, 3)}');
    print('【アウェイ野手の打率（ホーム守備力の影響）】 ${f(aH / aAb, 3)}');
    print('【アウェイ投手 能力$awayPit】 防御率 ${f(pEr * 27 / pOuts, 2)} / 奪三振率 ${f(pSo * 27 / pOuts, 1)} / 与四球率 ${f(pBb * 27 / pOuts, 1)} / 平均投球回 ${f(pOuts / games / 3, 1)}');
  }
  print('---- NPB目安: 得点3.5-4 / 安打8 / 本塁打0.8 / 三振7-8 / 四球3 / 打率.250 / 球数3.8 ----');
}
