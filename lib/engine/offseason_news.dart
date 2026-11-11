import 'dart:math';
import '../models/player.dart';
import '../models/team.dart';
import 'game_news.dart' show FanComment;
import 'item_news.dart';
import 'trade_rumor.dart';
import 'news_talk.dart';
import 'transfer_engine.dart' show FaCase, FreeAgent;

/// オフシーズン（11月〜2月）の去就予想：その週の月曜付けで、FA 宣言選手・自由契約の選手・新外国人の候補について
///  評論家が行き先を予想する記事。保存はせず、いまの状況から毎回同じ記事を作る
class OffseasonNews {
  static const _critics = ['山根 誠一', '大川 剛', '佐伯 修', '黒沢 透', '森本 健吾'];
  static String _short(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;

  static bool isOffseason(DateTime d) => d.month >= 11 || d.month <= 2;

  /// 選手の守備のまとまり（球団に入る前の選手にも使う）
  static String _groupOf(Player p) {
    if (p.isPitcher) return p.stamina >= 55 ? '先発投手' : '中継ぎ';
    return switch (p.mainPosition) {
      '捕手' => '捕手',
      '一塁手' || '二塁手' || '三塁手' || '遊撃手' => '内野手',
      _ => '外野手',
    };
  }

  /// その選手のまとまりがいちばん手薄な球団（except は除く）
  static List<Team> _needy(List<Team> teams, Player p, String exceptId) {
    final g = _groupOf(p);
    final l = teams.where((t) => t.id != exceptId).toList()
      ..sort((a, b) => TradeRumor.scoreOf(TradeRumor.depthOf(a)[g]!, g).compareTo(TradeRumor.scoreOf(TradeRumor.depthOf(b)[g]!, g)));
    return l;
  }

  static List<FanComment> _fans(Random r, List<String> lines, String crowd) {
    final l = [...lines]..shuffle(r);
    final names = ['名無しの${crowd}ファン', '現地組', 'ライトスタンドの民', '野球好きの会社員', 'オフも野球の話がしたい'];
    return [
      for (final x in l.take(5 + r.nextInt(3))) FanComment(names[r.nextInt(names.length)], x, 5 + r.nextInt(250), '${1 + r.nextInt(58)}分前', !x.contains('いらん') && !x.contains('無理')),
    ]..sort((a, b) => b.likes.compareTo(a.likes));
  }

  static String _prof(Player p) => '${p.registeredName}（${p.age}歳・${p.isPitcher ? '投手' : p.mainPosition}）';

  /// いまの週の予想記事（FA・自由契約・新外国人を1本ずつまで）
  static List<(DateTime, ItemNews)> predictions({
    required List<Team> teams,
    required List<FaCase> faCases,
    required List<FreeAgent> freeAgents,
    required List<Player> foreignPool,
    required DateTime today,
    required Player? Function(String id) playerById,
    String? myTeamId,
  }) {
    if (!isOffseason(today)) return const [];
    final league = teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    if (league.length < 4) return const [];
    var monday = today;
    while (monday.weekday != DateTime.monday) {
      monday = monday.subtract(const Duration(days: 1));
    }
    final r = Random(monday.millisecondsSinceEpoch ~/ 86400000 * 17 + 3);
    final date = '${monday.month}/${monday.day}';
    final critic = _critics[r.nextInt(_critics.length)];
    final out = <(DateTime, ItemNews)>[];
    Team? teamById(String id) => league.where((t) => t.id == id).firstOrNull;

    // FA：まだ決まっていない選手（ランクの高い順）
    final open = faCases.where((c) => c.result.isEmpty).toList()..sort((a, b) => a.rank.compareTo(b.rank));
    if (open.isNotEmpty) {
      final c = open[r.nextInt(min(3, open.length))];
      final p = playerById(c.playerId);
      final from = teamById(c.fromTeamId);
      if (p != null && from != null) {
        // 本命：条件を出している球団（年俸の高い順）。無ければ手薄な球団
        final offers = c.offers.entries.where((e) => e.key != from.id).toList()..sort((a, b) => b.value[0].compareTo(a.value[0]));
        final fav = offers.isNotEmpty ? teamById(offers.first.key) : _needy(league, p, from.id).first;
        final dark = _needy(league, p, from.id).firstWhere((t) => t != fav, orElse: () => from);
        if (fav != null) {
          final g = _groupOf(p);
          final years = p.age <= 29 ? 5 : (p.age <= 32 ? 4 : (p.age <= 34 ? 3 : 2));
          final total = c.ask * years; // 万円
          final money = total >= 10000 ? '${(total / 10000).round()}億' : '${(total / 1000).round()}千万';
          final head = '${_short(fav)}　ＦＡ宣言の${_short(from)}${p.lastName.isNotEmpty ? p.lastName : p.registeredName}を獲得調査　$years年$money級の${total >= 50000 ? '大型契約' : '複数年契約'}準備';
          final body = [
            '${_short(from)}からFA宣言した${_prof(p)}の去就に注目が集まっている。',
            'ランクは${c.rank}で、希望は年俸${(c.ask / 10000).toStringAsFixed(c.ask % 10000 == 0 ? 0 : 1)}億円前後とみられる。',
            if (offers.length >= 2) '${offers.length}球団が条件を提示しており、争奪戦の様相だ。',
            NewsTalk.stats(p),
            '${_short(fav)}は$gの補強が急務で、$years年総額$money円規模の条件を用意しているとみられる。',
            '野球評論家の$critic氏は「${NewsTalk.insight(p, r)}。${_short(fav)}が本命だが、${_short(dark)}も獲得に動けば面白くなる。${_short(from)}の残留交渉も最後まで分からない」と話す。',
            'あくまで評論家の見立てで、球団からの発表はない。',
          ];
          out.add((monday, ItemNews(NewsTopic.rumor, date, head, head, body, p, fav, _fans(r, ['${p.registeredName}来てくれたら優勝できる', '$years年$moneyは高すぎんか', 'マネーゲームになったら勝てん', '${_short(fav)}が本命は納得', '評論家の予想は当たらんからな', '${p.registeredName}ならどこでも活躍しそう', '${p.age}歳で$years年契約はリスクある', ...NewsTalk.fanInsight(p, r)], _short(fav)), _fans(r, ['また${_short(fav)}が取るんか', 'FAの目玉やな', '${_short(from)}はどう引き止めるんやろ', '${p.registeredName}は${_short(from)}に残るべき', '${p.registeredName}には残ってほしい…', '人的補償で誰が取られるか心配', ...NewsTalk.fanInsight(p, r)], '他球団'), playerTeam: from)));
        }
      }
    }

    // 自由契約：力のある選手（総合の高い順）
    final fas = freeAgents.where((f) => f.player.age <= 36).toList()..sort((a, b) => b.player.ovr.compareTo(a.player.ovr));
    if (fas.isNotEmpty) {
      final f = fas[r.nextInt(min(3, fas.length))];
      final p = f.player;
      final from = teamById(f.fromTeamId);
      final fav = _needy(league, p, f.fromTeamId).first;
      final head = '【自由契約選手の行方】${p.registeredName}に${_short(fav)}が関心か　新天地でチャンスをつかみ取れるか';
      final body = [
        '${from == null ? '' : '${_short(from)}を'}${f.reason.isEmpty ? '自由契約' : f.reason}となった${_prof(p)}の行き先に、関心が集まっている。',
        NewsTalk.stats(p),
        '野球評論家の$critic氏は「${_groupOf(p)}が手薄な${_short(fav)}なら、すぐに出番がある。${NewsTalk.insight(p, r)}」と見る。',
        '独立リーグや海外を含め、再出発の場所はどこになるか。',
      ];
      out.add((monday, ItemNews(NewsTopic.rumor, date, head, head, body, p, fav, _fans(r, ['${p.registeredName}来てくれ', '格安で取れるなら大歓迎', '${p.registeredName}はまだやれる', '枠が空いてるならありやな', '${p.registeredName}いらん、若手使え', '育成契約からでもええやん', ...NewsTalk.fanInsight(p, r)], _short(fav)), _fans(r, ['${p.registeredName}頑張れ', 'どこかで拾われてほしい', '${from == null ? '' : _short(from)}は見切るの早かったかも'], '他球団'), playerTeam: from)));
    }

    // 新外国人：候補（育成以外）の目玉
    final pool = foreignPool.where((p) => !p.ikusei).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    if (pool.isNotEmpty) {
      final p = pool[r.nextInt(min(5, pool.length))];
      final fav = _needy(league, p, '').first;
      // 来日前の成績の最新の行「2025　MLB・○○　…」の2つめ（リーグ・球団）
      final parts = p.abroad.isEmpty ? const <String>[] : p.abroad.first.split('　');
      final where = parts.length > 1 ? parts[1] : '';
      final head = '【新外国人予想】${p.registeredName}（${p.origin.isEmpty ? '海外' : p.origin}）に${_short(fav)}が調査か';
      final body = [
        '来季の助っ人候補として、${p.origin.isEmpty ? '' : '${p.origin}出身の'}${_prof(p)}の名前が挙がっている。',
        if (where.isNotEmpty) '直近は$whereでプレー。',
        p.isPitcher ? '最速${p.velocity}km/hの${p.control >= 60 ? '制球も安定した' : '力で押す'}投球が持ち味だ。' : '${p.power >= 70 ? '長打力' : 'ミート力'}が売りで、${p.power >= 70 ? '中軸' : '上位打線'}を任せられる力がある。',
        '野球評論家の$critic氏は「${_groupOf(p)}が手薄な${_short(fav)}にぴったり。${NewsTalk.insight(p, r)}。日本の野球に順応できるかがカギ」と話す。',
      ];
      out.add((monday, ItemNews(NewsTopic.rumor, date, head, head, body, p, fav, _fans(r, [p.isPitcher ? '${p.registeredName}来たらローテが厚くなる' : '${p.registeredName}来たら打線変わる', '助っ人ガチャ、今年こそ当たってくれ', '${p.registeredName}の動画見たけどえぐい', '日本の野球に合うかが心配', '大型契約はやめとけ', '${p.age}歳なら全盛期やな', ...NewsTalk.fanInsight(p, r)], _short(fav)), _fans(r, ['${p.registeredName}は当たりの匂いがする', '${_short(fav)}は外国人の見る目あるからな', 'また助っ人頼みか'], '他球団'), playerTeam: null)));
    }
    return out;
  }
}
