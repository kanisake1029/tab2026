import '../engine/growth_curve.dart';
import '../engine/game_summary.dart';
import '../engine/growth_engine.dart';
import '../models/team.dart';
import '../utils/schedule_generator.dart';
import '../models/player.dart';
import '../utils/grade_utils.dart';
import 'ai_writer.dart';
import 'player_outline.dart';

/// AI に渡す事実（画面に出ている情報だけ）を作る
class AiFacts {
  static String g(int v) => '${GradeUtils.getGrade(v)}($v)';
  static String _rate(double v) => v.toStringAsFixed(3).replaceFirst('0.', '.');
  static String _hand(Player p) => '${p.throws == 'L' ? '左' : '右'}投${p.bats == 'L' ? '左' : (p.bats == 'S' ? '両' : '右')}打';
  static String _ip(int x) => '${x ~/ 3}回${x % 3 > 0 ? '${x % 3}/3' : ''}';

  static String batLine(PlayerStats s) => s.atBats + s.walks == 0
      ? '出場なし'
      : '${s.games}試合 打率${_rate(s.battingAverage)} ${s.homeRuns}本塁打 ${s.rbi}打点 ${s.stolenBases}盗塁 出塁率${_rate(s.obp)} OPS${_rate(s.ops)} 三振${s.strikeouts} 四球${s.walks}';
  static String pitchLine(PlayerStats s) => s.inningsPitched == 0
      ? '登板なし'
      : '${s.appsText} ${s.wins}勝${s.losses}敗${s.holds}H${s.saves}S 防御率${s.era.toStringAsFixed(2)} ${_ip(s.inningsPitched)} 奪三振${s.pitcherStrikeouts} 与四球${s.pitcherWalks} 被本塁打${s.hrAllowed}';

  /// 選手詳細の寸評
  ///  事実はアプリが決めた「骨組み」だけを渡す（役割・数字の取り違えを防ぐ）
  static AiItem player(Player p, {required String team, required DateTime date, int condition = 0, PlayerStats? last, int? lastYear, String lastTeam = ''}) {
    final b = StringBuffer();
    b.writeln('選手：${p.listName}（$team・${p.isPitcher ? '投手' : p.mainPosition}・${_hand(p)}）');
    b.writeln('今日：${date.year}年${date.month}月${date.day}日');
    final outline = PlayerOutline.build(p, date: date, last: last, lastYear: lastYear, lastTeam: lastTeam, condition: condition);
    b.writeln('骨組み（この順番・この内容で書く）：');
    for (final l in outline) {
      b.writeln(l);
    }
    if (p.honors.isNotEmpty) b.writeln('（触れてもよい実績：${p.honors.take(4).join('、')}）');
    final s = p.seasonStats;
    final key = 'player3:${p.id}:${date.year}-${date.month}:${p.ovr}:${p.injuryDays > 0 ? 1 : 0}:${s.games ~/ 15}';
    return AiItem(key, 'player', b.toString(), features: {...playerFeatures(p, team: team, condition: condition), 'outline': outline, 'last': last?.toJson(), 'lastYear': lastYear});
  }

  /// 選手の元データ（文章と組にして貯める）
  static Map<String, dynamic> playerFeatures(Player p, {required String team, int condition = 0}) => {
        'id': p.id,
        'name': p.listName,
        'team': team,
        'pos': p.isPitcher ? '投手' : p.mainPosition,
        'twoWay': p.twoWay,
        'age': p.age,
        'proYears': p.proYears,
        'bats': p.bats,
        'throws': p.throws,
        'foreign': p.origin,
        'ikusei': p.ikusei,
        'ovr': p.ovr,
        'bat': {'contactL': p.contactLeft, 'contactR': p.contactRight, 'power': p.power, 'traj': p.trajectory, 'eye': p.eye, 'clutch': p.clutch, 'run': p.run, 'arm': p.arm, 'throw': p.throwAccuracy, 'catch': p.catchSkill},
        'pitch': {'velo': p.velocity, 'power': p.pitchPower, 'control': p.control, 'stamina': p.stamina, 'pinch': p.clutchPitching, 'quick': p.quick},
        'pitches': [for (final x in p.pitches) {'name': x.name, 'break': x.breakLevel, 'sharp': x.sharpness, 'heavy': x.heaviness, 'ratio': x.ratio}],
        'body': {'energy': p.energy, 'maxEnergy': p.maxEnergy, 'recovery': p.recovery, 'durability': p.durability},
        'talent': p.talent,
        'ambition': p.ambition,
        'curve': {'primeStart': p.primeStart, 'rise': p.riseLen, 'prime': p.primeLen, 'trans': p.transLen, 'label': GrowthCurve.label(p)},
        'phase': GrowthEngine.phaseOf(p).label,
        'injury': p.injuryDays > 0 ? {'name': p.injuryName, 'days': p.injuryDays} : null,
        'condition': condition,
        'season': p.seasonStats.toJson(),
        'career': p.career.toJson(),
        'honors': p.honors,
      };

  /// 試合総評（試合結果の画面と、試合後に自動で書くときで同じ鍵を使う）
  static AiItem game(Match m, Team home, Team away, {String context = ''}) => AiItem(
        'game:${m.date.toIso8601String().substring(0, 10)}:${m.homeTeamId}:${m.awayTeamId}',
        'game',
        GameSummary.facts(m, home, away) + (context.isEmpty ? '' : '状況：\n$context'),
        features: {...GameSummary.features(m, home, away), 'context': context},
      );

  /// スカウトのトレード推薦
  static AiItem trade(Player p, {required String team, required String myTeam, required bool onFarm, required String autoComment, required String date}) {
    final b = StringBuffer();
    b.writeln('候補：${p.listName}（$team・${p.isPitcher ? '投手' : p.mainPosition}・${p.age}歳・${_hand(p)}・いま${onFarm ? '2軍' : '1軍'}）');
    b.writeln('自球団：$myTeam');
    b.writeln('総合力：${g(p.ovr)}');
    if (p.isPitcher) {
      b.writeln('投球：最速${p.velocity}km 球威${g(p.pitchPower)} 制球${g(p.control)} スタミナ${g(p.stamina)}');
    } else {
      b.writeln('打撃・走守：ミート${g(p.contact)} パワー${g(p.power)} 走力${g(p.run)} 選球眼${g(p.eye)} 肩力${g(p.arm)} 捕球${g(p.catchSkill)}');
    }
    b.writeln('今季1軍：${p.isPitcher ? pitchLine(p.seasonStats) : batLine(p.seasonStats)}');
    b.writeln('今季2軍：${p.isPitcher ? pitchLine(p.farmStats) : batLine(p.farmStats)}');
    b.writeln('スカウトの報告（この内容に沿って書く）：$autoComment');
    return AiItem('trade:${p.id}:$date', 'trade', b.toString(), features: {...playerFeatures(p, team: team), 'onFarm': onFarm, 'farm': p.farmStats.toJson(), 'myTeam': myTeam, 'scoutReport': autoComment});
  }
}
