import 'dart:math';
import '../models/player.dart';
import 'defense_ai.dart';
import 'fielder_ai.dart';
import 'base_path.dart';
import 'field_time.dart';
import 'spec_constants.dart';

/// 2点間の距離（pow を使わない分だけ速い）
double _hypot(double a, double b) => sqrt(a * a + b * b);

/// 走者の動き（アニメーション・記録用）。塁: 0=本塁(打者) 1=一塁 2=二塁 3=三塁 4=本塁(生還)
class RunMove {
  final String name;
  final int from;
  final int to;     // 到達（またはアウトになった）塁
  final bool out;
  final double t0;  // 走り出し（打った瞬間=0 からの秒）
  final double t1;  // 到達
  final double? sStart; // 走り出す位置（レールの s。飛び出して戻る走者など。null なら塁かリード）
  RunMove(this.name, this.from, this.to, this.out, this.t0, this.t1, {this.sStart});
}

/// 送球（アニメーション用）
class ThrowLeg {
  final double x0, y0, x1, y1;
  final double t0, t1;
  ThrowLeg(this.x0, this.y0, this.x1, this.y1, this.t0, this.t1);
}

/// インプレーの結果
class PlayOutcome {
  List<String?> bases = [null, null, null]; // プレー後の一塁・二塁・三塁
  int runs = 0;
  int outs = 0;
  bool hit = false;       // 打者に安打が記録される
  int hitBases = 0;
  bool dp = false;        // 併殺（打点なし）
  bool tp = false;        // 三重殺
  bool sacFly = false;    // 犠牲フライ（打数に数えない）
  bool error = false;     // 失策で出塁（安打にしない。入った点は自責点・打点にしない）
  String desc = '';
  String code = '';       // 6-4-3 など
  final List<RunMove> moves = [];
  final List<ThrowLeg> throws = [];
}

/// 時間（秒）と距離（m）で、打球処理後の走者と送球の勝負を決める。
/// 座標: 本塁(0,0)、一塁(19.4,19.4)、二塁(0,38.8)、三塁(-19.4,19.4)
///  判断（defense_ai.dart）：9人の役割を割り当て、送球先は得点期待値で選ぶ。走者も期待値で進むか決める。
///  判断は見積もりのぶれ（判断力・重圧）を含むので、いつも最善とは限らない
class PlayResolver {
  /// 外野からの送球で、受けてから滑り込む走者にタッチするまで（秒）
  static double tagTime = 0.25; // 捕って、滑り込む走者へタッチするまで（送球が少しそれる分も）
  final Random r;
  final Map<String, FielderState> fielders; // role → 野手（start 位置は fielderStart）
  final Map<String, List<double>> start;
  final double runAdj;   // 積極走塁 +0.15 / 慎重走塁 −0.15
  final bool hitRun;     // ヒットエンドラン（一塁走者がスタートしている）
  final bool infieldIn;  // 前進守備
  final bool rightSide;  // 右狙いで右方向へ打った（走者が進みやすい）
  final bool batterLefty; // 左打席（一塁へ近く、スイングの勢いが一塁向き）
  final bool slowBall;   // 打球が弱い（素手で拾ってスナップスロー）
  final double pressure; // 重圧（終盤・接戦・得点圏 0〜1）
  final double runWeight; // 1点の重み（前進守備・終盤の接戦で大きい）
  PlayResolver(this.r, this.fielders, this.start,
      {this.runAdj = 0, this.hitRun = false, this.infieldIn = false, this.rightSide = false, this.batterLefty = false, this.slowBall = false, this.pressure = 0, this.runWeight = 1});

  static const List<List<double>> basePos = [[0, 0], [19.4, 19.4], [0, 38.8], [-19.4, 19.4], [0, 0]];
  static const Map<String, int> posNo = {'P': 1, 'C': 2, '1B': 3, '2B': 4, '3B': 5, 'SS': 6, 'LF': 7, 'CF': 8, 'RF': 9};
  static const double basePath = 27.43;
  static final Map<String, int> stats = {};
  static void _s(String k) => stats[k] = (stats[k] ?? 0) + 1;

  /// 最後に割り当てた役割（3D・アニメーション用）
  DefensePlan? lastPlan;

  double _g() => ThrowChoice.gauss(r);

  double _dist(double x0, double y0, double x1, double y1) => _hypot(x1 - x0, y1 - y0);
  double runSpeed(Player p) => Sprint.of(p.run).vTop;                      // 最高速（m/s。走力60で8.7、100で9.5）
  double runnerSpeed(Player p) => runSpeed(p);                              // 塁上の走者（リードから走っている）
  double batterTo1B(Player b) => Running.batterTo1B(b, lefty: batterLefty); // 脱出＋加速＋全力（平均約4.1〜4.3秒）
  double infieldThrow(Player p) => ThrowStyle.standard.speed * ThrowStyle.armFactor(p); // 内野の送球（142km/h 基準）
  double outfieldThrow(Player p) => ThrowStyle.crowHop.speed * ThrowStyle.armFactor(p); // 外野の遠投（155km/h 基準。遠いほど失速）
  /// 内野手が捕ってから塁へ投げて届くまで（投げ方は時間が最短のものを選ぶ）
  double _infieldThrowTime(Player f, double d, {bool deep = false}) => ThrowStyle.best(f, d, ballSlow: slowBall, deepHole: deep).t;

  Player? _p(String role) => fielders[role]?.player;
  List<double> _startOf(String role) => start[role] ?? FielderAI().basePositions[role] ?? [0, 0];

  /// 役割の割り当てに使う野手の情報
  Map<String, DefenderInfo> _info() => {
        for (final e in fielders.entries)
          e.key: DefenderInfo(e.key, e.value.player, _startOf(e.key)[0], _startOf(e.key)[1], e.value.reactionDelay, Sprint(e.value.speed, e.value.accel), e.value.judgment),
      };

