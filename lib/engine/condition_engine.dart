import 'dart:math';
import '../models/player.dart';
import '../models/team.dart';
import '../models/league_rules.dart';
import 'match_simulator.dart';

/// 体力・回復・怪我・モチベーションの処理（試合後と日ごと）。
/// 仕様のたたき台: docs/player_growth_finance_spec.md
class ConditionEngine {
  // ---- 体力の消費（最大値 1〜1000 に対して）----
  static const int pitchCost = 4;      // 1球あたり（先発・中継ぎで差なし）: 100球で −400
  static const int fielderCost = 60;   // 野手 1試合
  static const int catcherCost = 85;   // 捕手 1試合
  static const int dhCost = 40;        // DH 1試合
  static const int benchCost = 30;     // 途中出場（代打・代走・守備固め）

  /// 1日あたりの回復量: 30 + 回復力 × 0.6（回復力50で60）
  static int dailyRecovery(Player p) => (30 + p.recovery * 0.6).round();

  /// 156試合制（移動日が少ない）の投手の回復の補正（中5〜6日で回るように）
  static double pitcherScheduleMul = 1.0;

  /// 球団ごとのメディカル＆リカバリーセンターの Lv（0〜5）：回復 +4%/Lv・怪我の起こりやすさ −6%/Lv・治るまでの日数 −5%/Lv
  static Map<String, int> medicalLevel = {};
  static int _med(Team t) => medicalLevel[t.id] ?? 0;
  static double healMul(Team t) => 1 - 0.05 * _med(t);

  // ---- 怪我 ----
  static const double injuryBase = 0.005; // 1試合・1人あたりの基本確率
  static const _mild = ['軽度の肩痛', '打撲', '軽い腰痛', '指のマメ', '軽い張り'];
  static const _moderate = ['肉離れ', '捻挫', '肘の炎症', '脇腹痛', '腰痛'];
  static const _severe = ['骨折', '靭帯損傷', '半月板損傷', '疲労骨折'];

  static final Random _r = Random();

  /// 自球団の id（自動で行うのは、全治10日以上の怪我人の登録抹消だけ）
  static String myTeamId = '';

  /// 1試合・1人あたりの怪我の確率（体力が少ないほど・怪我しにくさが低いほど高い。メディカルセンターで下がる）
  static double injuryProb(Player p, Team team) {
    final ratio = p.energyRatio;
    final eMult = ratio >= 0.5 ? 1.0 : (ratio >= 0.3 ? 1.5 : 3.0);
    return injuryBase * eMult * (1.5 - p.durability / 100.0) * (1 - 0.06 * _med(team));
  }

  /// 怪我をさせる（重さ・名前・全治の日数を決める）。お知らせの文を返す
  static String inflict(Player p, Team team, Random r) {
    final x = r.nextDouble();
    if (x < 0.6) {
      p.injurySeverity = 1;
      p.injuryName = _mild[r.nextInt(_mild.length)];
      p.injuryDays = ((3 + r.nextInt(8)) * healMul(team)).round().clamp(1, 999);
    } else if (x < 0.9) {
      p.injurySeverity = 2;
      p.injuryName = _moderate[r.nextInt(_moderate.length)];
      p.injuryDays = ((14 + r.nextInt(29)) * healMul(team)).round();
    } else {
      p.injurySeverity = 3;
      p.injuryName = _severe[r.nextInt(_severe.length)];
      p.injuryDays = ((60 + r.nextInt(121)) * healMul(team)).round();
    }
    p.motivation = (p.motivation - 10).clamp(0, 100);
    return '${team.name}の${p.registeredName}が試合中に負傷：${p.injuryName}（全治${p.injuryDays}日${p.injurySeverity == 1 ? '・強行出場可' : '・登録抹消'}）';
  }

