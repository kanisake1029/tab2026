import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import 'order_shared.dart';
import '../../widgets/player_row.dart';

/// ベンチ入り設定（1軍31人 → ベンチ入り26人）
///  - 今日投げない先発は自動でベンチ外（列1・ロック）
///  - 残りのベンチ外はユーザーが選ぶ（列2）。足りない分は控えの下位から自動で補う
///  - それ以外がベンチ入り（列3）
class GameRosterTab extends StatefulWidget {
  final Team team;
  final AppState appState;
  final VoidCallback onRosterChanged;
  final Map<String, Player> playerMap;

  const GameRosterTab({
    super.key,
    required this.team,
    required this.appState,
    required this.onRosterChanged,
    required this.playerMap,
  });

  @override
  State<GameRosterTab> createState() => _GameRosterTabState();
}

class _GameRosterTabState extends State<GameRosterTab> {
  Team get team => widget.team;

  Player _p(String id) => widget.playerMap[id] ?? team.players.firstWhere((x) => x.id == id, orElse: () => team.players.first);

  Set<String> get _protected => {
        ...team.lineup.map((l) => l.playerId),
        ...team.winningPattern.where((e) => e.isNotEmpty),
        if (team.todaysStarterId != null) team.todaysStarterId!,
      };

  int get _manualSlots => (team.benchOutNeeded - team.autoBenchOutRotation.length).clamp(0, 99);

  void _changed() {
    team.refreshActive26();
    widget.appState.updateAndSave();
    widget.onRosterChanged();
  }

  void _toManualOut(String id) {
    final msg = ScaffoldMessenger.of(context);
    if (team.activeRotation.contains(id)) {
      msg.showSnackBar(const SnackBar(content: Text('先発ローテの投手は自動で管理されます（投手タブで変更）')));
      return;
    }
    if (_protected.contains(id)) {
      msg.showSnackBar(const SnackBar(content: Text('スタメン・勝利の方程式・今日の先発はベンチ外にできません')));
      return;
    }
    if (team.manualBenchOut.contains(id)) return;
    setState(() {
      team.manualBenchOut.add(id);
      _changed();
    });
  }

  void _toBench(String id) {
    final msg = ScaffoldMessenger.of(context);
    if (team.autoBenchOutRotation.contains(id)) {
      msg.showSnackBar(const SnackBar(content: Text('今日投げない先発は自動でベンチ外です（投手タブで先発の人数を変えられます）')));
      return;
    }
    if (team.manualBenchOut.contains(id)) {
      setState(() {
        team.manualBenchOut.remove(id);
        _changed();
      });
      if (team.autoBenchOutFill.isNotEmpty) {
        msg.showSnackBar(const SnackBar(content: Text('ベンチ外が足りない分は控えの下位から自動で選ばれます')));
      }
      return;
    }
    if (team.autoBenchOutFill.contains(id)) {
      msg.showSnackBar(const SnackBar(content: Text('自動で選ばれた選手です（「自動」）。代わりにベンチ外にする選手を選ぶと戻せます')));
    }
  }

  Widget _tag(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      );

  bool _narrow = false;

