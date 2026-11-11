import 'dart:math' as m;
import '../models/player.dart';
import 'field_time.dart';

/// 守備・走塁の判断（統合モデル：状況 × 打球 × 9人の役割 × 最小動作）
///  物理エンジンが出した打球の軌道と、各選手の到達時間（反応＋加速＋全力）から、
///  ①9人に役割を割り当て（捕る・ベースに入る・中継・カバー）、②送球先を期待値で選び、③走者も期待値で進むか決める。
///  判断は完璧ではない：判断力が低いほど、時間の見積もりがぶれ、迷う時間が長い。重圧（終盤・接戦・得点圏）でさらに乱れる

/// 判断力（新しい指標。隠し 1〜100）：既存の能力と経験から作る
class Judgment {
  /// 経験：プロ1年目 25 → 6年目 約70 → 10年目 約84
  static double experience(Player p) => 25 + 75 * (1 - m.exp(-(p.proYears - 1).clamp(0, 30) / 6.0));

  /// 野手の判断力：その位置の守備力・捕球・経験・勝負強さ
  static double fielder(Player p, int fieldStat) => (fieldStat * 0.45 + p.catchSkill * 0.10 + experience(p) * 0.30 + p.clutch * 0.15).clamp(1.0, 100.0);

  /// 走者の判断力：走力（走塁の感覚）・経験・選球眼（打球の見極め）・勝負強さ
  static double runner(Player p) => (p.run * 0.30 + experience(p) * 0.35 + p.eye * 0.15 + p.clutch * 0.20).clamp(1.0, 100.0);

  /// 迷う時間（秒）。判断力50で約0.14秒、90で約0.05秒
  static double hesitation(double j, double pressure) => (0.03 + (100 - j) * 0.0022) * (1 + 0.5 * pressure);

  /// 時間の見積もりのぶれ（秒の標準偏差）。判断力50で約0.2秒、90で約0.09秒
  static double readSigma(double j, double pressure) => (0.06 + (100 - j) * 0.0028) * (1 + 0.4 * pressure);

  /// 重圧：終盤・接戦・得点圏の走者（0〜1）
  static double pressure({required int inning, required int scoreDiff, required bool risp}) =>
      ((inning >= 7 ? 0.4 : (inning >= 5 ? 0.15 : 0.0)) + (scoreDiff.abs() <= 1 ? 0.3 : (scoreDiff.abs() <= 3 ? 0.15 : 0.0)) + (risp ? 0.3 : 0.0)).clamp(0.0, 1.0);
}

/// 得点期待値（走者の状況 8通り × アウト 3通り = 24通り）。NPB の1試合約4.4点に合う値
///  bits：一塁=1・二塁=2・三塁=4
class RunValue {
  static const _re = [
    [0.48, 0.85, 1.10, 1.44, 1.35, 1.75, 1.96, 2.25],
    [0.26, 0.51, 0.66, 0.89, 0.95, 1.13, 1.38, 1.53],
    [0.10, 0.22, 0.32, 0.43, 0.36, 0.48, 0.57, 0.75],
  ];
  static double re(int bits, int outs) => outs >= 3 ? 0 : _re[outs][bits & 7];

  /// 攻撃側の価値：入った点（重み付き）＋そのあとの得点期待値
  static double value(int runs, int bits, int outs, {double runWeight = 1}) => runs * runWeight + re(bits, outs);
}

/// 打球の分類（守備の連係を決める）
enum BallClass { bunt, grounder, liner, fly, popup, gap }

/// 9人の役割
enum Duty { primary, secondary, cover1B, cover2B, cover3B, coverHome, cutoff, trailer, throwBackup, idle }

/// 最小動作（3D の骨格アニメーションの単位。第5段階で再生する）
enum Motion {
  prePitchCreep, splitStep, // 準備
  readReact, pivotTurn, firstStep, // 初動
  sprintLook, sprintBlind, adjustGlide, callSignal, avoidCollision, // 移動
  fieldGroundStd, fieldBackhand, fieldForehand, fieldShortHop, catchDiveFlat, catchSlideKnee, catchJumpWall, catchFlyRun, catchFlySet, // 捕球
  transferStd, transferQuick, transferFlip, // 握り替え
  crowHop, proStep, pivot2B, // ステップ
  throwOverhand, throwThreeQuarter, throwSideUnder, throwOffBalance, // 送球
  baseCoverRun, baseSetupForce, baseStretch, baseSetupTag, applyTag, // 塁上
  cutoffPosture, backupMove, decoy, // 補助
}

class MotionKey {
  final Motion motion;
  final double t; // 打った瞬間からの秒
  const MotionKey(this.motion, this.t);
}