  /// 試合後の処理。怪我などのお知らせを返す（怪我そのものは試合中に起きる：MatchSimulator）
  static List<String> applyPostGame(GameSession s, {String? myTeam}) {
    if (myTeam != null) myTeamId = myTeam;
    final news = <String>[...s.injuryNews];
    for (final home in [true, false]) {
      final team = home ? s.homeTeam : s.awayTeam;
      final pitchers = home ? s.homePitchers : s.awayPitchers;
      final appeared = home ? s.homeAppeared : s.awayAppeared;
      final lineup = home ? s.homeLineup : s.awayLineup;
      final box = s.boxScore;

      // 体力の消費と連投の記録
      final d = s.match.date, y = d.subtract(const Duration(days: 1));
      final today = '${d.year}-${d.month}-${d.day}', yesterday = '${y.year}-${y.month}-${y.day}';
      for (final p in pitchers) {
        final n = s.gamePitchCounts[p.id] ?? 0;
        p.energy = (p.energy - n * pitchCost * (s.weather.heat ? 1.12 : 1.0)).round().clamp(0, p.maxEnergy);
        if (p.lastPitched != today) {
          p.consecDays = p.lastPitched == yesterday ? p.consecDays + 1 : 1;
          p.lastPitched = today;
        }
      }
      final starters = (home ? s.homeTeam : s.awayTeam).lineup.map((l) => l.playerId).toSet();
      for (final p in appeared.toSet()) {
        if (p.isPitcher) continue;
        String pos = '';
        for (final l in lineup) { if (l.playerId == p.id) pos = l.position; }
        int cost;
        if (!starters.contains(p.id) && pos.isEmpty) {
          cost = benchCost;
        } else {
          cost = pos == '捕' ? catcherCost : (pos == 'DH' ? dhCost : fielderCost);
        }
        p.energy = (p.energy - cost * (s.weather.heat ? 1.12 : 1.0)).round().clamp(0, p.maxEnergy); // 猛暑は 12% 増し
      }

      // モチベーション（試合の結果）
      final bat = box[home ? 'homeBatters' : 'awayBatters'] as Map<String, dynamic>;
      for (final p in appeared.toSet()) {
        final b = bat[p.registeredName];
        if (b == null) continue;
        final ab = (b['ab'] ?? 0) as int, h = (b['h'] ?? 0) as int, hr = (b['hr'] ?? 0) as int;
        int d = 0;
        if (ab >= 3 && h == 0) d -= 2;
        if (h >= 3) d += 3;
        if (hr > 0) d += 2;
        p.motivation = (p.motivation + d).clamp(0, 100);
      }
      final pit = box[home ? 'homePitcher' : 'awayPitcher'] as Map<String, dynamic>;
      for (var i = 0; i < pitchers.length; i++) {
        final p = pitchers[i];
        final b = pit[p.registeredName];
        if (b == null) continue;
        final er = (b['er'] ?? 0) as int;
        final outs = s.pitcherOuts[p.id] ?? 0;
        int d = 0;
        if (er >= 4) d -= 3;
        if (i == 0 && outs >= 18 && er <= 3) d += 3; // クオリティスタート
        if (i > 0 && outs >= 3 && er == 0) d += 1;
        p.motivation = (p.motivation + d).clamp(0, 100);
      }

      // 軽い怪我を押して出場した選手は、悪化することがある（この試合で怪我をした選手は除く）
      final played = <Player>{...appeared, ...pitchers};
      for (final p in played) {
        if (s.injuredNow.contains(p.id)) continue;
        if (p.injuryDays > 0 && p.injurySeverity == 1 && _r.nextDouble() < 0.15) {
          p.injurySeverity = 2;
          p.injuryName = _moderate[_r.nextInt(_moderate.length)];
          p.injuryDays += 14 + _r.nextInt(21);
          p.motivation = (p.motivation - 5).clamp(0, 100);
          news.add('${team.name}の${p.registeredName}が強行出場で悪化（${p.injuryName}・全治${p.injuryDays}日）');
        }
      }
      news.addAll(handleInjuries(team));
    }
    return news;
  }