  /// 選手1人の行。action を渡すと右端にボタン（ベンチ外にする／戻す）
  Widget _row(Player p, {List<Widget> tags = const [], (String, VoidCallback, Color)? action, bool locked = false, bool draggable = true}) {
    // 共通の1行（オーダー画面・補強画面などと同じ形）
    final trailing = locked
        ? const Icon(Icons.lock, size: 14, color: Colors.grey)
        : (action == null
            ? null
            : SizedBox(
                height: 30,
                child: OutlinedButton(
                  onPressed: action.$2,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), foregroundColor: action.$3, side: BorderSide(color: action.$3), visualDensity: VisualDensity.compact),
                  child: Text(action.$1, style: const TextStyle(fontSize: 12)),
                ),
              ));
    final content = PlayerRow(face: false, player: p, date: widget.appState.currentDate, tags: tags, trailing: trailing);
    final tap = InkWell(
      onTap: () => selectedOrderPlayer.value = p,
      onDoubleTap: () => openPlayerDetail(context, p, widget.appState, team, widget.onRosterChanged),
      child: content,
    );
    if (!draggable || _narrow) return tap;
    return Draggable<String>(
      data: p.id,
      feedback: Material(color: Colors.transparent, child: SizedBox(width: 280, child: Opacity(opacity: 0.9, child: content))),
      childWhenDragging: Opacity(opacity: 0.3, child: content),
      child: tap,
    );
  }

  Widget _section({required String title, required Color color, String? sub, required List<Widget> rows, void Function(String)? onAccept}) {
    Widget body(bool hovering) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: hovering ? const Color(0xFFFFFBEB) : Colors.white,
            border: Border.all(color: hovering ? const Color(0xFFF59E0B) : const Color(0xFFE7E5E4)),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
                if (sub != null) Text(sub, style: const TextStyle(fontSize: 11.5, color: Color(0xFF78716C))),
              ]),
            ),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(10), child: Text('なし', style: TextStyle(color: Colors.grey))),
            ...rows,
          ]),
        );
    if (onAccept == null || _narrow) return body(false);
    return DragTarget<String>(
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidate, rejected) => body(candidate.isNotEmpty),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _narrow = c.maxWidth < 760;
      team.refreshActive26();
      final protected = _protected;
      final today = team.todaysStarterId;
      final lineupIds = team.lineup.map((l) => l.playerId).toSet();
      final pattern = team.winningPattern.toSet();
      final resting = team.restingStarters;

      final autoRot = team.autoBenchOutRotation.map(_p).toList();
      final manualOut = team.roster1G.where((id) => !team.active26.contains(id) && !team.autoBenchOutRotation.contains(id)).map(_p).toList()..sort(compareByUniform);
      final bench = team.active26.map(_p).toList()..sort(compareByUniform);
      final need = team.benchOutNeeded;
      final remain = (_manualSlots - team.manualBenchOut.length).clamp(0, 99);
      final foreign = team.active26.where((id) => _p(id).foreignSlot).length;
      const canOut = true; // 必要な人数を超えても、控えを使わせないためにベンチ外にできる

      final header = Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDCE2EA))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('1軍${team.roster1G.length}人 → ベンチ入り${team.active26.length}人（ベンチ外 ${team.roster1G.length - team.active26.length}人・最低$need人）', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(
            '今日投げない先発${autoRot.length}人は自動でベンチ外。'
            '${_manualSlots == 0 ? 'ほかに選ぶ必要はありません。' : (remain == 0 ? '必要なベンチ外はそろっています。' : 'あと$remain人は選ぶ必要があります（選ばない分は控えの下位から自動で選びます）。')}'
            'ベンチ外は最低の人数より多く選べます（試合で自動で起用されないように）。ベンチの投手は6人まで残ります。',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
          ),
        ]),
      );

      final autoSec = _section(
        title: '自動ベンチ外（先発ローテ） ${autoRot.length}人',
        color: Colors.blueGrey,
        sub: '今日投げない先発。次回登板が近い順（投手タブで人数を変更）',
        rows: [for (final p in autoRot) _row(p, locked: true, draggable: false, tags: [_tag('${resting.indexOf(p.id) + 1}試合後', Colors.blueGrey)])],
      );
      final manualSec = _section(
        title: '手動ベンチ外 ${manualOut.length}人（必要 $_manualSlots人）',
        color: Colors.pinkAccent,
        sub: _manualSlots == 0 ? '今日は選ぶ必要がありません' : (_narrow ? 'ベンチ入りの「外す」で選ぶ' : 'ベンチ入りの「外す」、またはドラッグで選ぶ'),
        onAccept: _toManualOut,
        rows: [
          for (final p in manualOut)
            _row(p,
                tags: [
                  if (team.autoBenchOutFill.contains(p.id)) _tag('自動', Colors.orange),
                  if (team.manualBenchOut.contains(p.id)) _tag('手動', Colors.pinkAccent),
                ],
                action: team.manualBenchOut.contains(p.id) ? ('戻す', () => _toBench(p.id), Colors.blue) : null),
        ],
      );
      final benchSec = _section(
        title: 'ベンチ入り ${bench.length}/${Team.benchSize}人',
        color: bench.length == Team.benchSize ? Colors.blue : Colors.redAccent,
        sub: '外国人 $foreign/4人',
        onAccept: _toBench,
        rows: [
          for (final p in bench)
            _row(p,
                tags: [
                  if (p.id == today) _tag('先発', Colors.redAccent),
                  if (lineupIds.contains(p.id)) _tag('スタメン', Colors.blue),
                  if (pattern.contains(p.id)) _tag('方程式', Colors.pinkAccent),
                  if (resting.contains(p.id) && !protected.contains(p.id)) _tag('ロング', Colors.teal),
                ],
                action: (!protected.contains(p.id) && !team.activeRotation.contains(p.id) && canOut) ? ('外す', () => _toManualOut(p.id), Colors.pinkAccent) : null),
        ],
      );

      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(_narrow ? 10 : 16, 12, _narrow ? 10 : 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          if (_narrow) ...[autoSec, manualSec, benchSec]
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [autoSec, manualSec])),
              const SizedBox(width: 14),
              Expanded(child: benchSec),
            ]),
        ]),
      );
    });
  }
}
