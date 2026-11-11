import 'dart:math';
import 'facility_engine.dart';
import '../models/finance.dart';
import '../models/player.dart';
import '../models/team.dart';

/// 球団経営の計算（単位：万円）
///  目安：平均的な球団は 収入 約130億（入場料95・グッズ飲食20・放映権14・スポンサー5〜15）、
///  支出 約130億（年俸30＋コーチ3＋運営費約100）で、ほぼ収支が釣り合う
class FinanceEngine {
  static const operatingPerMonth = 88000; // 運営費（年105億。試合のある月が重く、オフは軽い）
  static const capacity = 50000;          // 球場の収容人数（ver1.0 は12球団とも同じ球場）
  static const initialFunds = 1500000;    // 初期の資金（150億円）。自球団は開始時に50億〜200億円から選べる
  static const _demandBase = 40000;       // 観客の需要の基準（人気50・勝率5割で約3万人）
  static const goodsPerFan = 700;         // 観客1人あたりのグッズ・飲食の売上（円）
  static const basePrice = 4000;          // 標準のチケット価格（円）
  static const maxSponsors = 6;

  static double _g(Random r) {
    final u1 = 1.0 - r.nextDouble();
    final u2 = r.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  /// 球団ごとの初期値（人気はばらつかせる。球場と資金は全球団同じ）
  static TeamFinance create(Team t, Random r, {required bool cpu}) => TeamFinance(
        teamId: t.id,
        capacity: capacity,
        popularity: (52 + _g(r) * 9).round().clamp(30, 80),
        funds: initialFunds,
        ticketPrice: basePrice,
        autoManage: cpu,
        ownerSat: 60,
      );

  // ───────── 観客と1試合の収入 ─────────

  /// チケット価格による需要の変化（高いほど客が減る。4500円前後で入場料収入が最も大きくなる）
  ///  スタジアムを改修（Lv）すると、高値でも客が減りにくい
  static double elasticity(int price, {int stadiumLv = 0}) => exp(-(price - basePrice) / (4500.0 * (1 + 0.08 * stadiumLv)));

  /// 1試合の観客数
  static int attendance(TeamFinance f, {required double winPct, required double gamesBehind, required bool weekend, required String type, int? price, Random? r}) {
    final p = price ?? f.ticketPrice;
    var demand = _demandBase * (0.55 + 0.30 * f.popularity / 100 + 0.30 * (winPct - 0.5) + (gamesBehind <= 5 ? 0.05 : 0) + (weekend ? 0.08 : 0));
    demand *= elasticity(p, stadiumLv: f.fac('stadium'));
    if (type == 'OPEN') demand *= 0.55;
    if (type == 'CS' || type == 'JS') demand *= 1.3;
    if (r != null) demand *= 0.94 + r.nextDouble() * 0.12;
    return demand.round().clamp(3000, f.capacity);
  }

  /// 1試合の収入（入場料・グッズ・放映権）。ポストシーズンは単価・放映権が高い
  static Map<String, int> gameRevenue(TeamFinance f, int att, String type, {double goodsMult = 1.0}) {
    final post = type == 'CS' || type == 'JS';
    final open = type == 'OPEN';
    final price = f.ticketPrice * (post ? 1.5 : (open ? 0.6 : 1.0));
    return {
      '入場料': (att * price / 10000).round(),
      'グッズ・飲食': (att * goodsPerFan * goodsMult * FacilityEngine.goodsMult(f.fac('stadium')) / 10000).round(),
      '放映権': ((open ? 300 : 1500) * (0.6 + f.popularity / 100) * (post ? 3 : 1)).round(),
    };
  }

  /// 収入が最も大きくなるチケット価格（手腕が低いほど外れる）
  static int bestPrice(TeamFinance f, int skill, Random r) {
    var best = basePrice, bestRev = 0.0;
    for (var p = 2500; p <= FacilityEngine.maxTicket(f.fac('stadium')); p += 250) {
      final att = attendance(f, winPct: 0.5, gamesBehind: 6, weekend: false, type: 'LEAGUE', price: p);
      final rev = att * (p + goodsPerFan) / 10000.0;
      if (rev > bestRev) {
        bestRev = rev;
        best = p;
      }
    }
    final err = ((100 - skill) / 100 * 900 * _g(r)).round();
    return ((best + err) / 250).round() * 250;
  }

  // ───────── スポンサー ─────────

  static const _local = ['北斗製菓', '青葉信用金庫', '港町運輸', '白峰酒造', '桜丘ハウジング', '旭電設', '若竹不動産', '清流ガス', '光陽印刷', '富岳食品', '湖南交通', '鳴門水産', '飛鳥建設', '明星ベーカリー',
    '山吹商店街振興会', '波止場食堂', '松葉運送', '野辺山牧場', '川端造園', '石畳珈琲', '鶴見歯科クリニック', '霧ヶ峰温泉旅館', '白樺ベーカリー', '小町呉服店', '岬観光バス', '杉並ミシン'];
  static const _middle = ['双葉精工', 'みなと物流', '青嵐システム', '銀杏ハウス', '若葉ドラッグ', '北辰建機', '翠嶺リゾート', '丸十ストア', 'ひかり家電', '桜井ゴム工業',
    '千歳製粉', '朝日ヶ丘乳業', '瀬戸内ケミカル', '三笠オート', 'はるか旅行', '曙ゼミナール', '琥珀ビール', '凪ホテルズ'];
  static const _big = ['ネクスト通信', 'グローバル自動車', 'ユニオン銀行', 'サンライズ飲料', 'アーク電機', 'スカイ航空', 'メトロ百貨店', 'ニューウェーブ保険',
    '大和重工', '帝都ホールディングス', 'コスモス化学', '銀河電子', '日昇製薬', 'パシフィック海運', 'オリオン食品', '東亜商事'];

  /// 候補の数（大企業・中企業・地方企業）
  static const offerCounts = {'大企業': 8, '中企業': 14, '地方企業': 18};

  /// その年のスポンサー候補（地元企業・大企業。条件つきの契約もある）
  /// スポンサーの候補（大企業・中企業・地方企業。同じ会社は1年に1社ずつ）。counts を省くと offerCounts
  ///  大企業：年2億〜5億・人気45〜69以上　中企業：年1億〜2億・人気25〜49以上　地方企業：年3000万〜1億・条件なし
  static List<Sponsor> offers(int year, Random r, {Map<String, int>? counts}) {
    final out = <Sponsor>[];
    var i = 0;
    for (final e in (counts ?? offerCounts).entries) {
      final names = [...switch (e.key) { '大企業' => _big, '中企業' => _middle, _ => _local }]..shuffle(r);
      for (var k = 0; k < e.value && k < names.length; k++) {
        final amount = switch (e.key) { '大企業' => 20000 + r.nextInt(31) * 1000, '中企業' => 10000 + r.nextInt(11) * 1000, _ => 3000 + r.nextInt(8) * 1000 };
        final cond = ['なし', 'なし', 'Aクラス', '優勝', '観客動員'][r.nextInt(5)];
        out.add(Sponsor(
          id: 'S${year}_${i++}',
          name: names[k],
          big: e.key == '大企業',
          tier: e.key,
          amount: cond == 'なし' ? amount : (amount * 0.7).round(),
          condition: cond,
          bonus: cond == 'なし' ? 0 : (amount * (cond == '優勝' ? 1.2 : 0.6)).round(),
          minPopularity: switch (e.key) { '大企業' => 45 + r.nextInt(25), '中企業' => 25 + r.nextInt(25), _ => 0 },
          years: 1 + r.nextInt(3),
        ));
      }
    }
    return out;
  }

  /// 更新の額：人気で増減（人気50で同じ、高いほど上がる。×0.85〜×1.25）
  static int renewAmount(Sponsor s, int popularity) => ((s.amount * (0.85 + popularity / 250).clamp(0.85, 1.25)) / 100).round() * 100;

  /// スポンサーのボーナスの条件を満たしたか
  static bool conditionMet(Sponsor s, {required int rank, required int avgAttendance}) => switch (s.condition) {
        'Aクラス' => rank <= 3,
        '優勝' => rank == 1,
        '観客動員' => avgAttendance >= 30000,
        _ => false,
      };

  // ───────── コンサルタント ─────────

  static const _cLast = ['神崎', '早瀬', '柏木', '真田', '藤堂', '水島', '芹沢', '東條', '久我', '朝倉', '一ノ瀬', '桐生'];
  static const _cFirst = ['誠一', '彩香', '恭平', '真理子', '達郎', '玲奈', '修司', '沙織', '健吾', '美和'];

  static List<Consultant> consultants(int year, Random r, {int count = 8}) => [
        for (var i = 0; i < count; i++)
          () {
            final skill = (55 + _g(r) * 15).round().clamp(20, 95);
            return Consultant(
              id: 'K${year}_$i',
              name: '${_cLast[r.nextInt(_cLast.length)]} ${_cFirst[r.nextInt(_cFirst.length)]}',
              skill: skill,
              salary: ((800 + skill * 45 + r.nextInt(800)) / 10).round() * 10,
            );
          }(),
      ];

  /// コンサルタントの手腕による収入の効率（0.92〜1.08）
  static double efficiency(int skill) => 0.92 + skill * 0.0016;

  // ───────── グッズ ─────────

  /// 選手グッズの人気の目安（能力・今季の成績・年齢）
  static double playerAppeal(Player p) {
    final s = p.seasonStats;
    var a = 0.5 + (p.ovr - 60) / 25;
    a += p.isPitcher ? s.wins / 25 + s.saves / 60 : s.homeRuns / 40 + s.hits / 300;
    if (p.age <= 24) a += 0.15;
    return a.clamp(0.3, 2.2);
  }

  /// 企画の費用と、売れ行き（隠し。当たり外れあり）
  static (int, double) planGoods(String kind, double base, TeamFinance f, Random r) {
    final cost = switch (kind) { '選手グッズ' => 2000, '記念グッズ' => 3000, _ => 5000 };
    final luck = exp(_g(r) * 0.45); // 当たり外れ
    final appeal = (base * (0.7 + f.popularity / 160) * luck).clamp(0.2, 3.0);
    return (cost, appeal);
  }

  /// 企画の売上（費用×売れ行き×1.6）
  static int goodsRevenue(GoodsProject g) => (g.cost * g.appeal * 1.6).round();

  // ───────── 人気・オーナー ─────────

  /// 期待される順位（年俸総額のリーグ内順位から。2〜5位の間）
  static double expectedRank(int payrollRank, int teams) => (teams + 1) / 2 + (payrollRank - (teams + 1) / 2) * 0.6;

  /// シーズン終了時のオーナーの評価（0〜100）と理由
  static (int, List<String>) ownerEval({
    required int rank,
    required double expected,
    required bool pennant,
    required bool champion,
    required bool cs,
    required int? prevRank,
    required int profit,
    required int avgAtt,
    required int prevAtt,
    required int sponsors,
  }) {
    final notes = <String>[];
    var v = 50.0;
    final diff = expected - rank;
    v += diff * 8;
    notes.add('順位 $rank位（期待 ${expected.toStringAsFixed(1)}位）：${diff >= 0 ? '+' : ''}${(diff * 8).round()}');
    if (champion) {
      v += 20;
      notes.add('日本一：+20');
    } else if (pennant) {
      v += 12;
      notes.add('リーグ優勝：+12');
    } else if (cs) {
      v += 4;
      notes.add('CS 進出：+4');
    }
    if (prevRank != null && prevRank != rank) {
      final d = (prevRank - rank) * 3;
      v += d;
      notes.add('前年からの順位の変化：${d >= 0 ? '+' : ''}$d');
    }
    final pf = (profit / 100000 * 5).clamp(-15.0, 15.0); // 10億円で5点
    v += pf;
    notes.add('収支 ${profit >= 0 ? '+' : ''}${(profit / 10000).toStringAsFixed(1)}億円：${pf >= 0 ? '+' : ''}${pf.round()}');
    if (prevAtt > 0) {
      final a = ((avgAtt - prevAtt) / 1000).clamp(-6.0, 6.0);
      v += a;
      notes.add('観客動員（1試合 ${avgAtt}人、前年 ${prevAtt}人）：${a >= 0 ? '+' : ''}${a.round()}');
    }
    final sp = (sponsors - 3) * 1.5;
    v += sp;
    notes.add('スポンサー $sponsors社：${sp >= 0 ? '+' : ''}${sp.round()}');
    return (v.round().clamp(0, 100), notes);
  }
}
