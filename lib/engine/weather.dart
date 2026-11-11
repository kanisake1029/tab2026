import 'dart:math' as m;

import '../models/stadium.dart';

/// 空模様
enum Sky { sunny, cloudy, lightRain, heavyRain }

/// 屋根の種類
///  dome：完全ドーム（天候の影響なし）／retractable：開閉式（雨・寒さ・猛暑の日は閉める）
///  semiOpen：屋根はあるが壁がない（狭山丘陵ドーム：雨天中止はないが、気温・湿度・風の影響を半分受ける）／open：屋外（雨天中止あり）
enum RoofType { dome, retractable, semiOpen, open }

/// 1日の天気（球場の所在地の緯度と季節から決める。同じ日・同じ球場ならいつも同じ）
class DailyWeather {
  final Sky sky;
  final double tempC; // 試合時間（夕方〜夜。デーゲームは少し高い）の気温 8〜36℃
  final double humidity; // 0.3〜0.9
  const DailyWeather(this.sky, this.tempC, this.humidity);

  /// セーブデータごとの天気の種（同じセーブなら、日程の天気予報と試合の天気が同じになる）
  static int saveSeed = 0;

  bool get rain => sky == Sky.lightRain || sky == Sky.heavyRain;

  String get label => switch (sky) { Sky.sunny => '晴れ', Sky.cloudy => 'くもり', Sky.lightRain => '小雨', Sky.heavyRain => '大雨' };
  String get icon => switch (sky) { Sky.sunny => '☀', Sky.cloudy => '☁', Sky.lightRain => '☂', Sky.heavyRain => '☔' };

  /// 雨の降りやすさ（小雨＋大雨）と、そのうち大雨の割合。月・日・緯度から
  ///  6月〜7月中旬は梅雨（北海道＝緯度 41 度より北は梅雨なし）、8月は夕立、9月は台風（南ほど多い）
  static (double, double) rainChance(int month, int day, double lat) {
    final north = lat >= 41;
    var p = switch (month) { 3 => 0.18, 4 => 0.22, 5 => 0.22, 6 => 0.3, 7 => day <= 18 ? 0.3 : 0.15, 8 => 0.15, 9 => 0.24, 10 => 0.18, _ => 0.15 };
    var heavy = 0.2;
    if ((month == 6 || (month == 7 && day <= 18)) && !north) heavy = 0.3; // 梅雨の大雨
    if (month == 6 && north) p = 0.15;
    if (month == 7 && north) p = 0.16;
    if (month == 9) {
      p += (36 - lat).clamp(-3.0, 5.0) * 0.01; // 台風は南ほど
      heavy = 0.32;
    }
    return (p.clamp(0.05, 0.4), heavy);
  }

  /// 月ごとの平年の気温（夕方〜夜、緯度 35.5 度＝東京の目安）と湿度
  static (double, double) climate(int month) => switch (month) {
        2 => (7.0, 0.5),
        3 => (11.0, 0.55),
        4 => (16.0, 0.6),
        5 => (20.0, 0.65),
        6 => (23.0, 0.75),
        7 => (27.0, 0.78),
        8 => (28.5, 0.76),
        9 => (24.5, 0.72),
        10 => (18.0, 0.66),
        11 => (12.0, 0.6),
        _ => (8.0, 0.55),
      };

  static DailyWeather of(String stadiumId, String prefecture, DateTime date, {int seed = 0}) {
    final lat = Stadium.latOf(prefecture);
    final r = m.Random(seed * 7919 + stadiumId.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0xffffff) + date.year * 10000 + date.month * 100 + date.day);
    final (p, heavy) = rainChance(date.month, date.day, lat);
    final x = r.nextDouble();
    final Sky sky;
    if (x < p * heavy) {
      sky = Sky.heavyRain;
    } else if (x < p) {
      sky = Sky.lightRain;
    } else if (x < p + 0.32) {
      sky = Sky.cloudy;
    } else {
      sky = Sky.sunny;
    }
    final (t0, h0) = climate(date.month);
    // 北ほど涼しい（緯度 1 度で約 0.8℃）。8月の本州以南は猛暑寄り
    var t = t0 - (lat - 35.5) * 0.8 + (date.month == 8 && lat < 37 ? 1.0 : 0) + _g(r) * 2.4;
    var h = h0 + _g(r) * 0.08;
    switch (sky) {
      case Sky.sunny:
        t += 1.2;
        h -= 0.06;
      case Sky.cloudy:
        break;
      case Sky.lightRain:
        t -= 1.5;
        h += 0.1;
      case Sky.heavyRain:
        t -= 2.5;
        h += 0.15;
    }
    return DailyWeather(sky, t.clamp(8.0, 36.0), h.clamp(0.3, 0.9));
  }

  static double _g(m.Random r) => m.sqrt(-2 * m.log(1 - r.nextDouble())) * m.cos(2 * m.pi * r.nextDouble());
}

