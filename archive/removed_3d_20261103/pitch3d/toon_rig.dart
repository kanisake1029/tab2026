import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../engine/ball_spec.dart';
import '../../engine/body_gen.dart';
import '../../engine/body_model.dart';
import '../../engine/human/human_body.dart';
import '../../engine/pitch_motion.dart' show J;
import '../../engine/play_motion.dart';
import '../../engine/vec3.dart';
import '../../models/player.dart';
import '../../models/uniform.dart';
import 'puppet2d.dart';
import 'scene_util.dart';
import 'sdf_mesh.dart';

/// デフォルメした選手（約5.7頭身・スタイライズド3D）
///  体格（身長・体重・胸囲・腹囲・臀囲・腕の長さ）はそのまま形に効く。顔は部品の組み合わせ（選手の id から。あとで編集できる）
///  手は指ごとに3つの関節（30本の骨）。握り（バット・グラブ・球種ごとのボールの握り）を手の形で表す

// ───────────── 顔の部品 ─────────────

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

// ───────────── 手の形 ─────────────

/// ボールの握り（仕様書 2.2 ②）：人差し指と中指の開き（度）・握りの深さ（0＝指先、1＝手のひらの奥まで）・握り方
///  カーブ・スライダーは 8° で密着、4シームは 24°、フォークは 95° で挟む。指の関節は、指の腹がボールの表面に触れる所まで曲げて求める
class PitchGrip {
  final double splitDeg, depth;
  final bool circle; // チェンジアップ（親指と人差し指で輪）
  final bool knuckle; // ナックル（指先を立てる）
  const PitchGrip(this.splitDeg, this.depth, {this.circle = false, this.knuckle = false});

  static const fourSeam = PitchGrip(24, 0.2), twoSeam = PitchGrip(20, 0.3), curve = PitchGrip(8, 0.35), slider = PitchGrip(8, 0.25);
  static const fork = PitchGrip(95, 0.9), split = PitchGrip(70, 0.7), change = PitchGrip(30, 0.8, circle: true), knuckleBall = PitchGrip(22, 0.4, knuckle: true);

  static PitchGrip ofPitch(String name) {
    if (name.contains('フォーク')) return fork;
    if (name.contains('スプリット')) return split;
    if (name.contains('ナックル')) return knuckleBall;
    if (name.contains('カーブ')) return curve;
    if (name.contains('スライダー') || name.contains('カット') || name.contains('スラーブ')) return slider;
    if (name.contains('チェンジ') || name.contains('シンカー') || name.contains('スクリュー') || name.contains('パーム')) return change;
    if (name.contains('ツーシーム') || name.contains('シュート')) return twoSeam;
    return fourSeam;
  }
}

/// 手の形：指（親指・人差し指・中指・薬指・小指）ごとに3つの関節の曲げ（ラジアン）と、指の開き
class HandPose {
  final List<List<double>> curl; // [5][3]
  final List<double> spread; // [5]（＋＝人差し指の側へ）
  const HandPose(this.curl, [this.spread = const [0, 0, 0, 0, 0]]);

  static const relaxed = HandPose([
    [0.15, 0.2, 0.15],
    [0.25, 0.3, 0.2],
    [0.3, 0.35, 0.2],
    [0.35, 0.4, 0.25],
    [0.4, 0.45, 0.3],
  ]);
  static const open = HandPose([
    [0.05, 0.05, 0.0],
    [0.05, 0.05, 0.03],
    [0.05, 0.05, 0.03],
    [0.05, 0.05, 0.03],
    [0.05, 0.05, 0.03],
  ], [0.1, 0.12, 0.0, -0.08, -0.16]);

  /// 握りこぶし（バット・走るとき）
  static const fist = HandPose([
    [0.7, 0.6, 0.5],
    [1.45, 1.6, 1.1],
    [1.5, 1.6, 1.1],
    [1.5, 1.6, 1.1],
    [1.45, 1.6, 1.1],
  ]);
  static const looseFist = HandPose([
    [0.4, 0.4, 0.3],
    [0.95, 1.1, 0.8],
    [1.0, 1.15, 0.8],
    [1.05, 1.15, 0.8],
    [1.05, 1.15, 0.8],
  ]);

  // ボールの握り（投手・送球）
  /// 直球（フォーシーム）：人差し指と中指をそろえて縫い目にかけ、親指は下
  static const fourSeam = HandPose([
    [1.0, 0.5, 0.3],
    [0.55, 0.45, 0.35],
    [0.55, 0.45, 0.35],
    [1.3, 1.4, 1.0],
    [1.35, 1.45, 1.0],
  ], [0, 0.04, -0.04, 0, 0]);
  static const twoSeam = HandPose([
    [1.0, 0.5, 0.3],
    [0.6, 0.5, 0.35],
    [0.6, 0.5, 0.35],
    [1.2, 1.3, 0.9],
    [1.3, 1.4, 1.0],
  ], [0, 0.02, -0.02, 0, 0]);

  /// フォーク：人差し指と中指を大きく開いてはさむ
  static const fork = HandPose([
    [0.9, 0.4, 0.2],
    [0.35, 0.3, 0.25],
    [0.35, 0.3, 0.25],
    [1.3, 1.4, 1.0],
    [1.35, 1.45, 1.0],
  ], [0, 0.32, -0.32, -0.1, -0.1]);

  /// カーブ：中指を縫い目にかけ、手首を立てる
  static const curve = HandPose([
    [1.1, 0.7, 0.4],
    [0.75, 0.8, 0.5],
    [0.6, 0.6, 0.45],
    [1.3, 1.4, 1.0],
    [1.35, 1.45, 1.0],
  ], [0, 0.02, -0.02, 0, 0]);

  /// スライダー：人差し指と中指をボールの外側へずらす
  static const slider = HandPose([
    [1.05, 0.55, 0.3],
    [0.6, 0.55, 0.4],
    [0.55, 0.5, 0.4],
    [1.3, 1.4, 1.0],
    [1.35, 1.45, 1.0],
  ], [0, -0.05, -0.12, 0, 0]);

  /// チェンジアップ（サークル）：親指と人差し指で輪を作り、残りの3本で包む
  static const change = HandPose([
    [1.3, 0.8, 0.6],
    [1.2, 1.3, 1.0],
    [0.45, 0.4, 0.3],
    [0.5, 0.45, 0.35],
    [0.7, 0.6, 0.4],
  ], [0, 0.0, 0.0, -0.06, -0.12]);

  /// ナックル：指先を立てて爪でつかむ
  static const knuckle = HandPose([
    [1.0, 0.5, 0.3],
    [0.35, 1.6, 1.3],
    [0.35, 1.6, 1.3],
    [0.4, 1.5, 1.2],
    [1.3, 1.4, 1.0],
  ]);