  double _judgOf(String role) => fielders[role]?.judgment ?? 50;

  static int bitsOf(List<Player?> runners) => (runners[0] != null ? 1 : 0) | (runners[1] != null ? 2 : 0) | (runners[2] != null ? 4 : 0);

  /// 走者 b（1〜3）のフォース：一塁から連続して埋まっている
  static int forcedUpTo(List<Player?> runners) {
    if (runners[0] == null) return 0;
    if (runners[1] == null) return 1;
    return runners[2] == null ? 2 : 3;
  }

  // =====================================================================
  // ゴロ（内野で処理）
  // =====================================================================
  /// fx,fy: 捕球地点 / tBall: 送球できる時刻 / runners: 一塁〜三塁の走者（なしは null）
  PlayOutcome groundBall({
    required String role,
    required double fx,
    required double fy,
    required double tBall,
    required Player batter,
    required List<Player?> runners,
    required int outsBefore,
    bool bunt = false,
  }) {
    final o = PlayOutcome();
    final f = _p(role)!;
    final bits = bitsOf(runners);
    final plan = DefensePlan.assign(
        d: _info(), primary: role, fx: fx, fy: fy, tField: tBall, ballClass: bunt ? BallClass.bunt : BallClass.grounder, bits: bits, outs: outsBefore, batterLefty: batterLefty, pressure: pressure);
    lastPlan = plan;
    final jf = _judgOf(role);
    final sigF = Judgment.readSigma(jf, pressure);
    final nRun = (bits & 1) + ((bits >> 1) & 1) + ((bits >> 2) & 1);
    // 捕ってから送球先を決めるまでの迷い（走者が多いほど選択肢が多い）
    final tHold = tBall + Judgment.hesitation(jf, pressure) * (nRun >= 2 ? 1.4 : (nRun == 1 ? 1.0 : 0.25));
    final twoOut = outsBefore == 2;
    final bt = batterTo1B(batter) + _g() * 0.12;
    final forced = forcedUpTo(runners);

    // ---- 塁に入る野手・送球が届く時刻 ----
    String coverOf(int base) => plan.cover[base] ?? const ['', '1B', 'SS', '3B', 'C'][base];
    double coverAt(int base) => plan.coverAt[base] ?? 0;
    ({double t, bool self, double rel}) reach(int base, String holder, double hx, double hy, double tr, {bool pivot = false}) {
      final b = basePos[base];
      final d = _dist(hx, hy, b[0], b[1]);
      final cov = coverOf(base);
      if (cov == holder || d < 3.5) return (t: tr + d / 6.5, self: true, rel: tr); // 自分でベースを踏む
      final hp = _p(holder) ?? f;
      final double fl;
      var hold = 0.0; // 持ってから放すまで（握り替え）
      if (pivot) {
        fl = ThrowStyle.flight(d, ThrowStyle.sidearm.speed * ThrowStyle.armFactor(hp)); // 併殺の転送：握り替えは済み
      } else if (d < 10) {
        fl = 0.30 + d / 14;
        hold = 0.30; // 二遊間の近い送球はトス（グラブトス・バックトス）
      } else {
        final bs = ThrowStyle.best(hp, d, ballSlow: slowBall, deepHole: hy > 40 && hx.abs() > 6);
        fl = bs.t;
        hold = bs.style.transferOf(hp) + hp.glove.transferDelay;
      }
      final tThrow = max(tr + fl, coverAt(base));
      // 塁が近ければ、自分で踏みに行くほうが早いこともある（一塁手がベース近くで捕った・三塁手が三塁の近く）
      if (d < 12 && !pivot && tr + d / 6.8 < tThrow) return (t: tr + d / 6.8, self: true, rel: tr);
      return (t: tThrow, self: false, rel: tr + hold + (tThrow - tr - fl)); // 受ける人が遅ければ待って投げる
    }

    double arriveAt(int base, String holder, double hx, double hy, double tr, {bool pivot = false}) => reach(base, holder, hx, hy, tr, pivot: pivot).t;

    // ---- 走者：フォースの走者は打球と同時に走る。フォースでない走者は期待値で進むか決める ----
    final going = List<bool>.filled(4, false); // 塁（1〜3）の走者が次へ走る
    final tNext = List<double>.filled(4, double.infinity); // 次の塁に着く時刻（実際）
    final t0 = List<double>.filled(4, 0.15);
    for (int b = 1; b <= 3; b++) {
      final p = runners[b - 1];
      if (p == null) continue;
      if (b <= forced) {
        final lead = b == 1 ? 3.5 : 4.5;
        final started = (b == 1 && hitRun) || twoOut;
        going[b] = true;
        t0[b] = started ? 0.0 : 0.15;
        tNext[b] = Running.runnerTo(p, from: b, lead: lead, to: b + 1, react: 0.15, started: started) + _g() * 0.10;
      }
    }
    // フォースでない走者（先の塁の走者から）：見積もった守備の時間と自分の走る時間を比べ、期待値で決める
    for (int b = 3; b >= 2; b--) {
      final p = runners[b - 1];
      if (p == null || b <= forced) continue;
      final target = b + 1;
      if (target <= 3 && runners[target - 1] != null && !going[target]) continue; // 先の塁が空かない
      final jr = Judgment.runner(p);
      final lead = b == 3 ? 4.0 : 5.0; // 第2リード
      final tDecide = twoOut ? 0.0 : 0.15 + Judgment.hesitation(jr, pressure);
      final tRun = tDecide + Running.runnerTo(p, from: b, lead: lead, to: target, react: 0, v0: twoOut ? 3.0 : 1.5) + _g() * 0.10;
      final tDef = arriveAt(target, role, fx, fy, tHold) + 0.1; // タッチまで
      if (twoOut) {
        going[b] = true;
      } else {
        final seen = tDef - tRun + _g() * Judgment.readSigma(jr, pressure);
        final pSafe = 1 - ThrowChoice.pOut(-seen);
        final bitsNoMe = bits & ~(1 << (b - 1));
        final vHold = RunValue.re(bits, outsBefore + 1); // 止まる → 打者が一塁でアウト
        final vSafe = RunValue.value(target == 4 ? 1 : 0, (bitsNoMe | 1) | (target < 4 ? 1 << (target - 1) : 0), outsBefore);
        final vOut = RunValue.re(bitsNoMe | 1, outsBefore + 1);
        going[b] = pSafe * vSafe + (1 - pSafe) * vOut + runAdj * 0.4 > vHold;
      }
      if (going[b]) {
        tNext[b] = tRun;
        t0[b] = tDecide;
      }
    }

    // ---- 送球先の候補：フォース・タッチ・一塁の、降順の並び（最大で残りのアウト数）----
    final cands = <int>[
      for (int t = 4; t >= 2; t--)
        if (runners[t - 2] != null && going[t - 1]) t,
      1,
    ];
    // 仕様書 1.3：フォースは後ろの走者（打者）が詰まっている間だけ。打者が先にアウトになれば、前の走者はタッチが要る
    bool isTag(int base, [List<int> before = const []]) => base >= 2 && ((base - 1) > forced || before.contains(1));
    double runnerAt(int base) => base == 1 ? bt : tNext[base - 1];
    final maxOuts = 3 - outsBefore;
    final chains = <List<int>>[];
    void build(List<int> cur, int from) {
      if (cur.isNotEmpty) chains.add(List.of(cur));
      if (cur.length >= maxOuts) return;
      for (int i = from; i < cands.length; i++) {
        cur.add(cands[i]);
        build(cur, i + 1);
        cur.removeLast();
      }
    }

    build([], 0);
    // 一塁手がベースの近くで捕った：先に一塁を踏んでから二塁へ（3-6。二塁はタッチプレー）
    if (role == '1B' && _dist(fx, fy, 19.4, 19.4) < 6 && runners[0] != null && maxOuts >= 2) chains.add([1, 2]);

    // 野手の見積もり：走者ごとに1つのぶれ
    final seenNoise = <int, double>{for (final c in cands) c: _g() * sigF};
    const pivotMean = 0.45;

    /// 並び c の結果（k 個目まで成功）での攻撃側の価値
    double valueAfter(List<int> c, int k) {
      final outBases = c.take(k).toSet(); // アウトにした走者（塁で表す：1=打者）
      var nb = 0, runs = 0;
      for (int b = 1; b <= 3; b++) {
        if (runners[b - 1] == null) continue;
        if (outBases.contains(b + 1)) continue;
        final to = going[b] ? b + 1 : b;
        if (to == 4) {
          runs++;
        } else {
          nb |= 1 << (to - 1);
        }
      }
      if (!outBases.contains(1)) nb |= 1;
      final outs = outsBefore + k;
      if (outs >= 3) return 0;
      return RunValue.value(runs, nb, outs, runWeight: runWeight);
    }

    double expected(List<int> c) {
      var holder = role;
      var hx = fx, hy = fy, tr = tHold;
      var pAll = 1.0, ev = 0.0;
      for (int i = 0; i < c.length; i++) {
        final base = c[i];
        final rc = reach(base, holder, hx, hy, tr, pivot: i > 0);
        final arr = rc.t + (isTag(base, c.sublist(0, i)) ? 0.1 : 0);
        final pi = ThrowChoice.pOut(runnerAt(base) - arr + seenNoise[base]!);
        ev += pAll * (1 - pi) * valueAfter(c, i);
        pAll *= pi;
        if (!rc.self) holder = coverOf(base);
        hx = basePos[base][0];
        hy = basePos[base][1];
        tr = arr + pivotMean;
        // 悪送球の危険（遠い・体勢が崩れた送球ほど）
        ev += 0.02 * (1 - (_p(holder) ?? f).throwAccuracy / 100) * _dist(hx, hy, fx, fy) / 30;
      }
      return ev + pAll * valueAfter(c, c.length);
    }

    var best = <int>[1];
    var bestV = double.infinity;
    for (final c in chains) {
      final v = expected(c);
      if (v < bestV) {
        bestV = v;
        best = c;
      }
    }
    _s('gb');

    // ---- 実行：実際の時間で勝負 ----
    final fNo = posNo[role]!;
    var code = '$fNo';
    var holder = role;
    var hx = fx, hy = fy, tr = tHold;
    final outBases = <int>[];
    int? failedAt;
    bool rundown = false;
    for (int i = 0; i < best.length; i++) {
      final base = best[i];
      final b = basePos[base];
      final cov = coverOf(base);
      final rc = reach(base, holder, hx, hy, tr, pivot: i > 0);
      final arr = rc.t;
      final selfStep = rc.self;
      if (!selfStep) {
        o.throws.add(ThrowLeg(hx, hy, b[0], b[1], rc.rel, arr));
        code += '-${posNo[cov]}';
      }
      final tag = isTag(base, outBases);
      final tR = runnerAt(base);
      final out = arr + (tag ? 0.1 : 0) < tR;
      if (tag && tR - arr > 0.8) {
        // 走者は完全に挟まれる：挟殺（ランダウン）。多くはアウト、まれに元の塁へ戻る
        rundown = true;
        if (r.nextDouble() < 0.88 + _judgOf(cov) * 0.001) {
          outBases.add(base);
        } else {
          failedAt = base;
        }
        break;
      }
      if (!out) {
        failedAt = base;
        break;
      }
      outBases.add(base);
      if (!selfStep) holder = cov;
      hx = b[0];
      hy = b[1];
      final pv = _p(holder) ?? f;
      tr = arr + 0.35 + (70 - pv.throwAccuracy).clamp(0, 50) * 0.005 + r.nextDouble() * 0.2;
    }

    // ---- 3D 用の動作：捕球 → 握り替え → ステップ → 送球（併殺の二塁はピボット）----
    {
      final b0 = basePos[best.first];
      final d0 = _dist(fx, fy, b0[0], b0[1]);
      final st = ThrowStyle.best(f, d0, ballSlow: slowBall, deepHole: fy > 40 && fx.abs() > 6).style;
      plan.addPlay(role,
          catchMotion: identical(st, ThrowStyle.bare) ? Motion.fieldForehand : (identical(st, ThrowStyle.jump) ? Motion.fieldBackhand : Motion.fieldGroundStd),
          tCatch: tBall,
          transfer: d0 < 10 ? Motion.transferFlip : (best.length >= 2 ? Motion.transferQuick : Motion.transferStd),
          footwork: d0 < 10 ? null : Motion.proStep,
          throwMotion: d0 < 10 ? null : DefensePlan.throwMotion(st),
          tThrow: tHold + st.transfer);
      if (best.length >= 2 && outBases.isNotEmpty) {
        final piv = coverOf(best.first);
        plan.duties[piv]?.motions.addAll([MotionKey(best.first == 2 ? Motion.pivot2B : Motion.baseSetupForce, tHold + 0.8), MotionKey(Motion.throwSideUnder, tHold + 1.2)]);
      }
    }

    // ---- 結果の組み立て ----
    final newBases = <String?>[null, null, null];
    var runs = 0;
    for (int b = 3; b >= 1; b--) {
      final p = runners[b - 1];
      if (p == null) continue;
      if (outBases.contains(b + 1)) {
        o.moves.add(RunMove(p.registeredName, b, b + 1, true, t0[b], tNext[b]));
        continue;
      }
      var to = going[b] ? b + 1 : b;
      if (rundown && failedAt == b + 1) to = b; // 挟まれて元の塁へ戻った
      if (to <= 3 && newBases[to - 1] != null) to = b;
      o.moves.add(RunMove(p.registeredName, b, to, false, t0[b], to == b ? t0[b] : tNext[b]));
      if (to == 4) {
        runs++;
      } else {
        newBases[to - 1] = p.registeredName;
      }
    }
    final batterOut = outBases.contains(1);
    o.moves.add(RunMove(batter.registeredName, 0, 1, batterOut, 0, bt));
    if (!batterOut) newBases[0] = batter.registeredName;
    o.outs = outBases.length;
    if (outsBefore + o.outs >= 3) {
      runs = 0; // 3アウト目がフォース・打者アウトなら得点なし（挟殺のタッチは時刻しだいだが、ここでは得点なし）
      o.bases = [runners[0]?.registeredName, runners[1]?.registeredName, runners[2]?.registeredName];
    } else {
      o.bases = newBases;
    }
    o.runs = runs;
    o.code = code == '$fNo' && batterOut ? '${fNo}A' : code;
    o.dp = o.outs >= 2;
    o.tp = o.outs >= 3;

    if (o.tp) {
      _s('gbTP');
      o.desc = '${role}ゴロ（$code のトリプルプレー！）';
    } else if (o.dp) {
      _s('gbDP');
      o.desc = '${role}ゴロ（$code の併殺）';
    } else if (rundown) {
      _s('gbRundown');
      o.desc = outBases.isNotEmpty ? '${role}ゴロ（飛び出した走者を挟殺）' : '${role}ゴロ（走者は挟まれるも帰塁）';
    } else if (o.outs == 1 && !batterOut) {
      _s(isTag(outBases.first) ? 'gbTagOut' : 'gbForce');
      final bn = outBases.first == 4 ? '本塁' : '${outBases.first}塁';
      o.desc = isTag(outBases.first) ? '${role}ゴロ（$code、$bnでタッチアウト）' : '${role}ゴロ（$code、$bnでフォースアウト）';
    } else if (o.outs == 1) {
      _s('gb1B');
      o.desc = '${role}ゴロ（${o.code.endsWith('A') ? 'ベースを踏んで' : o.code}アウト）';
    } else if (best.first == 1) {
      // 一塁へ投げて間に合わなかった：内野安打
      _s('gbHit');
      o.hit = true;
      o.hitBases = 1;
      o.desc = '${role}の内野安打';
    } else {
      // 先の走者を狙って間に合わなかった：野選
      _s('gbFC');
      o.desc = '${role}ゴロ（野選。${best.first == 4 ? '本塁' : '${best.first}塁'}は間に合わず）';
    }
    return o;
  }

