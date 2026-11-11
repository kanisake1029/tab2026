import 'dart:math';
import 'velo.dart';
import '../models/player.dart';
import '../models/team.dart';
import 'growth_curve.dart';

/// 成長フェーズ。早熟・普通・晩成は「全盛期がいつ来るか」を決める
enum GrowthPhase {
  developing('育成期', 1.3),
  rising('成長期', 1.5),
  prime('全盛期', 0.6),
  transition('過渡期', 0.3),
  decline('衰退期', 0.15);

  final String label;
  final double expMultiplier;
  const GrowthPhase(this.label, this.expMultiplier);
}

/// EXP の対象になる能力1つ
class GrowthStat {
  final String key;
  final String label;
  final String group; // bat / field / pitch / body
  final int Function(Player) get;
  final void Function(Player, int) set;
  final int min;
  final int max;
  final int step; // 1段階で変わる量（体力は6）
  final double weight; // 入る経験値の割合（1.0。サブの守備位置だけ 0.5）
  final int base; // 値60のとき +1 に要る経験値
  final double curve; // 伸びにくさ：値がこれだけ上がるごとに、要る経験値が2倍（大きいほど伸びやすい）
  final bool body; // 体の能力（過渡期の入りから落ちる）。false は技術（過渡期の終わりまで落ちない）
  final bool pitcherOnly;
  final bool batterOnly;
  const GrowthStat(this.key, this.label, this.group, this.get, this.set,
      {this.min = 1, this.max = 100, this.step = 1, this.weight = 1.0, this.base = 1150, this.curve = 16, this.body = false, this.pitcherOnly = false, this.batterOnly = false});
}

/// 1年分の成長の結果（年度更新の画面用）
class GrowthChange {
  final String teamId;
  final Player player;
  final int ovrBefore;
  final int ovrAfter;
  final GrowthPhase phase;
  final Map<String, int> deltas; // 能力名 → 増減
  final bool reverted; // 1つ前の成長フェーズに戻った（復調の兆し）
  GrowthChange(this.teamId, this.player, this.ovrBefore, this.ovrAfter, this.phase, this.deltas, {this.reverted = false});
  int get ovrDiff => ovrAfter - ovrBefore;
}

/// 育成（企画書 4章）
///  - 能力ごとに経験値（EXP）をためて +1。必要量は能力ごとの指数関数（base × 2^((値−60)÷curve)）
///  - 試合に出ると全能力に経験値（野手 +15／試合、投手 +18／登板 ＋5／回。2軍 ×0.5、3軍 ×0.3）。守備適性はメイン ×1.0、サブ ×0.5
///  - 試合・練習とも、コーチ・設備（ラボ）・転向・2軍／3軍監督の育成眼の倍率がかかる
///  - 練習で選んだ能力に +10（キャンプ ×2、2軍キャンプ ×1.3、オフの自主トレ ×0.8）
///  - 実際に入る量 = 上の値 × 成長率（才能 × 向上心）× 成長フェーズの倍率。上限（潜在能力）はない
///  - 過渡期・衰退期は年齢で毎年下がる（経験値で上がる分と差し引き）。毎年10%の確率で1つ前のフェーズに戻る
class GrowthEngine {
  // 経験値の基本の量（リーグトップの選手が OVR 85〜87 に収まるように合わせた値）
  /// 野手：試合に1つ出るごとに全能力へ
  static double gameExpBase = 15.0;
  /// 投手：1登板ごと＋投げた1イニングごとに全能力へ（年間フルに投げた先発と中継ぎが、レギュラー野手と同じくらいになる比率）
  static double pitcherAppExp = 18.0;
  static double pitcherInningExp = 5.0;
  /// 練習1日で、選んだ能力へ
  static double practiceExpBase = 10.0;

