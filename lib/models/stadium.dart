import 'dart:math' as math;
import 'dart:math' as m;

/// 球場の寸法（本塁を原点、x の＋＝一塁・右翼側、y の＋＝中堅方向。m）
///  いまは全球団が同じ「標準球場」。今後、12球団別の球場や、オリジナルの球場を作れるようにする
///  角度は中堅を 0°、右翼線を ＋45°、左翼線を −45°（打球の向き atan2(x, y) と同じ）
class Stadium {
  String id, name;

  /// フェンス：角度ごとの本塁からの距離と高さ（ポールの外のファウルゾーンまで続く）。間は滑らかにつなぐ
  List<FencePoint> fence;

  // ───── ファウルエリア（公認野球規則 2.01：本塁からバックストップまで、塁線からフェンス・スタンドまで 60フィート＝18.288m 以上が望ましい） ─────
  double backstop; // 本塁からバックネットまで
  double foulFirst, foulThird; // 一塁線・三塁線から内野スタンド（フェンス）までの距離（一塁・三塁の横あたり）
  double foulCorner; // ポール際での、ファウルラインからフェンスまでの距離

  // ───── ベンチ・ブルペン ─────
  Dugout homeDugout, awayDugout;
  String bullpen; // 'ファウルゾーン'・'外野奥'・'外野横'

  // ───── グラウンド ─────
  String turf; // '天然芝'・'人工芝'
  String roof; // '屋外'・'ドーム'・'開閉式'
  int capacity;
  double altitude; // 標高（m）：高いほど空気が薄く、打球が飛び、変化球が曲がりにくい
  double windFactor; // 風の通りやすさ（1＝ふつう、0＝風が入らない）

  // ───── スタンド・ビジョン・看板 ─────
  List<StandTier> stands;
  Vision vision;
  List<AdBoard> ads;

  // ───── 建物（3D の見た目だけ。試合の計算には使わない）─────
  List<Vision> moreVisions; // メイン以外の大型ビジョン（横長の2面など）
  bool showMainVision; // メインのビジョン（中堅の後ろ）を置くか
  double roofRidge; // 開閉式の屋根の棟の高さ（0＝屋根なし）。開いた状態で、内野側の大きな三角屋根として描く
  double glassWall; // 外野側のガラスの壁の高さ（0＝なし）
  List<Building> buildings; // 外野の奥の建物（ホテル・醸造所など）
  bool outfieldBullpens; // ブルペンを外野フェンスの外（見える所）に置く
  // ───── 見た目の違い（3D）─────
  String infield; // 'alldirt'（内野は全部土・日本式）・'grass'（内野は芝で、塁間の走路と周りだけ土）・'cutout'（人工芝で、塁とマウンドと本塁の周りだけ土）
  int dirtColor, turfColor, fenceColor, seatColor;
  double domeHeight; // ドームの天井の高さ（0＝屋根なし）
  int domeColor;
  bool domeOpenSides; // ドームの横が開いている（屋根だけ）
  String domeStyle; // 'membrane'（白い膜・四角い格子）・'lattice'（濃い鉄骨の格子）・'ring'（内側の円盤＋外側の鉄骨の輪）
  bool dirtFoul; // ファウルゾーンも土（甲子園）
  double foulTrack; // ファウルゾーンの壁ぎわの土の帯の幅（0＝なし）
  int? cutoutColor; // 人工芝の球場の、塁・マウンド・本塁の周りの土の色（東京のオレンジなど）
  String mow; // 天然芝の刈り目：'stripe'（同心の縞）・'checker'（格子）
  List<LightTower> lights; // 照明塔
  bool adRing; // 外野席の上に広告の看板が並ぶ
  List<String> scenery; // 球場の外の景色：'ferris'・'marineTower'・'skyline'・'mountains'・'trees'・'sea'・'town'
  bool straightFence; // 外野フェンスが直線だけでできている（点と点を直線で結ぶ）
  List<(double, double, double)> fenceOverrides; // フェンスの高さの部分的な違い（角度の範囲・高さ）
  // ───── 外野フェンスの作り（写真・公表値から）─────
  double fenceNet; // ラバーの上の金網の高さ（m。0＝金網なし）
  int fenceTop; // ラバーの上端の線の色（本塁打の目印。0＝なし）
  String fenceAds; // 広告：'color'（色の看板）・'white'（白い字で直接書く）・'none'
  double oldFence; // テラス席の後ろの元のフェンスの高さ（0＝なし）
  int oldFenceColor, oldFenceUpper; // 元のフェンスの色（下・上半分）
  double oldFenceBack; // テラスの奥行き（前のフェンスから元のフェンスまで）
  int wallColor; // 外野席の前の壁の色
  List<Ribbon> ribbons; // リボンビジョン（帯状の光る広告）
  int? warningColor; // フェンス際（ウォーニングゾーン）の色（null＝土）
  // ───── 打球の飛びやすさ（寸法以外）─────
  double carry; // 打球の空気抵抗の倍率（1 未満ほど伸びる）：空調の流れ（東京の上昇気流など）・湿気・海風など、寸法では表せない飛びやすさ
  double windFrom; // よく吹く風が来る向き（中堅 0°、右翼 +45°。NaN＝決まった向きなし）
  double windSteady; // その向きの風が吹く試合の割合

  Stadium({
    required this.id,
    required this.name,
    required this.fence,
    this.backstop = 18.3,
    this.foulFirst = 18.3,
    this.foulThird = 18.3,
    this.foulCorner = 3.0,
    Dugout? homeDugout,
    Dugout? awayDugout,
    this.bullpen = '外野奥',
    this.turf = '人工芝',
    this.roof = '屋外',
    this.capacity = 32000,
    this.altitude = 10,
    this.windFactor = 1.0,
    List<StandTier>? stands,
    Vision? vision,
    List<AdBoard>? ads,
    List<Vision>? moreVisions,
    this.showMainVision = true,
    this.roofRidge = 0,
    this.glassWall = 0,
    List<Building>? buildings,
    this.outfieldBullpens = false,
    this.infield = 'alldirt',
    this.dirtColor = 0xFFC9935F,
    this.turfColor = 0xFF3F8A3A,
    this.fenceColor = 0xFF1F4F35,
    this.seatColor = 0xFF1E3A8A,
    this.domeHeight = 0,
    this.domeColor = 0xFFE8EAEC,
    this.domeOpenSides = false,
    this.domeStyle = 'membrane',
    this.dirtFoul = false,
    this.foulTrack = 0,
    this.cutoutColor,
    this.mow = 'stripe',
    List<LightTower>? lights,
    this.adRing = false,
    List<String>? scenery,
    this.straightFence = false,
    List<(double, double, double)>? fenceOverrides,
    this.carry = 1.0,
    this.windFrom = double.nan,
    this.windSteady = 0,
    this.fenceNet = 0,
    this.fenceTop = 0xFFFACC15,
    this.fenceAds = 'color',
    this.oldFence = 0,
    this.oldFenceColor = 0xFF1F2937,
    this.oldFenceUpper = 0,
    this.oldFenceBack = 0,
    this.wallColor = 0xFF334155,
    List<Ribbon>? ribbons,
    this.warningColor,
  })  : ribbons = ribbons ?? const [],
        lights = lights ?? LightTower.standard(),
        scenery = scenery ?? const [],
        fenceOverrides = fenceOverrides ?? const [],
        moreVisions = moreVisions ?? [],
        buildings = buildings ?? [],
        homeDugout = homeDugout ?? Dugout(side: 3),
        awayDugout = awayDugout ?? Dugout(side: 1),
        stands = stands ?? StandTier.standard(),
        vision = vision ?? Vision(),
        ads = ads ?? AdBoard.standard();

  /// 標準球場（公認野球規則の目安：両翼 320フィート＝97.5m 以上・中堅 400フィート＝121.9m 以上）：両翼100m・左中間/右中間 約115.6m・中堅122m・フェンス3m（これまでの試合の計算と同じ）
  static final Stadium standard = Stadium(
    id: 'std',
    name: '標準球場',
    fence: [for (var i = 0; i <= 10; i++) FencePoint(-56.25 + i * 11.25, 100 + 22 * m.cos(2 * (-56.25 + i * 11.25) * m.pi / 180), 3.0)],
  );

