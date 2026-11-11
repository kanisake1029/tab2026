import 'package:flutter/material.dart';
import '../../widgets/condition_face.dart';
import '../../widgets/player_row.dart';
import '../../engine/farm_engine.dart';
import '../../engine/growth_curve.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import '../../utils/app_theme.dart';
import '../../utils/grade_utils.dart';
import '../../widgets/note_box.dart';
import 'order_shared.dart';

/// スタメン（1軍・2軍・3軍で同じ画面）
///  ・入れ替えはドラッグだけ（広い画面はそのまま、スマホは長押しで掴む）
///    （打順同士＝打順の入れ替え／控え⇔スタメン＝交代／守備位置のマーカー＝その位置へ）
///  ・タップは「選んだ選手の能力」に表示するだけ（何人もタップして見比べられる）
///  ・広い画面：打順表＋守備フィールド。狭い画面：2行のカード型の打順＋守備フィールド＋控え
///  ・2軍：打順を変えると「自分で組む」になる（出られない選手は自動で代わりが入る）
///  ・3軍：守備位置は無く（3軍監督が決める）、打順だけを変えられる
class LineupTab extends StatefulWidget {
  final Team team;
  final AppState appState;
  final VoidCallback onRosterChanged;
  final Map<String, Player> playerMap;
  /// 相手先発が左投げか（null＝不明）。対左・対右の列に使う
  final bool? oppLefty;
  /// 1＝1軍、2＝2軍、3＝3軍
  final int level;

  const LineupTab({
    super.key,
    required this.team,
    required this.appState,
    required this.onRosterChanged,
    required this.playerMap,
    this.oppLefty,
    this.level = 1,
  });

  @override
  State<LineupTab> createState() => _LineupTabState();
}

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);
const _pickBg = Color(0xFFFEF3C7);
const _pickBorder = Color(0xFFF59E0B);

/// 2軍：いま出ている打順（自動、または代わりの選手が入った手動）を「自分で組む」の打順として固める
void farmToManual(Team team) {
  team.farmLineup = [for (final e in FarmEngine.effectiveLineup(team)) LineupEntry(playerId: e.playerId, position: e.position)];
  if (team.farmAuto) team.farmRotation = FarmEngine.effectiveRotation(team);
  team.farmAuto = false;
}

/// 3軍戦に出ない選手（2軍の打順と2軍の次の先発）
Set<String> thirdUsed(Team team) {
  final rot = FarmEngine.effectiveRotation(team);
  return {
    for (final e in FarmEngine.effectiveLineup(team)) e.playerId,
    if (rot.isNotEmpty) rot[team.farmRotationIndex % rot.length],
  };
}

/// 年齢・全盛期・成長率（2軍・3軍の行に小さく出す）
String ageLine(Player p) {
  final (a, b) = GrowthCurve.primeRange(p);
  return '${p.age}歳 全盛$a-$b 成長×${p.growthRate.toStringAsFixed(2)}';
}

class _LineupTabState extends State<LineupTab> {
  Team get team => widget.team;
  int get _lv => widget.level;
  String? _picked; // 「選んだ選手の能力」に表示中の選手（色を付けて分かるようにする）
  bool _narrow = false;
  List<LineupEntry> _cur = const []; // 表示中の打順（2軍・3軍は見込み）
  (List<Player>, List<Player>, Set<String>)? _third;

  void _changed() {
    widget.appState.updateAndSave();
    widget.onRosterChanged();
    setState(() {});
  }

  Player _p(String id) => widget.playerMap[id] ?? team.players.where((x) => x.id == id).firstOrNull ?? team.players.first;

  /// その軍の成績
  PlayerStats _st(Player p) => _lv == 2 ? p.farmStats : (_lv == 3 ? p.thirdStats : p.shownStats);

  /// DH を使うか（2軍は常に DH、3軍は守備位置なし）
  bool get _dh => _lv == 1 ? team.useDH : _lv == 2;

  void _load() {
    if (_lv == 2) {
      _cur = FarmEngine.effectiveLineup(team);
    } else if (_lv == 3) {
      _third = widget.appState.thirdOrder(team, used: thirdUsed(team));
      _cur = [for (final p in _third?.$1 ?? const <Player>[]) LineupEntry(playerId: p.id, position: '')];
    } else {
      _cur = team.lineup;
    }
  }

  Player? get _sp {
    if (_lv == 2) {
      final rot = FarmEngine.effectiveRotation(team);
      if (rot.isEmpty) return null;
      final id = rot[team.farmRotationIndex % rot.length];
      return id.isEmpty ? null : _p(id);
    }
    if (_lv == 3) return _third == null || _third!.$2.isEmpty ? null : _third!.$2.first;
    final id = team.todaysStarterId;
    return id != null && id.isNotEmpty ? widget.playerMap[id] : null;
  }

