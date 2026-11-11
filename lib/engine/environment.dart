import 'dart:math' as m;
import 'spec_constants.dart';
import '../models/stadium.dart';
import 'vec3.dart';
import 'weather.dart';

/// 試合の環境（第0層：空気・風・地面）
///  空気密度 ρ は標高（気圧）・気温・湿度から。抗力もマグヌス力も ρ に比例する
///  風は本塁基準の座標（x＝一塁側、y＝中堅方向）の向きの速度。ボールには「ボールの速度 − 風」が空気に対する速度になる
class GameEnv {
  final double altitude; // m
  final double tempC;
  final double humidity; // 0〜1
  final double rho; // kg/m³
  final V3 wind; // m/s
  final bool dome;
  const GameEnv({required this.altitude, required this.tempC, required this.humidity, required this.rho, required this.wind, required this.dome});

  /// 標準の空気（海抜10m・20℃・湿度60%・無風）。これまでの計算（ρ≒1.20）と同じ
  static final GameEnv standard = GameEnv.of(altitude: 10, tempC: 20, humidity: 0.6);

  factory GameEnv.of({required double altitude, required double tempC, required double humidity, V3 wind = V3.zero, bool dome = false}) =>
      GameEnv(altitude: altitude, tempC: tempC, humidity: humidity, rho: airDensity(altitude, tempC, humidity), wind: wind, dome: dome);

  /// 空気密度：気圧（標準大気の標高の式）・飽和水蒸気圧（Tetens の式）・乾燥空気と水蒸気の気体定数
  ///  水蒸気（分子量18）は乾燥空気（約29）より軽いので、湿度が高いほど少し軽くなる
  static double airDensity(double altitude, double tempC, double humidity) {
    final p = 101325 * m.pow(1 - 2.25577e-5 * altitude, 5.25588); // Pa
    final es = 610.78 * m.pow(10, 7.5 * tempC / (tempC + 237.3)); // Pa
    final pv = humidity.clamp(0.0, 1.0) * es;
    final tk = tempC + 273.15;
    return (p - pv) / (287.058 * tk) + pv / (461.495 * tk);
  }

  /// 月ごとの夕方〜夜の気温と湿度（日本の平年の目安）
  static (double, double) _climate(int month) => switch (month) {
        3 => (10.0, 0.55),
        4 => (15.0, 0.60),
        5 => (19.0, 0.65),
        6 => (22.0, 0.75),
        7 => (26.0, 0.78),
        8 => (27.0, 0.76),
        9 => (23.0, 0.72),
        10 => (17.0, 0.66),
        11 => (12.0, 0.60),
        _ => (8.0, 0.55),
      };

  /// 試合の環境：球場（標高・屋根）と日付から。屋外は試合ごとに気温が少し揺れ、風が吹く（同じ試合はいつも同じ）
  ///  weather（その日の天候）があれば、気温・湿度・屋根はそこから（夏の高温多湿は空気が軽く、打球が伸びる）
  factory GameEnv.forGame(Stadium st, DateTime date, {int seed = 0, GameWeather? weather}) {
    if (weather != null ? weather.indoor : st.roof == 'ドーム') return GameEnv.of(altitude: st.altitude, tempC: 22, humidity: 0.5, dome: true);
    final r = m.Random(seed ^ (date.year * 10000 + date.month * 100 + date.day));
    final (t0, h0) = _climate(date.month);
    final rt = r.nextDouble(), rh = r.nextDouble();
    final t = weather?.tempC ?? t0 + (rt - 0.5) * 6;
    final h = weather?.humidity ?? (h0 + (rh - 0.5) * 0.2).clamp(0.3, 0.95);
    // 風：平均 2.5m/s 前後。向きは毎試合ちがう（球場ごとの吹きやすい向きは今後）
    final speed = m.max(0.0, 2.5 + _g(r) * 1.5) * st.windFactor * (weather?.windMul ?? 1.0);
    var dir = r.nextDouble() * 2 * m.pi;
    // 球場ごとのよく吹く風（甲子園の浜風など）：吹く先の向き＝来る向き＋180°、±25°ばらつく
    if (!st.windFrom.isNaN && r.nextDouble() < st.windSteady) dir = (st.windFrom + 180 + (r.nextDouble() - 0.5) * 50) * m.pi / 180;
    return GameEnv.of(altitude: st.altitude, tempC: t, humidity: h, wind: V3(speed * m.sin(dir), speed * m.cos(dir), 0), dome: false);
  }

