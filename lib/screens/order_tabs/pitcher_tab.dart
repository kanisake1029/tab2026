import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import 'order_shared.dart';
import 'lineup_tab.dart' show farmToManual, thirdToManual, thirdUsed;
import '../../engine/farm_engine.dart';
import '../../engine/growth_curve.dart';
import '../../widgets/condition_face.dart';
import '../../widgets/player_row.dart';

/// 投手（先発ローテ・勝利の方程式・中継ぎ）
///  入れ替えはドラッグだけ（スマホは長押しで掴む）。タップは「選んだ選手の能力」に表示するだけ
///  広い画面：左に先発・方程式、右に中継ぎ。狭い画面：縦に1列
class PitcherTab extends StatefulWidget {
  final Team team;
  final AppState appState;
  final VoidCallback onRosterChanged;
  final Map<String, Player> playerMap;
  /// 1＝1軍、2＝2軍、3＝3軍
  final int level;

  const PitcherTab({
    super.key,
    required this.team,
    required this.appState,
    required this.onRosterChanged,
    required this.playerMap,
    this.level = 1,
  });

  @override
  State<PitcherTab> createState() => _PitcherTabState();
}

const _ink = Color(0xFF1C1917);
const _sub = Color(0xFF78716C);
const _line = Color(0xFFE7E5E4);
const _pickBorder = Color(0xFFF59E0B);

class _PitcherTabState extends State<PitcherTab> {
  static const _farmCols = <(String, double)>[('年', 22), ('全盛', 40), ('成長', 34), ('登', 22), ('防御', 36)];

  Team get team => widget.team;
  String? _picked; // 「選んだ選手の能力」に表示中の投手
  bool _narrow = false;

  // 役割: 'rotation'（先発枠）/ 'pattern'（勝利の方程式3枠: 7回・8回・9回）
  List<String> _slots(String role) => role == 'rotation' ? team.rotation : team.winningPattern;

  Player? _p(String id) => id.isEmpty ? null : (widget.playerMap[id] ?? team.players.where((x) => x.id == id).firstOrNull);

  void _save() {
    widget.appState.updateAndSave();
    widget.onRosterChanged();
  }

  /// 選手をスロットに配置する。すでに別スロットにいる場合は入れ替える（空きなら元の枠を空ける）
  void _setPitcherRole(String playerId, String targetRole, int targetIndex) {
    setState(() {
      String oldRole = '';
      int oldIndex = -1;
      for (final r in ['rotation', 'pattern']) {
        final i = _slots(r).indexOf(playerId);
        if (i >= 0) { oldRole = r; oldIndex = i; }
      }
      final target = _slots(targetRole);
      final occupant = target[targetIndex];
      if (oldRole.isNotEmpty) {
        _slots(oldRole)[oldIndex] = occupant; // 入れ替え（occupant が空なら元の枠は空になる）
      }
      target[targetIndex] = playerId;
      team.manualBenchOut.remove(playerId);
      team.refreshActive26();
    });
    _save();
  }

  /// 枠をタップ：入っている投手の能力を表示するだけ（入れ替えはドラッグで行う）
  void _tapSlot(String role, int index) {
    final occupant = _slots(role)[index];
    if (occupant.isEmpty) return;
    _tapPlayer(occupant);
  }

  /// 投手をタップ：「選んだ選手の能力」に表示するだけ
  void _tapPlayer(String id) {
    final p = _p(id);
    if (p != null) selectedOrderPlayer.value = p;
    setState(() => _picked = id);
  }

  /// 2・3軍の先発ローテの人数（4〜12）
  void _changeFarmRotation(int delta) {
    setState(() {
      if (widget.level == 2) {
        team.farmRotationCount = (team.farmRotationCount + delta).clamp(Team.farmRotationMin, Team.farmRotationMax);
        if (team.farmRotation.length > team.farmRotationCount) team.farmRotation = team.farmRotation.sublist(0, team.farmRotationCount);
        team.farmRotationIndex %= team.farmRotationCount;
      } else {
        team.thirdRotationCount = (team.thirdRotationCount + delta).clamp(Team.farmRotationMin, Team.farmRotationMax);
        if (team.thirdRotation.length > team.thirdRotationCount) team.thirdRotation = team.thirdRotation.sublist(0, team.thirdRotationCount);
        team.thirdRotationIndex %= team.thirdRotationCount;
      }
    });
    _save();
  }