  /// 球種の名前から握り
  static HandPose ofPitch(String name) {
    if (name.contains('フォーク') || name.contains('スプリット')) return fork;
    if (name.contains('ナックル')) return knuckle;
    if (name.contains('カーブ')) return curve;
    if (name.contains('スライダー') || name.contains('カット') || name.contains('スラーブ')) return slider;
    if (name.contains('チェンジ') || name.contains('シンカー') || name.contains('スクリュー') || name.contains('パーム')) return change;
    if (name.contains('ツーシーム') || name.contains('シュート')) return twoSeam;
    return fourSeam;
  }

  static HandPose lerp(HandPose a, HandPose b, double t) => HandPose(
        [for (var f = 0; f < 5; f++) [for (var s = 0; s < 3; s++) a.curl[f][s] + (b.curl[f][s] - a.curl[f][s]) * t]],
        [for (var f = 0; f < 5; f++) a.spread[f] + (b.spread[f] - a.spread[f]) * t],
      );
}

// ───────────── 人 ─────────────

class ToonRig implements PlayerRig {
  final FaceLook face;
  final Uniform uni;
  final bool lefty; // 投げる腕（T）が左
  final bool glove; // グラブの手（G）にグラブをはめる
  final bool helmet; // 帽子の代わりにヘルメット
  final Node root = Node();
  late final BodyModel body; // デフォルメした体（動きの計算に使う）
  late final double headR;
  late final List<Node> joints; // 0〜14 体、15〜29 T の指、30〜44 G の指
  late final List<vm.Matrix4> _bindG;
  late final List<V3> _bindJ;
  late final HumanBody human; // Layer 1：関節の角度・可動域・IK
  HandPose handT = HandPose.relaxed, handG = HandPose.relaxed;

  /// ボールを握る（T の手）：球種の握りで指をボールに沿わせる。null で離す
  void holdBall(PitchGrip? g) {
    if (g == null) {
      _ballLocal = null;
      return;
    }
    final w = _gripCache[g] ??= _hands[0].wrap(g);
    handT = w.$1;
    _ballLocal = w.$2;
  }

  final Map<PitchGrip, (HandPose, V3)> _gripCache = {};
  V3? _ballLocal; // 握ったボールの中心（立った姿勢の手の座標）
  V3? _ballNow;

  /// 握ったボールの中心（いまの姿勢）。握っていなければ握りの穴
  V3 get ballPoint => _ballNow ?? _gripNow[0];

  // 指の骨の作り（立った姿勢＝本塁基準の座標で、原点に立って +y を向く）
  late final List<_Hand> _hands; // [T, G]

  /// 頭身・太さ（参考の画面に合わせたデフォルメ）
  static const heads = 4.5, limbThick = 1.42, torsoThick = 1.15;

  ToonRig(this.face, this.uni, {required BodyModel real, this.lefty = false, this.glove = true, this.helmet = false}) {
    // 約4.5頭身（参考：大きな頭・太く短めの手足）。頭を大きくした分、首から下を同じ割合で縮めて身長をそろえる
    //  身長・腕の長さ・体重・周囲などの設定は、縮めたあとの長さ・太さにそのまま比例して効く
    final h = real.height;
    headR = h / heads / 2;
    final neck = real.neck * 0.45;
    // 股関節の高さ＋胴（骨盤〜首の付け根）を k 倍、首は短く、頭は 2R
    final k = (h - 2 * headR - neck) / (real.hipJointH + real.trunk);
    body = real.copyWith(
      height: h,
      upperArm: real.upperArm * k,
      forearm: real.forearm * k,
      hand: real.hand * 1.22,
      thigh: real.thigh * k,
      shank: real.shank * k,
      hipJointH: real.hipJointH * k,
      trunk: real.trunk * k,
      neck: neck,
      headR: headR,
      shoulderW: real.shoulderW * 1.18,
      hipW: real.hipW * 1.15,
    );
    joints = [for (var i = 0; i < 45; i++) Node()];
    for (final j in joints) {
      root.add(j);
    }
    human = HumanBody(body, lefty: lefty);
    final bo = human.fk(human.fit(Poser(body, lefty: lefty).stand(V3.zero, 0)));
    _bindJ = bo.p;
    final fr = _framesOf(bo);
    _hands = [_Hand(this, true), _Hand(this, false)];
    _bindG = [
      ...fr,
      for (final hd in _hands) ...hd.frames(HandPose.relaxed, null),
    ];
    for (var i = 0; i < joints.length; i++) {
      joints[i].localTransform = _bindG[i];
    }
    _build();
  }

  /// 関節の位置（本塁基準の座標）と手の形で動かす
  /// 手の向きを決める（握りの穴＝小指 → 人差し指の向きを、この向きにそろえる。null なら腕の曲がりから）
  V3? aimT, aimG;

  /// 手のひら（グラブのポケット）の向き・指の向きの指定（仕様書 2.2：捕るときはポケットをボールへ正対させる）
  V3? palmT, palmG, fingerT, fingerG;

  /// 握りの穴の中心（いまの姿勢・本塁基準の座標）。バットはここを通す
  V3 gripPoint(bool t) => _gripNow[t ? 0 : 1];
  final List<V3> _gripNow = [V3.zero, V3.zero];

  /// 関節の目標の位置（Layer 2）→ Layer 1 で可動域内の角度にして動かす
  void pose(List<V3> p, {V3? look}) => poseOut(human.fk(prepare(p, look: look)));

  /// 目標の位置 → 角度（手の向きの指定 palm・aim も、前腕のねじりと手首の2軸で可動域の中で合わせる）
  HumanPose prepare(List<V3> p, {V3? look}) {
    final q = human.fit(p, look: look);
    orientHands(q);
    return q;
  }

  /// 手の向きの指定（palm／aim）を角度に入れる
  void orientHands(HumanPose q) {
    if (palmT == null && palmG == null && aimT == null && aimG == null) return;
    final o = human.fk(q);
    for (var hi = 0; hi < 2; hi++) {
      final palm = hi == 0 ? palmT : palmG, aim = hi == 0 ? aimT : aimG;
      final fa = o.forearm[hi] * const V3(0, 0, -1);
      if (palm != null && aim != null) {
        // 握ったまま手のひらの向きも（打撃のインパクト）：握りの穴はバットの向き、手のひらは指定の向き
        human.orientHand(q, o, hi, palm: palm, aim: aim, wPalm: 0.6, wAim: 1);
      } else if (palm != null) {
        human.orientHand(q, o, hi, palm: palm, finger: (hi == 0 ? fingerT : fingerG) ?? fa);
      } else if (aim != null) {
        // 握る：親指の側（握りの穴）をバットの向きへ、指は前腕の向きからバットの成分を除いた向き
        final fp = fa.perpTo(aim.unit);
        human.orientHand(q, o, hi, aim: aim, finger: fp.length > 0.2 ? fp.unit : null, wFinger: 0.4);
      }
    }
  }

