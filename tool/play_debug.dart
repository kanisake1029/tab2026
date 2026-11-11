// 打球処理（PlayResolver）の内訳を確認するデバッグ用
import 'package:npb_pennant_app/engine/play_resolver.dart';
import 'balance_sim.dart' as bs;

void main(List<String> args) {
  bs.main(args.isEmpty ? ['150'] : args);
  final s = PlayResolver.stats;
  print(s);
  final n = s['gbR1lt2'] ?? 1;
  print('一塁走者あり・2アウト未満のゴロ: $n件  平均 送球可能時刻 ${((s['tBallR1'] ?? 0) / n / 100).toStringAsFixed(2)}s / 打者の一塁到達 ${((s['btR1'] ?? 0) / n / 100).toStringAsFixed(2)}s');
}
