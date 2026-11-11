import 'dart:math' as m;
import '../models/player.dart';
import 'field_time.dart';
import 'pitch_engine.dart';
import 'spec_constants.dart';

/// 戦術の時間（第5章）
///  盗塁：投手のクイック＋捕手のポップタイム＋タッチ ＜＝＞ 走者の到達時間（リード・スタートの利得込み）

class StealRace {
  /// 調整用（成功率を NPB の約70%に合わせる）
  static double bias = -0.12;

  /// 投手のクイック：動き始めから捕手のミットに届くまで（秒）。kmh：実際に投げた球の速さ（省略時は最高球速）
  static double quickTime(Player p, {double? kmh}) {
    final ph = PitcherPhysics.of(p);
    final flight = ph.flightTime * p.velocity / (kmh ?? p.velocity.toDouble()).clamp(70.0, 170.0);
    if (Spec.pit) return Spec.quickMotion(p.quick) + flight; // 仕様書 6.2
    return (ph.quickRelease + flight) * 1.08 * (1 + (60 - p.quick) * 0.004);
  }

  /// 捕球してから送球の体勢に入るまでの遅れ（秒）：ワンバウンド・低め・左右に外れた球は遅く、高めは速い
  ///  wz：球の高さ（m）、wx：ホームの中心からの左右（m）
  static double receiveDelay(Player? c, {required double wz, required double wx}) {
    final fc = c?.fieldC ?? 50;
    var d = 0.0;
    if (wz < 0.22) {
      d += 0.14 + (60 - fc) * 0.003; // ワンバウンド：止めてから拾う
    } else if (wz < 0.55) {
      d += (0.55 - wz) * 0.25;        // 低め：体を起こしながら
    } else if (wz > 1.15 && wz < 1.6) {
      d -= 0.03;                       // 高め：そのまま投げる体勢
    } else if (wz >= 1.6) {
      d += 0.04;                       // 高すぎる：伸び上がって捕る
    }
    if (wx.abs() > 0.30) d += (wx.abs() - 0.30) * 0.30; // 左右に外れた球
    return d * (1.2 - fc / 250); // 守備のうまい捕手ほど遅れが小さい
  }

  /// 捕手のポップタイム：捕球から塁に届くまで（二塁へ約1.8〜2.0秒）
  static double popTime(Player c, {required bool toSecond, bool pitchOut = false}) {
    final transfer = 0.75 + (60 - c.fieldC) * 0.004 + c.glove.transferDelay * 0.5 - (pitchOut ? 0.12 : 0);
    final speed = (Spec.thr ? Spec.throwMaxKmh(c.arm) : 115 + c.arm * 0.25) / 3.6; // 肩60で 130km/h（二塁へのポップタイム 約2.0秒）
    final d = toSecond ? 39.4 : 28.0;
    return transfer + ThrowStyle.flight(d, speed);
  }

  /// 走者の到達時間（投手が動き始めてから）。リード・スタートの読み・スライディング込み
  static double runTime(Player r, {required bool toSecond, required bool lefty}) {
    final lead = (toSecond ? 3.4 : 4.6) + (r.run - 60) * 0.01 - (lefty && toSecond ? 0.3 : 0);
    final jump = 0.10 + (r.run - 60) * 0.002 - (lefty && toSecond ? 0.06 : 0); // 投手の動き出しを読む利得
    return 0.18 - jump + Sprint.of(r.run).time(27.43 - lead, v0: 2.0) + 0.10; // クロスオーバーステップで初速あり
  }