  List<Player> get _benchFielders {
    final ids = _cur.map((l) => l.playerId).toSet();
    if (_lv == 2) {
      return FarmEngine.farmPlayers(team).where((p) => !p.isPitcher && !ids.contains(p.id)).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    }
    if (_lv == 3) {
      final used = thirdUsed(team);
      return team.players.where((p) => !p.isPitcher && !team.roster1G.contains(p.id) && !used.contains(p.id) && !ids.contains(p.id)).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    }
    return team.active26.map(_p).where((p) => p.canBat && !ids.contains(p.id)).toList()..sort(compareByUniform);
  }

  /// 打順を変える。2軍は「自分で組む」に、3軍は「自分で組む」の打順として保存する
  void _edit(void Function(List<LineupEntry> l) f) {
    if (_lv == 2) {
      farmToManual(team);
      f(team.farmLineup);
    } else if (_lv == 3) {
      final l = [for (final e in _cur) LineupEntry(playerId: e.playerId, position: e.position)];
      f(l);
      team.thirdLineup = [for (final e in l) e.playerId];
      team.thirdAuto = false;
    } else {
      f(team.lineup);
    }
    _changed();
  }

  // ───────── 入れ替え処理 ─────────

  /// 打順 index の枠に選手を落とした
  void _dropOnSlot(int index, String draggedId) {
    final droppedP = _p(draggedId);
    final oldIndex = _cur.indexWhere((l) => l.playerId == draggedId);
    if (oldIndex == -1) {
      final pos = _cur[index].position;
      if (pos == '投' ? !droppedP.canPitch : !droppedP.canBat) {
        _toast(pos == '投' ? '投手の打順には投手（二刀流を含む）しか入れられません' : '投手は野手の打順に入れられません（二刀流にすると入れられます）');
        return;
      }
    }
    _edit((l) {
      if (oldIndex != -1) {
        // 打順の入れ替え（守備位置は選手について動く）
        final tmp = l[index];
        l[index] = l[oldIndex];
        l[oldIndex] = tmp;
      } else {
        l[index].playerId = draggedId;
      }
    });
  }

  /// 守備位置 pos に選手を落とした
  void _dropOnPosition(String pos, String draggedId) {
    final idx = _cur.indexWhere((l) => l.position == pos);
    if (idx == -1) return;
    final oldIndex = _cur.indexWhere((l) => l.playerId == draggedId);
    if (oldIndex != -1 && (_cur[oldIndex].position == '投' || pos == '投')) return;
    if (oldIndex == -1 && (pos == '投' ? !_p(draggedId).canPitch : !_p(draggedId).canBat)) return;
    _edit((l) {
      if (oldIndex != -1) {
        // スタメン同士なら守備位置だけを入れ替える（打順はそのまま）
        final tmp = l[oldIndex].position;
        l[oldIndex].position = pos;
        l[idx].position = tmp;
      } else {
        l[idx].playerId = draggedId;
      }
    });
  }

  /// 守備位置を変える（その位置にいた選手と入れ替え）
  void _setPosition(int index, String val) {
    _edit((l) {
      final oldPos = l[index].position;
      final dup = l.indexWhere((x) => x.position == val);
      if (dup != -1) l[dup].position = oldPos;
      l[index].position = val;
    });
  }

  void _setDH(bool val) {
    final sp = _sp;
    team.useDH = val;
    if (!val) {
      final dhIdx = team.lineup.indexWhere((l) => l.position == 'DH');
      if (dhIdx != -1 && sp != null) {
        team.lineup[dhIdx].playerId = sp.id;
        team.lineup[dhIdx].position = '投';
      }
    } else {
      final pIdx = team.lineup.indexWhere((l) => l.position == '投');
      if (pIdx != -1) team.lineup[pIdx].position = 'DH';
    }
    _changed();
  }

