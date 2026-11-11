import 'package:flutter/material.dart';
import '../engine/body_gen.dart';
import '../models/pitching_form.dart';
import '../models/player.dart';
import '../models/equipment.dart';

const _sub = Color(0xFF78716C);

/// 体格（身長・体重・腕の長さ・頭囲・胸囲・腹囲・臀囲）と投球フォームの編集。保存で true を返す
///  自動の値と同じものは保存しない（0＝自動のまま）。「自動に戻す」で id と能力から決まる値に戻る
class BodyFormEditor extends StatefulWidget {
  final Player player;
  /// 体格を変えられるか（初期選手編集だけ。選手詳細のタブでは見るだけ）
  final bool bodyEditable;
  /// 選手詳細のタブに埋め込む（変えるたびにすぐ保存して onChanged）
  final bool embedded;
  final VoidCallback? onChanged;
  const BodyFormEditor({super.key, required this.player, this.bodyEditable = true, this.embedded = false, this.onChanged});
  @override
  State<BodyFormEditor> createState() => _BodyFormEditorState();
}

class _BodyFormEditorState extends State<BodyFormEditor> {
  Player get p => widget.player;
  late int height = p.height, weight = p.weight, arm = p.armLength, head = p.headGirth, chest = p.chestGirth, waist = p.waistGirth, hip = p.hipGirth;
  late int axis = p.spinAxis;
  late PitchingForm form = p.form.copy();
  late Bat bat = Bat.fromJson(p.bat.toJson());
  late Glove glove = Glove.fromJson(p.glove.toJson());

  void _resetBody() => _set(() {
        weight = BodyGen.weight(p.id, height, power: p.power, pitchPower: p.pitchPower, pitcher: p.isPitcher);
        arm = BodyGen.armLength(p.id, height, arm: p.arm, velocity: p.velocity);
        final bmi = BodyGen.bmi(p.id, power: p.power, pitchPower: p.pitchPower, pitcher: p.isPitcher);
        head = BodyGen.headGirth(p.id, height);
        chest = BodyGen.chestGirth(p.id, height, bmi);
        waist = BodyGen.waistGirth(p.id, height, bmi);
        hip = BodyGen.hipGirth(p.id, height, bmi);
      });

  void _resetForm() => _set(() {
        axis = BodyGen.spinAxis(p.id);
        form = BodyGen.form(p.id, velocity: p.velocity, control: p.control, stamina: p.stamina);
      });

  void _set(VoidCallback fn) {
    setState(fn);
    if (widget.embedded) {
      _commit();
      widget.onChanged?.call();
    }
  }

  void _save() {
    _commit();
    Navigator.of(context).pop(true);
  }

  void _commit() {
    if (widget.bodyEditable) _commitBody();
    _commitFormGear();
  }

  void _commitBody() {
    p.height = height;
    // 自動と同じ値は持たない（体格は身長から計算し直すので、身長を変えたら比べ直す）
    final bmi = BodyGen.bmi(p.id, power: p.power, pitchPower: p.pitchPower, pitcher: p.isPitcher);
    int keep(int v, int auto) => v == auto ? 0 : v;
    p.bodyWeight = keep(weight, BodyGen.weight(p.id, height, power: p.power, pitchPower: p.pitchPower, pitcher: p.isPitcher));
    p.bodyArm = keep(arm, BodyGen.armLength(p.id, height, arm: p.arm, velocity: p.velocity));
    p.bodyHead = keep(head, BodyGen.headGirth(p.id, height));
    p.bodyChest = keep(chest, BodyGen.chestGirth(p.id, height, bmi));
    p.bodyWaist = keep(waist, BodyGen.waistGirth(p.id, height, bmi));
    p.bodyHip = keep(hip, BodyGen.hipGirth(p.id, height, bmi));
  }