/// 試合のときの天候（屋根を考えた、グラウンドで効く値）
class GameWeather {
  final DailyWeather outside; // 外の天気
  final RoofType roof;
  final bool roofClosed; // 開閉式の屋根を閉めた
  const GameWeather(this.outside, this.roof, this.roofClosed);

  /// 球場の屋根の種類（仕様：東京中央・博多湾・尾張・大阪湾岸は完全ドーム、北の開閉式は開閉式、狭山丘陵は半屋外、ほかは屋外）
  static RoofType roofOf(Stadium st) {
    switch (st.baseId) {
      case 'tokyo' || 'fukuoka' || 'nagoya' || 'osaka':
        return RoofType.dome;
      case 'north':
        return RoofType.retractable;
      case 'saitama':
        return RoofType.semiOpen;
    }
    return switch (st.roof) { 'ドーム' => RoofType.dome, '開閉式' => RoofType.retractable, _ => RoofType.open };
  }

  static String roofLabel(RoofType r) => switch (r) { RoofType.dome => 'ドーム', RoofType.retractable => '開閉式屋根', RoofType.semiOpen => '屋根つき（壁なし）', RoofType.open => '屋外' };

  factory GameWeather.of(Stadium st, String prefecture, DateTime date, {int seed = 0}) {
    final w = DailyWeather.of(st.id, prefecture, date, seed: seed);
    final roof = roofOf(st);
    // 開閉式：雨・寒い（15℃未満）・猛暑（30℃以上）の日は屋根を閉める
    final closed = roof == RoofType.retractable && (w.rain || w.tempC < 15 || w.tempC >= 30);
    return GameWeather(w, roof, closed);
  }

  /// 天候の影響を受けない（屋根を閉めた室内）
  bool get indoor => roof == RoofType.dome || roofClosed;

  /// 雨天中止（屋外の球場で大雨）
  bool get rainout => roof == RoofType.open && outside.sky == Sky.heavyRain;

  /// 小雨の中で試合をする（屋外）：地面が重く、ボールが滑る
  bool get wetPlay => roof == RoofType.open && outside.sky == Sky.lightRain;

  /// 猛暑（32℃以上。屋外と狭山丘陵ドーム）：試合中の体力の減りが増える
  bool get heat => (roof == RoofType.open || roof == RoofType.semiOpen || (roof == RoofType.retractable && !roofClosed)) && outside.tempC >= 32;

  /// グラウンドでの気温・湿度・風の効き方（室内は 22℃・50%・無風、半屋外は外との半分ずつ）
  double get tempC => indoor ? 22 : (roof == RoofType.semiOpen ? 22 + (outside.tempC - 22) * 0.5 : outside.tempC);
  double get humidity => indoor ? 0.5 : (roof == RoofType.semiOpen ? 0.5 + (outside.humidity - 0.5) * 0.5 : outside.humidity);
  double get windMul => indoor ? 0 : (roof == RoofType.semiOpen ? 0.5 : 1);

  String get text {
    if (roof == RoofType.dome) return 'ドーム（外は${outside.label}）';
    final base = '${outside.icon}${outside.label} ${outside.tempC.round()}℃ 湿度${(outside.humidity * 100).round()}%';
    if (roofClosed) return '$base（屋根を閉めて試合）';
    return base;
  }

  /// いま試合中の天候（打球の物理・守備のミスで使う。試合を始めるたびに切り替える）
  static GameWeather? current;
}
