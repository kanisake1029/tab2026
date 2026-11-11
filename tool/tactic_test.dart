// 采配（打撃・走塁・投手・守備）の効果測定
//  攻撃系: アウェイ攻撃時に「状況が合うとき毎回」その作戦を使い、アウェイ得点の変化を見る
//  守備系: アウェイが守備のとき（=ホーム攻撃時）に毎回その作戦を使い、ホーム得点の変化を見る
// 実行: dart run tool/tactic_test.dart [試合数]
import 'dart:io';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/fielder_ai.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';

final int _pow = int.tryParse(Platform.environment['POWER'] ?? '') ?? 65; // 打者のパワー（POWER=85 で引っ張りの強打者）
Player _b(String id, int lv) => Player(id: id, isPitcher: false, lastName: id, trajectory: 2, contactLeft: lv, contactRight: lv, power: _pow, run: lv, arm: lv, throwAccuracy: lv, catchSkill: lv, eye: lv, clutch: lv, fieldP: lv, fieldC: lv, field1B: lv, field2B: lv, field3B: lv, fieldSS: lv, fieldLF: lv, fieldCF: lv, fieldRF: lv);
Player _p(String id, int lv) => Player(id: id, isPitcher: true, lastName: id, velocity: 120 + lv ~/ 2, pitchPower: lv, control: lv, stamina: lv, clutchPitching: lv, spinAxis: 45, run: 60, arm: 60, throwAccuracy: 60, catchSkill: 60, fieldP: 60);

Team _team(String id) {
  const pos = ['中', '二', '遊', '一', '三', '左', '右', '捕', 'DH'];
  final ps = <Player>[];
  final l = <LineupEntry>[];
  for (var i = 0; i < 9; i++) {
    final p = _b('$id-B$i', 65);
    ps.add(p);
    l.add(LineupEntry(playerId: p.id, position: pos[i]));
  }
  final sp = _p('$id-P', 65);
  ps.add(sp);
  return Team(id: id, name: id, league: 'CL', players: ps, lineup: l, rotation: [sp.id]);
}

class Scenario {
  final String label;
  final bool attack; // true=アウェイ攻撃に適用 / false=アウェイ守備(ホーム攻撃)に適用
  final AtBatPlan plan;
  final bool Function(MatchState) when;
  Scenario(this.label, this.attack, this.plan, this.when);
}

bool _any(MatchState s) => true;
bool _r1(MatchState s) => s.runner1B != null && s.outs < 2;
bool _r13orR23(MatchState s) => (s.runner2B != null || s.runner3B != null) && s.outs < 2;
bool _r3(MatchState s) => s.runner3B != null && s.outs < 2;
bool _r12(MatchState s) => (s.runner1B != null || s.runner2B != null) && s.runner3B == null && s.outs < 2;
bool _steal(MatchState s) => (s.runner1B != null && s.runner2B == null) || (s.runner2B != null && s.runner3B == null);
bool _hr(MatchState s) => s.runner1B != null && s.runner2B == null && s.outs < 2;
bool _anyRunner(MatchState s) => s.runner1B != null || s.runner2B != null || s.runner3B != null;

class Stat {
  double runs = 0, hits = 0, bb = 0, so = 0;
  int n = 0;
  Map<String, int> dbg = {};
}

Stat run(Scenario? sc, int games) {
  final sim = MatchSimulator(applyForm: false);
  final st = Stat();
  for (var g = 0; g < games; g++) {
    final h = _team('H'), a = _team('A');
    final s = sim.startGame(Match(homeTeamId: 'H', awayTeamId: 'A', date: DateTime(2026, 4, 1), matchType: 'regular'), h, a);
    while (!sim.isFinished(s)) {
      final m = s.state;
      var plan = const AtBatPlan();
      if (sc != null) {
        if (sc.attack && m.isTop && sc.when(m)) plan = sc.plan;
        if (!sc.attack && !m.isTop && sc.when(m)) plan = sc.plan;
      }
      sim.stepPlateAppearance(s, plan: plan);
    }
    final r = sim.finishGame(s);
    final attack = sc == null || sc.attack;
    st.runs += attack ? r.awayScore : r.homeScore;
    st.hits += attack ? r.awayHits : r.homeHits;
    final batters = attack ? a : h;
    for (final p in batters.players.where((p) => !p.isPitcher)) {
      st.bb += p.seasonStats.walks;
      st.so += p.seasonStats.strikeouts;
    }
    st.n++;
  }
  st.dbg = sim.debugStats;
  return st;
}