  /// 能力の一覧。入る経験値はどれも同じで、+1 に要る経験値（base・curve）が能力ごとに違う
  ///  body：体の能力（球速・スタミナ・変化量・選球眼・走力・肩力・守備適性・体力・回復力）は過渡期の入りから落ちる
  ///  それ以外は技術（ミート・パワー・チャンス・送球・捕球・球威・制球・クイック・キレ・重さ・ピンチ）で、過渡期の終わりまで落ちない
  static final List<GrowthStat> stats = [
    // 野手
    GrowthStat('contactLeft', '対左ミート', 'bat', (p) => p.contactLeft, (p, v) => p.contactLeft = v, batterOnly: true),
    GrowthStat('contactRight', '対右ミート', 'bat', (p) => p.contactRight, (p, v) => p.contactRight = v, batterOnly: true),
    GrowthStat('power', 'パワー', 'bat', (p) => p.power, (p, v) => p.power = v, curve: 15, batterOnly: true),
    GrowthStat('eye', '選球眼', 'bat', (p) => p.eye, (p, v) => p.eye = v, body: true, batterOnly: true),
    GrowthStat('clutch', 'チャンス', 'bat', (p) => p.clutch, (p, v) => p.clutch = v, base: 1500, curve: 15, batterOnly: true),
    GrowthStat('run', '走力', 'field', (p) => p.run, (p, v) => p.run = v, curve: 15, body: true, batterOnly: true),
    GrowthStat('arm', '肩力', 'field', (p) => p.arm, (p, v) => p.arm = v, base: 1300, curve: 15, body: true, batterOnly: true),
    GrowthStat('throwAccuracy', '送球', 'field', (p) => p.throwAccuracy, (p, v) => p.throwAccuracy = v, base: 1100, curve: 18, batterOnly: true),
    GrowthStat('catchSkill', '捕球', 'field', (p) => p.catchSkill, (p, v) => p.catchSkill = v, base: 1100, curve: 18, batterOnly: true),
    // 投手（球速は km で別の式）
    GrowthStat('velocity', '球速', 'pitch', (p) => p.velocity, setVelocity, min: 100, max: 170, base: veloBase, body: true, pitcherOnly: true),
    GrowthStat('pitchPower', '球威', 'pitch', (p) => p.pitchPower, (p, v) => p.pitchPower = v, pitcherOnly: true),
    GrowthStat('control', '制球', 'pitch', (p) => p.control, (p, v) => p.control = v, pitcherOnly: true),
    GrowthStat('quick', 'クイック', 'pitch', (p) => p.quick, (p, v) => p.quick = v, base: 1800, curve: 16, pitcherOnly: true),
    GrowthStat('stamina', 'スタミナ', 'pitch', (p) => p.stamina, (p, v) => p.stamina = v, base: 1200, body: true, pitcherOnly: true),
    GrowthStat('clutchPitching', 'ピンチ', 'pitch', (p) => p.clutchPitching, (p, v) => p.clutchPitching = v, base: 1500, curve: 15, pitcherOnly: true),
    // 共通
    GrowthStat('maxEnergy', '体力', 'body', (p) => p.maxEnergy, (p, v) => p.maxEnergy = v, max: 1000, step: 6, base: 2000, curve: 20, body: true),
    GrowthStat('recovery', '回復力', 'body', (p) => p.recovery, (p, v) => p.recovery = v, base: 2800, curve: 20, body: true),
  ];

  /// 球速：150km で +1 に要る経験値（6km 速くなるごとに2倍）
  static const veloBase = 3300;
  /// 守備適性・球種（キレ・重さ・変化量）は伸びやすい（守備位置・球種が多いほど、1つずつの練習が薄くなるため）
  static const easyBase = 900;
  static const double easyCurve = 22;

  /// 球速を変える。球種ごとの球速も同じ伸び率で変える（150→160km なら、135km のスライダーは約144km に）
  static void setVelocity(Player p, int v) {
    final old = p.velocity;
    p.velocity = v;
    if (old <= 0 || old == v) return;
    final ratio = v / old;
    for (final pitch in p.pitches) {
      pitch.speed = (pitch.speed * ratio).round().clamp(70, 175);
    }
  }

