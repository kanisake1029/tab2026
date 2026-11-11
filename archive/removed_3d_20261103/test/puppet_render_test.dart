// 2D の人形（2.5D の選手）を画像に描き出して、見た目（体の線のつなぎ目など）を確かめるためのテスト。
//  実機がなくても確認できるように、いくつかの姿勢とカメラの向きで PNG を書き出す。
//  flutter test test/puppet_render_test.dart --dart-define=OUT=<書き出し先のフォルダ>
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/body_model.dart';
import 'package:npb_pennant_app/engine/pitch_motion.dart' show J;
import 'package:npb_pennant_app/engine/play_motion.dart';
import 'package:npb_pennant_app/engine/vec3.dart';
import 'package:npb_pennant_app/models/uniform.dart';
import 'package:npb_pennant_app/widgets/pitch3d/poses.dart';
import 'package:npb_pennant_app/widgets/pitch3d/puppet2d.dart';
import 'package:npb_pennant_app/widgets/pitch3d/scene_util.dart';
import 'package:npb_pennant_app/widgets/pitch3d/toon_rig.dart';

void main() {
  test('人形を画像に描き出す', () async {
    const out = String.fromEnvironment('OUT');
    if (out.isEmpty) return;
    Directory(out).createSync(recursive: true);
    final base = BodyModel.of(heightCm: 180, weightKg: 84, armCm: 80);
    PuppetRig mk(String id, {bool helmet = false, bool glove = true}) =>
        PuppetRig(FaceLook.of(id), Uniform.basic(0xFFE67E22), real: base, glove: glove, helmet: helmet)
          ..number = '18'
          ..teamText = 'ソフトクリーム';
    void pose(PuppetRig r, List<V3> p, {V3? look}) {
      final q = r.prepare(p, look: look);
      r.poseOut(r.human.fk(q));
    }

    // 姿勢：構えた野手・立つ・走る・送球・捕手・打者
    final rigs = <(String, PuppetRig, List<V3>, bool)>[];
    final pz = Poser(base);
    final a = mk('a');
    pose(a, pz.ready(V3.zero, 0, crouch: 0.5, look: const V3(0, -20, 1)));
    rigs.add(('ready', a, const [], false));
    final b = mk('b');
    pose(b, pz.stand(V3.zero, 0.6, look: const V3(5, -20, 1.5)));
    rigs.add(('stand', b, const [], false));
    final c = mk('c');
    pose(c, pz.throwBall(V3.zero, 0.0, 0.55, armSlot: 35, look: const V3(0, 30, 1.5)));
    rigs.add(('throw', c, const [], false));
    final d = mk('d', glove: true);
    pose(d, StaticPoses.catcher(base));
    rigs.add(('catcher', d, const [], true));
    final e = mk('e', helmet: true, glove: false);
    pose(e, StaticPoses.batter(base, right: true));
    rigs.add(('batter', e, const [], false));

    // 動きの途中（MOTION=1）：送球・スイング・走り・ゴロ捕球の各段階を斜め前と横から（線の重なりを確かめる）
    if (const String.fromEnvironment('MOTION') == '1') {
      final frames = <(String, PuppetRig, V3?, V3?)>[];
      for (final u in [0.2, 0.4, 0.55, 0.7, 0.9]) {
        final r = mk('t${(u * 100).round()}');
        pose(r, pz.throwBall(V3.zero, 0.0, u, armSlot: 35, look: const V3(0, 30, 1.5)));
        frames.add(('m_throw${(u * 100).round()}', r, null, null));
      }
      for (final t in [-0.3, -0.12, 0.0, 0.1, 0.3]) {
        final r = mk('s${(t * 100).round()}', helmet: true, glove: false);
        final sw = pz.swingAt(right: true, t: t, contact: const V3(-0.1, 0.7, 0.85), look: const V3(0, 10, 1.2));
        pose(r, sw.p);
        final o = r.out!.p;
        final knob = (o[J.wristT.index] + o[J.wristG.index]) * 0.5 - sw.bat * 0.06;
        frames.add(('m_swing${(t * 100).round()}', r, knob, knob + sw.bat * 0.84));
      }
      for (final ph in [0.0, 0.25, 0.5, 0.75]) {
        final r = mk('r${(ph * 100).round()}', helmet: true, glove: false);
        pose(r, pz.run(V3.zero, 0, 7.5, ph * 2 * math.pi, look: const V3(0, 20, 1.6)));
        frames.add(('m_run${(ph * 100).round()}', r, null, null));
      }
      for (final u in [0.3, 0.6, 0.9]) {
        final r = mk('g${(u * 100).round()}');
        pose(r, pz.fieldGround(V3.zero, 0, u, look: const V3(0, -20, 0)));
        frames.add(('m_ground${(u * 100).round()}', r, null, null));
      }
      for (final (name, rig, knob, tip) in frames) {
        for (final (vn, ang) in [('q', 40.0), ('s', 90.0), ('f', 0.0)]) {
          final pel = rig.out!.p[J.pelvis.index];
          final ctr = V3(pel.x, pel.y, 1.0);
          final dir = V3(math.sin(ang * math.pi / 180), math.cos(ang * math.pi / 180), 0);
          final cam = PerspectiveCamera(position: sv(ctr + dir * 4.2 + const V3(0, 0, 0.7)), target: sv(ctr), fovRadiansY: 0.62);
          final painter = PuppetPainter(items: () => [PuppetItem(rig, batKnob: knob, batTip: tip)], camera: () => cam, ball: () => null, repaint: ValueNotifier(0));
          const w = 600.0, h = 600.0;
          final rec = ui.PictureRecorder();
          final cv = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
          cv.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF4E9B47));
          cv.translate(w, 0);
          cv.scale(-1, 1);
          painter.paint(cv, const Size(w, h));
          final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/${name}_$vn.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        }
      }
      return;
    }
    // 顔の一覧（FACES=1）：いろいろな選手（年齢・体格・能力・国籍）の顔を 40 人、正面からと斜めから並べる（見分けがつくかを見る）
    if (const String.fromEnvironment('FACES') != '') {
      // FACES=2：最初の 8 人を大きく、正面・斜め 35°・真横から（目・眉・輪郭・横顔を見る）
      final bigT = const String.fromEnvironment('FACES') == '2';
      final cols = bigT ? 6 : 10, rowsN = bigT ? 4 : 8, tile = bigT ? 330.0 : 150.0;
      final rec = ui.PictureRecorder();
      final cv = Canvas(rec, Rect.fromLTWH(0, 0, cols * tile, rowsN * tile));
      cv.drawRect(Rect.fromLTWH(0, 0, cols * tile, rowsN * tile), Paint()..color = const Color(0xFF4E9B47));
      final labels = <String>[];
      for (var i = 0; i < (bigT ? 8 : 40); i++) {
        final rnd = math.Random(1000 + i * 7);
        final age = 19 + rnd.nextInt(20);
        final pitcher = rnd.nextBool();
        final face = FaceLook.of('p${i * 37}',
            foreign: rnd.nextDouble() < 0.2,
            age: age,
            bmi: 21 + rnd.nextDouble() * 9,
            pitcher: pitcher,
            power: 35 + rnd.nextInt(60),
            run: 35 + rnd.nextInt(60),
            contact: 35 + rnd.nextInt(60),
            velocity: pitcher ? 138 + rnd.nextInt(24) : 0,
            control: 35 + rnd.nextInt(60));
        labels.add(FaceLook.archetypeNames[face.archetype]);
        final r = PuppetRig(face, Uniform.basic(const [0xFF1D4ED8, 0xFFE67E22, 0xFFB91C1C, 0xFF15803D, 0xFF111827][i % 5]), real: base, glove: true, helmet: i % 9 == 4);
        pose(r, pz.stand(V3.zero, 0, look: const V3(0, 20, 1.75)));
        final views = bigT ? const [(0, 0.0), (1, 35.0), (2, 90.0)] : const [(0, 0.0), (1, 35.0)];
        for (final (vi, ang) in views) {
          final head = r.out!.p[J.head.index];
          final dir = V3(math.sin(ang * math.pi / 180), math.cos(ang * math.pi / 180), 0);
          final cam = PerspectiveCamera(position: sv(head + dir * (bigT ? 1.7 : 2.2) + V3(0, 0, bigT ? 0.06 : 0.18)), target: sv(head + V3(0, 0, bigT ? -0.03 : 0.1)), fovRadiansY: 0.36);
          final painter = PuppetPainter(items: () => [PuppetItem(r)], camera: () => cam, ball: () => null, repaint: ValueNotifier(0));
          final idx = i * views.length + vi;
          final ox = (idx % cols) * tile, oy = (idx ~/ cols) * tile;
          cv.save();
          cv.translate(ox, oy);
          cv.clipRect(Rect.fromLTWH(0, 0, tile, tile));
          cv.translate(tile, 0);
          cv.scale(-1, 1);
          painter.paint(cv, Size(tile, tile));
          cv.restore();
        }
      }
      final img = await rec.endRecording().toImage((cols * tile).toInt(), (rowsN * tile).toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File(bigT ? '$out/faces12.png' : '$out/faces40.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('型: ${labels.join(' ')}');
      return;
    }
    // 顔の見本：選手ごとの顔（id・国籍・年齢・体格を変えて）を、正面・斜め・横から大きく
    {
      final faces = <(String, bool, int, double)>[('p01', false, 24, 22), ('p02', false, 33, 27), ('p03', true, 28, 25), ('p04', false, 38, 24), ('p05', true, 30, 29), ('p06', false, 21, 21), ('p07', true, 26, 23), ('p08', false, 29, 26)];
      for (final (fid, foreign, age, bmi) in faces) {
        final r = PuppetRig(FaceLook.of(fid, foreign: foreign, age: age, bmi: bmi), Uniform.basic(0xFF1D4ED8), real: base, glove: true);
        pose(r, pz.stand(V3.zero, 0, look: const V3(0, 20, 1.75)));
        for (final (vn, ang) in [('f', 0.0), ('q', 35.0), ('s', 80.0)]) {
          final head = r.out!.p[J.head.index];
          final dir = V3(math.sin(ang * math.pi / 180), math.cos(ang * math.pi / 180), 0);
          final cam = PerspectiveCamera(position: sv(head + dir * 2.2 + const V3(0, 0, 0.05)), target: sv(head - const V3(0, 0, 0.08)), fovRadiansY: 0.36);
          final painter = PuppetPainter(items: () => [PuppetItem(r)], camera: () => cam, ball: () => null, repaint: ValueNotifier(0));
          const w = 420.0, h = 420.0;
          final rec = ui.PictureRecorder();
          final cv = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
          cv.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF4E9B47));
          cv.translate(w, 0);
          cv.scale(-1, 1);
          painter.paint(cv, const Size(w, h));
          final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/face_${fid}_$vn.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        }
      }
    }
    // カメラ：正面・斜め前・横・斜め後ろ・後ろ・上から（人形の正面は +y 向き＝heading 0）
    final views = <(String, double, double)>[('front', 0, 1.6), ('q1', 40, 1.8), ('side', 90, 1.6), ('q3', 140, 1.8), ('back', 180, 1.6), ('high', 25, 5.0)];
    const w = 900.0, h = 900.0;
    for (final (name, rig, _, gear) in rigs) {
      for (final (vn, ang, ht) in views) {
        // 人形の中心を写す（本塁基準の座標。体の中心は原点、捕手・打者は少しずれている）
        final pel = rig.out!.p[J.pelvis.index];
        final ctr = V3(pel.x, pel.y, 1.0);
        final dir = V3(math.sin(ang * math.pi / 180), math.cos(ang * math.pi / 180), 0);
        final pos = ctr + dir * 4.2 + V3(0, 0, ht - 1.0);
        final cam = PerspectiveCamera(position: sv(pos), target: sv(ctr), fovRadiansY: 0.62);
        final painter = PuppetPainter(items: () => [PuppetItem(rig, catcherGear: gear)], camera: () => cam, ball: () => null, repaint: ValueNotifier(0));
        final rec = ui.PictureRecorder();
        final cv = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
        cv.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF4E9B47));
        // アプリと同じく左右を反転して見せる
        cv.translate(w, 0);
        cv.scale(-1, 1);
        painter.paint(cv, const Size(w, h));
        final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/${name}_$vn.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      }
    }
  });
}