  /// Layer 1 の順運動学の結果で、骨・指を動かす
  void poseOut(HumanOut o) {
    final fr = _framesOf(o);
    for (var i = 0; i < 15; i++) {
      joints[i].localTransform = fr[i];
    }
    for (var hi = 0; hi < 2; hi++) {
      final hd = _hands[hi];
      final bone = hi == 0 ? 5 : 8;
      final m = fr[bone] * vm.Matrix4.inverted(_bindG[bone]);
      final g = m.transformed3(sv(hd.grip));
      _gripNow[hi] = V3(-g.x, g.z, g.y);
      if (hi == 0) {
        final bl = _ballLocal;
        if (bl == null) {
          _ballNow = null;
        } else {
          final c = m.transformed3(sv(bl));
          _ballNow = V3(-c.x, c.z, c.y);
        }
      }
    }
    final ft = _hands[0].frames(handT, fr[5]), fg = _hands[1].frames(glove ? HandPose.relaxed : handG, fr[8]);
    for (var i = 0; i < 15; i++) {
      joints[15 + i].localTransform = ft[i];
      joints[30 + i].localTransform = fg[i];
    }
  }

  /// 骨の向き（原点・骨の向き y・横の軸 x）→ 3D の行列
  static List<vm.Matrix4> _framesOf(HumanOut o) => [
        for (var i = 0; i < 15; i++) _boneM(o.org[i], o.y[i], o.x[i]),
      ];
  static vm.Matrix4 _boneM(V3 org, V3 yw, V3 xw) {
    final y = sv(yw)..normalize();
    var x = sv(xw);
    x = x - y * x.dot(y);
    if (x.length < 1e-6) x = (vm.Vector3(1, 0, 0) - y * y.x);
    x.normalize();
    final z = x.cross(y)..normalize();
    final o = sv(org);
    return vm.Matrix4.identity()
      ..setColumn(0, vm.Vector4(x.x, x.y, x.z, 0))
      ..setColumn(1, vm.Vector4(y.x, y.y, y.z, 0))
      ..setColumn(2, vm.Vector4(z.x, z.y, z.z, 0))
      ..setColumn(3, vm.Vector4(o.x, o.y, o.z, 1));
  }