  static const _fieldStats = {
    '捕手': 'fieldC', '一塁手': 'field1B', '二塁手': 'field2B', '三塁手': 'field3B', '遊撃手': 'fieldSS',
    '左翼手': 'fieldLF', '中堅手': 'fieldCF', '右翼手': 'fieldRF',
  };

  static final List<GrowthStat> _pitcherStats = stats.where((s) => !s.batterOnly).toList();
  static final List<GrowthStat> _batterStats = stats.where((s) => !s.pitcherOnly).toList();
  /// 基本の能力（球種と守備適性を除く）
  static List<GrowthStat> statsOf(Player p) => p.twoWay ? stats : (p.isPitcher ? _pitcherStats : _batterStats);

  /// 球種ごとのキレ・重さ・変化量（ストレート系はキレ・重さだけ）
  static List<GrowthStat> pitchStatsOf(Player p) {
    if (!p.canPitch) return const [];
    final out = <GrowthStat>[];
    for (var i = 0; i < p.pitches.length; i++) {
      final pt = p.pitches[i];
      final idx = i;
      out.add(GrowthStat('pitch:$i:sharpness', '${pt.name}のキレ', 'pitch', (q) => q.pitches.length > idx ? q.pitches[idx].sharpness : 0, (q, v) { if (q.pitches.length > idx) q.pitches[idx].sharpness = v; }, base: easyBase, curve: easyCurve, pitcherOnly: true));
      out.add(GrowthStat('pitch:$i:heaviness', '${pt.name}の重さ', 'pitch', (q) => q.pitches.length > idx ? q.pitches[idx].heaviness : 0, (q, v) { if (q.pitches.length > idx) q.pitches[idx].heaviness = v; }, base: easyBase, curve: easyCurve, pitcherOnly: true));
      if (pt.breakLevel > 20) {
        out.add(GrowthStat('pitch:$i:break', '${pt.name}の変化量', 'pitch', (q) => q.pitches.length > idx ? q.pitches[idx].breakLevel : 0, (q, v) { if (q.pitches.length > idx) q.pitches[idx].breakLevel = v; }, base: easyBase, curve: easyCurve, body: true, pitcherOnly: true));
      }
    }
    return out;
  }

  /// メインの守備位置の守備適性（試合の係数 1.0）
  static GrowthStat? fieldStatOf(Player p) {
    final key = _fieldStats[p.mainPosition];
    if (key == null || p.isPitcher) return null;
    return GrowthStat(key, '守備適性', 'field', (q) => _getField(q, key), (q, v) => _setField(q, key, v), base: easyBase, curve: easyCurve, body: true, batterOnly: true);
  }

  /// サブの守備位置（守れる位置＝適性20以上）の守備適性。試合・練習とも、メインの0.5倍
  static const subFieldWeight = 0.5;
  static List<GrowthStat> subFieldStatsOf(Player p) {
    if (p.isPitcher) return const [];
    final main = _fieldStats[p.mainPosition];
    return [
      for (final e in _fieldStats.entries)
        if (e.value != main && _getField(p, e.value) >= 20)
          GrowthStat(e.value, '守備適性（${e.key}）', 'field', (q) => _getField(q, e.value), (q, v) => _setField(q, e.value, v), weight: subFieldWeight, base: easyBase, curve: easyCurve, body: true, batterOnly: true),
    ];
  }

  /// 経験値が入る能力すべて（基本の能力＋球種＋メインとサブの守備位置）
  static List<GrowthStat> allStatsOf(Player p) => [...statsOf(p), ...pitchStatsOf(p), if (fieldStatOf(p) != null) fieldStatOf(p)!, ...subFieldStatsOf(p)];

  // ---------- フェーズ ----------
  // 開始年齢（成長期・全盛期・過渡期・衰退期）は選手ごとの成長曲線（GrowthCurve）で決まる。育成期はその前

  /// 全盛期の年齢（開始, 終了）。標準は27〜30歳
  static (int, int) peakRange(Player p) => GrowthCurve.primeRange(p);