  /// 北の開閉式ボールパーク（北海道の新しい球場を参考にした形）：左翼97m・中堅121m・右翼99m、左中間・右中間のふくらみは小さめ、
  ///  バックネットまで 15m（設計値）・ファウルゾーンが狭い、天然芝・開閉式の屋根（幅約166m）、外野側に高さ 70m のガラスの壁、
  ///  中堅の左右に横長の大型ビジョン 2面（86m×16m）でメインのスコアボードはない、3層のスタンド（約35,000席）、
  ///  左翼の奥に5階建ての建物（ホテル・サウナ）、中堅の奥に醸造所、ブルペンは外野フェンスのすぐ外
  static final Stadium northPark = Stadium(
    id: 'north',
    name: '北の開閉式ボールパーク',
    fence: [
      FencePoint(-56.25, 88, 2.8),
      FencePoint(-45, 97, 2.8),
      FencePoint(-33.75, 106, 2.8),
      FencePoint(-22.5, 113, 2.8),
      FencePoint(-11.25, 119, 2.8),
      FencePoint(0, 121, 2.8),
      FencePoint(11.25, 119.5, 2.8),
      FencePoint(22.5, 114, 2.8),
      FencePoint(33.75, 107.5, 2.8),
      FencePoint(45, 99, 2.8),
      FencePoint(56.25, 90, 2.8),
    ],
    backstop: 15.0,
    foulFirst: 13.0,
    foulThird: 13.0,
    foulCorner: 2.0,
    bullpen: '外野奥',
    turf: '天然芝',
    roof: '開閉式',
    capacity: 35000,
    altitude: 70,
    stands: [
      // 写真・中継で確かめた形：座席は濃い灰色、内野は3層（2層目・3層目は後ろへ下げて高く、前に光る帯）
      // 1層目：グラウンドのすぐ近く（すり鉢状）
      StandTier(area: 'バックネット裏', fromAngle: 150, toAngle: 210, baseHeight: 1.6, rows: 22, seatColor: 0xFF2C3136),
      StandTier(area: '内野', fromAngle: -150, toAngle: -45, baseHeight: 1.0, rows: 24, seatColor: 0xFF2C3136),
      StandTier(area: '内野', fromAngle: 45, toAngle: 150, baseHeight: 1.0, rows: 24, seatColor: 0xFF2C3136),
      // 2層目・3層目
      StandTier(area: 'バックネット裏', fromAngle: 150, toAngle: 210, baseHeight: 13, rows: 14, rowRise: 0.55, seatColor: 0xFF2F3439, setback: 21),
      StandTier(area: '内野', fromAngle: -150, toAngle: -50, baseHeight: 13, rows: 14, rowRise: 0.55, seatColor: 0xFF2F3439, setback: 23),
      StandTier(area: '内野', fromAngle: 50, toAngle: 150, baseHeight: 13, rows: 14, rowRise: 0.55, seatColor: 0xFF2F3439, setback: 23),
      StandTier(area: '内野', fromAngle: -140, toAngle: -58, baseHeight: 23, rows: 12, rowRise: 0.6, seatColor: 0xFF32373C, setback: 36),
      StandTier(area: '内野', fromAngle: 58, toAngle: 140, baseHeight: 23, rows: 12, rowRise: 0.6, seatColor: 0xFF32373C, setback: 36),
      // 外野：ポール際はブルペンをくり抜いて、その後ろに一段高い席
      StandTier(area: '外野', fromAngle: -36, toAngle: -12, baseHeight: 3.0, rows: 18, seatColor: 0xFF2C3136),
      StandTier(area: '外野', fromAngle: 12, toAngle: 36, baseHeight: 3.0, rows: 18, seatColor: 0xFF2C3136),
      StandTier(area: '外野', fromAngle: -45, toAngle: -36, baseHeight: 4.5, rows: 12, seatColor: 0xFF2C3136, setback: 8),
      StandTier(area: '外野', fromAngle: 36, toAngle: 45, baseHeight: 4.5, rows: 12, seatColor: 0xFF2C3136, setback: 8),
    ],
    vision: Vision(angle: 0, behind: 30, bottom: 30, width: 30, height: 12, ribbon: false),
    showMainVision: false,
    // 両翼のスタンドの上に横長の大型ビジョン（86m×16m）を 2面
    moreVisions: [
      Vision(angle: -47, behind: 9, bottom: 16, width: 86, height: 16, ribbon: false),
      Vision(angle: 47, behind: 9, bottom: 16, width: 86, height: 16, ribbon: false),
    ],
    straightFence: true, // 外野フェンスは直線だけでできている
    carry: 0.975,
    fenceOverrides: const [(-45.0, -40.5, 6.9)], // 左翼ポールからビジター側ブルペンまでは 6.9m の黒い壁（コンコースから切れ落ちている）
    lights: const [],
    roofRidge: 72, // 閉じた三角屋根（二塁の上で約70m）
    glassWall: 70, // 外野の裏のガラスの壁（屋根の妻面）
    buildings: [
      // 左翼の外野席の奥：木目とガラスの5階建て（ホテル・温泉）
      Building(angle: -30, distance: 124, width: 30, depth: 12, height: 23, color: 0xFFB4875A, label: 'タワー（ホテル・温泉）'),
    ],
    outfieldBullpens: true,
  );

  /// ファウルゾーンと客席の境のネットの高さ（地面から）：本塁の後ろは高く、内野の横は 4.5m、ポールへ向かって 3.5m
  ///  p：本塁基準の地面の点（ネットの所）
  double netTop(double x, double y) {
    if (y < 2 && x.abs() < 14) return backstopNet;
    final along = (x.abs() + y) / math.sqrt2; // 線に沿った距離
    return along < 40 ? 4.5 : 4.5 - math.min(1.0, (along - 40) / 50);
  }

  double backstopNet = 9.0;

  /// ファウルの打球がネット（客席の前）の所まで来たか（本塁基準の地面の点）
  bool pastFoulWall(double x, double y) {
    const s2 = 0.7071067811865476;
    if (y < 0 && x.abs() < 12) return math.sqrt(x * x + y * y) > backstop;
    if (x >= 0) return x * s2 - y * s2 > foulFirst && x * s2 + y * s2 > 0;
    return -x * s2 - y * s2 > foulThird && -x * s2 + y * s2 > 0;
  }

