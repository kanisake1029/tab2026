import 'dart:math';
import '../models/player.dart';

/// 年俸のたたき台（単位: 万円）
///  - 基準: OVR50 → 約800万、60 → 約2500万、70 → 約8000万、80 → 約2.5億（10上がるごとに約3.16倍）
///  - 補正: プロ1年目 ×0.5（上限1600万）・2年目 ×0.65・3年目 ×0.8、外国人 ×1.5、27〜32歳 ×1.1
///  - 下限 440万、10万円単位
int estimateSalary(Player p) {
  double s = 800 * pow(10, 0.05 * (p.ovr - 50)).toDouble();
  final rookie = p.nationality != '海外'; // 外国人は来日1年目でも新人の扱いにしない
  if (!rookie) {
  } else if (p.proYears <= 1) {
    s *= 0.5;
  } else if (p.proYears == 2) {
    s *= 0.65;
  } else if (p.proYears == 3) {
    s *= 0.8;
  }
  if (p.nationality == '海外') s *= 1.5;
  if (p.age >= 27 && p.age <= 32) s *= 1.1;
  if (rookie && p.proYears <= 1) s = min(s, 1600);
  s = max(s, 450);
  return round50(s);
}

/// 年俸は50万円単位（最低50万）
int round50(num v) => max(50, (v / 50).round() * 50);

/// 年俸の表示（例: 12000 → 「1億2000万」、850 → 「850万」）
String formatSalary(int man) {
  if (man >= 10000) {
    final oku = man ~/ 10000;
    final rest = man % 10000;
    return rest == 0 ? '$oku億' : '$oku億$rest万';
  }
  return '$man万';
}
