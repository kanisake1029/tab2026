import 'dart:math' as m;

import '../models/player.dart';
import 'field_time.dart';
import 'vec3.dart';

/// 【Layer 2】走塁の道筋と速さ（仕様書 2.1）。試合の結果の計算と 3D の再生で同じものを使う
///  ・塁は本塁 (0,0)、一塁 (19.397,19.397)、二塁 (0,38.795)、三塁 (−19.397,19.397)。1次元のレール s（0＝本塁、1＝一塁 … 4＝本塁）
///  ・塁を回るときは直角ではなく、塁の手前約9mから外へ膨らみ、塁の内側の角を踏んで次の塁へ切れ込む（バナナ型）
///  ・曲がるときは横向きの加速度の限界（√(a横·半径)）まで速さが落ちる
///  ・終わり方は4通り：一塁の駆け抜け（全速で踏み、ファウル側へ 4m/s² で減速）／立ったまま止まる（3.5m 手前から制動）／
///    スライディング（4m 手前から摩擦 μ=0.4 で減速）／回って止まる（オーバーランして戻る）
///  ・帰塁は s が減る向きに同じレールをたどる（二塁を越えた走者が一塁へ戻るときは、二塁を踏み直す）
enum RunEnd { runThrough, stand, slide, overrun }

class BasePath {
  static const bases = [V3(0, 0, 0), V3(19.397, 19.397, 0), V3(0, 38.795, 0), V3(-19.397, 19.397, 0), V3(0, 0, 0)];
  static const between = 27.432;
  static bool curves = true; // false：以前の計算（比較用）

  /// レールの上の点（まっすぐな塁間）
  static V3 railPos(double s) {
    final c = s.clamp(0.0, 4.0);
    final i = m.min(3, c.floor());
    return bases[i].lerp(bases[i + 1], c - i);
  }

  /// 塁 i の手前で膨らみ始める距離（m）と、塁を回ったあと次の塁間の線へ戻るまで（m）
  static const turnIn = 9.0, turnOut = 7.0, turnR = 6.5;

  /// 曲がるときの横向きの加速度の限界（m/s²）：走力が高いほど鋭く回れる
  static double latAccel(int run) => 6.0 + 0.025 * run;
  static const slideDecel = 0.4 * 9.8; // スライディングの摩擦
  static const throughDecel = 4.0; // 一塁を駆け抜けたあと
  static const stopDecel = 8.0; // 立ったまま止まる（スタッターステップ）
  static const brakeDecel = 6.0; // 曲がる前に落とす
}

/// 1回の走塁（s の始まり → 目標の塁）。道筋の点・その点の速さと時刻
class BaseRun {
  final List<V3> pts = [];
  final List<double> rail = []; // その点の s（塁を踏んだかの判定用）
  final List<double> v = [], t = [];
  int touchIndex = 0; // 目標の塁を踏む点
  late final double tArrive; // 走り出してから目標の塁を踏むまで（秒）
  late final RunEnd end;
  final int to;

  /// 駆け抜けは一塁だけ（二塁・三塁は踏んで止まるかスライディング）
  BaseRun(Sprint sp, {required double sFrom, required this.to, RunEnd end = RunEnd.stand, double v0 = 0, int run = 60, double overrunDist = 4.5}) {
    this.end = (end == RunEnd.runThrough && to != 1) ? RunEnd.slide : end;
    final back = to < sFrom - 1e-6; // 帰塁
    if (back) {
      _backPath(sFrom);
    } else {
      _forwardPath(sFrom, overrunDist);
    }
    _speeds(sp, v0, run, back);
    tArrive = t[touchIndex];
  }

  static final Map<String, double> _cache = {};

  /// 走る時間（目標の塁を踏むまで）。結果の計算用（同じ条件は覚えておく）
  static double time(Player p, {required double sFrom, required int to, RunEnd end = RunEnd.stand, double v0 = 0}) {
    if (!BasePath.curves) {
      // 比較用：以前の計算（まっすぐ＋塁を回るごとに4%）
      final n = (to - sFrom).abs();
      return Sprint.of(p.run).time(n * BasePath.between * (1 + 0.04 * m.max(0.0, n.ceil() - 1.0)), v0: v0);
    }
    final key = '${p.run}|${(sFrom * 20).round()}|$to|${end.index}|${(v0 * 4).round()}';
    final c = _cache[key];
    if (c != null) return c;
    if (_cache.length > 20000) _cache.clear();
    return _cache[key] = BaseRun(Sprint.of(p.run), sFrom: sFrom, to: to, end: end, v0: v0, run: p.run).tArrive;
  }