  /// 外野の形から球場を作る：両翼・左右中間（±22.5°）・中堅の距離と、左・中・右のフェンスの高さ
  static Stadium park({
    required String id,
    required String name,
    required double lf, required double lcf, required double cf, required double rcf, required double rf,
    required double hl, required double hc, required double hr, double? hlg, double? hrg, int? warning,
    double backstop = 18.3, double foul = 18.0, String turf = '人工芝', String roof = '屋外', int capacity = 32000, double altitude = 10,
    double wind = 1.0, String infield = 'alldirt', int dirt = 0xFFC9935F, int grass = 0xFF3F8A3A, int fenceColor = 0xFF1F4F35,
    double domeHeight = 0, int domeColor = 0xFFE8EAEC, bool openSides = false, String domeStyle = 'membrane', int homeSide = 3, double bulge = 1.5,
    required List<StandTier> stands, Vision? vision, List<Vision>? moreVisions, bool showMainVision = true,
    bool dirtFoul = false, double foulTrack = 0, int? cutoutColor, String mow = 'stripe', List<LightTower>? lights, bool adRing = false,
    List<String> scenery = const [], bool noAds = false, double carry = 1.0, double windFrom = double.nan, double windSteady = 0,
    double fenceNet = 0, int fenceTop = 0xFFFACC15, String fenceAds = 'color', double oldFence = 0, int oldFenceColor = 0xFF1F2937, int oldFenceUpper = 0,
    double oldFenceBack = 0, int wallColor = 0xFF334155, List<Ribbon> ribbons = const [], List<(double, double, double)> fenceOverrides = const [],
  }) {
    // 11.25° ごとの点：線上・左右中間・中堅はそのまま、間は平均に少しふくらみ
    final d = <double, double>{-45: lf, -22.5: lcf, 0: cf, 22.5: rcf, 45: rf};
    d[-33.75] = (lf + lcf) / 2 + bulge;
    d[-11.25] = (lcf + cf) / 2 + bulge * 0.6;
    d[11.25] = (rcf + cf) / 2 + bulge * 0.6;
    d[33.75] = (rf + rcf) / 2 + bulge;
    d[-56.25] = lf - 9;
    d[56.25] = rf - 9;
    // 高さ：両翼・左右中間（±22.5°）・中堅をつなぐ（左右中間の値がなければ間をとる）
    final hL2 = hlg ?? (hl + hc) / 2, hR2 = hrg ?? (hr + hc) / 2;
    double h(double a) => a <= -22.5 ? hl + (hL2 - hl) * (a + 45) / 22.5 : (a <= 0 ? hL2 + (hc - hL2) * (a + 22.5) / 22.5 : (a <= 22.5 ? hc + (hR2 - hc) * a / 22.5 : hR2 + (hr - hR2) * (a - 22.5) / 22.5));
    final keys = d.keys.toList()..sort();
    return Stadium(
      id: id,
      name: name,
      fence: [for (final a in keys) FencePoint(a, d[a]!, h(a.clamp(-45, 45)))],
      backstop: backstop,
      foulFirst: foul,
      foulThird: foul,
      turf: turf,
      roof: roof,
      capacity: capacity,
      altitude: altitude,
      windFactor: wind,
      homeDugout: Dugout(side: homeSide),
      awayDugout: Dugout(side: homeSide == 1 ? 3 : 1),
      infield: infield,
      dirtColor: dirt,
      turfColor: grass,
      fenceColor: fenceColor,
      domeHeight: domeHeight,
      domeColor: domeColor,
      domeOpenSides: openSides,
      domeStyle: domeStyle,
      stands: stands,
      vision: vision,
      moreVisions: moreVisions,
      showMainVision: showMainVision,
      dirtFoul: dirtFoul,
      foulTrack: foulTrack,
      cutoutColor: cutoutColor,
      mow: mow,
      lights: lights ?? const [],
      adRing: adRing,
      scenery: scenery,
      ads: noAds ? const [] : null,
      carry: carry,
      windFrom: windFrom,
      windSteady: windSteady,
      fenceNet: fenceNet,
      fenceTop: fenceTop,
      fenceAds: fenceAds,
      oldFence: oldFence,
      oldFenceColor: oldFenceColor,
      oldFenceUpper: oldFenceUpper,
      oldFenceBack: oldFenceBack,
      wallColor: wallColor,
      ribbons: ribbons,
      fenceOverrides: fenceOverrides,
      warningColor: warning,
    );
  }

  /// スタンドの組み合わせ（写真で確かめた段の数と色）
  ///  lower：内野と本塁の後ろの1層目の段数、upper：2層目（0＝なし）、of：外野の段数、ofUpper：外野の2層目、terrace：外野フェンスのすぐ後ろの低い席
  static List<StandTier> bowl({
    required int seat, int? upperSeat, int? ofSeat, int? ofUpperSeat,
    int lower = 30, double lowerRise = 0.42, int upper = 0, double upperBase = 13, double upperSetback = 15, double upperRise = 0.55,
    int of = 20, double ofBase = 3.0, int ofUpper = 0, double ofUpperBase = 12, double ofUpperSetback = 12, double ofUpperRise = 0.55,
    double ofFrom = 8, int terrace = 0, double ofSetback = 0, int? ofLeft,
    int roof = 0, double roofCover = 0.55, double roofRise = 5, bool roofOnUpper = true, bool roofOnOutfield = false, double upperFrom = 45,
  }) {
    final up = upperSeat ?? seat, os = ofSeat ?? seat, ous = ofUpperSeat ?? up;
    final lowRoof = upper == 0 || !roofOnUpper ? roof : 0;
    final t = <StandTier>[
      StandTier(area: 'バックネット裏', fromAngle: 150, toAngle: 210, baseHeight: 1.2, rows: lower, rowRise: lowerRise, seatColor: seat, roofColor: lowRoof, roofCover: roofCover, roofRise: roofRise),
      StandTier(area: '内野', fromAngle: -150, toAngle: -45, baseHeight: 1.2, rows: lower, rowRise: lowerRise, seatColor: seat, roofColor: lowRoof, roofCover: roofCover, roofRise: roofRise),
      StandTier(area: '内野', fromAngle: 45, toAngle: 150, baseHeight: 1.2, rows: lower, rowRise: lowerRise, seatColor: seat, roofColor: lowRoof, roofCover: roofCover, roofRise: roofRise),
      if (terrace > 0) ...[
        StandTier(area: '外野', fromAngle: -42, toAngle: -ofFrom, baseHeight: 0.9, rows: terrace, rowRise: 0.3, seatColor: os),
        StandTier(area: '外野', fromAngle: ofFrom, toAngle: 42, baseHeight: 0.9, rows: terrace, rowRise: 0.3, seatColor: os),
      ],
      StandTier(area: '外野', fromAngle: -45, toAngle: -ofFrom, baseHeight: ofBase, rows: ofLeft ?? of, seatColor: os, setback: ofSetback, roofColor: roofOnOutfield && ofUpper == 0 ? roof : 0, roofCover: roofCover, roofRise: roofRise),
      StandTier(area: '外野', fromAngle: ofFrom, toAngle: 45, baseHeight: ofBase, rows: of, seatColor: os, setback: ofSetback, roofColor: roofOnOutfield && ofUpper == 0 ? roof : 0, roofCover: roofCover, roofRise: roofRise),
      if (upper > 0) ...[
        StandTier(area: 'バックネット裏', fromAngle: 150, toAngle: 210, baseHeight: upperBase, rows: upper, rowRise: upperRise, seatColor: up, setback: upperSetback, roofColor: roofOnUpper ? roof : 0, roofCover: roofCover, roofRise: roofRise),
        StandTier(area: '内野', fromAngle: -150, toAngle: -upperFrom, baseHeight: upperBase, rows: upper, rowRise: upperRise, seatColor: up, setback: upperSetback, roofColor: roofOnUpper ? roof : 0, roofCover: roofCover, roofRise: roofRise),
        StandTier(area: '内野', fromAngle: upperFrom, toAngle: 150, baseHeight: upperBase, rows: upper, rowRise: upperRise, seatColor: up, setback: upperSetback, roofColor: roofOnUpper ? roof : 0, roofCover: roofCover, roofRise: roofRise),
      ],
      if (ofUpper > 0) ...[
        StandTier(area: '外野', fromAngle: -45, toAngle: -ofFrom, baseHeight: ofUpperBase, rows: ofUpper, rowRise: ofUpperRise, seatColor: ous, setback: ofUpperSetback, roofColor: roofOnOutfield ? roof : 0, roofCover: roofCover, roofRise: roofRise),
        StandTier(area: '外野', fromAngle: ofFrom, toAngle: 45, baseHeight: ofUpperBase, rows: ofUpper, rowRise: ofUpperRise, seatColor: ous, setback: ofUpperSetback, roofColor: roofOnOutfield ? roof : 0, roofCover: roofCover, roofRise: roofRise),
      ],
    ];
    return t;
  }

