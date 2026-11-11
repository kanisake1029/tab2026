import 'dart:math' as math;
import '../engine/body_gen.dart' show stableHash;
import 'player.dart';

/// 顔の部品の設定（顔アイコンを選ぶのに使う。もとは3Dの人形の顔。3D表示は2026-11-03に外した）
class FaceLook {
  final int skin, hair, iris; // 色
  final int hairStyle; // 0 短髪 1 スポーツ刈り 2 もみあげ長め 3 アフロ 4 襟足長め 5 坊主
  final double eyeSize, eyeGap, eyeTilt; // 目の大きさ・間隔・つり目（＋）
  final double browThick, browAngle, browLen; // 眉の太さ・角度（＋＝上がり）・長さ
  final int noseType; // 0 小さい丸 1 すっと長い 2 幅広 3 わし鼻
  final double noseSize;
  final double mouthWidth, lip; // 口の幅・唇の厚さ
  final double jaw, chin, cheek, ear; // あごの幅・あごの長さ・頬・耳
  final int beard; // 0 なし 1 無精ひげ 2 あごひげ 3 口ひげ 4 あごと口 5 濃いひげ
  // ── 個性の部品（2.5D の顔）──
  final int faceShape; // 0 丸顔 1 卵形 2 四角（えらが張る） 3 面長
  final int lid; // 0 一重 1 二重 2 奥二重
  final int browShape; // 0 まっすぐ 1 弓なり 2 角ばる（山がある）
  final double noseLen; // 鼻の長さ（1＝ふつう）
  final int mouthShape; // 0 ふつう 1 口角が上がる 2 への字 3 厚い唇
  final int mole; // ほくろ：-1 なし 0 左目の下 1 右の口元 2 左のほお
  final int wrinkle; // しわ：0 なし 1 目じり 2 目じりとほうれい線（年齢から）
  final bool freckles; // そばかす
  final double gazeX; // 目の位置（黒目の寄り：−＝内、＋＝外）
  // ── 小さく写っても見分けがつく誇張（2.5D の顔。face_art.dart で画像にする）──
  final int eyeStyle; // 0 ふつう 1 キリッ 2 タレ目 3 ジト目 4 細目 5 丸目 6 点目 7 三白眼 8 つぶら 9 鋭い 10 眠そう 11 力強い
  final int browStyle; // 0 ふつう 1 太い 2 細い 3 つり 4 困り（八の字） 5 への字 6 ゲジゲジ 7 短い 8 角ばった 9 麻呂
  final int accessory; // 0 なし 1 アイブラック 2 スポーツサングラス 3 鼻の絆創膏 4 メガネ
  final int archetype; // 0 強打者 1 俊足 2 エース 3 剛腕 4 職人 5 ベテラン 6 若手 7 ムードメーカー
  static const archetypeNames = ['強打者', '俊足', 'エース', '剛腕', '職人', 'ベテラン', '若手', 'ムードメーカー'];
  const FaceLook({
    required this.skin,
    required this.hair,
    required this.iris,
    required this.hairStyle,
    required this.eyeSize,
    required this.eyeGap,
    required this.eyeTilt,
    required this.browThick,
    required this.browAngle,
    required this.browLen,
    required this.noseType,
    required this.noseSize,
    required this.mouthWidth,
    required this.lip,
    required this.jaw,
    required this.chin,
    required this.cheek,
    required this.ear,
    required this.beard,
    this.faceShape = 1,
    this.lid = 1,
    this.browShape = 1,
    this.noseLen = 1,
    this.mouthShape = 0,
    this.mole = -1,
    this.wrinkle = 0,
    this.freckles = false,
    this.gazeX = 0,
    this.eyeStyle = 0,
    this.browStyle = 1,
    this.accessory = 0,
    this.archetype = 7,
  });

  /// 選手の id から（同じ選手はいつも同じ顔）。国籍で肌・髪・目の色と髪型の出方が変わる
  factory FaceLook.ofPlayer(Player p) => FaceLook.of(p.id,
      foreign: p.nationality == '海外',
      age: p.age,
      bmi: p.weight / math.pow(p.height / 100, 2),
      pitcher: p.isPitcher,
      power: p.isPitcher ? p.pitchPower : p.power,
      run: p.run,
      contact: ((p.contactLeft + p.contactRight) / 2).round(),
      velocity: p.isPitcher ? p.velocity : 0,
      control: p.isPitcher ? p.control : 50);

