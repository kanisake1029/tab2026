import 'dart:math' as m;
import 'fielding_times.dart';

/// マスター仕様書（第0章・第6章）の数値。on のとき、試合の計算はこの数値を使う（off なら以前の実測合わせの値）
///  能力（0〜100）→ 物理の変換式と、球場・用具・守備位置の定数
class Spec {
  static bool on = true;

  // ── 係数（式の形は仕様書。大きさは NPB に合わせ直した値。仕様書の原値はコメント）──
  static double batA = 103.8, batB = 0.12; // 仕様書 100 + 0.38×パワー km/h。本塁打王 約50本に合わせ、パワー60 の速さはそのままで傾きを 0.21 → 0.12（2026-11-11）
  static double attA = 2, attK = 1.8; // 仕様書 2° + (弾道−1)×5°。高い弾道が本塁打に偏りすぎるので 3 → 1.8（2026-11-11）
  static double eyA = 0.0055, eyK = 0.002; // 仕様書 2mm + (弾道−1)×3mm
  static double sigEyBase = 0.0355, sigExBase = 0.045; // 仕様書 22mm・45mm
  static double ctrlBase = 0.65; // 仕様書 1.8°
  static double thrBase = 2.4; // 仕様書 3.5°
  static double ofDepth = 1.0; // 外野の定位置の深さの倍率（仕様書 1.0）
  static double umpEdge = 0.80; // 審判のゾーンの端（仕様書のゾーンの何割の所から確率で判定するか）
  static double stealBias = -0.20; // 盗塁の時間の勝負の調整（成功率 約70%）

  /// 分野ごとの切り替え（on と両方が true のときだけ仕様書の数値）
  static bool batting = true, pitching = true, zone = true, fielding = true, throwing = true, running = true, field = true;
  static bool get bat => on && batting;
  static bool get pit => on && pitching;
  static bool get zon => on && zone;
  static bool get fld => on && fielding;
  static bool get thr => on && throwing;
  static bool get run => on && running;
  static bool get fie => on && field;

  // ── 第5章 5.1 守備の初期配置（定位置）──
  static const positions = <String, List<double>>{
    'P': [0.0, 18.0],
    'C': [0.0, -1.2],
    '1B': [18.5, 22.5],
    '2B': [11.0, 38.0],
    '3B': [-18.0, 22.0],
    'SS': [-11.0, 38.0],
    'LF': [-38.0, 72.0],
    'CF': [0.0, 88.0],
    'RF': [38.0, 72.0],
  };
  static const firstBaseHolding = [19.0, 19.5]; // 一塁走者がいるとき（ベースに付く）

  // ── 第2章 2.1 地面（反発・1回のバウンドでの水平の減速）──
  static const artificial = (0.60, 0.15), natural = (0.40, 0.28), dirt = (0.52, 0.20);

  // ── 第6章 6.1 打者・野手 ──
  /// 最高走速度（m/s）
  static double sprint(int run) => FieldTimes.sprintMs.at(run); // 6.8 + 0.028×走力

  /// 最大送球初速（km/h）
  static double throwMaxKmh(int arm) => FieldTimes.throwKmh.at(arm); // 110 + 0.48×肩

  /// 握り替え時間（秒。標準のステップ送球）
  static double transfer(int acc) => FieldTimes.transferSec.at(acc); // 0.85 − 0.003×送球の正確さ

  /// 送球の角度の誤差（度、標準偏差）
  static double throwAngleSigma(int acc) => thrBase * (1 - 0.0085 * acc);

  /// ファンブルの確率（捕球。BaseError は仕様書に値がないので 0.10 とする）
  static double baseError = 0.10;
  static double fumble(int fld) => baseError * m.pow((1 - 0.009 * fld).clamp(0.0, 1.0), 2);

  /// ファンブルしたときの拾い直し（秒）
  static const refieldTime = 1.2;

  /// 1歩目の反応（秒）
  static double reaction(int pos) => FieldTimes.reaction.at(pos); // 0.18 + 0.25×(1 − 守備/100)

  /// 最大スイング速度（m/s）
  static double batSpeed(int pow) => (batA + batB * pow) / 3.6;

  /// 基本アタックアングル（度）
  static double attack(int traj) => attA + (traj - 1) * attK;

  /// 目標の上下オフセット（m。仕様書の負＝芯がボールの下。このエンジンでは＋がバットの下）
  static double eyTarget(int traj) => eyA + (traj - 1) * eyK;

  /// 芯ずれの標準偏差（m）：上下・長さ方向
  static double sigEy(int meet) => sigEyBase * (1 - 0.0075 * meet);
  static double sigEx(int meet) => sigExBase * (1 - 0.0075 * meet);

  // ── 第6章 6.2 投手 ──
  /// 直球の有効なバックスピン（rpm）
  static double fastballRpm(int stuff) => 1900 + 8.0 * stuff;

  /// 重さ：バットとの反発係数の減り
  static double heavyCor(int heavy) => 1 - 0.0012 * heavy;

  /// 制球：放出角のガウス誤差（度）
  ///  制球60 で以前と同じ（0.32°）。ctrlK だけ上がると e 分の1（制球90 ≈ 0.55倍、40 ≈ 1.5倍）
  static double ctrlK = 50;
  static double controlSigma(int ctrl) => ctrlBase * 0.49 * m.exp(-(ctrl - 60) / ctrlK);
  /// 失投（真ん中に甘く入り、変化球は曲がりきらない）の割合：制球60 で mistakeBase、mistakeK 上がるごとに e 分の1
  static double mistakeBase = 0.05, mistakeK = 22;
  static double mistakeRate(int ctrl) => (mistakeBase * m.exp(-(ctrl - 60) / mistakeK)).clamp(0.004, 0.25);

  /// クイック：動き始めから放すまで（秒）
  static double quickMotion(int quick) => 1.05 - 0.0038 * quick;

  // ── 第0章 0.2 ストライクゾーン ──
  static const zoneHalfWidth = 0.2525; // ボールの中心で（ボールがかすめればストライク）
  static double zoneLow(double heightM) => 0.27 * heightM;
  static double zoneHigh(double heightM) => 0.56 * heightM;
  static const ballR = 0.0365;
}