  // ───── 12球団の本拠地（実在の球場の写真・中継・公表値を参考にした架空の球場。名前とロゴ・広告は架空。docs/stadium_research.md）─────
  //  寸法・フェンス・ビジョンの大きさは各球場の公表値（Wikipedia 2026年）より
  /// みずほPayPayドーム福岡を参考：高い鉄骨の屋根（68m）、ホームランテラス（前のフェンス 4.2m＝ラバー2.7m＋金網1.5m、後ろに元のフェンス 5.84m）、
  ///  中堅の上に 10m×53m のメインビジョンと左右のウイングビジョン（5.7m×33m）が外野の上にひと続き、ネット裏に吊り下げ式のビジョン
  static final Stadium fukuoka = park(id: 'fukuoka', carry: 1, name: '博多湾ドーム', lf: 100, lcf: 110, cf: 122, rcf: 110, rf: 100, hl: 4.2, hc: 4.2, hr: 4.2,
      roof: 'ドーム', capacity: 40000, infield: 'cutout', grass: 0xFF3E9C4A, cutoutColor: 0xFFB5532E, fenceColor: 0xFF1C2333, fenceNet: 1.5,
      oldFence: 5.84, oldFenceColor: 0xFF22324A, oldFenceBack: 5.0, wallColor: 0xFF1F2937,
      domeHeight: 68, domeColor: 0xFF4A4F57, domeStyle: 'lattice',
      stands: bowl(seat: 0xFF2E9E4F, lower: 30, upper: 18, upperBase: 13, upperSetback: 16, of: 22, ofBase: 6.2, ofSetback: 5.6, terrace: 5, ofUpper: 12, ofUpperBase: 17, ofUpperSetback: 22),
      showMainVision: false,
      moreVisions: [
        Vision(angle: 0, behind: 34, bottom: 27, width: 53, height: 10, ribbon: false, arc: true, content: 'main'),
        Vision(angle: -15.2, behind: 34, bottom: 30, width: 27, height: 7, ribbon: false, arc: true, content: 'ads'),
        Vision(angle: 15.2, behind: 34, bottom: 30, width: 27, height: 7, ribbon: false, arc: true, content: 'ads'),
        Vision(angle: -29.6, behind: 33, bottom: 31.3, width: 33, height: 5.7, ribbon: false, arc: true, content: 'lineupHome'),
        Vision(angle: 29.6, behind: 33, bottom: 31.3, width: 33, height: 5.7, ribbon: false, arc: true, content: 'lineupAway'),
        Vision(angle: 180, behind: 40, bottom: 24, width: 32, height: 10.8, ribbon: false, content: 'video'),
      ],
      ribbons: const [Ribbon('tier', -150, -45), Ribbon('tier', 45, 150)]);
  /// ZOZOマリンスタジアムを参考：海のそばの屋外球場、フェンス 3.3m の青に白い字の広告、ホームランラグーン（フェンスを 4m 前へ）、
  ///  スタンドを一周する大きなひさし（先に照明）、中堅にメイン（10m×28.8m）、外野席にサブ（5.8m×20m）、2階の前に一周するリボンビジョン
  static final Stadium chiba = park(id: 'chiba', carry: 1, name: '幕張海浜球場', lf: 99.5, lcf: 112.3, cf: 122, rcf: 112.3, rf: 99.5, hl: 3.3, hc: 3.3, hr: 3.3,
      capacity: 30000, wind: 1.8, infield: 'grass', dirt: 0xFFB4553A, grass: 0xFF3B8E40, fenceColor: 0xFF1F3F8F, fenceAds: 'white', fenceTop: 0,
      oldFence: 3.0, oldFenceColor: 0xFF1F3F8F, oldFenceBack: 4.0, foulTrack: 3.5, wallColor: 0xFF1E3A8A,
      stands: bowl(seat: 0xFF2747A8, upperSeat: 0xFF1E3A8A, lower: 26, upper: 16, upperBase: 12, upperSetback: 14, of: 18, ofSetback: 4.6, terrace: 3, ofUpper: 12, ofUpperBase: 10, ofUpperSetback: 16,
          roof: 0xFFD7DCE1, roofCover: 0.9, roofRise: 4, roofOnOutfield: true),
      showMainVision: false,
      moreVisions: [
        Vision(angle: 0, behind: 10, bottom: 12, width: 28.8, height: 10.1, ribbon: false, content: 'main'),
        Vision(angle: -24, behind: 18, bottom: 15, width: 20.2, height: 5.8, ribbon: false, content: 'video'),
      ],
      ribbons: const [Ribbon('tier', -150, -45), Ribbon('tier', 45, 150)],
      lights: const [], scenery: ['sea', 'town']);
  /// 楽天モバイル 最強パーク宮城を参考：フェンス 2m（左中間 1.8m）で両翼へ向かって高くなる、フェンスと外野席の間の席（Eウイング）、
  ///  中堅のスコアボードと右中間の大型ビジョン（16.2m×20.8m）、その間の細いビジョン、左翼席の奥の観覧車、黒土、えんじの座席
  static final Stadium miyagi = park(id: 'miyagi', carry: 1.05, name: '杜の都ボールパーク', lf: 100.1, lcf: 110, cf: 122, rcf: 112, rf: 100.1, hl: 3.0, hlg: 1.8, hc: 2.0, hrg: 2.0, hr: 3.0,
      turf: '天然芝', capacity: 30500, infield: 'grass', dirt: 0xFF3E3028, grass: 0xFF3D8A37, fenceColor: 0xFF1D2B3F, foulTrack: 2.5, wallColor: 0xFF3B2A30,
      stands: [
        ...bowl(seat: 0xFF7F1D2D, lower: 28, of: 16, ofSetback: 6, terrace: 4),
        StandTier(area: '内野', fromAngle: 45, toAngle: 150, baseHeight: 11, rows: 10, rowRise: 0.55, seatColor: 0xFF7F1D2D, setback: 13, roofColor: 0xFFB8BEC6, roofCover: 0.8),
      ],
      showMainVision: false,
      moreVisions: [
        Vision(angle: -6, behind: 12, bottom: 8, width: 26, height: 12, ribbon: false, content: 'main'),
        Vision(angle: 7.5, behind: 13, bottom: 8, width: 6, height: 16.2, ribbon: false, content: 'ads'),
        Vision(angle: 19, behind: 13, bottom: 8, width: 20.8, height: 16.2, ribbon: false, content: 'video'),
      ],
      lights: LightTower.six(125, 45, style: 'lattice', ads: 3, angles: [-105, -55, -20, 20, 55, 105]), scenery: ['ferris', 'town']);
  /// 京セラドーム大阪を参考：外野フェンス 4.2m の濃い紺（席とは別で少し内側）、外野席の最前列は高さ約 8m、
  ///  中堅のメインビジョン（8.7m×34m）と左右のウイングビジョン（8.6m×15m）の3面、ネット裏のサブ（2.6m×14.9m）、内野の上のサイドビジョン2基、二重の屋根
  static final Stadium osaka = park(id: 'osaka', carry: 0.943, name: '大阪湾岸ドーム', lf: 100, lcf: 116, cf: 122, rcf: 116, rf: 100, hl: 4.2, hc: 4.2, hr: 4.2,
      roof: 'ドーム', capacity: 36000, infield: 'grass', dirt: 0xFFE0703A, grass: 0xFF3E9C4A, fenceColor: 0xFF16224A, fenceAds: 'white', foulTrack: 3.5, wallColor: 0xFF16224A,
      domeHeight: 60, domeColor: 0xFF9AA3AD, domeStyle: 'ring', homeSide: 1,
      stands: bowl(seat: 0xFF3B3F9E, lower: 28, upper: 20, upperBase: 14, upperSetback: 14, upperRise: 0.6, of: 16, ofBase: 8.0, ofSetback: 4.0, ofUpper: 14, ofUpperBase: 16, ofUpperSetback: 18),
      showMainVision: false,
      moreVisions: [
        Vision(angle: 0, behind: 26, bottom: 26, width: 34, height: 8.7, ribbon: false, arc: true, content: 'main'),
        Vision(angle: -9.6, behind: 26, bottom: 26, width: 15, height: 8.6, ribbon: false, arc: true, content: 'video'),
        Vision(angle: 9.6, behind: 26, bottom: 26, width: 15, height: 8.6, ribbon: false, arc: true, content: 'ads'),
        Vision(angle: 180, behind: 52, bottom: 30, width: 14.9, height: 2.6, ribbon: false, content: 'score'),
        Vision(angle: -112, behind: 58, bottom: 25, width: 20, height: 4.9, ribbon: false, content: 'video'),
        Vision(angle: 112, behind: 58, bottom: 25, width: 20, height: 4.9, ribbon: false, content: 'video'),
      ],
      ribbons: const [Ribbon('tier', -150, -45), Ribbon('tier', 45, 150)]);
  /// ベルーナドームを参考：もとは屋外球場で、スタンドの上の柱で膜の屋根（直径 145m）を支え、屋根とスタンドの間に壁がない（外の森が見える）、
  ///  フェンスは中堅 3.2m から両翼 4.37m へ高くなる（ラバー＋金網）、中堅に 13m×46m のスコアボード、すり鉢の1層、赤い土
  static final Stadium saitama = park(id: 'saitama', carry: 0.945, name: '狭山丘陵ドーム', lf: 100, lcf: 116, cf: 122, rcf: 116, rf: 100, hl: 4.37, hc: 3.2, hr: 4.37,
      roof: 'ドーム', capacity: 31500, altitude: 100, infield: 'grass', dirt: 0xFFD9452B, grass: 0xFF3E9C4A, fenceColor: 0xFF1E2F5A, fenceNet: 1.2, foulTrack: 3.5,
      domeHeight: 45, domeColor: 0xFFF1F3F5, openSides: true, domeStyle: 'membrane',
      stands: bowl(seat: 0xFF7BAA3A, lower: 36, of: 22),
      vision: Vision(angle: 0, behind: 12, bottom: 10, width: 46, height: 13, ribbon: false, content: 'main'), scenery: ['forest']);
  /// 東京ドームを参考：白い膜の屋根（61.7m、外野へ向かって低い）、フェンス 4.24m（青いラバー4.0m＋ネット、上端は黄色）、
  ///  外野席の上ほぼ全体に横 125m のメインビジョン、外野席の最前列にリボンビジョン（ポール際から左中間・右中間）、オレンジの土
  static final Stadium tokyo = park(id: 'tokyo', carry: 0.94, name: '東京中央ドーム', lf: 100, lcf: 110, cf: 122, rcf: 110, rf: 100, hl: 4.24, hc: 4.24, hr: 4.24,
      roof: 'ドーム', capacity: 43500, infield: 'cutout', grass: 0xFF41A447, cutoutColor: 0xFFE57B3A, fenceColor: 0xFF1F4C9A, fenceNet: 0.24, wallColor: 0xFF1E3A8A,
      domeHeight: 62, domeColor: 0xFFF4F4F2, domeStyle: 'membrane', homeSide: 1,
      stands: bowl(seat: 0xFF1F4FB5, lower: 28, upper: 18, upperBase: 13, upperSetback: 14, of: 20, ofBase: 5.9, ofUpper: 10, ofUpperBase: 14, ofUpperSetback: 14),
      showMainVision: false,
      moreVisions: [Vision(angle: 0, behind: 22, bottom: 21, width: 125.6, height: 8.4, ribbon: false, arc: true, content: 'main')],
      ribbons: const [Ribbon('ofFront', -45, -20), Ribbon('ofFront', 20, 45), Ribbon('tier', -150, -45), Ribbon('tier', 45, 150)]);
  /// 阪神甲子園球場を参考：内野もファウルゾーンも黒土、つたの壁（3m＝ラバー1.9m＋金網0.7m、広告なし）、フェンス際 4.57m は人工芝、
  ///  銀傘（内野席の大屋根）の下にリボンビジョン（1.2m×250m）、中堅に 13m×31.6m のスコアボード、ネット裏にサブ（2.5m×28.3m）、浜風
  static final Stadium koshien = park(id: 'koshien', carry: 1.0, windFrom: 45, windSteady: 0.55, // 浜風：右翼から左翼・本塁の方へ（右方向のフライが押し戻される）
      name: '鳴尾浜球場', lf: 95, lcf: 118, cf: 118, rcf: 118, rf: 95, hl: 3.0, hc: 3.0, hr: 3.0,
      turf: '天然芝', capacity: 42600, wind: 1.15, infield: 'alldirt', dirt: 0xFF4A3A2E, grass: 0xFF3F8A3A, fenceColor: 0xFF2E5A2A, fenceNet: 0.7, fenceTop: 0, fenceAds: 'none',
      warning: 0xFF2F6B2E, homeSide: 1, bulge: 3.0, backstop: 19, foul: 21, dirtFoul: true, noAds: true, wallColor: 0xFF2E5A2A,
      stands: [
        // 内野と本塁の後ろ：大きな1層のすり鉢、上に銀傘（銀色の大屋根）
        StandTier(area: 'バックネット裏', fromAngle: 150, toAngle: 210, baseHeight: 1.2, rows: 42, rowRise: 0.46, seatColor: 0xFF2F6B3F, roofColor: 0xFFC9CED3, roofCover: 0.62, roofRise: 7),
        StandTier(area: '内野', fromAngle: -150, toAngle: -72, baseHeight: 1.2, rows: 42, rowRise: 0.46, seatColor: 0xFF2F6B3F, roofColor: 0xFFC9CED3, roofCover: 0.62, roofRise: 7),
        StandTier(area: '内野', fromAngle: 72, toAngle: 150, baseHeight: 1.2, rows: 42, rowRise: 0.46, seatColor: 0xFF2F6B3F, roofColor: 0xFFC9CED3, roofCover: 0.62, roofRise: 7),
        // アルプス席（屋根なし）
        StandTier(area: '内野', fromAngle: -72, toAngle: -45, baseHeight: 1.2, rows: 40, rowRise: 0.46, seatColor: 0xFF2F6B3F),
        StandTier(area: '内野', fromAngle: 45, toAngle: 72, baseHeight: 1.2, rows: 40, rowRise: 0.46, seatColor: 0xFF2F6B3F),
        StandTier(area: '外野', fromAngle: -45, toAngle: -7, baseHeight: 3.0, rows: 28, seatColor: 0xFF2F6B3F),
        StandTier(area: '外野', fromAngle: 7, toAngle: 45, baseHeight: 3.0, rows: 28, seatColor: 0xFF2F6B3F),
      ],
      showMainVision: false,
      moreVisions: [
        Vision(angle: 0, behind: 6, bottom: 9, width: 31.6, height: 13, ribbon: false, content: 'main', frame: 0xFF22302A),
        Vision(angle: 180, behind: 44, bottom: 21, width: 28.3, height: 2.5, ribbon: false, content: 'score'),
      ],
      ribbons: const [Ribbon('infieldBack', -150, -72), Ribbon('infieldBack', 72, 150), Ribbon('infieldBack', 150, 210)],
      lights: LightTower.six(122, 50, style: 'lattice', ads: 4, angles: [-108, -62, -24, 24, 62, 108]), adRing: true, scenery: ['town']);
  /// 横浜スタジアムを参考：どんぶり形のすり鉢、フェンス 5.0〜5.3m の青に白い字の広告、ポール際の上にとても急なウイング席、
  ///  逆三角形（Y の字）の照明塔 6基、中堅に大型ビジョン、外のビル群と赤白の塔
  static final Stadium yokohama = park(id: 'yokohama', carry: 0.988, name: '横浜港スタジアム', lf: 94.2, lcf: 111.4, cf: 117.7, rcf: 111.4, rf: 94.2, hl: 5.0, hc: 5.3, hr: 5.0,
      capacity: 34000, infield: 'grass', dirt: 0xFFB4553A, grass: 0xFF3B8E40, fenceColor: 0xFF1F55B5, fenceAds: 'white', fenceTop: 0, foulTrack: 2.0, wallColor: 0xFF1F55B5,
      stands: [
        ...bowl(seat: 0xFF1D5FD6, lower: 42, lowerRise: 0.48, of: 26),
        // ウイング席：外野の上にとても急な席
        StandTier(area: '外野', fromAngle: -45, toAngle: -18, baseHeight: 14, rows: 18, rowRise: 0.64, seatColor: 0xFF1D5FD6, setback: 20),
        StandTier(area: '外野', fromAngle: 18, toAngle: 45, baseHeight: 14, rows: 18, rowRise: 0.64, seatColor: 0xFF1D5FD6, setback: 20),
      ],
      vision: Vision(angle: 0, behind: 12, bottom: 12, width: 34, height: 14, ribbon: false, content: 'main'),
      lights: LightTower.six(118, 56, style: 'y', angles: [-115, -66, -28, 28, 66, 115]), scenery: ['skyline', 'marineTower']);
  /// MAZDA Zoom-Zoom スタジアム広島を参考：左右非対称、フェンスは左翼の直線部分 3.6m・中堅 2.5m（ラバー1.8m＋金網0.7m）・右翼 3.4m、
  ///  正面の左寄りに横 37.4m のスコアボード、内野2階の前にリボンビジョン、低い左翼席と広い右翼席、遠くの山並み、格子の刈り目の天然芝
  static final Stadium hiroshima = park(id: 'hiroshima', carry: 0.985, name: '広島ボールパーク', lf: 101, lcf: 116, cf: 122, rcf: 116, rf: 100, hl: 3.6, hlg: 3.0, hc: 2.5, hrg: 2.5, hr: 3.4,
      turf: '天然芝', capacity: 33000, infield: 'grass', dirt: 0xFF9C5A3C, grass: 0xFF3F8A3A, fenceColor: 0xFF22553A, fenceNet: 0.7, homeSide: 1, foulTrack: 3.0, mow: 'checker', wallColor: 0xFF5B1C1C,
      stands: bowl(seat: 0xFFB91C1C, lower: 26, upper: 14, upperBase: 11, upperSetback: 14, upperFrom: 52, of: 22, ofLeft: 12, roof: 0xFF9AA0A8, roofCover: 0.8, roofRise: 4),
      showMainVision: false,
      moreVisions: [Vision(angle: -11, behind: 14, bottom: 9, width: 37.4, height: 9, ribbon: false, content: 'main')],
      ribbons: const [Ribbon('tier', -150, -52), Ribbon('tier', 52, 150)],
      lights: LightTower.six(130, 48), scenery: ['mountains', 'town']);
  /// 明治神宮野球場を参考：フェンス 3.3m（青いラバー1.8m＋金網1.5m）、左右中間から両翼はまっすぐ、中堅に 12m×27.2m のスコアボード、
  ///  ネット裏の正面スタンドに白い膜の大屋根、細い柱の照明塔 6基、外の木々とビル
  static final Stadium jingu = park(id: 'jingu', carry: 0.957, name: '外苑球場', lf: 97.5, lcf: 112.3, cf: 120, rcf: 112.3, rf: 97.5, hl: 3.3, hc: 3.3, hr: 3.3, bulge: 0.2,
      capacity: 31000, infield: 'grass', dirt: 0xFFC0573A, grass: 0xFF3B8E40, fenceColor: 0xFF1F4FA0, fenceNet: 1.5, foulTrack: 2.5, wallColor: 0xFF1E3A8A,
      stands: [
        ...bowl(seat: 0xFF2563EB, lower: 30, of: 16),
        StandTier(area: 'バックネット裏', fromAngle: 150, toAngle: 210, baseHeight: 10, rows: 10, rowRise: 0.55, seatColor: 0xFF2563EB, setback: 13, roofColor: 0xFFF1F5F9, roofCover: 0.9, roofRise: 5),
        StandTier(area: '内野', fromAngle: -150, toAngle: -70, baseHeight: 10, rows: 10, rowRise: 0.55, seatColor: 0xFF2563EB, setback: 13),
        StandTier(area: '内野', fromAngle: 70, toAngle: 150, baseHeight: 10, rows: 10, rowRise: 0.55, seatColor: 0xFF2563EB, setback: 13),
      ],
      showMainVision: false,
      moreVisions: [Vision(angle: 0, behind: 10, bottom: 8, width: 27.2, height: 12, ribbon: false, content: 'main')],
      lights: LightTower.six(122, 44), scenery: ['trees', 'skyline']);
  /// バンテリンドーム ナゴヤを参考：鉄骨の三角格子の屋根、ホームランウイング（前のフェンス 3.6m＝紺のラバー2.6m＋ネット1.0m、後ろに元のフェンス 4.8m）、
  ///  中堅の上に横 106m・高さ 9.9m の1面の大型ビジョン、ネット裏に横 20m のサブビジョン、1階は青・2階は水色と黄色の座席、オレンジの土
  static final Stadium nagoya = park(id: 'nagoya', carry: 1.07, name: '尾張ドーム', lf: 100, lcf: 110, cf: 122, rcf: 110, rf: 100, hl: 3.6, hc: 3.6, hr: 3.6,
      roof: 'ドーム', capacity: 36000, infield: 'cutout', grass: 0xFF4CA94F, cutoutColor: 0xFFE8803E, fenceColor: 0xFF1C2E66, fenceNet: 1.0,
      oldFence: 4.8, oldFenceColor: 0xFF1C2E66, oldFenceBack: 4.5, wallColor: 0xFF1C2E66,
      domeHeight: 60, domeColor: 0xFF3A3F47, domeStyle: 'lattice',
      stands: bowl(seat: 0xFF1E40AF, upperSeat: 0xFF5EC4C9, ofUpperSeat: 0xFFE8C547, lower: 26, upper: 16, upperBase: 12, upperSetback: 15, of: 18, ofBase: 5.0, ofSetback: 5.0, terrace: 4, ofUpper: 12, ofUpperBase: 15, ofUpperSetback: 18),
      showMainVision: false,
      moreVisions: [
        Vision(angle: 0, behind: 26, bottom: 22, width: 106, height: 9.9, ribbon: false, arc: true, content: 'main'),
        Vision(angle: 180, behind: 46, bottom: 22, width: 20, height: 4.2, ribbon: false, content: 'score'),
      ],
      ribbons: const [Ribbon('tier', -150, -45), Ribbon('tier', 45, 150)]);

