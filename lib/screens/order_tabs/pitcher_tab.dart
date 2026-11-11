import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import 'order_shared.dart';
import 'lineup_tab.dart' show farmToManual, thirdUsed, ageLine;
import '../../engine/farm_engine.dart';
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

  /// 2軍の先発ローテの人数（4〜12）
  void _changeFarmRotation(int delta) {
    setState(() {
      team.farmRotationCount = (team.farmRotationCount + delta).clamp(Team.farmRotationMin, Team.farmRotationMax);
      if (team.farmRotation.length > team.farmRotationCount) team.farmRotation = team.farmRotation.sublist(0, team.farmRotationCount);
      team.farmRotationIndex %= team.farmRotationCount;
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

  /// 2軍の先発ローテの枠 i に投手を入れる（ほかの枠にいれば入れ替え）。「自分で組む」になる
  void _setFarmRotation(String id, int i) {
    farmToManual(team);
    final r = team.farmRotation;
    while (r.length < team.farmRotationCount) {
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
      final List<Widget> left, right;
      if (widget.level == 2) {
        final rot = FarmEngine.effectiveRotation(team);
        final n = rot.isEmpty ? 1 : rot.length;
        final next = team.farmRotationIndex % n;
        final inRot = rot.where((e) => e.isNotEmpty).toSet();
        final relievers = FarmEngine.farmPlayers(team).where((p) => p.isPitcher && !inRot.contains(p.id)).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
        left = [
          _section(
            title: '2軍の先発ローテ',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: '先発を1人減らす', visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline), onPressed: team.farmRotationCount > Team.farmRotationMin ? () => _changeFarmRotation(-1) : null),
              Text('${team.farmRotationCount}人', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              IconButton(tooltip: '先発を1人増やす', visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline), onPressed: team.farmRotationCount < Team.farmRotationMax ? () => _changeFarmRotation(1) : null),
            ]),
            note: '日程順に登板。${team.farmAuto ? '今は自動で組んでいます。' : ''}入れ替えると「自分で組む」になります',
            children: [
              for (var i = 0; i < rot.length; i++) _farmSlot(i, _p(rot[i]), i == next ? '次回' : '${(i - next + n) % n}試合後', i == next),
            ],
          ),
        ];
        right = [
          _section(
            title: '2軍の中継ぎ ${relievers.length}人',
            note: _narrow ? '長押しで先発の枠へドラッグ（タップで能力を表示）' : '先発の枠へドラッグ（タップで能力を表示）',
            children: [
              if (relievers.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('中継ぎがいません', style: TextStyle(color: _sub))),
              for (final p in relievers)
                orderDraggable(
                  longPress: _narrow,
                  data: p.id,
                  feedback: Material(color: Colors.transparent, child: SizedBox(width: 300, child: Opacity(opacity: 0.9, child: _pitcherRow(p, '', false)))),
                  childWhenDragging: Opacity(opacity: 0.3, child: _pitcherRow(p, '', false)),
                  child: _tapArea(p, _pitcherRow(p, '', _picked == p.id)),
                ),
            ],
          ),
        ];
      } else {
        final used = thirdUsed(team);
        final order = widget.appState.thirdOrder(team, used: used);
        final planned = order?.$2 ?? const <Player>[];
        final others = team.players.where((p) => p.isPitcher && !team.roster1G.contains(p.id) && !used.contains(p.id) && !planned.contains(p)).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
        Widget prio(Player p) => Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('優先', style: TextStyle(fontSize: 10.5, color: _sub)),
              Switch(
                value: team.thirdPriority.contains(p.id),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) {
                  if (v) {
                    team.thirdPriority.add(p.id);
                  } else {
                    team.thirdPriority.remove(p.id);
                  }
                  _save();
                  setState(() {});
                },
              ),
            ]);
        left = [
          _section(
            title: '次の3軍戦の登板予定',
            note: '3回ずつ。投手は3軍監督が選びます（「優先」の投手を先に使います）',
            children: [
              if (order == null) const Padding(padding: EdgeInsets.all(8), child: Text('投手がいないため、3軍戦は組めません', style: TextStyle(color: _sub))),
              for (var i = 0; i < planned.length; i++) _tapArea(planned[i], _pitcherRow(planned[i], '${i * 3 + 1}〜${i * 3 + 3}回', _picked == planned[i].id, highlight: i == 0, trailing: prio(planned[i]))),
            ],
          ),
        ];
        right = [
          _section(
            title: '3軍の投手 ${others.length}人',
            note: '「優先」にすると、3軍監督より先に登板させます',
            children: [
              if (others.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('ほかの投手はいません', style: TextStyle(color: _sub))),
              for (final p in others) _tapArea(p, _pitcherRow(p, '', _picked == p.id, trailing: prio(p))),
            ],
          ),
        ];
      }
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(_narrow ? 10 : 16, 12, _narrow ? 10 : 16, 24),
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
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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

  /// 投手1人の行（共通の1行。先頭に役割のラベル、2行目は今季成績）
  Widget _pitcherRow(Player p, String label, bool picked, {bool highlight = false, Widget? trailing}) {
    final s = widget.level == 2 ? p.farmStats : (widget.level == 3 ? p.thirdStats : p.shownStats);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            PitcherLine(p: p, s: s, date: widget.appState.currentDate, faceSize: widget.level > 1 ? 11 : 14),
            if (widget.level > 1) Padding(padding: const EdgeInsets.only(left: 20), child: Text(ageLine(p), style: const TextStyle(fontSize: 9.5, color: Color(0xFF0F766E)))),
          ]),
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