  /// 日が進んだときの回復（体力・怪我の残り日数）
  static void advanceDays(Iterable<Team> teams, int days) {
    if (days <= 0) return;
    for (final t in teams) {
      for (final p in t.players) {
        p.energy = (p.energy + dailyRecovery(p) * days * (1 + 0.04 * _med(t)) * (p.isPitcher ? pitcherScheduleMul : 1.0)).round().clamp(0, p.maxEnergy);
        if (p.injuryDays > 0) {
          p.injuryDays -= days;
          if (p.injuryDays <= 0) {
            p.injuryDays = 0;
            p.injurySeverity = 0;
            p.injuryName = '';
          }
        }
      }
    }
  }

  /// 出場できない怪我人を1軍から外し、スタメン・ローテ・方程式を埋め、2軍から補充する
  ///  自球団は、全治10日以上の怪我人の登録抹消だけ（補充・スタメンの入れ替えはしない）
  static List<String> handleInjuries(Team t) {
    final news = <String>[];
    final pmap = {for (final p in t.players) p.id: p};
    final mine = t.id == myTeamId;
    final out = t.roster1G.where((id) {
      final p = pmap[id];
      if (p == null || !p.isInjuredOut) return false;
      return !mine || p.injuryDays >= 10;
    }).toList();
    if (out.isEmpty) return news;
    if (mine) {
      for (final id in out) {
        final p = pmap[id]!;
        t.roster1G.remove(id);
        t.manualBenchOut.remove(id);
        for (var i = 0; i < t.rotation.length; i++) { if (t.rotation[i] == id) t.rotation[i] = ''; }
        for (var i = 0; i < t.winningPattern.length; i++) { if (t.winningPattern[i] == id) t.winningPattern[i] = ''; }
        news.add('${t.name}：${p.registeredName}を登録抹消（全治${p.injuryDays}日）。代わりの昇格・オーダーの組み替えは監督の判断で');
      }
      t.refreshActive26();
      return news;
    }
    for (final id in out) {
      final p = pmap[id]!;
      t.roster1G.remove(id);
      t.manualBenchOut.remove(id);
      for (var i = 0; i < t.rotation.length; i++) { if (t.rotation[i] == id) t.rotation[i] = ''; }
      for (var i = 0; i < t.winningPattern.length; i++) { if (t.winningPattern[i] == id) t.winningPattern[i] = ''; }
      // 2軍から同じ種類（投手/野手）の最もOVRが高い健康な選手を昇格
      final foreign1G = t.roster1G.where((x) => pmap[x]!.foreignSlot).length;
      final cands = t.players.where((c) => c.isPitcher == p.isPitcher && !c.ikusei && !t.roster1G.contains(c.id) && c.injuryDays == 0 && (!c.foreignSlot || LeagueRules.under1G(foreign1G))).toList()
        ..sort((a, b) {
          final sa = (a.mainPos == p.mainPos ? 5 : 0) + a.ovr, sb = (b.mainPos == p.mainPos ? 5 : 0) + b.ovr;
          return sb.compareTo(sa);
        });
      String upName = '';
      if (cands.isNotEmpty) {
        t.roster1G.add(cands.first.id);
        upName = cands.first.registeredName;
      }
      // スタメンの穴を1軍の控え野手で埋める
      for (final l in t.lineup) {
        if (l.playerId != id) continue;
        final used = t.lineup.map((e) => e.playerId).toSet();
        final posName = const {'捕': '捕手', '一': '一塁手', '二': '二塁手', '三': '三塁手', '遊': '遊撃手', '左': '左翼手', '中': '中堅手', '右': '右翼手'}[l.position];
        final bench = t.roster1G.map((x) => pmap[x]!).where((c) => !c.isPitcher && !used.contains(c.id) && !c.isInjuredOut).toList()
          ..sort((a, b) {
            final sa = (a.mainPos == posName ? 10 : 0) + a.ovr, sb = (b.mainPos == posName ? 10 : 0) + b.ovr;
            return sb.compareTo(sa);
          });
        if (bench.isNotEmpty) l.playerId = bench.first.id;
      }
      news.add('${t.name}：${p.registeredName}を登録抹消${upName.isNotEmpty ? '、$upNameを1軍に昇格' : ''}');
    }
    t.autoFillPitchingStaff();
    t.refreshActive26();
    return news;
  }
}
