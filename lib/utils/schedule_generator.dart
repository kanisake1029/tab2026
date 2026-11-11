import '../models/team.dart';

class Match {
  final String homeTeamId;
  final String awayTeamId;
  DateTime date; // 雨天中止で順延すると変わる
  final String matchType; 
  int dh = 0; // ダブルヘッダー：0＝なし、1＝第1試合（13:00）、2＝第2試合（18:00）
  bool cancelled = false; // 中止（オープン戦の雨天中止、または順延先がなく打ち切り）
  String note = ''; // 順延の記録（例：「4/12 雨天中止の振替」）
  int? homeScore;
  int? awayScore;
  bool isPlayed = false;
  
  List<int>? homeInningScores;
  List<int>? awayInningScores;
  int? homeHits;
  int? awayHits;
  List<String>? playByPlay;
  List<String>? pitchByPitch;
  Map<String, dynamic>? boxScore; // 追加

  Match({
    required this.homeTeamId,
    required this.awayTeamId,
    required this.date,
    required this.matchType,
  });

  Map<String, dynamic> toJson() => {
    'homeTeamId': homeTeamId,
    'awayTeamId': awayTeamId,
    'date': date.toIso8601String(),
    'matchType': matchType,
    'homeScore': homeScore,
    'awayScore': awayScore,
    'isPlayed': isPlayed,
    'homeInningScores': homeInningScores,
    'awayInningScores': awayInningScores,
    'homeHits': homeHits,
    'awayHits': awayHits,
    'playByPlay': playByPlay,
    'pitchByPitch': pitchByPitch,
    'boxScore': boxScore,
    if (dh != 0) 'dh': dh,
    if (cancelled) 'cancelled': true,
    if (note.isNotEmpty) 'note': note,
  };

  /// 終わった試合（結果が出た、または中止）
  bool get done => homeScore != null || cancelled;

  String get dhLabel => dh == 1 ? '第1試合 13:00' : (dh == 2 ? '第2試合 18:00' : '');

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      homeTeamId: json['homeTeamId'],
      awayTeamId: json['awayTeamId'],
      date: DateTime.parse(json['date']),
      matchType: json['matchType'],
    )
      ..homeScore = json['homeScore']
      ..awayScore = json['awayScore']
      ..isPlayed = json['isPlayed'] ?? false
      ..homeInningScores = json['homeInningScores'] != null ? List<int>.from(json['homeInningScores']) : null
      ..awayInningScores = json['awayInningScores'] != null ? List<int>.from(json['awayInningScores']) : null
      ..homeHits = json['homeHits']
      ..awayHits = json['awayHits']
      ..playByPlay = json['playByPlay'] != null ? List<String>.from(json['playByPlay']) : null
      ..pitchByPitch = json['pitchByPitch'] != null ? List<String>.from(json['pitchByPitch']) : null
      ..boxScore = json['boxScore'] != null ? Map<String, dynamic>.from(json['boxScore']) : null
      ..dh = json['dh'] ?? 0
      ..cancelled = json['cancelled'] ?? false
      ..note = json['note'] ?? '';
  }
}

class ScheduleGenerator {
  /// 公式戦の試合数（1球団あたり）の選択肢
  ///  143（標準・NPB と同じ）：同一リーグ 25回戦×5＝125 ＋ 交流戦 3回戦×6＝18
  ///  120（短期）：同一リーグ 20回戦×5＝100 ＋ 交流戦 20（3〜4回戦×6）
  ///  156（タフな日程）：同一リーグ 27回戦×5＝135 ＋ 交流戦 21（3〜4回戦×6）
  static const seasonLengths = [120, 143, 156];

  /// 同一リーグの「巡」（5カードで全チームと 1 回ずつ当たる）ごとのカードの試合数と、交流戦 6 カードそれぞれの試合数
  static (List<int>, List<int>) shapeOf(int games) => switch (games) {
        120 => (const [3, 3, 3, 3, 3, 3, 2], const [3, 3, 3, 3, 4, 4]),
        156 => (const [3, 3, 3, 3, 3, 3, 3, 3, 3], const [4, 4, 4, 3, 3, 3]),
        _ => (const [3, 3, 3, 3, 3, 3, 3, 2, 2], const [3, 3, 3, 3, 3, 3]),
      };

