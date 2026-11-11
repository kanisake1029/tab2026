import '../models/player.dart';
import 'package:flutter/material.dart';
import '../engine/career_path.dart';
import '../engine/foreign_engine.dart';
import '../engine/draft_engine.dart';
import '../models/prospect.dart';
import '../utils/app_theme.dart';
import '../utils/grade_utils.dart';
import 'dart:math';
import '../engine/coach_engine.dart';
import '../engine/growth_curve.dart';
import '../engine/growth_engine.dart';
import '../ai/ai_text.dart';
import '../ai/ai_writer.dart';

const _sub = Color(0xFF64748B);

/// 候補の詳しい見立てで使うスカウト眼力（ドラフト・外国人の画面を開いたときに入れる）
int scoutEyeForDetail = 60;

/// スカウトの見立て：選手タイプ（眼力が低いと見誤る）・成長フェーズ・全盛期の年齢（眼力が低いほど幅が広い）。選手ごとに毎回同じ
(String, String, String) scoutCurveView(Player pl, int eye) {
  final r = Random(pl.id.hashCode ^ 0x51c0 ^ eye);
  final miss = (100 - eye.clamp(1, 100)) / 100.0;
  var type = CoachEngine.playerType(pl);
  if (r.nextDouble() < miss * 0.6) {
    final pool = pl.isPitcher ? CoachEngine.pitcherTypes : CoachEngine.hitterTypes;
    type = pool[r.nextInt(pool.length)];
  }
  final (a, b) = GrowthCurve.primeRange(pl);
  final err = (miss * 5).round();
  final lo = a - r.nextInt(err + 1), hi = b + r.nextInt(err + 1);
  final shift = err == 0 ? 0 : r.nextInt(err * 2 + 1) - err;
  final phase = GrowthEngine.phaseOf(pl).label;
  return (type, phase, '${lo + shift}〜${hi + shift}歳ごろ');
}
const _line = Color(0xFFE2E8F0);

/// 「C〜B」のような幅の表示
Widget gradeRange(int lo, int hi, {double size = 13}) {
  final a = GradeUtils.getGrade(lo), b = GradeUtils.getGrade(hi);
  return Text.rich(TextSpan(children: [
    TextSpan(text: a, style: TextStyle(fontWeight: FontWeight.w900, fontSize: size, color: AppTheme.getGradeColor(a))),
    if (a != b) TextSpan(text: '〜', style: TextStyle(fontSize: size - 2, color: _sub)),
    if (a != b) TextSpan(text: b, style: TextStyle(fontWeight: FontWeight.w900, fontSize: size, color: AppTheme.getGradeColor(b))),
  ]));
}

/// 才能・向上心の見立て（幅をランクで。まだ調べていなければ「未調査」）
Widget traitText(Prospect p, {required bool talent, double size = 13}) {
  final lo = talent ? p.talentLo : p.ambitionLo, hi = talent ? p.talentHi : p.ambitionHi;
  if (lo == null || hi == null) return Text(p.reports == 0 ? '未調査' : '？', style: TextStyle(fontSize: size - 2, color: _sub, fontWeight: FontWeight.w700));
  return gradeRange(lo, hi, size: size);
}

/// 候補の並び替えの基準（自球団スカウトの見立て：今の力と才能・向上心）
double prospectSortKey(Prospect p) {
  final (lo, hi) = DraftEngine.curRange(p);
  final cur = (lo + hi) / 2;
  if (p.reports == 0 || p.talentLo == null) return cur * 0.5;
  final t = (p.talentLo! + p.talentHi!) / 2, a = (p.ambitionLo! + p.ambitionHi!) / 2;
  final rate = Player.rateOf(t, a);
  final years = (27 - p.player.age).clamp(0, 9);
  return cur * 0.45 + (cur + rate * years * 2.6) * 0.55;
}

