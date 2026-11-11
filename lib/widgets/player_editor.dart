import 'dart:math';
import '../engine/growth_curve.dart';
import '../engine/pitch_catalog.dart';
import '../engine/coach_engine.dart';
import '../engine/career_engine.dart';
import '../utils/name_data.dart';
import 'package:flutter/material.dart';
import '../models/player.dart';
import '../screens/order_tabs/order_shared.dart';
import '../utils/app_theme.dart';
import '../utils/grade_utils.dart';
import '../utils/salary_utils.dart';
import 'condition_face.dart';
import 'body_form_editor.dart';
import 'player_detail_dialog.dart' show PitchVectorPainter;

/// 初期選手編集（デザイン案B：レポート編集）
///  選手詳細Bと同じ見た目のまま、各項目をその場で書き換える。
///  数値は「評価の文字＋入力欄」。総合評価は入力するたびに再計算する。
class PlayerEditor extends StatefulWidget {
  final Player player;
  final dynamic appState;
  final VoidCallback onChanged;
  const PlayerEditor({super.key, required this.player, required this.appState, required this.onChanged});

  @override
  State<PlayerEditor> createState() => _PlayerEditorState();
}

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);
const _soft = Color(0xFFFAFAF9);

class _PlayerEditorState extends State<PlayerEditor> {
  Player get p => widget.player;

  // 連動して変わる入力欄を作り直すための番号（入力中の欄は作り直さない）
  int _birthRev = 0, _proRev = 0, _salaryRev = 0, _careerRev = 0;

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  // ───────── 背番号：入力を確定したときに、同じ番号の選手と入れ替える ─────────
  late final TextEditingController _uniCtl = TextEditingController(text: p.uniformText);