  // ───────── 形 ─────────
  void _build() {
    final b = body;
    final bj = _bindJ;
    V3 j(J x) => bj[x.index];
    final eyeW = _MB(this), iris = _MB(this), pupil = _MB(this), shine = _MB(this), brow = _MB(this), mouth = _MB(this), hair = _MB(this);
    final cap = _MB(this), brim = _MB(this), belt = _MB(this), pocket = _MB(this);
    const ex = V3.ex, ey = V3.ey, ez = V3.ez;
    final sT = lefty ? -1.0 : 1.0;

    // ── 胴（ユニフォームの上着）：腰・腹・胸・肩の塊を溶かし合わせる ──
    final pel = j(J.pelvis), neck = j(J.neck);
    final tl = neck.z - pel.z;
    final shirtP = <SdfPrim>[];
    final pantsP = <SdfPrim>[];
    final underP = <SdfPrim>[];
    final socksP = <SdfPrim>[];
    final shoesP = <SdfPrim>[];
    const cl = 0.014; // 服のゆとり
    const tk = torsoThick, lk = limbThick;
    shirtP.addAll([
      Ellipsoid.aligned(pel + ez * (tl * 0.22), b.waistA * tk + cl, b.waistB * tk + cl, tl * 0.28, [(0, 0.5), (1, 0.5)], blend: 0.035),
      Ellipsoid.aligned(pel + ez * (tl * 0.48), b.waistA * 1.04 * tk + cl, b.waistB * 1.04 * tk + cl, tl * 0.3, [(1, 1.0)], blend: 0.035),
      Ellipsoid.aligned(pel + ez * (tl * 0.74), b.chestA * 1.12 * tk + cl, b.chestB * tk + cl, tl * 0.32, [(1, 1.0)], blend: 0.035),
      Ellipsoid.aligned(neck - ez * 0.05, b.shoulderW * 0.52 + cl, b.chestB * 0.8 * tk + cl, 0.08, [(1, 1.0)], blend: 0.03), // 肩幅の広い四角い肩
    ]);
    // ベルトとズボンの腰まわり
    final beltZ = pel.z + 0.035;
    belt.loft([
      _Ring(V3(pel.x, pel.y, beltZ - 0.022), ex, ey, b.waistA + cl + 0.006, b.waistB + cl + 0.006, [(0, 1.0)]),
      _Ring(V3(pel.x, pel.y, beltZ + 0.022), ex, ey, b.waistA + cl + 0.006, b.waistB + cl + 0.006, [(0, 0.8), (1, 0.2)]),
    ]);
    pantsP.add(Ellipsoid.aligned(pel + ez * (-0.005), b.hipA * 0.96 * tk + 0.016, b.hipB * 0.9 * tk + 0.016, 0.13, [(0, 1.0)], blend: 0.035));
    pantsP.add(Ellipsoid.aligned(pel + ez * (0.05), b.waistA + cl + 0.004, b.waistB + cl + 0.004, 0.05, [(0, 1.0)], blend: 0.04));
    // ── 首・頭（肌）──
    final hd = j(J.head);
    final up = (hd - neck).unit;
    final hc = hd + up * (headR * 0.05);
    final head = _SdfCollect();
    head.prims.add(RoundCone(neck - up * 0.04, hc - up * (headR * 0.55), headR * 0.44, headR * 0.4, (t) => t < 0.4 ? [(1, 1 - t * 1.5), (2, t * 1.5)] : [(2, 1.0)], blend: 0.03));
    _face(hc, head, hair, eyeW, iris, pupil, shine, brow, mouth);
    // 帽子・ヘルメット
    if (helmet) {
      cap.ellipsoid(hc + ez * (headR * 0.12) - ey * (headR * 0.04), ex * (headR * 1.1), ey * (headR * 1.16), ez * (headR * 1.02), [(2, 1.0)], upperOnly: true);
      cap.ellipsoid(hc + ez * (headR * 0.12) - ey * (headR * 0.3), ex * (headR * 1.06), ey * (headR * 0.86), ez * (headR * 0.55), [(2, 1.0)], lowerOnly: true); // 後頭部を覆う
      brim.ellipsoid(hc + ey * (headR * 1.08) + ez * (headR * 0.2), ex * (headR * 0.62), ey * (headR * 0.3), ez * (headR * 0.05), [(2, 1.0)]);
      // 投手側の耳当て（耳を覆う板。右打者は左耳）
      final side = -sT;
      cap.ellipsoid(hc + ex * (side * headR * 0.97) + ez * (-headR * 0.08) + ey * (headR * 0.08), ex * (headR * 0.12), ey * (headR * 0.42), ez * (headR * 0.46), [(2, 1.0)]);
    } else {
      cap.ellipsoid(hc + ez * (headR * 0.18), ex * (headR * 1.04), ey * (headR * 1.08), ez * (headR * 0.92), [(2, 1.0)], upperOnly: true);
      brim.ellipsoid(hc + ey * (headR * 1.05) + ez * (headR * 0.22), ex * (headR * 0.7), ey * (headR * 0.52), ez * (headR * 0.04), [(2, 1.0)]);
    }
    // ── 腕：肩の丸み・上腕・前腕（アンダーシャツ）、半袖（上着）──
    for (final t in [true, false]) {
      final sh = j(t ? J.shoulderT : J.shoulderG), el = j(t ? J.elbowT : J.elbowG), wr2 = j(t ? J.wristT : J.wristG);
      final bu = t ? 3 : 6, bf = t ? 4 : 7, bh = t ? 5 : 8;
      final ru = b.upperArmR * 1.08 * lk, rf = b.forearmR * 1.05 * lk;
      shirtP.add(Ellipsoid.aligned(sh + ez * 0.008 - V3(sh.x - neck.x, 0, 0) * 0.15, ru * 1.4 + cl, ru * 1.4 + cl, ru * 1.4 + cl, [(1, 0.8), (bu, 0.2)], blend: 0.05)); // 肩は胴について動く
      shirtP.add(RoundCone(sh, sh + (el - sh) * 0.55, ru * 1.12 + cl, ru * 0.98 + cl, (u) => [(bu, 1.0)], blend: 0.02));
      underP.add(RoundCone(sh + (el - sh) * 0.3, el, ru * 0.98 + 0.004, ru * 0.82 + 0.004, (u) => [(bu, 1.0)], blend: 0.015));
      underP.add(RoundCone(el, wr2 - (wr2 - el).unit * 0.01, rf * 0.98 + 0.004, rf * 0.62 + 0.004, (u) => u < 0.9 ? [(bf, 1.0)] : [(bf, 0.7), (bh, 0.3)], blend: 0.015));
    }
    // ── 手（肌）・グラブ ──
    final skinHands = <SdfPrim>[];
    final leatherP = <SdfPrim>[];
    for (var hi = 0; hi < 2; hi++) {
      final hand = _hands[hi];
      if (hi == 1 && glove) {
        leatherP.addAll(hand.mittPrims());
        hand.pocketShape(pocket);
      } else {
        skinHands.addAll(hand.prims());
      }
    }
    // ── 脚：ズボン（膝の下まで）・ストッキング・スパイク ──
    for (final t in [true, false]) {
      final hip = j(t ? J.hipT : J.hipG), kn = j(t ? J.kneeT : J.kneeG), an = j(t ? J.ankleT : J.ankleG), toe = j(t ? J.toeT : J.toeG);
      final bt = t ? 9 : 12, bs = t ? 10 : 13, bft = t ? 11 : 14;
      final rt = b.thighR * 1.08 * lk, rs = b.shankR * 1.05 * lk;
      pantsP.add(RoundCone(hip + ez * 0.03, kn, rt * 1.05 + 0.022, rt * 0.72 + 0.022, (u) => [(bt, 1.0)], blend: 0.04));
      pantsP.add(RoundCone(kn, kn + (an - kn) * 0.42, rs * 1.0 + 0.022, rs * 0.92 + 0.022, (u) => [(bs, 1.0)], blend: 0.03));
      socksP.add(RoundCone(kn + (an - kn) * 0.3, an + ez * 0.02, rs * 1.0 + 0.006, rs * 0.6 + 0.006, (u) => u < 0.92 ? [(bs, 1.0)] : [(bs, 0.6), (bft, 0.4)], blend: 0.02));
      socksP.add(Ellipsoid.aligned(kn + (an - kn) * 0.35 - ey * 0.012, rs * 0.95 + 0.006, rs * 1.08 + 0.006, (an - kn).length * 0.2, [(bs, 1.0)], blend: 0.03)); // ふくらはぎ
      final fd = (toe - an);
      final fdir = V3(fd.x, fd.y, 0).unit;
      final fl = V3(fd.x, fd.y, 0).length;
      final fside = V3(fdir.y, -fdir.x, 0);
      shoesP.add(Ellipsoid(V3(an.x, an.y, 0.045) + fdir * (fl * 0.4), fside, fdir, ez, rs * 0.92, fl * 0.85 + 0.03, 0.05, [(bft, 0.9), (bs, 0.1)], blend: 0.02));
      shoesP.add(Ellipsoid(V3(an.x, an.y, 0.07) - fdir * 0.01, fside, fdir, ez, rs * 0.85, rs * 0.95, 0.07, [(bft, 0.5), (bs, 0.5)], blend: 0.025));
    }

    final shirt = _MB(this)..surface(buildSurface(shirtP, cell: 0.012));
    final under = _MB(this)..surface(buildSurface(underP, cell: 0.009));
    final pants = _MB(this)..surface(buildSurface(pantsP, cell: 0.012));
    final socks = _MB(this)..surface(buildSurface(socksP, cell: 0.009));
    final shoes = _MB(this)..surface(buildSurface(shoesP, cell: 0.008));
    final skin = _MB(this)
      ..surface(buildSurface(head.prims, cell: 0.0055, maxCells: 320000, weightSoft: 0.01))
      ..surface(buildSurface(skinHands.where((p) => _hands[0].owns(p)).toList(), cell: 0.0032, weightSoft: 0.004))
      ..surface(buildSurface(skinHands.where((p) => !_hands[0].owns(p)).toList(), cell: 0.0032, weightSoft: 0.004));

    const rough = 0.88; // 平らな陰影に近づける（光沢を抑える）
    root.add(skin.node(mat(face.skin, rough: 0.9)));
    root.add(shirt.node(mat(uni.base, rough: rough)));
    root.add(under.node(mat(uni.undershirt, rough: rough)));
    root.add(pants.node(mat(uni.base, rough: rough)));
    root.add(socks.node(mat(uni.socks, rough: rough)));
    root.add(shoes.node(mat(uni.shoes, rough: 0.55)));
    root.add(belt.node(mat(uni.belt, rough: 0.6)));
    root.add(cap.node(mat(helmet ? uni.helmet : uni.capBase, rough: helmet ? 0.3 : 0.75)));
    root.add(brim.node(mat(helmet ? uni.helmet : uni.capBrim, rough: helmet ? 0.3 : 0.75)));
    root.add(hair.node(mat(face.hair, rough: 0.9)));
    root.add(eyeW.node(mat(0xFFF7F4EF, rough: 0.5)));
    root.add(iris.node(mat(face.iris, rough: 0.4)));
    root.add(pupil.node(mat(0xFF0B0B0B, rough: 0.3)));
    root.add(shine.node(mat(0xFFFFFFFF, rough: 0.1)));
    root.add(brow.node(mat(face.hair, rough: 0.95)));
    root.add(mouth.node(mat(_mix(face.skin, 0xFF8A3B32, 0.55), rough: 0.7)));
    if (glove) {
      root.add((_MB(this)..surface(buildSurface(leatherP, cell: 0.007))).node(mat(uni.glove, rough: 0.6)));
      root.add(pocket.node(mat(_mix(uni.glove, 0xFF000000, 0.25), rough: 0.7)));
    }
  }

