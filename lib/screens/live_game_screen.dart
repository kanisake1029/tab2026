import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/farm_engine.dart';
import '../engine/pitch_catalog.dart';
import '../engine/match_simulator.dart';
import '../engine/commentary.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../models/stadium.dart';
import '../utils/schedule_generator.dart';
import '../widgets/live_game_widgets.dart';
import '../widgets/player_row.dart';
import '../widgets/player_detail_dialog.dart' show showPlayerDetail;
import '../engine/matchup_book.dart';
import '../engine/scorer_brief.dart';
import '../utils/app_theme.dart';
import '../utils/grade_utils.dart';
import '../utils/standings.dart' show teamColor;
import '../widgets/condition_face.dart';

/// 自チームの試合を進める画面。
/// - 簡易采配（manage=false）: 「交代」（代打・代走・継投・守備交代）のみ。1人ずつ進める
/// - フル采配（manage=true）: 交代に加えて
///     攻撃時 = 打撃采配・走塁采配 / 守備時 = 投手采配・守備采配
///     「1球ずつ」「1人ずつ」を切り替えられる。1球ずつでは 待て（攻撃）・外せ（守備）を指示できる。
///     1人ずつでも、2ストライクからのバント（スリーバントか強攻か）などの判断の場面では止まる。
/// 閉じると結果（MatchResult）を返す。
class LiveGameScreen extends StatefulWidget {
  final Match match;
  final Team homeTeam;
  final Team awayTeam;
  final String myTeamId;
  final bool manage;
  final bool clutch; // 終盤接戦のみ采配：6回までは自動で進め、7回以降の接戦（3点差以内）か得点圏に走者がいる場面だけ止まる
  final dynamic appState; // 選手の詳細を開くため（日付・球団の一覧）

  const LiveGameScreen({super.key, required this.match, required this.homeTeam, required this.awayTeam, required this.myTeamId, required this.manage, this.clutch = false, this.appState});

  @override
  State<LiveGameScreen> createState() => _LiveGameScreenState();
}

class _Opt<T> {
  final T value;
  final String label;
  final String desc;
  final bool enabled;
  const _Opt(this.value, this.label, this.desc, {this.enabled = true});
}

class _LiveGameScreenState extends State<LiveGameScreen> with SingleTickerProviderStateMixin {
  final MatchSimulator _sim = MatchSimulator();
  late final GameSession _s;
  late final bool _myHome;
  final ScrollController _logScroll = ScrollController();

  // ---- 一球速報の実況（試合の記録と1球ごとの場面から作る） ----
  late final Commentator _cm = Commentator(widget.match.date.millisecondsSinceEpoch);
  final List<LiveLine> _live = [];
  int _logPos = 0, _evPos = 0, _introPa = -1;
  final Map<int, PitchEvent> _evAt = {};
  (int, String)? _pendingPa; // 打者紹介の行（打順・投手）
  static final _paRe = RegExp(r'^(.+?) (先発|救援) (.+?) vs (.+) (\d+)番 (.+)$');
  static final _innRe = RegExp(r'^【(\d+)回(表|裏)');

  void _syncLive() {
    final evs = _s.pitchEvents;
    while (_evPos < evs.length && evs[_evPos].logIndex >= 0) {
      _evAt[evs[_evPos].logIndex] = evs[_evPos];
      _evPos++;
    }
    final log = _s.playByPlay;
    while (_logPos < log.length) {
      final i = _logPos, line = log[i];
      final e = _evAt[i];
      if (e != null) {
        final offense = e.top ? widget.awayTeam : widget.homeTeam, defense = e.top ? widget.homeTeam : widget.awayTeam;
        if (e.paIndex != _introPa) {
          _introPa = e.paIndex;
          final order = [..._s.homeOrder, ..._s.awayOrder];
          final b = order.where((p) => p.registeredName == e.batter).firstOrNull;
          final hand = b == null ? '' : (b.bats == 'L' ? '左打' : (b.bats == 'S' ? '両打' : '右打'));
          _live.addAll(_cm.paIntro(e, order: _pendingPa?.$1 ?? 0, hand: hand, pitcher: _pendingPa?.$2 ?? e.pitcher));
        }
        _live.addAll(_cm.pitch(e, offense: _shortName(offense), defense: _shortName(defense)));
      } else if (_innRe.hasMatch(line)) {
        final m = _innRe.firstMatch(line)!;
        final top = m.group(2) == '表';
        _live.add(LiveLine('${m.group(1)}回${top ? '表' : '裏'}　${_shortName(top ? widget.awayTeam : widget.homeTeam)}の攻撃', 'inning'));
      } else if (_paRe.hasMatch(line)) {
        final m = _paRe.firstMatch(line)!;
        _pendingPa = (int.parse(m.group(5)!), m.group(3)!);
      } else if (RegExp(r'^\d+球目').hasMatch(line)) {
        _live.add(LiveLine(line.replaceAll(RegExp(r' \[.*\]$'), ''), 'pitch'));
      } else {
        _live.add(LiveLine(line.replaceAll('【', '').replaceAll('】', '　'), 'note'));
      }
      _logPos++;
    }
  }

  String _shortName(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;

  // 次の打席（1球ずつなら次の1球）に適用する采配
  BatTactic _bat = BatTactic.none;
  RunTactic _run = RunTactic.none;
  PitchTactic _pitch = PitchTactic.none;
  FieldTactic _field = FieldTactic.none;
  int? _col;
  String _tacTab = ''; // スマホの采配欄で開いている分類
  int? _row;
  String? _pitchName;

  bool _perPitch = false; // true=1球ずつ / false=1人ずつ

  // ---- アニメーション ----
  late final AnimationController _anim;
  final List<PitchEvent> _queue = [];
  PitchEvent? _cur;
  double _speed = 1.0;
  int _seen = 0;

  // アニメーション中はスコアボードを打席前の状態で止めておく
  MatchState? _frozen;
  int _fAwayHits = 0, _fHomeHits = 0;
  void _freeze() {
    _frozen = _st.copy();
    _fAwayHits = _s.awayHits;
    _fHomeHits = _s.homeHits;
  }

  // 表示する試合状態（アニメ中は止めた状態に、投げている球のカウントを反映）
  MatchState get _view {
    final f = _frozen;
    if (f == null) return _st;
    final c = _cur;
    if (c != null) {
      f.balls = c.balls;
      f.strikes = c.strikes;
    }
    return f;
  }

  @override
  void initState() {
    super.initState();
    _myHome = widget.homeTeam.id == widget.myTeamId;
    _s = _sim.startGame(widget.match, widget.homeTeam, widget.awayTeam);
    _s.userTeamId = widget.myTeamId; // 相手側だけ CPU 監督の作戦（シフト・バント・盗塁など）を使う
    _anim = AnimationController(vsync: this);
    _prepareNext();
    if (widget.clutch) WidgetsBinding.instance.addPostFrameCallback((_) => _clutchSkip());
    _loadScout();
  }

  // ───────── スコアラー（今季の自チームの試合の 1 球ごとの記録 ＋ この試合の 1 球）─────────
  List<ScoutPitch> _scout = [];
  String _scoutKey = '', _scoutText = '';

  Future<void> _loadScout() async {
    final app = widget.appState;
    if (app == null) return;
    try {
      final rows = await app.db.loadSeasonPitches(app.startYear);
      final names = {for (final p in [...widget.homeTeam.players, ...widget.awayTeam.players]) p.registeredName};
      _scout = [
        for (final r in rows)
          if (names.contains(r.pitcher) || names.contains(r.batter))
            ScoutPitch(pitcher: r.pitcher, batter: r.batter, hand: r.batterHand, pitch: r.pitchName, result: r.result, rawX: r.x, z: r.z, pitchNo: r.pitchNo, balls: r.balls, strikes: r.strikes, landX: r.landX, landY: r.landY),
      ];
      if (mounted) setState(() => _scoutKey = '');
    } catch (_) {}
  }

  /// いまの場面の助言（攻撃中は相手投手の配球、守備中は相手打者の傾向）
  String _scoutLine() {
    if (_finished) return '';
    final pitcher = _st.isTop ? _s.homePitcher : _s.awayPitcher;
    final order = _st.isTop ? _s.awayOrder : _s.homeOrder;
    if (order.isEmpty) return '';
    final batter = order[(_st.isTop ? _s.awayBatterIndex : _s.homeBatterIndex) % order.length];
    final key = '${_myBatting}|${pitcher.id}|${batter.id}|${_s.pitchEvents.length ~/ 10}|${_scout.length}';
    if (key == _scoutKey) return _scoutText;
    final live = [
      for (final e in _s.pitchEvents)
        ScoutPitch(pitcher: e.pitcher, batter: e.batter, hand: e.batterHand, pitch: e.pitchName, result: e.result, rawX: e.x, z: e.z, pitchNo: e.pitchNo, balls: e.balls, strikes: e.strikes, landX: e.landX, landY: e.landY),
    ];
    final all = [..._scout, ...live];
    _scoutKey = key;
    _scoutText = _myBatting ? ScorerBrief.pitcher(all, pitcher) : ScorerBrief.batter(all, batter);
    return _scoutText;
  }

  /// 勝負どころ：7回以降で、点差が3点以内か、得点圏に走者がいる
  bool get _clutchScene => _st.inning >= 7 && ((_st.homeScore - _st.awayScore).abs() <= 3 || _st.runner2B != null || _st.runner3B != null);

  /// 終盤接戦のみ采配：勝負どころでない間は、自チームの交代も CPU 任せで 1 打席ずつ一気に進める
  void _clutchSkip() {
    if (!widget.clutch || !mounted || _finished || _s.inPlateAppearance || _clutchScene) return;
    _skipAnimation();
    setState(() {
      while (!_sim.isFinished(_s) && !_clutchScene) {
        _sim.autoManage(_s);
        _sim.stepPlateAppearance(_s);
      }
      _clearPlan();
      if (!_finished) _prepareNext();
      _seen = _s.pitchEvents.length;
      _queue.clear();
      _cur = null;
    });
    _scrollLog();
    if (!_finished) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text('勝負どころ：${_st.inning}回${_st.isTop ? '表' : '裏'}　ここから采配できます')));
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  MatchState get _st => _s.state;
  bool get _finished => _sim.isFinished(_s) && !_s.inPlateAppearance;
  // 自チームが攻撃中か（表=アウェイ攻撃）
  bool get _myBatting => _st.isTop ? !_myHome : _myHome;
  bool get _animating => _anim.isAnimating;