  /// 盗塁の結果：守備側の時間 − 走者の時間 ＋ ばらつき が ＋なら成功。
  ///  投げた球（速さ kmh・高さ wz・左右 wx）で、ミットに届く時間と捕手の握り替えが変わる。
  ///  送球の正確さ：それた分だけタッチが遅れ、まれに悪送球（走者はもう1つ進む）
  static ({bool safe, bool error, double tDef, double tRun}) race(Player runner, Player pitcher, Player? catcher,
      {required bool toSecond, bool pitchOut = false, double runnerBonus = 0, double? kmh, double wz = 0.9, double wx = 0.15, required m.Random rnd}) {
    double g() => m.sqrt(-2 * m.log(1 - rnd.nextDouble())) * m.cos(2 * m.pi * rnd.nextDouble());
    final c = catcher;
    final acc = c?.throwAccuracy ?? 50;
    final off = g().abs() * (0.04 + (70 - acc).clamp(0, 60) * 0.0015); // 送球のそれ（タッチまでの遅れ）
    final tDef = quickTime(pitcher, kmh: kmh) + (pitchOut ? 0 : receiveDelay(c, wz: wz, wx: wx)) + (c == null ? 1.95 : popTime(c, toSecond: toSecond, pitchOut: pitchOut)) + 0.10 + off - (pitchOut ? 0.18 : 0);
    final tRun = runTime(runner, toSecond: toSecond, lefty: pitcher.throws == 'L') - runnerBonus;
    final error = rnd.nextDouble() < 0.006 + m.max(0, 55 - acc) * 0.0008;
    return (safe: error || tDef - tRun + (Spec.thr ? Spec.stealBias : bias) + g() * 0.11 > 0, error: error, tDef: tDef, tRun: tRun);
  }
}

/// フレーミング：捕手が際どい球をミットでゾーンへ止める（2〜4cm）。ゾーンの端の判定が捕手の守備力で動く
class Framing {
  /// ゾーン座標でのずらし（＋＝ストライクが広がる）
  static double umpEdge = 0.96;

  static double shift(Player? catcher) => catcher == null ? 0 : ((catcher.fieldC - 60) * 0.003).clamp(-0.12, 0.15);

  /// 見逃しの判定：ゾーンの端の近くは審判の見え方で揺れる
  static bool calledStrike(double x, double z, Player? catcher, m.Random rnd) {
    final d = m.max(x.abs(), z.abs()) - shift(catcher);
    final umpEdge = Spec.zon ? Spec.umpEdge : Framing.umpEdge;
    // 審判のゾーンはルールの端よりわずかに内側（NPB の四球率 約8% に合わせた値）。端の前後 ±0.12 は確率
    if (d < umpEdge - 0.12) return true;
    if (d > umpEdge + 0.12) return false;
    return rnd.nextDouble() < (umpEdge + 0.12 - d) / 0.24;
  }
}

/// バント：バットを引いて打球を殺す（打球の速さ 7〜14m/s）。一塁・三塁へ転がす。ポップになると捕られる
class BuntBall {
  final double speed, launch, direction; // m/s・度・度（＋＝一塁側）
  const BuntBall(this.speed, this.launch, this.direction);

  /// バットの上下の芯ずれ（打球の角度のぶれ）が、投球の高さ・変化の大きさで大きくなる感度
  static double eySens = 1.6;
  /// バットの引き（勢いの殺し方）のばらつき（m/s）
  static double pullSpread = 3.75;

  /// pitchZ：投球の高さ（ゾーンの座標。＋＝高め）、brk：変化の大きさ（0〜1。ホップ・落差）
  static BuntBall make(Player b, {required bool toFirst, required double pitchKmh, required m.Random rnd, double pitchZ = 0, double brk = 0.35}) {
    double g() => m.sqrt(-2 * m.log(1 - rnd.nextDouble())) * m.cos(2 * m.pi * rnd.nextDouble());
    final skill = (b.contactLeft + b.contactRight) / 2;
    final dead = (1 - (skill - 50) * 0.004).clamp(0.6, 1.3); // うまいほど勢いを殺せる
    final speed = ((4.5 + pitchKmh / 3.6 * 0.06) * dead + g() * pullSpread).clamp(2.5, 18.0); // 強すぎる・弱すぎるバントもある
    // 上下の芯ずれ：高めはバットの下に当たって上がり（小フライ）、低めは叩きつける。変化が大きいほどずれが大きい
    final bias = eySens * (6.0 * m.max(0.0, pitchZ - 0.2) - 4.0 * m.max(0.0, -0.4 - pitchZ));
    final sigma = (11 - (skill - 50) * 0.05) * (1 + eySens * 0.55 * brk);
    final launch = (-2 + bias + g() * sigma).clamp(-35.0, 60.0);
    final dir = (toFirst ? 18.0 : -18.0) + g() * (13 - (skill - 50) * 0.06);
    return BuntBall(speed, launch, dir);
  }
}

enum BuntResult { sacrifice, hit, forceOut, doublePlay, popOut }