  void _commitFormGear() {
    if (p.canPitch) {
      p.spinAxisSet = axis == BodyGen.spinAxis(p.id) ? -1 : axis;
      final auto = BodyGen.form(p.id, velocity: p.velocity, control: p.control, stamina: p.stamina);
      p.formSet = form.toJson().toString() == auto.toJson().toString() ? null : form;
    }
    // 用具：自動と同じなら持たない
    final autoBat = Bat.auto(p.id, power: p.power, contact: (p.contactLeft + p.contactRight) ~/ 2, height: p.height);
    p.batSet = bat.toJson().toString() == autoBat.toJson().toString() ? null : bat;
    final autoGlove = Glove.auto(p.id, p.isPitcher ? '投手' : p.mainPosition);
    p.gloveSet = glove.toJson().toString() == autoGlove.toJson().toString() ? null : glove;
  }

  /// 数値の1行：項目・値（−＋）・スライダー
  Widget _num(String label, int v, String unit, int lo, int hi, ValueChanged<int> set) => SizedBox(
        height: 34,
        child: Row(children: [
          SizedBox(width: 78, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF334155)))),
          InkWell(onTap: v > lo ? () => _set(() => set(v - 1)) : null, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.remove, size: 16, color: Color(0xFF64748B)))),
          SizedBox(width: 58, child: Text('$v$unit', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
          InkWell(onTap: v < hi ? () => _set(() => set(v + 1)) : null, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.add, size: 16, color: Color(0xFF64748B)))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7), overlayShape: const RoundSliderOverlayShape(overlayRadius: 12)),
              child: Slider(value: v.toDouble().clamp(lo.toDouble(), hi.toDouble()), min: lo.toDouble(), max: hi.toDouble(), divisions: hi - lo, onChanged: (x) => _set(() => set(x.round()))),
            ),
          ),
        ]),
      );

  /// 小見出し（左に線）
  Widget _sub2(String s) => Container(
        margin: const EdgeInsets.only(top: 10, bottom: 2),
        padding: const EdgeInsets.only(left: 6),
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFF0F172A), width: 3))),
        child: Text(s, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
      );
  /// 説明（小さく灰色の枠）
  Widget _note(String s) => Container(
        margin: const EdgeInsets.only(top: 2, bottom: 4),
        padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(4)),
        child: Text(s, style: const TextStyle(fontSize: 10.5, color: _sub, height: 1.4)),
      );

  /// 大見出し（帯）
  Widget _h(String s, {VoidCallback? reset}) => Container(
        margin: const EdgeInsets.only(top: 14, bottom: 4),
        padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
        decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          Text(s, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Colors.white)),
          const Spacer(),
          if (reset != null)
            TextButton.icon(
              onPressed: reset,
              style: TextButton.styleFrom(foregroundColor: Colors.white70, visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('自動に戻す', style: TextStyle(fontSize: 11.5)),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final bmi = weight / ((height / 100) * (height / 100));
    final children = <Widget>[
        _h('用具', reset: () => _set(() {
              bat = Bat.auto(p.id, power: p.power, contact: (p.contactLeft + p.contactRight) ~/ 2, height: p.height);
              glove = Glove.auto(p.id, p.isPitcher ? '投手' : p.mainPosition);
            })),
        _sub2('バット'),
        _num('長さ', (bat.length * 10).round(), 'mm', 820, 880, (v) => bat.length = v / 10),
        _num('重さ', bat.weight.round(), 'g', 820, 980, (v) => bat.weight = v.toDouble()),
        Wrap(spacing: 6, children: [
          for (final b in Bat.balances) ChoiceChip(label: Text(b), selected: bat.balance == b, onSelected: (_) => _set(() => bat.balance = b)),
        ]),
        _num('短く持つ', bat.choke.round(), 'cm', 0, 8, (v) => bat.choke = v.toDouble()),
        Wrap(spacing: 6, runSpacing: 4, children: [
          const Text('バットの塗り：'),
          for (final f in Bat.finishes.keys) ChoiceChip(label: Text(f), selected: bat.finish == f, onSelected: (_) => _set(() => bat.finish = f)),
        ]),
        Wrap(spacing: 6, runSpacing: 4, children: [
          const Text('バットのメーカー：'),
          for (final mk in makers) ChoiceChip(label: Text(mk), selected: bat.maker == mk, onSelected: (_) => _set(() => bat.maker = mk)),
        ]),
        Text('振りやすさ ${(bat.swingSpeedRatio * 100).round()}%（標準 85cm・900g＝100）　当たり負けしにくさ（芯の有効質量）${(bat.effectiveMass * 1000).round()}g',
            style: const TextStyle(fontSize: 11.5, color: _sub)),
        _sub2('グラブ'),
        _num('大きさ', (glove.length * 10).round(), 'mm', 280, 330, (v) => glove.length = v / 10),
        Wrap(spacing: 6, children: [
          for (final pk in Glove.pockets) ChoiceChip(label: Text('ポケット$pk'), selected: glove.pocket == pk, onSelected: (_) => _set(() => glove.pocket = pk)),
        ]),
        Wrap(spacing: 6, runSpacing: 4, children: [
          const Text('グラブの色：'),
          for (final c in Glove.colors.keys)
            ChoiceChip(avatar: CircleAvatar(backgroundColor: Color(Glove.colors[c]!), radius: 7), label: Text(c), selected: glove.color == c, onSelected: (_) => _set(() => glove.color = c)),
        ]),
        Wrap(spacing: 6, runSpacing: 4, children: [
          const Text('ひもの色：'),
          for (final c in Glove.colors.keys)
            ChoiceChip(avatar: CircleAvatar(backgroundColor: Color(Glove.colors[c]!), radius: 7), label: Text(c), selected: glove.lace == c, onSelected: (_) => _set(() => glove.lace = c)),
        ]),
        Wrap(spacing: 6, runSpacing: 4, children: [
          const Text('ウェブ：'),
          for (final w in Glove.webs) ChoiceChip(label: Text(w), selected: glove.web == w, onSelected: (_) => _set(() => glove.web = w)),
        ]),
        Wrap(spacing: 6, runSpacing: 4, children: [
          const Text('グラブのメーカー：'),
          for (final mk in makers) ChoiceChip(label: Text(mk), selected: glove.maker == mk, onSelected: (_) => _set(() => glove.maker = mk)),
        ]),
        Text('捕れる範囲 ${glove.reachBonus >= 0 ? '+' : ''}${(glove.reachBonus * 100).toStringAsFixed(1)}cm　握り替え +${glove.transferDelay.toStringAsFixed(2)}秒（規則：バット 106.7cm 以下、グラブ 33cm 以下）',
            style: const TextStyle(fontSize: 11.5, color: _sub)),
        _h('体格', reset: widget.bodyEditable ? _resetBody : null),
        if (!widget.bodyEditable) ...[
          Text('身長 ${height}cm・体重 ${weight}kg・腕の長さ ${arm}cm　頭囲$head・胸囲$chest・腹囲$waist・臀囲${hip}cm', style: const TextStyle(fontSize: 13)),
          _note('体格は変えられません（変えるのは初期選手編集だけ）'),
        ] else ...[
        _num('身長', height, 'cm', 155, 210, (v) => height = v),
        _num('体重', weight, 'kg', 55, 140, (v) => weight = v),
        _num('腕の長さ', arm, 'cm', 60, 100, (v) => arm = v),
        Text('BMI ${bmi.toStringAsFixed(1)}　腕の長さ÷身長 ${(arm / height).toStringAsFixed(3)}（肩先〜中指先。ふつう 0.43〜0.47）', style: const TextStyle(fontSize: 11.5, color: _sub)),
        _num('頭囲', head, 'cm', 50, 64, (v) => head = v),
        _num('胸囲', chest, 'cm', 80, 135, (v) => chest = v),
        _num('腹囲', waist, 'cm', 65, 130, (v) => waist = v),
        _num('臀囲', hip, 'cm', 80, 130, (v) => hip = v),
        ],
        if (p.canPitch) ...[
          _h('投球フォーム', reset: _resetForm),
          Wrap(spacing: 6, children: [
            for (final s in PitchingForm.armSlots)
              ChoiceChip(label: Text(s), selected: PitchingForm.armSlotOf(axis) == s, onSelected: (_) => _set(() => axis = PitchingForm.spinAxisOf(s))),
          ]),
          _num('腕の角度', axis, '°', 0, 170, (v) => axis = v),
          Text('0°＝真上から（オーバー）、90°＝真横（サイド）、135°前後＝下から（アンダー）。いまは${PitchingForm.armSlotOf(axis)}', style: const TextStyle(fontSize: 11.5, color: _sub)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final w in PitchingForm.windups) ChoiceChip(label: Text(w), selected: form.windup == w, onSelected: (_) => _set(() => form.windup = w)),
          ]),
          const Text('走者がいるときは、どの投げ方でもセットポジション（クイック）で投げます', style: TextStyle(fontSize: 11.5, color: _sub)),
          _sub2('構え'),
          _num('プレート位置', form.rubberPos, 'cm', -30, 30, (v) => form.rubberPos = v),
          Wrap(spacing: 6, children: [
            for (var i = 0; i < 3; i++) ChoiceChip(label: Text(PitchingForm.handHolds[i]), selected: form.handHold == i, onSelected: (_) => _set(() => form.handHold = i)),
          ]),
          _note('プレート位置：0＝中央、＋＝三塁側、−＝一塁側（右投手の基準。左投手は逆側）　構える高さ：ボールとグラブを置く位置'),
          _sub2('①足上げ（${form.legKickType}）'),
          _num('足の高さ', form.legLiftHeight, '', 0, 100, (v) => form.legLiftHeight = v),
          _num('足上げ', form.legLiftMs, 'ms', 250, 900, (v) => form.legLiftMs = v),
          _num('ため', form.holdMs, 'ms', 0, 600, (v) => form.holdMs = v),
          _num('ひねり', form.counterRot, '°', 0, 30, (v) => form.counterRot = v),
          _note('足の高さ：0＝すり足（股関節30°）50＝太ももが水平 100＝胸まで（120°）　ため：一番高い所で止める時間　ひねり：骨盤を背中側へ回す量（カウンターローテーション）'),
          _sub2('②並進（${form.takebackType}・${form.driveType}・${form.stepType}）'),
          _num('テイクバック', form.takeback, '', 0, 100, (v) => form.takeback = v),
          _num('軸足の沈み', form.kneeDrop, '°', 15, 65, (v) => form.kneeDrop = v),
          _num('踏み出し', form.strideRatio, '%', 70, 98, (v) => form.strideRatio = v),
          _num('踏み出す向き', form.stepOffset, 'cm', -20, 25, (v) => form.stepOffset = v),
          _note('テイクバック：0＝ショートアーム 100＝ロングアーム　軸足の沈み：膝の曲がり（20〜30°＝トール＆フォール、45〜60°＝ドロップ＆ドライブ）　踏み出し：身長に対する幅（80〜90%がふつう）　向き：＋＝インステップ −＝アウトステップ'),
          _sub2('③レイトコッキング'),
          _num('捻転差', form.hipShoulderSep, '°', 15, 70, (v) => form.hipShoulderSep = v),
          _num('肩の外旋', form.merDeg, '°', 150, 190, (v) => form.merDeg = v),
          _note('捻転差：踏み出し足の着地で、腰に対して肩が遅れて残る角度（40〜60°）　肩の外旋：腕がしなって一番後ろへ倒れた角度（160〜185°）'),
          _sub2('④加速・リリース'),
          _num('前傾', form.trunkFlex, '°', 25, 50, (v) => form.trunkFlex = v),
          _num('前への伸び', form.extension, '', 0, 100, (v) => form.extension = v),
          _num('テンポ', form.tempo, '', 0, 100, (v) => form.tempo = v),
          _note('前傾：リリースでの体幹の前への倒れ（30〜45°）　前への伸び：0＝プレートから約180cm 100＝約210cmで放す　'
              '体の横の傾きは腕の角度から決まります（いまは約${PitchingForm.lateralTiltOf(axis).round()}°）'),
        ],
        const SizedBox(height: 12),
        const Text('体格とフォームは、リリースの位置・球の速さと回転の計算（物理エンジン）に使います',
            style: TextStyle(fontSize: 11.5, color: _sub, height: 1.5)),
    ];
    if (widget.embedded) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return Scaffold(
      appBar: AppBar(title: Text('${p.registeredName}　${widget.bodyEditable ? '体格・' : ''}フォーム・道具'), actions: [TextButton(onPressed: _save, child: const Text('保存'))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 30), children: children),
    );
  }
}