  /// 2軍・3軍：おまかせ／自分で組む の切り替えと説明（打順の上）
  Widget _levelHeader() {
    final auto = _lv == 2 ? team.farmAuto : team.thirdAuto;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<bool>(
            segments: [ButtonSegment(value: true, label: Text(_lv == 2 ? '自動で組む' : '3軍監督におまかせ')), const ButtonSegment(value: false, label: Text('自分で組む'))],
            selected: {auto},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12.5)),
            onSelectionChanged: (v) {
              if (_lv == 2) {
                if (v.first) {
                  team.farmAuto = true;
                } else {
                  team.farmLineup = FarmEngine.autoLineup(team);
                  team.farmRotation = FarmEngine.effectiveRotation(team);
                  team.farmAuto = false;
                }
              } else {
                team.thirdAuto = v.first;
                if (!v.first) team.thirdLineup = [for (final e in _cur) e.playerId];
              }
              _changed();
            },
          ),
          if (_lv == 2 && !auto)
            TextButton.icon(
              onPressed: () {
                team.farmLineup = FarmEngine.autoLineup(team);
                team.farmRotation = FarmEngine.effectiveRotation(team);
                _changed();
              },
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('自動の並びに戻す', style: TextStyle(fontSize: 12.5)),
            ),
        ]),
        const SizedBox(height: 6),
        NoteBox(_lv == 2
            ? '2軍の試合は1軍と同じ日程・同じ相手の2軍と行い、試合は自動で進みます。打順を入れ替えると「自分で組む」になります。出られない選手には自動で代わりが入ります。'
            : '3軍戦は2軍戦のある日に12球団の総当たりで行います（簡易計算）。1軍と、その日の2軍戦に出る選手は出ません。守備位置と投手は3軍監督が決めます。打順を入れ替えると「自分で組む」になります。'),
        if (_lv == 2 && _cur.length < 9)
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('出場できる2軍の野手が足りません（この間、2軍の試合は行われません）', style: TextStyle(color: Color(0xFFB91C1C), fontSize: 12))),
        if (_lv == 3 && _third == null) const Padding(padding: EdgeInsets.only(top: 6), child: Text('投手がいないため、3軍戦は組めません', style: TextStyle(color: _sub, fontSize: 12))),
      ]),
    );
  }

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 2)));

  // ───────── タップ ─────────

  /// タップ：「選んだ選手の能力」に表示するだけ（入れ替えはドラッグで行う。何人もタップして見比べられるように）
  void _tap(String id) {
    selectedOrderPlayer.value = _p(id);
    setState(() => _picked = id);
  }

  void _tapPosition(String pos) {
    final p = _playerAt(pos);
    if (p != null && !(pos == '投' && _dh)) _tap(p.id);
  }

  Widget _tapArea(Player p, Widget child) => InkWell(
        onTap: () => _tap(p.id),
        onDoubleTap: _narrow ? null : () => openPlayerDetail(context, p, widget.appState, team, widget.onRosterChanged), // スマホはタップを即反応させる（詳細は下のパネルから）
        child: child,
      );

  // ───────── 画面 ─────────

  @override
  Widget build(BuildContext context) {
    _load();
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 880 && _lv != 3;
      _narrow = c.maxWidth < 600;
      final table = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [if (_lv > 1) _levelHeader(), _narrow ? _lineupCards() : _lineupTable()]);
      final field = _lv == 3 ? const SizedBox.shrink() : _fieldCard();
      final bench = _benchCard();
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(_narrow ? 10 : 16, 12, _narrow ? 10 : 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (wide) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: table),
              const SizedBox(width: 18),
              SizedBox(width: 280, child: field),
            ]),
            const SizedBox(height: 16),
            bench,
          ] else ...[
            table,
            const SizedBox(height: 16),
            bench,
            const SizedBox(height: 16),
            Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: field)),
          ],
        ]),
      );
    });
  }

  Widget _titleRow() => Row(children: [
        const Text('打順', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(_narrow ? '長押しでドラッグして入替（タップで能力を表示）' : 'ドラッグで入替（タップで能力を表示）',
              style: const TextStyle(fontSize: 11.5, color: _sub), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        if (_lv == 1) ...[
          const Text('指名打者', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          Switch(value: team.useDH, onChanged: _setDH),
        ],
      ]);

  Widget _gradeText(int v, {double size = 14}) {
    final g = GradeUtils.getGrade(v);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: g, style: TextStyle(fontWeight: FontWeight.w900, fontSize: size, color: AppTheme.getGradeColor(g))),
        TextSpan(text: ' $v', style: const TextStyle(fontSize: 13, color: _ink)),
      ]),
      textAlign: TextAlign.right,
    );
  }

  Widget _energy(Player p, {double size = 13}) => Text('${(p.energyRatio * 100).round()}%',
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: size, fontFeatures: const [FontFeature.tabularFigures()], color: p.energyRatio < 0.3 ? Colors.red : (p.energyRatio < 0.5 ? const Color(0xFFB45309) : const Color(0xFF57534E))));

  Widget _injury(Player p) => p.injuryDays > 0
      ? Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Tooltip(message: '${p.injuryName} 残り${p.injuryDays}日', child: Icon(Icons.local_hospital, size: 15, color: p.injurySeverity >= 2 ? Colors.redAccent : Colors.orange)),
        )
      : const SizedBox.shrink();

  String _hand(Player p) => p.bats == 'L' ? '左打' : (p.bats == 'S' ? '両打' : '右打');
  String _avg(Player p) => _st(p).atBats == 0 ? '-' : _st(p).battingAverage.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');

  List<String> get _posOptions => _lv == 3 ? const [] : ['捕', '一', '二', '三', '遊', '左', '中', '右', if (_dh) 'DH'];

  /// 守備位置をボトムシートで選ぶ（スマホ向け）
  Future<void> _choosePosition(int index) async {
    final entry = _cur[index];
    final player = _p(entry.playerId);
    final val = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${player.listName} の守備位置', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 4),
            const Text('その位置にいた選手と入れ替わります。数字はその位置の守備適性', style: TextStyle(fontSize: 12, color: _sub)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final pos in _posOptions)
                ChoiceChip(
                  selected: pos == entry.position,
                  label: Text(pos == 'DH' ? '指' : '$pos ${GradeUtils.getGrade(fieldingAt(player, pos))}'),
                  onSelected: (_) => Navigator.pop(c, pos),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (val != null && val != entry.position) _setPosition(index, val);
  }

  // ───────── 打順（狭い画面：2行のカード） ─────────

  // 1行の並び（試合前のラインナップと同じ）
  //  1軍：順・守（適性）・調子・選手・利き手・総合・打率・本・点・盗
  //  2・3軍：順・守（適性）・調子・選手・利き手・年齢・全盛期・成長率・打率・本
  List<(String, double)> get _rowCols => _lv == 1
      ? const [('総合', 42), ('打率', 38), ('本', 22), ('点', 26), ('盗', 22)]
      : const [('年', 22), ('全盛', 40), ('成長', 34), ('打率', 38), ('本', 22)];

  List<Widget> _valueCells(Player p) {
    final s = _st(p);
    const st = TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()], color: Color(0xFF292524));
    final cols = _rowCols;
    final bat = !(p.isPitcher && !p.twoWay);
    final List<Widget> v;
    if (_lv == 1) {
      v = [
        _gradeText(p.ovr, size: 12.5),
        Text(bat ? _avg(p) : '−', textAlign: TextAlign.right, style: st),
        Text(bat ? '${s.homeRuns}' : '', textAlign: TextAlign.right, style: st),
        Text(bat ? '${s.rbi}' : '', textAlign: TextAlign.right, style: st),
        Text(bat ? '${s.stolenBases}' : '', textAlign: TextAlign.right, style: st),
      ];
    } else {
      final (pa, pb) = GrowthCurve.primeRange(p);
      v = [
        Text('${p.age}', textAlign: TextAlign.right, style: st),
        Text('$pa-$pb', textAlign: TextAlign.right, style: st.copyWith(color: const Color(0xFF0F766E))),
        Text(p.growthRate.toStringAsFixed(2), textAlign: TextAlign.right, style: st.copyWith(color: const Color(0xFF0F766E))),
        Text(bat ? _avg(p) : '−', textAlign: TextAlign.right, style: st),
        Text(bat ? '${s.homeRuns}' : '', textAlign: TextAlign.right, style: st),
      ];
    }
    return [for (var i = 0; i < cols.length; i++) SizedBox(width: cols[i].$2, child: Align(alignment: Alignment.centerRight, child: v[i]))];
  }

  /// 表の見出し
  Widget _statHeader(double left, {String name = '選手'}) {
    const h = TextStyle(fontSize: 10.5, color: _sub);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Row(children: [
        const SizedBox(width: 18, child: Text('順', style: h)),
        const SizedBox(width: 48, child: Text('守・適性', style: h)),
        const SizedBox(width: 20),
        Expanded(child: Text(name, style: h)),
        for (final c in _rowCols) SizedBox(width: c.$2, child: Text(c.$1, textAlign: TextAlign.right, style: h)),
      ]),
    );
  }

  /// 守備位置と、その位置の守備適性（例：遊 B）。onTap があれば枠つき（変えられる）
  Widget _posCell(String pos, Player p, {VoidCallback? onTap}) {
    final apt = pos == 'DH' || pos == '投' || pos.isEmpty ? null : fieldingAt(p, pos);
    final g = apt == null ? '' : GradeUtils.getGrade(apt);
    final inner = Row(mainAxisSize: MainAxisSize.min, children: [
      Text(posLabel(pos), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: onTap == null ? _sub : _ink)),
      if (apt != null) ...[
        const SizedBox(width: 2),
        Text(g, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: apt < 40 ? Colors.red : AppTheme.getGradeColor(g))),
      ],
      if (onTap != null) const Icon(Icons.arrow_drop_down, size: 14),
    ]);
    return SizedBox(
      width: 48,
      child: onTap == null
          ? Padding(padding: const EdgeInsets.only(left: 2), child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: inner))
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(5),
              child: Container(
                height: 24,
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.only(left: 3),
                decoration: BoxDecoration(border: Border.all(color: _ink), borderRadius: BorderRadius.circular(5)),
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: inner),
              ),
            ),
    );
  }

  /// 選手名（調子のマーク・怪我・体力が少ないときだけ体力）と利き手
  List<Widget> _nameCells(Player p) => [
        SizedBox(width: 22, child: Align(alignment: Alignment.centerLeft, child: ConditionFace(level: p.conditionAt(widget.appState.currentDate), size: _lv > 1 ? 11 : 14))),
        const SizedBox(width: 3),
        Expanded(
          child: Row(children: [
            Flexible(child: Text(p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            _injury(p),
            if (p.energyRatio < 0.7) Padding(padding: const EdgeInsets.only(left: 3), child: _energy(p, size: 10)),
          ]),
        ),
        SizedBox(width: 14, child: Text(_hand(p).substring(0, 1), style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)))),
      ];

  Widget _lineupCards() {
    final sp = _sp;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titleRow(),
      _statHeader(0),
      const Divider(height: 1, color: _ink),
      for (int i = 0; i < 9 && i < _cur.length; i++) _cardSlot(i),
      if ((_dh || _lv == 3) && sp != null)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          decoration: const BoxDecoration(color: Color(0xFFFAFAF9), border: Border(bottom: BorderSide(color: _line))),
          child: Row(children: [
            SizedBox(width: 44, child: Text(_lv == 3 ? '1〜3回' : '先発', style: const TextStyle(fontSize: 11.5, color: _sub))),
            Expanded(child: PitcherLine(p: sp, s: _st(sp), date: widget.appState.currentDate, faceSize: _lv > 1 ? 11 : 14)),
          ]),
        ),
    ]);
  }

  Widget _cardSlot(int index) {
    final entry = _cur[index];
    final p = _p(entry.playerId);
    final picked = _picked == p.id;
    final pos = _lv == 3 ? _shortPos(p) : entry.position;
    Widget body(bool hovered) => Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: picked ? _pickBg : (hovered ? const Color(0xFFFFFBEB) : Colors.white),
            border: Border(bottom: const BorderSide(color: _line), left: BorderSide(color: picked ? _pickBorder : Colors.transparent, width: 3)),
          ),
          child: Row(children: [
            SizedBox(width: 18, child: Text('${index + 1}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
            _posCell(pos, p, onTap: entry.position == '投' || _lv == 3 ? null : () => _choosePosition(index)),
            ..._nameCells(p),
            ..._valueCells(p),
          ]),
        );
    return DragTarget<String>(
      onAcceptWithDetails: (d) => _dropOnSlot(index, d.data),
      builder: (context, cand, _) => orderDraggable(
        longPress: true,
        data: entry.playerId,
        feedback: Material(color: Colors.transparent, child: SizedBox(width: 360, child: Opacity(opacity: 0.9, child: body(false)))),
        childWhenDragging: Opacity(opacity: 0.3, child: body(false)),
        child: _tapArea(p, body(cand.isNotEmpty)),
      ),
    );
  }

  // ───────── 打順表（広い画面） ─────────

  static const _cols = <(String, double)>[('総合', 46), ('守適', 40), ('打率', 50), ('本', 32), ('打点', 38), ('対投', 52), ('体力', 46)];

  Widget _lineupTable() {
    final vsLabel = widget.oppLefty == null ? '対右' : (widget.oppLefty! ? '対左' : '対右');
    const head = TextStyle(fontSize: 11, color: _sub);
    final sp = _sp;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titleRow(),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _ink))),
        child: Row(children: [
          const SizedBox(width: 30, child: Text('打順', style: head)),
          const SizedBox(width: 58, child: Text('守備', style: head)),
          const Expanded(child: Text('選手', style: head)),
          for (final col in _cols) SizedBox(width: col.$2, child: Text(col.$1 == '対投' ? vsLabel : col.$1, textAlign: TextAlign.right, style: head)),
          const SizedBox(width: 16),
        ]),
      ),
      for (int i = 0; i < 9 && i < _cur.length; i++) _slot(i),
      if ((_dh || _lv == 3) && sp != null)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: const BoxDecoration(color: Color(0xFFFAFAF9), border: Border(bottom: BorderSide(color: _line))),
          child: Row(children: [
            const SizedBox(width: 30, child: Text('P', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _sub))),
            const SizedBox(width: 58, child: Text('先発', style: TextStyle(fontSize: 12, color: _sub))),
            Expanded(child: _nameCell(sp, false)),
            SizedBox(width: 46, child: _gradeText(sp.ovr)),
            Expanded(child: Text('${_st(sp).wins}勝${_st(sp).losses}敗　防御率 ${_st(sp).era.toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, color: _sub))),
          ]),
        ),
    ]);
    return LayoutBuilder(builder: (context, c) {
      const minW = 30 + 58 + 150 + 304 + 16 + 8.0;
      if (c.maxWidth >= minW) return body;
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: minW, child: body));
    });
  }

  Widget _nameCell(Player p, bool picked) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        ConditionFace(level: p.conditionAt(widget.appState.currentDate), size: 18),
        const SizedBox(width: 8),
        Flexible(child: Text(p.listName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
        _injury(p),
        const SizedBox(width: 6),
        Text(_hand(p), style: const TextStyle(fontSize: 11, color: _sub)),
      ]),
    );
  }

  Widget _slot(int index) {
    final entry = _cur[index];
    final player = _p(entry.playerId);
    final picked = _picked == player.id;
    final posOptions = [..._posOptions];
    if (!posOptions.contains(entry.position) && entry.position != '投') posOptions.add(entry.position);
    final s = _st(player);
    final vs = widget.oppLefty == true ? player.contactLeft : player.contactRight;
    final apt = entry.position == 'DH' || entry.position.isEmpty ? null : fieldingAt(player, entry.position);
    const num = TextStyle(fontSize: 13.5, fontFeatures: [FontFeature.tabularFigures()]);

    Widget row(bool hovered) => Container(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          decoration: BoxDecoration(
            color: picked ? _pickBg : (hovered ? const Color(0xFFFEF3C7) : Colors.white),
            border: Border(bottom: const BorderSide(color: _line), top: hovered ? const BorderSide(color: _pickBorder, width: 2) : BorderSide.none, left: BorderSide(color: picked ? _pickBorder : Colors.transparent, width: 3)),
          ),
          child: Row(children: [
            SizedBox(width: 30, child: Text('${index + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            SizedBox(
              width: 58,
              child: entry.position == '投' || _lv == 3
                  ? Text(_lv == 3 ? _shortPos(player) : '投', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))
                  : Container(
                      height: 30,
                      padding: const EdgeInsets.only(left: 6),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(border: Border.all(color: _ink), borderRadius: BorderRadius.circular(4)),
                      child: DropdownButton<String>(
                        value: entry.position,
                        isExpanded: true,
                        isDense: true,
                        underline: const SizedBox(),
                        iconSize: 16,
                        style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 13),
                        items: posOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (val) {
                          if (val != null) _setPosition(index, val);
                        },
                      ),
                    ),
            ),
            Expanded(child: _tapArea(player, _nameCell(player, picked))),
            SizedBox(width: 46, child: _gradeText(player.ovr)),
            SizedBox(
              width: 40,
              child: apt == null
                  ? const Text('−', textAlign: TextAlign.right, style: TextStyle(color: _sub))
                  : Text(GradeUtils.getGrade(apt), textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: apt < 40 ? Colors.red : AppTheme.getGradeColor(GradeUtils.getGrade(apt)))),
            ),
            SizedBox(width: 50, child: Text(player.isPitcher ? '−' : _avg(player), textAlign: TextAlign.right, style: num)),
            SizedBox(width: 32, child: Text('${s.homeRuns}', textAlign: TextAlign.right, style: num)),
            SizedBox(width: 38, child: Text('${s.rbi}', textAlign: TextAlign.right, style: num)),
            SizedBox(width: 52, child: _gradeText(vs, size: 13)),
            SizedBox(width: 46, child: _energy(player, size: 13.5)),
            const Icon(Icons.drag_indicator, size: 16, color: Color(0xFFA8A29E)),
          ]),
        );

    return DragTarget<String>(
      onAcceptWithDetails: (d) => _dropOnSlot(index, d.data),
      builder: (context, cand, _) {
        final content = row(cand.isNotEmpty);
        return orderDraggable(
          longPress: false,
          data: entry.playerId,
          feedback: Material(color: Colors.transparent, child: SizedBox(width: 600, child: Opacity(opacity: 0.9, child: row(false)))),
          childWhenDragging: Opacity(opacity: 0.3, child: content),
          child: content,
        );
      },
    );
  }

  // ───────── 守備フィールド ─────────

  static const _fieldPos = <String, Offset>{
    '中': Offset(0.50, 0.11), '左': Offset(0.16, 0.25), '右': Offset(0.84, 0.25),
    '遊': Offset(0.33, 0.46), '二': Offset(0.67, 0.46), '三': Offset(0.15, 0.62), '一': Offset(0.85, 0.62),
    '投': Offset(0.50, 0.66), '捕': Offset(0.50, 0.90),
  };

  Widget _fieldCard() {
    // 守備力＝野手8人（投手を除く）の守備適性の平均
    final apts = <int>[];
    for (final e in _cur) {
      if (e.position == 'DH' || e.position == '投') continue;
      apts.add(fieldingAt(_p(e.playerId), e.position));
    }
    final avg = apts.isEmpty ? 0 : (apts.reduce((a, b) => a + b) / apts.length).round();
    final dh = _cur.where((l) => l.position == 'DH').firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Text('守備位置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const Spacer(),
        const Text('守備力 ', style: TextStyle(fontSize: 12, color: _sub)),
        _gradeText(avg, size: 16),
      ]),
      const SizedBox(height: 6),
      AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth, h = c.maxHeight;
          return Stack(children: [
            Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CustomPaint(painter: _DiamondPainter()))),
            for (final e in _fieldPos.entries) _marker(e.key, Offset(e.value.dx * w, e.value.dy * h), w),
          ]);
        }),
      ),
      const SizedBox(height: 6),
      if (dh != null) _dhBox(dh),
      const SizedBox(height: 4),
      const Text('選んだ選手のあとにマーカーをタップすると、その位置へ（スタメン同士は守備位置を入替）。赤枠＝守備適性E以下', style: TextStyle(fontSize: 11, color: _sub)),
    ]);
  }

  Player? _playerAt(String pos) {
    final e = _cur.where((l) => l.position == pos).firstOrNull;
    if (e != null) return _p(e.playerId);
    if (pos == '投') return _sp; // DH制なら先発投手
    return null;
  }

  Widget _marker(String pos, Offset center, double w) {
    final p = _playerAt(pos);
    final mw = (w * 0.30).clamp(76.0, 104.0);
    const mh = 46.0;
    final apt = p == null ? 0 : fieldingAt(p, pos);
    final g = GradeUtils.getGrade(apt);
    final weak = p != null && apt < 40;
    final picked = p != null && _picked == p.id;
    return Positioned(
      left: center.dx - mw / 2,
      top: center.dy - mh / 2,
      width: mw,
      height: mh,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (_) => pos != '投' || !_dh,
        onAcceptWithDetails: (d) => _dropOnPosition(pos, d.data),
        builder: (context, cand, _) {
          final hi = cand.isNotEmpty;
          return GestureDetector(
            onTap: () => _tapPosition(pos),
            onDoubleTap: p == null ? null : () => openPlayerDetail(context, p, widget.appState, team, widget.onRosterChanged),
            child: Container(
              decoration: BoxDecoration(
                color: picked ? const Color(0xFF78350F) : (cand.isNotEmpty ? const Color(0xFF365314) : const Color(0xE60B1626)),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: picked ? _pickBorder : (hi ? const Color(0xFFC6F24E) : (weak ? Colors.redAccent : const Color(0xFF3A5578))), width: hi || weak || picked ? 2 : 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(posLabel(pos), style: const TextStyle(fontSize: 9.5, color: Color(0xFF8EA3BF), height: 1.1)),
                Text(p?.lastName ?? '−', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2)),
                if (p != null) Text('守 $g', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: weak ? Colors.redAccent : AppTheme.getGradeColor(g), height: 1.15)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _dhBox(LineupEntry dh) {
    final p = _p(dh.playerId);
    final picked = _picked == p.id;
    return DragTarget<String>(
      onAcceptWithDetails: (d) => _dropOnPosition('DH', d.data),
      builder: (context, cand, _) => InkWell(
        onTap: () => _tapPosition('DH'),
        onDoubleTap: _narrow ? null : () => openPlayerDetail(context, p, widget.appState, team, widget.onRosterChanged), // スマホはタップを即反応させる（詳細は下のパネルから）
        child: Container(
          decoration: BoxDecoration(
            color: picked || cand.isNotEmpty ? _pickBg : const Color(0xFFFAFAF9),
            border: Border.all(color: picked || cand.isNotEmpty ? _pickBorder : _line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const SizedBox(width: 10),
            const Text('指', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _sub)),
            Expanded(child: _nameCell(p, picked)),
          ]),
        ),
      ),
    );
  }

  // ───────── 控え ─────────

  Widget _benchCard() {
    final bench = _benchFielders;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${_lv == 1 ? '控え野手' : '${_lv}軍の控え野手'} ${bench.length}人', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
      Text(_narrow ? '長押しでスタメンへドラッグして交代' : 'スタメンへドラッグして交代', style: const TextStyle(fontSize: 11.5, color: _sub)),
      const SizedBox(height: 6),
      if (bench.isEmpty)
        Text(_lv == 1 ? 'ベンチ入りの控え野手がいません' : '控えの野手がいません', style: const TextStyle(color: _sub))
      else if (_narrow) ...[
        // スマホ：スタメンと同じ形（守備位置・打率・本・点・盗・名前・総合/体力）
        _statHeader(64),
        const Divider(height: 1, color: _ink),
        for (final p in bench)
          orderDraggable(
            longPress: true,
            data: p.id,
            feedback: Material(color: Colors.transparent, child: SizedBox(width: 320, child: Opacity(opacity: 0.85, child: _benchRow(p)))),
            childWhenDragging: Opacity(opacity: 0.3, child: _benchRow(p)),
            child: _tapArea(p, _benchRow(p)),
          ),
      ] else
        Container(
          decoration: BoxDecoration(border: Border.all(color: _line)),
          child: LayoutBuilder(builder: (context, c) {
            final cols = (c.maxWidth / 220).floor().clamp(1, 6);
            final w = c.maxWidth / cols;
            return Wrap(children: [
              for (final p in bench)
                SizedBox(
                  width: w,
                  child: orderDraggable(
                    longPress: _narrow,
                    data: p.id,
                    feedback: Material(color: Colors.transparent, child: SizedBox(width: 240, child: Opacity(opacity: 0.85, child: _benchTile(p)))),
                    childWhenDragging: Opacity(opacity: 0.3, child: _benchTile(p)),
                    child: _tapArea(p, _benchTile(p)),
                  ),
                ),
            ]);
          }),
        ),
    ]);
  }

  /// 控え野手の 1 行（スマホ）：スタメンの行と同じ並び
  Widget _benchRow(Player p) {
    final picked = _picked == p.id;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: picked ? _pickBg : Colors.white,
        border: Border(bottom: const BorderSide(color: _line), left: BorderSide(color: picked ? _pickBorder : Colors.transparent, width: 3)),
      ),
      child: Row(children: [
        const SizedBox(width: 18),
        _posCell(_shortPos(p), p),
        ..._nameCells(p),
        ..._valueCells(p),
      ]),
    );
  }

  String _shortPos(Player p) => const {'捕手': '捕', '一塁手': '一', '二塁手': '二', '三塁手': '三', '遊撃手': '遊', '左翼手': '左', '中堅手': '中', '右翼手': '右'}[p.mainPosition] ?? p.mainPosition;

  Widget _ageText(Player p) => Text(ageLine(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: Color(0xFF0F766E), height: 1.2));

  Widget _benchTile(Player p) {
    final s = _st(p);
    final picked = _picked == p.id;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: picked ? _pickBg : Colors.white,
        border: Border(right: const BorderSide(color: _line), bottom: const BorderSide(color: _line), left: BorderSide(color: picked ? _pickBorder : Colors.transparent, width: 3)),
      ),
      child: Row(children: [
        ConditionFace(level: p.conditionAt(widget.appState.currentDate), size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
              _injury(p),
            ]),
            Text('${p.mainPosition}　${_hand(p)}　${_avg(p)}　${s.homeRuns}本', style: const TextStyle(fontSize: 11, color: _sub)),
            if (_lv > 1) _ageText(p),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [_gradeText(p.ovr, size: 13), _energy(p, size: 11)]),
      ]),
    );
  }
}

