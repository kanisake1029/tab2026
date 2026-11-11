import 'dart:math';
import '../models/player.dart';
import 'physics_engine.dart'; // Vector3DとHitVectorを参照
import 'field_time.dart';
import 'defense_ai.dart';
import 'spec_constants.dart';

/// 2点間の距離（pow を使わない分だけ速い）
double _hypot(double a, double b) => sqrt(a * a + b * b);

enum CatchStance { normal, diving, jumping }

class CatchResult {
  final bool caught;
  final String fielderRole;
  final CatchStance stance;
  final double catchTime;
  final Vector3D catchPosition;
  
  final bool isGroundBall;
  final bool fumble; // 捕ったがこぼした（ゴロは拾い直し、フライは落球）

  CatchResult(this.caught, this.fielderRole, this.stance, this.catchTime, this.catchPosition, {this.isGroundBall = false, this.fumble = false});
}

class FielderState {
  final Player player;
  final String role;
  double x;
  double y;
  
  double reactionDelay; // 反応までの遅延時間（秒）
  double speed; // 最高速 (m/s)
  double accel = 6.5; // 加速度 (m/s²)
  double judge = 0.3; // フライの落下点の見極め（秒）
  double reach = 1.25; // 捕れる範囲（腕＋グラブ m）
  double cur = 0; // いまの速さ
  double v0 = 0; // 打った瞬間の初速（内野手はスプリットステップ、外野手は投球に合わせた数歩）
  double judgment = 50; // 判断力（defense_ai.dart の Judgment）
  int fieldingStat;
  int catchStat;
  
  bool isProne = false;
  double penaltyTimer = 0.0;
  
  FielderState({
    required this.player,
    required this.role,
    required this.x,
    required this.y,
    required this.reactionDelay,
    required this.speed,
    required this.fieldingStat,
    required this.catchStat,
  });
}

class FielderAI {
  final Random _rand = Random();
  /// 直前の打球での声の掛け合い（「CFがオーライ」「お見合い」）
  String lastCall = '';
  /// 役割（声の掛け合い・ベースカバー）を使う（テスト用に切れる）
  static bool useRoles = true;
  /// ゴロ：いちばん早く追いつける野手から何秒遅れまでの野手が一緒に追うか（それより遅い野手はベースカバーへ）
  static double chaseWindow = 0.25;
  /// ライナーの見極めにかかる時間の倍率（強いライナーほど伸びるか沈むかの判断に時間がかかる）
  static double linerJudge = 1.75;
  /// 外野手が打球を止められる範囲の上乗せ（m。クッションボールになる前に単打で止める）
  static double ofReachBonus = 0.25;
  /// 準備動作（PrePitch_Creep・SplitStep）で、打った瞬間にもう動き出せる速さ（m/s）。投手は投げ終わりの体勢、捕手は座っている
  static Map<String, double> splitStepV0 = {'P': 0.0, 'C': 0.0, '1B': 1.5, '2B': 1.5, '3B': 1.5, 'SS': 1.5, 'LF': 0.8, 'CF': 0.8, 'RF': 0.8};
  
  // グラウンドの初期配置 (X: 左右, Y: 本塁からの距離)
  // 本塁(0,0), 1塁(19.4, 19.4), 2塁(0, 38.8), 3塁(-19.4, 19.4)
  /// 右の引っ張り打者へのシフトで、本塁から見た角度（°）をどれだけ動かすか（− がレフト方向）
  static Map<String, double> shiftLeftDeg = {'3B': 0.0, 'SS': -5.0, '2B': -12.0, '1B': -3.0, 'LF': 0.0, 'CF': 0.0, 'RF': 0.0};
  /// シフトで寄った野手が打球を待ち構える分、出足が速くなる（秒）
  static double shiftAnticipation = 0.15;

  final Map<String, List<double>> basePositions = {
    'P': [0.0, 18.44],
    'C': [0.0, -2.0],
    // 内野の定位置（計測の平均）：二遊間は本塁から約46m・中堅線から約14°、一塁・三塁は約34m・塁線から約8°内側
    '1B': [21.0, 27.0],
    '2B': [11.0, 44.5],
    '3B': [-20.5, 27.5],
    'SS': [-11.0, 44.5],
    'LF': [-42.0, 82.0],
    'CF': [0.0, 95.0],
    'RF': [42.0, 82.0],
  };