  static final List<Stadium> all = [standard, fukuoka, northPark, chiba, miyagi, osaka, saitama, tokyo, koshien, yokohama, hiroshima, jingu, nagoya];
  static final List<Stadium> viewChoices = all;
  static Stadium byId(String id) => (forceId == null ? _modded[id]?.$2 : null) ?? all.firstWhere((s) => s.id == (forceId ?? id), orElse: () => standard);

  /// 元の球場の ID（改修した球場は「元の ID@球団 ID」）
  String get baseId => id.split('@').first;

  /// 同じ中身の別の球場（改修に使う。フェンスなどの一覧は写す）
  Stadium copy({String? id}) => Stadium(
        id: id ?? this.id, name: name, fence: [...fence], backstop: backstop, foulFirst: foulFirst, foulThird: foulThird, foulCorner: foulCorner,
        homeDugout: homeDugout, awayDugout: awayDugout, bullpen: bullpen, turf: turf, roof: roof, capacity: capacity, altitude: altitude, windFactor: windFactor,
        stands: stands, vision: vision, ads: ads, moreVisions: moreVisions, showMainVision: showMainVision, roofRidge: roofRidge, glassWall: glassWall,
        buildings: buildings, outfieldBullpens: outfieldBullpens, infield: infield, dirtColor: dirtColor, turfColor: turfColor, fenceColor: fenceColor,
        seatColor: seatColor, domeHeight: domeHeight, domeColor: domeColor, domeOpenSides: domeOpenSides, domeStyle: domeStyle, dirtFoul: dirtFoul,
        foulTrack: foulTrack, cutoutColor: cutoutColor, mow: mow, lights: lights, adRing: adRing, scenery: scenery, straightFence: straightFence,
        fenceOverrides: [...fenceOverrides], carry: carry, windFrom: windFrom, windSteady: windSteady, fenceNet: fenceNet, fenceTop: fenceTop,
        fenceAds: fenceAds, oldFence: oldFence, oldFenceColor: oldFenceColor, oldFenceUpper: oldFenceUpper, oldFenceBack: oldFenceBack,
        wallColor: wallColor, ribbons: ribbons, warningColor: warningColor,
      );