  void _add(V3 p, double s) {
    if (pts.isNotEmpty && pts.last.distanceTo(p) < 1e-4) return;
    pts.add(p);
    rail.add(s);
  }

  void _line(V3 a, V3 b, double sa, double sb) {
    final n = m.max(1, (a.distanceTo(b) / 0.8).ceil());
    for (var i = 1; i <= n; i++) {
      _add(a.lerp(b, i / n), sa + (sb - sa) * i / n);
    }
  }

  void _bez(V3 p0, V3 c0, V3 c1, V3 p1, double sa, double sb) {
    const n = 14;
    for (var i = 1; i <= n; i++) {
      final u = i / n, w = 1 - u;
      _add(p0 * (w * w * w) + c0 * (3 * w * w * u) + c1 * (3 * w * u * u) + p1 * (u * u * u), sa + (sb - sa) * u);
    }
  }

  /// 塁 i を回る：手前で外へ膨らみ（S字）、半径 R の弧で塁の内側の角を踏み、出たあと次の塁間の線へ戻る。cur から入る
  ///  弧は塁の上で 45° 内向き。入口は塁の 0.71R 手前・0.29R 外、出口も同じだけ外（R＝6.5m で約1.9m 膨らむ）
  V3 _round(V3 cur, int i, double sCur, {bool exit = true}) {
    final bi = BasePath.bases[i];
    final din = (bi - BasePath.bases[i - 1]).unit, dout = (BasePath.bases[i + 1] - bi).unit;
    const r = BasePath.turnR;
    V3 left(V3 d) => V3(-d.y, d.x, 0);
    final c = bi + left(din).rotate(V3.ez, 45 * deg) * r; // 弧の中心（内側）
    final e = c - left(din) * r, x = c - left(dout) * r; // 入口・出口
    final lIn = m.max(1.0, m.min(BasePath.turnIn, (e - cur).dot(din)));
    final p0 = e - din * lIn;
    final p0b = p0 - left(din) * ((p0 - bi).dot(left(din))); // 膨らみ始め（塁間の線の上）
    final sP0 = i - (bi - p0b).dot(din) / BasePath.between;
    _line(cur, p0b, sCur, sP0);
    _bez(p0b, p0b + din * (lIn * 0.45), e - din * (lIn * 0.45), e, sP0, i - 0.7 * r / BasePath.between);
    const n = 16;
    var hit = pts.length - 1;
    for (var k = 1; k <= n; k++) {
      final d = din.rotate(V3.ez, 90 * deg * k / n);
      _add(c - left(d) * r, i + (k / n - 0.5) * 1.4 * r / BasePath.between);
      if (k == n ~/ 2) hit = pts.length - 1;
    }
    _lastHit = hit;
    if (!exit) return x; // オーバーラン：弧を出た所で止まる
    const lOut = BasePath.turnOut;
    final p2 = x + dout * lOut;
    final p2b = p2 - left(dout) * ((p2 - bi).dot(left(dout)));
    _bez(x, x + dout * (lOut * 0.45), p2b - dout * (lOut * 0.45), p2b, i + 0.7 * r / BasePath.between, i + (p2b - bi).dot(dout) / BasePath.between);
    _lastHit = hit;
    return p2b;
  }

  int _lastHit = 0;

  void _forwardPath(double sFrom, double overrunDist) {
    var cur = BasePath.railPos(sFrom);
    var sCur = sFrom;
    _add(cur, sFrom);
    final first = sFrom.floor() + 1;
    for (var i = first; i < to; i++) {
      cur = _round(cur, i, sCur);
      sCur = rail.last;
    }
    final bt = BasePath.bases[to];
    if (end == RunEnd.overrun && to < 4) {
      _round(cur, to, sCur, exit: false); // 回って、弧を出た所（塁の約5m先）で止まる
      touchIndex = _lastHit;
      return;
    }
    _line(cur, bt, sCur, to.toDouble());
    touchIndex = pts.length - 1;
    if (end == RunEnd.runThrough) {
      // 一塁だけ：全速で踏み、ファウル側へ少し振って減速
      final din = (bt - BasePath.bases[to - 1]).unit.rotate(V3.ez, -8 * deg);
      _line(bt, bt + din * 12, to.toDouble(), to.toDouble());
    }
  }