/// 1人の野手の役割と動き
class FielderDuty {
  final String role;
  Duty duty;
  double tx, ty; // 目標地点
  double tArrive; // 着く時刻
  final List<MotionKey> motions = [];
  FielderDuty(this.role, this.duty, this.tx, this.ty, this.tArrive);
}

/// 野手のスタート位置と能力（役割の割り当てに使う）
class DefenderInfo {
  final String role;
  final Player player;
  final double x, y;
  final double reaction; // 反応（秒）
  final Sprint sprint;
  final double judgment;
  const DefenderInfo(this.role, this.player, this.x, this.y, this.reaction, this.sprint, this.judgment);
}

/// 役割の割り当て（Frame 0 で決める）
class DefensePlan {
  static const basePos = [[0.0, 0.0], [19.4, 19.4], [0.0, 38.8], [-19.4, 19.4], [0.0, 0.0]];
  static const outfield = {'LF', 'CF', 'RF'};

  /// フライの捕球の優先順位（数が小さいほど優先。外野手が「オーライ」と言えば内野手は引く）
  static const callPriority = {'CF': 0, 'LF': 1, 'RF': 1, 'SS': 2, '2B': 3, '3B': 4, '1B': 4, 'C': 5, 'P': 6};

  final Map<String, FielderDuty> duties = {};
  final Map<int, String> cover = {}; // 塁（1〜4）→ 入る野手
  final Map<int, double> coverAt = {}; // 塁 → 着く時刻
  final List<String> cutoffs = []; // 中継（外野側から）
  final String primary;
  final BallClass ballClass;
  DefensePlan._(this.primary, this.ballClass);

