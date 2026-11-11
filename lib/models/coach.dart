/// コーチ・OB（引退した選手）。コーチもスカウトも、すべての能力を持つ
///  - 本当の能力（trueAbil）は、雇って1シーズン経つと分かる（known）
///  - それまでは、通算成績から予想される値（expected）に幅を持たせて表示する
///  - 本当の能力 ＝ 50% は通算成績から予想される値 ＋ 50% は隠れた値（期待外れ・期待以上もある）
class Coach {
  final String id;
  String lastName;
  String firstName;
  int age;
  bool pitcherBg;        // 現役時代は投手
  String type;           // 現役時代のタイプ（選手と同じ分類。相性に使う）
  String formerTeamId;   // 古巣（同じ条件なら古巣を優先する）
  Map<String, int> career; // 通算成績の要約（試合・安打・本塁打・打率×1000／登板・勝利・セーブ・防御率×100）
  Map<String, int> trueAbil;
  Map<String, int> expected;
  bool known;
  int salary;            // 年俸（万円）
  String? teamId;        // 所属球団（null なら OB 一覧）
  String? role;          // 役職
  int seasonsWithTeam;   // いまの球団での在任年数
  int mgrWins = -1;      // 監督としての通算勝利（-1 は不明：ゲーム開始時からの監督。新しく監督になると0から数える）
  Map<String, int> style; // 監督の傾向（バント・盗塁・継投の早さ・若手起用、0〜100）。監督でなければ空

  static const abilityKeys = ['打撃', '守備', '走塁', '球速球威', '制球', 'スタミナ', '変化球', '人望', '代打判断', '継投判断', '守備交代判断', '走塁判断', 'スカウト眼力', '育成眼'];
  static const teachKeys = ['打撃', '守備', '走塁', '球速球威', '制球', 'スタミナ', '変化球'];

  Coach({
    required this.id,
    required this.lastName,
    required this.firstName,
    required this.age,
    required this.pitcherBg,
    required this.type,
    required this.formerTeamId,
    required this.career,
    required this.trueAbil,
    required this.expected,
    this.known = false,
    this.salary = 1000,
    this.teamId,
    this.role,
    this.seasonsWithTeam = 0,
    Map<String, int>? style,
  }) : style = style ?? {};

  String get name => '$lastName $firstName';

  /// 画面に出す値。分かっていれば本当の値、分からなければ null
  int? shown(String key) => known ? trueAbil[key] : null;

  /// 分からないときの幅（予想値±12）
  (int, int) range(String key) {
    final e = expected[key] ?? 50;
    return ((e - 12).clamp(1, 99), (e + 12).clamp(1, 99));
  }

  /// 通算成績の一言（例：1856試合 2013安打 241本 .289）
  String get careerText {
    if (pitcherBg) {
      final era = (career['era'] ?? 0) / 100;
      return '${career['games'] ?? 0}登板 ${career['wins'] ?? 0}勝 ${career['saves'] ?? 0}S 防御率${era.toStringAsFixed(2)}';
    }
    final avg = (career['avg'] ?? 0) / 1000;
    return '${career['games'] ?? 0}試合 ${career['hits'] ?? 0}安打 ${career['hr'] ?? 0}本 ${avg.toStringAsFixed(3).replaceFirst('0.', '.')}';
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'lastName': lastName, 'firstName': firstName, 'age': age, 'pitcherBg': pitcherBg, 'type': type,
        'formerTeamId': formerTeamId, 'career': career, 'trueAbil': trueAbil, 'expected': expected, 'known': known,
        'salary': salary, 'teamId': teamId, 'role': role, 'seasonsWithTeam': seasonsWithTeam, if (mgrWins >= 0) 'mgrWins': mgrWins,
        if (style.isNotEmpty) 'style': style,
      };

  factory Coach.fromJson(Map<String, dynamic> j) => Coach(
        id: j['id'], lastName: j['lastName'], firstName: j['firstName'], age: j['age'], pitcherBg: j['pitcherBg'] ?? false,
        type: j['type'] ?? '万能型', formerTeamId: j['formerTeamId'] ?? '',
        career: Map<String, int>.from(j['career'] ?? {}), trueAbil: Map<String, int>.from(j['trueAbil'] ?? {}),
        expected: Map<String, int>.from(j['expected'] ?? {}), known: j['known'] ?? false, salary: j['salary'] ?? 1000,
        teamId: j['teamId'], role: j['role'], seasonsWithTeam: j['seasonsWithTeam'] ?? 0,
        style: j['style'] != null ? Map<String, int>.from(j['style']) : null,
      )..mgrWins = j['mgrWins'] ?? -1;
}