  /// 帰塁：レールを逆向きにたどる（途中の塁は踏み直す）
  void _backPath(double sFrom) {
    _add(BasePath.railPos(sFrom), sFrom);
    var s = sFrom;
    while (s > to + 1e-6) {
      final next = (s - 1e-6).floor().toDouble() < to ? to.toDouble() : (s - 1e-6).floor().toDouble();
      _line(BasePath.railPos(s), BasePath.railPos(next), s, next);
      s = next;
    }
    touchIndex = pts.length - 1;
  }

  void _speeds(Sprint sp, double v0, int run, bool back) {
    final n = pts.length;
    final ds = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      ds[i] = pts[i].distanceTo(pts[i - 1]);
    }
    // 曲がる所の上限
    final vMax = List<double>.filled(n, sp.vTop);
    final aLat = BasePath.latAccel(run);
    for (var i = 1; i + 1 < n; i++) {
      final r = _radius(pts[i - 1], pts[i], pts[i + 1]);
      if (r.isFinite && !(end == RunEnd.runThrough && i >= touchIndex)) vMax[i] = m.min(sp.vTop, m.sqrt(aLat * r));
    }
    // 終わり方
    final dTo = List<double>.filled(n, 0); // 目標の塁までの残り（道のり）
    for (var i = touchIndex - 1; i >= 0; i--) {
      dTo[i] = dTo[i + 1] + ds[i + 1];
    }
    if (end == RunEnd.stand || back) vMax[touchIndex] = m.min(vMax[touchIndex], 0.6);
    if (end == RunEnd.overrun || end == RunEnd.runThrough) vMax[n - 1] = 0;
    // 前から：加速（スライディング中は摩擦で減速、駆け抜けたあとは 4m/s²）
    v.add(m.min(v0, vMax[0]));
    for (var i = 1; i < n; i++) {
      final pv = v[i - 1];
      double nv;
      if (end == RunEnd.slide && !back && i <= touchIndex && dTo[i - 1] <= 4.0) {
        nv = m.sqrt(m.max(0.0, pv * pv - 2 * BasePath.slideDecel * ds[i]));
      } else if (end == RunEnd.runThrough && i > touchIndex) {
        nv = m.sqrt(m.max(0.0, pv * pv - 2 * BasePath.throughDecel * ds[i]));
      } else {
        nv = m.min(vMax[i], m.sqrt(pv * pv + 2 * sp.accel * ds[i]));
      }
      v.add(nv);
    }
    // 後ろから：曲がる前・止まる前の減速（スライディングと駆け抜けの区間は前からの計算のまま）
    for (var i = n - 2; i >= 0; i--) {
      if (end == RunEnd.slide && !back && i < touchIndex && dTo[i] <= 4.0) continue;
      if (end == RunEnd.runThrough && i >= touchIndex) continue;
      final stopping = (end == RunEnd.stand || back) && i < touchIndex && dTo[i] <= 3.5;
      final a = stopping ? BasePath.stopDecel : BasePath.brakeDecel;
      v[i] = m.min(v[i], m.sqrt(v[i + 1] * v[i + 1] + 2 * a * ds[i + 1]));
    }
    t.add(0);
    for (var i = 1; i < n; i++) {
      t.add(t[i - 1] + ds[i] / m.max(0.35, (v[i] + v[i - 1]) / 2));
    }
  }

  static double _radius(V3 a, V3 b, V3 c) {
    final ab = a.distanceTo(b), bc = b.distanceTo(c), ca = c.distanceTo(a);
    final cr = (b - a).cross(c - a).length;
    if (cr < 1e-6) return double.infinity;
    return ab * bc * ca / (2 * cr);
  }

  /// 時刻 tt（走り出し＝0）の位置
  V3 posAt(double tt) {
    if (tt <= 0) return pts.first;
    if (tt >= t.last) return pts.last;
    var lo = 0, hi = t.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (t[mid] <= tt) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final f = (tt - t[lo]) / m.max(1e-6, t[hi] - t[lo]);
    return pts[lo].lerp(pts[hi], f);
  }

  double speedAt(double tt) {
    if (tt <= 0) return v.first;
    for (var i = 1; i < t.length; i++) {
      if (t[i] >= tt) return v[i - 1] + (v[i] - v[i - 1]) * ((tt - t[i - 1]) / m.max(1e-6, t[i] - t[i - 1]));
    }
    return v.last;
  }

  /// 目標の塁までの残りの道のり（スライディングを始めるかの判断）
  double distToBase(double tt) => pts[touchIndex].distanceTo(posAt(tt));
  double get tEnd => t.last;
}
