import 'dart:math';
import '../models/player.dart';
import 'matchup_book.dart';
import 'pitch_catalog.dart';

/// 打者の詳しい成績：項目ごとに [打数, 安打, 本塁打, 三振] を PlayerStats.spl に積み上げる（1軍の公式戦）。
///  コース   c1〜c25：5×5のマス（打者から見て左上から。左＝内角、上＝高め。7〜9・12〜14・17〜19がストライクゾーン）
///  打球方向 d0〜d4 ：フェアゾーンを5等分（左・左中・中・右中・右）。前に飛んだ打球だけ
///  球種     t…     ：ストレート・速球系（ツーシームなど）・スライダー系・カーブ系・フォーク系・シンカー系
///  球速     v…     ：〜129・130〜139・140〜144・145〜149・150〜154・155〜
///  投手の被打率は、同じ項目の頭に p を付けて投手の成績に積み上げる（pc13・pt…など。コースは打者から見た向き）
class BattingSplits {
  static const dirNames = ['左', '左中', '中', '右中', '右'];
  static const typeNames = ['ストレート', '速球系', 'スライダー系', 'カーブ系', 'フォーク系', 'シンカー系'];
  static const speedNames = ['〜129', '130〜139', '140〜144', '145〜149', '150〜154', '155〜'];
  static const zoneCells = {7, 8, 9, 12, 13, 14, 17, 18, 19};

  /// コースのマス（1〜25）。x は投球のゾーン座標（±1 がゾーン端）。右打者は +x が内角（シミュレーターと同じ向き）
  static int cell(double x, double z, String bats) {
    final u = x * (bats == 'L' ? -1 : 1);
    int band(double v) => v > 1 ? 0 : (v > 1 / 3 ? 1 : (v >= -1 / 3 ? 2 : (v >= -1 ? 3 : 4)));
    return band(z) * 5 + band(u) + 1;
  }

  /// 打球方向（0＝左〜4＝右）。落下地点（+x が右翼側、+y が中堅方向）から
  static int dir(double landX, double landY) {
    final a = (atan2(landX, max(0.1, landY)) * 180 / pi).clamp(-45.0, 44.99);
    return ((a + 45) / 18).floor().clamp(0, 4);
  }

  static String? type(String pitchName) {
    if (pitchName == 'ストレート') return 'ストレート';
    final g = PitchCatalog.groupOf(pitchName);
    if (g.isEmpty) return null;
    return g == 'ストレート系' ? '速球系' : g;
  }

  static int speedBand(double kmh) => kmh < 130 ? 0 : (kmh < 140 ? 1 : (kmh < 145 ? 2 : (kmh < 150 ? 3 : (kmh < 155 ? 4 : 5))));

  /// 1打席分を足す（打数のある打席だけ。四死球・犠打は数えない）
  static void add(PlayerStats st, VsLine r, {required double x, required double z, required String bats, required String pitchName, required double speed, double? landX, double? landY, String prefix = ''}) {
    if (r.ab == 0) return;
    void inc(String k) {
      final v = st.spl.putIfAbsent('$prefix$k', () => [0, 0, 0, 0]);
      v[0] += 1;
      v[1] += r.h;
      v[2] += r.hr;
      v[3] += r.so;
    }

    inc('c${cell(x, z, bats)}');
    final t = type(pitchName);
    if (t != null) {
      inc('t$t');
      inc('v${speedBand(speed)}');
    }
    if (r.so == 0 && landX != null && landY != null) inc('d${dir(landX, landY)}');
  }

  /// 表のセル：「.275(40-11) HR 1 K 3」（打数-安打）。打球方向は三振がないので K を出さない
  static String text(List<int>? v, {bool k = true, String sep = ' '}) {
    if (v == null || v[0] == 0) return '-';
    final avg = (v[1] / v[0]).toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');
    return '$avg(${v[0]}-${v[1]})${sep}HR ${v[2]}${k ? ' K ${v[3]}' : ''}';
  }
}