  /// 次の打席の前に、CPU側の継投だけ自動で行う
  void _prepareNext() {
    if (_finished || _s.inPlateAppearance) return;
    final defendingHome = _st.isTop;
    final cpuDefends = defendingHome != _myHome;
    if (cpuDefends) {
      _sim.autoDefenseSubs(_s, defendingHome); // 相手の守備固め
      _sim.autoPitching(_s, defendingHome);
      _sim.prepareCpuDefense(_s); // 相手の守備位置を打席の前に決めて見せる（シフトの逆を突けるように）
    } else {
      _sim.autoOffenseSubs(_s, !defendingHome); // 相手の代打・代走
    }
  }

  void _clearPlan() {
    _bat = BatTactic.none;
    _run = RunTactic.none;
    _pitch = PitchTactic.none;
    _field = FieldTactic.none;
    _col = null;
    _row = null;
    _pitchName = null;
  }

  AtBatPlan? _plan() {
    if (!widget.manage) return null; // 観戦：自球団も CPU 監督の采配
    return AtBatPlan(bat: _myBatting ? _bat : BatTactic.none, run: _myBatting ? _run : RunTactic.none, pitch: _myBatting ? PitchTactic.none : _pitch, field: _myBatting ? FieldTactic.none : _field, targetCol: _myBatting ? null : _col, targetRow: _myBatting ? null : _row, pitchName: _myBatting ? null : _pitchName);
  }

  // ---------------- 進行 ----------------

  /// アニメーションを飛ばして最新の状態にする
  void _skipAnimation() {
    if (_queue.isNotEmpty) _cur = _queue.last;
    _queue.clear();
    _anim.stop();
    _anim.value = 1.0;
    _frozen = null;
  }

  void _enqueueNew() {
    final evs = _s.pitchEvents;
    if (_seen < evs.length) {
      _queue.addAll(evs.sublist(_seen));
      _seen = evs.length;
    }
    _speed = _queue.length > 2 ? 2.2 : (_queue.length > 1 ? 1.6 : 1.0);
    if (!_animating) _playNext();
  }

  void _playNext() {
    if (!mounted || _queue.isEmpty) {
      _frozen = null;
      if (mounted) setState(() {});
      return;
    }
    _cur = _queue.removeAt(0);
    final total = PlayTiming.total(_cur!) / _speed;
    _anim.duration = Duration(milliseconds: (total * 1000).round());
    _anim.forward(from: 0).whenCompleteOrCancel(() {
      if (_anim.value >= 1.0) _playNext();
    });
    setState(() {});
  }

  /// 打席が終わった後の処理
  void _afterPa() {
    _clearPlan();
    _prepareNext();
    if (widget.clutch) WidgetsBinding.instance.addPostFrameCallback((_) => _clutchSkip());
  }

