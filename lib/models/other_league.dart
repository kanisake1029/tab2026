import 'player.dart';

/// 他リーグ（MLB・マイナー・海外・独立リーグ）の1リーグ
class OLeague {
  final String id;       // 'MLB' 'AAA' 'AA' 'A' 'KBO' 'CPBL' 'MEX' 'ME' 'AUS' 'US1'… 'JP1'…
  final String name;     // 表示名
  final String group;    // 画面の分類：アメリカ / アジア / 中南米 / その他 / 米独立 / 日本独立
  final String level;    // 'MLB' '3A' '2A' '1A' 'KBO' 'CPBL' 'メキシカンリーグ' '中東リーグ' '豪州リーグ' '米独立' '日本独立'（来歴の行・成績の補正に使う）
  final double mean;     // 選手の力の平均（NPB と同じ尺度）
  final int ageLo, ageHi;
  final int games;       // 1シーズンの試合数
  final int startM, startD, endM, endD; // シーズンの期間（冬のリーグは年をまたぐ）
  final List<String> divisions; // 地区（「アリーグ東地区」など。1つなら地区なし）
  const OLeague({required this.id, required this.name, required this.group, required this.level, required this.mean, required this.ageLo, required this.ageHi, required this.games, required this.startM, required this.startD, required this.endM, required this.endD, required this.divisions});

  bool get winter => false; // 全リーグ春に開幕する

  /// 開幕日：全リーグ共通で3月の第4金曜日
  static DateTime opening(int y) {
    var d = DateTime(y, 3, 1);
    while (d.weekday != DateTime.friday) {
      d = d.add(const Duration(days: 1));
    }
    return d.add(const Duration(days: 21));
  }

  DateTime closing(int y) => DateTime(y, endM, endD);

  /// その日が、そのリーグのシーズン中か
  bool inSeason(DateTime d) {
    final x = DateTime(d.year, d.month, d.day);
    return !x.isBefore(opening(d.year)) && !x.isAfter(closing(d.year));
  }

  /// その年のシーズンの日数
  int daysIn(int y) => closing(y).difference(opening(y)).inDays + 1;
  int get days => daysIn(2027);

  /// その日のシーズンの年
  int seasonYear(DateTime d) => d.year;
}

/// 他リーグの1球団
class OTeam {
  final String id;
  String name;
  String short;
  final String leagueId;
  final int division;    // OLeague.divisions の番号
  final String org;      // マイナー球団の親球団（MLB の球団 id）。ほかは ''
  List<Player> players;
  int w, l, d;
  int rotation;          // 次の先発（0〜4）
  /// 前のシーズンの順位・成績（表示用）「2026 東地区1位 88勝74敗」
  List<String> history;

  OTeam({required this.id, required this.name, required this.short, required this.leagueId, this.division = 0, this.org = '', List<Player>? players, this.w = 0, this.l = 0, this.d = 0, this.rotation = 0, List<String>? history})
      : players = players ?? [],
        history = history ?? [];

  double get pct => w + l == 0 ? 0 : w / (w + l);

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'short': short, 'lg': leagueId, 'div': division, if (org.isNotEmpty) 'org': org,
        'p': [for (final p in players) p.toJson()], 'w': w, 'l': l, 'd': d, 'rot': rotation, if (history.isNotEmpty) 'hist': history,
      };

  factory OTeam.fromJson(Map<String, dynamic> j) => OTeam(
        id: j['id'], name: j['name'], short: j['short'] ?? j['name'], leagueId: j['lg'], division: j['div'] ?? 0, org: j['org'] ?? '',
        players: [for (final e in (j['p'] as List? ?? [])) Player.fromJson(Map<String, dynamic>.from(e as Map))],
        w: j['w'] ?? 0, l: j['l'] ?? 0, d: j['d'] ?? 0, rotation: j['rot'] ?? 0, history: List<String>.from(j['hist'] ?? const []),
      );
}

/// 他リーグ全体（球団・選手・最後に計算した日）
class OtherWorld {
  List<OTeam> teams;
  DateTime simDate;      // ここまでの日の試合を計算した
  int seasonYear;        // 夏のリーグの今のシーズン
  /// リーグごとの過去の優勝球団「2026 MLB ○○」
  List<String> champions;
  /// NPB から移った選手の来歴（選手 id → 「2027年12月 ポスティングで○○へ」）
  Map<String, String> fromNpb;
  /// リーグごとの年ごとの記録（新しい順）：{'y': 年, 'st': 順位の行, 'ld': タイトルの行}
  Map<String, List<Map<String, dynamic>>> seasons;

  OtherWorld({required this.teams, required this.simDate, required this.seasonYear, List<String>? champions, Map<String, String>? fromNpb, Map<String, List<Map<String, dynamic>>>? seasons})
      : champions = champions ?? [],
        fromNpb = fromNpb ?? {},
        seasons = seasons ?? {};

  Iterable<Player> get allPlayers => teams.expand((t) => t.players);
  List<OTeam> teamsOf(String leagueId) => [for (final t in teams) if (t.leagueId == leagueId) t];
  OTeam? teamOfPlayer(String playerId) {
    for (final t in teams) {
      for (final p in t.players) {
        if (p.id == playerId) return t;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'teams': [for (final t in teams) t.toJson()],
        'date': simDate.toIso8601String(),
        'year': seasonYear,
        if (champions.isNotEmpty) 'champ': champions,
        if (fromNpb.isNotEmpty) 'fromNpb': fromNpb,
        if (seasons.isNotEmpty) 'seasons': seasons,
      };

  factory OtherWorld.fromJson(Map<String, dynamic> j) => OtherWorld(
        teams: [for (final e in (j['teams'] as List? ?? [])) OTeam.fromJson(Map<String, dynamic>.from(e as Map))],
        simDate: DateTime.parse(j['date']),
        seasonYear: j['year'] ?? 2026,
        champions: List<String>.from(j['champ'] ?? const []),
        fromNpb: Map<String, String>.from((j['fromNpb'] as Map?) ?? {}),
        seasons: {
          for (final e in ((j['seasons'] as Map?) ?? const {}).entries)
            '${e.key}': [for (final x in (e.value as List)) Map<String, dynamic>.from(x as Map)],
        },
      );
}