  static int _mix(int a, int c, double t) {
    int ch(int s) => (((a >> s) & 255) * (1 - t) + ((c >> s) & 255) * t).round().clamp(0, 255);
    return 0xFF000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }

  /// 顔：輪郭（頭・あご・頬・あご先）・耳・目（白目・瞳・黒目・光）・眉・鼻・口・ひげ・髪
  void _face(V3 c, _SdfCollect skin, _MB hair, _MB eyeW, _MB iris, _MB pupil, _MB shine, _MB brow, _MB mouth) {
    final f = face;
    final R = headR;
    const ex = V3.ex, ey = V3.ey, ez = V3.ez;
    const w = [(2, 1.0)];
    // 頭の形：後頭部が丸く、顔は少し前へ
    skin.ellipsoid(c + ez * (R * 0.08), ex * (R * 0.9), ey * (R * 0.95), ez * (R * 1.0), w);
    // あご・頬
    skin.ellipsoid(c + ez * (-R * 0.38) + ey * (R * 0.18), ex * (R * 0.74 * f.jaw * f.cheek), ey * (R * 0.72), ez * (R * 0.6), w);
    // あご先
    skin.ellipsoid(c + ez * (-R * (0.78 + 0.08 * (f.chin - 1))) + ey * (R * 0.5), ex * (R * 0.3 * f.jaw), ey * (R * 0.28), ez * (R * 0.22 * f.chin), w);
    // 耳
    for (final s in [-1.0, 1.0]) {
      skin.ellipsoid(c + ex * (s * R * 0.9) + ez * (-R * 0.06) + ey * (-R * 0.02), ex * (R * 0.1), ey * (R * 0.17 * f.ear), ez * (R * 0.26 * f.ear), w, blend: 0.012);
    }
    // 目：顔の前面に沿って少し内向き。つり目は外側を上げる
    final eyeZ = c.z + R * 0.06;
    for (final s in [-1.0, 1.0]) {
      final ox = s * R * 0.34 * f.eyeGap;
      final ec = V3(c.x + ox, c.y + R * 0.84, eyeZ);
      final tilt = s * f.eyeTilt * deg; // 外側を上げる
      final ax = (ex * math.cos(tilt) + ez * math.sin(tilt));
      final az = (ez * math.cos(tilt) - ex * math.sin(tilt));
      final es = R * 0.155 * f.eyeSize;
      eyeW.ellipsoid(ec, ax * es, ey * (R * 0.07), az * (es * 0.72), w);
      final ic = ec + ey * (R * 0.055) + ex * (-s * R * 0.01);
      iris.ellipsoid(ic, ax * (es * 0.52), ey * (R * 0.025), az * (es * 0.6), w);
      pupil.ellipsoid(ic + ey * (R * 0.018), ax * (es * 0.26), ey * (R * 0.015), az * (es * 0.3), w);
      shine.ellipsoid(ic + ey * (R * 0.03) + ax * (-es * 0.18) + az * (es * 0.22), ax * (es * 0.11), ey * (R * 0.01), az * (es * 0.11), w);
      // 上まぶたの線（髪の色の細い帯）
      brow.ellipsoid(ec + ey * (R * 0.03) + az * (es * 0.6), ax * (es * 1.05), ey * (R * 0.03), az * (es * 0.14), w);
      // 眉
      final ba = s * -f.browAngle * deg + tilt * 0.5;
      final bx = ex * math.cos(ba) + ez * math.sin(ba);
      final bz = ez * math.cos(ba) - ex * math.sin(ba);
      brow.ellipsoid(V3(c.x + ox * 1.05, c.y + R * 0.86, eyeZ + R * 0.24), bx * (R * 0.2 * f.browLen), ey * (R * 0.06), bz * (R * 0.045 * f.browThick), w);
    }
    // 鼻
    final nc = V3(c.x, c.y + R * 0.95, c.z - R * 0.14);
    final ns = R * f.noseSize;
    switch (f.noseType) {
      case 1: // すっと長い
        skin.ellipsoid(nc + ez * (R * 0.08), ex * (ns * 0.09), ey * (ns * 0.14), ez * (ns * 0.26), w);
        skin.ellipsoid(nc + ey * (ns * 0.06) + ez * (-ns * 0.08), ex * (ns * 0.12), ey * (ns * 0.1), ez * (ns * 0.08), w);
      case 2: // 幅広
        skin.ellipsoid(nc, ex * (ns * 0.17), ey * (ns * 0.13), ez * (ns * 0.16), w);
        for (final s in [-1.0, 1.0]) {
          skin.ellipsoid(nc + ex * (s * ns * 0.1) + ez * (-ns * 0.06), ex * (ns * 0.08), ey * (ns * 0.08), ez * (ns * 0.07), w);
        }
      case 3: // わし鼻（鼻筋が高い）
        skin.ellipsoid(nc + ez * (R * 0.1) + ey * (ns * 0.04), ex * (ns * 0.08), ey * (ns * 0.16), ez * (ns * 0.24), w);
        skin.ellipsoid(nc + ey * (ns * 0.1) + ez * (-ns * 0.04), ex * (ns * 0.1), ey * (ns * 0.11), ez * (ns * 0.09), w);
      default: // 小さい丸
        skin.ellipsoid(nc, ex * (ns * 0.12), ey * (ns * 0.12), ez * (ns * 0.13), w);
    }
    // 口
    final mc = V3(c.x, c.y + R * 0.82, c.z - R * 0.42);
    mouth.ellipsoid(mc, ex * (R * 0.2 * f.mouthWidth), ey * (R * 0.06), ez * (R * 0.035 * f.lip), w);
    // ひげ
    final beardC = _mix(f.skin, f.hair, 0.55);
    if (f.beard > 0) {
      final bm = _MB(this);
      final dark = f.beard == 1 || f.beard == 5;
      if (dark) bm.ellipsoid(c + ez * (-R * 0.42) + ey * (R * 0.2), ex * (R * 0.78 * f.jaw * f.cheek), ey * (R * 0.75), ez * (R * 0.58), w, lowerOnly: true);
      if (f.beard == 2 || f.beard == 4 || f.beard == 5) bm.ellipsoid(c + ez * (-R * 0.8) + ey * (R * 0.52), ex * (R * 0.26), ey * (R * 0.24), ez * (R * 0.2), w);
      if (f.beard == 3 || f.beard == 4 || f.beard == 5) bm.ellipsoid(mc + ez * (R * 0.08) + ey * (R * 0.02), ex * (R * 0.22), ey * (R * 0.05), ez * (R * 0.05), w);
      root.add(bm.node(mat(f.beard == 1 ? _mix(f.skin, f.hair, 0.3) : beardC, rough: 0.95)));
    }
    // 髪（帽子・ヘルメットの下から見える所：もみあげ・えり足・前髪）
    final hs = f.hairStyle;
    final vol = hs == 3 ? 1.12 : (hs == 5 ? 1.0 : 1.03);
    if (hs != 5) {
      hair.ellipsoid(c + ez * (R * 0.05) + ey * (-R * 0.08), ex * (R * 0.94 * vol), ey * (R * 0.92 * vol), ez * (R * 1.0 * vol), w, upperOnly: true, cutFront: true);
    }
    for (final s in [-1.0, 1.0]) {
      final len = hs == 2 ? 0.34 : (hs == 5 ? 0.12 : 0.22);
      hair.ellipsoid(c + ex * (s * R * 0.86) + ey * (R * 0.22) + ez * (-R * 0.02), ex * (R * 0.07), ey * (R * 0.1), ez * (R * len), w);
    }
    if (hs == 4 || hs == 3) {
      hair.ellipsoid(c + ey * (-R * 0.55) + ez * (-R * 0.3), ex * (R * 0.62), ey * (R * 0.3), ez * (R * (hs == 4 ? 0.42 : 0.35)), w);
    }
  }
}