/// ドラフト候補の1行
/// ドラフト候補の区分（守備位置9つ＋二刀流）
const draftPositions = ['投手', '捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手', '二刀流'];
const draftCategories = [('高校', '高卒'), ('大学', '大卒'), ('社会人', '社会人'), ('独立', '独立リーグ')];

String draftPosOf(Prospect p) => p.player.twoWay ? '二刀流' : (p.player.isPitcher ? '投手' : p.player.mainPosition);

/// 経歴の区分（高卒・大卒・社会人・独立）を選ぶ。画面の幅に4つ並べる（横にすべらせない）
Widget draftCategoryBar(List<Prospect> all, String selected, ValueChanged<String> onSelect) {
  int count(String c) => all.where((p) => p.category == c).length;
  return Row(children: [
    for (final (cat, label) in draftCategories)
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(cat),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: selected == cat ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected == cat ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1)),
              ),
              child: Column(children: [
                Text(label == '独立リーグ' ? '独立' : label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: selected == cat ? Colors.white : const Color(0xFF0F172A))),
                Text('${count(cat)}人', style: TextStyle(fontSize: 10.5, color: selected == cat ? Colors.white70 : const Color(0xFF64748B))),
              ]),
            ),
          ),
        ),
      ),
  ]);
}

/// 区分の中を守備位置ごとに分けて並べる（見出しつき）
List<Widget> draftPosSections(List<Prospect> list, Widget Function(Prospect) row) => [
      for (final pos in draftPositions)
        if (list.any((p) => draftPosOf(p) == pos)) ...[
          Container(
            width: double.infinity,
            color: const Color(0xFFF1F5F9),
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
            child: Text('${pos == '二刀流' ? '★' : ''}$pos（${list.where((p) => draftPosOf(p) == pos).length}人）', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
          ),
          for (final p in list.where((p) => draftPosOf(p) == pos)) row(p),
        ],
      if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('この区分の候補はいません', style: TextStyle(color: Color(0xFF64748B)))),
    ];

/// 区分を選ぶチップ（人数つき）
Widget draftPositionChips(List<Prospect> all, String selected, ValueChanged<String> onSelect) {
  final counts = <String, int>{};
  for (final p in all) {
    counts[draftPosOf(p)] = (counts[draftPosOf(p)] ?? 0) + 1;
  }
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      for (final pos in draftPositions)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ChoiceChip(
            label: Text('${pos == '二刀流' ? '★' : ''}$pos ${counts[pos] ?? 0}', style: const TextStyle(fontSize: 12)),
            selected: selected == pos,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onSelect(pos),
          ),
        ),
    ]),
  );
}

/// 区分の中を高卒→大卒→社会人→独立に分けて並べる（見出しつき）
List<Widget> draftSections(List<Prospect> list, Widget Function(Prospect) row) => [
      for (final (cat, label) in draftCategories)
        if (list.any((p) => p.category == cat)) ...[
          Container(
            width: double.infinity,
            color: const Color(0xFFF1F5F9),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Text('$label（${list.where((p) => p.category == cat).length}人）', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
          ),
          for (final p in list.where((p) => p.category == cat)) row(p),
        ],
      if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('この区分の候補はいません', style: TextStyle(color: Color(0xFF64748B)))),
    ];