  // =====================================================================
  // 外野からの送球（中継・ダイレクト）
  // =====================================================================
  /// 送球を受ける中継の野手（役割の割り当てがあればそれに従う）
  String _cutoffFor(int base, double fx) {
    final plan = lastPlan;
    if (plan != null && plan.cutoffs.isNotEmpty) {
      if (base == 4 && plan.cutoffs.contains('3B')) return '3B';
      if (base == 4 && plan.cutoffs.contains('1B')) return '1B';
      if (base != 4) {
        for (final c in plan.cutoffs) {
          if (c == 'SS' || c == '2B') return c;
        }
      }
    }
    if (base == 4) return fx < -15 ? '3B' : '1B';
    if (base == 3) return 'SS';
    return fx < 0 ? 'SS' : '2B';
  }

  /// 外野の地点から塁へボールが届く時刻と送球経路
  ///  中継の位置は、外野の返球と中継の送球の合計が最短になる所（中継の判断力でずれる）。中継が間に合う所まで
  ({double t, List<ThrowLeg> legs, String via, double cutX, double cutY, double tCut, String cut}) _throwToBase(String role, double fx, double fy, double tRelease, int base, {bool noise = true}) {
    final f = _p(role)!;
    final b = basePos[base];
    final d = _dist(fx, fy, b[0], b[1]);
    final vd = outfieldThrow(f);
    // ダイレクト: 肩が強いほど遠くまで届く。遠投は制球のぶれ（送球がそれて時間がかかる）あり
    final maxDirect = 45 + f.arm * 0.45;
    double tDirect = double.infinity;
    if (d <= maxDirect) {
      // それた送球は受けてから追い直す（仕様書：送球の角度の誤差。届く範囲 2m を外れたら）
      final double wild;
      if (!noise) {
        wild = 0;
      } else if (Spec.thr) {
        final s = Spec.throwAngleSigma(f.throwAccuracy) * pi / 180;
        wild = (d * tan(_g() * s)).abs() > 2.0 || (d * tan(_g() * s)).abs() > 2.0 ? 0.6 : 0.0;
      } else {
        wild = r.nextDouble() < (1 - f.throwAccuracy / 100) * 0.35 ? 0.6 : 0.0;
      }
      tDirect = tRelease + ThrowStyle.flight(d, vd) + wild;
    }
    // 中継: 内野手が途中で受けて投げる
    final cut = _cutoffFor(base, fx);
    final cp = _p(cut) ?? f;
    final cs = fielders[cut];
    final cst = _startOf(cut);
    final vr = ThrowStyle.standard.speed * ThrowStyle.armFactor(cp);
    var bestT = double.infinity, bestK = 0.55;
    for (var k = 0.30; k <= 0.80; k += 0.05) {
      final cx = fx + (b[0] - fx) * k, cy = fy + (b[1] - fy) * k;
      final tc = tRelease + ThrowStyle.flight(_dist(fx, fy, cx, cy), vd);
      // 中継が間に合わない所には立てない
      if (cs != null && cs.reactionDelay + Sprint(cs.speed, cs.accel).time(_dist(cst[0], cst[1], cx, cy)) > tc) continue;
      final t = tc + 0.55 + ThrowStyle.flight(_dist(cx, cy, b[0], b[1]), vr);
      if (t < bestT) {
        bestT = t;
        bestK = k;
      }
    }
    final jc = _judgOf(cut);
    final cx = fx + (b[0] - fx) * bestK, cy = fy + (b[1] - fy) * bestK;
    final d1 = _dist(fx, fy, cx, cy), d2 = _dist(cx, cy, b[0], b[1]);
    final tCatchCut = tRelease + ThrowStyle.flight(d1, vd);
    final lineErr = noise ? r.nextDouble() * (100 - jc) * 0.002 : 0.0; // 送球のライン上に立てていない
    final tRelay = tCatchCut + 0.55 + lineErr + (noise ? r.nextDouble() * 0.15 : 0.075) + ThrowStyle.flight(d2, vr); // 中継は超高速の握り替え（約0.55秒）
    if (tDirect <= tRelay) {
      return (t: tDirect, legs: [ThrowLeg(fx, fy, b[0], b[1], tRelease, tDirect)], via: 'ダイレクト', cutX: cx, cutY: cy, tCut: tCatchCut, cut: cut);
    }
    return (
      t: tRelay,
      legs: [ThrowLeg(fx, fy, cx, cy, tRelease, tCatchCut), ThrowLeg(cx, cy, b[0], b[1], tCatchCut + 0.55, tRelay)],
      via: '$cut中継',
      cutX: cx,
      cutY: cy,
      tCut: tCatchCut,
      cut: cut
    );
  }