  /// 成長フェーズを決める年齢（フェーズが戻った分を引く）
  static int phaseAge(Player p, {int? age}) => (age ?? p.age) - p.phaseShift;

  static GrowthPhase phaseOf(Player p, {int? age}) {
    final s = GrowthCurve.starts(p);
    final a = phaseAge(p, age: age);
    if (a < s[0]) return GrowthPhase.developing;
    if (a < s[1]) return GrowthPhase.rising;
    if (a < s[2]) return GrowthPhase.prime;
    if (a < s[3]) return GrowthPhase.transition;
    return GrowthPhase.decline;
  }

  /// 1つ前の成長フェーズに戻す（過渡期 → 全盛期の最後の年、衰退期 → 過渡期の最後の年）
  static void revertPhase(Player p) {
    final s = GrowthCurve.starts(p);
    final a = phaseAge(p);
    final ph = phaseOf(p);
    final target = ph == GrowthPhase.decline ? s[3] - 1 : s[2] - 1;
    if (ph != GrowthPhase.decline && ph != GrowthPhase.transition) return;
    p.phaseShift += max(1, a - target);
  }

  // ---------- EXP の加減 ----------
  /// 能力の高さ（必要経験値を決める値。球速は 120km=0〜170km=100、体力は 1/10）
  static int levelOf(GrowthStat s, int v) => s.key == 'velocity' ? Velo.norm(v) : (s.key == 'maxEnergy' ? v ~/ 10 : v);

  /// +1 に必要な経験値：base × 2^((値−60)÷curve)。例 base 1150・curve 16 なら 60：1150、76：2300、92：4600
  static int needExp(GrowthStat s, int v) {
    // 球速は km で：150km で veloBase、6km 速くなるごとに2倍。150km より下は12kmごとに半分
    if (s.key == 'velocity') return (s.base * pow(2, (v - 150) / (v < 150 ? 12 : 6))).round().clamp(300, 200000);
    final l = levelOf(s, v);
    final over = max(0, l - 80); // 80 から先は少しずつ重く（90 ちょうどで止まる選手が固まらないように、なだらかに）
    return (s.base * pow(2, (l - 60) / s.curve + over * over / highK)).round().clamp(100, 400000);
  }

  /// 80 から先の重さ：(値−80)²÷highK だけ 2 倍を重ねる（90 で ×2^(100/highK)、100 で ×2^(400/highK)）
  static double highK = 50;

  /// 成長フェーズの経験値の倍率（能力ごと）。円熟の選手は、過渡期も技術を全盛期と同じように伸ばす
  static double phaseMult(Player p, GrowthStat s, [GrowthPhase? ph]) {
    ph ??= phaseOf(p);
    if (ph == GrowthPhase.transition && !s.body && GrowthCurve.mature(p)) return GrowthPhase.prime.expMultiplier;
    return ph.expMultiplier;
  }

  /// EXP を足し（マイナスなら引き）、必要量ごとに能力を上げ下げする。変化した量を返す
  static int addExp(Player p, GrowthStat s, double amount) {
    if (amount == 0) return 0;
    var e = (p.exp[s.key] ?? 0) + amount.round();
    var v = s.get(p);
    final before = v;
    while (e >= needExp(s, v)) {
      if (v >= s.max) { e = 0; break; }
      e -= needExp(s, v);
      v = min(v + s.step, s.max);
    }
    while (e < 0 && e.abs() >= needExp(s, max(s.min, v - s.step))) {
      if (v <= s.min) { e = 0; break; }
      e += needExp(s, max(s.min, v - s.step));
      v = max(v - s.step, s.min);
    }
    p.exp[s.key] = e.clamp(-200000, 200000);
    s.set(p, v);
    return v - before;
  }

