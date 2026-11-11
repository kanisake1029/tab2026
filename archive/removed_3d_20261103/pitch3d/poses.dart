import '../../engine/body_model.dart';
import '../../engine/pitch_motion.dart' show J;
import '../../engine/vec3.dart';

/// 止まった姿勢（捕手のしゃがみ・打者の構え）の関節の位置（本塁基準の座標）
///  T＝利き腕の側（捕手は投げる腕、打者は後ろの手）、G＝反対側
class StaticPoses {
  static List<V3> _blank() => List<V3>.filled(J.values.length, V3.zero);

  /// 捕手（右投げ）：本塁の後ろでしゃがむ（写真・中継で確かめた形）。足は肩幅より広く、つま先とひざは外へ（約35°）、
  ///  かかとは少し浮かせ、腰はひざより少し低い。上体は少し前へ。ミットの腕は前へ伸ばして構える。
  ///  runners：走者がいるとき（腰を高くし、右足を少し引く＝すぐ投げられる構え）。mitt：ミットの位置
  static List<V3> catcher(BodyModel b, {V3 mitt = const V3(-0.02, -0.15, 0.78), bool runners = false}) {
    final k = b.height / 1.80;
    final p = _blank();
    V3 at(double x, double y, double z) => V3(x * k, -0.80 + y * k, z * k);
    final hz = runners ? 0.58 : 0.44; // 腰の高さ
    final rb = runners ? -0.10 : 0.0; // 右足（T）を引く
    p[J.pelvis.index] = at(0, -0.06, hz);
    p[J.hipT.index] = at(0.10, -0.06, hz + 0.01);
    p[J.hipG.index] = at(-0.10, -0.06, hz + 0.01);
    p[J.kneeT.index] = at(0.36, 0.20 + rb * 0.5, hz + 0.08);
    p[J.kneeG.index] = at(-0.36, 0.20, hz + 0.08);
    p[J.ankleT.index] = V3(0.33 * k, -0.80 + (0.02 + rb) * k, b.ankleH + 0.04);
    p[J.ankleG.index] = V3(-0.33 * k, -0.80 + 0.02 * k, b.ankleH + 0.04);
    p[J.toeT.index] = V3(0.44 * k, -0.80 + (0.18 + rb) * k, 0.02);
    p[J.toeG.index] = V3(-0.44 * k, -0.80 + 0.18 * k, 0.02);
    p[J.neck.index] = at(0, 0.14, hz + 0.50);
    p[J.head.index] = at(0, 0.19, hz + 0.68);
    p[J.shoulderT.index] = at(0.19, 0.12, hz + 0.46);
    p[J.shoulderG.index] = at(-0.19, 0.12, hz + 0.46);
    if (runners) {
      // 投げる手はミットの後ろ（すぐ持ち替える）
      p[J.elbowT.index] = at(0.22, 0.30, hz + 0.26);
      p[J.wristT.index] = V3(mitt.x + 0.08, mitt.y - 0.10, mitt.z - 0.04);
      p[J.ball.index] = V3(mitt.x + 0.06, mitt.y - 0.06, mitt.z - 0.02);
    } else {
      // 投げる手は右足首の後ろ（ファウルチップから守る）
      p[J.elbowT.index] = at(0.30, 0.04, hz + 0.18);
      p[J.wristT.index] = at(0.30, -0.10, hz - 0.06);
      p[J.ball.index] = at(0.30, -0.06, hz - 0.08);
    }
    // ミットの腕：ひじを少し曲げて前へ
    final mt = V3(mitt.x, mitt.y, mitt.z);
    p[J.glove.index] = mt;
    p[J.wristG.index] = mt + V3(-0.04, -0.09 * k, -0.04);
    p[J.elbowG.index] = at(-0.27, 0.34, hz + 0.30);
    return p;
  }

  /// 打者の構え（right：右打席＝三塁側に立つ）
  static List<V3> batter(BodyModel b, {required bool right}) {
    final k = b.height / 1.80;
    final s = right ? -1.0 : 1.0; // 打席の側の x（右打席は三塁側＝−x）
    final p = _blank();
    // 体は本塁の方（x の −s 向き）を向き、前の足（G）が投手側（y の＋）
    V3 at(double xFromBox, double y, double z) => V3(s * (0.95 - xFromBox) * 1.0, 0.25 + y * k, z * k);
    p[J.pelvis.index] = at(0.02, 0.0, 0.92);
    p[J.hipT.index] = at(0.03, -0.10, 0.92);
    p[J.hipG.index] = at(0.01, 0.10, 0.92);
    p[J.kneeT.index] = at(0.08, -0.28, 0.50);
    p[J.kneeG.index] = at(0.08, 0.30, 0.50);
    p[J.ankleT.index] = V3(s * 0.88, 0.25 - 0.40 * k, b.ankleH);
    p[J.ankleG.index] = V3(s * 0.88, 0.25 + 0.42 * k, b.ankleH);
    p[J.toeT.index] = V3(s * (0.88 - 0.20 * k), 0.25 - 0.36 * k, 0.02);
    p[J.toeG.index] = V3(s * (0.88 - 0.20 * k), 0.25 + 0.48 * k, 0.02);
    p[J.neck.index] = at(0.08, 0.02, 1.42);
    p[J.head.index] = at(0.10, 0.06, 1.60);
    p[J.shoulderT.index] = at(0.06, -0.17, 1.38);
    p[J.shoulderG.index] = at(0.10, 0.19, 1.38);
    // 両手は後ろの肩の前（バットを立てて構える）
    final hands = at(0.30, -0.12, 1.36);
    p[J.elbowT.index] = at(0.10, -0.32, 1.22);
    p[J.elbowG.index] = at(0.32, 0.08, 1.15);
    p[J.wristT.index] = hands + V3(0, 0, 0.03);
    p[J.wristG.index] = hands - V3(0, 0, 0.05);
    p[J.ball.index] = hands + V3(-s * 0.02, 0, 0.06);
    p[J.glove.index] = hands + V3(-s * 0.02, 0, -0.02);
    return p;
  }

  /// 打者の目の位置（構えたとき）
  static V3 batterEye(BodyModel b, {required bool right}) {
    final h = batter(b, right: right)[J.head.index];
    final s = right ? -1.0 : 1.0;
    return h + V3(-s * 0.08, 0.02, 0.02);
  }

  static V3 catcherEye(BodyModel b) => catcher(b)[J.head.index] + const V3(0, 0.09, 0.02);
}
