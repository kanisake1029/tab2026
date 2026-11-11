import 'dart:math';
import '../models/player.dart';
import 'salary_utils.dart';
import '../engine/growth_curve.dart';

/// 身体・精神・成長タイプ・年俸の初期値を決める（たたき台）。
/// 固有12は固定シードで一度だけ決めてデータに保存し、新規チームは生成時に決める。
void assignTraits(Player p, Random r) {
  double g() {
    final u1 = 1.0 - r.nextDouble();
    final u2 = r.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  // 体力の最大値（1〜1000。平均 A80 相当の800）: 投手はスタミナ、野手は走力と少し連動
  final base = p.isPitcher ? 800 + (p.stamina - 60) * 3 : 800 + (p.run - 60) * 2;
  p.maxEnergy = (base + g() * 80).round().clamp(250, 1000);
  p.energy = p.maxEnergy;
  // 回復力（平均 A80。若いほど高め）・怪我しにくさ（平均 B70）。たまに回復が遅い選手・怪我に弱い選手がいる
  p.recovery = (80 + (27 - p.age) * 0.6 + g() * 7).round().clamp(20, 99);
  p.durability = (70 + g() * 8).round().clamp(20, 99);
  if (r.nextDouble() < 0.08) p.recovery = (p.recovery - 25).clamp(20, 99);
  if (r.nextDouble() < 0.08) p.durability = (p.durability - 25).clamp(20, 99);
  p.trust = (50 + g() * 8).round().clamp(20, 80);
  p.motivation = 50;
  // 調子の波: 周期10〜40日、位相はばらばら
  final period = 10 + r.nextDouble() * 30;
  p.conditionFreq = double.parse((2 * pi / period).toStringAsFixed(4));
  p.conditionPhase = double.parse((r.nextDouble() * 2 * pi).toStringAsFixed(4));
  // 成長タイプ: 年齢が高いほど晩成になりやすい
  final late = (0.15 + (p.age - 22) * 0.025).clamp(0.10, 0.45);
  final early = (0.30 - (p.age - 22) * 0.02).clamp(0.10, 0.35);
  final x = r.nextDouble();
  p.growthType = x < early ? '早熟' : (x < early + late ? '晩成' : '普通');
  GrowthCurve.generate(p, r, bias: p.growthType); // 成長曲線（全盛期の年齢と長さ）
  p.injuryDays = 0;
  p.injuryName = '';
  p.injurySeverity = 0;
  p.salary = estimateSalary(p);
  p.contractYears = 1;
}

/// 以前の基準（体力・回復力・怪我しにくさの平均50）で作った選手を、今の基準（平均 A80・A80・B70）に底上げする。個人差はそのまま
void raiseBodyStats(Player p) {
  final ratio = p.maxEnergy > 0 ? p.energy / p.maxEnergy : 1.0;
  p.maxEnergy = (p.maxEnergy + 300).clamp(250, 1000);
  p.energy = (p.maxEnergy * ratio).round();
  p.recovery = (p.recovery + 30).clamp(20, 99);
  p.durability = (p.durability + 20).clamp(20, 99);
}