  // ---------- 試合の経験値 ----------
  /// 試合に出た選手に経験値を入れる（全能力に。level：1軍 1.0、2軍 0.5、3軍 0.3）
  ///  野手は1試合ごと、投手は1登板ごと＋投げたイニング（アウトの数）ごと
  ///  coach：能力ごとの倍率（コーチ・設備・転向・2軍／3軍監督の育成眼。練習と同じ）。無ければ 1
  static void gameExp(Player p, double level, {double innings = 0, double Function(GrowthStat)? coach}) {
    final raw = p.isPitcher ? pitcherAppExp + pitcherInningExp * innings : gameExpBase;
    final base = raw * level * p.growthRate;
    final ph = phaseOf(p);
    for (final s in allStatsOf(p)) {
      addExp(p, s, base * phaseMult(p, s, ph) * s.weight * (coach == null ? 1.0 : coach(s)));
    }
  }

  // ---------- 練習 ----------
  static const _batterMenu = ['対左ミート', '対右ミート', 'パワー', '選球眼', 'チャンス', '走力', '肩力', '送球', '捕球', '守備'];
  // 投手の球種の練習：全球種のキレ・重さ、変化球の変化量
  static const pitchSharp = 'キレ（全球種）', pitchHeavy = '重さ（全球種）', pitchBreak = '変化量（変化球）';
  /// 経験値が2倍になる練習（ミートは対左・対右に分けたので、片方に絞る分を2倍に）
  static const _doubleMenu = {'対左ミート', '対右ミート'};
  static const _pitcherMenu = ['球速', '球威', '制球', 'クイック', 'スタミナ', 'ピンチ'];
  static const _bodyMenu = ['体力', '回復力'];
  static const _menuKeys = {
    '対左ミート': ['contactLeft'], '対右ミート': ['contactRight'], 'パワー': ['power'], '選球眼': ['eye'], 'チャンス': ['clutch'], '走力': ['run'],
    '肩力': ['arm'], '送球': ['throwAccuracy'], '捕球': ['catchSkill'],
    '球速': ['velocity'], '球威': ['pitchPower'], '制球': ['control'], 'クイック': ['quick'], 'スタミナ': ['stamina'], 'ピンチ': ['clutchPitching'],
    '体力': ['maxEnergy'], '回復力': ['recovery'],
  };

  /// 練習メニューの選択肢（選手ごと。投手は全球種のキレ・重さと、変化球の変化量。二刀流は打撃・投球の両方）
  ///  投手が打撃・守備の練習を、野手が投球の練習をすることもできる（専門外の能力も伸びる）
  static List<String> practiceOptions(Player p) {
    final ps = pitchStatsOf(p);
    return [
      'おまかせ',
      ...(p.isPitcher && !p.twoWay ? [..._pitcherMenu, ..._batterMenu] : [..._batterMenu, ..._pitcherMenu]),
      if (ps.any((x) => x.key.endsWith(':sharpness'))) pitchSharp,
      if (ps.any((x) => x.key.endsWith(':heaviness'))) pitchHeavy,
      if (ps.any((x) => x.key.endsWith(':break'))) pitchBreak,
      ..._bodyMenu,
    ];
  }

  static const batterMenu = _batterMenu, pitcherMenu = _pitcherMenu, bodyMenu = _bodyMenu;

  /// 専門（投手・野手。二刀流は両方）の練習メニュー（球種・体を含む）
  static List<String> ownMenus(Player p) {
    final ps = pitchStatsOf(p);
    return [
      ...(p.twoWay ? [..._batterMenu, ..._pitcherMenu] : (p.isPitcher ? _pitcherMenu : _batterMenu)),
      if (ps.any((x) => x.key.endsWith(':sharpness'))) pitchSharp,
      if (ps.any((x) => x.key.endsWith(':heaviness'))) pitchHeavy,
      if (ps.any((x) => x.key.endsWith(':break'))) pitchBreak,
      ..._bodyMenu,
    ];
  }

