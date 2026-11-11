/// 球団経営のデータ（単位：万円）
class TeamFinance {
  final String teamId;
  int funds;            // 球団の資金
  int popularity;       // 人気（0〜100）
  int capacity;         // 球場の収容人数
  int ticketPrice;      // 平均チケット価格（円）
  bool autoManage;      // 経営をコンサルタントにおまかせ
  String consultantId;  // 雇っている経営コンサルタント（'' はなし）
  List<Sponsor> sponsors;
  List<GoodsProject> goods;
  int ownerSat;         // オーナー満足度（0〜100）
  List<int> satHistory; // シーズン終了時の満足度（古い順）
  List<String> ownerNotes; // 満足度の理由（直近の評価）
  Map<String, int> season;   // 今季の収支（項目 → 金額。収入は+、支出は−）
  Map<String, int> lastSeason; // 前年の収支
  int homeGames;        // 今季の主催試合数（公式戦・ポストシーズン）
  int attendance;       // 今季の観客動員の合計
  int lastAttendance;   // 前年の1試合平均
  Map<String, int> facilities; // 施設の Lv（bio・medical・scout・stadium。0〜5）
  List<String> makerDeals; // 用具メーカーとのアドバイザリー契約（メーカー名）

  TeamFinance({
    required this.teamId,
    this.funds = 200000,
    this.popularity = 50,
    this.capacity = 50000,
    this.ticketPrice = 4000,
    this.autoManage = true,
    this.consultantId = '',
    List<Sponsor>? sponsors,
    List<GoodsProject>? goods,
    this.ownerSat = 60,
    List<int>? satHistory,
    List<String>? ownerNotes,
    Map<String, int>? season,
    Map<String, int>? lastSeason,
    this.homeGames = 0,
    this.attendance = 0,
    this.lastAttendance = 0,
    Map<String, int>? facilities,
    List<String>? makerDeals,
  })  : facilities = facilities ?? {},
        makerDeals = makerDeals ?? [],
        sponsors = sponsors ?? [],
        goods = goods ?? [],
        satHistory = satHistory ?? [],
        ownerNotes = ownerNotes ?? [],
        season = season ?? {},
        lastSeason = lastSeason ?? {};

  int get seasonProfit => season.values.fold(0, (a, b) => a + b);
  int get avgAttendance => homeGames == 0 ? 0 : attendance ~/ homeGames;

  void add(String category, int amount) {
    funds += amount;
    season[category] = (season[category] ?? 0) + amount;
  }

  Map<String, dynamic> toJson() => {
        'teamId': teamId, 'funds': funds, 'popularity': popularity, 'capacity': capacity, 'ticketPrice': ticketPrice,
        'autoManage': autoManage, 'consultantId': consultantId,
        'sponsors': sponsors.map((s) => s.toJson()).toList(), 'goods': goods.map((g) => g.toJson()).toList(),
        'ownerSat': ownerSat, 'satHistory': satHistory, 'ownerNotes': ownerNotes, 'season': season, 'lastSeason': lastSeason,
        'homeGames': homeGames, 'attendance': attendance, 'lastAttendance': lastAttendance,
        if (facilities.isNotEmpty) 'fac': facilities,
        if (makerDeals.isNotEmpty) 'makers': makerDeals,
      };

  int fac(String key) => facilities[key] ?? 0;

  factory TeamFinance.fromJson(Map<String, dynamic> j) => TeamFinance(
        teamId: j['teamId'],
        funds: j['funds'] ?? 200000,
        popularity: j['popularity'] ?? 50,
        capacity: j['capacity'] ?? 35000,
        ticketPrice: j['ticketPrice'] ?? 4000,
        autoManage: j['autoManage'] ?? true,
        consultantId: j['consultantId'] ?? '',
        sponsors: [for (final s in (j['sponsors'] as List? ?? [])) Sponsor.fromJson(Map<String, dynamic>.from(s as Map))],
        goods: [for (final g in (j['goods'] as List? ?? [])) GoodsProject.fromJson(Map<String, dynamic>.from(g as Map))],
        ownerSat: j['ownerSat'] ?? 60,
        satHistory: List<int>.from(j['satHistory'] ?? []),
        ownerNotes: List<String>.from(j['ownerNotes'] ?? []),
        season: Map<String, int>.from(j['season'] ?? {}),
        lastSeason: Map<String, int>.from(j['lastSeason'] ?? {}),
        homeGames: j['homeGames'] ?? 0,
        attendance: j['attendance'] ?? 0,
        lastAttendance: j['lastAttendance'] ?? 0,
        facilities: Map<String, int>.from(j['fac'] ?? {}),
        makerDeals: List<String>.from(j['makers'] ?? []),
      );
}