  static List<Match> generateSeasonSchedule(int year, List<Team> teams, {int games = 143}) {
    final matches = <Match>[];
    final pl = teams.where((t) => t.league == 'PL').toList();
    final cl = teams.where((t) => t.league == 'CL').toList();
    final all = [...pl, ...cl];

    // ── オープン戦（2月の第1火曜から 11 カード）──
    var date = DateTime(year, 2, 1);
    while (date.weekday != DateTime.tuesday) {
      date = date.add(const Duration(days: 1));
    }
    for (var round = 0; round < 11; round++) {
      for (var i = 0; i < 6; i++) {
        final homeIdx = (round + i) % 11;
        var awayIdx = (11 - i + round) % 11;
        if (i == 0) awayIdx = 11;
        for (var day = 0; day < 3; day++) {
          matches.add(Match(homeTeamId: all[homeIdx].id, awayTeamId: all[awayIdx].id, date: date.add(Duration(days: day)), matchType: 'OPEN'));
        }
      }
      date = date.add(Duration(days: date.weekday == DateTime.tuesday ? 3 : 4));
    }

    // ── 公式戦 ──
    final (cycles, inter) = shapeOf(games);
    // 開幕：156 試合は 3 月の第 3 金曜（日程が長いので早め）、ほかは 3 月の最後の金曜
    var opening = DateTime(year, 3, 1);
    var fridays = 0;
    final want = games >= 156 ? 3 : 99;
    while (true) {
      if (opening.weekday == DateTime.friday) {
        fridays++;
        final nextFri = opening.add(const Duration(days: 7));
        if (fridays == want || (want == 99 && nextFri.month != 3)) break;
      }
      opening = opening.add(const Duration(days: 1));
    }
    date = opening;
    var allStarDone = false;
    // ホームの割り振り：カードごとに、その相手とのホーム試合が少ない方（同じなら全体のホーム試合が少ない方）をホームにする
    final homeVs = <String, int>{}, homeAll = <String, int>{};
    bool firstIsHome(Team x, Team y) {
      final a = homeVs['${x.id}>${y.id}'] ?? 0, b = homeVs['${y.id}>${x.id}'] ?? 0;
      if (a != b) return a < b;
      return (homeAll[x.id] ?? 0) <= (homeAll[y.id] ?? 0);
    }

    void addHome(Team h, Team v, int n) {
      homeVs['${h.id}>${v.id}'] = (homeVs['${h.id}>${v.id}'] ?? 0) + n;
      homeAll[h.id] = (homeAll[h.id] ?? 0) + n;
    }

    // 1 カード分（両リーグ同じ日に L 試合ずつ）を入れて日付を進める。月曜は休み。7 月中旬にオールスター
    DateTime round(DateTime d, int len, void Function(DateTime) add) {
      add(d);
      // 月曜は休み。120 試合（短期）はカードの間に 1 日休んで、9 月まで続ける
      var nd = d.add(Duration(days: len + (games <= 120 ? 1 : 0)));
      while (nd.weekday == DateTime.monday) {
        nd = nd.add(const Duration(days: 1));
      }
      return nd;
    }

    DateTime allStar(DateTime d) {
      if (allStarDone || d.isBefore(DateTime(year, 7, 14))) return d;
      allStarDone = true;
      matches.add(Match(homeTeamId: 'PL_ALLSTAR', awayTeamId: 'CL_ALLSTAR', date: d, matchType: 'ALLSTAR'));
      matches.add(Match(homeTeamId: 'CL_ALLSTAR', awayTeamId: 'PL_ALLSTAR', date: d.add(const Duration(days: 1)), matchType: 'ALLSTAR'));
      return d.add(const Duration(days: 4));
    }

    // 同一リーグの 1 巡（円の方法の総当たり：r 番目のカードは (r,5)・(r+1,r+4)・(r+2,r+3)）
    DateTime cycle(DateTime d, int c, int len) {
      for (var r = 0; r < 5; r++) {
        d = allStar(d);
        d = round(d, len, (day) {
          for (final lg in [pl, cl]) {
            if (lg.length < 6) continue;
            for (var i = 0; i < 3; i++) {
              final h = (r + i) % 5;
              final a = i == 0 ? 5 : (5 - i + r) % 5;
              final hh = firstIsHome(lg[h], lg[a]) ? lg[h] : lg[a], vv = identical(hh, lg[h]) ? lg[a] : lg[h];
              addHome(hh, vv, len);
              for (var k = 0; k < len; k++) {
                matches.add(Match(homeTeamId: hh.id, awayTeamId: vv.id, date: day.add(Duration(days: k)), matchType: 'LEAGUE'));
              }
            }
          }
        });
      }
      return d;
    }

    final before = cycles.length ~/ 2 - 1; // 交流戦の前の巡の数（5月下旬に交流戦）
    for (var c = 0; c < before; c++) {
      date = cycle(date, c, cycles[c]);
    }
    // 交流戦：パの i 番目と、セの (i+k) 番目。ホームはカードごと・年ごとに入れ替え。4 回戦は前半 2 試合と後半 2 試合でホームを入れ替える
    if (pl.length == 6 && cl.length == 6) {
      for (var k = 0; k < inter.length; k++) {
        final len = inter[k];
        date = round(date, len, (day) {
          for (var i = 0; i < 6; i++) {
            final p = pl[i], q = cl[(i + k) % 6];
            final plHome = (k + year) % 2 == 0;
            for (var g = 0; g < len; g++) {
              final h = len == 4 && g >= 2 ? !plHome : plHome;
              matches.add(Match(homeTeamId: (h ? p : q).id, awayTeamId: (h ? q : p).id, date: day.add(Duration(days: g)), matchType: 'INTERLEAGUE'));
            }
          }
        });
      }
      date = date.add(const Duration(days: 3)); // 交流戦明けの休み
      if (date.weekday == DateTime.monday) date = date.add(const Duration(days: 1));
    }
    for (var c = before; c < cycles.length; c++) {
      date = cycle(date, c, cycles[c]);
    }
    allStar(DateTime(year, 7, 14).isAfter(date) ? DateTime(year, 7, 14) : date);
    return matches;
  }
}