class _DiamondPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF0E3B2A));
    final home = Offset(w * 0.5, h * 0.95);
    // 外野（扇形）
    final fan = Path()
      ..moveTo(home.dx, home.dy)
      ..lineTo(w * 0.02, h * 0.45)
      ..quadraticBezierTo(w * 0.5, -h * 0.12, w * 0.98, h * 0.45)
      ..close();
    canvas.drawPath(fan, Paint()..color = const Color(0xFF14563B));
    // 内野の土
    final dirt = Path()
      ..moveTo(home.dx, home.dy)
      ..lineTo(w * 0.80, h * 0.62)
      ..lineTo(w * 0.5, h * 0.36)
      ..lineTo(w * 0.20, h * 0.62)
      ..close();
    canvas.drawPath(dirt, Paint()..color = const Color(0xFFB7845A));
    final grass = Path()
      ..moveTo(home.dx, h * 0.88)
      ..lineTo(w * 0.70, h * 0.63)
      ..lineTo(w * 0.5, h * 0.44)
      ..lineTo(w * 0.30, h * 0.63)
      ..close();
    canvas.drawPath(grass, Paint()..color = const Color(0xFF1B6B48));
    canvas.drawCircle(Offset(w * 0.5, h * 0.66), w * 0.03, Paint()..color = const Color(0xFFB7845A));
    final line = Paint()
      ..color = const Color(0x99E8F5EC)
      ..strokeWidth = 1.5;
    canvas.drawLine(home, Offset(w * 0.02, h * 0.45), line);
    canvas.drawLine(home, Offset(w * 0.98, h * 0.45), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