/// スポンサー（条件つきの契約もある）
class Sponsor {
  final String id;
  final String name;
  final bool big;        // 大企業（人気が一定以上でないと契約できない）
  final int amount;      // 年額（万円）
  final String condition; // なし / Aクラス / 優勝 / 観客動員
  final int bonus;       // 条件を満たしたときのボーナス（万円）
  final int minPopularity;
  int years;             // 残りの契約年数（今年を含む）
  final String tier;     // 大企業 / 中企業 / 地方企業（以前のデータは big から）
  bool pending;          // 12月に結んだ来季からの契約（1月1日から。それまでは支払いも枠も来季の分）

  Sponsor({required this.id, required this.name, required this.big, required this.amount, this.condition = 'なし', this.bonus = 0, this.minPopularity = 0, this.years = 1, String tier = '', this.pending = false})
      : tier = tier.isNotEmpty ? tier : (big ? '大企業' : '地方企業');

  String get conditionText => switch (condition) {
        'Aクラス' => 'Aクラス（3位以内）でボーナス',
        '優勝' => 'リーグ優勝でボーナス',
        '観客動員' => '1試合平均3万人以上でボーナス',
        _ => '条件なし',
      };

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'big': big, 'amount': amount, 'condition': condition, 'bonus': bonus, 'minPop': minPopularity, 'years': years, 'tier': tier, if (pending) 'pending': true};
  factory Sponsor.fromJson(Map<String, dynamic> j) =>
      Sponsor(id: j['id'], name: j['name'], big: j['big'] ?? false, amount: j['amount'] ?? 0, condition: j['condition'] ?? 'なし', bonus: j['bonus'] ?? 0, minPopularity: j['minPop'] ?? 0, years: j['years'] ?? 1, tier: j['tier'] ?? '', pending: j['pending'] ?? false);

  /// 条件を変えずに年数・額だけ変えた契約（更新）
  Sponsor renewed({required int amount, required int years}) =>
      Sponsor(id: id, name: name, big: big, amount: amount, condition: condition, bonus: condition == 'なし' ? 0 : (bonus * amount / (this.amount == 0 ? 1 : this.amount)).round(), minPopularity: minPopularity, years: years, tier: tier);
}

/// グッズ企画（売れ行きに当たり外れがある）
class GoodsProject {
  final String id;
  final String kind;     // 選手グッズ / 記念グッズ / 限定ユニフォーム
  final String label;    // 例：「佐藤 翔太 グッズ」
  final int cost;        // 費用（万円）
  final String endDate;  // 販売の終わる日（yyyy-mm-dd）
  final double appeal;   // 売れ行きの見込み（隠し。0.3〜2.5 倍）
  int revenue;           // 売上（終わったら決まる）
  bool done;

  GoodsProject({required this.id, required this.kind, required this.label, required this.cost, required this.endDate, required this.appeal, this.revenue = 0, this.done = false});

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind, 'label': label, 'cost': cost, 'end': endDate, 'appeal': appeal, 'revenue': revenue, 'done': done};
  factory GoodsProject.fromJson(Map<String, dynamic> j) => GoodsProject(
        id: j['id'], kind: j['kind'] ?? '', label: j['label'] ?? '', cost: j['cost'] ?? 0, endDate: j['end'] ?? '',
        appeal: (j['appeal'] as num?)?.toDouble() ?? 1.0, revenue: j['revenue'] ?? 0, done: j['done'] ?? false,
      );
}

/// 経営コンサルタント（雇うと経営をおまかせにできる。結果は手腕しだい）
class Consultant {
  final String id;
  final String name;
  final int skill;   // 手腕（1〜100）
  final int salary;  // 年俸（万円）
  String teamId;     // 雇っている球団（'' はフリー）

  Consultant({required this.id, required this.name, required this.skill, required this.salary, this.teamId = ''});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'skill': skill, 'salary': salary, 'teamId': teamId};
  factory Consultant.fromJson(Map<String, dynamic> j) => Consultant(id: j['id'], name: j['name'], skill: j['skill'] ?? 50, salary: j['salary'] ?? 2000, teamId: j['teamId'] ?? '');
}