  /// 練習メニューの能力の今の値（画面に添える。球種の練習は全球種の平均）
  static String menuValue(Player p, String menu) {
    if (menu == '球速') return '${p.velocity}km';
    final t = practiceTargets(p, menu: menu);
    if (t.isEmpty) return '';
    final v = t.map((s) => s.get(p)).reduce((a, b) => a + b) / t.length;
    return menu == '体力' ? '${(v / 10).round()}' : '${v.round()}';
  }

  /// 「おまかせ」のときに伸ばす能力：選手の主な能力のうち、いちばん低いもの（バランスよく育てる）。
  ///  eye（2軍監督の育成眼）が低いと、ときどき合っていないメニュー（体力・回復力など）を選んでしまう（週ごとに決まる）
  static String autoPractice(Player p, {int eye = 100, DateTime? date}) {
    if (eye < 100 && date != null) {
      final week = date.difference(DateTime(2000)).inDays ~/ 7;
      final r = Random(p.id.hashCode ^ week ^ 0x2f9);
      if (r.nextDouble() < (100 - eye) / 100 * 0.6) {
        final opts = ownMenus(p); // 育成眼が低くても、専門外の練習は選ばない
        if (opts.isEmpty) return 'おまかせ';
        return opts[r.nextInt(opts.length)];
      }
    }
    final cands = <String, int>{};
    if (p.isPitcher) {
      cands['球速'] = levelOf(stats.firstWhere((s) => s.key == 'velocity'), p.velocity);
      cands['球威'] = p.pitchPower;
      cands['制球'] = p.control;
      cands['スタミナ'] = p.stamina;
      final brk = p.pitches.where((x) => x.breakLevel > 20).toList();
      if (brk.isNotEmpty) cands[pitchSharp] = (brk.map((x) => x.sharpness).reduce((a, b) => a + b) / brk.length).round();
    } else {
      cands['対左ミート'] = p.contactLeft;
      cands['対右ミート'] = p.contactRight;
      cands['パワー'] = p.power;
      cands['選球眼'] = p.eye;
      cands['走力'] = p.run;
      cands['捕球'] = p.catchSkill;
      final f = fieldStatOf(p);
      if (f != null) cands['守備'] = f.get(p);
    }
    return cands.entries.reduce((a, b) => b.value < a.value ? b : a).key;
  }

  /// 練習で経験値が入る能力（練習メニューから決める）
  /// いま練習しているメニュー（おまかせや選べないメニューなら自動で決めたもの）
  static String practiceMenu(Player p, {int eye = 100, DateTime? date}) {
    final menu = p.practiceInstruction;
    return (!practiceOptions(p).contains(menu) || menu == 'おまかせ') ? autoPractice(p, eye: eye, date: date) : menu;
  }

  /// 練習の経験値の倍率（対左・対右ミートは2倍）
  static double practiceMult(Player p, {String? menu}) => _doubleMenu.contains(menu ?? practiceMenu(p)) ? 2.0 : 1.0;

  /// 練習が同じまとまりの能力にも広がる割合（打撃・守備走塁・投球。選んだ能力には全量）
  static const practiceSpill = 0.3;

  static List<GrowthStat> practiceTargets(Player p, {String? menu}) {
    menu ??= practiceMenu(p);
    if (menu == '守備') {
      final f = fieldStatOf(p);
      return f == null ? const [] : [f, ...subFieldStatsOf(p)]; // サブの守備位置にも0.5倍
    }
    final keys = _menuKeys[menu];
    if (keys != null) return [for (final s in stats) if (keys.contains(s.key)) s];
    final suffix = menu == pitchSharp ? ':sharpness' : (menu == pitchHeavy ? ':heaviness' : (menu == pitchBreak ? ':break' : null));
    if (suffix != null) return [for (final s in pitchStatsOf(p)) if (s.key.endsWith(suffix)) s];
    return [for (final s in pitchStatsOf(p)) if (s.label == menu) s];
  }

