/// 投球フォーム（投手。二刀流も）
///  腕の角度の分類（オーバー〜アンダー）は、選手の腕の角度（spinAxis：0＝真上 90＝真横 180＝真下）から決まる
///  局面：構え → ①足上げ（片足立ち）→ ②並進（踏み出し足の着地＝FFS まで）→ ③レイトコッキング（肩の最大外旋＝MER まで）→ ④加速（リリース＝BR まで）
class PitchingForm {
  // ───────── 構え ─────────
  /// 投げ方：ワインドアップ／ノーワインドアップ／セットポジション／トルネード（走者がいるときはどれもセット＝クイック）
  String windup;

  /// プレート上の軸足の位置（cm。0＝中央、＋＝三塁側、−＝一塁側。右投手の基準。左投手は鏡に映した側）
  int rubberPos;

  /// ボールとグラブを構える高さ：0＝顔の前 1＝胸の前 2＝ベルト付近
  int handHold;

  // ───────── ①足上げ ─────────
  /// 足を上げる高さ（0〜100。0＝すり足（股関節30°）、50＝太ももが水平（90°）、100＝胸まで（120°））
  int legLiftHeight;

  /// 足を上げ始めてから一番高くなるまでの時間（ミリ秒）
  int legLiftMs;

  /// ための長さ：一番高い所で止める時間（ミリ秒）
  int holdMs;

  /// 骨盤を背中側へひねる量（カウンターローテーション。度、0〜30）
  int counterRot;

  // ───────── ②並進 ─────────
  /// テイクバックの大きさ（0＝ショートアーム（肘から最短で上げる）100＝ロングアーム（太ももの横まで下ろして円を描く））
  int takeback;

  /// 軸足の沈み方（膝の曲がり 度：20〜30＝トール＆フォール（高い位置から倒れ込む）、45〜60＝ドロップ＆ドライブ（深く沈んで蹴る））
  int kneeDrop;

  /// 踏み出し幅（身長に対する％。75〜95）
  int strideRatio;

  /// 踏み出す左右の向き（cm。＋＝インステップ（三塁側へ。右投手基準）、−＝アウトステップ（一塁側へ開く））
  int stepOffset;

  // ───────── ③レイトコッキング ─────────
  /// 腰と肩の捻転差（度。40〜60 が目安）
  int hipShoulderSep;

  /// 肩の最大外旋（MER。地面に対する前腕の倒れ 度：160〜185）
  int merDeg;

  // ───────── ④加速・リリース ─────────
  /// 体幹の前傾（リリースでの体幹の屈曲 度：30〜45）
  int trunkFlex;

  /// リリースの前への伸び（0〜100。プレートから約180〜210cm）
  int extension;

  /// 投球のテンポ（0＝ゆったり 100＝せっかち）
  int tempo;

  PitchingForm({
    this.windup = 'ノーワインドアップ',
    this.rubberPos = 0,
    this.handHold = 1,
    this.legLiftHeight = 55,
    this.legLiftMs = 500,
    this.holdMs = 150,
    this.counterRot = 15,
    this.takeback = 50,
    this.kneeDrop = 35,
    this.strideRatio = 85,
    this.stepOffset = 0,
    this.hipShoulderSep = 45,
    this.merDeg = 172,
    this.trunkFlex = 36,
    this.extension = 50,
    this.tempo = 50,
  });

  static const windups = ['ワインドアップ', 'ノーワインドアップ', 'セットポジション', 'トルネード'];
  static const armSlots = ['オーバー', 'スリークォーター', 'サイド', 'アンダー'];
  static const handHolds = ['顔の前', '胸の前', 'ベルト付近'];

  /// 腕の角度（spinAxis）→ 分類
  static String armSlotOf(int spinAxis) {
    final a = spinAxis % 360;
    final v = a > 180 ? 360 - a : a; // 左右どちらに倒しても同じ分類
    if (v <= 30) return 'オーバー';
    if (v <= 60) return 'スリークォーター';
    if (v <= 105) return 'サイド';
    return 'アンダー';
  }

  /// 分類 → その分類の代表の腕の角度（分類を選び直したとき）
  static int spinAxisOf(String slot) => switch (slot) { 'オーバー' => 20, 'スリークォーター' => 45, 'サイド' => 80, _ => 135 };

  /// 腕の角度 → リリースでの体幹の横の傾き（度。＋＝グラブ側へ傾く。アンダーは投球腕側へ折れる）
  ///  オーバー 30°以上・スリークォーター 15〜25°・サイド 0°前後・アンダー −40〜−60°
  static double lateralTiltOf(int spinAxis) {
    final a = spinAxis.toDouble();
    if (a <= 30) return 40 - a / 3; // 0°→40 30°→30
    if (a <= 60) return 30 - (a - 30) * 0.5; // 30→30 60→15
    if (a <= 105) return 15 - (a - 60) * 0.4; // 60→15 105→-3
    return -3 - (a - 105) * 1.1; // 135→-36 150→-52
  }

  /// 足上げの型（表示用）
  String get legKickType => legLiftHeight >= 70 ? 'ハイキック' : (legLiftHeight <= 20 ? 'すり足' : '標準');
  String get takebackType => takeback >= 60 ? 'ロングアーム' : (takeback <= 35 ? 'ショートアーム' : '中間');
  String get driveType => kneeDrop >= 45 ? 'ドロップ＆ドライブ' : (kneeDrop <= 30 ? 'トール＆フォール' : '中間');
  String get stepType => stepOffset >= 5 ? 'インステップ' : (stepOffset <= -5 ? 'アウトステップ' : 'ストレート');

  PitchingForm copy() => PitchingForm.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'windup': windup, 'rubber': rubberPos, 'hold': handHold, 'lift': legLiftHeight, 'liftMs': legLiftMs, 'holdMs': holdMs,
        'counter': counterRot, 'takeback': takeback, 'knee': kneeDrop, 'stride': strideRatio, 'step': stepOffset,
        'sep': hipShoulderSep, 'mer': merDeg, 'flex': trunkFlex, 'ext': extension, 'tempo': tempo,
      };

  factory PitchingForm.fromJson(Map<String, dynamic> j) => PitchingForm(
        windup: j['windup'] ?? 'ノーワインドアップ',
        rubberPos: j['rubber'] ?? 0,
        handHold: j['hold'] ?? 1,
        legLiftHeight: j['lift'] ?? 55,
        legLiftMs: j['liftMs'] ?? 500,
        holdMs: j['holdMs'] ?? 150,
        counterRot: j['counter'] ?? 15,
        takeback: j['takeback'] ?? 50,
        kneeDrop: j['knee'] ?? 35,
        strideRatio: j['stride'] ?? 85,
        stepOffset: j['step'] ?? 0,
        hipShoulderSep: j['sep'] ?? 45,
        merDeg: j['mer'] ?? 172,
        trunkFlex: j['flex'] ?? 36,
        extension: j['ext'] ?? 50,
        tempo: j['tempo'] ?? 50,
      );
}