/// バントの処理（投内連携）：打球が転がる → 投手・捕手・一塁手・三塁手（バントシフトで前進）のうち最も早く捕れる野手 →
///  先の走者のフォース（間に合えば）→ 併殺の転送 ／ 一塁送球。打者は構えた体勢から走るので脱出が短い
class BuntPlay {
  static ({BuntResult result, String fielder}) resolve({
    required BuntBall ball,
    required Player batter,
    required bool batterLefty,
    required Player? runner1B,
    required Player? runner2B,
    required Map<String, Player> defense, // 'P'・'C'・'1B'・'3B'・'2B'・'SS'
    required int outs,
    required m.Random rnd,
  }) {
    // 小フライ：上がりすぎた打球は捕られる（飛びつく野手が近い）
    if (ball.launch > 18 && ball.speed < 16) return (result: BuntResult.popOut, fielder: ball.direction > 0 ? '1B' : 'P');
    // 打球の位置（転がりながら減速：土の上 0.40g）
    final dir = ball.direction * m.pi / 180;
    final v0 = ball.speed * m.cos(ball.launch.clamp(-30, 30) * m.pi / 180);
    const decel = 0.40 * 9.8;
    double posAt(double t) {
      final tt = m.min(t, v0 / decel);
      return v0 * tt - 0.5 * decel * tt * tt;
    }

    // 野手：スタート位置と反応（バントシフトの一塁・三塁は投球と同時に前進している）
    final starts = <String, (double, double, double)>{
      'P': (0.0, 16.5, 0.45),
      'C': (0.0, -1.0, 0.35),
      '1B': (17.0, 19.0, 0.25), // 打者がバントの構えを見せてから前進
      '3B': (-17.0, 19.0, 0.25),
    };
    String best = 'P';
    var bt = double.infinity;
    starts.forEach((role, s) {
      final f = defense[role];
      if (f == null) return;
      final sp = Fielding.sprint(f);
      for (var t = 0.2; t < 4.0; t += 0.05) {
        final d = posAt(t);
        final bx = d * m.sin(dir), by = d * m.cos(dir);
        final dist = m.sqrt(m.pow(bx - s.$1, 2) + m.pow(by - s.$2, 2));
        if (s.$3 + sp.time(m.max(0, dist - Fielding.reach(f))) <= t) {
          if (t < bt) {
            bt = t;
            best = role;
          }
          break;
        }
      }
    });
    bt += 0.3; // かがんで拾う
    final f = defense[best]!;
    final dGo = posAt(bt - 0.3);
    final fx = dGo * m.sin(dir), fy = dGo * m.cos(dir);
    double g() => m.sqrt(-2 * m.log(1 - rnd.nextDouble())) * m.cos(2 * m.pi * rnd.nextDouble());
    double throwT(double tx, double ty) => ThrowStyle.best(f, m.sqrt(m.pow(tx - fx, 2) + m.pow(ty - fy, 2)), ballSlow: true).t;
    final tBatter = (batterLefty ? 0.20 : 0.25) + Sprint.of(batter.run).time(27.43) + g() * 0.08;
    // 先の走者：二塁（一塁走者）・三塁（二塁走者がいて一塁も埋まっているとき）
    final lead = runner2B != null && runner1B != null ? runner2B : runner1B;
    if (lead != null && outs < 2) {
      final toThird = lead == runner2B;
      // 走者は第2リードから、打球が転がる（ライナーでない）のを確かめてスタート
      final tRun = 0.3 + Sprint.of(lead.run).time(27.43 - (toThird ? 5.6 : 4.6), v0: 2.0) + g() * 0.08;
      final base = toThird ? (-19.4, 19.4) : (0.0, 38.8);
      final tForce = bt + throwT(base.$1, base.$2) + 0.05;
      if (tForce < tRun - 0.05) {
        // 併殺：二塁（三塁）で受けた野手が一塁へ
        final tDp = tForce + 0.55 + ThrowStyle.flight(toThird ? 38.8 : 27.43, ThrowStyle.sidearm.speed);
        return (result: tDp < tBatter ? BuntResult.doublePlay : BuntResult.forceOut, fielder: best);
      }
    }
    final t1B = bt + throwT(19.4, 19.4) + 0.05;
    return (result: t1B < tBatter ? BuntResult.sacrifice : BuntResult.hit, fielder: best);
  }
}