  /// 日付の期間 (from, to] の練習（全チーム）
  ///  campMult：その日の練習の倍率（キャンプ ×2、2軍キャンプ ×1.3、休養 0 など）。無ければ 1
  ///  coach：コーチによる練習効果の倍率（相性・指導力・人望）。無ければ 1
  ///  devEye：2軍の選手の練習を見る2軍監督の育成眼（効果 ×0.85〜×1.15、おまかせの選び方）。無ければ 100 扱い
  static void advanceDays(Iterable<Team> teams, DateTime from, DateTime to,
      {double Function(Team, Player, GrowthStat)? coach, double Function(Team, Player, DateTime)? campMult, int Function(Team, bool ikusei)? devEye}) {
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (d.isBefore(end)) {
      d = d.add(const Duration(days: 1));
      for (final t in teams) {
        final eye2 = devEye == null ? 100 : devEye(t, false), eye3 = devEye == null ? 100 : devEye(t, true);
        for (final p in t.players) {
          if (p.isInjuredOut) continue; // 怪我で離脱中は練習できない
          final cm = campMult == null ? defaultPracticeMult(d) : campMult(t, p, d);
          if (cm <= 0) continue;
          final farm = !t.roster1G.contains(p.id);
          final eye = p.ikusei ? eye3 : (farm ? eye2 : 100); // 2軍の選手は2軍監督、育成選手は3軍監督が練習を見る
          final menu = practiceMenu(p, eye: eye, date: d);
          final dev = farm && devEye != null ? 0.85 + eye / 100 * 0.3 : 1.0;
          final plain = practiceExpBase * cm * p.growthRate * dev;
          final ph = phaseOf(p);
          final targets = practiceTargets(p, menu: menu);
          for (final s in targets) {
            addExp(p, s, plain * phaseMult(p, s, ph) * practiceMult(p, menu: menu) * s.weight * (coach == null ? 1.0 : coach(t, p, s))); // サブの守備位置は0.5倍
          }
          // 同じまとまりの基本の能力にも3割（試合の経験値と同じ係数をかける）。体力・回復力と球種の練習は広がらない
          final groups = {for (final s in targets) if (s.group != 'body' && !s.key.startsWith('pitch:')) s.group};
          if (groups.isEmpty) continue;
          final keys = {for (final s in targets) s.key};
          for (final s in statsOf(p)) {
            if (!groups.contains(s.group) || keys.contains(s.key) || s.key == 'velocity') continue; // 球速は広がらない（直接の練習と試合だけ）
            addExp(p, s, plain * phaseMult(p, s, ph) * practiceSpill * (coach == null ? 1.0 : coach(t, p, s)));
          }
        }
      }
    }
  }

  /// キャンプ以外の日の練習の倍率（シーズン中 ×1、オフの自主トレ（10・12月）×0.8）
  static double defaultPracticeMult(DateTime d) => (d.month == 10 || d.month == 12) ? 0.8 : 1.0;

  static int _getField(Player p, String k) => {
        'fieldC': p.fieldC, 'field1B': p.field1B, 'field2B': p.field2B, 'field3B': p.field3B,
        'fieldSS': p.fieldSS, 'fieldLF': p.fieldLF, 'fieldCF': p.fieldCF, 'fieldRF': p.fieldRF,
      }[k] ?? 0;

  static void _setField(Player p, String k, int v) {
    switch (k) {
      case 'fieldC': p.fieldC = v; break;
      case 'field1B': p.field1B = v; break;
      case 'field2B': p.field2B = v; break;
      case 'field3B': p.field3B = v; break;
      case 'fieldSS': p.fieldSS = v; break;
      case 'fieldLF': p.fieldLF = v; break;
      case 'fieldCF': p.fieldCF = v; break;
      case 'fieldRF': p.fieldRF = v; break;
    }
  }

  // ---------- 年度 ----------
  /// 年度の初めの能力を控えておく（1年の成長の結果を出すため）
  /// 能力のひかえ（OVR と、経験値の入る能力すべて）
  static Map<String, int> abilities(Player p) => {'ovr': p.ovr, for (final s in statsOf(p)) s.key: s.get(p)};