  void _commitUniform() {
    final v = parseUniform(_uniCtl.text);
    if (v == null || v == p.uniformNumber) {
      _uniCtl.text = p.uniformText;
      return;
    }
    final teams = (widget.appState?.teams as List?) ?? const [];
    final team = teams.where((t) => (t.players as List).contains(p)).firstOrNull;
    final Player? other = team == null ? null : (team.players as List<Player>).where((x) => !identical(x, p) && x.uniformNumber == v).firstOrNull;
    final old = p.uniformNumber, oldText = p.uniformText;
    _set(() {
      if (other != null) other.uniformNumber = old;
      p.uniformNumber = v;
    });
    _uniCtl.text = p.uniformText;
    if (other != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('#${p.uniformText}だった${other.listName}は、#$oldText（${p.listName}の前の番号）に変えました')));
    }
  }

  Widget _uniformBox() => Focus(
        onFocusChange: (has) {
          if (!has) _commitUniform();
        },
        child: TextField(
          controller: _uniCtl,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFD6D3D1))),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFD6D3D1))),
          ),
          onSubmitted: (_) => _commitUniform(),
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
        ),
      );

  @override
  void dispose() {
    _uniCtl.dispose();
    super.dispose();
  }

  /// 球種を選ぶメニュー（38種。系統ごと）
  Widget _pitchMenu({required Widget child, required ValueChanged<PitchSpec> onPicked}) => PopupMenuButton<String>(
        tooltip: '38種から選ぶ',
        onSelected: (name) => onPicked(PitchCatalog.of(name)!),
        itemBuilder: (_) => [
          for (final g in PitchCatalog.groups) ...[
            PopupMenuItem<String>(enabled: false, height: 28, child: Text(g, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _sub))),
            for (final s in PitchCatalog.all.where((s) => s.group == g))
              PopupMenuItem<String>(
                value: s.name,
                height: 34,
                enabled: !p.pitches.any((x) => x.name == s.name),
                child: Text('${s.name}　${s.memo}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ),
          ],
        ],
        child: child,
      );

  // ───────── 生年月日・プロ年数・年齢の連動（従来の編集画面と同じ規則） ─────────

  DateTime? _parseDate(String d) {
    try {
      return DateTime.parse(d.replaceAll('/', '-'));
    } catch (_) {
      return null;
    }
  }

  void _syncDates({bool fromBirthDate = false, bool fromProYears = false, bool fromDraft = false}) {
    final baseDate = DateTime(widget.appState.startYear, 1, 1);
    int baseAge = 19;
    if (p.draftType == 'B') baseAge = 23;
    if (p.draftType == 'C') baseAge = p.draftCustomAge;
    DateTime? bDate = _parseDate(p.birthDate);
    if (bDate == null) return;
    final before = baseDate.month < bDate.month || (baseDate.month == bDate.month && baseDate.day < bDate.day);
    String fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (fromBirthDate || fromDraft) {
      int age = baseDate.year - bDate.year;
      if (before) age--;
      p.age = age;
      int newProYear = p.age - baseAge + 1;
      if (newProYear < 1) {
        newProYear = 1;
        p.age = baseAge;
        bDate = DateTime(baseDate.year - p.age - (before ? 1 : 0), bDate.month, bDate.day);
        p.birthDate = fmt(bDate);
      }
      p.proYears = newProYear;
    } else if (fromProYears) {
      if (p.proYears < 1) p.proYears = 1;
      p.age = p.proYears + baseAge - 1;
      bDate = DateTime(baseDate.year - p.age - (before ? 1 : 0), bDate.month, bDate.day);
      p.birthDate = fmt(bDate);
    }
  }

  // ───────── 部品 ─────────

  Widget _grade(int v, {double size = 15}) {
    final g = GradeUtils.getGrade(v);
    return Text(g, style: TextStyle(fontWeight: FontWeight.w900, fontSize: size, color: AppTheme.getGradeColor(g)));
  }

  /// 数値の入力欄。選手が変わると作り直す（key に選手IDを含める）
  Widget _numBox(String key, int value, ValueChanged<int> onChanged, {double width = 58, int min = 1, int max = 100}) {
    return SizedBox(
      width: width,
      height: 30,
      child: TextFormField(
        key: ValueKey('${p.id}_$key'),
        initialValue: '$value',
        keyboardType: TextInputType.number,
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFD6D3D1))),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFD6D3D1))),
        ),
        onChanged: (s) {
          final v = int.tryParse(s);
          if (v != null) _set(() => onChanged(v.clamp(min, max)));
        },
      ),
    );
  }

  Widget _textBox(String key, String value, ValueChanged<String> onChanged, {TextStyle? style}) {
    return TextFormField(
      key: ValueKey('${p.id}_$key'),
      initialValue: value,
      style: style ?? const TextStyle(fontSize: 13.5),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFD6D3D1))),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFD6D3D1))),
      ),
      onChanged: (s) => _set(() => onChanged(s)),
    );
  }

  Widget _dropdown<T>(T value, List<(T, String)> items, ValueChanged<T> onChanged) {
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFD6D3D1)), borderRadius: BorderRadius.circular(4)),
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        style: const TextStyle(fontSize: 13.5, color: _ink),
        items: [for (final it in items) DropdownMenuItem(value: it.$1, child: Text(it.$2, overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) _set(() => onChanged(v));
        },
      ),
    );
  }

  Widget _field(String label, Widget child, {double width = 150}) => SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: _sub)),
          const SizedBox(height: 3),
          child,
        ]),
      );

  Widget _section(String title, List<Widget> rows, {Widget? trailing}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)), const Spacer(), if (trailing != null) trailing]),
          const SizedBox(height: 4),
          ...rows,
        ]),
      );

  /// 能力1行：項目名・評価・入力欄
  Widget _abilityRow(String label, int value, ValueChanged<int> onChanged, {String? note, String? key}) => Container(
        height: 38,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F4)))),
        child: Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: label, style: const TextStyle(fontSize: 13.5)),
              if (note != null) TextSpan(text: '  $note', style: const TextStyle(fontSize: 11, color: _sub)),
            ]), overflow: TextOverflow.ellipsis),
          ),
          SizedBox(width: 22, child: Center(child: _grade(value))),
          const SizedBox(width: 8),
          _numBox(key ?? label, value, onChanged),
        ]),
      );

  Widget _displayRow(String label, String grade, String value, {String? note}) => Container(
        height: 38,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F4)))),
        child: Row(children: [
          Expanded(child: Text.rich(TextSpan(children: [
            TextSpan(text: label, style: const TextStyle(fontSize: 13.5)),
            if (note != null) TextSpan(text: '  $note', style: const TextStyle(fontSize: 11, color: _sub)),
          ]))),
          SizedBox(width: 22, child: Center(child: Text(grade, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppTheme.getGradeColor(grade))))),
          const SizedBox(width: 8),
          SizedBox(width: 58, child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _sub))),
        ]),
      );

  // ───────── 画面 ─────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final sections = _abilitySections();
      final side = _sideColumn();
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(wide ? 26 : 14, 18, wide ? 26 : 14, 30),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(),
          const SizedBox(height: 12),
          _profile(),
          const SizedBox(height: 16),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _twoColumns(sections)),
              const SizedBox(width: 20),
              SizedBox(width: 280, child: side),
            ])
          else ...[
            for (final s in sections) Padding(padding: const EdgeInsets.only(bottom: 12), child: s),
            side,
          ],
          ...[
            const SizedBox(height: 16),
            _pitchSection(wide),
          ],
          const SizedBox(height: 16),
          _statsSection(),
          const SizedBox(height: 16),
          _careerSection(),
        ]),
      );
    });
  }

  Widget _twoColumns(List<Widget> items) {
    final left = <Widget>[], right = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(Padding(padding: const EdgeInsets.only(bottom: 14), child: items[i]));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
    ]);
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _ink, width: 2))),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 10,
        runSpacing: 8,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('EDIT MODE　編集中', style: TextStyle(fontSize: 12, letterSpacing: 3, color: _sub)),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('#', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              SizedBox(width: 64, child: _uniformBox()),
              const SizedBox(width: 8),
              SizedBox(width: 120, child: _textBox('last', p.lastName, (s) => p.lastName = s, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
              const SizedBox(width: 6),
              SizedBox(width: 120, child: _textBox('first', p.firstName, (s) => p.firstName = s, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            ]),
          ]),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${p.isPitcher ? '投手' : p.mainPosition}　登録名「${p.registeredName}」', style: const TextStyle(fontSize: 14, color: Color(0xFF57534E))),
          ),
        ],
      ),
    );
  }

  Widget _profile() {
    final positions = p.isPitcher ? ['投手'] : ['捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手'];
    final mainPos = p.isPitcher ? '投手' : p.mainPosition;
    return Wrap(spacing: 10, runSpacing: 10, children: [
      _field('表示名パターン', _dropdown<String>(p.nameType, const [('A', 'A: 姓 名'), ('B', 'B: 姓名'), ('C', 'C: 姓+名の頭文字'), ('D', 'D: 名前のみ'), ('E', 'E: オリジナル（姓＋名、または1つの名前）'), ('F', 'F: 名・姓（外国人）')], (v) => p.nameType = v), width: 170),
      if (p.nameType == 'E') _field('オリジナルの姓（1つの名前ならここだけ。例：イチロー）', _textBox('custom', p.customName, (s) => p.customName = s.trim())),
      if (p.nameType == 'E') _field('オリジナルの名（空欄なら1つの名前）', _textBox('customFirst', p.customFirst, (s) => p.customFirst = s.trim())),
      _field('メインポジション', _dropdown<String>(positions.contains(mainPos) ? mainPos : positions.first, [for (final x in positions) (x, x)], (v) => p.mainPos = v), width: 130),
      _field('投 / 打', _dropdown<String>('${p.throws}/${p.bats}', const [('R/R', '右投右打'), ('R/L', '右投左打'), ('R/S', '右投両打'), ('L/L', '左投左打'), ('L/R', '左投右打'), ('L/S', '左投両打')], (v) {
        p.throws = v.split('/')[0];
        p.bats = v.split('/')[1];
      }), width: 120),
      _field('タイプ', _dropdown<String>(
        (p.isPitcher ? CoachEngine.pitcherTypes : CoachEngine.hitterTypes).contains(p.typeSet) ? p.typeSet : '',
        [('', '自動（${CoachEngine.autoType(p)}）'), for (final t in (p.isPitcher ? CoachEngine.pitcherTypes : CoachEngine.hitterTypes)) (t, t)],
        (v) => p.typeSet = v,
      ), width: 160),
      _field('国籍', _dropdown<String>(['日本', '海外'].contains(p.nationality) ? p.nationality : '日本', const [('日本', '日本'), ('海外', '海外')], (v) => p.nationality = v), width: 96),
      // 出身：日本人は47都道府県、海外は出身国（8か国）
      if (p.nationality == '海外')
        _field('出身国', _dropdown<String>(
          NameData2.countries.contains(p.origin) ? p.origin : '',
          [('', '未設定'), for (final c in NameData2.countries) (c, c)],
          (v) => p.origin = v,
        ), width: 130)
      else
        _field('出身地', _dropdown<String>(
          NameData2.prefectures.any((x) => x.$1 == p.birthplace) ? p.birthplace : '',
          [('', '未設定'), for (final x in NameData2.prefectures) (x.$1, x.$1)],
          (v) => p.birthplace = v,
        ), width: 130),
      _field('来歴', _dropdown<String>(['A', 'B', 'C'].contains(p.draftType) ? p.draftType : 'A', const [('A', '高卒'), ('B', '大卒'), ('C', '社卒・その他')], (v) {
        p.draftType = v;
        _syncDates(fromDraft: true);
        _birthRev++;
        _proRev++;
      }), width: 120),
      if (p.draftType == 'C') _field('1年目の年齢', _numBox('draftAge', p.draftCustomAge, (v) {
        p.draftCustomAge = v;
        _syncDates(fromDraft: true);
        _birthRev++;
        _proRev++;
      }, width: 90, min: 15, max: 45), width: 90),
      _field('生年月日', _textBox('birth_$_birthRev', p.birthDate, (s) {
        p.birthDate = s;
        _syncDates(fromBirthDate: true);
        _proRev++;
      }), width: 130),
      _field('年齢', Container(height: 36, alignment: Alignment.centerLeft, child: Text('${p.age}歳', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))), width: 60),
      _field('プロ年数', _numBox('proYears_$_proRev', p.proYears, (v) {
        p.proYears = v;
        _syncDates(fromProYears: true);
        _birthRev++;
      }, width: 76, min: 1, max: 30), width: 76),
      _field('身長(cm)', _numBox('height', p.height, (v) => p.height = v, width: 76, min: 140, max: 220), width: 76),
      _field('体重(kg)', _numBox('weight', p.weight, (v) => p.bodyWeight = v, width: 76, min: 50, max: 150), width: 76),
      _field('腕の長さ', _numBox('armLen', p.armLength, (v) => p.bodyArm = v, width: 76, min: 55, max: 105), width: 76),
      _field('頭囲', _numBox('headG', p.headGirth, (v) => p.bodyHead = v, width: 76, min: 48, max: 66), width: 76),
      _field('胸囲', _numBox('chestG', p.chestGirth, (v) => p.bodyChest = v, width: 76, min: 75, max: 140), width: 76),
      _field('腹囲', _numBox('waistG', p.waistGirth, (v) => p.bodyWaist = v, width: 76, min: 60, max: 135), width: 76),
      _field('臀囲', _numBox('hipG', p.hipGirth, (v) => p.bodyHip = v, width: 76, min: 75, max: 135), width: 76),
      _field('フォーム・道具', SizedBox(height: 36, child: OutlinedButton.icon(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BodyFormEditor(player: p, bodyEditable: false)));
          if (mounted) setState(() {});
          widget.onChanged();
        },
        icon: const Icon(Icons.sports_baseball, size: 16),
        label: const Text('フォーム・道具'),
      )), width: 150),
      _field('才能', _numBox('talent', p.talent, (v) => p.talent = v, width: 64), width: 64),
      _field('向上心', _numBox('ambition', p.ambition, (v) => p.ambition = v, width: 64), width: 64),
      // 成長曲線：全盛期が始まる年齢と、成長期・全盛期・過渡期の長さ（標準 27歳・2年・4年・2年）
      _field('全盛期の開始(歳)', _numBox('primeStart', (GrowthCurve.starts(p))[1], (v) => p.primeStart = v, width: 76, min: 18, max: 42), width: 110),
      _field('成長期(年)', _numBox('riseLen', p.riseLen, (v) => p.riseLen = v, width: 64, min: 1, max: 5), width: 80),
      _field('全盛期(年)', _numBox('primeLen', p.primeLen, (v) => p.primeLen = v, width: 64, min: 1, max: 15), width: 80),
      _field('過渡期(年)', _numBox('transLen', p.transLen, (v) => p.transLen = v, width: 64, min: 1, max: 6), width: 80),
      _field('弾道', _dropdown<int>(p.trajectory.clamp(1, 4), const [(1, '1'), (2, '2'), (3, '3'), (4, '4')], (v) => p.trajectory = v), width: 70),
    ]);
  }

  List<Widget> _abilitySections() {
    final batting = _section('打撃', [
      _displayRow('ミート', GradeUtils.getGrade(p.contact), '${p.contact}', note: '対左右の平均'),
      _abilityRow('ミート（対左）', p.contactLeft, (v) => p.contactLeft = v),
      _abilityRow('ミート（対右）', p.contactRight, (v) => p.contactRight = v),
      _abilityRow('パワー', p.power, (v) => p.power = v),
      _abilityRow('選球眼', p.eye, (v) => p.eye = v),
      _abilityRow('チャンス', p.clutch, (v) => p.clutch = v),
    ]);
    final defense = _section('守備・走塁', [
      _abilityRow('走力', p.run, (v) => p.run = v),
      _abilityRow('肩力', p.arm, (v) => p.arm = v),
      _abilityRow('送球', p.throwAccuracy, (v) => p.throwAccuracy = v),
      _abilityRow('捕球', p.catchSkill, (v) => p.catchSkill = v),
    ]);
    final body = _section('身体・精神', [
      Container(
        height: 38,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F4)))),
        child: Row(children: [
          Expanded(child: Text.rich(TextSpan(children: [
            const TextSpan(text: '体力', style: TextStyle(fontSize: 13.5)),
            TextSpan(text: '  現在 ${p.energy}／最大', style: const TextStyle(fontSize: 11, color: _sub)),
          ]))),
          SizedBox(width: 22, child: Center(child: _grade(p.energyRank))),
          const SizedBox(width: 8),
          _numBox('maxEnergy', p.maxEnergy, (v) {
            final wasFull = p.energy >= p.maxEnergy;
            p.maxEnergy = v;
            p.energy = wasFull ? p.maxEnergy : p.energy.clamp(0, p.maxEnergy);
          }, max: 1000),
        ]),
      ),
      _abilityRow('回復力', p.recovery, (v) => p.recovery = v),
      _abilityRow('怪我しにくさ', p.durability, (v) => p.durability = v),
      _abilityRow('監督への信頼', p.trust, (v) => p.trust = v),
    ]);
    final pitching = _section(p.isPitcher ? '投球' : '投球（野手登板・二刀流用）', [
      Container(
        height: 38,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F4)))),
        child: Row(children: [
          const Expanded(child: Text('球速', style: TextStyle(fontSize: 13.5))),
          SizedBox(width: 22, child: Center(child: _grade(p.velocityNorm))),
          const SizedBox(width: 8),
          _numBox('velocity', p.velocity, (v) => p.velocity = v, min: 80, max: 175),
          const SizedBox(width: 4),
          const Text('km', style: TextStyle(fontSize: 11, color: _sub)),
        ]),
      ),
      _abilityRow('球威', p.pitchPower, (v) => p.pitchPower = v),
      _abilityRow('制球', p.control, (v) => p.control = v),
      _abilityRow('スタミナ', p.stamina, (v) => p.stamina = v),
      _abilityRow('ピンチ', p.clutchPitching, (v) => p.clutchPitching = v),
      _abilityRow('クイック', p.quick, (v) => p.quick = v),
      Container(
        height: 38,
        child: Row(children: [
          const Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: '腕の角度', style: TextStyle(fontSize: 13.5)), TextSpan(text: '  0＝真上 90＝真横 135＝下から（度）', style: TextStyle(fontSize: 11, color: _sub))]))),
          _numBox('spinAxis', p.spinAxis, (v) => p.spinAxis = v, min: 0, max: 360),
        ]),
      ),
    ]);
    if (!p.isPitcher) return [batting, defense, body, pitching];
    return [pitching, body, batting, defense];
  }

  Widget _sideColumn() {
    final mainShort = const {'投手': '投', '捕手': '捕', '一塁手': '一', '二塁手': '二', '三塁手': '三', '遊撃手': '遊', '左翼手': '左', '中堅手': '中', '右翼手': '右'}[p.isPitcher ? '投手' : p.mainPosition];
    const posOrder = ['左', '中', '右', '三', '遊', '二', '投', '一', '捕'];
    void setField(String pos, int v) {
      switch (pos) {
        case '投': p.fieldP = v; break;
        case '捕': p.fieldC = v; break;
        case '一': p.field1B = v; break;
        case '二': p.field2B = v; break;
        case '三': p.field3B = v; break;
        case '遊': p.fieldSS = v; break;
        case '左': p.fieldLF = v; break;
        case '中': p.fieldCF = v; break;
        case '右': p.fieldRF = v; break;
      }
    }

    final cond = p.conditionAt(widget.appState.currentDate);
    final injury = p.injuryDays <= 0
        ? '健康'
        : '${p.injuryName.isEmpty ? '怪我' : p.injuryName} 全治${p.injuryDays}日（${const {1: '軽度・強行出場可', 2: '中度・出場不可', 3: '重度・出場不可'}[p.injurySeverity] ?? ''}）';
    final box = BoxDecoration(color: Colors.white, border: Border.all(color: _line));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: box,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            const Text('総合', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            _grade(p.ovr, size: 34),
            const SizedBox(width: 6),
            Text('${p.ovr}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          ]),
          const Text('数値を変えると即時に再計算', style: TextStyle(fontSize: 11.5, color: _sub)),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: box,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('守備適性', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.5,
            children: [
              for (final pos in posOrder)
                Container(
                  decoration: BoxDecoration(
                    color: pos == mainShort ? const Color(0xFFFEF3C7) : _soft,
                    border: Border.all(color: pos == mainShort ? const Color(0xFFF59E0B) : _line, width: pos == mainShort ? 2 : 1),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(pos, style: const TextStyle(fontSize: 10.5, color: _sub)),
                      const SizedBox(width: 4),
                      _grade(fieldingAt(p, pos), size: 12),
                    ]),
                    const SizedBox(height: 2),
                    _numBox('field_$pos', fieldingAt(p, pos), (v) => setField(pos, v), width: 50),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('黄色＝メインポジション（上のプルダウンで変更）', style: TextStyle(fontSize: 11, color: _sub)),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: box,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('契約', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Row(children: [
            const Expanded(child: Text('年俸（万円）', style: TextStyle(fontSize: 13))),
            _numBox('salary_$_salaryRev', p.salary, (v) => p.salary = v, width: 90, min: 0, max: 999999),
          ]),
          Align(alignment: Alignment.centerRight, child: Text(formatSalary(p.salary), style: const TextStyle(fontSize: 12, color: _sub))),
          const SizedBox(height: 4),
          Row(children: [
            const Expanded(child: Text('契約年数', style: TextStyle(fontSize: 13))),
            _numBox('contract', p.contractYears, (v) => p.contractYears = v, width: 90, min: 1, max: 10),
          ]),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _set(() {
              p.salary = estimateSalary(p);
              _salaryRev++;
            }),
            style: OutlinedButton.styleFrom(foregroundColor: _ink, side: const BorderSide(color: Color(0xFFD6D3D1)), shape: const RoundedRectangleBorder()),
            child: const Text('能力から年俸を自動算出'),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: box,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('いまの状態', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Row(children: [
            const Text('調子  ', style: TextStyle(fontSize: 12.5, color: _sub)),
            ConditionFace(level: cond, size: 18),
            const SizedBox(width: 4),
            Text(Player.conditionLabels[cond]!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('モチベ ${p.motivation}', style: const TextStyle(fontSize: 12.5)),
          ]),
          const SizedBox(height: 4),
          Text('故障  $injury', style: TextStyle(fontSize: 12.5, color: p.injuryDays > 0 ? Colors.red : Colors.green.shade700, fontWeight: FontWeight.w600)),
        ]),
      ),
    ]);
  }

  // ───────── 変化球 ─────────

  Widget _pitchSection(bool wide) {
    final total = p.pitches.fold<int>(0, (s, x) => s + x.ratio);
    final totalColor = total == 100 ? Colors.green.shade700 : (total > 100 ? Colors.red : Colors.orange.shade800);
    const head = TextStyle(fontSize: 11, color: _sub);
    final table = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFD6D3D1)))),
        child: const Row(children: [
          Expanded(child: Text('球種名', style: head)),
          SizedBox(width: 64, child: Text('球速', style: head, textAlign: TextAlign.right)),
          SizedBox(width: 60, child: Text('割合%', style: head, textAlign: TextAlign.right)),
          SizedBox(width: 64, child: Text('方向°', style: head, textAlign: TextAlign.right)),
          SizedBox(width: 82, child: Text('変化量', style: head, textAlign: TextAlign.right)),
          SizedBox(width: 82, child: Text('キレ', style: head, textAlign: TextAlign.right)),
          SizedBox(width: 82, child: Text('重さ', style: head, textAlign: TextAlign.right)),
          SizedBox(width: 36),
        ]),
      ),
      for (int i = 0; i < p.pitches.length; i++) _pitchRow(i),
      const SizedBox(height: 8),
      Row(children: [
        _pitchMenu(
          onPicked: (s) => _set(() => p.pitches.add(PitchCatalog.fromSpec(p, s, Random()))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD6D3D1))),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, size: 18, color: _ink), SizedBox(width: 4), Text('球種を追加（38種から）', style: TextStyle(color: _ink))]),
          ),
        ),
        const Spacer(),
        const Text('投球割合の合計  ', style: TextStyle(fontSize: 12.5, color: _sub)),
        Text('$total%', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: totalColor)),
      ]),
    ]);
    final chart = Column(children: [
      SizedBox(width: 170, height: 170, child: CustomPaint(painter: PitchVectorPainter(p.pitches))),
      const SizedBox(height: 4),
      const Text('変化球図（方向と変化量）', style: TextStyle(fontSize: 11, color: _sub)),
    ]);
    return _section(p.isPitcher ? '持ち球' : '持ち球（野手登板・二刀流用）', [
      const SizedBox(height: 4),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          chart,
          const SizedBox(width: 20),
          Expanded(child: table),
        ])
      else ...[
        Center(child: chart),
        const SizedBox(height: 8),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: 600, child: table)),
      ],
    ]);
  }

  Widget _pitchRow(int i) {
    final pitch = p.pitches[i];
    // 同じ球種を削除して詰めたときに入力欄が残らないよう、行番号と名前を key に含める
    final k = 'pitch_${i}_${identityHashCode(pitch)}';
    Widget graded(String key, int v, ValueChanged<int> f) => SizedBox(
          width: 82,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [_grade(v, size: 13), const SizedBox(width: 4), _numBox('${k}_$key', v, f, width: 52)]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F4)))),
      child: Row(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _pitchMenu(
              // 別の球種に変えると、その球種の典型的な球速・変化に作り直す（割合はそのまま）
              onPicked: (s) => _set(() {
                final np = PitchCatalog.fromSpec(p, s, Random());
                np.ratio = pitch.ratio;
                p.pitches[i] = np;
              }),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFD6D3D1))),
                child: Row(children: [
                  Expanded(child: Text(pitch.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
                  const Icon(Icons.arrow_drop_down, size: 18, color: _sub),
                ]),
              ),
            ),
          ),
        ),
        SizedBox(width: 64, child: Align(alignment: Alignment.centerRight, child: _numBox('${k}_speed', pitch.speed, (v) => pitch.speed = v, width: 58, min: 60, max: 175))),
        SizedBox(width: 60, child: Align(alignment: Alignment.centerRight, child: _numBox('${k}_ratio', pitch.ratio, (v) => pitch.ratio = v, width: 52, min: 0, max: 100))),
        SizedBox(width: 64, child: Align(alignment: Alignment.centerRight, child: _numBox('${k}_angle', pitch.angle, (v) => pitch.angle = v, width: 58, min: 0, max: 360))),
        graded('break', pitch.breakLevel, (v) => pitch.breakLevel = v),
        graded('sharp', pitch.sharpness, (v) => pitch.sharpness = v),
        graded('heavy', pitch.heaviness, (v) => pitch.heaviness = v),
        SizedBox(
          width: 36,
          child: IconButton(
            tooltip: '削除',
            icon: const Icon(Icons.close, size: 18, color: _sub),
            onPressed: () => _set(() => p.pitches.removeAt(i)),
          ),
        ),
      ]),
    );
  }

  // ───────── 通算成績（開始時点まで。固有12で入力する） ─────────

  Widget _careerSection() {
    final c = p.career;
    void ch(void Function() f) {
      f();
      p.careerEstimated = false;
    }
    // 投球（投手の登板は試合数。野手の登板は登板数として持つ）
    final pitching = <(String, int, ValueChanged<int>)>[
            if (p.isPitcher) ('登板', c.games, (v) => ch(() => c.games = v)) else ('登板', c.pitchApps, (v) => ch(() => c.pitchApps = v)),
            ('勝', c.wins, (v) => ch(() => c.wins = v)),
            ('敗', c.losses, (v) => ch(() => c.losses = v)),
            ('セーブ', c.saves, (v) => ch(() => c.saves = v)),
            ('ホールド', c.holds, (v) => ch(() => c.holds = v)),
            ('投球回', c.inningsPitched ~/ 3, (v) => ch(() => c.inningsPitched = v * 3)),
            ('奪三振', c.pitcherStrikeouts, (v) => ch(() => c.pitcherStrikeouts = v)),
            ('自責点', c.earnedRuns, (v) => ch(() => c.earnedRuns = v)),
            ('与四球', c.pitcherWalks, (v) => ch(() => c.pitcherWalks = v)),
          ];
    // 打撃（投手の試合数は登板と同じ）
    final batting = <(String, int, ValueChanged<int>)>[
            if (!p.isPitcher) ('試合', c.games, (v) => ch(() => c.games = v)),
            ('打数', c.atBats, (v) => ch(() => c.atBats = v)),
            ('安打', c.hits, (v) => ch(() => c.hits = v)),
            ('二塁打', c.doubles, (v) => ch(() => c.doubles = v)),
            ('三塁打', c.triples, (v) => ch(() => c.triples = v)),
            ('本塁打', c.homeRuns, (v) => ch(() => c.homeRuns = v)),
            ('打点', c.rbi, (v) => ch(() => c.rbi = v)),
            ('四球', c.walks, (v) => ch(() => c.walks = v)),
            ('三振', c.strikeouts, (v) => ch(() => c.strikeouts = v)),
            ('盗塁', c.stolenBases, (v) => ch(() => c.stolenBases = v)),
          ];
    final groups = p.isPitcher ? [('投球', pitching, 'p'), ('打撃', batting, 'b')] : [('打撃', batting, 'b'), ('投球', pitching, 'p')];
    return _section(p.careerEstimated ? '通算成績（開始時点まで）　※能力とプロ年数からの推定値。実際の数字に直せます' : '通算成績（開始時点まで）', [
      for (final g in groups) ...[
        Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text(g.$1, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _sub))),
        Wrap(spacing: 10, runSpacing: 8, children: [
          for (final it in g.$2) _field(it.$1, _numBox('career_${g.$3}_${it.$1}_$_careerRev', it.$2, it.$3, width: 80, min: 0, max: 99999), width: 80),
        ]),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        OutlinedButton.icon(
          onPressed: () => _set(() {
            p.career = p.proYears <= 1 ? PlayerStats() : CareerEngine.estimate(p);
            p.careerEstimated = true;
            _careerRev++;
          }),
          icon: const Icon(Icons.calculate, size: 16),
          label: const Text('能力から推定する'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final team = ((widget.appState?.teams as List?) ?? const []).cast<dynamic>().where((t) => (t.players as List).contains(p)).firstOrNull;
            if (team == null) return;
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('この球団の全員を推定しますか？'),
                content: Text('${team.name}の選手${(team.players as List).length}人の通算成績を、能力とプロ年数から計算し直します（入力した数字は上書きされます。プロ1年目は0）'),
                actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('やめる')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('推定する'))],
              ),
            );
            if (ok != true) return;
            _set(() {
              for (final x in (team.players as List).cast<Player>()) {
                x.career = x.proYears <= 1 ? PlayerStats() : CareerEngine.estimate(x);
                x.careerEstimated = true;
              }
              _careerRev++;
            });
          },
          icon: const Icon(Icons.groups, size: 16),
          label: const Text('この球団の全員を推定'),
        ),
      ]),
      const SizedBox(height: 4),
      const Text('推定は、今の能力・年齢・プロ年数・全盛期から、年ごとの出場と成績を積み上げて計算します（同じ能力なら同じ値）。推定したあとに数字を直すこともできます。'
          '防御率は 自責点×9÷投球回、打率は 安打÷打数 で計算します。ここで入れた数字に、ゲームで記録した成績が足されていきます', style: TextStyle(fontSize: 11, color: _sub)),
    ]);
  }

  // ───────── 今季成績（表示のみ） ─────────

  Widget _statsSection() {
    final s = p.seasonStats;
    final items = p.isPitcher
        ? [('登板', '${s.games}'), ('勝', '${s.wins}'), ('敗', '${s.losses}'), ('H', '${s.holds}'), ('S', '${s.saves}'), ('防御率', s.era.toStringAsFixed(2)), ('投球回', (s.inningsPitched / 3).toStringAsFixed(1)), ('奪三振', '${s.pitcherStrikeouts}'), ('与四球', '${s.pitcherWalks}'), ('自責点', '${s.earnedRuns}')]
        : [('試合', '${s.games}'), ('打率', s.battingAverage.toStringAsFixed(3).replaceFirst('0.', '.')), ('打数', '${s.atBats}'), ('安打', '${s.hits}'), ('本塁打', '${s.homeRuns}'), ('打点', '${s.rbi}'), ('三振', '${s.strikeouts}'), ('四球', '${s.walks}'), ('盗塁', '${s.stolenBases}')];
    return _section('今季の成績（表示のみ）', [
      const SizedBox(height: 4),
      Wrap(children: [
        for (final it in items)
          Container(
            width: 92,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFF5F5F4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.$1, style: const TextStyle(fontSize: 11, color: _sub)),
              Text(it.$2, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    ]);
  }
}
