import '../models/player.dart';

/// 選手寸評の「骨組み」：役割・数字・持ち味をアプリが決めて、決まった順に並べる。
///  AI はこの順番と内容のまま名鑑の文章に整えるだけ（事実を足さない）。
///  骨組みをそのままつなげれば、AI なしでも寸評になる。
class PlayerOutline {
  static String _rate(double v) => v.toStringAsFixed(3).replaceFirst('0.', '.');
  static String _ip(int x) => '${x ~/ 3}回${x % 3 > 0 ? '${x % 3}/3' : ''}';

  /// 投手の役割（成績から決める）。登板が無ければ ''
  static String pitcherRole(PlayerStats s) {
    final apps = s.apps;
    if (apps == 0 || s.inningsPitched == 0) return '';
    if (s.starts > 0 || s.pitchApps > 0) {
      // 先発数が分かる（今季・昨季の記録）
      if (s.starts / apps >= 0.6) return '先発';
      if (s.starts / apps >= 0.25) return '先発と中継ぎ';
    } else if (s.inningsPitched / 3 / apps >= 4.5) {
      return '先発'; // 先発数が無い記録（再編前の通算）は1登板あたりの投球回で判断
    }
    if (s.saves >= 5 && s.saves >= s.holds) return '抑え';
    if (s.holds >= 5) return 'セットアッパー';
    return '中継ぎ';
  }

  static String _pitchSummary(PlayerStats s) {
    final role = pitcherRole(s);
    final parts = <String>['${s.apps}試合に登板${s.starts > 0 && role != '先発' ? '（うち${s.starts}先発）' : ''}'];
    if (role == '先発' || role == '先発と中継ぎ') parts.add('${s.wins}勝${s.losses}敗');
    if (role == '抑え') parts.add('${s.saves}セーブ');
    if (role == 'セットアッパー') parts.add('${s.holds}ホールド');
    if (role == '中継ぎ' && s.holds + s.saves > 0) parts.add('${s.holds}ホールド${s.saves > 0 ? '・${s.saves}セーブ' : ''}');
    parts.add('防御率${s.era.toStringAsFixed(2)}');
    if (s.inningsPitched >= 90) parts.add('${_ip(s.inningsPitched)}');
    if (s.pitcherStrikeouts >= 50) parts.add('${s.pitcherStrikeouts}奪三振');
    return parts.join('、');
  }

  static String _batSummary(PlayerStats s) {
    final parts = <String>['${s.games}試合に出場', '打率${_rate(s.battingAverage)}', '${s.homeRuns}本塁打', '${s.rbi}打点'];
    if (s.stolenBases >= 10) parts.add('${s.stolenBases}盗塁');
    return parts.join('、');
  }

  /// 成績の評価（数字に合った言葉）
  static String _pitchEval(PlayerStats s) {
    if (s.inningsPitched < 15) return '';
    if (s.era < 2.3) return '安定した投球を見せている';
    if (s.era < 3.3) return 'まずまずの投球を続けている';
    if (s.era < 4.5) return '内容にはばらつきがある';
    return '苦しい投球が続いている';
  }

  static String _batEval(PlayerStats s) {
    if (s.plateAppearances < 50) return '';
    if (s.ops >= 0.900) return '打線の中心として結果を残している';
    if (s.ops >= 0.750) return 'まずまずの打撃を見せている';
    if (s.ops >= 0.620) return '打撃はやや物足りない';
    return '打撃で苦しんでいる';
  }

  static List<String> strengths(Player p) {
    final out = <String>[];
    if (p.isPitcher || p.twoWay) {
      if (p.velocity >= 153) out.add('最速${p.velocity}kmの速球');
      if (p.pitchPower >= 75) out.add('球威');
      if (p.control >= 75) out.add('制球力');
      final brk = p.pitches.where((x) => x.breakLevel >= 60 && x.sharpness >= 60).toList()..sort((a, b) => (b.breakLevel + b.sharpness).compareTo(a.breakLevel + a.sharpness));
      if (brk.isNotEmpty) out.add('切れのある${brk.first.name}');
      if (p.clutchPitching >= 75) out.add('ピンチでの粘り');
    }
    if (!p.isPitcher || p.twoWay) {
      if (p.power >= 75) out.add('長打力');
      if (p.contact >= 75) out.add('確実性の高い打撃');
      if (p.eye >= 75) out.add('選球眼');
      if (p.run >= 75) out.add('俊足');
      if (p.arm >= 75) out.add('強肩');
      if (p.catchSkill >= 75) out.add('堅実な守備');
      if (p.clutch >= 75) out.add('勝負強さ');
    }
    return out.take(3).toList();
  }