  /// 顔を決める（パワプロ風の部品の組み合わせ。架空の顔で、実在の選手には似せない）。
  ///  ① 顔の比率は、日本人青年男性の顔の計測の統計（AIST 人体寸法データベース 1991-92、約217人）から、平均からのずれ（z）を選手ごとに引き、
  ///     似顔絵のように k＝2.5 倍に誇張する：頬弓幅 146.5±5.2mm・下顎角幅 111.7±5.0・形態顔高 123.9±6.0・瞳孔間幅 61.9±3.6・口裂幅 47.6±3.1
  ///     （顔の幅に対する変動係数：顔の幅 3.6%・あご 4.5%・顔の高さ 4.8%・目の間 5.8%・口 6.5%）
  ///  ② まぶた：日本人は一重 55%・二重 33%・左右で違う 11%（大学生の調査）。海外の選手はほとんど二重。目の型はまぶたで出やすさを変える
  ///  ③ 型（アーキタイプ）：能力・年齢から 8 つ（強打者・俊足・エース・剛腕・職人・ベテラン・若手・ムードメーカー）。型で顔の形・目・眉・ひげの出やすさを変える
  factory FaceLook.of(String id, {bool foreign = false, int age = 27, double bmi = 24, bool pitcher = false, int power = 50, int run = 50, int contact = 50, int velocity = 0, int control = 50}) {
    double u(int salt) => (stableHash(id, salt) % 10000) / 10000.0;
    double n(int salt) => (u(salt) + u(salt + 101) + u(salt + 202) - 1.5) / 0.5; // おおよそ −1〜1 の山形
    // 標準正規分布（Box–Muller）
    double z(int salt) => math.sqrt(-2 * math.log(math.max(1e-6, u(salt)))) * math.cos(2 * math.pi * u(salt + 7));
    final r = u(0x7ace);
    // 0 東アジア 1 アフリカ系 2 ヨーロッパ系 3 中南米
    final race = !foreign ? 0 : (r < 0.35 ? 1 : (r < 0.75 ? 2 : 3));
    final skins = [
      [0xFFF1CBA6, 0xFFE8BC94, 0xFFDDAE86, 0xFFF5D3B3],
      [0xFF8D5A3B, 0xFF6E4429, 0xFF5A3620, 0xFF9C6644],
      [0xFFF3D2BC, 0xFFEAC0A2, 0xFFF0C8A8, 0xFFE3B38E],
      [0xFFD9A276, 0xFFC98D60, 0xFFBE8156, 0xFFE0AE82],
    ][race];
    final hairs = [
      [0xFF1A1512, 0xFF221A14, 0xFF2E2118, 0xFF3A2A1E],
      [0xFF15110E, 0xFF1E1712, 0xFF15110E, 0xFF231A12],
      [0xFF4A3322, 0xFF6B4A2E, 0xFFA77B4A, 0xFF2C1F16],
      [0xFF1F1712, 0xFF2E2119, 0xFF3D2A1D, 0xFF17120F],
    ][race];
    final irises = race == 2 ? const [0xFF3B6EA8, 0xFF5B7B3A, 0xFF6B4A2E, 0xFF4A6B7B] : const [0xFF3A2618, 0xFF2C1D13, 0xFF4A3322, 0xFF5A3A22];
    int pick(List<int> l, int salt) => l[stableHash(id, salt) % l.length];
    int wpick(List<num> w, int salt) {
      final tot = w.fold<double>(0.0, (a, b) => a + b);
      var x = u(salt) * tot;
      for (var i = 0; i < w.length; i++) {
        x -= w[i];
        if (x < 0) return i;
      }
      return w.length - 1;
    }

    // ── 型（アーキタイプ）──
    final sc = <double>[
      (power - 62) / (pitcher ? 25 : 22),
      (run - 62) / 22,
      pitcher && velocity > 0 ? ((velocity - 146) / 8 + (control - 60) / 25) / 2 : -9,
      pitcher && velocity > 0 ? (velocity - 151) / 6 : -9,
      pitcher ? (control - 66) / 18 : (contact - 66) / 18,
      (age - 31) / 4,
      (24 - age) / 3,
      0.15,
    ];
    var at = 7;
    var best = -99.0;
    for (var i = 0; i < sc.length; i++) {
      final v = sc[i] + (u(0x90 + i) - 0.5) * 0.5;
      if (v > best) {
        best = v;
        at = i;
      }
    }
    // ── ① 顔の比率（計測の統計 × 誇張）──
    const k = 2.5; // 似顔絵の誇張
    final zW = z(0x40) + (bmi - 24) * 0.25 + (at == 0 ? 0.5 : 0) - (at == 1 ? 0.4 : 0); // 顔の幅（頬骨）
    final zJ = 0.6 * zW + 0.8 * z(0x41) + (at == 0 || at == 3 ? 0.7 : 0) - (at == 1 ? 0.7 : 0) - (at == 6 ? 0.3 : 0); // あごの幅（顔の幅と相関）
    final zH = 0.3 * zW + 0.95 * z(0x42) + (at == 1 || at == 5 ? 0.4 : 0) - (at == 6 ? 0.5 : 0); // 顔の高さ（あごの長さ）
    final zI = z(0x43); // 目の間
    final zM = 0.3 * zW + 0.95 * z(0x44); // 口の幅
    final faceW = (1 + k * 0.036 * zW).clamp(0.82, 1.18);
    final jawRel = (1 + k * 0.045 * zJ).clamp(0.78, 1.25);
    final faceH = (1 + k * 0.048 * zH).clamp(0.8, 1.3);
    // 顔の型（パワプロの考え方：ふつう・ホームベース（あごがとがる強キャラ）・長方形（ゴツいパワー型）・面長（のんびり・クセ者））
    final faceShape = jawRel > 1.09 && faceH < 1.12 ? 2 : (faceH > 1.1 && jawRel < 1.03 ? 3 : (jawRel < 0.92 ? 1 : 0));
    // ── ② まぶた ──
    final lid = race == 0 ? wpick(const [0.554, 0.33, 0.108], 0x71) : (u(0x71) < 0.9 ? 1 : 2); // 0 一重 1 二重 2 奥二重（左右で違う）
    // 目の型：0 ふつう 1 キリッ 2 タレ目 3 ジト目 4 細目 5 丸目 6 点目 7 三白眼 8 つぶら 9 鋭い 10 眠そう 11 力強い
    const eyeArch = [
      [2.0, 3, 0.5, 1, 1, 0.5, 0, 3, 0.2, 3, 0.5, 4], // 強打者
      [2.0, 4, 0.5, 1, 2, 1, 0.3, 1, 0.5, 3, 0.3, 2], // 俊足
      [4.0, 3, 1, 0.3, 0.5, 2, 0.2, 0.5, 1, 1, 0.3, 3], // エース
      [1.0, 3, 0.2, 1, 1, 0.3, 0, 4, 0.2, 4, 0.2, 4], // 剛腕
      [3.0, 1, 1, 2, 3, 1, 1, 0.5, 1, 0.5, 2, 1], // 職人
      [3.0, 1, 3, 2, 1, 0.5, 0.5, 1, 0.3, 1, 3, 2], // ベテラン
      [3.0, 1, 1, 0.3, 0.3, 4, 1, 0.2, 4, 0.2, 0.5, 1], // 若手
      [3.0, 1, 3, 2, 1, 2, 2, 0.3, 2, 0.3, 2, 0.5], // ムードメーカー
    ];
    // まぶたとの相性：一重は細め・鋭め、二重は丸め
    const eyeLid = [
      [1.0, 1.4, 0.8, 1.4, 1.8, 0.4, 1.2, 1.3, 0.5, 1.5, 1.3, 1.0], // 一重
      [1.0, 0.8, 1.3, 0.7, 0.4, 1.6, 0.7, 0.8, 1.6, 0.7, 0.8, 1.0], // 二重
      [1.0, 1.0, 1.1, 1.0, 1.0, 1.0, 0.9, 1.0, 1.1, 1.0, 1.0, 1.0], // 奥二重
    ];
    final eyeStyle = wpick([for (var i = 0; i < 12; i++) eyeArch[at][i] * eyeLid[lid][i]], 0x79);
    // 眉の型：0 ふつう 1 太い 2 細い 3 つり 4 困り（八の字） 5 への字 6 ゲジゲジ 7 短い 8 角ばった 9 麻呂
    const browW = [
      [1.0, 4, 0.2, 3, 0.2, 1, 3, 0.5, 2, 0.1],
      [2.0, 1, 2, 3, 0.3, 0.5, 0.3, 1, 2, 0.2],
      [3.0, 2, 1, 2, 0.3, 0.5, 0.5, 0.5, 2, 0.2],
      [1.0, 3, 0.3, 4, 0.1, 1, 2, 0.5, 2, 0.1],
      [3.0, 1, 2, 1, 1, 1, 0.5, 1, 1, 0.5],
      [2.0, 2, 1, 0.5, 2, 3, 2, 0.5, 1, 0.2],
      [2.0, 1, 2, 0.5, 1, 0.3, 0.2, 2, 0.5, 2],
      [2.0, 1, 1, 0.3, 4, 0.5, 0.5, 1, 0.3, 2],
    ];
    final browStyle = wpick(browW[at], 0x72);
    // 髪型：0 短髪 1 スポーツ刈り 2 もみあげ長め 3 アフロ 4 襟足長め 5 坊主 6 ツンツン跳ね髪 7 ウェーブ長髪
    const hairArch = [
      [1.0, 1, 2, 1, 1, 2, 1, 1],
      [1.0, 1, 1, 1, 1, 0.5, 4, 1],
      [2.0, 2, 1, 1, 1, 1, 1, 1],
      [1.0, 1, 1, 1, 2, 1, 2, 2],
      [2.0, 3, 1, 1, 0.5, 2, 0.5, 0.5],
      [2.0, 2, 2, 1, 1, 2, 0.5, 0.5],
      [2.0, 2, 0.5, 1, 0.5, 1, 2, 0.5],
      [1.0, 1, 1, 2, 1, 1, 2, 2],
    ];
    final hairRace = race == 1 ? const [1.0, 3, 0, 3, 0, 2, 1, 0] : const [3.0, 2, 2, 0, 2, 1, 2, 1];
    final hairStyle = wpick([for (var i = 0; i < 8; i++) hairRace[i] * hairArch[at][i]], 0x54);
    // ひげ：0 なし 1 無精ひげ 2 あごひげ 3 口ひげ 4 あごと口 5 濃いひげ
    const beardP = [0.5, 0.12, 0.15, 0.42, 0.15, 0.6, 0.03, 0.22];
    const beardW = [
      [0.0, 2, 2, 1, 2, 3],
      [0.0, 4, 2, 1, 1, 1],
      [0.0, 4, 2, 1, 1, 1],
      [0.0, 2, 4, 1, 2, 1],
      [0.0, 4, 2, 1, 1, 1],
      [0.0, 2, 1, 3, 2, 2],
      [0.0, 4, 2, 1, 1, 1],
      [0.0, 3, 2, 2, 1, 1],
    ];
    final hasBeard = u(0x6d) < beardP[at] + (age >= 30 ? 0.12 : 0) + (race != 0 ? 0.15 : 0);
    final beard = hasBeard ? wpick(beardW[at], 0x6e) : 0;
    // 口：0 小さい線 1 口角が上がる 2 への字 3 厚い唇
    const mouthW = [
      [2.0, 1, 2, 2],
      [3.0, 2, 1, 1],
      [3.0, 2, 1, 1],
      [2.0, 0, 4, 1],
      [3.0, 2, 1, 1],
      [2.0, 1, 3, 1],
      [3.0, 3, 0, 1],
      [1.0, 5, 0, 1],
    ];
    final mw = [for (var i = 0; i < 4; i++) mouthW[at][i] + (race == 1 && i == 3 ? 3.0 : 0)];
    // アクセサリ：0 なし 1 アイブラック 2 スポーツサングラス 3 鼻の絆創膏 4 メガネ
    const accW = [
      [1.6, 0.6, 0.1, 0.05, 0.05],
      [2.0, 0.4, 0.25, 0.05, 0.05],
      [3.0, 0.1, 0.1, 0.05, 0.1],
      [2.0, 0.3, 0.3, 0.05, 0.05],
      [3.0, 0.05, 0.1, 0.05, 0.6],
      [3.0, 0.05, 0.1, 0.05, 0.4],
      [3.0, 0.1, 0.05, 0.2, 0.15],
      [2.0, 0.1, 0.1, 0.7, 0.2],
    ];
    return FaceLook(
      skin: pick(skins, 0x51),
      hair: pick(hairs, 0x52),
      iris: pick(irises, 0x53),
      hairStyle: hairStyle,
      eyeSize: 1 + n(0x60) * 0.12,
      // 目の間：統計のばらつきをそのまま誇張すると離れ目・寄り目が極端で不自然なので、誇張しない（±約 6%）
      eyeGap: (1 + 0.035 * zI).clamp(0.93, 1.07),
      eyeTilt: n(0x62) * 6,
      browThick: (1 + n(0x63) * 0.5 + (browStyle == 1 || browStyle == 6 ? 0.6 : 0) - (browStyle == 2 ? 0.4 : 0)).clamp(0.45, 2.4),
      browAngle: n(0x64) * 10,
      browLen: 1 + n(0x65) * 0.2,
      noseType: 0,
      noseSize: 1,
      mouthWidth: (1 + k * 0.065 * zM).clamp(0.75, 1.3),
      lip: 1 + n(0x69) * 0.25 + (race == 1 ? 0.25 : 0),
      jaw: jawRel,
      chin: faceH,
      cheek: faceW,
      ear: 1,
      beard: beard,
      faceShape: faceShape,
      lid: lid,
      browShape: 0,
      noseLen: 1,
      mouthShape: wpick(mw, 0x74),
      mole: u(0x75) < 0.15 ? stableHash(id, 0x76) % 3 : -1,
      wrinkle: age >= 36 || at == 5 ? 2 : (age >= 32 ? 1 : 0),
      freckles: (race == 2 && u(0x77) < 0.3) || (at == 6 && u(0x77) < 0.12),
      gazeX: n(0x78) * 0.1,
      eyeStyle: eyeStyle,
      browStyle: browStyle,
      accessory: wpick(accW[at], 0x7a),
      archetype: at,
    );
  }
}