/// 1本の手（指の骨とその形）。右手か左手かは、立った姿勢の手首の位置で決める
class _Hand {
  final ToonRig rig;
  final bool t; // T の手
  late final V3 wrist, dir, palmN, across;
  late final double size; // 手の長さ（手首〜中指の先）
  late final List<V3> base; // 指の付け根
  late final List<V3> fdir; // 指の向き（曲げる前）
  late final List<List<double>> seg; // 指の節の長さ
  late final List<double> rad; // 指の太さ
  late final V3 grip; // 握りの穴の中心（立った姿勢）

  _Hand(this.rig, this.t) {
    final bj = rig._bindJ;
    wrist = bj[(t ? J.wristT : J.wristG).index];
    final mid = bj[(t ? J.ball : J.glove).index];
    dir = (mid - wrist).unit;
    final right = wrist.x > 0; // 体の右側の手
    final inward = V3(-wrist.x, 0, 0).unit; // 手のひらは体の方を向く
    palmN = inward.perpTo(dir).unit;
    final a = dir.cross(palmN).unit;
    across = right ? a : -a; // 小指 → 人差し指の向き（親指の側）
    size = rig.body.hand;
    final w = size * 0.48; // 手のひらの幅
    final kn = wrist + dir * (size * 0.45); // 指の付け根の並び
    base = [
      wrist + dir * (size * 0.12) + across * (w * 0.42) + palmN * (size * 0.05), // 親指
      kn + across * (w * 0.36),
      kn + across * (w * 0.12) + dir * (size * 0.01),
      kn - across * (w * 0.12),
      kn - across * (w * 0.34) - dir * (size * 0.03),
    ];
    final fl = size * 0.55;
    seg = [
      [fl * 0.36, fl * 0.3, fl * 0.26],
      [fl * 0.42, fl * 0.27, fl * 0.22],
      [fl * 0.45, fl * 0.3, fl * 0.24],
      [fl * 0.42, fl * 0.29, fl * 0.23],
      [fl * 0.33, fl * 0.22, fl * 0.2],
    ];
    rad = [size * 0.06, size * 0.05, size * 0.052, size * 0.049, size * 0.043];
    grip = wrist + dir * (size * 0.42) + palmN * (size * 0.14);
    fdir = [
      (dir * 0.55 + across * 0.65 + palmN * 0.35).unit,
      (dir + across * 0.06).unit,
      dir,
      (dir - across * 0.04).unit,
      (dir - across * 0.1).unit,
    ];
  }

  /// ボールを握る形（仕様書 2.2 ②）：ボールの中心を手のひらの前に置き、指は付け根から順に、指の腹がボールに触れる角度まで曲げる
  (HandPose, V3) wrap(PitchGrip g) {
    const r = BallSpec.radius;
    final c = wrist + dir * (size * (0.66 - 0.16 * g.depth)) + palmN * (r + size * (0.10 - 0.05 * g.depth));
    final half = g.splitDeg * math.pi / 180 / 2;
    final spread = [0.0, half * 0.9, -half * 0.9, -half * 0.6 - 0.05, -half * 0.5 - 0.12];
    final curl = [for (var f = 0; f < 5; f++) [0.0, 0.0, 0.0]];
    for (var f = 0; f < 5; f++) {
      if (g.circle && f == 1) {
        curl[f] = [1.3, 1.25, 0.9]; // 親指と輪を作る
        continue;
      }
      if (!g.circle && f >= 3) {
        curl[f] = [1.25, 1.35, 0.95]; // 薬指・小指は折りたたんでボールの横を支える
        continue;
      }
      for (var sI = 0; sI < 3; sI++) {
        // この関節の曲げを 0 から増やし、節の先がボールの表面（＋指の太さ）に触れた所で止める
        var best = 0.0, bestErr = double.infinity;
        for (var a = 0.0; a <= 1.75; a += 0.04) {
          curl[f][sI] = a;
          final ch = _chain(HandPose(curl, spread));
          final (p, d, _) = ch[f * 3 + sI];
          final tip = p + d * seg[f][sI];
          final err = tip.distanceTo(c) - (r + rad[f] * 0.9);
          if (err.abs() < bestErr) {
            bestErr = err.abs();
            best = a;
          }
          if (err <= 0) break;
        }
        curl[f][sI] = best;
      }
      if (g.knuckle && (f == 1 || f == 2)) curl[f][1] += 0.5; // 指先を立てて爪でつかむ
    }
    return (HandPose(curl, spread), c);
  }

  /// 指の節（指ごとに3つ）の、曲げたあとの位置と向き（立った姿勢の座標）
  List<(V3, V3, V3)> _chain(HandPose hp) {
    final out = <(V3, V3, V3)>[];
    for (var f = 0; f < 5; f++) {
      var d = fdir[f].rotate(palmN, hp.spread[f] * (across.dot(V3.ex) >= 0 ? 1 : 1)); // 指を開く（手のひらの法線のまわり）
      // 曲げる軸：指の向き × 手のひらの法線（親指は手のひらを横切るように）
      final axis = (f == 0 ? d.cross(palmN) * 0.6 + dir * 0.4 : d.cross(palmN)).unit;
      var p = base[f];
      for (var s = 0; s < 3; s++) {
        d = d.rotate(axis, hp.curl[f][s]);
        out.add((p, d, axis));
        p = p + d * seg[f][s];
      }
    }
    return out;
  }