  static final Map<String, (String, Stadium)> _modded = {};

  /// 球団が改修した本拠地（改修がなければ元の球場）。mods：terrace（true＝テラス新設、false＝もとからあるテラスを撤去）・
  ///  wall（true＝フェンスを 1.5m 高く）・turf（'天然芝'・'人工芝'）
  static Stadium modded(String baseId, String owner, Map<String, dynamic> mods) {
    final base = byId(baseId);
    if (mods.isEmpty || forceId != null) return base;
    final key = '${base.id}@$owner';
    final sig = (mods.entries.map((e) => '${e.key}=${e.value}').toList()..sort()).join(',');
    final hit = _modded[key];
    if (hit != null && hit.$1 == sig) return hit.$2;
    final s = base.copy(id: key);
    final terrace = mods['terrace'];
    if (terrace == true && base.oldFence <= 0) {
      // テラス新設：元のフェンスはテラス席の後ろの壁として残し、左右中間で最大 3m 前に低い（2.5m）フェンスを立てる
      s.oldFence = base.fenceHeight(-25);
      s.oldFenceBack = 3.0;
      s.fence = [
        for (final p in base.fence)
          FencePoint(p.angle, p.distance - s.terraceGap(p.angle), s.terraceGap(p.angle) > 0.3 ? math.min(p.height, 2.5) : p.height),
      ];
      s.fenceOverrides = [for (final o in base.fenceOverrides) (o.$1, o.$2, s.terraceGap((o.$1 + o.$2) / 2) > 0.3 ? math.min(o.$3, 2.5) : o.$3)];
    } else if (terrace == false && base.oldFence > 0) {
      // もとからあるテラスの撤去：前のフェンスを元のフェンスの位置・高さに戻す
      s.fence = [
        for (final p in base.fence)
          FencePoint(p.angle, p.distance + base.terraceGap(p.angle), base.terraceGap(p.angle) > 0.3 ? base.oldFence : p.height),
      ];
      s.oldFence = 0;
      s.oldFenceBack = 0;
    }
    if (mods['wall'] == true) {
      s.fence = [for (final p in s.fence) FencePoint(p.angle, p.distance, p.height + 1.5)];
      s.fenceOverrides = [for (final o in s.fenceOverrides) (o.$1, o.$2, o.$3 + 1.5)];
    }
    final turf = mods['turf'];
    if (turf is String && turf != base.turf) {
      s.turf = turf;
      s.turfColor = turf == '天然芝' ? 0xFF4A9A3C : 0xFF2F9E55;
      if (turf == '天然芝') s.mow = 'stripe';
    }
    _modded[key] = (sig, s);
    return s;
  }