  static void snapshotYearStart(Iterable<Team> teams) {
    for (final t in teams) {
      for (final p in t.players) {
        p.yearStart = {'ovr': p.ovr, for (final s in statsOf(p)) s.key: s.get(p)};
      }
    }
  }

  /// シーズンの終わり：衰え（過渡期・衰退期）と、成長フェーズの戻り（10%）。年齢・プロ年数はここでは進めない
  ///  結果は、年度の初めからの能力の変化（試合・練習で伸びた分を含む）
  static List<GrowthChange> endOfSeason(Iterable<Team> teams, int year) {
    final changes = <GrowthChange>[];
    for (final t in teams) {
      for (final p in t.players) {
        final rnd = Random(p.id.hashCode ^ year);
        var phase = phaseOf(p);
        final before = p.yearStart['ovr'] ?? p.ovr;
        decline(p, phase, rnd);
        var reverted = false;
        if ((phase == GrowthPhase.transition || phase == GrowthPhase.decline) && rnd.nextDouble() < 0.10) {
          revertPhase(p);
          reverted = true;
          phase = phaseOf(p);
        }
        final deltas = <String, int>{};
        for (final s in statsOf(p)) {
          final b = p.yearStart[s.key];
          if (b == null) continue;
          final d = s.get(p) - b;
          if (d != 0) deltas[s.label] = d;
        }
        if (deltas.isNotEmpty || reverted || phase != GrowthPhase.prime) {
          changes.add(GrowthChange(t.id, p, before, p.ovr, phase, deltas, reverted: reverted));
        }
      }
    }
    return changes;
  }

  /// 1年分の衰え：体の能力は過渡期から、技術は衰退期から落ちる（球種・守備適性も含む）
  static void decline(Player p, GrowthPhase phase, Random rnd) {
    for (final s in allStatsOf(p)) {
      final pts = _declinePoints(phase, s, p, rnd) * shiftDeclineMult(p, s.key);
      if (pts > 0) addExp(p, s, -pts * needExp(s, s.get(p)));
    }
  }

  /// ベテランのモデルチェンジ（改修5.2）：武器にする能力の衰えをゆるめる倍率（体の能力＝球速・走力・肩はそのまま落ちる）
  static double shiftDeclineMult(Player p, String key) {
    if (p.styleShift == '技巧派') {
      if (key.endsWith(':sharpness')) return 0.3;
      if (key == 'control' || key == 'clutchPitching' || key == 'stamina') return key == 'stamina' ? 0.6 : 0.3;
    } else if (p.styleShift == '職人') {
      if (key == 'eye' || key == 'clutch' || key == 'catchSkill' || key == 'contactLeft' || key == 'contactRight' || key == 'throwAccuracy') return 0.35;
    }
    return 1.0;
  }

  /// 転向した選手の練習の経験値の倍率（武器にする能力を磨く）
  static double shiftPracticeMult(Player p, String key) {
    if (p.styleShift == '技巧派' && (key == 'control' || key == 'clutchPitching' || (key.startsWith('pitch:') && !key.endsWith(':heaviness')))) return 1.3;
    if (p.styleShift == '職人' && (key == 'eye' || key == 'clutch' || key == 'catchSkill' || key == 'field1B' || key == 'field3B')) return 1.3;
    return 1.0;
  }

  /// 衰えの量（能力の段階数／年）。±30%の個人差
  ///  体の能力：過渡期 2.0・衰退期 3.8。技術：過渡期 0・衰退期 1.7（円熟の選手は半分）
  static double _declinePoints(GrowthPhase phase, GrowthStat s, Player p, Random rnd) {
    double d;
    switch (phase) {
      case GrowthPhase.transition:
        d = s.body ? 2.0 : 0;
        break;
      case GrowthPhase.decline:
        d = s.body ? 3.8 : 1.7 * (GrowthCurve.mature(p) ? 0.5 : 1.0);
        break;
      default:
        return 0;
    }
    return d * (0.7 + rnd.nextDouble() * 0.6);
  }
}