  static List<String> weaknesses(Player p) {
    final out = <String>[];
    if (p.isPitcher || p.twoWay) {
      if (p.control < 45) out.add('制球');
      if (p.pitchPower < 45) out.add('球威');
    }
    if (!p.isPitcher || p.twoWay) {
      if (p.contact < 45) out.add('確実性');
      if (p.eye < 45) out.add('選球眼');
      if (p.catchSkill < 45) out.add('守備');
    }
    return out.take(2).toList();
  }

  /// 骨組み（この順に書く）
  static List<String> build(Player p, {required DateTime date, PlayerStats? last, int? lastYear, String lastTeam = '', int condition = 0}) {
    final out = <String>[];
    final pitcher = p.isPitcher;
    final s = p.seasonStats, c = p.career, f = p.farmStats;
    final who = pitcher ? (p.throws == 'L' ? '左腕' : '右腕') : p.mainPosition;
    out.add('【立場】${p.origin.isNotEmpty ? '来日' : 'プロ'}${p.proYears}年目、${p.age}歳の$who${p.origin.isNotEmpty ? '（${p.origin}出身の外国人）' : ''}${p.ikusei ? '（育成選手）' : ''}${p.twoWay ? '。投打の二刀流' : ''}。');
    // 実績（昨季、無ければ再編前の通算）
    if (last != null && (pitcher ? last.apps > 0 : last.games > 0)) {
      out.add(pitcher
          ? '【昨季】$lastYear年は${pitcherRole(last)}として${_pitchSummary(last)}。'
          : '【昨季】$lastYear年は${_batSummary(last)}。');
    } else if (pitcher ? c.apps > 0 : c.games > 0) {
      out.add(pitcher
          ? '【実績】リーグ再編前までの通算で、主に${pitcherRole(c)}として${c.apps}試合に登板し${c.wins}勝${c.saves > 0 ? '${c.saves}セーブ' : ''}${c.holds > 0 ? '${c.holds}ホールド' : ''}、防御率${c.era.toStringAsFixed(2)}。'
          : '【実績】リーグ再編前までの通算で${c.games}試合に出場し、打率${_rate(c.battingAverage)}、${c.homeRuns}本塁打。');
    } else if (p.abroad.isNotEmpty) {
      out.add('【実績】来日前の成績：${p.abroad.take(2).join(' / ')}');
    } else if (p.proYears > 1) {
      out.add('【実績】昨季までは1軍出場がない。');
    }
    // 今季
    final mo = date.month;
    final offSeason = mo >= 11 || mo == 1;
    final preSeason = mo <= 3 && s.games == 0;
    if (!preSeason) {
      final label = offSeason ? '今季は' : '今季はここまで';
      if (pitcher && s.apps > 0) {
        final ev = _pitchEval(s);
        out.add('【今季】$label${pitcherRole(s)}として${_pitchSummary(s)}。${ev.isEmpty ? '' : '$ev。'}');
      } else if (!pitcher && s.games > 0) {
        final ev = _batEval(s);
        out.add('【今季】$label${_batSummary(s)}。${ev.isEmpty ? '' : '$ev。'}');
      } else if (pitcher ? f.apps > 0 : f.games > 0) {
        out.add('【今季】${label}1軍での出場はなく、2軍で${pitcher ? '${f.apps}試合に登板し防御率${f.era.toStringAsFixed(2)}' : '${f.games}試合に出場し打率${_rate(f.battingAverage)}'}。');
      } else {
        out.add('【今季】${label}1軍・2軍とも出場がない。');
      }
      if (p.twoWay) {
        out.add(pitcher
            ? (s.atBats > 0 ? '【今季・打撃】${_batSummary(s)}。' : '')
            : (s.apps > 0 ? '【今季・投球】${pitcherRole(s)}として${_pitchSummary(s)}。' : ''));
      }
    }
    final st = strengths(p), wk = weaknesses(p);
    if (st.isNotEmpty) out.add('【持ち味】${st.join('、')}。');
    if (wk.isNotEmpty) out.add('【課題】${wk.join('、')}。');
    if (p.injuryDays > 0) out.add('【状態】${p.injuryName}で離脱中（復帰まで残り${p.injuryDays}日）。');
    if (condition <= -1 && p.injuryDays == 0) out.add('【状態】調子を落としている。');
    if (condition >= 1 && p.injuryDays == 0) out.add('【状態】調子は上向き。');
    out.add(offSeason
        ? '【締め】来季への期待。'
        : (preSeason ? '【締め】リーグ再編後の新シーズンへの期待。' : '【締め】今季の残りへの期待（「来季」とは書かない）。'));
    return out.where((l) => l.isNotEmpty).toList();
  }
}