  Future<bool> _askThreeBunt() async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('2ストライクです'),
        content: const Text('バントを続けますか？\nスリーバントはファウルでも三振になります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('強攻に切り替える')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('スリーバント')),
        ],
      ),
    );
    return r ?? false;
  }

  /// 判断が必要な場面で止まったときの対応。続けて進めてよければ true
  Future<bool> _handlePause(PaPause p) async {
    if (p.kind == PaPauseKind.threeBunt) {
      _s.threeBunt = _myBatting ? await _askThreeBunt() : false;
    }
    return true;
  }

  /// 1球ずつ: 次の1球（cmd: 待て・外せ）
  Future<void> _nextPitch({PitchCommand cmd = PitchCommand.none}) async {
    if (_finished) return;
    _skipAnimation();
    _freeze();
    _s.pitchCommand = cmd;
    var p = _sim.stepPitch(_s, plan: _plan());
    while (p != null && p.important) {
      await _handlePause(p);
      if (!mounted) return;
      p = _sim.stepPitch(_s);
    }
    if (p == null) _afterPa();
    setState(_enqueueNew);
    _scrollLog();
  }

  /// 1人ずつ: 打席の終わりまで（判断が必要な場面では止まる）
  Future<void> _nextBatter() async {
    if (_finished) return;
    _skipAnimation();
    _freeze();
    var p = _sim.stepPitch(_s, plan: _plan());
    while (p != null) {
      if (p.important) {
        setState(_enqueueNew);
        await _handlePause(p);
        if (!mounted) return;
      }
      p = _sim.stepPitch(_s);
    }
    _afterPa();
    setState(_enqueueNew);
    _scrollLog();
  }

  /// untilInningEnd=true: 回の終わりまで / false: 試合終了まで。自チームの継投もCPU任せにする
  void _auto({required bool untilInningEnd}) {
    _skipAnimation();
    if (_s.inPlateAppearance) _sim.stepPlateAppearance(_s, plan: _plan());
    final startInning = _st.inning;
    final startTop = _st.isTop;
    setState(() {
      while (!_sim.isFinished(_s)) {
        if (untilInningEnd && (_st.inning != startInning || _st.isTop != startTop)) break;
        _sim.autoManage(_s);
        _sim.stepPlateAppearance(_s);
      }
      _clearPlan();
      if (!_finished) _prepareNext();
      _seen = _s.pitchEvents.length;
      _queue.clear();
      _cur = null;
    });
    _scrollLog();
  }

  void _scrollLog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  void _finish() {
    final result = _sim.finishGame(_s);
    Navigator.of(context).pop(result);
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('試合を終了しますか？'),
        content: const Text('残りは自動で最後まで進めて結果を確定します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('続ける')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('自動で終了')),
        ],
      ),
    );
    if (ok == true) {
      _auto(untilInningEnd: false);
      _finish();
    }
  }

  // ---------------- 汎用ダイアログ ----------------

  Future<T?> _choose<T>(String title, List<_Opt<T>> opts) {
    return showDialog<T>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(title),
        children: opts
            .map(
              (o) => SimpleDialogOption(
                onPressed: o.enabled ? () => Navigator.pop(c, o.value) : null,
                child: Opacity(
                  opacity: o.enabled ? 1 : 0.4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (o.desc.isNotEmpty) Text(o.desc, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  /// タップで選手の詳細（打者・投手のカード）
  Widget _tapDetail(Player p, Widget child) => widget.appState == null ? child : GestureDetector(onTap: () => showPlayerDetail(context, widget.appState, p, allowActions: false), child: child);

  /// 交代する選手を選ぶ（オーダー画面と同じ1行の形。行をタップで決定、右の i で詳細）
  Future<Player?> _pickPlayer(String title, List<Player> candidates, {String? note, bool sort = true, Widget Function(Player)? leading}) {
    final list = sort ? (List.of(candidates)..sort(compareByUniform)) : candidates;
    return showModalBottomSheet<Player>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                if (note != null) Text(note, style: const TextStyle(fontSize: 12, color: Color(0xFF78716C))),
                const Text('行をタップで決定。i で選手の詳細', style: TextStyle(fontSize: 11, color: Color(0xFF78716C))),
              ]),
            ),
            if (list.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('ベンチに交代できる選手がいません'))
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final p in list)
                    PlayerRow(
                      player: p,
                      date: widget.match.date,
                      leading: leading?.call(p),
                      onTap: () => Navigator.pop(c, p),
                      trailing: IconButton(
                        tooltip: '詳細',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.info_outline, size: 20),
                        onPressed: widget.appState == null ? null : () => showPlayerDetail(c, widget.appState, p, allowActions: false),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  // ---------------- 交代 ----------------

  bool get _hasMyRunner => _myBatting && (_st.runner1B != null || _st.runner2B != null || _st.runner3B != null);

  Future<void> _pinchHit() async {
    final order = _myHome ? _s.homeOrder : _s.awayOrder;
    final cur = order[_sim.nextBatterSlot(_s, _myHome) % order.length];
    final p = await _pickPlayer('代打を選択', _sim.availableBatters(_s, _myHome), note: '今の打者：${cur.listName}（${PlayerRow.defaultSub(cur)}）');
    if (p == null) return;
    setState(() => _sim.pinchHit(_s, _myHome, p));
    _scrollLog();
  }

  Future<void> _pinchRun() async {
    final bases = <int>[if (_st.runner1B != null) 1, if (_st.runner2B != null) 2, if (_st.runner3B != null) 3];
    if (bases.isEmpty) return;
    final base = await _choose<int>('代走を出す走者', [for (final b in bases) _Opt(b, '$b塁走者', b == 1 ? _st.runner1B ?? '' : (b == 2 ? _st.runner2B ?? '' : _st.runner3B ?? ''))]);
    if (base == null) return;
    final p = await _pickPlayer('代走を選択', _sim.availableBatters(_s, _myHome)..sort((a, b) => b.run.compareTo(a.run)), sort: false, note: '走力の高い順');
    if (p == null) return;
    setState(() => _sim.pinchRun(_s, _myHome, base, p));
    _scrollLog();
  }

  Future<void> _changePitcher() async {
    final now = _myHome ? _s.homePitcher : _s.awayPitcher;
    final p = await _pickPlayer('継投：投手を選択', _sim.availablePitchers(_s, _myHome), note: '今の投手：${now.listName}（${_s.gamePitchCounts[now.id] ?? 0}球）');
    if (p == null) return;
    setState(() => _sim.changePitcher(_s, _myHome, p));
    _scrollLog();
  }

  Future<void> _defensiveSwap() async {
    final order = _myHome ? _s.homeOrder : _s.awayOrder;
    final lineup = _myHome ? _s.homeLineup : _s.awayLineup;
    final mode = await _choose<int>('守備交代', const [
      _Opt(0, '控えの選手と交代', '打順の選手を控えと入れ替え、守備位置を決める'),
      _Opt(1, '出ている選手同士で入れ替え', '打順はそのままで、2人の守備位置を入れ替える（例：遊撃と二塁）'),
    ]);
    if (mode == null || !mounted) return;
    if (mode == 1) {
      Widget lead(Player x) {
        final i = order.indexOf(x);
        return SizedBox(width: 40, child: Text('${i + 1} ${i < lineup.length ? posLabel(lineup[i].position) : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)));
      }
      final movable = [for (var i = 0; i < order.length && i < lineup.length; i++) if (lineup[i].position != '投') order[i]];
      final a = await _pickPlayer('守備位置を変える選手（1人目）', movable, sort: false, leading: lead);
      if (a == null || !mounted) return;
      final b = await _pickPlayer('入れ替える相手（2人目）', movable.where((x) => !identical(x, a)).toList(), sort: false, leading: lead);
      if (b == null || !mounted) return;
      setState(() => _sim.swapPositions(_s, _myHome, order.indexOf(a), order.indexOf(b)));
      _scrollLog();
      return;
    }
    final out = await _pickPlayer('交代させる選手', order, sort: false, leading: (x) {
      final i = order.indexOf(x);
      return SizedBox(width: 34, child: Text('${i + 1} ${i < lineup.length ? posLabel(lineup[i].position) : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)));
    });
    if (out == null) return;
    final slot = order.indexOf(out);
    final p = await _pickPlayer('入る選手を選択', _sim.availableBatters(_s, _myHome));
    if (p == null || !mounted) return;
    const positions = ['捕', '一', '二', '三', '遊', '左', '中', '右', 'DH'];
    final pos = await _choose<String>('守備位置', [for (final x in positions) _Opt(x, x, '')]);
    if (pos == null) return;
    setState(() => _sim.defensiveSwap(_s, _myHome, slot, p, pos));
    _scrollLog();
  }

  // ---------------- 采配（4分類） ----------------

  bool get _hasRunner => _st.runner1B != null || _st.runner2B != null || _st.runner3B != null;
  bool get _lt2 => _st.outs < 2;

  String _planSummary() {
    final parts = <String>[];
    if (_myBatting) {
      if (_bat != BatTactic.none) parts.add('打撃: ${_batLabel(_bat)}');
      if (_run != RunTactic.none) parts.add('走塁: ${_runLabel(_run)}');
    } else {
      if (_pitch != PitchTactic.none) parts.add('投手: ${_pitchLabel(_pitch)}');
      if (_col != null) parts.add('投球指定: ${_row! * 5 + _shownCol(_col!) + 1}番${_pitchName != null ? ' $_pitchName' : ''}');
      if (_field != FieldTactic.none) parts.add('守備: ${_fieldLabel(_field)}');
    }
    return parts.join('  /  ');
  }

  String _batLabel(BatTactic t) => const {BatTactic.pullRight: '右狙い', BatTactic.bunt: '送りバント', BatTactic.squeeze: 'スクイズ', BatTactic.powerSwing: '強振', BatTactic.contactSwing: 'ミート打ち', BatTactic.oppositeField: '流し打ち', BatTactic.pullHit: '引っ張り', BatTactic.chopDown: '叩きつけ', BatTactic.firstPitch: '初球から積極的', BatTactic.flyBall: '外野フライ狙い', BatTactic.patient: '粘れ', BatTactic.lowBall: '低め狙い', BatTactic.highBall: '高め狙い', BatTactic.fastballFocus: 'ストレート狙い', BatTactic.breakingFocus: '変化球狙い'}[t] ?? '';
  String _runLabel(RunTactic t) => const {RunTactic.steal: '盗塁', RunTactic.hitAndRun: 'ヒットエンドラン', RunTactic.aggressive: '積極走塁', RunTactic.cautious: '慎重走塁'}[t] ?? '';
  String _pitchLabel(PitchTactic t) => const {PitchTactic.groundOut: '打たせて取る', PitchTactic.strikeout: '三振狙い', PitchTactic.doublePlay: '併殺狙い', PitchTactic.intentionalWalk: '敬遠', PitchTactic.fullPower: '全力投球', PitchTactic.controlFocus: 'コントロール重視', PitchTactic.insideAttack: '内角攻め', PitchTactic.outsideFocus: '外角中心', PitchTactic.fastballMain: '直球中心', PitchTactic.breakingMain: '変化球中心'}[t] ?? '';
  String _fieldLabel(FieldTactic t) => const {FieldTactic.powerGuard: '長打警戒', FieldTactic.infieldIn: '前進守備', FieldTactic.doublePlayShift: '併殺シフト', FieldTactic.infieldBack: '内野後方', FieldTactic.pullShift: '引っ張りシフト', FieldTactic.oppositeShift: '流し警戒'}[t] ?? '';

  // ---------------- 画面（デザイン案A：テレビ中継） ----------------
  //  上：スコアボード / 中央：球場（打者・投手のカードを重ねる）と一球速報
  //  右：投球（捕手から見た図＋変化の詳細）・采配（その場で選べるボタン）・進行ボタン
  //  狭い画面では、球場と投球を上に並べ、下を「采配／投球／速報」のタブにする
  //  キーボード：スペース＝次へ、W＝待て／外せ

  // 白い画面：_navy＝背景（白）・_navy2＝枠の中（薄い灰）・_edge＝線・_lime＝選んだもの・強調（深い緑）・_muted＝薄い字・_text＝字
  static const _navy = Color(0xFFFFFFFF);
  static const _navy2 = Color(0xFFF1F5F9);
  static const _edge = Color(0xFFCBD5E1);
  static const _lime = Color(0xFF15803D);
  static const _muted = Color(0xFF64748B);
  static const _text = Color(0xFF0F172A);

  String _short(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;

  /// 今季この2球団の何回目の対戦か（同じ種類の試合。0 は分からない）
  int? _gameNoCache;
  int _gameNo() {
    if (_gameNoCache != null) return _gameNoCache!;
    final app = widget.appState;
    if (app == null) return _gameNoCache = 0;
    final m = widget.match;
    final pair = {m.homeTeamId, m.awayTeamId};
    var n = 0;
    for (final x in app.matches) {
      if (x.matchType != m.matchType || x.date.year != m.date.year) continue;
      if (!pair.containsAll({x.homeTeamId, x.awayTeamId})) continue;
      if (x.date.isBefore(m.date) || identical(x, m) || (x.date == m.date && x.homeTeamId == m.homeTeamId)) n++;
    }
    return _gameNoCache = n;
  }

  bool get _perPitchMode => widget.manage && _perPitch;

  void _primary() {
    if (_finished) {
      if (_animating) {
        setState(_skipAnimation);
      } else {
        _finish();
      }
      return;
    }
    if (_perPitchMode) {
      _nextPitch();
    } else {
      _nextBatter();
    }
  }

  void _command() {
    if (!_perPitchMode || _finished) return;
    _nextPitch(cmd: _myBatting ? PitchCommand.take : PitchCommand.pitchOut);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    if (ev.logicalKey == LogicalKeyboardKey.space || ev.logicalKey == LogicalKeyboardKey.enter) {
      _primary();
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.keyW) {
      _command();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.homeTeam;
    final away = widget.awayTeam;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: _text,
          elevation: 0,
          toolbarHeight: 58,
          titleSpacing: 8,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.match.date.month}月${widget.match.date.day}日　${_short(away)} 対 ${_short(home)}${_gameNo() > 0 ? '　第${_gameNo()}回戦' : ''}',
                maxLines: 1,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _text),
              ),
            ),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${Stadium.byId(home.homeStadium).name}　${_s.weather.text.replaceAll(RegExp(r' 湿度\d+%'), '')}　風 ${_s.env.windText.replaceAll('方向', '')}　'),
                TextSpan(text: widget.clutch ? '終盤接戦のみ采配' : (widget.manage ? 'フル采配' : '簡易采配'), style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w800)),
              ]),
              maxLines: 1,
              style: const TextStyle(fontSize: 11, color: _muted),
            )),
          ]),
          actions: [Padding(padding: const EdgeInsets.only(right: 10), child: AnimatedBuilder(animation: _anim, builder: (context, _) => CountAndBases(st: _view, finished: _finished)))],
        ),
        // 下のボタンが端末のナビゲーションバーに隠れないようにする
        body: SafeArea(
          top: false,
          child: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: LayoutBuilder(
              builder: (context, c) {
                final board = ScoreBoard(awayName: _short(away), homeName: _short(home), st: _view, awayHits: _frozen != null ? _fAwayHits : _s.awayHits, homeHits: _frozen != null ? _fHomeHits : _s.homeHits, finished: _finished, awayErrors: _s.pitchEvents.where((e) => e.errorBy.isNotEmpty && e.battingHome).length, homeErrors: _s.pitchEvents.where((e) => e.errorBy.isNotEmpty && !e.battingHome).length);
                if (c.maxWidth >= 1000) {
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        board,
                        const SizedBox(height: 8),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: _fieldWithCards(compact: false)),
                                    const SizedBox(height: 8),
                                    SizedBox(height: 130, child: _logBox()),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 420,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _navy,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: _edge),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(height: 260, child: _pitchBox()),
                                      const Divider(height: 1, color: _edge),
                                      Expanded(
                                        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: _tactics()),
                                      ),
                                      const Divider(height: 1, color: _edge),
                                      Padding(padding: const EdgeInsets.all(12), child: _progress()),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                // 狭い画面：スコアボード、球場とコース、対戦の帯（案B）、采配（分類のチップ＋マス。案C）、進行
                final topH = (c.maxHeight * 0.30).clamp(180.0, 300.0);
                final boardNarrow = ScoreBoard(awayName: _short(away), homeName: _short(home), st: _view, awayHits: _frozen != null ? _fAwayHits : _s.awayHits, homeHits: _frozen != null ? _fHomeHits : _s.homeHits, finished: _finished, awayErrors: _s.pitchEvents.where((e) => e.errorBy.isNotEmpty && e.battingHome).length, homeErrors: _s.pitchEvents.where((e) => e.errorBy.isNotEmpty && !e.battingHome).length, showCount: false);
                return Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    boardNarrow,
                    const SizedBox(height: 4),
                    SizedBox(
                      height: topH,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(flex: 5, child: _fieldWithCards(compact: true)),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _animated((t, cur, paEvents, hand) => PitchView(paEvents: paEvents, animating: cur, t: cur == null ? 0 : t, batterHand: hand)),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    AnimatedBuilder(animation: _anim, builder: (context, _) => _matchStrip()),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(8), border: Border.all(color: _edge)),
                        child: _tacticsPanel(),
                      ),
                    ),
                    Container(color: _navy, padding: const EdgeInsets.fromLTRB(6, 4, 6, 4), child: _progress()),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// アニメーションの経過に合わせて作り直す部品
  Widget _animated(Widget Function(double t, PitchEvent? cur, List<PitchEvent> paEvents, String hand) b) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final cur = _cur;
        final t = cur == null ? 0.0 : _anim.value * PlayTiming.total(cur);
        final paIdx = cur?.paIndex ?? (_s.paCount - 1);
        final paEvents = _s.pitchEvents.where((e) => e.paIndex == paIdx && (cur == null || e.pitchNo < cur.pitchNo)).toList();
        final hand = cur?.batterHand ?? (paEvents.isNotEmpty ? paEvents.last.batterHand : 'R');
        return b(t, cur, paEvents, hand);
      },
    );
  }

  // ---- 球場（打者・投手のカードを重ねる） ----

  /// いま見せている場面：2D の動きの間は、動いている1球の打者・投手・攻守（先に次の打者や攻守交代を出さない）
  (bool, List<Player>, int, Player) _scene() {
    final c = _frozen != null ? _cur : null;
    if (c != null) {
      final bh = c.battingHome;
      final order = bh ? _s.homeOrder : _s.awayOrder;
      final i = order.indexWhere((p) => p.registeredName == c.batter);
      final pTeam = bh ? widget.awayTeam : widget.homeTeam;
      final pit = pTeam.players.where((p) => p.registeredName == c.pitcher).firstOrNull ?? (bh ? _s.awayPitcher : _s.homePitcher);
      if (i >= 0) return (bh, order, i, pit);
    }
    final battingHome = !_st.isTop;
    final order = battingHome ? _s.homeOrder : _s.awayOrder;
    return (battingHome, order, _sim.nextBatterSlot(_s, battingHome), battingHome ? _s.awayPitcher : _s.homePitcher);
  }

  /// 投手のこの試合の球数（2D の動きの間は、その球までの数）
  int _pitchCountOf(Player p) {
    final c = _frozen != null ? _cur : null;
    if (c == null) return _s.gamePitchCounts[p.id] ?? 0;
    final upTo = _s.pitchEvents.indexOf(c);
    var n = 0;
    for (var i = 0; i <= upTo && i < _s.pitchEvents.length; i++) {
      if (_s.pitchEvents[i].pitcher == p.registeredName) n++;
    }
    return n;
  }

  Widget _fieldWithCards({required bool compact}) {
    final (battingHome, order, slot, pitcher) = _scene();
    final batter = order[slot % order.length];

    final field = _animated((t, cur, paEvents, hand) {
      final recent = _s.pitchEvents.where((e) => e.paIndex >= (cur?.paIndex ?? (_s.paCount - 1)) - 3 && e.landX != null).toList();
      final fieldEvent = (cur != null && cur.path.isNotEmpty) ? cur : null;
      return FieldPlayView(event: fieldEvent, t: t, r1: _st.runner1B != null, r2: _st.runner2B != null, r3: _st.runner3B != null, before: [_view.runner1B != null, _view.runner2B != null, _view.runner3B != null], recent: recent);
    });
    return GestureDetector(
      onTap: _animating ? () => setState(_skipAnimation) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Positioned.fill(child: field),
            if (!_finished && !compact) ...[Positioned(left: 10, top: 10, width: 250, child: _tapDetail(batter, _batterCard(batter, slot % order.length, battingHome))), Positioned(right: 10, top: 10, width: 250, child: _tapDetail(pitcher, _pitcherCard(pitcher, !battingHome)))],
            if (_animating)
              const Positioned(
                right: 10,
                bottom: 8,
                child: Text('タップでスキップ', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _overlayCard(List<Widget> children, {bool right = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xD907101C),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _edge),
    ),
    child: Column(crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
  );

  Widget _batterCard(Player b, int slot, bool home) {
    final box = (_s.boxScore[home ? 'homeBatters' : 'awayBatters'] as Map<String, dynamic>)[b.registeredName];
    final today = box == null ? '' : '今日 ${box['ab']}打数${box['h']}安打${(box['hr'] ?? 0) > 0 ? ' ${box['hr']}本' : ''}${(box['bb'] ?? 0) > 0 ? ' ${box['bb']}四球' : ''}';
    final hand = b.bats == 'L' ? '左' : (b.bats == 'S' ? '両' : '右');
    return _overlayCard([
      Text('打者　${slot + 1}番　$hand打', style: const TextStyle(fontSize: 11, color: _muted)),
      Text(
        b.listName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white),
      ),
      Text('ミ${b.contact} パ${b.power} 走${b.run} 選${b.eye}', style: const TextStyle(fontSize: 12, color: Color(0xFFB8C6D8))),
      Text('今季 ${b.seasonStats.battingAverage.toStringAsFixed(3).replaceFirst('0.', '.')}  ${b.seasonStats.homeRuns}本  ${b.seasonStats.rbi}打点', style: const TextStyle(fontSize: 12, color: Color(0xFFB8C6D8))),
      if (today.isNotEmpty) Text(today, style: const TextStyle(fontSize: 12, color: _lime)),
    ]);
  }

  Widget _pitcherCard(Player p, bool home) {
    final used = _s.staminaUsed[p.id] ?? 0;
    final left = (1 - used / MatchSimulator.staminaLimit(p)).clamp(0.0, 1.0);
    final box = (_s.boxScore[home ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>)[p.registeredName];
    final line = box == null ? '' : '${box['ip']}回  自責${box['er']}  ${box['so']}K  ${box['bb']}四球';
    final col = left < 0.3 ? const Color(0xFFEF4444) : (left < 0.5 ? const Color(0xFFF59E0B) : const Color(0xFF22C55E));
    return _overlayCard([
      Text('投手　${p.throws == 'L' ? '左' : '右'}投', style: const TextStyle(fontSize: 11, color: _muted)),
      Text(
        p.listName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white),
      ),
      Text('${_pitchCountOf(p)}球　$line', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFFCD34D))),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          width: 160,
          height: 6,
          child: LinearProgressIndicator(value: left, backgroundColor: _edge, color: col),
        ),
      ),
      Text('スタミナ残り ${(left * 100).round()}%', style: const TextStyle(fontSize: 11, color: _muted)),
    ], right: true);
  }

  // ---- 投球（捕手から見た図＋変化の詳細） ----

  Widget _pitchBox() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _animated((t, cur, paEvents, hand) => PitchView(paEvents: paEvents, animating: cur, t: cur == null ? 0 : t, batterHand: hand)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _vsPanel(pad: 0)),
        ],
      ),
    );
  }

  // ---- 対戦（いまの投手と打者の能力・今季成績・対戦成績） ----

  /// オーダー（両軍）を浮かせて出す。選手を押すと詳しい画面
  void _showOrders() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => SizedBox(height: MediaQuery.of(c).size.height * 0.75, child: _orderSheet()),
    );
  }

  /// オーダー（浮かせて出す）：試合前のラインナップと同じ表を小さく。ビジター→ホーム。いまの打者に印、投手は球数つき
  Widget _orderSheet() {
    final date = (widget.appState?.currentDate as DateTime?) ?? widget.match.date;
    final battingHome = !_st.isTop;
    final slotNow = _finished ? -1 : _sim.nextBatterSlot(_s, battingHome);
    const head = TextStyle(fontSize: 10, color: Color(0xFF64748B));
    Widget card(bool home) {
      final t = home ? widget.homeTeam : widget.awayTeam;
      final order = home ? _s.homeOrder : _s.awayOrder;
      final line = home ? _s.homeLineup : _s.awayLineup;
      final box = (_s.boxScore[home ? 'homeBatters' : 'awayBatters'] as Map?) ?? const {};
      final pit = home ? _s.homePitcher : _s.awayPitcher;
      String today(Player p) {
        final r = box[p.registeredName];
        return r is Map ? '${r['ab'] ?? 0}-${r['h'] ?? 0}' : '';
      }

      final rows = <Widget>[
        Row(children: [
          Container(width: 4, height: 16, color: teamColor(widget.appState == null ? [widget.homeTeam, widget.awayTeam] : List<Team>.from(widget.appState.teams as List), t)),
          const SizedBox(width: 6),
          Expanded(child: Text('${home ? 'ホーム' : 'ビジター'}　${t.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.only(bottom: 2),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
          child: const Row(children: [
            SizedBox(width: 15, child: Text('順', style: head)),
            SizedBox(width: 34, child: Text('守・適', style: head)),
            Expanded(child: Text('選手', style: head)),
            SizedBox(width: 38, child: Text('総合', style: head, textAlign: TextAlign.right)),
            SizedBox(width: 36, child: Text('打率', style: head, textAlign: TextAlign.right)),
            SizedBox(width: 20, child: Text('本', style: head, textAlign: TextAlign.right)),
            SizedBox(width: 22, child: Text('点', style: head, textAlign: TextAlign.right)),
            SizedBox(width: 30, child: Text('今日', style: head, textAlign: TextAlign.right)),
          ]),
        ),
      ];
      for (var i = 0; i < order.length; i++) {
        final p = order[i];
        final pos = i < line.length ? line[i].position : '';
        final apt = pos == 'DH' || pos == '投' || pos.isEmpty ? null : FarmEngine.fieldingAt(p, pos);
        final g = apt == null ? '' : GradeUtils.getGrade(apt);
        final now = home == battingHome && i == slotNow % order.length;
        final og = GradeUtils.getGrade(p.ovr);
        rows.add(InkWell(
          onTap: widget.appState == null ? null : () => showPlayerDetail(context, widget.appState, p, allowActions: false),
          child: Container(
            height: 24,
            color: now ? const Color(0xFFFEF3C7) : null,
            child: Row(children: [
              SizedBox(width: 15, child: Text('${i + 1}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800))),
              SizedBox(
                width: 34,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: posLabel(pos), style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  if (apt != null) TextSpan(text: ' $g', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: apt < 40 ? Colors.red : AppTheme.getGradeColor(g))),
                ])),
              ),
              ConditionFace(level: p.conditionAt(date), size: 12),
              const SizedBox(width: 3),
              Expanded(child: Text(p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: now ? FontWeight.w900 : FontWeight.w700))),
              SizedBox(
                width: 38,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: og, style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.getGradeColor(og))),
                  TextSpan(text: ' ${p.ovr}'),
                ]), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11)),
              ),
              SizedBox(width: 36, child: Text(VsLine.rate(p.shownStats.battingAverage), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
              SizedBox(width: 20, child: Text('${p.shownStats.homeRuns}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
              SizedBox(width: 22, child: Text('${p.shownStats.rbi}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
              SizedBox(width: 30, child: Text(today(p), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
          ),
        ));
      }
      rows.add(const SizedBox(height: 4));
      rows.add(InkWell(
        onTap: widget.appState == null ? null : () => showPlayerDetail(context, widget.appState, pit, allowActions: false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Text('投手', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
            const SizedBox(width: 6),
            ConditionFace(level: pit.conditionAt(date), size: 12),
            const SizedBox(width: 3),
            Expanded(child: Text(pit.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
            Text('${_pitchCountOf(pit)}球', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFFB91C1C))),
            Text('　体力${(pit.energyRatio * 100).round()}%', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
          ]),
        ),
      ));
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      );
    }

    return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), children: [card(false), card(true)]);
  }

  Widget _vsPanel({double pad = 10}) {
    if (_finished) return const Center(child: Text('試合終了', style: TextStyle(color: _muted)));
    final (battingHome, order, slot0, p) = _scene(); // 2D の動きの間は、動いている1球の打者・投手
    final slot = slot0 % order.length;
    final b = order[slot];
    // 今季（前の試合まで）＋今日の対戦
    final MatchupBook? book = widget.appState?.matchups as MatchupBook?;
    final before = book?.of(p.id, b.id) ?? VsLine();
    final today = VsLine();
    final last = <int, PitchEvent>{};
    for (final e in _s.pitchEvents) {
      if (e.batter != b.registeredName || e.pitcher != p.registeredName) continue;
      final c = last[e.paIndex];
      if (c == null || e.pitchNo >= c.pitchNo) last[e.paIndex] = e;
    }
    for (final e in last.values) {
      final r = paResult(PitchRec(paIndex: e.paIndex, pitchNo: e.pitchNo, battingHome: e.battingHome, batter: e.batter, pitcher: e.pitcher, result: e.result, outcome: e.outcome, balls: e.balls, strikes: e.strikes));
      if (r != null) today.add(r);
    }
    final official = widget.match.matchType == 'LEAGUE' || widget.match.matchType == 'INTERLEAGUE';
    final season = VsLine()
      ..add(before)
      ..add(official ? today : VsLine());

    const lbl = TextStyle(fontSize: 10.5, color: _muted);
    // 能力のマス（見出しの下に評価と数値）。1行に同じ幅で並べる
    Widget abil(String name, int v, {bool hi = false}) {
      final g = GradeUtils.getGrade(v);
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(color: hi ? const Color(0x2215803D) : _navy, borderRadius: BorderRadius.circular(5), border: Border.all(color: hi ? _lime : _edge)),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(name, maxLines: 1, style: lbl)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: g, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.getGradeColor(g))),
              TextSpan(text: '$v', style: const TextStyle(fontSize: 10.5, color: _text)),
            ]), maxLines: 1),
          ),
        ]),
      );
    }

    // 欄の幅に合わせて、1行に並べる数を決めて折り返す（狭いと3つずつ）
    List<List<T>> chunk<T>(List<T> xs, int per) => [for (var i = 0; i < xs.length; i += per) xs.sublist(i, i + per > xs.length ? xs.length : i + per)];
    Widget cells(List<Widget> xs) => LayoutBuilder(builder: (context, c) {
          final per = (c.maxWidth / 60).floor().clamp(3, xs.length);
          final rows = chunk(xs, per);
          return Column(children: [
            for (var r = 0; r < rows.length; r++)
              Padding(
                padding: EdgeInsets.only(top: r == 0 ? 0 : 3),
                child: Row(children: [
                  for (var i = 0; i < per; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(child: i < rows[r].length ? rows[r][i] : const SizedBox()),
                  ],
                ]),
              ),
          ]);
        });
    // 成績の表（見出しの行と数字の行）
    Widget stats(List<(String, String)> all) => LayoutBuilder(builder: (context, c) {
          final per = (c.maxWidth / 54).floor().clamp(3, all.length);
          return Column(children: [
            for (final xs in chunk(all, per))
              Container(
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), border: Border.all(color: _edge)),
          child: Row(children: [
            for (var i = 0; i < xs.length; i++)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: _edge))),
                  child: Column(children: [
                    FittedBox(fit: BoxFit.scaleDown, child: Text(xs[i].$1, maxLines: 1, style: lbl)),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(xs[i].$2, maxLines: 1, style: const TextStyle(fontSize: 12.5, color: _text, fontWeight: FontWeight.w800))),
                  ]),
                ),
              ),
            for (var k = xs.length; k < per; k++) const Expanded(child: SizedBox()),
          ]),
        ),
          ]);
        });

    Widget head(String role, Player x, String sub) => Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: role == '投' ? const Color(0xFF1D4ED8) : const Color(0xFFB91C1C), borderRadius: BorderRadius.circular(4)),
            child: Text(role, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _tapDetail(x, Text(x.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: _text))),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: lbl),
            ]),
          ),
        ]);

    final ps = p.seasonStats, bs = b.seasonStats;
    final ip = '${ps.inningsPitched ~/ 3}${ps.inningsPitched % 3 > 0 ? '.${ps.inningsPitched % 3}' : ''}';
    final vsLeft = p.throws == 'L';
    final pitches = [...p.pitches]..sort((a, c) => c.ratio.compareTo(a.ratio));

    Widget box(List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: _navy2, borderRadius: BorderRadius.circular(8), border: Border.all(color: _edge)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );

    return ListView(padding: EdgeInsets.all(pad), children: [
      // 対戦成績
      box([
        Text('対戦成績（今季）　${p.lastName} × ${b.lastName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: lbl),
        const SizedBox(height: 2),
        Row(children: [
          Text(season.avgText, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _lime)),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(season.pa == 0 ? '今季は対戦なし' : '${season.pa}打席　${season.summary}', maxLines: 1, style: const TextStyle(fontSize: 12.5, color: _text, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
        if (today.pa > 0) Text('今日：${today.summary}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _lime)),
        if (book != null && !(widget.appState.matchupsReady as bool)) const Text('（記録を読み込み中…）', style: lbl),
      ]),
      // 投手
      box([
        head('投', p, '${p.throws == 'L' ? '左' : '右'}投　${p.age}歳　${_pitchCountOf(p)}球'),
        const SizedBox(height: 5),
        cells([
          Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(5), border: Border.all(color: _edge)),
            child: Column(children: [
              const Text('最速', style: lbl),
              FittedBox(fit: BoxFit.scaleDown, child: Text('${p.velocity}km', style: const TextStyle(fontSize: 12, color: _text, fontWeight: FontWeight.w800))),
            ]),
          ),
          abil('コン', p.control),
          abil('スタ', p.stamina),
          abil('ピンチ', p.clutchPitching),
          abil('クイック', p.quick),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 3, runSpacing: 3, children: [
          for (final x in pitches)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(4), border: Border.all(color: _edge)),
              child: Text(x.name, style: const TextStyle(fontSize: 10.5, color: _text)),
            ),
        ]),
        const SizedBox(height: 4),
        stats([
          ('登板', '${ps.pitchApps}'),
          ('勝', '${ps.wins}'),
          ('敗', '${ps.losses}'),
          ('H', '${ps.holds}'),
          ('S', '${ps.saves}'),
          ('防御率', ps.inningsPitched == 0 ? '-.--' : ps.era.toStringAsFixed(2)),
        ]),
        const SizedBox(height: 3),
        stats([
          ('投球回', ip),
          ('奪三振', '${ps.pitcherStrikeouts}'),
          ('与四球', '${ps.pitcherWalks}'),
          ('被本塁打', '${ps.hrAllowed}'),
        ]),
      ]),
      // 打者
      box([
        head('打', b, '${slot + 1}番　${b.bats == 'L' ? '左' : (b.bats == 'S' ? '両' : '右')}打　${b.age}歳'),
        const SizedBox(height: 5),
        cells([
          abil('対左ミ', b.contactLeft, hi: vsLeft),
          abil('対右ミ', b.contactRight, hi: !vsLeft),
          abil('パワー', b.power),
          abil('走力', b.run),
          abil('選球眼', b.eye),
          abil('チャンス', b.clutch),
        ]),
        const SizedBox(height: 4),
        stats([
          ('試合', '${bs.games}'),
          ('打率', VsLine.rate(bs.battingAverage)),
          ('本', '${bs.homeRuns}'),
          ('打点', '${bs.rbi}'),
          ('盗塁', '${bs.stolenBases}'),
        ]),
        const SizedBox(height: 3),
        stats([
          ('打数', '${bs.atBats}'),
          ('安打', '${bs.hits}'),
          ('出塁率', VsLine.rate(bs.obp)),
          ('OPS', VsLine.rate(bs.ops)),
          ('三振', '${bs.strikeouts}'),
        ]),
      ]),
    ]);
  }

  // ---- 一球速報 ----

  Widget _logBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _edge),
      ),
      child: Builder(builder: (_) {
        _syncLive();
        return ListView.builder(
          controller: _logScroll,
          itemCount: _live.length,
          itemBuilder: (_, i) => _liveRow(_live[i]),
        );
      }),
    );
  }

  Widget _liveRow(LiveLine l) {
    switch (l.kind) {
      case 'inning':
        return Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          padding: const EdgeInsets.only(bottom: 3),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _lime, width: 1))),
          child: Text(l.text, style: const TextStyle(color: _lime, fontWeight: FontWeight.w900, fontSize: 13.5)),
        );
      case 'pa':
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(l.text, style: const TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 13.5, height: 1.4)),
        );
      case 'situation':
        return Text(l.text, style: const TextStyle(color: Color(0xFFB45309), fontSize: 11.5, height: 1.5));
      case 'result':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(l.text, style: TextStyle(color: l.hit ? const Color(0xFF15803D) : _text, fontWeight: FontWeight.w800, fontSize: 13, height: 1.45)),
        );
      case 'big':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: const Color(0x33F59E0B), borderRadius: BorderRadius.circular(5)),
          child: Text(l.text, style: const TextStyle(color: Color(0xFFFCD34D), fontWeight: FontWeight.w900, fontSize: 13.5, height: 1.4)),
        );
      case 'score':
        return Text(l.text, style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.5));
      case 'state':
        return Text(l.text, style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.5));
      case 'note':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(l.text, style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 12, fontWeight: FontWeight.w700, height: 1.4)),
        );
      default:
        return Text(l.text, style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.5));
    }
  }

  // ---- 采配（表のように並べたボタン） ----

  /// 采配の1マス。幅はそろえ、文字が長いときは縮めて収める
  Widget _cell(String label, {required bool selected, required bool enabled, required VoidCallback onTap, String? tip, double h = 32}) {
    final c = Material(
      color: selected ? _lime : (enabled ? _navy2 : const Color(0xFFF8FAFC)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: selected ? _lime : (enabled ? _edge : const Color(0xFFE2E8F0)))),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: h,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w700, color: selected ? _navy : (enabled ? _text : const Color(0xFF94A3B8)))),
              ),
            ),
          ),
        ),
      ),
    );
    return tip == null ? c : Tooltip(message: tip, child: c);
  }

  /// マスを cols 列の表にする（足りないところは空き）
  Widget _grid(List<Widget> cells, int cols) {
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += cols) {
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
        child: Row(children: [
          for (var j = 0; j < cols; j++) ...[
            if (j > 0) const SizedBox(width: 3),
            Expanded(child: i + j < cells.length ? cells[i + j] : const SizedBox()),
          ],
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  /// 左に縦書きの見出しを付けたまとまり
  Widget _group(String title, Widget body, {Color color = const Color(0xFFDBEAFE)}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Container(width: 4, height: 13, decoration: BoxDecoration(color: color.withValues(alpha: 1), borderRadius: BorderRadius.circular(2), border: Border.all(color: _edge))),
          const SizedBox(width: 5),
          Text(title, style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900)),
        ]),
      ),
      body,
    ]),
  );

  Widget _tactics() => LayoutBuilder(builder: (context, c) => _tacticsBody(c.maxWidth >= 380 ? 4 : 3));

  Widget _tacticsBody(int cols, {String? only}) {
    if (_finished) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('試合終了', textAlign: TextAlign.center, style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900)),
      );
    }
    final children = <Widget>[];
    final summary = widget.manage ? _planSummary() : '';
    final scout = _scoutLine();
    // 分類を1つだけ出すとき（スマホ）は、見出しを付けずにその分類のマスだけ
    void addG(String name, Widget body, {Color color = const Color(0xFFDBEAFE)}) {
      if (only == null) {
        children.add(_group(name, body, color: color));
      } else if (only == name) {
        children.add(Padding(padding: const EdgeInsets.only(top: 6), child: body));
      }
    }

    // 見出し：攻撃／守備と解除
    if (only == null) children.add(Row(children: [
      Text(widget.manage ? (_myBatting ? '攻撃の采配' : '守備の采配') : '簡易采配（交代のみ）', style: const TextStyle(color: Color(0xFF15803D), fontSize: 13, fontWeight: FontWeight.w900)),
      const SizedBox(width: 6),
      if (widget.manage) const Expanded(child: Text('もう一度押すと解除', overflow: TextOverflow.ellipsis, style: TextStyle(color: _muted, fontSize: 10))) else const Spacer(),
      if (summary.isNotEmpty)
        InkWell(
          onTap: () => setState(_clearPlan),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(border: Border.all(color: _edge), borderRadius: BorderRadius.circular(4)),
            child: const Text('すべて解除', style: TextStyle(color: _muted, fontSize: 10.5)),
          ),
        ),
    ]));
    if (scout.isNotEmpty && only == null) {
      children.add(GestureDetector(
        onTap: () => showDialog<void>(context: context, builder: (_) => AlertDialog(title: const Text('スコアラー'), content: Text(scout), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))])),
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: const Color(0x2238BDF8), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0x5538BDF8))),
          child: Text(scout, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontSize: 12, height: 1.4)),
        ),
      ));
    }
    if (widget.manage && _myBatting && _s.cpuFieldPa == _s.paCount && _s.cpuField != FieldTactic.none) {
      children.add(Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: const Color(0x33FF5252), borderRadius: BorderRadius.circular(5)),
        child: Text('相手の守備：${_fieldLabel(_s.cpuField)}', style: const TextStyle(color: _text, fontSize: 11, fontWeight: FontWeight.w700)),
      ));
    }

    if (widget.manage) {
      if (_myBatting) {
        final r3 = _st.runner3B != null;
        final r2or3 = _st.runner2B != null || r3;
        final r1or2 = _st.runner1B != null || _st.runner2B != null;
        final bats = <(BatTactic, String, bool, String)>[
          (BatTactic.bunt, '送りバント', _lt2 && r1or2, '走者を進める'),
          (BatTactic.squeeze, 'スクイズ', _lt2 && r3, '三塁走者を還す（失敗すると走者憤死）'),
          (BatTactic.pullRight, '右狙い', _lt2 && r2or3, '右方向へ打って走者を進める（ミート低下）'),
          (BatTactic.flyBall, '犠飛狙い', _lt2 && r3, '外野フライを狙って打球を上げる'),
          (BatTactic.contactSwing, 'ミート打ち', true, 'ミート上昇・パワー減少（三振が減り、長打も減る）'),
          (BatTactic.powerSwing, '強振', true, 'パワー上昇・ミート低下・三振増'),
          (BatTactic.oppositeField, '流し打ち', true, '逆方向へ打つ。ミート少し上昇・パワー減少'),
          (BatTactic.pullHit, '引っ張り', true, '引っ張り方向へ打つ。パワー上昇・ミート減少'),
          (BatTactic.chopDown, '叩きつけ', true, 'ゴロを打つ。内野安打・三塁走者の生還を狙う（長打は減る）'),
          (BatTactic.firstPitch, '初球から', true, '初球のストライクを狙い打つ（球数は少なくなる）'),
          (BatTactic.patient, '粘れ', true, '見極めてカットする（四球狙い）'),
          (BatTactic.lowBall, '低め狙い', true, '低めは打ちやすく、高めは苦手になる'),
          (BatTactic.highBall, '高め狙い', true, '高めは打ちやすく、低めは苦手になる'),
          (BatTactic.fastballFocus, '直球狙い', true, 'ストレートは打ちやすく、変化球は苦手になる'),
          (BatTactic.breakingFocus, '変化球狙い', true, '変化球は打ちやすく、ストレートは苦手になる'),
        ];
        addG('打撃', _grid([for (final b in bats) _cell(b.$2, selected: _bat == b.$1, enabled: b.$3, tip: b.$4, onTap: () => setState(() => _bat = _bat == b.$1 ? BatTactic.none : b.$1))], cols));
        final canSteal = (_st.runner1B != null && _st.runner2B == null) || (_st.runner2B != null && _st.runner3B == null);
        final canHitRun = _st.runner1B != null && _st.runner2B == null && _lt2;
        final runs = <(RunTactic, String, bool, String)>[(RunTactic.steal, '盗塁', canSteal, '走者の走力・捕手の肩・投手のクイックで成功率が決まる'), (RunTactic.hitAndRun, 'エンドラン', canHitRun, '確実に当てにいき、ゴロでは併殺なし'), (RunTactic.aggressive, '積極走塁', _hasRunner, '1つ先の塁を狙いやすい'), (RunTactic.cautious, '慎重走塁', _hasRunner, '無理に進塁しない')];
        addG('走塁', _grid([for (final r in runs) _cell(r.$2, selected: _run == r.$1, enabled: r.$3, tip: r.$4, onTap: () => setState(() => _run = _run == r.$1 ? RunTactic.none : r.$1))], cols), color: const Color(0xFFDCFCE7));
      } else {
        final pitches = <(PitchTactic, String, bool, String)>[(PitchTactic.groundOut, '打たせて取る', true, 'ゾーン内で勝負し、ゴロを打たせる'), (PitchTactic.strikeout, '三振狙い', true, 'ボール球で振らせる（四球も増える）'), (PitchTactic.doublePlay, '併殺狙い', _st.runner1B != null && _lt2, 'ゴロを打たせて併殺を狙う'), (PitchTactic.fullPower, '全力投球', true, '球速・キレ上昇。スタミナの消耗が激しい'), (PitchTactic.controlFocus, '制球重視', true, '制球上昇・ストライク先行。球速・キレは下がる'), (PitchTactic.insideAttack, '内角攻め', true, '内角を突いて意識させる（甘く入ると打たれる）'), (PitchTactic.outsideFocus, '外角中心', true, '外角のくさいところを突く（四球が増える）'), (PitchTactic.fastballMain, '直球中心', true, 'ストレートを多く投げる'), (PitchTactic.breakingMain, '変化球中心', true, '変化球を多く投げる'), (PitchTactic.intentionalWalk, '敬遠', true, '打者を歩かせる')];
        addG('投手', _grid([for (final p in pitches) _cell(p.$2, selected: _pitch == p.$1, enabled: p.$3, tip: p.$4, onTap: () => setState(() => _pitch = _pitch == p.$1 ? PitchTactic.none : p.$1))], cols));
        addG('配球', _courseAndPitch(cols), color: const Color(0xFFFEF3C7));
        final fields = <(FieldTactic, String, bool, String)>[(FieldTactic.powerGuard, '長打警戒', true, '外野を深く・一三塁を線寄りに'), (FieldTactic.infieldIn, '前進守備', _st.runner3B != null && _lt2, '三塁走者の生還を防ぐ（ゴロが抜けやすくなる）'), (FieldTactic.doublePlayShift, '併殺シフト', _st.runner1B != null && _lt2, '二遊間を二塁寄りに'), (FieldTactic.infieldBack, '内野後方', true, '内野を深く。ヒットは減るが走者は進みやすい'), (FieldTactic.pullShift, '引っ張り', true, '野手を打者の引っ張り方向へ寄せる（流し打ちには弱い）'), (FieldTactic.oppositeShift, '流し警戒', true, '野手を逆方向へ寄せる（引っ張りには弱い）')];
        addG('守備', _grid([for (final f in fields) _cell(f.$2, selected: _field == f.$1, enabled: f.$3, tip: f.$4, onTap: () => setState(() => _field = _field == f.$1 ? FieldTactic.none : f.$1))], cols), color: const Color(0xFFDCFCE7));
      }
    }

    final midPa = _s.inPlateAppearance;
    addG(
      '交代',
      _grid([
        _cell('代打', selected: false, enabled: !midPa, tip: '次に打席が回ってくる打者を差し替える', onTap: _pinchHit),
        _cell('代走', selected: false, enabled: _hasMyRunner, tip: '塁上の走者を差し替える', onTap: _pinchRun),
        _cell('継投', selected: false, enabled: !midPa, tip: '投手を交代する（打席の途中はできません）', onTap: _changePitcher),
        _cell('守備交代', selected: false, enabled: !midPa, tip: '控えと交代、または出ている選手同士で守備位置を入れ替える', onTap: _defensiveSwap),
      ], cols),
      color: const Color(0xFFFCE7F3),
    );
    if (only != null && scout.isNotEmpty) {
      children.add(Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: const Color(0x2238BDF8), borderRadius: BorderRadius.circular(6)),
        child: Text(scout, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontSize: 11.5, height: 1.4)),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  /// 対戦の帯（案B）：投手（球数・体力・成績）と打者（打順・成績）を2行で。「詳しく」でデータの全部
  Widget _matchStrip() {
    if (_finished) return const SizedBox.shrink();
    final (_, order, slot, p) = _scene();
    final b = order[slot % order.length];
    final ps = p.seasonStats, bs = b.seasonStats;
    Widget tag(String t, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
          child: Text(t, style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w900)),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: _edge)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              tag('投', const Color(0xFF1D4ED8)),
              const SizedBox(width: 5),
              Flexible(child: _tapDetail(p, Text(p.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _text)))),
              const SizedBox(width: 5),
              Text('${_pitchCountOf(p)}球', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFFB91C1C))),
              Text('　体力${(p.energyRatio * 100).round()}%　${ps.wins}勝${ps.losses}敗 防${ps.inningsPitched == 0 ? '-.--' : ps.era.toStringAsFixed(2)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: _muted)),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              tag('打', const Color(0xFFB91C1C)),
              const SizedBox(width: 5),
              Flexible(child: _tapDetail(b, Text(b.listName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _text)))),
              Expanded(child: Text('　${slot % order.length + 1}番 ${b.bats == 'L' ? '左' : (b.bats == 'S' ? '両' : '右')}打　${VsLine.rate(bs.battingAverage)} ${bs.homeRuns}本 ${bs.rbi}点', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: _muted))),
            ]),
          ]),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            backgroundColor: Colors.white,
            builder: (c) => SizedBox(height: MediaQuery.of(c).size.height * 0.7, child: _vsPanel(pad: 8)),
          ),
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          child: const Text('詳しく'),
        ),
      ]),
    );
  }

  /// 采配欄（案C）：分類のチップ（打撃・走塁・交代・速報 など）と、その分類のマス。オーダーもここから
  Widget _tacticsPanel() {
    if (_finished) return _tacticsBody(4);
    final tabs = widget.manage ? (_myBatting ? ['打撃', '走塁', '交代', '速報'] : ['投手', '配球', '守備', '交代', '速報']) : ['交代', '速報'];
    final cur = tabs.contains(_tacTab) ? _tacTab : tabs.first;
    Widget chip(String t, {VoidCallback? onTap, bool sel = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: sel ? const Color(0xFF0F172A) : Colors.white,
              shape: StadiumBorder(side: BorderSide(color: sel ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1))),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: SizedBox(height: 30, child: Center(child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: sel ? Colors.white : const Color(0xFF0F172A))))),
              ),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Row(children: [
          for (final t in tabs) chip(t, sel: t == cur, onTap: () => setState(() => _tacTab = t)),
          chip('オーダー', onTap: _showOrders),
        ]),
      ),
      Expanded(
        child: cur == '速報'
            ? Padding(padding: const EdgeInsets.all(4), child: _logBox())
            : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(6, 0, 6, 6), child: LayoutBuilder(builder: (context, c) => _tacticsBody(c.maxWidth >= 330 ? 4 : 3, only: cur))),
      ),
    ]);
  }

  /// コース（5×5のマス。捕手から見た並び。真ん中の3×3がストライク）と球種をその場で指定する
  ///  エンジンの列は「0＝内角」なので、左打者のときは見た目の左右を入れ替える
  Widget _courseAndPitch(int cols) {
    final pitcher = _myHome ? _s.homePitcher : _s.awayPitcher;
    final (_, order, slot, _) = _scene();
    final batter = order[slot % order.length];
    final lefty = batter.bats == 'S' ? pitcher.throws != 'L' : batter.bats == 'L'; // 両打ちは投手の逆
    Widget course(int dc, int r) {
      final cc = lefty ? 4 - dc : dc; // 見た目の列 → エンジンの列
      final sel = _col == cc && _row == r;
      final zone = cc >= 1 && cc <= 3 && r >= 1 && r <= 3;
      return Material(
        color: sel ? _lime : (zone ? const Color(0xFFDBEAFE) : const Color(0xFFF8FAFC)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3), side: BorderSide(color: sel ? _lime : (zone ? const Color(0xFF4F7CB0) : _edge))),
        child: InkWell(
          onTap: () => setState(() {
            if (sel) {
              _col = null;
              _row = null;
            } else {
              _col = cc;
              _row = r;
            }
          }),
          child: SizedBox(
            height: 22,
            child: Center(child: Text('${r * 5 + dc + 1}', style: TextStyle(fontSize: 11, color: sel ? _navy : (zone ? _text : _muted), fontWeight: sel || zone ? FontWeight.w800 : FontWeight.w500))),
          ),
        ),
      );
    }

    final kinds = [
      _cell('おまかせ', selected: _pitchName == null, enabled: true, h: 22, onTap: () => setState(() => _pitchName = null)),
      for (final p in pitcher.pitches)
        _cell(PitchCatalog.short(p.name), selected: _pitchName == p.name, enabled: true, h: 22, tip: '${p.name}　${p.speed}km/h　割合${p.ratio}%', onTap: () => setState(() {
          _pitchName = _pitchName == p.name ? null : p.name;
          // 球種だけを選んだときは、コースは真ん中
          if (_pitchName != null && _col == null) {
            _col = 2;
            _row = 2;
          }
        })),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 128,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Text(lefty ? '外' : '内', style: const TextStyle(color: _text, fontSize: 10, fontWeight: FontWeight.w900)),
              Expanded(child: Text('捕手から見て（${lefty ? '左' : '右'}打者）', textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 9))),
              Text(lefty ? '内' : '外', style: const TextStyle(color: _text, fontSize: 10, fontWeight: FontWeight.w900)),
            ]),
          ),
          for (var r = 0; r < 5; r++)
            Padding(
              padding: EdgeInsets.only(top: r == 0 ? 0 : 2),
              child: Row(children: [
                if (!lefty) _batterMark(),
                for (var dc = 0; dc < 5; dc++) ...[if (dc > 0) const SizedBox(width: 2), Expanded(child: course(dc, r))],
                if (lefty) _batterMark(),
              ]),
            ),
        ]),
      ),
      const SizedBox(width: 5),
      Expanded(child: _grid(kinds, 1)),
    ]);
  }

  /// エンジンの列 → 捕手から見た列（左打者は左右が逆）
  int _shownCol(int col) {
    final pitcher = _myHome ? _s.homePitcher : _s.awayPitcher;
    final (_, order, slot, _) = _scene();
    final b = order[slot % order.length];
    final lefty = b.bats == 'S' ? pitcher.throws != 'L' : b.bats == 'L';
    return lefty ? 4 - col : col;
  }

  /// 打者の立つ側の印（コースの表の横）
  Widget _batterMark() => Container(width: 4, height: 22, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: const Color(0xFFB91C1C), borderRadius: BorderRadius.circular(2)));

  // ---- 進行ボタン ----

  Widget _progress() {
    if (_finished) {
      return SizedBox(
        height: 50,
        child: FilledButton(
          onPressed: _primary,
          style: FilledButton.styleFrom(
            backgroundColor: _lime,
            foregroundColor: _navy,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          child: Text(_animating ? 'スキップ' : '結果を確定して戻る'),
        ),
      );
    }
    final perPitch = _perPitchMode;
    final outline = OutlinedButton.styleFrom(
      foregroundColor: _text,
      side: const BorderSide(color: Color(0xFF94A3B8)),
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 12),
    );
    // 1球ずつ／1人ずつの切り替え（小さめのトグル）
    Widget modeToggle() {
      Widget seg(bool v, String label) {
        final sel = _perPitch == v;
        return InkWell(
          onTap: () => setState(() => _perPitch = v),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            color: sel ? _lime : const Color(0xFFF1F5F9),
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: sel ? FontWeight.w800 : FontWeight.w500, color: sel ? _navy : _muted),
            ),
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: _edge),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(mainAxisSize: MainAxisSize.min, children: [seg(true, '1球ずつ'), seg(false, '1人ずつ')]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Tooltip(
                message: perPitch ? 'スペースキーでも進めます（W＝${_myBatting ? '待て' : '外せ'}）' : 'スペースキーでも進めます',
                child: SizedBox(
                  height: 42,
                  child: FilledButton.icon(
                    onPressed: _primary,
                    icon: Icon(perPitch ? Icons.sports_baseball : Icons.play_arrow),
                    label: Text(perPitch ? '次の1球' : '次の打者へ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _lime,
                      foregroundColor: _navy,
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ),
            if (perPitch) ...[
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton(
                    onPressed: _command,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _text,
                      side: const BorderSide(color: _lime),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_myBatting ? '待て' : '外せ', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.manage) modeToggle(),
            if (perPitch && _s.inPlateAppearance) OutlinedButton(onPressed: _nextBatter, style: outline, child: const Text('打席の最後まで')),
            OutlinedButton(onPressed: () => _auto(untilInningEnd: true), style: outline, child: const Text('回の終わりまで')),
            OutlinedButton(onPressed: () => _auto(untilInningEnd: false), style: outline, child: const Text('試合終了まで')),
          ],
        ),
      ],
    );
  }
}
