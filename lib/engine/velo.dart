import 'dart:math' as m;

import '../models/player.dart';

/// 球速の基準（2026-11 改定）
///  NPB 1軍はおおむね 150km 以上、プロ入りする高校生（育成級）は 140〜144km、MLB の最速で 170km。
///  135〜145km で通用するのは、特殊な軌道のアンダースロー（体感で約10km 速い）くらい。
///  速い球ほど指数関数的に打ちにくく（試合）、伸ばしにくい（成長）。
class Velo {
  /// 腕の角度による体感の上乗せ（km/h）
  static int slotBonus(String slot) => switch (slot) { 'アンダー' => 10, 'サイド' => 3, _ => 0 };

  /// 球速 → 能力の値（0〜100）。130km=0、150km≈57、155km≈68、160km≈79、165km≈90、170km=100
  static int norm(int v, {String slot = ''}) {
    final e = v + slotBonus(slot);
    if (e <= 130) return 0;
    if (e >= 170) return 100;
    return (100 * m.pow((e - 130) / 40, 0.82)).round();
  }

  /// 能力の値（0〜100）→ 球速
  static int fromNorm(num n) => (130 + 40 * m.pow(n.clamp(0, 100) / 100, 1 / 0.82)).round();

  /// 以前の基準の球速を新しい基準に底上げする（160km 以上とアンダースローはそのまま）
  ///  プロ（支配下・海外のプロ）：遅いほど大きく上げる（140→147、145→150、150→154、155→157）
  ///  アマチュア・育成：控えめ（140→143、145→147、150→152）
  static int lift(int v, {bool amateur = false, String slot = ''}) {
    if (slot == 'アンダー' || v >= 160) return v;
    final k = amateur ? 0.85 : 0.65;
    return (160 - (160 - v) * k).round();
  }

  /// 選手の球速を v に変え、持ち球の球速も同じ比率で変える
  static void setTo(Player p, int v) {
    final old = p.velocity;
    if (old <= 0 || old == v) {
      p.velocity = v;
      return;
    }
    final r = v / old;
    p.velocity = v;
    for (final x in p.pitches) {
      x.speed = (x.speed * r).round().clamp(70, 175);
    }
  }

  /// 作ったばかりの選手：生成の値（以前の基準）から底上げする（アンダースローはそのまま）
  static void liftNew(Player p, {bool amateur = false}) {
    if (!p.isPitcher && !p.twoWay) return;
    setTo(p, lift(p.velocity, amateur: amateur, slot: p.armSlot));
  }

  // ── 試合：速い球ほど打ちにくい ──
  /// タイミングのばらつきの倍率の中心（この体感球速で1倍）
  static double pivot = 157;
  /// 何km で e 倍になるか
  static double scaleKm = 17;

  /// 対応力1あたり、何km で e 倍になるかの伸び（対応力が高いほど速い球でも崩れにくい）
  static double adaptK = 0.02;
  /// 基準より速い球の効き：1 + 差 × fastLinK（0 なら指数関数のまま）
  static double fastLinK = 0.0;

  /// 打者の対応力（動体視力・反応）：ミート5割・選球眼3割・パワー（スイングの速さ＝引きつけて打てる）2割
  static double adapt(int meet, int eye, int power) => meet * 0.5 + eye * 0.3 + power * 0.2;

  /// 体感球速 → タイミングのばらつきの倍率（指数関数）。対応力65 の打者で 145km≈0.66、152km=1、160km≈1.6、165km≈2.2
  ///  対応力80 なら 160km≈1.4、対応力50 なら 160km≈2.0
  static double timingMul(double perceivedKmh, {double adapt = 65}) {
    final k = scaleKm * (1 + (adapt - 65) * adaptK).clamp(0.6, 1.8);
    final x = (perceivedKmh - pivot) / k;
    // 基準より速い側は、倍々ではなくまっすぐ増える（fastLinK 倍の傾き）。遅い側は今までどおり
    return (x <= 0 || fastLinK <= 0 ? m.exp(x) : 1 + x * fastLinK).clamp(0.4, 4.0);
  }
}