  static vm.Matrix4 _frame(V3 o, V3 y, V3 x) {
    final yy = sv(y)..normalize();
    var xx = sv(x);
    xx = (xx - yy * xx.dot(yy))..normalize();
    final zz = xx.cross(yy)..normalize();
    final p = sv(o);
    return vm.Matrix4.identity()
      ..setColumn(0, vm.Vector4(xx.x, xx.y, xx.z, 0))
      ..setColumn(1, vm.Vector4(yy.x, yy.y, yy.z, 0))
      ..setColumn(2, vm.Vector4(zz.x, zz.y, zz.z, 0))
      ..setColumn(3, vm.Vector4(p.x, p.y, p.z, 1));
  }

  /// 指の骨の行列（hand：いまの手の骨。null なら立った姿勢のまま）
  List<vm.Matrix4> frames(HandPose hp, vm.Matrix4? hand) {
    final ch = _chain(hp);
    final local = [for (final c in ch) _frame(c.$1, c.$2, c.$3)];
    if (hand == null) return local;
    final rel = hand * vm.Matrix4.inverted(_bindHandM);
    return [for (final m in local) rel * m];
  }

  vm.Matrix4 get _bindHandM => rig._bindG[t ? 5 : 8];

  int _bone(int f, int s) => (t ? 15 : 30) + f * 3 + s;
  int get _handBone => t ? 5 : 8;

  final Set<SdfPrim> _mine = {};
  bool owns(SdfPrim p) => _mine.contains(p);

  /// 手のひらと指（肌）：指の節ごとに骨。指どうしは溶け合わないように、溶かす幅を小さく
  List<SdfPrim> prims() {
    final w = size * 0.48;
    final out = <SdfPrim>[
      Ellipsoid(wrist + dir * (size * 0.25), across, dir, palmN, w * 0.52, size * 0.25, size * 0.11, [(_handBone, 1.0)], blend: 0.012),
      Ellipsoid(wrist + dir * (size * 0.05), across, dir, palmN, w * 0.4, size * 0.1, size * 0.1, [(_handBone, 1.0)], blend: 0.015),
    ];
    final ch = _chain(HandPose.relaxed);
    for (var f = 0; f < 5; f++) {
      for (var s = 0; s < 3; s++) {
        final (p, d, _) = ch[f * 3 + s];
        final r = rad[f] * (1 - s * 0.1);
        final bone = _bone(f, s);
        out.add(RoundCone(p, p + d * seg[f][s], r, r * 0.9, (u) => [(bone, 1.0)], blend: s == 0 ? 0.006 : 0.003));
      }
    }
    _mine.addAll(out);
    return out;
  }

  /// グラブ：手のひら（土手）・4本の指袋（少し開いて、先はポケットの側へ丸まる）・親指・網（ウェブ）・手首のバンド
  ///  大きさは手の長さの約1.5倍。手の向き（dir＝指先、across＝親指の側、palmN＝ポケットの向き）に沿って作る
  List<SdfPrim> mittPrims() {
    final wb = [(_handBone, 1.0)];
    final sz = size * 1.12;
    final out = <SdfPrim>[
      // 手のひらの土手（厚い革）
      Ellipsoid(wrist + dir * (sz * 0.42) - palmN * (sz * 0.03), across, dir, palmN, sz * 0.46, sz * 0.42, sz * 0.15, wb, blend: 0.012),
      // 小指側の土手の巻き（ヒール）
      Ellipsoid(wrist + dir * (sz * 0.22) - across * (sz * 0.30), across, dir, palmN, sz * 0.16, sz * 0.30, sz * 0.15, wb, blend: 0.012),
      // 手首のバンド
      Ellipsoid(wrist + dir * (sz * 0.04) - palmN * (sz * 0.05), across, dir, palmN, sz * 0.34, sz * 0.10, sz * 0.12, wb, blend: 0.008),
    ];
    // 4本の指袋：人差し指（親指の側）から小指へ。少し扇に開き、先はポケットの側へ丸まる
    const offs = [0.30, 0.10, -0.10, -0.30], lens = [0.78, 0.84, 0.78, 0.66], fan = [0.10, 0.03, -0.04, -0.12];
    for (var i = 0; i < 4; i++) {
      final d0 = (dir + across * fan[i]).unit;
      final p0 = wrist + dir * (sz * 0.62) + across * (sz * offs[i]);
      final p1 = p0 + d0 * (sz * lens[i] * 0.55);
      final d1 = (d0 + palmN * 0.35).unit;
      final p2 = p1 + d1 * (sz * lens[i] * 0.45);
      final r = sz * (0.115 - 0.008 * i.abs());
      out.add(RoundCone(p0, p1, r, r * 0.95, (u) => wb, blend: 0.006));
      out.add(RoundCone(p1, p2, r * 0.95, r * 0.8, (u) => wb, blend: 0.006));
    }
    // 親指：付け根から斜め前へ、先はポケットの側へ
    final t0 = wrist + dir * (sz * 0.22) + across * (sz * 0.36);
    final td = (dir * 0.75 + across * 0.55).unit;
    final t1 = t0 + td * (sz * 0.42);
    final t2 = t1 + (td + palmN * 0.4).unit * (sz * 0.34);
    out.add(RoundCone(t0, t1, sz * 0.13, sz * 0.12, (u) => wb, blend: 0.01));
    out.add(RoundCone(t1, t2, sz * 0.12, sz * 0.095, (u) => wb, blend: 0.006));
    // 網（ウェブ）：親指と人差し指の間の薄い面
    out.add(Ellipsoid(wrist + dir * (sz * 0.86) + across * (sz * 0.50) + palmN * (sz * 0.06), (across - dir * 0.3).unit, (dir + across * 0.3).unit, palmN, sz * 0.17, sz * 0.30, sz * 0.035, wb, blend: 0.006));
    return out;
  }

  /// ポケット（手のひら側の捕る面。少し暗い革）：土手から指の付け根まで、くぼんだ面
  void pocketShape(_MB pocket) {
    final sz = size * 1.12;
    final c = wrist + dir * (sz * 0.58);
    pocket.ellipsoid(c + palmN * (sz * 0.10), across * (sz * 0.36), dir * (sz * 0.38), palmN * (sz * 0.04), [(_handBone, 1.0)]);
  }
}

