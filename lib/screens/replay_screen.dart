import 'dart:math';
import 'package:flutter/material.dart';
import '../db/app_database.dart';
import '../engine/match_simulator.dart';
import '../widgets/live_game_widgets.dart';

/// 試合を振り返る（アニメ再生）。保存してある1球ごとの記録（コース・球種・結果・打球の落下点）から、
/// 投球と打球を作り直して、試合画面と同じ部品で再生する。今季の自球団の試合が対象
class ReplayScreen extends StatefulWidget {
  final List<PitchRow> rows;
  final String title;
  const ReplayScreen({super.key, required this.rows, required this.title});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> with SingleTickerProviderStateMixin {
  late final List<PitchEvent> _events = [for (final r in widget.rows) _toEvent(r)];
  late final AnimationController _anim = AnimationController(vsync: this);
  int _i = 0;          // いま再生している球
  bool _playing = false;
  double _speed = 1.0;

  static const _navy = Color(0xFF0B1626);
  static const _muted = Color(0xFF8A9BB4);

  /// 保存した1球を、アニメ用の投球・打球に作り直す（打球は本塁から落下点への放物線）
  static PitchEvent _toEvent(PitchRow r) {
    final e = PitchEvent(
      paIndex: r.paIndex, pitchNo: r.pitchNo, battingHome: r.battingHome, batter: r.batter, batterHand: r.batterHand,
      pitcher: r.pitcher, pitchName: r.pitchName, speed: r.speed, x: r.x, z: r.z, inZone: r.inZone, balls: r.balls, strikes: r.strikes,
    );
    e.result = r.result;
    e.contact = r.contact;
    e.landX = r.landX;
    e.landY = r.landY;
    e.launch = r.launch;
    e.fielder = r.fielder;
    e.outcome = r.outcome;
    e.playCode = r.playCode;
    e.breakDX = r.breakDX;
    e.breakDY = r.breakDY;
    if (r.landX != null && r.landY != null) {
      final lx = r.landX!, ly = r.landY!;
      final dist = sqrt(lx * lx + ly * ly);
      final launch = (r.launch ?? 10).clamp(-10.0, 70.0);
      final peak = launch < 8 ? 0.6 : (dist * tan(launch * pi / 180) / 4).clamp(1.0, 45.0);
      const n = 20;
      e.path = [
        for (var k = 0; k <= n; k++)
          () {
            final u = k / n;
            return [lx * u, ly * u, max(0.0, 1.0 + 4 * peak * u * (1 - u) - u)];
          }(),
      ];
      e.flightTime = (dist / (launch < 8 ? 32.0 : 26.0)).clamp(0.6, 6.0);
    }
    e.desc = _describe(e);
    return e;
  }

  static String _describe(PitchEvent e) {
    final res = e.outcome.isNotEmpty ? e.outcome : e.result;
    return '${e.pitchNo}球目 ${e.speed.round()}km/h ${e.pitchName}　$res';
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  PitchEvent get _cur => _events[_i];

  Future<void> _playFrom(int i) async {
    if (i >= _events.length) {
      setState(() => _playing = false);
      return;
    }
    setState(() => _i = i);
    final total = PlayTiming.total(_cur);
    _anim.duration = Duration(milliseconds: (total * 1000 / _speed).round());
    await _anim.forward(from: 0);
    if (!mounted || !_playing) return;
    await Future.delayed(Duration(milliseconds: (250 / _speed).round()));
    if (mounted && _playing) _playFrom(i + 1);
  }

  void _toggle() {
    if (_playing) {
      setState(() => _playing = false);
      _anim.stop();
    } else {
      setState(() => _playing = true);
      _playFrom(_i >= _events.length - 1 ? 0 : _i);
    }
  }

  void _jumpPa(int dir) {
    final pa = _cur.paIndex;
    var j = _i;
    if (dir > 0) {
      while (j < _events.length && _events[j].paIndex == pa) {
        j++;
      }
    } else {
      while (j > 0 && _events[j].paIndex == pa) {
        j--;
      }
      final prevPa = _events[j].paIndex;
      while (j > 0 && _events[j - 1].paIndex == prevPa) {
        j--;
      }
    }
    j = j.clamp(0, _events.length - 1);
    _anim.stop();
    setState(() {
      _i = j;
      _anim.value = 1;
    });
    if (_playing) _playFrom(j);
  }

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(widget.title)), body: const Center(child: Text('この試合の1球ごとの記録はありません')));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF07101C),
      appBar: AppBar(backgroundColor: _navy, foregroundColor: Colors.white, title: Text(widget.title, style: const TextStyle(fontSize: 15))),
      body: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final cur = _cur;
          final t = _anim.value * PlayTiming.total(cur);
          final paEvents = _events.where((e) => e.paIndex == cur.paIndex && e.pitchNo < cur.pitchNo).toList();
          final recent = _events.where((e) => e.paIndex >= cur.paIndex - 3 && e.paIndex <= cur.paIndex && e.landX != null && _events.indexOf(e) <= _i).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: _navy,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${cur.battingHome ? '裏' : '表'}の攻撃　第${cur.paIndex + 1}打席　${cur.balls}ボール${cur.strikes}ストライク', style: const TextStyle(color: _muted, fontSize: 12)),
                Text('${cur.pitcher} → ${cur.batter}（${cur.batterHand == 'L' ? '左' : (cur.batterHand == 'S' ? '両' : '右')}打）', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                Text(cur.desc, style: const TextStyle(color: Color(0xFFC6F24E), fontSize: 13)),
              ]),
            ),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 3, child: FieldPlayView(event: cur.path.isEmpty ? null : cur, t: t, recent: recent)),
                Expanded(flex: 2, child: PitchView(paEvents: paEvents, animating: cur, t: t, batterHand: cur.batterHand)),
              ]),
            ),
            Container(
              color: _navy,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(children: [
                Slider(
                  value: _i.toDouble(),
                  min: 0,
                  max: (_events.length - 1).toDouble(),
                  onChanged: (v) {
                    _anim.stop();
                    setState(() {
                      _i = v.round();
                      _anim.value = 1;
                      _playing = false;
                    });
                  },
                ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  IconButton(onPressed: () => _jumpPa(-1), icon: const Icon(Icons.skip_previous, color: Colors.white), tooltip: '前の打席'),
                  IconButton(onPressed: _toggle, icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle, color: Colors.white, size: 40), tooltip: _playing ? '一時停止' : '再生'),
                  IconButton(onPressed: () => _jumpPa(1), icon: const Icon(Icons.skip_next, color: Colors.white), tooltip: '次の打席'),
                  TextButton(
                    onPressed: () => setState(() => _speed = _speed >= 4 ? 1 : _speed * 2),
                    child: Text('×${_speed.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ]),
                Text('${_i + 1} / ${_events.length}球', style: const TextStyle(color: _muted, fontSize: 11)),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