  int _getFieldingStat(Player p, String role) {
    switch(role) {
      case 'P': return p.fieldP;
      case 'C': return p.fieldC;
      case '1B': return p.field1B;
      case '2B': return p.field2B;
      case '3B': return p.field3B;
      case 'SS': return p.fieldSS;
      case 'LF': return p.fieldLF;
      case 'CF': return p.fieldCF;
      case 'RF': return p.fieldRF;
      default: return 50;
    }
  }

  // 低い側は緩く、高い側はやや強めに効かせる
  int _softenDefense(int r) => r >= 60 ? (60 + (r - 60) * 0.58).round() : (60 - (60 - r) * 0.55).round();

  /// powerGuard=長打警戒：外野を深く、一塁・三塁を線寄りに守らせる
  List<FielderState> initializeFielders(Map<String, Player> defenseTeam, {bool powerGuard = false, bool infieldIn = false, bool dpShift = false, bool infieldBack = false, double shift = 0.0, bool holdRunner = false}) {
    // 仕様書 5.1 の定位置（一塁走者がいれば一塁手はベースに付く）
    final pos = Spec.fie
        ? {
            for (final e in Spec.positions.entries) e.key: const {'LF', 'CF', 'RF'}.contains(e.key) ? [e.value[0] * Spec.ofDepth, e.value[1] * Spec.ofDepth] : e.value,
            if (holdRunner) '1B': Spec.firstBaseHolding,
          }
        : basePositions;
    // シフト（+ はライト方向、− はレフト方向。1.0 で目いっぱい寄せる）。
    //   右の引っ張り打者へのシフト（−1.0）：二塁手が二塁ベースの左へ回り、内野の3人が左側を守る。遊撃手は三遊間、三塁手は少し中寄り、
    //   一塁手は一二塁間を1人で守る。外野も左へ寄る。左打者へのシフト（+1.0）はその左右反転
    //   本塁から見た角度（°）の変化量。− がレフト方向
    final toLeftDeg = shiftLeftDeg;
    const mirror = {'1B': '3B', '3B': '1B', '2B': 'SS', 'SS': '2B', 'LF': 'RF', 'RF': 'LF', 'CF': 'CF'};
    List<double> shiftOf(String role) {
      if (shift == 0) return const [0.0, 0.0];
      final deg = shift < 0 ? (toLeftDeg[role] ?? 0.0) : -(toLeftDeg[mirror[role] ?? role] ?? 0.0);
      if (deg == 0) return const [0.0, 0.0];
      final base = pos[role]!;
      final r = sqrt(base[0] * base[0] + base[1] * base[1]);
      final ang = atan2(base[0], base[1]) + deg * shift.abs() * pi / 180;
      return [r * sin(ang) - base[0], r * cos(ang) - base[1]];
    }
    List<FielderState> fielders = [];
    defenseTeam.forEach((role, player) {
      if (!pos.containsKey(role)) return;
      
      // 守備力の影響を緩和（極端な守備力でも被打率が極端に変わらないように）
      int fStat = _softenDefense(_getFieldingStat(player, role));
      
      // 反応：スプリットステップから1歩目まで約0.2秒（守備力が高いほど速い）。投手は投げ終わりの体勢から
      double delay = Fielding.reaction(fStat, role) + (_rand.nextDouble() - 0.5) * 0.12;
      // シフト：打球の傾向に合わせて寄った引っ張り側の内野手は、待ち構えている分だけ出足が速い
      if (shift != 0 && (shift < 0 ? const {'3B', 'SS', '2B'} : const {'1B', '2B', 'SS'}).contains(role)) delay -= shiftAnticipation * shift.abs();
      
      // 走力による最高速と加速（ルート取りのばらつき込み）
      final sp = Fielding.sprint(player);
      double speed = sp.vTop * (0.94 + _rand.nextDouble() * 0.12);
      
      fielders.add(FielderState(
        player: player,
        role: role,
        x: pos[role]![0] + shiftOf(role)[0] + (powerGuard ? (role == '1B' ? 3.0 : (role == '3B' ? -3.0 : 0.0)) : 0.0) + (dpShift ? (role == '2B' ? -4.0 : (role == 'SS' ? 4.0 : 0.0)) : 0.0),
        y: pos[role]![1] + shiftOf(role)[1] + (powerGuard && (role == 'LF' || role == 'CF' || role == 'RF') ? 4.0 : 0.0) + ((infieldIn && const {'1B', '2B', '3B', 'SS'}.contains(role)) ? -6.0 : 0.0) + ((infieldBack && const {'1B', '2B', '3B', 'SS'}.contains(role)) ? 4.0 : 0.0) + ((dpShift && (role == '2B' || role == 'SS')) ? -1.0 : 0.0),
        reactionDelay: delay,
        speed: speed,
        fieldingStat: fStat,
        catchStat: _softenDefense(player.catchSkill),
      )
        ..accel = sp.accel
        ..judge = Fielding.judge(fStat, role)
        ..reach = Fielding.reach(player) + (const {'LF', 'CF', 'RF'}.contains(role) ? ofReachBonus : 0.0)
        ..judgment = Judgment.fielder(player, fStat)
        ..v0 = splitStepV0[role] ?? 0.0);
    });
    return fielders;
  }