  static double _g(m.Random r) => m.sqrt(-2 * m.log(1 - r.nextDouble())) * m.cos(2 * m.pi * r.nextDouble());

  /// 物理の計算を使い回すときの目印（空気密度 0.005 刻み・風 0.5m/s 刻み）
  String get key => '${(rho * 200).round()}|${(wind.x * 2).round()}|${(wind.y * 2).round()}';

  /// 風の表示（例：「センター方向へ 3m」）
  String get windText {
    final s = m.sqrt(wind.x * wind.x + wind.y * wind.y);
    if (dome || s < 0.5) return '無風';
    final ang = m.atan2(wind.x, wind.y) * 180 / m.pi; // 0＝中堅へ（追い風）
    final a = ang.abs();
    String dirText;
    if (a < 30) {
      dirText = 'センター方向へ';
    } else if (a > 150) {
      dirText = 'ホーム方向へ';
    } else if (a < 70) {
      dirText = ang > 0 ? 'ライト方向へ' : 'レフト方向へ';
    } else if (a < 110) {
      dirText = ang > 0 ? '一塁側へ' : '三塁側へ';
    } else {
      dirText = ang > 0 ? '一塁側からホームへ' : '三塁側からホームへ';
    }
    return '$dirText ${s.toStringAsFixed(1)}m';
  }
}

/// 地面の跳ね方：垂直の反発係数 e と、1回跳ねたときの横の速さの減り方、転がるときの抵抗
class Surface {
  final String name;
  final double restitution, bounceLoss, rolling;
  const Surface(this.name, this.restitution, this.bounceLoss, this.rolling);

  /// 人工芝（いまの NPB のロングパイル。昔のカーペットより柔らかい）：よく跳ね、1回で約20%減速、転がりは天然芝より少し速い
  static Surface get artificial => Spec.fie ? Surface('人工芝', Spec.artificial.$1, Spec.artificial.$2, 0.30) : const Surface('人工芝', 0.52, 0.20, 0.37);

  /// 天然芝（柔らかい）：芝に食われて1回で25〜30%減速
  static Surface get natural => Spec.fie ? Surface('天然芝', Spec.natural.$1, Spec.natural.$2, 0.42) : const Surface('天然芝', 0.40, 0.27, 0.42);

  /// 土（内野・ウォーニングトラック）
  static Surface get dirt => Spec.fie ? Surface('土', Spec.dirt.$1, Spec.dirt.$2, 0.40) : const Surface('土', 0.48, 0.22, 0.40);

  static Surface grassOf(Stadium st) => st.turf == '天然芝' ? natural : artificial;

  /// 小雨の中の試合：土と天然芝は水を含んで重くなり、打球が死ぬ（跳ねたときの減速・転がりの抵抗が 2 割増し）
  static Surface _wet(Surface s) => (GameWeather.current?.wetPlay ?? false) && s.name != '人工芝' ? Surface(s.name, s.restitution * 0.95, m.min(0.9, s.bounceLoss * 1.2), s.rolling * 1.2) : s;

  /// 打球が落ちた場所の地面（本塁基準の座標）
  static Surface at(Stadium st, double x, double y) => _wet(_at(st, x, y));

  static Surface _at(Stadium st, double x, double y) {
    final d = m.sqrt(x * x + y * y);
    if (d <= 3.96) return dirt; // 本塁のまわり（半径 13ft。7.92m は直径）
    final ang = m.atan2(x, y) * 180 / m.pi;
    if (ang.abs() <= 45 && d >= st.fenceDistance(ang) - 4.6) return dirt; // ウォーニングトラック
    // 内野の土：投手板から半径 95ft（28.96m）の内側で、内野の芝（ベースラインの内側）を除く
    final dm = m.sqrt(x * x + (y - 18.29) * (y - 18.29));
    if (dm <= 28.96 && ang.abs() <= 50) {
      if (dm <= 2.74) return dirt; // マウンド
      // 内野の芝：塁を結ぶ正方形の内側（ベースラインの幅 0.9m を除く）
      final u = (x + y) / m.sqrt2, v = (y - x) / m.sqrt2; // 本塁から一塁・三塁方向の座標
      if (u > 1.5 && v > 1.5 && u < 27.43 - 0.9 && v < 27.43 - 0.9) return grassOf(st);
      return dirt;
    }
    return grassOf(st);
  }
}
