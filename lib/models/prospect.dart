import 'player.dart';

/// ドラフト候補（高校・大学・社会人・独立リーグ）
///  - 能力と才能・向上心（隠し）は player に入っている
///  - 自球団のスカウトの見立て（reports・才能と向上心の幅）だけが画面に出る
class Prospect {
  final Player player;
  final int year;          // ドラフトの年（その年の10月31日に指名する）
  String category;         // 高校 / 大学 / 社会人 / 独立
  String school;           // 学校・チーム名（架空）
  bool ikuseiTier;         // 育成候補（本指名の評価に届かない選手）
  int curBias;             // 今の能力の見立てのずれ（−4〜+4。表示は ±5 の幅）
  int reports;             // 自球団スカウトの調査回数
  int? talentLo, talentHi;     // 自球団スカウトによる才能の見立ての幅。null=まだ調べていない
  int? ambitionLo, ambitionHi; // 同じく向上心の見立ての幅
  List<String> memo;           // スカウトメモ（架空のアマチュア成績）
  bool watched;            // 注目（スカウトが優先して調べる）
  String comment;          // スカウトの一言
  // 志望届（9月1日に出す。出した時点で固定）
  bool wishFiled;          // 志望届を出した
  List<String> wishes;     // 希望球団（1〜3。空なら「希望なし」）
  List<String> wishNames;  // 希望球団の略称（表示用）
  String orient;           // 志向タイプ（出場機会重視・優勝志向・育成重視・華やかさ志向）
  List<String> idols;      // 憧れの選手（3人の id）
  /// この候補を発掘・調査した球団（ここにない球団からは「不明」。空は以前の方式の候補で、全球団が知っている）
  Set<String> knownBy;

  Prospect({
    required this.player,
    required this.year,
    required this.category,
    required this.school,
    this.ikuseiTier = false,
    this.curBias = 0,
    this.reports = 0,
    this.talentLo,
    this.talentHi,
    this.ambitionLo,
    this.ambitionHi,
    this.memo = const [],
    this.watched = false,
    this.comment = '',
    this.wishFiled = false,
    List<String>? wishes,
    List<String>? wishNames,
    this.orient = '',
    List<String>? idols,
    Set<String>? knownBy,
  })  : knownBy = knownBy ?? {},
        wishes = wishes ?? [],
        wishNames = wishNames ?? [],
        idols = idols ?? [];

  String get id => player.id;

  /// その球団が知っている候補か
  bool knownTo(String teamId) => knownBy.isEmpty || knownBy.contains(teamId);

  Map<String, dynamic> toJson() => {
        'player': player.toJson(),
        'year': year,
        'category': category,
        'school': school,
        'ikuseiTier': ikuseiTier,
        'curBias': curBias,
        'reports': reports,
        'talentLo': talentLo,
        'talentHi': talentHi,
        'ambitionLo': ambitionLo,
        'ambitionHi': ambitionHi,
        'memo': memo,
        'watched': watched,
        'comment': comment,
        if (knownBy.isNotEmpty) 'kb': knownBy.toList(),
        if (wishFiled) 'wish': {'f': true, 'w': wishes, 'n': wishNames, 'o': orient, 'i': idols},
      };

  factory Prospect.fromJson(Map<String, dynamic> j) => Prospect(
        player: Player.fromJson(Map<String, dynamic>.from(j['player'] as Map)),
        year: j['year'] ?? 0,
        category: j['category'] ?? '高校',
        school: j['school'] ?? '',
        ikuseiTier: j['ikuseiTier'] ?? false,
        curBias: j['curBias'] ?? 0,
        reports: j['reports'] ?? 0,
        talentLo: j['talentLo'],
        talentHi: j['talentHi'],
        ambitionLo: j['ambitionLo'],
        ambitionHi: j['ambitionHi'],
        memo: j['memo'] != null ? List<String>.from(j['memo']) : const [],
        watched: j['watched'] ?? false,
        comment: j['comment'] ?? '',
        wishFiled: (j['wish'] as Map?)?['f'] == true,
        wishes: List<String>.from((j['wish'] as Map?)?['w'] ?? const []),
        wishNames: List<String>.from((j['wish'] as Map?)?['n'] ?? const []),
        orient: '${(j['wish'] as Map?)?['o'] ?? ''}',
        idols: List<String>.from((j['wish'] as Map?)?['i'] ?? const []),
        knownBy: Set<String>.from(j['kb'] ?? const []),
      );

  /// 「希望：ソ・西・東」「希望なし」（志望届の前は空）
  String get wishText => !wishFiled ? '' : (wishes.isEmpty ? '希望なし' : '希望：${wishNames.join('・')}');
}