  /// 追いつける点を探すとき、0.05秒の区間を何分割して調べるか
  static const int _subSteps = 6;
  /// 打った点のまわり（打者の体・バットの所）では捕れない（m）
  static const double _batterZone = 1.5;
  /// 横っ飛びで手の届く範囲より先に伸ばせる距離（m）。守備力が高いほど遠くまで
  static double _diveExtra(FielderState f) => 2.0 + (f.fieldingStat - 60) * 0.04;

  CatchResult? simulateDefense(List<Vector3D> ballTrajectory, List<FielderState> fielders) {
    double dt = 0.05;

    // 第1バウンド地点（最初に z<=0 となった点）。転がって止まった地点ではない
    int firstBounceIdx = ballTrajectory.indexWhere((b) => b.z <= 0);
    if (firstBounceIdx < 0) firstBounceIdx = ballTrajectory.length - 1;

    // 各野手のインターセプト地点を決める。
    // 捕球可能な高さ(z<=2.5)の軌道点のうち、野手が到達できる最初の点を目指す。
    // 守備力が低いほど予測が甘く、反応(reactionDelay)も遅い。
    // ゴロ・低い打球はほぼ反射で動き出せる。フライは落下点の見極めに時間がかかる
    // ゴロ（打球角度が低い）だけが反射的に動き出せる。ライナーは見極めが要る
    final b0v = ballTrajectory.first;
    final double launchDeg = atan2(b0v.vz, sqrt(b0v.vx * b0v.vx + b0v.vy * b0v.vy)) * 180 / pi;
    final bool groundish = launchDeg < 8.0 && firstBounceIdx * dt < 1.5;
    // ゴロ・低い打球は反応だけで動き出せる。フライ・ライナーは落下点の見極めの間、6割の速さで寄る
    // 低く速いライナー（滞空2.5秒未満）は落下点が読みにくく、見極めに時間がかかる
    final bool liner = !groundish && (firstBounceIdx * dt < 2.5 || launchDeg < 22); // 低い弾道は、滞空が長くても伸びるか沈むかが読みにくい
    // 正面に飛んでくる打球は距離感がつかみにくい（横へ切れる打球は角度の変化で読める）：打球の線から野手までの横の距離で、見極めが最大1.8倍
    final land0 = ballTrajectory[firstBounceIdx];
    final landLen = max(1.0, _hypot(land0.x, land0.y));
    final Map<FielderState, double> headOn = {
      for (final f in fielders) f: exp(-pow((f.x * land0.y - f.y * land0.x).abs() / landLen / 6.0, 2).toDouble()),
    };
    // 頭を越える打球：体の向きを変える（Pivot_Turn・ドロップステップ）時間。判断力が高いほど最初の1歩を正しい向きに切れる
    final Map<FielderState, double> turn = {};
    if (!groundish) {
      for (final f in fielders) {
        final dx = land0.x - f.x, dy = land0.y - f.y;
        final dd = _hypot(dx, dy), fl = max(1.0, _hypot(f.x, f.y));
        final back = dd > 4 ? (dx * f.x + dy * f.y) / (dd * fl) : 0.0; // ＋1＝真後ろ
        if (back > 0.3) turn[f] = 0.25 * (1.2 - f.judgment / 100) * back;
        // 打球を見ながら走る（Sprint_Look）と全力より遅い。判断力の高い外野手は、遠い打球なら目を切って全力で落下点へ（Sprint_Blind）
        final blind = f.judgment >= 65 && dd > 20 && const {'LF', 'CF', 'RF'}.contains(f.role);
        if (!blind) f.speed *= 0.93;
      }
    }
    double delayOf(FielderState f) => groundish ? f.reactionDelay : f.reactionDelay + f.judge * (liner ? linerJudge : 0.5) * (1 + 0.8 * (headOn[f] ?? 0)) + (turn[f] ?? 0);
    double distBy(FielderState f, double t) => Sprint(f.speed, f.accel).distance(t - delayOf(f), v0: f.v0);
    // 担当範囲：内野手は浅い外野までのフライと内野のゴロ、捕手は本塁まわり、外野へ抜けた打球と深いフライは外野手
    bool allowed(FielderState f, Vector3D b, int i) {
      final d = _hypot(b.x, b.y);
      switch (f.role) {
        case 'C':
          return d <= 25;
        case 'P' || '1B' || '2B' || '3B' || 'SS':
          return i < firstBounceIdx ? d <= 60 : d <= 52; // 二遊間は本塁から約43m に守る
        default:
          return true;
      }
    }

    for (final f in fielders) {
      f.cur = f.v0;
    }
    final Map<FielderState, Vector3D> targets = {};
    final Map<FielderState, int> foundIdx = {}; // 追いつける最初の点
    final Map<FielderState, double> spare = {}; // その点で何秒余裕があるか
    final Map<FielderState, double> nearMiss = {}; // 追いつけない野手：いちばん近づけたときに、あと何 m 足りないか
    for (var f in fielders) {
      Vector3D best = ballTrajectory[firstBounceIdx];
      double bestSlack = double.infinity;
      bool found = false;
      // 打った瞬間の点（バットの位置）は誰も捕れない。区間（前の点→今の点）を細かく区切って調べる
      //  （0.05秒ごとの点だけだと、速いゴロが点と点の間で野手の手の届く範囲を通り過ぎる）
      for (int i = 1; i < ballTrajectory.length; i++) {
        final bi = ballTrajectory[i], bp = ballTrajectory[i - 1];
        if (!allowed(f, bi, i)) continue;
        Vector3D? hitPt;
        double slack = double.infinity, t = i * dt;
        for (int s = 1; s <= _subSteps; s++) {
          final u = s / _subSteps;
          final z = bp.z + (bi.z - bp.z) * u;
          if (z > 2.5) continue;
          final px = bp.x + (bi.x - bp.x) * u, py = bp.y + (bi.y - bp.y) * u;
          if (_hypot(px - b0v.x, py - b0v.y) < _batterZone) continue;
          final sl = _hypot(px - f.x, py - f.y) - (distBy(f, (i - 1 + u) * dt) + f.reach);
          if (sl < slack) { slack = sl; t = (i - 1 + u) * dt; hitPt = Vector3D(px, py, z, bi.vx, bi.vy, bi.vz); }
          if (sl <= 0) break;
        }
        if (hitPt == null) continue;
        final b = hitPt;
        if (slack <= 0) {
          best = b;
          found = true;
          foundIdx[f] = i;
          double spareAt(Vector3D p, double tp) => tp - (delayOf(f) + Sprint(f.speed, f.accel).time(max(0.0, _hypot(p.x - f.x, p.y - f.y) - f.reach), v0: f.v0));
          spare[f] = spareAt(b, t);
          // ぎりぎり届く点ではなく、構える余裕（0.15秒）のある少し先の点で待つ（0.4秒先まで）
          for (int j = i + 1; j < ballTrajectory.length && j <= i + 8; j++) {
            final bj = ballTrajectory[j];
            if (bj.z > 2.5 || !allowed(f, bj, j) || (i < firstBounceIdx && j >= firstBounceIdx)) break; // フライはノーバウンドのうちに
            final sj = spareAt(bj, j * dt);
            if (sj >= 0.15) {
              best = bj;
              spare[f] = sj;
              break;
            }
          }
          break;
        }
        if (slack < bestSlack) { bestSlack = slack; best = b; }
      }
      if (!found) nearMiss[f] = bestSlack;
      if (!found && bestSlack == double.infinity) best = Vector3D(f.x, f.y, 0, 0, 0, 0); // 担当外：持ち場（ベース）に残る
      if (groundish) {
        // ゴロ：打球の通り道へ入る。判断力が低いほど、入る位置が通り道から少しずれる（判断力50で約0.4m）
        final hv = _hypot(best.vx, best.vy);
        final off = (_rand.nextDouble() * 2 - 1) * (100 - f.judgment) * 0.008 * 1.7;
        targets[f] = hv > 0.1 ? Vector3D(best.x - best.vy / hv * off, best.y + best.vx / hv * off, 0, 0, 0, 0) : Vector3D(best.x, best.y, 0, 0, 0, 0);
        continue;
      }
      // フライ・ライナー：守備力が低いほど、落下点の予測が第1バウンドの地点（落ちる所）寄りに甘くなる
      double acc = (0.5 + f.fieldingStat / 200.0).clamp(0.5, 1.0);
      Vector3D b0 = allowed(f, ballTrajectory[firstBounceIdx], firstBounceIdx) ? ballTrajectory[firstBounceIdx] : best;
      targets[f] = Vector3D(best.x * acc + b0.x * (1 - acc), best.y * acc + b0.y * (1 - acc), 0, 0, 0, 0);
    }

    // ---- 役割：誰が捕るか（声の掛け合い）。捕らない野手はベースカバー・打球のカバーへ ----
    final Set<FielderState> cover = {}; // 打球を追わない（ベースに入る）
    var coverUntil = double.infinity; // 捕る野手がそれまでに捕れなければ、ほかの野手も追い始める
    final Set<FielderState> yieldAir = {}; // ノーバウンドでは捕らない（譲った・お見合い）
    lastCall = '';
    if (useRoles && foundIdx.isNotEmpty) {
      final found = foundIdx.keys.toList()..sort((a, b) => foundIdx[a]!.compareTo(foundIdx[b]!));
      final airborne = found.where((f) => foundIdx[f]! < firstBounceIdx).toList();
      if (!groundish && airborne.length >= 2) {
        // フライ：余裕のある野手のうち優先順位の高い者が「オーライ」。ほかは譲って後ろに回る
        final comfy = airborne.where((f) => spare[f]! >= 0.3).toList();
        int prio(FielderState f) => DefensePlan.callPriority[f.role] ?? 9;
        FielderState primary;
        if (comfy.isNotEmpty) {
          // 余裕（落下点に着いてから捕るまでの時間）がいちばん大きい野手＝持ち場の野手。優先順位（中堅手が先など）は、
          //  余裕の差が 0.35秒以内の野手どうしでだけ使う（レフトフライ・セカンドフライを中堅手が取りに行かない）
          final maxSpare = comfy.map((f) => spare[f]!).reduce(max);
          var pool = comfy.where((f) => spare[f]! >= maxSpare - 0.35).toList();
          // 内野の飛球（落下点が本塁から 50m 以内）：捕れる内野手がいれば内野手
          final land = ballTrajectory[firstBounceIdx];
          if (_hypot(land.x, land.y) < 50) {
            final inf = pool.where((f) => !const {'LF', 'CF', 'RF'}.contains(f.role)).toList();
            if (inf.isNotEmpty) pool = inf;
          }
          pool.sort((a, b) => prio(a) != prio(b) ? prio(a).compareTo(prio(b)) : spare[b]!.compareTo(spare[a]!));
          primary = pool.first;
        } else {
          primary = airborne.first;
        }
        final pt = targets[primary]!;
        for (final f in airborne) {
          if (f == primary) continue;
          if (_hypot(targets[f]!.x - pt.x, targets[f]!.y - pt.y) < 12) yieldAir.add(f);
        }
        // お見合い：同じくらいの優先順位の2人がどちらも捕れるとき、声が重なって落とすことがある（判断力が低いほど）
        final rival = comfy.where((f) => f != primary && (prio(f) - prio(primary)).abs() <= 1 && _hypot(targets[f]!.x - pt.x, targets[f]!.y - pt.y) < 6).toList();
        if (rival.isNotEmpty && _rand.nextDouble() < 0.006 * (2 - (primary.judgment + rival.first.judgment) / 100)) {
          yieldAir.add(primary);
          lastCall = 'お見合い';
        } else {
          lastCall = '${primary.role}がオーライ';
        }
      } else if (groundish) {
        // ゴロ：いちばん早く追いつける野手と、ほぼ同時に追いつける野手（三遊間で前に出る三塁手など）が追う。
        //  追いつけなくても飛びつけば届く野手は飛びつきにいく。ほかの内野手はベースカバーへ（外野手はゴロが抜けたときに備えて前へ）
        final tFirst = foundIdx[found.first]! * dt;
        coverUntil = tFirst + 0.15;
        for (final f in fielders) {
          if (const {'LF', 'CF', 'RF'}.contains(f.role)) continue;
          final i = foundIdx[f];
          if (i == null ? (nearMiss[f] ?? double.infinity) > _diveExtra(f) : i * dt > tFirst + chaseWindow) cover.add(f);
        }
      }
    }

    bool hasBounced = false;
    final Map<FielderState, double> nextTry = {}; // 捕球に失敗した野手が次に試せる時刻
    double hardPenaltyOf(Vector3D b) { final v = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz); return v > 30.0 ? (1.0 - (v - 30.0) * 0.02).clamp(0.6, 1.0) : 1.0; }
    for (int i = 0; i < ballTrajectory.length; i++) {
      Vector3D ball = ballTrajectory[i];
      double time = i * dt;
      if (i >= firstBounceIdx) hasBounced = true;

      for (var fielder in fielders) {
        if (time < delayOf(fielder)) continue; // 反応遅れ中
        if (!allowed(fielder, ball, i)) continue; // 担当外の打球は捕りにいかない
        if (cover.contains(fielder) && time < coverUntil) continue; // ベースカバーへ（捕る野手が取り損ねたら追う）
        final bool mayCatch = !(yieldAir.contains(fielder) && !hasBounced); // 譲ったフライは、落ちてから拾う

        Vector3D tgt = targets[fielder]!;
        double dx = tgt.x - fielder.x;
        double dy = tgt.y - fielder.y;
        double dist = sqrt(dx * dx + dy * dy);

        if (dist > 0.1) {
          // 加速しながら最高速へ（見極め中のフライは 6割まで）
          final cap = (!groundish && time < fielder.reactionDelay + fielder.judge) ? fielder.speed * 0.6 : fielder.speed;
          fielder.cur = min(cap, fielder.cur + fielder.accel * dt);
          double moveDist = fielder.cur * dt;
          if (moveDist > dist) moveDist = dist;
          fielder.x += (dx / dist) * moveDist;
          fielder.y += (dy / dist) * moveDist;
        }

        // 1ステップで打球が進む区間（前の点→今の点）に対する最短距離（速い打球のすり抜けを防ぐ）
        double ballDistToFielder;
        if (i > 0) {
          final p0 = ballTrajectory[i - 1];
          final sx = ball.x - p0.x, sy = ball.y - p0.y;
          final len2 = sx * sx + sy * sy;
          final u = len2 > 0 ? (((fielder.x - p0.x) * sx + (fielder.y - p0.y) * sy) / len2).clamp(0.0, 1.0) : 1.0;
          ballDistToFielder = _hypot(p0.x + sx * u - fielder.x, p0.y + sy * u - fielder.y);
        } else {
          ballDistToFielder = _hypot(ball.x - fielder.x, ball.y - fielder.y);
        }
        double ballZ = ball.z;

        // 1. 通常捕球 / ゴロ捕球 (低い打球も距離1.5m以内なら捕球)
        if (mayCatch && ballDistToFielder <= fielder.reach && ballZ <= 2.5) {
          // 速い打球（ライナー・強いゴロ）は反応が間に合わず弾いたり抜けたりしやすい
          double ballSpeed = sqrt(ball.vx * ball.vx + ball.vy * ball.vy + ball.vz * ball.vz);
          double hardPenalty = ballSpeed > 30.0 ? (1.0 - (ballSpeed - 30.0) * 0.02).clamp(0.6, 1.0) : 1.0;
          if (time >= (nextTry[fielder] ?? 0)) {
            // 構える余裕がない（ぎりぎり追いついた・逆シングル・走りながら）ほど難しい。守備力が高いほど崩れにくい
            final rush = (1 - (spare[fielder] ?? 0.3) / 0.3).clamp(0.0, 1.0);
            final setFactor = 1 - rush * (0.35 - (fielder.fieldingStat - 60) * 0.004).clamp(0.15, 0.5);
            if (_rand.nextDouble() < (Spec.fld ? 1.0 : _catchSuccessRate(fielder.catchStat, CatchStance.normal)) * hardPenalty * setFactor) {
              // 仕様書 6.1：グラブに入っても、捕球の能力に応じてこぼす（ファンブル）
              final fum = Spec.fld && _rand.nextDouble() < Spec.fumble(fielder.player.catchSkill);
              return CatchResult(true, fielder.role, CatchStance.normal, time, ball, isGroundBall: hasBounced, fumble: fum); // 一度でも跳ねたら（高いバウンドでも）ノーバウンドではない
            }
            nextTry[fielder] = time + 0.6; // 弾いた・グラブの下を抜けた
          }
        }

        // 2. ジャンプ一番
        if (mayCatch && ballDistToFielder <= 0.8 && ballZ > 2.5 && ballZ <= 3.8) {
          if (time >= (nextTry[fielder] ?? 0) && _rand.nextDouble() < _catchSuccessRate(fielder.catchStat, CatchStance.jumping)) {
            fielder.penaltyTimer = 1.0;
            return CatchResult(true, fielder.role, CatchStance.jumping, time, ball, isGroundBall: hasBounced);
          }
        }

        // 3. 横っ飛びダイビング
        //  普通に追いつける野手は飛びつかない（構えて捕る）。飛びつくのは届かない打球だけ
        if (mayCatch && !foundIdx.containsKey(fielder) && ballDistToFielder > fielder.reach && ballDistToFielder <= fielder.reach + _diveExtra(fielder) && ballZ >= 0.0 && ballZ <= 0.8) {
          if (time >= (nextTry[fielder] ?? 0) && _rand.nextDouble() < (fielder.fieldingStat / 100.0) * hardPenaltyOf(ball)) {
            nextTry[fielder] = time + 0.8; // 飛びついて捕れなければ、もう追いつけない
            if (_rand.nextDouble() < _catchSuccessRate(fielder.catchStat, CatchStance.diving)) {
              fielder.isProne = true;
              fielder.penaltyTimer = 2.5;
              return CatchResult(true, fielder.role, CatchStance.diving, time, ball, isGroundBall: hasBounced);
            }
          }
        }
      }

      if (ball.z == 0 && ball.vz == 0 && ball.vx == 0 && ball.vy == 0) {
        break;
      }
    }

    return null; // 誰も捕球できなかった
  }

  double _catchSuccessRate(int catchStat, CatchStance stance) {
    double baseRate = 0.5 + (catchStat * 0.005); // 捕球50で 75% ベース
    switch (stance) {
      case CatchStance.normal:
        return (baseRate + 0.2).clamp(0.0, 0.999); // ほぼ捕れるが稀にポロリ
      case CatchStance.jumping:
        return (baseRate - 0.2).clamp(0.0, 0.95); // 難易度高
      case CatchStance.diving:
        return (baseRate - 0.35).clamp(0.0, 0.90); // 難易度激高（ファインプレーかグラブを弾くか）
    }
  }
}