  void _changeRotation(int delta) {
    setState(() => team.setRotationCount(team.rotationCount + delta));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.level > 1) return _farmBuild();
    return LayoutBuilder(builder: (context, c) {
      _narrow = c.maxWidth < 700;
      final firstTeamPitchers = team.roster1G.map((id) => _p(id)).whereType<Player>().where((p) => p.canPitch).toList(); // 二刀流の野手も投手として起用できる
      final assigned = <String>{...team.activeRotation, ...team.winningPattern}..remove('');
      final relievers = firstTeamPitchers.where((p) => !assigned.contains(p.id)).toList()..sort(compareByUniform);

      final rotationCard = _section(
        title: '先発ローテ',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: '先発を1人減らす', visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: team.rotationCount > Team.minRotation ? () => _changeRotation(-1) : null),
          Text('${team.rotationCount}人', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          IconButton(tooltip: '先発を1人増やす', visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: team.rotationCount < Team.maxRotation ? () => _changeRotation(1) : null),
        ]),
        note: '日程順に登板。今日投げない先発${team.rotationCount - 1}人は自動でベンチ外（4〜9人）',
        children: [
          for (int i = 0; i < team.rotationCount; i++) _slot('rotation', i, _rotLabel(i), highlight: (i - team.rotationIndex + team.rotationCount) % team.rotationCount == 0),
        ],
      );
      final patternCard = _section(
        title: '勝利の方程式',
        note: '1〜3点リードのとき、上から7回・8回・9回に登板',
        children: [
          _slot('pattern', 0, '7回'),
          _slot('pattern', 1, '8回'),
          _slot('pattern', 2, '9回'),
        ],
      );
      final relieverCard = _section(
        title: '中継ぎ ${relievers.length}人',
        note: _narrow ? '長押しで枠へドラッグ（タップで能力を表示）' : '枠へドラッグ（タップで能力を表示）',
        children: [
          if (relievers.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('中継ぎがいません', style: TextStyle(color: _sub))),
          LayoutBuilder(builder: (context, cc) {
            final cols = (cc.maxWidth / 240).floor().clamp(1, 4);
            final w = cc.maxWidth / cols;
            return Wrap(children: [
              for (final p in relievers)
                SizedBox(
                  width: w,
                  child: orderDraggable(
                    longPress: _narrow,
                    data: p.id,
                    feedback: Material(color: Colors.transparent, child: SizedBox(width: 260, child: Opacity(opacity: 0.9, child: _pitcherRow(p, '', false)))),
                    childWhenDragging: Opacity(opacity: 0.3, child: _pitcherRow(p, '', false)),
                    child: _tapArea(p, _pitcherRow(p, '', _picked == p.id)),
                  ),
                ),
            ]);
          }),
        ],
      );

      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(_narrow ? 10 : 16, 12, _narrow ? 10 : 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_narrow) ...[
            rotationCard,
            const SizedBox(height: 14),
            patternCard,
            const SizedBox(height: 14),
            relieverCard,
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [rotationCard, const SizedBox(height: 14), patternCard])),
              const SizedBox(width: 16),
              Expanded(child: relieverCard),
            ]),
        ]),
      );
    });
  }

  // ───────── 2軍・3軍 ─────────

  /// 2・3軍の先発ローテの枠 i に投手を入れる（ほかの枠にいれば入れ替え）。「自分で組む」になる
  void _setFarmRotation(String id, int i) {
    final isFarm = widget.level == 2;
    if (isFarm) {
      farmToManual(team);
    } else {
      thirdToManual(team, widget.appState);
    }
    final r = isFarm ? team.farmRotation : team.thirdRotation;
    final count = isFarm ? team.farmRotationCount : team.thirdRotationCount;
    while (r.length < count) {
      r.add('');
    }
    final old = r.indexOf(id);
    if (old >= 0) r[old] = r[i];
    r[i] = id;
    _save();
    setState(() {});
  }

  Widget _farmSlot(int i, Player? p, String label, bool highlight) {
    Widget content(bool hovered) {
      if (p == null) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          decoration: BoxDecoration(color: hovered ? const Color(0xFFFFFBEB) : const Color(0xFFFAFAF9), border: const Border(bottom: BorderSide(color: _line))),
          child: Row(children: [
            SizedBox(width: 58, child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
            const Text('自動で決める（ドラッグで入れる）', style: TextStyle(color: _sub)),
          ]),
        );
      }
      final row = _pitcherRow(p, label, _picked == p.id, highlight: highlight);
      return hovered ? Container(foregroundDecoration: BoxDecoration(border: Border.all(color: _pickBorder, width: 2)), child: row) : row;
    }

    return DragTarget<String>(
      onAcceptWithDetails: (d) => _setFarmRotation(d.data, i),
      builder: (context, cand, _) {
        final tile = InkWell(onTap: p == null ? null : () => _tapPlayer(p.id), child: content(cand.isNotEmpty));
        if (p == null) return tile;
        return orderDraggable(
          longPress: _narrow,
          data: p.id,
          feedback: Material(color: Colors.transparent, child: SizedBox(width: 320, child: Opacity(opacity: 0.9, child: content(false)))),
          childWhenDragging: Opacity(opacity: 0.3, child: content(false)),
          child: tile,
        );
      },
    );
  }

  Widget _farmBuild() {
    return LayoutBuilder(builder: (context, c) {
      _narrow = c.maxWidth < 700;
      final isFarm = widget.level == 2;
      final used = isFarm ? const <String>{} : thirdUsed(team);
      final rot = isFarm
          ? FarmEngine.effectiveRotation(team)
          : widget.appState.effectiveThirdRotation(team, used: used);
      final rotCount = isFarm ? team.farmRotationCount : team.thirdRotationCount;
      final rotIdx = isFarm ? team.farmRotationIndex : team.thirdRotationIndex;
      final auto = isFarm ? team.farmAuto : team.thirdAuto;
      final n = rot.isEmpty ? 1 : rot.length;
      final next = rotIdx % n;
      final inRot = rot.where((e) => e.isNotEmpty).toSet();
      final relievers = (isFarm
              ? FarmEngine.farmPlayers(team)
              : team.players.where((p) => !team.roster1G.contains(p.id) && !used.contains(p.id)))
          .where((p) => p.isPitcher && !inRot.contains(p.id))
          .toList()
        ..sort((a, b) => b.ovr.compareTo(a.ovr));
      final lvName = isFarm ? '2軍' : '3軍';
      final left = [
        _section(
          title: '$lvNameの先発ローテ',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: '先発を1人減らす', visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: rotCount > Team.farmRotationMin ? () => _changeFarmRotation(-1) : null),
            Text('$rotCount人', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            IconButton(tooltip: '先発を1人増やす', visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: rotCount < Team.farmRotationMax ? () => _changeFarmRotation(1) : null),
          ]),
          note: '日程順に登板。${auto ? '今は自動で組んでいます。' : ''}入れ替えると「自分で組む」になります',
          children: [
            _farmHeader(withSlot: true),
            const Divider(height: 1, color: _ink),
            for (var i = 0; i < rot.length; i++) _farmSlot(i, _p(rot[i]), i == next ? '次回' : '${(i - next + n) % n}試合後', i == next),
          ],
        ),
      ];
      final right = [
        _section(
          title: '$lvNameの中継ぎ ${relievers.length}人',
          note: _narrow ? '長押しで先発の枠へドラッグ（タップで能力を表示）' : '先発の枠へドラッグ（タップで能力を表示）',
          children: [
            if (relievers.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('中継ぎがいません', style: TextStyle(color: _sub)))
            else ...[
              _farmHeader(withSlot: false),
              const Divider(height: 1, color: _ink),
              for (final p in relievers)
                orderDraggable(
                  longPress: _narrow,
                  data: p.id,
                  feedback: Material(color: Colors.transparent, child: SizedBox(width: 300, child: Opacity(opacity: 0.9, child: _pitcherRow(p, '', false)))),
                  childWhenDragging: Opacity(opacity: 0.3, child: _pitcherRow(p, '', false)),
                  child: _tapArea(p, _pitcherRow(p, '', _picked == p.id)),
                ),
            ],
          ],
        ),
      ];
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(_narrow ? 6 : 16, 12, _narrow ? 6 : 16, 24),
        child: _narrow
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...left, const SizedBox(height: 14), ...right])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: left)),
                const SizedBox(width: 16),
                Expanded(child: Column(children: right)),
              ]),
      );
    });
  }

  String _rotLabel(int i) {
    final order = (i - team.rotationIndex + team.rotationCount) % team.rotationCount;
    return order == 0 ? '次回' : '$order試合後';
  }

  Widget _section({required String title, String? note, Widget? trailing, required List<Widget> children}) => Container(
        padding: EdgeInsets.fromLTRB(_narrow ? 8 : 12, 10, _narrow ? 8 : 12, 10),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))), if (trailing != null) trailing]),
          if (note != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(note, style: const TextStyle(fontSize: 11.5, color: _sub))),
          ...children,
        ]),
      );

  Widget _tapArea(Player p, Widget child) => InkWell(
        onTap: () => _tapPlayer(p.id),
        onDoubleTap: _narrow ? null : () => openPlayerDetail(context, p, widget.appState, team, widget.onRosterChanged), // スマホはタップを即反応させる（詳細は下のパネルから）
        child: child,
      );

  /// 2・3軍投手の表見出し
  Widget _farmHeader({bool withSlot = false}) {
    const h = TextStyle(fontSize: 10.5, color: _sub);
    return Padding(
      padding: const EdgeInsets.fromLTRB(7, 4, 4, 2),
      child: Row(children: [
        if (withSlot) ...[const SizedBox(width: 44, child: Text('枠', style: h)), const SizedBox(width: 4)],
        const SizedBox(width: 18),
        const Expanded(child: Text('選手', style: h)),
        const SizedBox(width: 14),
        for (final c in _farmCols) SizedBox(width: c.$2, child: Text(c.$1, textAlign: TextAlign.right, style: h)),
      ]),
    );
  }

  /// 2・3軍投手の1行（打者と揃えて年齢・全盛期・成長率・登板・防御率を並べる）
  Widget _farmPitcherLine(Player p, PlayerStats s) {
    final (pa, pb) = GrowthCurve.primeRange(p);
    const st = TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()], color: Color(0xFF292524));
    return Row(children: [
      SizedBox(width: 16, child: Align(alignment: Alignment.centerLeft, child: ConditionFace(level: p.conditionAt(widget.appState.currentDate), size: 11))),
      const SizedBox(width: 2),
      Expanded(
        child: Row(children: [
          Flexible(child: Text(p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PlayerRow.ink))),
          PlayerRow.injury(p),
          if (p.energyRatio < 0.7) Padding(padding: const EdgeInsets.only(left: 2), child: PlayerRow.energy(p, size: 9)),
        ]),
      ),
      SizedBox(width: 14, child: Text(p.throws == 'L' ? '左' : '右', style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)))),
      SizedBox(width: 22, child: Align(alignment: Alignment.centerRight, child: Text('${p.age}', style: st))),
      SizedBox(width: 40, child: Align(alignment: Alignment.centerRight, child: Text('$pa-$pb', style: st.copyWith(color: const Color(0xFF0F766E))))),
      SizedBox(width: 34, child: Align(alignment: Alignment.centerRight, child: Text(p.growthRate.toStringAsFixed(2), style: st.copyWith(color: const Color(0xFF0F766E))))),
      SizedBox(width: 22, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text('${s.apps}', style: st))),
      SizedBox(width: 36, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(s.inningsPitched == 0 ? '-' : s.era.toStringAsFixed(2), style: st.copyWith(fontWeight: FontWeight.w700)))),
    ]);
  }

  /// 投手1人の行（共通の1行。先頭に役割のラベル、2行目は今季成績）
  Widget _pitcherRow(Player p, String label, bool picked, {bool highlight = false, Widget? trailing}) {
    final s = widget.level == 2 ? p.farmStats : (widget.level == 3 ? p.thirdStats : p.shownStats);
    return Container(
      constraints: widget.level > 1 ? const BoxConstraints(minHeight: 34) : null,
      padding: widget.level > 1 ? const EdgeInsets.symmetric(horizontal: 4, vertical: 3) : const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: BoxDecoration(
        color: picked ? PlayerRow.selBg : Colors.white,
        border: Border(bottom: const BorderSide(color: _line), left: BorderSide(color: picked ? PlayerRow.selBorder : Colors.transparent, width: 3)),
      ),
      child: Row(children: [
        if (label.isNotEmpty) ...[
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(color: highlight ? _ink : const Color(0xFFF5F5F4), borderRadius: BorderRadius.circular(4)),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: highlight ? Colors.white : _ink))),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: widget.level > 1
              ? _farmPitcherLine(p, s)
              : PitcherLine(p: p, s: s, date: widget.appState.currentDate, faceSize: 14),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget _slot(String role, int index, String label, {bool highlight = false}) {
    final id = _slots(role)[index];
    final p = _p(id);
    final picked = p != null && _picked == p.id;
    Widget content(bool hovered) {
      if (p == null) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          decoration: BoxDecoration(
            color: hovered ? const Color(0xFFFFFBEB) : const Color(0xFFFAFAF9),
            border: const Border(bottom: BorderSide(color: _line)),
          ),
          child: Row(children: [
            Container(
              width: 58,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFF5F5F4), borderRadius: BorderRadius.circular(4)),
              child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
            Text('空き枠（ドラッグで入れる）', style: const TextStyle(color: _sub)),
          ]),
        );
      }
      final row = _pitcherRow(p, label, picked, highlight: highlight);
      return hovered ? Container(foregroundDecoration: BoxDecoration(border: Border.all(color: _pickBorder, width: 2)), child: row) : row;
    }

    return DragTarget<String>(
      onAcceptWithDetails: (d) => _setPitcherRole(d.data, role, index),
      builder: (context, cand, _) {
        final tile = InkWell(
          onTap: () => _tapSlot(role, index),
          onDoubleTap: p == null ? null : () => openPlayerDetail(context, p, widget.appState, team, widget.onRosterChanged),
          child: content(cand.isNotEmpty),
        );
        if (p == null) return tile;
        return orderDraggable(
          longPress: _narrow,
          data: p.id,
          feedback: Material(color: Colors.transparent, child: SizedBox(width: 320, child: Opacity(opacity: 0.9, child: content(false)))),
          childWhenDragging: Opacity(opacity: 0.3, child: content(false)),
          child: tile,
        );
      },
    );
  }
}