/// 顔の部品を、溶かし合わせる形として集める（肌の頭・あご・鼻・耳）
class _SdfCollect {
  final List<SdfPrim> prims = [];
  void ellipsoid(V3 c, V3 ax, V3 ay, V3 az, List<(int, double)> w, {double blend = 0.025}) =>
      prims.add(Ellipsoid(c, ax.unit, ay.unit, az.unit, ax.length, ay.length, az.length, w, blend: blend));
}

/// 輪切り（中心・横軸・前後軸・半径・骨の重み）
class _Ring {
  final V3 c, ax, ay;
  final double rx, ry;
  final List<(int, double)> w;
  const _Ring(this.c, this.ax, this.ay, this.rx, this.ry, this.w);
}

/// 立った姿勢の座標（本塁基準）で形を作り、骨の重みを付けて1つのスキン付きの形にする
class _MB {
  final ToonRig rig;
  final _v = <double>[];
  final _i = <int>[];
  _MB(this.rig);
  int get _n => _v.length ~/ 26;

  void _vert(V3 p, V3 nrm, List<(int, double)> w) {
    final q = sv(p);
    final n = sv(nrm)..normalize();
    final ws = [...w]..sort((a, b) => b.$2.compareTo(a.$2));
    final jj = [0.0, 0.0, 0.0, 0.0], ww = [0.0, 0.0, 0.0, 0.0];
    var sum = 0.0;
    for (var k = 0; k < math.min(4, ws.length); k++) {
      jj[k] = ws[k].$1.toDouble();
      ww[k] = math.max(0.0, ws[k].$2);
      sum += ww[k];
    }
    if (sum <= 0) {
      ww[0] = 1;
      sum = 1;
    }
    _v.addAll([q.x, q.y, q.z, n.x, n.y, n.z, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, jj[0], jj[1], jj[2], jj[3], ww[0] / sum, ww[1] / sum, ww[2] / sum, ww[3] / sum]);
  }

  /// 輪切りをつないだ筒（両端にふた）
  void loft(List<_Ring> rings, {int seg = 18}) {
    final start = _n;
    for (final r in rings) {
      for (var j = 0; j <= seg; j++) {
        final a = j / seg * math.pi * 2;
        final c = math.cos(a), s = math.sin(a);
        _vert(r.c + r.ax * (r.rx * c) + r.ay * (r.ry * s), r.ax * (c / r.rx) + r.ay * (s / r.ry), r.w);
      }
    }
    for (var i = 0; i + 1 < rings.length; i++) {
      for (var j = 0; j < seg; j++) {
        final a = start + i * (seg + 1) + j, b2 = a + seg + 1;
        _i.addAll([a, a + 1, b2, a + 1, b2 + 1, b2]);
      }
    }
    for (final (r, flip) in [(rings.first, true), (rings.last, false)]) {
      final axis = (rings.last.c - rings.first.c).unit * (flip ? -1.0 : 1.0);
      final c0 = _n;
      _vert(r.c, axis, r.w);
      for (var j = 0; j <= seg; j++) {
        final a = j / seg * math.pi * 2;
        _vert(r.c + r.ax * (r.rx * math.cos(a)) + r.ay * (r.ry * math.sin(a)), axis, r.w);
      }
      for (var j = 0; j < seg; j++) {
        _i.addAll(flip ? [c0, c0 + 2 + j, c0 + 1 + j] : [c0, c0 + 1 + j, c0 + 2 + j]);
      }
    }
  }

  /// a → b の手足（u は 0〜1。radius は横・前後の半径、side は前後軸のヒント）
  void limb(V3 a, V3 b, V3 side, (double, double) Function(double u) radius, List<(int, double)> Function(double u) weights, {double from = 0, double to = 1, int rings = 10, int seg = 14}) {
    final d = (b - a);
    final ay = d.unit;
    var fz = side.perpTo(ay).unit;
    if (fz.length < 0.5) fz = V3.ez.perpTo(ay).unit;
    final fx = ay.cross(fz).unit;
    loft([
      for (var i = 0; i <= rings; i++)
        () {
          final u = from + (to - from) * i / rings;
          final r = radius(u.clamp(0.0, 1.0));
          return _Ring(a + d * u, fx, fz, r.$1, r.$2, weights(u.clamp(0.0, 1.0)));
        }(),
    ], seg: seg);
  }

  /// 楕円体（3つの軸は半径をかけたベクトル）。upperOnly：上半分（帽子）、lowerOnly：下半分、cutFront：前の下側を除く（髪）
  void ellipsoid(V3 c, V3 ax, V3 ay, V3 az, List<(int, double)> w, {bool upperOnly = false, bool lowerOnly = false, bool cutFront = false, int rings = 12, int seg = 18}) {
    final start = _n;
    final th0 = lowerOnly ? 0.5 : 0.0, th1 = upperOnly ? 0.5 : 1.0;
    final ux = ax.unit, uy = ay.unit, uz = az.unit;
    final lx = ax.length, ly = ay.length, lz = az.length;
    for (var i = 0; i <= rings; i++) {
      final th = (th0 + (th1 - th0) * i / rings) * math.pi; // 0＝上（az の向き）
      for (var j = 0; j <= seg; j++) {
        final ph = j / seg * math.pi * 2;
        final dx = math.sin(th) * math.cos(ph), dy = math.sin(th) * math.sin(ph), dz = math.cos(th);
        var p = c + ux * (dx * lx) + uy * (dy * ly) + uz * (dz * lz);
        // 前髪：顔の前（y の＋）で額より下へ来ないように押し上げる
        if (cutFront && dy > 0.2 && dz < 0.35) p = p + uz * ((0.35 - dz) * lz * 0.9) - uy * (dy * ly * 0.1);
        _vert(p, ux * (dx / lx) + uy * (dy / ly) + uz * (dz / lz), w);
      }
    }
    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < seg; j++) {
        final a = start + i * (seg + 1) + j, b2 = a + seg + 1;
        _i.addAll([a, b2, a + 1, a + 1, b2, b2 + 1]);
      }
    }
  }

  /// 継ぎ目のない表面（sdf_mesh.dart）を足す
  void surface(SdfSurface sf) {
    final base = _n;
    for (var i = 0; i < sf.pos.length; i++) {
      _vert(sf.pos[i], sf.nrm[i], sf.w[i]);
    }
    for (final t in sf.tri) {
      _i.add(base + t);
    }
  }

  Node node(Material m) {
    final g = SkinnedGeometry();
    final v = Float32List.fromList(_v);
    assert(_n < 65536, '1つの形の頂点が多すぎます');
    g.uploadVertexData(v.buffer.asByteData(), _n, Uint16List.fromList(_i).buffer.asByteData());
    final s = Skin();
    s.joints.addAll(rig.joints);
    for (final b in rig._bindG) {
      s.inverseBindMatrices.add(vm.Matrix4.inverted(b));
    }
    m.doubleSided = true;
    return Node(mesh: Mesh(g, m))..skin = s;
  }
}