void main(List<String> args) {
  final ant = Platform.environment['ANT'];
  if (ant != null) FielderAI.shiftAnticipation = double.parse(ant);
  final sh = Platform.environment['SHIFT']; // 例 SHIFT=3,-5,-20,-5,-4  (3B,SS,2B,1B,外野)
  if (sh != null) { final v = sh.split(',').map(double.parse).toList(); FielderAI.shiftLeftDeg = {'3B': v[0], 'SS': v[1], '2B': v[2], '1B': v[3], 'LF': v[4], 'CF': v[4], 'RF': v[4]}; }
  final n = args.isNotEmpty ? int.parse(args[0]) : 300;
  final base = run(null, n);
  String f(double v) => (v / n).toStringAsFixed(2);
  print('基準(作戦なし)           得点 ${f(base.runs)}  安打 ${f(base.hits)}  四球 ${f(base.bb)}  三振 ${f(base.so)}');
  final scenarios = <Scenario>[
    Scenario('【打撃】右狙い             ', true, const AtBatPlan(bat: BatTactic.pullRight), _r13orR23),
    Scenario('【打撃】送りバント        ', true, const AtBatPlan(bat: BatTactic.bunt), _r12),
    Scenario('【打撃】スクイズ          ', true, const AtBatPlan(bat: BatTactic.squeeze), _r3),
    Scenario('【打撃】強振(常時)        ', true, const AtBatPlan(bat: BatTactic.powerSwing), _any),
    Scenario('【打撃】ミート打ち(常時)  ', true, const AtBatPlan(bat: BatTactic.contactSwing), _any),
    Scenario('【打撃】流し打ち(常時)    ', true, const AtBatPlan(bat: BatTactic.oppositeField), _any),
    Scenario('【打撃】引っ張り(常時)    ', true, const AtBatPlan(bat: BatTactic.pullHit), _any),
    Scenario('【読み】引っ張りシフト×通常打撃', true, const AtBatPlan(field: FieldTactic.pullShift), _any),
    Scenario('【読み】引っ張りシフト×流し打ち', true, const AtBatPlan(bat: BatTactic.oppositeField, field: FieldTactic.pullShift), _any),
    Scenario('【読み】引っ張りシフト×引っ張り', true, const AtBatPlan(bat: BatTactic.pullHit, field: FieldTactic.pullShift), _any),
    Scenario('【読み】流し警戒×通常打撃    ', true, const AtBatPlan(field: FieldTactic.oppositeShift), _any),
    Scenario('【読み】流し警戒×引っ張り    ', true, const AtBatPlan(bat: BatTactic.pullHit, field: FieldTactic.oppositeShift), _any),
    Scenario('【読み】流し警戒×流し打ち    ', true, const AtBatPlan(bat: BatTactic.oppositeField, field: FieldTactic.oppositeShift), _any),
    Scenario('【打撃】叩きつけ(三塁)    ', true, const AtBatPlan(bat: BatTactic.chopDown), _r3),
    Scenario('【打撃】初球から積極的    ', true, const AtBatPlan(bat: BatTactic.firstPitch), _any),
    Scenario('【打撃】外野フライ狙い    ', true, const AtBatPlan(bat: BatTactic.flyBall), _r3),
    Scenario('【打撃】粘れ(常時)        ', true, const AtBatPlan(bat: BatTactic.patient), _any),
    Scenario('【打撃】低め狙い(常時)    ', true, const AtBatPlan(bat: BatTactic.lowBall), _any),
    Scenario('【打撃】ストレート狙い    ', true, const AtBatPlan(bat: BatTactic.fastballFocus), _any),
    Scenario('【走塁】盗塁              ', true, const AtBatPlan(run: RunTactic.steal), _steal),
    Scenario('【走塁】ヒットエンドラン  ', true, const AtBatPlan(run: RunTactic.hitAndRun), _hr),
    Scenario('【走塁】積極走塁          ', true, const AtBatPlan(run: RunTactic.aggressive), _anyRunner),
    Scenario('【走塁】慎重走塁          ', true, const AtBatPlan(run: RunTactic.cautious), _anyRunner),
    Scenario('【投手】打たせて取る      ', false, const AtBatPlan(pitch: PitchTactic.groundOut), _any),
    Scenario('【投手】三振狙い          ', false, const AtBatPlan(pitch: PitchTactic.strikeout), _any),
    Scenario('【投手】全力投球          ', false, const AtBatPlan(pitch: PitchTactic.fullPower), _any),
    Scenario('【投手】コントロール重視  ', false, const AtBatPlan(pitch: PitchTactic.controlFocus), _any),
    Scenario('【投手】内角攻め          ', false, const AtBatPlan(pitch: PitchTactic.insideAttack), _any),
    Scenario('【投手】外角中心          ', false, const AtBatPlan(pitch: PitchTactic.outsideFocus), _any),
    Scenario('【投手】直球中心          ', false, const AtBatPlan(pitch: PitchTactic.fastballMain), _any),
    Scenario('【投手】変化球中心        ', false, const AtBatPlan(pitch: PitchTactic.breakingMain), _any),
    Scenario('【投手】併殺狙い          ', false, const AtBatPlan(pitch: PitchTactic.doublePlay), _r1),
    Scenario('【投手】敬遠(一塁空き時)    ', false, const AtBatPlan(pitch: PitchTactic.intentionalWalk), (m) => m.runner1B == null),
    Scenario('【投手】外角低めへ指定    ', false, const AtBatPlan(targetCol: 2, targetRow: 0), _any),
    Scenario('【投手】真ん中高めへ指定  ', false, const AtBatPlan(targetCol: 1, targetRow: 2), _any),
    Scenario('【守備】長打警戒          ', false, const AtBatPlan(field: FieldTactic.powerGuard), _any),
    Scenario('【守備】前進守備          ', false, const AtBatPlan(field: FieldTactic.infieldIn), _r3),
    Scenario('【守備】併殺シフト        ', false, const AtBatPlan(field: FieldTactic.doublePlayShift), _r1),
    Scenario('【守備】内野後方          ', false, const AtBatPlan(field: FieldTactic.infieldBack), _any),
  ];
  // 守備系は「ホームの攻撃」の基準が別なので、基準もホーム得点で出す
  final baseHome = () {
    final sim = MatchSimulator(applyForm: false);
    double runs = 0, hits = 0, bb = 0, so = 0;
    for (var g = 0; g < n; g++) {
      final h = _team('H'), a = _team('A');
      final r = sim.simulateMatch(Match(homeTeamId: 'H', awayTeamId: 'A', date: DateTime(2026, 4, 1), matchType: 'regular'), h, a);
      runs += r.homeScore;
      hits += r.homeHits;
      for (final p in h.players.where((p) => !p.isPitcher)) { bb += p.seasonStats.walks; so += p.seasonStats.strikeouts; }
    }
    return [runs, hits, bb, so];
  }();
  print('基準(ホーム攻撃側)       得点 ${f(baseHome[0])}  安打 ${f(baseHome[1])}  四球 ${f(baseHome[2])}  三振 ${f(baseHome[3])}');
  final filter = args.length > 1 ? args[1] : '';
  for (final sc in scenarios) {
    if (filter.isNotEmpty && !sc.label.contains(filter)) continue;
    final r = run(sc, n);
    final b = sc.attack ? [base.runs, base.hits, base.bb, base.so] : baseHome;
    String d(double v, double bv) => '${v / n >= bv / n ? '+' : ''}${((v - bv) / n).toStringAsFixed(2)}';
    final extra = <String>[];
    for (final k in ['bunts', 'buntSuccess', 'squeezes', 'squeezeSuccess', 'steals', 'stealSuccess']) {
      if ((r.dbg[k] ?? 0) > 0) extra.add('$k ${r.dbg[k]}');
    }
    print('${sc.label} 得点 ${f(r.runs)}(${d(r.runs, b[0])})  安打 ${f(r.hits)}  四球 ${f(r.bb)}  三振 ${f(r.so)}  ${extra.join(' ')}');
  }
}
