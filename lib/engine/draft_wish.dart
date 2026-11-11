import 'dart:math';
import '../models/player.dart';
import '../models/prospect.dart';

/// 志望届と希望球団（仕様書 docs/transfer_system_spec.md 1.2・1.3）
///  志望届を出すときに、希望球団を1〜3まで決めるか「希望なし」を選ぶ。出した時点で固定する。
///  入団した球団で国内FA が短くなる：1希望は短縮なし、2・3希望は1年、それ以外は2年。「希望なし」は短縮なし
class DraftWish {
  /// 志向タイプ（重く見る要素）
  static const orients = ['出場機会重視', '優勝志向', '育成重視', '華やかさ志向'];

  /// 「希望なし」を選ぶ割合（仮）
  static const noWishRate = 0.3;

  /// 入団した球団による国内FA の短縮年数
  static int faShortFor(Prospect pr, String teamId) {
    if (pr.wishes.isEmpty) return 0;
    final i = pr.wishes.indexOf(teamId);
    if (i == 0) return 0;
    if (i == 1 || i == 2) return 1;
    return 2;
  }

  /// 「1希望」「希望外」「希望なし」
  static String wishLabel(Prospect pr, String teamId) {
    if (!pr.wishFiled) return '';
    if (pr.wishes.isEmpty) return '希望なし';
    final i = pr.wishes.indexOf(teamId);
    return i < 0 ? '希望外' : '${i + 1}希望';
  }

  /// 志望届を出す：球団ごとの点数（7要素）を志向タイプで重みづけし、上位を1〜3希望にする
  static void file(Prospect pr, List<WishTeam> teams, List<Player> league, Random r) {
    if (pr.wishFiled || teams.isEmpty) return;
    final pl = pr.player;
    pr.orient = orients[r.nextInt(orients.length)];
    // 憧れの選手（3人）：同じ投手／野手の、力のある選手から
    final stars = league.where((p) => p.isPitcher == pl.isPitcher && !p.ikusei).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final top = stars.take(40).toList()..shuffle(r);
    pr.idols = [for (final p in top.take(3)) p.id];
    pr.wishFiled = true;
    if (r.nextDouble() < noWishRate) {
      pr.wishes = [];
      pr.wishNames = [];
      return;
    }
    // 要素ごとに 0〜1 にそろえる（球団の間で最小〜最大）
    List<double> norm(List<double> v) {
      final lo = v.reduce(min), hi = v.reduce(max);
      return [for (final x in v) hi - lo < 1e-9 ? 0.5 : (x - lo) / (hi - lo)];
    }

    final fac = norm([for (final t in teams) t.facility.toDouble()]);
    final aff = norm([for (final t in teams) t.affinity]);
    final idol = [for (final t in teams) pr.idols.any(t.playerIds.contains) ? 1.0 : 0.0];
    final chance = norm([for (final t in teams) -t.depth.toDouble()]); // 自分のポジションの層が薄いほど高い
    final funds = norm([for (final t in teams) t.funds.toDouble()]);
    final strong = norm([for (final t in teams) t.strength]);
    final pop = norm([for (final t in teams) t.popularity.toDouble()]);
    double w(String k) => switch (pr.orient) {
          '出場機会重視' => k == 'chance' ? 3 : 1,
          '優勝志向' => k == 'strong' ? 3 : 1,
          '育成重視' => k == 'fac' || k == 'aff' ? 2.5 : 1,
          _ => k == 'pop' || k == 'funds' ? 2.5 : 1,
        };
    final score = <String, double>{};
    for (var i = 0; i < teams.length; i++) {
      score[teams[i].id] = fac[i] * w('fac') + aff[i] * w('aff') + idol[i] * 1.2 + chance[i] * w('chance') + funds[i] * w('funds') + strong[i] * w('strong') + pop[i] * w('pop') + r.nextDouble() * 1.5;
    }
    final order = teams.toList()..sort((a, b) => score[b.id]!.compareTo(score[a.id]!));
    final n = [1, 2, 3, 3][r.nextInt(4)];
    pr.wishes = [for (final t in order.take(n)) t.id];
    pr.wishNames = [for (final t in order.take(n)) t.short];
  }
}

/// 志望届の点数に使う球団の情報
class WishTeam {
  final String id, short;
  final int facility;     // 育成設備（バイオメカニクス解析ラボ＋メディカル）のレベル
  final double affinity;  // 監督との相性（CoachEngine.affinity）
  final Set<String> playerIds;
  final int depth;        // 自分のポジションの層（同じ守備位置の支配下の選手の数。投手は投手の数の半分）
  final int funds;
  final double strength;  // 前年の順位（なければ今季の勝率）から
  final int popularity;
  const WishTeam({required this.id, required this.short, required this.facility, required this.affinity, required this.playerIds, required this.depth, required this.funds, required this.strength, required this.popularity});
}