  static double _d(double x0, double y0, double x1, double y1) => m.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));

  /// 打球の分類：打ち出し角・第1バウンドまでの時間・落下地点の深さから
  static BallClass classify({required double launchDeg, required double tBounce, required double landDist, required bool bunt}) {
    if (bunt) return BallClass.bunt;
    if (launchDeg < 10) return BallClass.grounder;
    if (launchDeg >= 45 && landDist < 70) return BallClass.popup;
    if (landDist > 85) return BallClass.gap; // 外野の間・頭を越える
    if (launchDeg < 25 && tBounce < 2.5) return BallClass.liner;
    return BallClass.fly;
  }

  /// 割り当て：primary（捕る野手）・捕球地点（fx,fy）・その時刻 tField から、残りの8人の役割を決める
  static DefensePlan assign({
    required Map<String, DefenderInfo> d,
    required String primary,
    required double fx,
    required double fy,
    required double tField,
    required BallClass ballClass,
    required int bits,
    required int outs,
    required bool batterLefty,
    double pressure = 0,
  }) {
    final plan = DefensePlan._(primary, ballClass);
    final infieldPlay = !outfield.contains(primary) && _d(0, 0, fx, fy) < 50;
    final used = <String>{primary};
    double arrive(String role, double tx, double ty) {
      final f = d[role];
      if (f == null) return double.infinity;
      final dist = _d(f.x, f.y, tx, ty);
      if (dist < 1.5) return f.reaction * 0.5;
      return f.reaction + Judgment.hesitation(f.judgment, pressure) + f.sprint.time(dist) + 0.1; // ＋構える
    }

    void put(String role, Duty duty, double tx, double ty) {
      if (!d.containsKey(role)) return;
      used.add(role);
      plan.duties[role] = FielderDuty(role, duty, tx, ty, arrive(role, tx, ty));
    }

    void coverBase(int base, List<String> prefs) {
      for (final r in prefs) {
        if (used.contains(r) || !d.containsKey(r)) continue;
        final b = basePos[base];
        put(r, const [Duty.idle, Duty.cover1B, Duty.cover2B, Duty.cover3B, Duty.coverHome][base], b[0], b[1]);
        plan.cover[base] = r;
        plan.coverAt[base] = plan.duties[r]!.tArrive;
        return;
      }
    }

    plan.duties[primary] = FielderDuty(primary, Duty.primary, fx, fy, tField);
    final leftSide = fx < -8;

    if (infieldPlay || ballClass == BallClass.bunt) {
      // ---- 内野で処理（ゴロ・バント・内野フライ）----
      // 一塁：一塁手（一塁手が捕りに出たら投手、バントで投手も出たら二塁手）
      coverBase(1, ['1B', 'P', '2B']);
      // 二塁：三遊間・投手前は二塁手がピボット、一二塁間は遊撃手。投ゴロは右打者なら遊撃手、左打者なら二塁手
      final second = switch (primary) {
        '3B' || 'SS' => ['2B', 'SS'],
        '2B' || '1B' => ['SS', '2B'],
        _ => batterLefty ? ['2B', 'SS'] : ['SS', '2B'],
      };
      coverBase(2, second);
      // 三塁：三塁手（三塁手が捕ったら遊撃手、いなければ投手）
      coverBase(3, ['3B', 'SS', 'P']);
      // 本塁：捕手（捕手が捕ったら投手）
      coverBase(4, ['C', 'P']);
      // 送球のカバー：一塁の後ろへ右翼手（と捕手）、二塁の後ろへ中堅手、三塁の後ろへ左翼手
      if (!used.contains('RF')) put('RF', Duty.throwBackup, 26, 8);
      if (!used.contains('CF')) put('CF', Duty.throwBackup, 0, 52);
      if (!used.contains('LF')) put('LF', Duty.throwBackup, -26, 8);
      for (final r in ['P', 'C', '1B', '2B', '3B', 'SS']) {
        if (!used.contains(r)) put(r, r == 'C' ? Duty.throwBackup : Duty.secondary, r == 'C' ? 14 : fx, r == 'C' ? 4 : fy);
      }
      return plan.._motions(d, pressure);
    }

    // ---- 外野へ（単打・長打・フライ）----
    final deep = ballClass == BallClass.gap || _d(0, 0, fx, fy) > 85;
    // 打球カバー：隣の外野手（中堅手が優先）
    final backupOF = primary == 'CF' ? (fx < 0 ? 'LF' : 'RF') : 'CF';
    put(backupOF, Duty.secondary, fx + (0 - fx) * 0.15, fy + 6);
    // 中継：本塁への返球は 左寄りなら三塁手、それ以外は一塁手。二塁・三塁への返球は二遊間
    final runnersOn = bits != 0;
    String relay1 = fx < 8 ? 'SS' : '2B';
    String relay2 = relay1 == 'SS' ? '2B' : 'SS';
    if (deep) {
      // ダブルカット：二遊間が外野の芝まで出て一直線に並ぶ（走者なしは三塁、走者ありは本塁のライン）
      final tgt = runnersOn ? basePos[4] : basePos[3];
      final k1 = 0.42, k2 = 0.62; // 捕球地点から塁までの割合
      put(relay1, Duty.cutoff, fx + (tgt[0] - fx) * k1, fy + (tgt[1] - fy) * k1);
      put(relay2, Duty.trailer, fx + (tgt[0] - fx) * k2, fy + (tgt[1] - fy) * k2);
      plan.cutoffs.addAll([relay1, relay2]);
      coverBase(3, ['3B']);
      coverBase(4, ['C']);
      coverBase(2, ['1B']); // 打者の触塁を見てから二塁へ
      coverBase(1, ['P']);
      if (runnersOn && !used.contains('P')) put('P', Duty.throwBackup, 0, -12);
    } else {
      // 単打：本塁のカットは三塁手（レフト寄り）・一塁手（センター・ライト）
      final homeCut = leftSide && fx < -15 ? '3B' : '1B';
      if ((bits & 2) != 0 || (bits & 4) != 0) {
        put(homeCut, Duty.cutoff, fx * 0.25 + 0, fy * 0.25 + 0 + (homeCut == '1B' ? 4 : 2));
        plan.cutoffs.add(homeCut);
      }
      // 三塁への中継（走者一塁で三塁を狙われる）：遊撃手
      if ((bits & 1) != 0) {
        final b3 = basePos[3];
        put('SS', Duty.cutoff, fx + (b3[0] - fx) * 0.6, fy + (b3[1] - fy) * 0.6);
        plan.cutoffs.add('SS');
      } else {
        final b2 = basePos[2];
        put(relay1, Duty.cutoff, fx + (b2[0] - fx) * 0.55, fy + (b2[1] - fy) * 0.55);
        plan.cutoffs.add(relay1);
      }
      coverBase(2, ['2B', 'SS']);
      coverBase(3, ['3B', 'SS', 'P']);
      coverBase(4, ['C', 'P']);
      coverBase(1, ['1B', 'P']);
      // 投手は送球の後ろへ（走者がいれば本塁か三塁の後ろ、いなければ二塁の後ろ）
      if (!used.contains('P')) {
        if ((bits & 2) != 0 || (bits & 4) != 0) {
          put('P', Duty.throwBackup, 0, -12);
        } else if ((bits & 1) != 0) {
          put('P', Duty.throwBackup, -30, 10);
        } else {
          put('P', Duty.throwBackup, 0, 30);
        }
      }
    }
    for (final r in d.keys) {
      if (!used.contains(r)) put(r, outfield.contains(r) ? Duty.throwBackup : Duty.idle, d[r]!.x, d[r]!.y);
    }
    return plan.._motions(d, pressure);
  }

  /// 役割ごとの最小動作の並び（打った瞬間＝0）。捕球・送球の動作は処理が決まったあとで足す（addPlay）
  void _motions(Map<String, DefenderInfo> d, double pressure) {
    for (final u in duties.values) {
      final f = d[u.role];
      if (f == null) continue;
      final react = f.reaction;
      u.motions.add(const MotionKey(Motion.splitStep, 0));
      u.motions.add(MotionKey(Motion.readReact, react * 0.5));
      final dist = _d(f.x, f.y, u.tx, u.ty);
      if (dist < 1.5) continue;
      final back = (u.tx - f.x) * f.x + (u.ty - f.y) * f.y > 0;
      u.motions.add(MotionKey(back ? Motion.pivotTurn : Motion.firstStep, react));
      switch (u.duty) {
        case Duty.primary || Duty.secondary:
          final blind = back && dist > 20 && f.judgment >= 65;
          u.motions.add(MotionKey(blind ? Motion.sprintBlind : Motion.sprintLook, react + 0.2));
          if (u.duty == Duty.primary) {
            if (ballClass == BallClass.fly || ballClass == BallClass.popup || ballClass == BallClass.gap) u.motions.add(MotionKey(Motion.callSignal, m.max(react + 0.3, u.tArrive - 1.2)));
            u.motions.add(MotionKey(Motion.adjustGlide, m.max(react + 0.2, u.tArrive - 0.35)));
          } else {
            u.motions.add(MotionKey(Motion.avoidCollision, m.max(react + 0.3, u.tArrive - 0.8)));
          }
        case Duty.cover1B || Duty.cover2B || Duty.cover3B || Duty.coverHome:
          u.motions.add(MotionKey(Motion.baseCoverRun, react));
          final force = u.duty == Duty.cover1B || ballClass == BallClass.grounder || ballClass == BallClass.bunt;
          u.motions.add(MotionKey(u.duty == Duty.cover1B ? Motion.baseStretch : (force ? Motion.baseSetupForce : Motion.baseSetupTag), u.tArrive));
        case Duty.cutoff || Duty.trailer:
          u.motions.add(MotionKey(Motion.sprintLook, react + 0.1));
          u.motions.add(MotionKey(Motion.cutoffPosture, u.tArrive));
        case Duty.throwBackup:
          u.motions.add(MotionKey(Motion.backupMove, react));
        case Duty.idle:
          break;
      }
    }
  }

  /// 捕球・握り替え・ステップ・送球の動作を足す（処理が決まってから）
  void addPlay(String role, {required Motion catchMotion, required double tCatch, Motion? transfer, Motion? footwork, Motion? throwMotion, double? tThrow}) {
    final u = duties[role];
    if (u == null) return;
    u.motions.add(MotionKey(catchMotion, tCatch));
    if (transfer != null) u.motions.add(MotionKey(transfer, tCatch + 0.05));
    if (footwork != null) u.motions.add(MotionKey(footwork, tCatch + 0.2));
    if (throwMotion != null) u.motions.add(MotionKey(throwMotion, tThrow ?? tCatch + 0.5));
  }

  /// 捕球の動作を選ぶ（3D 用）：打球と野手の動きの向き・バウンド・体勢から
  static Motion catchMotion({required bool ground, required bool shortHop, required bool dive, required bool jump, required double sideToGlove, required double spare}) {
    if (dive) return Motion.catchDiveFlat;
    if (jump) return Motion.catchJumpWall;
    if (ground) {
      if (shortHop) return Motion.fieldShortHop;
      if (sideToGlove < -0.8) return Motion.fieldBackhand; // 利き手側へ跳んだ打球
      if (sideToGlove > 0.8) return Motion.fieldForehand;
      return Motion.fieldGroundStd;
    }
    return spare > 0.5 ? Motion.catchFlySet : Motion.catchFlyRun;
  }

  /// 送球の様式 → 動作
  static Motion throwMotion(ThrowStyle s) {
    if (identical(s, ThrowStyle.bare) || identical(s, ThrowStyle.sidearm)) return Motion.throwSideUnder;
    if (identical(s, ThrowStyle.jump)) return Motion.throwOffBalance;
    if (identical(s, ThrowStyle.crowHop)) return Motion.throwOverhand;
    return Motion.throwThreeQuarter;
  }
}

/// 送球先の選択（Utility AI）：U = −（入る点×重み＋得点期待値）の期待値 − 悪送球の危険
///  アウトにできる確率は「走者の到着 − ボールの到着」のマージン（野手の見積もり＝ぶれ込み）をシグモイドに入れて求める
class ThrowChoice {
  /// マージンの尺度（秒）：0.07秒の差で約 73%
  static double pOut(double margin) => 1 / (1 + m.exp(-margin / 0.07));
  static double gauss(m.Random r) => m.sqrt(-2 * m.log(1 - r.nextDouble())) * m.cos(2 * m.pi * r.nextDouble());
}