class ProspectRow extends StatelessWidget {
  final Prospect p;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onWatch;
  final Widget? trailing;
  final String? forecast; // スカウトの指名予想
  final Widget? traits;   // 才能・向上心の欄の代わりに出すもの（外国人の環境適応力など）
  final VoidCallback? onLongPress;
  const ProspectRow({super.key, required this.p, this.selected = false, this.onTap, this.onWatch, this.trailing, this.forecast, this.traits, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final pl = p.player;
    final (lo, hi) = DraftEngine.curRange(p);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress ?? () => showProspectDetail(context, p),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFEF3C7) : Colors.white,
          border: Border(bottom: const BorderSide(color: _line), left: BorderSide(color: selected ? const Color(0xFFF59E0B) : Colors.transparent, width: 3)),
        ),
        child: Row(children: [
          if (onWatch != null)
            InkWell(
              onTap: onWatch,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(p.watched ? Icons.star : Icons.star_border, size: 20, color: p.watched ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1)),
              ),
            ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: pl.listName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                TextSpan(text: '　${pl.twoWay ? '二刀流（${pl.mainPosition}・投手）' : pl.mainPosition}　${pl.age}歳${p.ikuseiTier ? '　育成候補' : ''}', style: const TextStyle(fontSize: 11.5, color: _sub)),
              ]), overflow: TextOverflow.ellipsis),
              Text('${p.category}・${p.school}${p.comment.isNotEmpty ? '　${p.comment}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _sub)),
              if (p.wishText.isNotEmpty) Text('${p.wishText}${p.orient.isNotEmpty ? '（${p.orient}）' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Color(0xFF0369A1), fontWeight: FontWeight.w700)),
              if (forecast != null && forecast!.isNotEmpty)
                Text('予想：$forecast', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Color(0xFFB45309), fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const Text('今の力', style: TextStyle(fontSize: 9.5, color: _sub)),
            p.reports == 0 ? const Text('？', style: TextStyle(color: _sub, fontWeight: FontWeight.w700)) : gradeRange(lo, hi),
          ]),
          const SizedBox(width: 10),
          if (traits != null) traits!,
          if (traits == null) ...[
            SizedBox(width: 44, child: Column(children: [const Text('才能', style: TextStyle(fontSize: 9.5, color: _sub)), traitText(p, talent: true, size: 12)])),
            SizedBox(width: 44, child: Column(children: [const Text('向上心', style: TextStyle(fontSize: 9.5, color: _sub)), traitText(p, talent: false, size: 12)])),
          ],
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ]),
      ),
    );
  }
}

/// 候補の詳しい見立て（能力はすべて ±5 の幅）
///  adapt を渡すと（外国人の支配下）才能・向上心の代わりに環境適応力の見立てを出す
/// 憧れの選手の名前を引く（志望届に出す。画面を開く側が設定する）
String? Function(String id) prospectPlayerName = (_) => null;