  static String? forceId; // 調べ用：全試合をこの球場で

  /// 球団の本拠地の初期値（初期データの12球団）
  static String defaultFor(String teamId) =>
      const {'P0': 'fukuoka', 'P1': 'north', 'P2': 'chiba', 'P3': 'miyagi', 'P4': 'osaka', 'P5': 'saitama', 'C0': 'tokyo', 'C1': 'koshien', 'C2': 'yokohama', 'C3': 'hiroshima', 'C4': 'jingu', 'C5': 'nagoya'}[teamId] ??
      'std';

  /// 47 都道府県（北から）
  static const prefectures = [
    '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県', '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県', '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県', '静岡県', '愛知県', '三重県',
    '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県', '鳥取県', '島根県', '岡山県', '広島県', '山口県', '徳島県', '香川県', '愛媛県', '高知県', '福岡県', '佐賀県', '長崎県', '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県',
  ];

  /// 都道府県のおおよその緯度（天候の地域差に使う：北ほど涼しく、梅雨が短い。北海道は梅雨なし）
  static double latOf(String pref) {
    final i = prefectures.indexOf(pref);
    if (i < 0) return 35.7;
    const lat = [43.1, 40.8, 39.7, 38.3, 39.7, 38.2, 37.8, 36.3, 36.6, 36.4, 35.9, 35.6, 35.7, 35.4, 37.9, 36.7, 36.6, 36.1, 35.7, 36.7, 35.4, 35.0, 35.2, 34.7,
      35.0, 35.0, 34.7, 34.7, 34.7, 34.2, 35.5, 35.5, 34.7, 34.4, 34.2, 34.1, 34.3, 33.8, 33.6, 33.6, 33.2, 32.7, 32.8, 33.2, 31.9, 31.6, 26.2];
    return lat[i];
  }

  /// 球場の所在地（都道府県）
  String get prefecture => const {'fukuoka': '福岡県', 'north': '北海道', 'chiba': '千葉県', 'miyagi': '宮城県', 'osaka': '大阪府', 'saitama': '埼玉県', 'tokyo': '東京都', 'koshien': '兵庫県', 'yokohama': '神奈川県', 'hiroshima': '広島県', 'jingu': '東京都', 'nagoya': '愛知県'}[baseId] ?? '東京都';

  /// 試合で使う球場（試合のたびにホーム球団の本拠地に切り替わる）
  static Stadium current = standard;

  // ───── フェンス ─────
  double _interp(double ang, double Function(FencePoint) f) {
    final a = ang.clamp(fence.first.angle, fence.last.angle);
    var i = 0;
    while (i < fence.length - 2 && fence[i + 1].angle < a) {
      i++;
    }
    final p1 = fence[i], p2 = fence[i + 1];
    final p0 = i > 0 ? fence[i - 1] : p1, p3 = i + 2 < fence.length ? fence[i + 2] : p2;
    final u = (a - p1.angle) / (p2.angle - p1.angle);
    // Catmull-Rom（制御点を通る滑らかな曲線）
    final v0 = f(p0), v1 = f(p1), v2 = f(p2), v3 = f(p3);
    final u2 = u * u, u3 = u2 * u;
    return 0.5 * (2 * v1 + (-v0 + v2) * u + (2 * v0 - 5 * v1 + 4 * v2 - v3) * u2 + (-v0 + 3 * v1 - 3 * v2 + v3) * u3);
  }

  /// その角度でのフェンスまでの距離（m）
  double fenceDistance(double angleDeg) {
    if (!straightFence) return _interp(angleDeg, (p) => p.distance);
    // 直線のフェンス：となりの点どうしを直線で結び、その角度の線との交点までの距離
    final a = angleDeg.clamp(fence.first.angle, fence.last.angle);
    var i = 0;
    while (i < fence.length - 2 && fence[i + 1].angle < a) {
      i++;
    }
    final p1 = fence[i], p2 = fence[i + 1];
    double x(FencePoint p) => p.distance * math.sin(p.angle * math.pi / 180);
    double y(FencePoint p) => p.distance * math.cos(p.angle * math.pi / 180);
    final dx = math.sin(a * math.pi / 180), dy = math.cos(a * math.pi / 180);
    final ex = x(p2) - x(p1), ey = y(p2) - y(p1);
    final den = dx * ey - dy * ex;
    if (den.abs() < 1e-9) return p1.distance;
    return (x(p1) * ey - y(p1) * ex) / den;
  }

  /// その角度でのフェンスの高さ（m）
  /// テラス席（前のフェンスと元のフェンスの間）の奥行き：左右中間で最大、ポール際と中堅で 0
  double terraceGap(double a) {
    if (oldFence <= 0) return 0;
    final t = (a.abs() / 45).clamp(0.0, 1.0);
    return oldFenceBack * math.pow(math.sin(math.pi * t), 0.5).toDouble();
  }

  double fenceHeight(double angleDeg) {
    for (final o in fenceOverrides) {
      if (angleDeg >= o.$1 && angleDeg <= o.$2) return o.$3;
    }
    return _interp(angleDeg, (p) => p.height);
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name,
        'fence': [for (final p in fence) [p.angle, p.distance, p.height]],
        'backstop': backstop, 'foulFirst': foulFirst, 'foulThird': foulThird, 'foulCorner': foulCorner,
        'homeDugout': homeDugout.toJson(), 'awayDugout': awayDugout.toJson(), 'bullpen': bullpen,
        'turf': turf, 'roof': roof, 'capacity': capacity, 'altitude': altitude, 'wind': windFactor,
        'stands': [for (final s in stands) s.toJson()], 'vision': vision.toJson(), 'ads': [for (final a in ads) a.toJson()],
      };

  factory Stadium.fromJson(Map<String, dynamic> j) => Stadium(
        id: j['id'] ?? 'std',
        name: j['name'] ?? '球場',
        fence: [for (final p in (j['fence'] as List? ?? const [])) FencePoint((p[0] as num).toDouble(), (p[1] as num).toDouble(), (p[2] as num).toDouble())],
        backstop: (j['backstop'] ?? 18.3).toDouble(),
        foulFirst: (j['foulFirst'] ?? 18.3).toDouble(),
        foulThird: (j['foulThird'] ?? 18.3).toDouble(),
        foulCorner: (j['foulCorner'] ?? 3.0).toDouble(),
        homeDugout: j['homeDugout'] is Map ? Dugout.fromJson(Map<String, dynamic>.from(j['homeDugout'])) : null,
        awayDugout: j['awayDugout'] is Map ? Dugout.fromJson(Map<String, dynamic>.from(j['awayDugout'])) : null,
        bullpen: j['bullpen'] ?? '外野奥',
        turf: j['turf'] ?? '人工芝',
        roof: j['roof'] ?? '屋外',
        capacity: j['capacity'] ?? 32000,
        altitude: (j['altitude'] ?? 10).toDouble(),
        windFactor: (j['wind'] ?? 1.0).toDouble(),
        stands: j['stands'] is List ? [for (final s in j['stands']) StandTier.fromJson(Map<String, dynamic>.from(s))] : null,
        vision: j['vision'] is Map ? Vision.fromJson(Map<String, dynamic>.from(j['vision'])) : null,
        ads: j['ads'] is List ? [for (final a in j['ads']) AdBoard.fromJson(Map<String, dynamic>.from(a))] : null,
      );
}