  /// 外野の地点から塁へボールが届く時刻（ダイレクトか中継の速いほう。ばらつきなし）
  double throwTime(String role, double fx, double fy, double tRelease, int base) => _throwToBase(role, fx, fy, tRelease, base, noise: false).t;

  /// 走者（と三塁コーチ）の見積もり：守備の時間 − 走る時間 にぶれを足し、セーフになる確率にする
  double _pSafeSeen(Player p, double margin) {
    final j = (Judgment.runner(p) + 60) / 2; // 三塁コーチの判断（約60）も合わせる
    final seen = margin + _g() * Judgment.readSigma(j, pressure);
    return 1 / (1 + exp(-seen / 0.12)); // 実際の結果にも 0.2秒のばらつきがあるので緩め
  }

  /// 外野への安打。batterBases は打者の到達塁（1〜3）。tField: 外野手がボールを持つ時刻
  PlayOutcome outfieldHit({
    required String role,
    required double fx,
    required double fy,
    required double tField,
    required int batterBases,
    required Player batter,
    required List<Player?> runners,
    required int outsBefore,
    required bool flyBall,
    int batterOutAt = 0, // 打者走者が先の塁を狙って刺された塁（0 なし）
  }) {
    final o = PlayOutcome();
    o.hit = true;
    o.hitBases = batterBases;
    final bits = bitsOf(runners);
    final dist0 = _hypot(fx, fy);
    lastPlan = DefensePlan.assign(
        d: _info(), primary: role, fx: fx, fy: fy, tField: tField, ballClass: dist0 > 85 ? BallClass.gap : (flyBall ? BallClass.fly : BallClass.liner), bits: bits, outs: outsBefore, batterLefty: batterLefty, pressure: pressure);
    final jOF = _judgOf(role);
    final tRelease = tField + ThrowStyle.crowHop.transfer + (_p(role)?.glove.transferDelay ?? 0) + Judgment.hesitation(jOF, pressure) * 0.5; // クロウホップで投げるまで
    final twoOut = outsBefore == 2;

    // ---- 1) 走者ごとに：最低限の塁（打者の塁打ぶん）と、もう1つ先を狙うか ----
    final minTo = List<int>.filled(4, 0), tryTo = List<int>.filled(4, 0);
    final tStart = List<double>.filled(4, 0), tArr = List<double>.filled(4, 0), tArrExtra = List<double>.filled(4, 0);
    final occupied = <int>{}; // 先の走者が入る塁
    for (int b = 3; b >= 1; b--) {
      final p = runners[b - 1];
      if (p == null) continue;
      // スタート: 2アウトは打った瞬間、フライは落ちるのを見てから（判断力で早い・遅い）
      final jr = Judgment.runner(p);
      final t0 = twoOut ? 0.0 : (flyBall ? 0.7 + Judgment.hesitation(jr, pressure) * 2 : 0.25 + Judgment.hesitation(jr, pressure));
      final lead = b == 1 ? 3.5 : 5.0;
      var to = min(4, b + batterBases);
      while (to < 4 && occupied.contains(to)) {
        to--;
      }
      minTo[b] = to;
      tStart[b] = t0;
      tArr[b] = t0 + Running.runnerTo(p, from: b, lead: lead, to: to, react: 0, v0: 2.5);
      tryTo[b] = to;
      final extra = to + 1;
      if (to < 4 && !occupied.contains(extra) && extra <= 4) {
        final tRun = t0 + Running.runnerTo(p, from: b, lead: lead, to: extra, react: 0, v0: 2.5);
        final thr = _throwToBase(role, fx, fy, tRelease, extra, noise: false);
        final pSafe = _pSafeSeen(p, thr.t + tagTime - 0.12 - tRun); // 走者の見積もりは従来どおり 0.12 を基準に
        // 期待値：止まる / 狙ってセーフ / 狙ってアウト（ほかの走者は打者の塁打ぶん進むとして）
        final bitsHold = (1 << (batterBases - 1)) | (to < 4 ? 1 << (to - 1) : 0);
        final runHold = to == 4 ? 1 : 0;
        final vHold = RunValue.value(runHold, bitsHold, outsBefore);
        final vSafe = RunValue.value(extra == 4 ? 1 : 0, (1 << (batterBases - 1)) | (extra < 4 ? 1 << (extra - 1) : 0), outsBefore);
        final vOut = RunValue.value(0, 1 << (batterBases - 1), outsBefore + 1);
        if (pSafe * vSafe + (1 - pSafe) * vOut + runAdj * 0.4 > vHold) {
          tryTo[b] = extra;
          tArrExtra[b] = tRun;
        }
      }
      occupied.add(tryTo[b]);
    }

    // ---- 2) 外野手の送球先：先を狙う走者のうち、期待値でいちばん得になる塁（狙わなければ二塁へ返して打者を止める）----
    int? target; // 送球を受ける走者の元の塁
    var bestGain = 0.02;
    for (int b = 3; b >= 1 && batterOutAt == 0; b--) { // 打者走者を刺しにいく送球なら、前の走者には投げない
      if (runners[b - 1] == null || tryTo[b] == minTo[b]) continue;
      final thr = _throwToBase(role, fx, fy, tRelease, tryTo[b], noise: false);
      final seen = tArrExtra[b] - thr.t + _g() * Judgment.readSigma(jOF, pressure);
      final pOut = 1 / (1 + exp(-(seen - 0.12) / 0.12));
      // アウトにした場合の得（得点期待値の差）。本塁なら1点も防ぐ
      final batBit = 1 << (batterBases - 1);
      final vS = RunValue.value(tryTo[b] == 4 ? 1 : 0, batBit | (tryTo[b] < 4 ? 1 << (tryTo[b] - 1) : 0), outsBefore, runWeight: runWeight);
      final vO = RunValue.value(0, batBit, outsBefore + 1, runWeight: runWeight);
      final gain = pOut * (vS - vO);
      if (gain > bestGain) {
        bestGain = gain;
        target = b;
      }
    }

    // ---- 3) 実行 ----
    final newBases = <String?>[null, null, null];
    int outs = outsBefore;
    double? thirdOutTime;
    String throwNote = '';
    ({double t, List<ThrowLeg> legs, String via, double cutX, double cutY, double tCut, String cut})? thrown;
    bool cutOff = false;
    for (int b = 3; b >= 1; b--) {
      final p = runners[b - 1];
      if (p == null) continue;
      final to = tryTo[b];
      if (b == target) {
        final thr = _throwToBase(role, fx, fy, tRelease, to);
        thrown = thr;
        final safe = (tArrExtra[b] + _g() * 0.2) < thr.t + tagTime;
        // 本塁が明らかに間に合わない：捕手の「カット！」で中継が止め、後ろの走者を狙う
        if (to == 4 && thr.via != 'ダイレクト' && tArrExtra[b] + 0.35 < thr.t) {
          cutOff = true;
          o.throws.add(thr.legs.first);
          o.moves.add(RunMove(p.registeredName, b, to, false, tStart[b], tArrExtra[b]));
          o.runs++;
          throwNote = '（本塁は間に合わず、${thr.cut}がカット）';
          continue;
        }
        o.throws.addAll(thr.legs);
        if (safe) {
          o.moves.add(RunMove(p.registeredName, b, to, false, tStart[b], tArrExtra[b]));
          if (to == 4) {
            o.runs++;
          } else {
            newBases[to - 1] = p.registeredName;
          }
          throwNote = '（${thr.via}の送球も間に合わず）';
        } else {
          outs++;
          o.outs++;
          o.moves.add(RunMove(p.registeredName, b, to, true, tStart[b], thr.t + 0.1));
          throwNote = '（${p.registeredName}は${to == 4 ? '本塁' : '$to塁'}で${thr.via}の送球にタッチアウト）';
          if (outs >= 3) thirdOutTime = thr.t;
        }
        continue;
      }
      // 送球が来ない走者：狙った塁まで進む
      final tt = to == tryTo[b] && to != minTo[b] ? tArrExtra[b] : tArr[b];
      o.moves.add(RunMove(p.registeredName, b, to, false, tStart[b], tt));
      if (to == 4) {
        o.runs++;
      } else {
        newBases[to - 1] = p.registeredName;
      }
    }

    // ---- 4) 打者走者：送球が本塁・三塁へ向かう間に次の塁を奪うか（中継がカットすれば刺される）----
    int bb = batterBases;
    final tB = Running.batterToBase(batter, bb, lefty: batterLefty);
    if (batterOutAt > 0) {
      final nb = basePos[batterOutAt];
      final tOut = throwTime(role, fx, fy, tRelease, batterOutAt) + 0.1;
      outs++;
      o.outs++;
      o.throws.add(ThrowLeg(fx, fy, nb[0], nb[1], tRelease, tOut - 0.1));
      o.moves.add(RunMove(batter.registeredName, 0, batterOutAt, true, 0, tOut));
      if (outs >= 3) thirdOutTime ??= tOut;
      bb = -1;
    } else if (thrown != null && bb < 3 && newBases[bb] == null && outs < 3) {
      final next = bb + 1;
      final tBn = Running.batterToBase(batter, next, lefty: batterLefty) + _g() * 0.15;
      // 中継（またはカット）から次の塁へ
      final nb = basePos[next];
      final cp = _p(thrown.cut) ?? _p(role)!;
      final tCutThrow = thrown.tCut + 0.55 + ThrowStyle.flight(_dist(thrown.cutX, thrown.cutY, nb[0], nb[1]), ThrowStyle.standard.speed * ThrowStyle.armFactor(cp));
      final pSafe = _pSafeSeen(batter, (cutOff ? tCutThrow : thrown.t + 1.2) - tBn);
      if (pSafe > 0.55 - runAdj) {
        if (cutOff && tCutThrow + 0.1 < tBn) {
          outs++;
          o.outs++;
          o.throws.add(ThrowLeg(thrown.cutX, thrown.cutY, nb[0], nb[1], thrown.tCut + 0.55, tCutThrow));
          o.moves.add(RunMove(batter.registeredName, 0, next, true, 0, tCutThrow + 0.1));
          throwNote += '（打者走者は${next}塁を狙うもタッチアウト）';
          if (outs >= 3) thirdOutTime ??= tCutThrow;
          bb = -1;
        } else {
          bb = next; // 送球の間に進む（記録は安打の塁打のまま）
          throwNote += '（送球の間に打者は$next塁へ）';
        }
      }
    }
    if (bb > 0) {
      o.moves.add(RunMove(batter.registeredName, 0, bb, false, 0, bb == batterBases ? tB : Running.batterToBase(batter, bb, lefty: batterLefty)));
      if (outs < 3) newBases[bb - 1] = batter.registeredName;
    }
    // 刺しにいく送球がなかった：外野手は中継に返し、中継が打者走者の次の塁（二塁か三塁）へ返す（走者を止める）
    if (thrown == null && batterOutAt == 0 && o.throws.isEmpty) {
      final tb = bb >= 2 ? 3 : 2;
      final thr = _throwToBase(role, fx, fy, tRelease, tb, noise: false);
      o.throws.addAll(thr.legs);
    }
    if (thirdOutTime != null) {
      // 3アウト目より後に生還した走者の得点は無効
      o.runs = o.moves.where((m) => m.to == 4 && !m.out && m.t1 < thirdOutTime!).length;
      o.bases = [null, null, null];
    } else {
      o.bases = newBases;
    }
    o.desc = throwNote;
    return o;
  }

