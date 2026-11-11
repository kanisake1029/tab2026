import 'dart:math';
import 'package:flutter/material.dart';

/// ドラフトの抽選（1位・1.5位・2.5位）：くじの入った封筒を選び、一斉に開封する。
///  tickets：球団の略称 → くじの本数（1位は各1本）。mine：自球団の略称。winner：交渉権を得た球団（結果は先に決まっている。どの封筒を選んでも確率は同じ）
Future<void> showDraftLottery(BuildContext context, {required String title, required String player, required Map<String, int> tickets, required String mine, required String winner}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog.fullscreen(child: _Lottery(title: title, player: player, tickets: tickets, mine: mine, winner: winner)),
  );
}

class _Lottery extends StatefulWidget {
  final String title, player, mine, winner;
  final Map<String, int> tickets;
  const _Lottery({required this.title, required this.player, required this.tickets, required this.mine, required this.winner});

  @override
  State<_Lottery> createState() => _LotteryState();
}

class _LotteryState extends State<_Lottery> with TickerProviderStateMixin {
  static const _navy = Color(0xFF0B1626), _lime = Color(0xFFC6F24E), _gold = Color(0xFFF5C542);
  late final int n = widget.tickets.values.fold(0, (a, b) => a + b);
  late final int myCount = widget.tickets[widget.mine] ?? 0;
  final List<int> _picked = [];
  List<String>? _owner; // 封筒ごとの球団（選び終わってから決まる）
  int _win = -1; // 当たりの封筒
  bool _opened = false;
  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void dispose() {
    _flip.dispose();
    _burst.dispose();
    super.dispose();
  }

  bool get _choosing => _picked.length < myCount;

  void _tap(int i) {
    if (!_choosing || _picked.contains(i)) return;
    setState(() => _picked.add(i));
    if (!_choosing) _assign();
  }

  /// 自球団の封筒が決まったら、残りをほかの球団に配り、当たりの封筒を決める
  void _assign() {
    final r = Random();
    final owner = List<String>.filled(n, '');
    for (final i in _picked) {
      owner[i] = widget.mine;
    }
    final rest = [for (var i = 0; i < n; i++) if (!_picked.contains(i)) i]..shuffle(r);
    var k = 0;
    widget.tickets.forEach((t, c) {
      if (t == widget.mine) return;
      for (var j = 0; j < c; j++) {
        owner[rest[k++]] = t;
      }
    });
    final cand = [for (var i = 0; i < n; i++) if (owner[i] == widget.winner) i];
    setState(() {
      _owner = owner;
      _win = cand[r.nextInt(cand.length)];
    });
  }

  Future<void> _open() async {
    setState(() => _opened = true);
    await _flip.forward();
    await _burst.forward();
    if (mounted) setState(() {}); // 「次へ」を押せるようにする
  }

  @override
  Widget build(BuildContext context) {
    final mineWon = widget.winner == widget.mine;
    return Scaffold(
      backgroundColor: _navy,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 12),
          Text(widget.title, style: const TextStyle(color: _lime, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(widget.player, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('抽選：${widget.tickets.entries.map((e) => '${e.key}${e.value > 1 ? '×${e.value}' : ''}').join('・')}（くじ$n本）', style: const TextStyle(color: Color(0xFF8EA3BF), fontSize: 12.5)),
          const SizedBox(height: 14),
          Text(
            _opened ? '' : (_choosing ? '封筒を選んでください（あと${myCount - _picked.length}つ）' : '全球団が選び終わりました。一斉に開封します'),
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Center(
              child: Wrap(spacing: 14, runSpacing: 14, alignment: WrapAlignment.center, children: [for (var i = 0; i < n; i++) _envelope(i)]),
            ),
          ),
          // 結果のバナー
          AnimatedBuilder(
            animation: _burst,
            builder: (_, __) {
              final t = Curves.elasticOut.transform(_burst.value.clamp(0.0, 1.0));
              if (_burst.value == 0) return const SizedBox(height: 90);
              return SizedBox(
                height: 90,
                child: Center(
                  child: Transform.scale(
                    scale: 0.4 + 0.6 * t,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                      decoration: BoxDecoration(
                        color: mineWon ? _gold : const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: mineWon ? [BoxShadow(color: _gold.withValues(alpha: 0.6 * _burst.value), blurRadius: 30 * _burst.value, spreadRadius: 6 * _burst.value)] : null,
                      ),
                      child: Text(
                        mineWon ? '交渉権獲得！' : '${widget.winner}が交渉権獲得',
                        style: TextStyle(color: mineWon ? _navy : Colors.white, fontSize: mineWon ? 30 : 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: _navy, textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                onPressed: _owner == null ? null : (_opened ? (_burst.isCompleted ? () => Navigator.pop(context) : null) : _open),
                child: Text(_opened ? '次へ' : '一斉に開封'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _envelope(int i) {
    final mine = _picked.contains(i);
    final owner = _owner?[i];
    return GestureDetector(
      onTap: () => _tap(i),
      child: AnimatedBuilder(
        animation: _flip,
        builder: (_, __) {
          // 開封：封筒が縦に回って、中のくじが見える
          final a = _flip.value * pi;
          final showInside = _flip.value > 0.5;
          final win = i == _win;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateX(showInside ? a - pi : a),
              child: Container(
                width: 78,
                height: 104,
                decoration: BoxDecoration(
                  color: showInside ? (win ? _gold : Colors.white) : (mine ? const Color(0xFFFDE68A) : const Color(0xFFF1EBDD)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: mine ? _lime : const Color(0xFFB8A98A), width: mine ? 3 : 1.5),
                ),
                child: showInside
                    ? Center(
                        child: Text(win ? '交渉権\n確定' : '', textAlign: TextAlign.center, style: const TextStyle(color: _navy, fontSize: 16, fontWeight: FontWeight.w900, height: 1.2)),
                      )
                    : CustomPaint(painter: _FlapPainter(), child: const SizedBox.expand()),
              ),
            ),
            const SizedBox(height: 4),
            Text(owner ?? (mine ? widget.mine : ''), style: TextStyle(color: owner == widget.mine || mine ? _lime : const Color(0xFF8EA3BF), fontSize: 12, fontWeight: FontWeight.w800)),
          ]);
        },
      ),
    );
  }
}

/// 封筒のふたの線
class _FlapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = const Color(0xFFB8A98A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width / 2, s.height * 0.42)
      ..lineTo(s.width, 0);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
