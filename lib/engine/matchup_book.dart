/// 投手と打者の対戦成績（今季の公式戦。自球団の試合の1球ごとの記録から集計する）
class VsLine {
  int pa = 0, ab = 0, h = 0, d2 = 0, d3 = 0, hr = 0, bb = 0, hbp = 0, so = 0, sac = 0;

  void add(VsLine o) {
    pa += o.pa; ab += o.ab; h += o.h; d2 += o.d2; d3 += o.d3; hr += o.hr; bb += o.bb; hbp += o.hbp; so += o.so; sac += o.sac;
  }

  double get avg => ab == 0 ? 0 : h / ab;
  double get obp => (ab + bb + hbp) == 0 ? 0 : (h + bb + hbp) / (ab + bb + hbp);
  double get slg => ab == 0 ? 0 : (h + d2 + d3 * 2 + hr * 3) / ab;
  double get ops => obp + slg;
  static String rate(double v) => v.toStringAsFixed(3).replaceFirst('0.', '.');
  String get avgText => ab == 0 ? '---' : rate(avg);

  /// 例：「5打数2安打 1本塁打 1三振 1四死球」
  String get summary {
    if (pa == 0) return '対戦なし';
    final parts = ['$ab打数$h安打'];
    if (hr > 0) parts.add('$hr本塁打');
    if (so > 0) parts.add('$so三振');
    if (bb + hbp > 0) parts.add('${bb + hbp}四死球');
    return parts.join(' ');
  }
}

/// 1球の記録（試合中の PitchEvent と、保存してある1球ごとの記録の両方から作る）
class PitchRec {
  final int paIndex, pitchNo, balls, strikes;
  final bool battingHome;
  final String batter, pitcher, result, outcome;
  const PitchRec({required this.paIndex, required this.pitchNo, required this.battingHome, required this.batter, required this.pitcher, required this.result, required this.outcome, required this.balls, required this.strikes});
}

/// 打席の結果を1打席分の VsLine にする。打席が途中で終わった（盗塁死でチェンジなど）なら null
VsLine? paResult(PitchRec e) {
  final l = VsLine();
  const hits = {'単打', '二塁打', '三塁打', 'ホームラン'};
  if (e.result == '死球') {
    l.hbp = 1;
  } else if (e.result == 'ボール') {
    if (e.balls < 3) return null;
    l.bb = 1;
  } else if (e.result == '見逃し' || e.result == '空振り') {
    if (e.strikes < 2) return null;
    l.ab = 1;
    l.so = 1;
  } else if (e.result == 'インプレー' || e.result == 'バント') {
    if (hits.contains(e.outcome)) {
      l.ab = 1;
      l.h = 1;
      if (e.outcome == '二塁打') l.d2 = 1;
      if (e.outcome == '三塁打') l.d3 = 1;
      if (e.outcome == 'ホームラン') l.hr = 1;
    } else if (e.result == 'バント') {
      l.sac = 1; // 送りバント・スクイズ（打数に数えない）
    } else {
      l.ab = 1;
    }
  } else {
    return null;
  }
  l.pa = 1;
  return l;
}

class MatchupBook {
  /// 'pitcherId|batterId' → 対戦成績
  final Map<String, VsLine> lines = {};
  /// 集計済みの試合（日程の番号）
  final Set<int> done = {};

  void clear() {
    lines.clear();
    done.clear();
  }

  /// 1試合分を足す。idOf(打者側か, 名前) で選手の id を引く（引けなければ数えない）
  void addGame(int matchIdx, Iterable<PitchRec> recs, String? Function(bool home, String name) idOf) {
    if (!done.add(matchIdx)) return;
    final last = <int, PitchRec>{};
    for (final e in recs) {
      final cur = last[e.paIndex];
      if (cur == null || e.pitchNo >= cur.pitchNo) last[e.paIndex] = e;
    }
    for (final e in last.values) {
      final r = paResult(e);
      if (r == null) continue;
      final b = idOf(e.battingHome, e.batter), p = idOf(!e.battingHome, e.pitcher);
      if (b == null || p == null) continue;
      lines.putIfAbsent('$p|$b', VsLine.new).add(r);
    }
  }

  VsLine of(String pitcherId, String batterId) => lines['$pitcherId|$batterId'] ?? VsLine();

  /// 打者から見た、投手ごとの対戦成績
  Map<String, VsLine> vsPitchers(String batterId) => {
        for (final e in lines.entries)
          if (e.key.endsWith('|$batterId')) e.key.substring(0, e.key.length - batterId.length - 1): e.value,
      };

  /// 投手から見た、打者ごとの対戦成績
  Map<String, VsLine> vsBatters(String pitcherId) => {
        for (final e in lines.entries)
          if (e.key.startsWith('$pitcherId|')) e.key.substring(pitcherId.length + 1): e.value,
      };
}