  // =====================================================================
  // フライ・ライナーの捕球後：タッチアップ・飛び出した走者の帰塁（併殺・三重殺）
  // =====================================================================
  PlayOutcome flyOut({
    required String role,
    required double fx,
    required double fy,
    required double tCatch,
    required List<Player?> runners,
    required int outsBefore,
    bool liner = false,
  }) {
    final o = PlayOutcome();
    o.outs = 1;
    final newBases = [runners[0]?.registeredName, runners[1]?.registeredName, runners[2]?.registeredName];
    final bits = bitsOf(runners);
    final depth = sqrt(fx * fx + fy * fy);
    final outfielder = DefensePlan.outfield.contains(role);
    lastPlan = DefensePlan.assign(
        d: _info(), primary: role, fx: fx, fy: fy, tField: tCatch, ballClass: liner ? BallClass.liner : (outfielder ? BallClass.fly : BallClass.popup), bits: bits, outs: outsBefore, batterLefty: batterLefty, pressure: pressure);
    if (outsBefore + 1 >= 3) {
      o.bases = newBases;
      return o;
    }
    final f = _p(role)!;

    // ---- 飛び出した走者：エンドランで走っていた一塁走者、ライナーを読み違えた走者 ----
    var outs = outsBefore + 1;
    var holder = role;
    var hx = fx, hy = fy;
    var tr = tCatch + (outfielder ? ThrowStyle.crowHop.transfer : 0.45);
    for (int b = 1; b <= 3 && outs < 3; b++) {
      final p = runners[b - 1];
      if (p == null) continue;
      final jr = Judgment.runner(p);
      double off = 0; // 塁から離れている距離（m）
      if (b == 1 && hitRun) {
        off = min(basePath - 1, 3.5 + Sprint.of(p.run).distance(tCatch + 0.25, v0: 2.0));
        if (!liner) off = min(off, 10 + jr * 0.05); // フライは見えるので、途中で止まって様子を見る
      } else if (liner && r.nextDouble() < 0.03 + (100 - jr) * 0.0015 + pressure * 0.02) {
        off = (b == 1 ? 3.5 : 5.0) + 2 + r.nextDouble() * 3; // 打球が抜けると思って飛び出した
      }
      if (off < 6) continue; // 普通のリード：楽に戻れる
      // 帰塁：捕球を見て止まり（約0.4秒）、向きを変えて戻る
      final tBack = tCatch + 0.25 + Judgment.hesitation(jr, pressure) + 0.4 + BaseRun.time(p, sFrom: b + off / basePath, to: b); // レールを戻る（越えた塁は踏み直す）
      final b0 = basePos[b];
      final cov = lastPlan!.cover[b] ?? (b == 1 ? '1B' : (b == 2 ? 'SS' : '3B'));
      final d = _dist(hx, hy, b0[0], b0[1]);
      final hp = _p(holder) ?? f;
      final tBall = (cov == holder || d < 3.5)
          ? tr + d / 6.5
          : max(tr + (outfielder && holder == role ? ThrowStyle.flight(d, outfieldThrow(hp)) : _infieldThrowTime(hp, d)), lastPlan!.coverAt[b] ?? 0);
      if (tBall + 0.05 < tBack) {
        outs++;
        o.outs++;
        newBases[b - 1] = null;
        if (cov != holder && d >= 3.5) o.throws.add(ThrowLeg(hx, hy, b0[0], b0[1], tr, tBall));
        o.moves.add(RunMove(p.registeredName, b, b, true, tCatch, tBall, sStart: b + off / basePath));
        o.code = o.code.isEmpty ? '${posNo[role]}${cov != role ? '-${posNo[cov]}' : ''}' : '${o.code}-${posNo[cov]}';
        holder = cov;
        hx = b0[0];
        hy = b0[1];
        tr = tBall + 0.4;
      }
    }
    if (o.outs >= 2) {
      o.dp = true;
      o.tp = o.outs >= 3;
      o.desc = o.tp ? '（飛び出した走者も戻れず、トリプルプレー！）' : '（飛び出した走者が戻れず併殺）';
      o.bases = outs >= 3 ? [null, null, null] : newBases;
      return o;
    }
    if (!outfielder || depth < 45) {
      o.bases = newBases;
      return o;
    }

    // ---- タッチアップ：走者は期待値で決める（深さ・肩・自分の足）。外野手は得になる塁へ投げる ----
    final tRelease = tCatch + ThrowStyle.crowHop.transfer * 0.8; // 捕りながら前へ出て投げる
    final tagTry = <int, double>{}; // 塁 → 着く時刻
    for (int b = 3; b >= 1; b--) {
      final p = runners[b - 1];
      if (p == null || newBases[b - 1] == null) continue;
      final target = b + 1;
      if (target <= 3 && newBases[target - 1] != null && !tagTry.containsKey(target)) continue;
      final jr = Judgment.runner(p);
      final tRun = tCatch + 0.05 + Judgment.hesitation(jr, pressure) * 0.5 + Running.runnerTo(p, from: b, lead: 0, to: target, react: 0, v0: 0);
      final thr = _throwToBase(role, fx, fy, tRelease, target, noise: false);
      final pSafe = _pSafeSeen(p, thr.t - tRun);
      final bNo = bits & ~(1 << (b - 1));
      final vHold = RunValue.re(bits, outs);
      final vSafe = RunValue.value(target == 4 ? 1 : 0, bNo | (target < 4 ? 1 << (target - 1) : 0), outs);
      final vOut = RunValue.re(bNo, outs + 1);
      if (pSafe * vSafe + (1 - pSafe) * vOut + runAdj * 0.4 > vHold) tagTry[b] = tRun;
    }
    // 送球先：先の走者（本塁を優先）のうち、刺せそうな塁
    int? target;
    for (final b in tagTry.keys.toList()..sort((a, c) => c.compareTo(a))) {
      final thr = _throwToBase(role, fx, fy, tRelease, b + 1, noise: false);
      final seen = tagTry[b]! - thr.t + _g() * Judgment.readSigma(_judgOf(role), pressure);
      if (b == 3 || seen > -0.3) {
        target = b;
        break;
      }
    }
    for (final b in tagTry.keys.toList()..sort((a, c) => c.compareTo(a))) {
      final p = runners[b - 1]!;
      final to = b + 1;
      final tRun = tagTry[b]!;
      if (b == target) {
        final thr = _throwToBase(role, fx, fy, tRelease, to);
        o.throws.addAll(thr.legs);
        final safe = (tRun + _g() * 0.2) < thr.t + 0.12;
        newBases[b - 1] = null;
        if (safe) {
          o.moves.add(RunMove(p.registeredName, b, to, false, tCatch, tRun));
          if (to == 4) {
            o.runs++;
            o.sacFly = true;
            o.desc = '（犠牲フライ）';
          } else {
            newBases[to - 1] = p.registeredName;
          }
        } else {
          o.outs++;
          outs++;
          o.dp = true;
          o.moves.add(RunMove(p.registeredName, b, to, true, tCatch, thr.t + 0.1));
          o.desc = to == 4 ? '（三塁走者タッチアップも${thr.via}の好返球で本塁タッチアウト）' : '（タッチアップした走者を${thr.via}で${to}塁タッチアウト）';
        }
      } else {
        // 送球が来ない塁へは楽に進む
        newBases[b - 1] = null;
        o.moves.add(RunMove(p.registeredName, b, to, false, tCatch, tRun));
        if (to == 4) {
          o.runs++;
          o.sacFly = true;
          if (o.desc.isEmpty) o.desc = '（犠牲フライ）';
        } else {
          newBases[to - 1] = p.registeredName;
        }
      }
    }
    if (outs >= 3) {
      // 3アウト目のタッチより前に生還していれば得点（タッチアップの得点は時刻しだい）
      final tOut = o.moves.where((m) => m.out).map((m) => m.t1).fold(double.infinity, min);
      o.runs = o.moves.where((m) => m.to == 4 && !m.out && m.t1 < tOut).length;
      if (o.runs == 0) o.sacFly = false;
      o.bases = [null, null, null];
    } else {
      o.bases = newBases;
    }
    return o;
  }
}