class FencePoint {
  final double angle, distance, height;
  const FencePoint(this.angle, this.distance, this.height);
}

/// ベンチ（side：1＝一塁側、3＝三塁側）。本塁寄りの端・長さ・掘り下げの深さ・屋根の有無
class Dugout {
  int side;
  double start, length, depth;
  bool roof;
  Dugout({required this.side, this.start = 6.0, this.length = 18.0, this.depth = 1.0, this.roof = true});
  Map<String, dynamic> toJson() => {'side': side, 'start': start, 'length': length, 'depth': depth, 'roof': roof};
  factory Dugout.fromJson(Map<String, dynamic> j) =>
      Dugout(side: j['side'] ?? 3, start: (j['start'] ?? 6.0).toDouble(), length: (j['length'] ?? 18.0).toDouble(), depth: (j['depth'] ?? 1.0).toDouble(), roof: j['roof'] ?? true);
}

/// スタンドの段（内野・外野、1階・2階…）：範囲（角度）・最前列の高さ・段数・1段の高さと奥行き・座席の色
class StandTier {
  String area; // '内野'・'外野'・'バックネット裏'
  double fromAngle, toAngle; // 角度（中堅0°。内野はファウルゾーンの外側＝±45°より外まで）
  double baseHeight; // 最前列の床の高さ（フェンスの上・下の段の上）
  int rows;
  double rowRise, rowDepth;
  int seatColor; // 0xAARRGGBB
  double setback; // フェンス（下の段）から後ろへ下げる距離（2層目・3層目）
  int roofColor; // 段の上の屋根の色（0＝屋根なし）
  double roofCover, roofRise; // 屋根が覆う奥行きの割合（後ろから）・最後列の上の高さ
  StandTier({required this.area, required this.fromAngle, required this.toAngle, this.baseHeight = 3.0, this.rows = 30, this.rowRise = 0.40, this.rowDepth = 0.85, this.seatColor = 0xFF1E3A8A, this.setback = 0, this.roofColor = 0, this.roofCover = 0.55, this.roofRise = 6});

  static List<StandTier> standard({int seat = 0xFF1E3A8A, int? outfield}) => [
        StandTier(area: 'バックネット裏', fromAngle: 150, toAngle: 210, baseHeight: 1.2, rows: 34, seatColor: seat, roofColor: 0xFFCBD5E1),
        StandTier(area: '内野', fromAngle: -150, toAngle: -45, baseHeight: 1.2, rows: 34, seatColor: seat, roofColor: 0xFFCBD5E1),
        StandTier(area: '内野', fromAngle: 45, toAngle: 150, baseHeight: 1.2, rows: 34, seatColor: seat, roofColor: 0xFFCBD5E1),
        StandTier(area: '外野', fromAngle: -45, toAngle: -8, baseHeight: 3.0, rows: 22, seatColor: outfield ?? (seat == 0xFF1E3A8A ? 0xFF0F766E : seat)),
        StandTier(area: '外野', fromAngle: 8, toAngle: 45, baseHeight: 3.0, rows: 22, seatColor: outfield ?? (seat == 0xFF1E3A8A ? 0xFF0F766E : seat)),
      ];

  Map<String, dynamic> toJson() => {'area': area, 'from': fromAngle, 'to': toAngle, 'base': baseHeight, 'rows': rows, 'rise': rowRise, 'depth': rowDepth, 'color': seatColor};
  factory StandTier.fromJson(Map<String, dynamic> j) => StandTier(
      area: j['area'] ?? '内野', fromAngle: (j['from'] ?? 0).toDouble(), toAngle: (j['to'] ?? 0).toDouble(), baseHeight: (j['base'] ?? 3.0).toDouble(),
      rows: j['rows'] ?? 30, rowRise: (j['rise'] ?? 0.4).toDouble(), rowDepth: (j['depth'] ?? 0.85).toDouble(), seatColor: j['color'] ?? 0xFF1E3A8A);
}

/// ビジョン（メインの大型画面）。角度・フェンスより奥の距離・下端の高さ・幅・高さ。リボンビジョンの有無
class Vision {
  double angle, behind, bottom, width, height;
  bool ribbon;
  bool arc; // 本塁を中心にした弧にそって曲がる（外野席の上の横長のビジョン）
  String content; // 映すもの：'main'（得点表など）・'video'（打者の紹介）・'score'（得点表だけ）・'ads'（広告）・'lineupHome'・'lineupAway'・'speed'（球種と球速）
  int frame; // 枠の色
  Vision({this.angle = 0, this.behind = 14, this.bottom = 12, this.width = 30, this.height = 12, this.ribbon = true, this.arc = false, this.content = 'main', this.frame = 0xFF18181B});
  Map<String, dynamic> toJson() => {'angle': angle, 'behind': behind, 'bottom': bottom, 'w': width, 'h': height, 'ribbon': ribbon};
  factory Vision.fromJson(Map<String, dynamic> j) => Vision(
      angle: (j['angle'] ?? 0).toDouble(), behind: (j['behind'] ?? 14).toDouble(), bottom: (j['bottom'] ?? 12).toDouble(), width: (j['w'] ?? 30).toDouble(), height: (j['h'] ?? 12).toDouble(), ribbon: j['ribbon'] ?? true);
}

/// 看板の枠（場所・範囲）。中身はスポンサー契約から（sponsor が空なら球団の広告）
class AdBoard {
  String place; // '外野フェンス'・'内野フェンス'・'バックネット'・'スタンド上'
  double fromAngle, toAngle;
  String sponsor;
  AdBoard({required this.place, required this.fromAngle, required this.toAngle, this.sponsor = ''});

  static List<AdBoard> standard() => [
        for (var a = -45.0; a < 45; a += 11.25) AdBoard(place: '外野フェンス', fromAngle: a, toAngle: a + 11.25),
        AdBoard(place: 'バックネット', fromAngle: 160, toAngle: 200),
        AdBoard(place: '内野フェンス', fromAngle: -110, toAngle: -50),
        AdBoard(place: '内野フェンス', fromAngle: 50, toAngle: 110),
      ];

  Map<String, dynamic> toJson() => {'place': place, 'from': fromAngle, 'to': toAngle, 'sponsor': sponsor};
  factory AdBoard.fromJson(Map<String, dynamic> j) =>
      AdBoard(place: j['place'] ?? '外野フェンス', fromAngle: (j['from'] ?? 0).toDouble(), toAngle: (j['to'] ?? 0).toDouble(), sponsor: j['sponsor'] ?? '');
}

/// 外野の奥などの建物（見た目だけ）：角度・本塁からの距離・幅・奥行き・高さ・色
class Building {
  double angle, distance, width, depth, height;
  int color;
  String label;
  Building({required this.angle, required this.distance, required this.width, required this.depth, required this.height, this.color = 0xFF8D7B68, this.label = ''});
}

/// 照明塔：角度・本塁からの距離・高さ・形（'lattice'＝鉄骨の格子・'pole'＝柱の上に四角いライト）・塔に積む広告の数
class LightTower {
  final double angle, distance, height;
  final String style;
  final int ads;
  const LightTower(this.angle, this.distance, this.height, {this.style = 'pole', this.ads = 0});
  static List<LightTower> standard() => const [LightTower(-70, 135, 44), LightTower(-30, 135, 44), LightTower(30, 135, 44), LightTower(70, 135, 44)];
  static List<LightTower> six(double dist, double h, {String style = 'pole', int ads = 0, List<double> angles = const [-110, -62, -25, 25, 62, 110]}) =>
      [for (final a in angles) LightTower(a, dist, h, style: style, ads: ads)];
}

/// リボンビジョン（帯状の光る広告）：場所（'ofFront'＝外野席の最前列の前・'infieldBack'＝内野席の後ろの壁・'tier'＝上の段の前）と角度の範囲・高さ
class Ribbon {
  final String place;
  final double fromAngle, toAngle, height;
  const Ribbon(this.place, this.fromAngle, this.toAngle, {this.height = 1.28});
}