/// ドラフト候補の詳細：「プロ野球志望届」の書類の形。本人の欄・希望球団・スカウトの調査書（眼力で幅がある見立て）・アマ時代の成績。
///  外国人の候補（adapt あり）は「調査書」だけ
Future<void> showProspectDetail(BuildContext context, Prospect p, {(int, int)? adapt, String memoTitle = 'スカウトメモ', String? note, int? eye}) {
  final (sType, sPhase, sPrime) = scoutCurveView(p.player, eye ?? scoutEyeForDetail);
  final pl = p.player;
  fixBirthDate(pl, p.year);
  final known = p.reports > 0;
  int b(String k) => p.curBias + (k.hashCode % 5 - 2); // 能力ごとの見立てのずれ
  final items = pl.isPitcher
      ? <(String, int)>[('球威', pl.pitchPower), ('制球', pl.control), ('スタミナ', pl.stamina), ('ピンチ', pl.clutchPitching)]
      : <(String, int)>[('ミート', pl.contact), ('パワー', pl.power), ('走力', pl.run), ('肩力', pl.arm), ('守備', pl.catchSkill), ('選球眼', pl.eye)];
  String rg(int lo, int hi) {
    final a = GradeUtils.getGrade(lo), c = GradeUtils.getGrade(hi);
    return a == c ? a : '$a〜$c';
  }

  final foreign = pl.origin.isNotEmpty || adapt != null;
  final hand = '${pl.throws == 'L' ? '左' : '右'}投${pl.bats == 'L' ? '左' : (pl.bats == 'S' ? '両' : '右')}打';
  final pos = pl.twoWay ? '二刀流（${pl.mainPosition}・投手）' : (pl.isPitcher ? '投手' : pl.mainPosition);
  // AI 寸評に渡す事実（画面に出ている見立てだけ。本当の値は渡さない）
  final facts = StringBuffer()
    ..writeln('候補：${pl.listName}（$pos・${pl.age}歳・$hand・${pl.height}cm・${foreign ? '${pl.origin}出身${pl.ikusei ? '・育成候補' : '・支配下候補'}' : '${p.category}・${p.school}${p.ikuseiTier ? '・育成候補' : ''}'}）')
    ..writeln('スカウトの調査回数：${p.reports}回')
    ..writeln('今の能力の見立て（幅あり）：${pl.isPitcher ? '球速${pl.velocity + p.curBias ~/ 2 - 2}〜${pl.velocity + p.curBias ~/ 2 + 2}km ' : ''}${items.map((it) => '${it.$1}${rg((it.$2 + b(it.$1) - 5).clamp(1, 99), (it.$2 + b(it.$1) + 5).clamp(1, 99))}').join(' ')}');
  if (adapt != null) facts.writeln('環境適応力の見立て：${rg(adapt.$1, adapt.$2)}（${adapt.$1}〜${adapt.$2}）');
  if (adapt == null && p.talentLo != null) facts.writeln('才能の見立て：${rg(p.talentLo!, p.talentHi!)}　向上心の見立て：${rg(p.ambitionLo!, p.ambitionHi!)}');
  if (p.memo.isNotEmpty) facts.writeln('$memoTitle：${p.memo.join(' / ')}');
  if (p.comment.isNotEmpty) facts.writeln('スカウトの一言：${p.comment}');
  final aiItem = AiItem('prospect:${pl.id}:${p.reports}:${adapt?.$1 ?? p.talentLo ?? 0}', foreign ? 'foreign' : 'draft', facts.toString());

  const paper = Color(0xFFFFFDF7), rule = Color(0xFF57534E);
  Widget cell(String label, Widget v, {double w = 74}) => Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFD6D3D1)))),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              color: const Color(0xFFF5F5F4),
              alignment: Alignment.centerLeft,
              child: Text(label, style: const TextStyle(fontSize: 11.5, color: _sub, fontWeight: FontWeight.w700)),
            ),
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Align(alignment: Alignment.centerLeft, child: v))),
          ]),
        ),
      );
  Widget txt(String s, {bool bold = false}) => Text(s, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, height: 1.4));
  Widget section(String title, List<Widget> rows) => Container(
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(border: Border.all(color: rule, width: 1.2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: rule,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ),
          ...rows,
        ]),
      );

  final idols = [for (final id in p.idols) prospectPlayerName(id)].whereType<String>().toList();
  final wishText = !p.wishFiled
      ? '（志望届はまだ出ていません。9月1日に出します）'
      : (p.wishes.isEmpty ? '希望なし（プロに入れればよい）' : [for (var i = 0; i < p.wishNames.length; i++) '${i + 1}希望 ${p.wishNames[i]}'].join('　'));

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: paper,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.95,
      builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        // 表題
        Center(child: Text(foreign ? '外国人選手　調査書' : 'プロ野球志望届', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 6))),
        Center(child: Text(foreign ? '' : '${p.year}年度　受付番号 ${(pl.id.hashCode & 0xFFFF).toString().padLeft(5, '0')}', style: const TextStyle(fontSize: 11, color: _sub))),
        const SizedBox(height: 4),
        // 本人の欄
        section('本人', [
          cell('氏名', Text(pl.listName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          cell('生年月日', txt('${pl.birthDate.replaceAll('-', '/')}（${pl.age}歳）')),
          cell(foreign ? '出身国' : '出身地', txt(foreign ? pl.origin : (pl.birthplace.isEmpty ? '−' : pl.birthplace))),
          cell('所属', txt(foreign ? (pl.draftInfo.isEmpty ? '−' : pl.draftInfo) : '${p.category}・${p.school}', bold: true)),
          if (!foreign) cell('経歴', txt(CareerPath.of(pl).join(' → '))),
          cell('守備位置', txt('$pos　$hand')),
          cell('体格', txt('${pl.height}cm・${pl.weight}kg')),
          if (p.ikuseiTier) cell('区分', txt('育成候補')),
        ]),
        // 希望球団
        if (!foreign)
          section('希望球団', [
            cell('希望', txt(wishText, bold: true)),
            if (p.orient.isNotEmpty) cell('志向', txt(p.orient)),
            if (idols.isNotEmpty) cell('憧れの選手', txt(idols.join('・'))),
            cell('国内FA', txt(!p.wishFiled ? '−' : (p.wishes.isEmpty ? 'どこに入っても8年' : '1希望は8年・2〜3希望は7年・希望外は6年'))),
          ]),
        // スカウトの調査書
        section('スカウトの調査書', [
          cell('調査', txt(known ? '${p.reports}回${p.comment.isNotEmpty ? '　「${p.comment}」' : ''}' : 'まだ調査していません（★注目にすると優先して調べます）')),
          if (known) ...[
            cell(
              '今の力',
              Wrap(spacing: 14, runSpacing: 6, children: [
                if (pl.isPitcher || pl.twoWay)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('球速', style: TextStyle(fontSize: 10.5, color: _sub)),
                    Text('${pl.velocity + p.curBias ~/ 2 - 2}〜${pl.velocity + p.curBias ~/ 2 + 2}km', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                for (final it in items)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.$1, style: const TextStyle(fontSize: 10.5, color: _sub)),
                    gradeRange((it.$2 + b(it.$1) - 5).clamp(1, 99), (it.$2 + b(it.$1) + 5).clamp(1, 99), size: 15),
                  ]),
              ]),
            ),
            if (adapt != null)
              cell('環境適応力', Row(mainAxisSize: MainAxisSize.min, children: [gradeRange(adapt.$1, adapt.$2, size: 15), Text('（${adapt.$1}〜${adapt.$2}）入団時 ×${ForeignEngine.adaptMult(adapt.$1).toStringAsFixed(2)}〜×${ForeignEngine.adaptMult(adapt.$2).toStringAsFixed(2)}', style: const TextStyle(fontSize: 11.5, color: _sub))])),
            if (adapt == null) ...[
              cell('才能', Row(mainAxisSize: MainAxisSize.min, children: [traitText(p, talent: true, size: 15), Text(p.talentLo == null ? '' : '（${p.talentLo}〜${p.talentHi}）', style: const TextStyle(fontSize: 11.5, color: _sub))])),
              cell('向上心', Row(mainAxisSize: MainAxisSize.min, children: [traitText(p, talent: false, size: 15), Text(p.ambitionLo == null ? '' : '（${p.ambitionLo}〜${p.ambitionHi}）', style: const TextStyle(fontSize: 11.5, color: _sub))])),
            ],
            cell('見立て', txt('タイプ $sType　成長 $sPhase　全盛期 $sPrime')),
          ],
        ]),
        // 寸評
        if (known)
          AiText(
            item: aiItem,
            fallback: '',
            builder: (t) => t.isEmpty ? const SizedBox.shrink() : section('寸評', [Padding(padding: const EdgeInsets.all(8), child: Text(t, style: const TextStyle(fontSize: 12.5, height: 1.6)))]),
          ),
        // アマ時代の成績
        section(foreign ? '海外での成績' : 'アマ時代の成績', [
          if (p.memo.isEmpty) Padding(padding: const EdgeInsets.all(8), child: txt('記録はありません')),
          for (final m in p.memo)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE7E5E4)))),
              child: Text(m, style: const TextStyle(fontSize: 12.5, height: 1.45, fontFeatures: [FontFeature.tabularFigures()])),
            ),
        ]),
        const SizedBox(height: 8),
        Text(note ?? '今の能力は実際の値の±5の幅で分かります。才能・向上心は、スカウトの眼力が高いほど狭い幅で見抜けます（眼力D50で±20、S100で±5）。成長の速さは 才能×向上心 で決まります。', style: const TextStyle(fontSize: 11, color: _sub, height: 1.5)),
      ]),
    ),
  );
}
