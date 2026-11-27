import 'dart:math';
import '../utils/schedule_generator.dart';
import '../models/player.dart';
import '../models/team.dart';
import 'game_news.dart';
import 'news_talk.dart';

/// 大リーグの選手（比べるコメント用）：選手・球団の略称・元のNPB球団（元NPB でなければ null）
typedef MlbStar = (Player, String, String?);

/// お知らせのうち、ネットニュース風の記事にするもの（確定：移籍・戦力外・ドラフト・故障・記録・試合／憶測：予想）
enum NewsTopic { transfer, release, draft, injury, record, game, rumor }

/// 移籍・退団記事の種別（否定・残留系を移籍・成立系より先に判定して見出し・本文・コメントを統一する）
enum _MoveCase {
  postingStayRejected,
  postingStayNoDeal,
  postingApproved,
  postingMoved,
  postingWish,
  overseasFaStay,
  overseasFaMoved,
  overseasFaDeclare,
  faDeclare,
  faUnsigned,
  faStay,
  faSigned,
  faCompPlayer,
  faCompPickOrMoney,
  partnerJoin,
  partnerStay,
  partnerLeave,
  ikuseiTenderSigned,
  ikuseiTenderFree,
  promote,
  otherLeagueJoin,
  foreignSign,
  reSignIkusei,
  reSignMain,
  freeAgentSign,
  retire,
  contractHoldout,
  retireRefused,
  contractExpired,
  released,
  other,
}

/// お知らせ1件から作る記事：見出し・リード・本文（選手の成績など）・ファンのコメント（自球団／他球団）
class ItemNews {
  final NewsTopic topic;
  final String date; // 「5/14」
  final String text; // お知らせの本文
  final String headline;
  final List<String> body;
  final Player? player;
  final Team? team;
  final List<FanComment> teamFans, otherFans;
  /// 選手の今の球団（トレード予想や試合記事では、もう一方の球団）
  final Team? playerTeam;
  /// 試合終了後の記事なら対象の試合
  final Match? match;
  final Team? homeTeam, awayTeam;
  ItemNews(this.topic, this.date, this.text, this.headline, this.body, this.player, this.team, this.teamFans, this.otherFans, {Team? playerTeam, this.match, this.homeTeam, this.awayTeam}) : playerTeam = playerTeam ?? team;

  bool get isConfirmed => topic != NewsTopic.rumor;

  static String label(NewsTopic t) => switch (t) {
        NewsTopic.transfer => '移籍',
        NewsTopic.release => '戦力外',
        NewsTopic.draft => 'ドラフト',
        NewsTopic.injury => '故障',
        NewsTopic.record => '記録',
        NewsTopic.game => '試合',
        NewsTopic.rumor => '予想',
      };

  static const _topicOrder = {
    NewsTopic.game: 0,
    NewsTopic.draft: 1,
    NewsTopic.transfer: 2,
    NewsTopic.release: 3,
    NewsTopic.record: 4,
    NewsTopic.injury: 5,
    NewsTopic.rumor: 6,
  };

  /// ニュース一覧の並び順を整える（新しい日付順 → 全球団時は同日内を自球団先頭＋球団のかたまり → 種別順 → 確定優先）
  static void sortFeed(List<(DateTime, ItemNews)> items, {required List<Team> leagueTeams, String? myTeamId, bool groupByTeam = true}) {
    final order = <String, int>{
      if (myTeamId != null) myTeamId: 0,
      for (var i = 0; i < leagueTeams.length; i++)
        if (leagueTeams[i].id != myTeamId) leagueTeams[i].id: i + 1,
    };
    int teamRank(ItemNews it) {
      if (myTeamId != null &&
          (it.team?.id == myTeamId || it.playerTeam?.id == myTeamId || it.homeTeam?.id == myTeamId || it.awayTeam?.id == myTeamId)) {
        return 0;
      }
      final primary = it.team ?? it.playerTeam ?? it.homeTeam ?? it.awayTeam;
      return primary == null ? 999 : (order[primary.id] ?? 998);
    }

    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    items.sort((x, y) {
      final dc = day(y.$1).compareTo(day(x.$1));
      if (dc != 0) return dc;
      if (groupByTeam) {
        final tc = teamRank(x.$2).compareTo(teamRank(y.$2));
        if (tc != 0) return tc;
      }
      final xc = (x.$2.isConfirmed ? 0 : 1).compareTo(y.$2.isConfirmed ? 0 : 1);
      if (xc != 0) return xc;
      final pc = (_topicOrder[x.$2.topic] ?? 9).compareTo(_topicOrder[y.$2.topic] ?? 9);
      if (pc != 0) return pc;
      return x.$2.headline.compareTo(y.$2.headline);
    });
  }

  /// お知らせの文から、記事にする種類を決める（登録・抹消・昇格などの入れ替えやまとめ行は個別に扱う）
  static NewsTopic? topicOf(String t) {
    bool has(List<String> ws) => ws.any(t.contains);
    if (has(['リーグ規定', 'ポストシーズン', '雨天', '提案', 'キャンプ', 'スポンサー', 'グッズ', '施設'])) return null;
    if (has(['負傷', '悪化', '全治', '故障', '離脱'])) return NewsTopic.injury;
    if (has([
      'ポスティング',
      '海外FA',
      'FA宣言',
      'FA 宣言',
      'FA：',
      'トレード',
      '新外国人',
      '補償',
      '支配下登録',
      '育成再契約',
      '再契約',
      'と契約',
      'と育成契約',
      '背番号の変更',
      '背番号の決定',
      '現役ドラフト',
      '提携枠',
    ])) {
      return NewsTopic.transfer;
    }
    if (t.contains('提携期間') || t.contains('育成テンダー')) {
      return (t.contains('自由契約') || t.contains('離れて') || t.contains('移ります')) ? NewsTopic.release : NewsTopic.transfer;
    }
    if (has(['契約満了', '戦力外', '自由契約', '退団', '引退', '育成契約満了'])) return NewsTopic.release;
    if (has(['ドラフト'])) return NewsTopic.draft;
    if (has(['FA', '入団', '獲得', '移籍', '加入', '育成選手', '残留'])) return NewsTopic.transfer;
    if (has(['勝目', '本塁打', '記録', '達成', '猛打', '完封', 'MVP', 'タイトル', '連続']) || RegExp(r'\d+号').hasMatch(t)) return NewsTopic.record;
    return null;
  }

  static String _short(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;

  static String _headline(String t) {
    var h = t;
    final i = h.indexOf('。');
    if (i > 0) h = h.substring(0, i);
    if (h.length > 34) h = '${h.substring(0, 33)}…';
    return h;
  }

  /// FanComment の並び：名前・いいね・時刻を付けて、いいねの多い順
  static List<FanComment> fanList(Random r, List<String> lines, List<String> names, {required bool positive, int extra = 0}) {
    final all = lines.toSet().toList()..shuffle(r);
    // 大リーグと比べるコメントは必ず残す
    final ordered = [...all.where((l) => l.startsWith('メジャー')), ...all.where((l) => !l.startsWith('メジャー'))];
    return [
      for (final l in ordered.take(5 + r.nextInt(3) + extra))
        FanComment(names[r.nextInt(names.length)], l, (positive ? 30 : 10) + r.nextInt(positive ? 320 : 160), '${1 + r.nextInt(58)}分前', positive),
    ]..sort((a, b) => b.likes.compareTo(a.likes));
  }

  /// [involved] トレードなどで名前が出てくる選手（今の球団つき）。2人以上なら全員について書く
  static ItemNews of(String date, String text, NewsTopic topic, {Player? player, Team? team, String? myTeamId, List<MlbStar> stars = const [], List<(Player, Team?)> involved = const []}) {
    final r = Random(Object.hash(date, text));
    String pick(List<String> xs) => xs[r.nextInt(xs.length)];
    final critic = NewsTalk.critics[r.nextInt(NewsTalk.critics.length)];
    // トレード：関わった全員を、行き先の球団ごとに取り上げる
    if (text.contains('トレード成立') && involved.length >= 2) return _trade(date, text, involved, myTeamId, r, critic);
    // 背番号変更・決定：1人だけをピックアップせず一覧で見やすく整理する
    if (text.contains('背番号の変更') || text.contains('背番号の決定')) return _numberChanges(date, text, team, r, critic);
    // 現役ドラフト：複数選手の移籍は1人ピックアップにせず一覧整理する
    if (text.contains('現役ドラフト：') && !text.contains('移籍なし')) return _activeDraft(date, text, team, r, critic);

    final p = player;
    final name = p?.registeredName ?? '';
    final t = team == null ? '' : _short(team);
    final mc = _classifyMove(text, topic, p);
    final leadText = _leadBody(text, topic, mc, name, t);
    final body = <String>[leadText.endsWith('。') ? leadText : '$leadText。'];
    if (p != null) {
      body.add('${NewsTalk.prof(p)}${team != null ? '（${_short(team)}）' : ''}。${NewsTalk.stats(p)}');
      if (topic == NewsTopic.injury && p.injuryDays > 0) {
        body.add('復帰までは約${p.injuryDays}日かかる見込みで、${pick(['チームにとっては痛い離脱となった', '首脳陣は戦力の穴埋めを迫られる', '早期の復帰が待たれる'])}。');
      }
      if (topic == NewsTopic.record) {
        body.add(pick(['チームメートからも祝福を受けた。', '節目の数字に、スタンドからは大きな拍手が送られた。', 'さらなる記録の更新に期待がかかる。']));
      }
      if (mc == _MoveCase.retire) {
        final careerNote = (p.career.hits > 0 || p.career.wins > 0) ? '球界に確かな足跡を残した功労者。' : 'チームのために全力でプレーし続けた。';
        body.add('${p.proYears}年間の現役生活に別れを告げ、$critic氏は「$careerNote次のステージでの活躍にも期待したい」と労った。');
      } else if (topic == NewsTopic.record || (topic == NewsTopic.transfer && !_needsReleaseExtra(mc))) {
        body.add('野球評論家の$critic氏は「${NewsTalk.insight(p, r)}」と見る。');
      }
    }

    List<String> fanLines(bool mine) {
      switch (topic) {
        case NewsTopic.injury:
          return mine
              ? [
                  if (name.isNotEmpty) ...['$name早く戻ってきて…', '$nameの離脱は痛すぎる', '$nameには無理せず治してほしい', '$nameおらんと戦力が落ちる'],
                  '起用しすぎやったんちゃうか',
                  'ここで代わりの選手が出てきてほしい',
                  '今年はけが人が多いな…',
                  'トレーナー陣どうなってんの',
                  '若手にはチャンスや',
                ]
              : [
                  if (name.isNotEmpty) ...['$nameお大事に', '$name、また元気な姿見せてくれ'],
                  if (t.isNotEmpty) '$tにとっては痛いな',
                  'これは他球団にとって大きいかもしれん',
                  '主力の離脱はきついな',
                  'けがだけはどうしようもない',
                ];
        case NewsTopic.rumor:
        case NewsTopic.game:
          return const [];
        case NewsTopic.draft:
          return mine
              ? [if (name.isNotEmpty) ...['$nameようこそ！', '$nameの将来性に期待', '$nameが1軍でプレーする日が待ち遠しい'], '良い指名できたな', '将来の主軸候補や', 'スカウト陣グッジョブ']
              : [if (name.isNotEmpty) '$nameいい選手取ったな', '今年のドラフトは豊作やな', '数年後が怖いな'];
        case NewsTopic.record:
          return mine
              ? [if (name.isNotEmpty) ...['$nameすごすぎる！', '$nameおめでとう！', '$nameはうちの誇りや', '$nameの記念グッズ出してくれ'], 'こういうニュースは嬉しい', 'まだまだ記録伸ばしてほしい', '現地で見たかった']
              : [if (name.isNotEmpty) ...['$nameは敵ながらあっぱれ', '$nameはやっぱりすごい', '$nameに打たれる未来しか見えん'], 'うちにも欲しい選手やな', 'おめでとうございます'];
        case NewsTopic.transfer:
        case NewsTopic.release:
          return _moveFanLines(mc, mine: mine, text: text, p: p, name: name, t: t, r: r, stars: stars);
      }
    }

    final positive = topic == NewsTopic.record || topic == NewsTopic.draft || ((topic == NewsTopic.transfer || topic == NewsTopic.release) && _isPositiveMove(mc));
    List<FanComment> fans(bool mine) {
      final useInsight = p != null && mc != _MoveCase.retire && mc != _MoveCase.contractHoldout && mc != _MoveCase.contractExpired && mc != _MoveCase.faCompPickOrMoney;
      final lines = [...fanLines(mine), if (useInsight) ...NewsTalk.fanInsight(p, r), ...(NewsTalk.generic(positive)..shuffle(r)).take(2)];
      final names = mine
          ? [
              '名無しの${t.isEmpty ? '野球' : t}ファン',
              '${t.isEmpty ? '' : t}一筋30年',
              'ライトスタンドの民',
              '現地組',
              '${t.isEmpty ? '野球' : t}党',
              'シーズンシート勢',
              '二軍ウォッチャー',
              '週末観戦組',
            ]
          : ['他球団ファン', '野球好きの会社員', '外野自由席', '中立の野球ファン', '昔からの野球ファン', 'セパ両方見る勢', 'データ好きの観戦者', '虎視眈々ファン'];
      return fanList(r, lines, names, positive: positive || !mine);
    }

    final head = _buildHeadline(text, topic, mc, p, t, r);
    if (p != null && _needsReleaseExtra(mc)) {
      body.add(p.age <= 28
          ? 'まだ${p.age}歳と若く、伸びしろは十分。'
          : (p.age >= 34 ? 'ベテランの経験は、若手の多い球団にとって貴重な戦力になりうる。' : '働き盛りの年齢で、出番さえあれば力を発揮できる。'));
      body.add('$critic氏は「${NewsTalk.strength(p)}は魅力。${pick(['環境が変われば化ける可能性はある', '獲得に動く球団が出てもおかしくない', '独立リーグや海外も含めて、どこで再出発するか注目したい'])}」とも話す。');
    }
    return ItemNews(topic, date, text, head, body, p, team, fans(true), fans(false));
  }

  static _MoveCase _classifyMove(String text, NewsTopic topic, Player? p) {
    if (topic != NewsTopic.transfer && topic != NewsTopic.release) return _MoveCase.other;
    if (text.contains('ポスティング')) {
      if (text.contains('認めなかった') || text.contains('認めませんでした')) return _MoveCase.postingStayRejected;
      if (text.contains('契約に至らず') || text.contains('見送') || text.contains('残留')) return _MoveCase.postingStayNoDeal;
      if (text.contains('容認') || text.contains('認めました')) return _MoveCase.postingApproved;
      if (text.contains('大リーグの') || text.contains('MLB') || text.contains('決定') || text.contains('入団') || text.contains('移籍した') || text.contains('へ移籍')) {
        return _MoveCase.postingMoved;
      }
      return _MoveCase.postingWish;
    }
    if (text.contains('海外FA')) {
      if (text.contains('契約に至らず') || text.contains('残留') || text.contains('見送') || text.contains('行使せず')) return _MoveCase.overseasFaStay;
      if (text.contains('大リーグの') || text.contains('MLB') || text.contains('決定') || text.contains('入団') || text.contains('へ移籍') || text.contains('契約')) {
        return _MoveCase.overseasFaMoved;
      }
      return _MoveCase.overseasFaDeclare;
    }
    if (text.contains('FA宣言') || text.contains('FA 宣言')) return _MoveCase.faDeclare;
    if (text.contains('人的補償')) return _MoveCase.faCompPlayer;
    if (text.contains('補償') && (text.contains('指名権') || text.contains('金銭'))) return _MoveCase.faCompPickOrMoney;
    if (text.contains('FA')) {
      if (text.contains('契約せず') || text.contains('自由契約')) return _MoveCase.faUnsigned;
      if (text.contains('残留')) return _MoveCase.faStay;
      if (text.contains('へ移籍') || text.contains('獲得') || text.contains('入団') || text.contains('合意') || text.contains('契約')) {
        return _MoveCase.faSigned;
      }
    }
    if (text.contains('提携枠') && text.contains('迎え')) return _MoveCase.partnerJoin;
    if (text.contains('提携期間')) {
      if (text.contains('残留')) return _MoveCase.partnerStay;
      if (text.contains('離れて') || text.contains('移ります') || text.contains('自由契約')) return _MoveCase.partnerLeave;
    }
    if (text.contains('育成テンダー')) {
      if (text.contains('自由契約')) return _MoveCase.ikuseiTenderFree;
      if (text.contains('支配下')) return _MoveCase.ikuseiTenderSigned;
    }
    if (text.contains('支配下登録')) return _MoveCase.promote;
    if (text.contains('日本球界復帰') || RegExp(r'（(?:日本球界復帰・)?[^）]+の[^）]+）と(?:育成)?契約').hasMatch(text)) {
      return _MoveCase.otherLeagueJoin;
    }
    if (text.contains('外国人') && (text.contains('契約') || text.contains('獲得') || text.contains('入団'))) {
      return _MoveCase.foreignSign;
    }
    if (text.contains('育成再契約') || (text.contains('育成') && text.contains('再契約'))) return _MoveCase.reSignIkusei;
    if (text.contains('再契約')) return _MoveCase.reSignMain;
    if (text.contains('自由契約') && (text.contains('契約') || text.contains('獲得')) && !text.contains('契約せず') && !text.contains('退団') && !text.contains('自由契約となりました') && !text.contains('自由契約になりました')) {
      return _MoveCase.freeAgentSign;
    }
    if (text.contains('引退勧告を拒み')) return _MoveCase.retireRefused;
    if (text.contains('引退')) return _MoveCase.retire;
    if (text.contains('合意できず')) return _MoveCase.contractHoldout;
    if (text.contains('契約満了') && text.contains('自由契約')) return _MoveCase.contractExpired;
    if (topic == NewsTopic.release) return _MoveCase.released;
    return _MoveCase.other;
  }

  static bool _isPositiveMove(_MoveCase mc) => switch (mc) {
        _MoveCase.postingStayRejected ||
        _MoveCase.postingStayNoDeal ||
        _MoveCase.postingApproved ||
        _MoveCase.overseasFaStay ||
        _MoveCase.faStay ||
        _MoveCase.faSigned ||
        _MoveCase.faCompPlayer ||
        _MoveCase.faCompPickOrMoney ||
        _MoveCase.partnerJoin ||
        _MoveCase.partnerStay ||
        _MoveCase.ikuseiTenderSigned ||
        _MoveCase.promote ||
        _MoveCase.otherLeagueJoin ||
        _MoveCase.foreignSign ||
        _MoveCase.reSignIkusei ||
        _MoveCase.reSignMain ||
        _MoveCase.freeAgentSign ||
        _MoveCase.retire ||
        _MoveCase.other => true,
        _MoveCase.postingMoved ||
        _MoveCase.postingWish ||
        _MoveCase.overseasFaMoved ||
        _MoveCase.overseasFaDeclare ||
        _MoveCase.faDeclare ||
        _MoveCase.faUnsigned ||
        _MoveCase.partnerLeave ||
        _MoveCase.ikuseiTenderFree ||
        _MoveCase.contractHoldout ||
        _MoveCase.retireRefused ||
        _MoveCase.contractExpired ||
        _MoveCase.released => false,
      };

  static bool _needsReleaseExtra(_MoveCase mc) => switch (mc) {
        _MoveCase.released ||
        _MoveCase.faUnsigned ||
        _MoveCase.ikuseiTenderFree ||
        _MoveCase.contractHoldout ||
        _MoveCase.retireRefused => true,
        _ => false,
      };

  static List<String> _moveFanLines(_MoveCase mc, {required bool mine, required String text, required Player? p, required String name, required String t, required Random r, required List<MlbStar> stars}) {
    final teamWord = t.isEmpty ? 'うち' : t;
    switch (mc) {
      case _MoveCase.foreignSign:
      case _MoveCase.otherLeagueJoin:
        final ik = text.contains('育成') || (p?.ikusei ?? false);
        String? compare;
        if (p != null) {
          final traits = p.isPitcher
              ? [('球速い', (Player x) => x.velocity), ('コントロールいい', (Player x) => x.control)]
              : [('打球速度速い', (Player x) => x.power), ('足速い', (Player x) => x.run), ('肩強い', (Player x) => x.arm)];
          for (final (word, get) in traits) {
            final better = [for (final s in stars) if (s.$1.isPitcher == p.isPitcher && get(s.$1) < get(p)) s];
            if (better.isEmpty) continue;
            final s = better[r.nextInt(better.length)];
            compare = 'メジャートップクラスの${s.$1.registeredName}（${s.$3 == null ? '' : '${s.$3}→'}MLB・${s.$2}）より$wordのマジ？';
            break;
          }
        }
        if (mine) {
          return ik
              ? ['今後に期待', 'ジャパニーズドリームをつかみ取ってくれ', '$nameの伸びしろに賭けたい', '育成からの下克上見たい', if (p != null) '${p.age}歳か、まだまだこれからやな', '支配下登録される日が楽しみ', '二軍からじっくり育ててほしい', if (compare != null) compare]
              : ['$name当たり助っ人であってくれ', if (p != null && p.origin.isNotEmpty) '${p.origin}出身か、楽しみすぎる', (p?.isPitcher ?? false) ? '$nameローテに入ってくれ' : '$name開幕4番いけるやろ', '助っ人ガチャ、今年こそ当たれ', '日本の野球に早く慣れてくれ', '前所属での数字も悪くないし期待できる', 'キャンプでの仕上がりが楽しみ', if (compare != null) compare];
        }
        return ik
            ? ['育成外国人は化けると怖い', '$nameええ素材らしいな', 'こういう育成外国人が数年後に大化けする', '安い年俸で夢がある補強やな', if (compare != null) compare]
            : ['$nameは嫌な助っ人になりそう', '${t.isEmpty ? '' : '$tの'}外国人補強は当たりが多いからな', '外国人は蓋を開けるまで分からん', '対戦するの厄介やな', '日本適応次第でタイトル争い絡みそう', if (compare != null) compare];
      case _MoveCase.postingStayRejected:
        return mine
            ? [
                if (name.isNotEmpty) ...['$nameには申し訳ないがチームに不可欠や', '$nameが残ってくれるなら来季も優勝狙える', '$nameの気持ちも分かるけど今は必要なんや'],
                '球団も簡単に手放せんよな',
                'まずは今年もう一年タイトル取って海外FAか',
                '残留が決まったからには全力で応援するで',
                'フロントの判断は苦渋の決断やろうな',
                '来オフまた話し合うことになるんかな',
              ]
            : [
                if (name.isNotEmpty) ...['$nameメジャー行かせてやらんの厳しいな', '$nameくらいの選手なら認めるかと思ったのに'],
                'チーム事情を考えたら認められんのも分かる',
                '残留したなら$teamWordは来年も手強いぞ',
                '本人とのしこりが残らんといいな',
                'ポスティングの可否は球団ごとに基準が違うよな',
              ];
      case _MoveCase.postingStayNoDeal:
      case _MoveCase.overseasFaStay:
        return mine
            ? [
                if (name.isNotEmpty) ...['$name残ってくれてありがとう！', '$nameの残留はデカすぎる', '$nameが戻ってきてくれるなら来季いけるで！', '$nameにはこのチームでもう一花咲かせてほしい'],
                'まさか決まらずに残留になるとは…嬉しい誤算や',
                '来季も全力で応援するぞ',
                'MLBの条件が厳しかったんかな、でも大歓迎や',
                'チームにとっても最大の補強になったな',
              ]
            : [
                if (name.isNotEmpty) ...['$name不成立で残留か、メジャーで見たかった気もする', '$nameがNPBに残るのは他球団として厄介やな'],
                '向こうの市場もシビアなんやな',
                'NPBのレベルが上がって残る選手も増えたな',
                '来季も対戦できると思えばファンとしては楽しみ',
                '年俸とか条件面で折り合わんかったんやろな',
              ];
      case _MoveCase.postingApproved:
        return mine
            ? [
                if (name.isNotEmpty) ...['$nameの夢を球団が認めてくれた！', '$name、メジャーでも暴れてきてくれ！', '$nameの穴は痛いが気持ちよく送り出したい'],
                '決断してくれた球団も立派や',
                '譲渡金と提携枠で次の補強に活かしてほしい',
                'どこからオファーが来るか楽しみやな',
                '日本での活躍は忘れんぞ！',
                '若手にとってポジションを掴む大チャンスや',
              ]
            : [
                if (name.isNotEmpty) ...['$nameついにポスティング容認か', '$nameならMLBでも十分通用するはず'],
                'どの球団と契約するんやろ',
                '$teamWordから主力が抜けるのはリーグ勢力図に響きそう',
                '譲渡金がすごい額になりそうやな',
                '契約決まるまで注目やな',
              ];
      case _MoveCase.postingMoved:
      case _MoveCase.overseasFaMoved:
        return mine
            ? [
                if (name.isNotEmpty) ...['$nameメジャーでも頑張って！', '$nameの穴は痛いが日本から応援するで', '$name、向こうでタイトル取ってくれ！', '$nameの雄姿をメジャーで見られるの楽しみ'],
                '寂しくなるな…本当にありがとう',
                '若手はこのチャンスを絶対に掴んでくれ',
                '提携枠でいい選手迎えられるといいな',
                'いつでも帰ってきてええんやで',
              ]
            : [
                if (name.isNotEmpty) ...['$nameがMLBでどこまでやるか楽しみ', '$nameは日本を代表する選手やったからな'],
                '流石の大型契約やな',
                '向こうの打線/投手陣でも通用しそう',
                'これでペナントの行方が変わってくるな',
                '日本人メジャーリーガーがまた増えて盛り上がるな',
              ];
      case _MoveCase.postingWish:
      case _MoveCase.overseasFaDeclare:
        return mine
            ? [
                if (name.isNotEmpty) ...['$nameついにメジャー挑戦か', '$nameの夢は応援したいけど寂しさもある'],
                '球団がどういう判断を下すかやな',
                'これまでの貢献を考えたら認めてあげたい気持ちもある',
                '抜けたら痛いのは間違いない',
                '見返りや来季の編成も含めて慎重に決めてほしい',
              ]
            : [
                if (name.isNotEmpty) '$nameが海を渡るんか、注目やな',
                '$teamWordとしては痛い流出になりそうやな',
                'いくらの契約になるんやろ',
                '認められるかどうかも含めて今オフの目玉やな',
              ];
      case _MoveCase.faDeclare:
        return mine
            ? [
                if (name.isNotEmpty) ...['$name宣言か…残ってほしいな', '$nameの決断を待ちたい', '$name、うちの条件で納得してくれ'],
                '宣言残留もあるからまだ分からんぞ',
                '全力で引き留めてくれフロント！',
                '提示する条件と年数が勝負やな',
                'もし抜けるなら補償のことも考えなあかんな',
              ]
            : [
                if (name.isNotEmpty) ...['$nameうちが獲りに行かんかな', '$nameは人気銘柄になりそうやな'],
                'FA市場が動き出したな',
                '複数球団の争奪戦になりそう',
                '人的補償のリストどうなるんやろ',
                '年俸がどこまで跳ね上がるか注目やな',
              ];
      case _MoveCase.faUnsigned:
        return mine
            ? [
                if (name.isNotEmpty) ...['$nameどこも獲らんかったんか…', '$name自由契約になったなら安く再契約できんかな'],
                'FA宣言したのに決まらんの厳しいな…',
                '条件面が高すぎたんやろか',
                'もう一度話してみるのも手かもしれん',
                '1月までに決まってほしいな',
              ]
            : [
                if (name.isNotEmpty) ...['$nameまだ決まってないならうち狙い目ちゃう？', '$nameが自由契約まで残るとは意外やな'],
                '補償なし・年俸も落ち着くなら動く球団あるやろ',
                'FA市場もなかなかシビアやな',
                'どこの球団が拾うか楽しみや',
              ];
      case _MoveCase.faStay:
        return mine
            ? [
                if (name.isNotEmpty) ...['$name宣言残留ありがとう！！', '$nameの残留は最大の補強や', '$name、これからもずっと応援するで！', '$name生涯$teamWord頼むぞ'],
                '胃が痛かったけどほっとした…',
                'フロントよく引き留めてくれた！',
                'これで来季の軸がブレずに済むな',
                '愛着を持って残ってくれたのが何より嬉しい',
              ]
            : [
                if (name.isNotEmpty) ...['$name結局残留か、うち来てほしかったのに', '$nameは移籍すると思ってたわ'],
                '宣言残留を許さない空気はなくなったよな',
                '大物が動かんかったな、次のターゲットに切り替えるしかない',
                '$teamWordにとっては最高のオフになったな',
              ];
      case _MoveCase.faSigned:
        return mine
            ? [
                if (name.isNotEmpty) ...['$nameよく来てくれた！！', '$nameの加入で一気に優勝候補や！', '$nameのユニフォーム買いに行くわ', '$name、打線/投手陣の核になってくれ！'],
                '大型補強に成功やな、フロント本気や！',
                'あとは人的補償がどうなるかやな…',
                '来季の開幕オーダー考えるだけでワクワクする',
                'ファン感謝デーが楽しみになってきた',
              ]
            : [
                if (name.isNotEmpty) ...['$name取られたか…痛すぎる', '$nameは向こうでも厄介な存在になりそう'],
                'マネーゲーム強いなあそこは',
                '人的補償で誰か良い若手取れたらええんやけど',
                'リーグの勢力図がまた変わるな',
                'うちも補強負けしてられんぞ',
              ];
      case _MoveCase.faCompPlayer:
      case _MoveCase.faCompPickOrMoney:
        final human = mc == _MoveCase.faCompPlayer;
        return mine
            ? human
                ? [if (name.isNotEmpty) ...['$nameようこそ！期待してるぞ！', '$nameのプロテクト漏れは見事な眼力や'], '良い若手/戦力を取れたな', 'FAの痛手を埋める補強になったぞ', '出番は絶対増えるはずや']
                : ['ドラフト指名権と金銭か、将来を見据えた良い選択や', '次のドラフトが楽しみになったな', '無理に人的補償取るよりプラスかも', 'この資金を次の補強に活かしてほしい']
            : human
                ? [if (name.isNotEmpty) ...['えっ、$nameがプロテクト外れてたんか…', '$nameには向こうでスタメン勝ち取ってほしい'], '人的補償ってほんまドキドキするよな', '惜しい選手を出したな…']
                : ['金銭・指名権なら主力は守れたってことか', 'ドラフト指名権の譲渡は珍しいな', '堅実な補償の選び方やね'];
      case _MoveCase.partnerJoin:
      case _MoveCase.partnerStay:
        return mine
            ? [if (name.isNotEmpty) ...['$nameの加入は頼もしい！', '$name、来季も力貸してくれ'], '提携枠をうまく活用できてるな', 'チームの厚みが増す補強や', 'ファンとしても応援しがいがあるわ']
            : [if (name.isNotEmpty) '$nameなかなか良い選手やん', '提携枠から良い選手見つけてくるよな', '来季マークしないといけんな'];
      case _MoveCase.partnerLeave:
        return mine
            ? [if (name.isNotEmpty) ...['$nameこれまでありがとう！', '$nameがいてくれて助かったで'], '期限付きとはいえ寂しくなるな', '次の場所でも応援してるぞ', 'また機会があれば戻ってきてほしい']
            : [if (name.isNotEmpty) '$name満了で抜けるんか', '提携期間終了やな、うちで獲れんかな', '外国人市場の動きも慌ただしくなってきた'];
      case _MoveCase.ikuseiTenderSigned:
        final stayTeam = !text.contains('移籍');
        return mine
            ? stayTeam
                ? [if (name.isNotEmpty) ...['$name支配下残留よかった！', '$nameの1軍昇格に期待してるぞ'], '他球団に取られずに済んで安心した', '育成3年からの飛躍を見せてくれ']
                : [if (name.isNotEmpty) ...['$nameようこそ！1軍の舞台で暴れてくれ！', '$nameの獲得はええ目の付け所や'], '育成テンダーからの這い上がり楽しみやな', '即戦力候補になりそう']
            : [if (name.isNotEmpty) '$nameが支配下契約を掴んだか、頑張れ！', 'こういう育成選手のチャンス増える制度ええな', '2桁背番号でどう伸びるか注目や'];
      case _MoveCase.promote:
        return mine
            ? [if (name.isNotEmpty) ...['$nameおめでとう！やっと支配下や！', '$nameを1軍で見るの楽しみにしてるぞ', '$name努力が報われたな'], '育成からの這い上がり最高や', '2桁背番号がよく似合うな', '1軍定着目指して頑張ってくれ！', 'こういう明るいニュースが一番嬉しい']
            : [if (name.isNotEmpty) '$nameって育成やったんや、いい選手やな', '育成が育つチームは強いな', 'うちも育成スカウト頑張らんとな'];
      case _MoveCase.reSignIkusei:
        return mine
            ? [if (name.isNotEmpty) ...['$name育成から這い上がってこい！', '$nameもう一回チャンスを掴んでくれ'], 'まずは怪我治して1日も早く支配下復帰や', 'チームに残ってくれて嬉しい', '3桁背番号からの再起を全力で応援するぞ']
            : [if (name.isNotEmpty) '$name育成で再契約か、応援したくなるな', '戦力外にならず再チャレンジできるのはええことや'];
      case _MoveCase.reSignMain:
        return mine
            ? [if (name.isNotEmpty) ...['$nameおかえり！再契約うれしいぞ', '$nameにはまだまだチームを支えてほしい'], '慣れ親しんだ球団で復活してくれ', '来季はキャリアハイのつもりで頼むで', 'やっぱりこのユニフォームが一番似合う']
            : [if (name.isNotEmpty) '$name元の球団と再契約か', '一番力を発揮しやすい環境やしな', '来季どこまで戻せるか注目や'];
      case _MoveCase.freeAgentSign:
        return mine
            ? [if (name.isNotEmpty) ...['$nameまだやれるはず、期待してるぞ！', '$name環境が変われば一花咲かせられる'], 'リスクも少なく良い補強になったな', 'こういう選手の復活劇を見たい', '経験豊富な戦力は貴重やで', 'キャンプからアピール頑張ってくれ']
            : [if (name.isNotEmpty) '$name拾われたか、頑張ってほしいな', '戦力外からの逆襲なるか注目や', '良い選手を安く獲ったかもしれんな'];
      case _MoveCase.retire:
        final coach = text.contains('就任');
        return mine
            ? [
                if (name.isNotEmpty) ...['$name長い間ほんまにお疲れさまでした！', '$nameのプレーは一生忘れへん', '$nameありがとう、大好きやったで！'],
                if (coach) ...['コーチとして戻ってきてくれるの嬉しい！', '経験を若手たちにしっかり伝えてほしい', '指導者としての第二の野球人生も応援してるぞ'],
                if (!coach) '引退試合とかセレモニーでしっかり送り出したい',
                '一つの時代が終わった感じがして寂しいな…',
                '本当にお疲れさまでした！',
              ]
            : [
                if (name.isNotEmpty) ...['$name引退か…敵ながらいい選手やった', '$nameとの対戦はいつも楽しみやったな'],
                if (coach) '良い指導者になりそうやな、頑張ってほしい',
                'プロの世界でやり切ったんやな、お疲れさまでした',
                '名選手がまた一人ユニフォームを脱ぐんやな…',
              ];
      case _MoveCase.contractHoldout:
        return mine
            ? [
                if (name.isNotEmpty) ...['えっ、$nameが更改決裂で退団マジか…', '$nameと折り合いつかんかったんか'],
                '金額の差が大きかったんやろか、もったいないな',
                '主力がこんな形で抜けるのはつらいわ',
                '自由契約になってもどこかがすぐ獲りそう',
                'フロントの査定基準どうなっとるんや',
              ]
            : [
                if (name.isNotEmpty) ...['$nameが自由契約に出たん！？すぐ狙いに行け！', '$nameは絶対複数球団が興味持つやろ'],
                '更改合意できずに自由契約って相当珍しいな',
                '争奪戦になりそうや',
              ];
      case _MoveCase.retireRefused:
        return mine
            ? [
                if (name.isNotEmpty) ...['$nameまだまだ現役への思いが強いんやな', '$name、他球団へ行っても応援してるで'],
                'チーム事情で引退勧告になったんやろけど寂しいな',
                '本人が納得いくまでプレーし続けてほしい',
                'どこかでユニフォーム着られるとええな',
              ]
            : [
                if (name.isNotEmpty) ...['$nameまだ老け込む年ちゃうやろ、うちで見てみたい', '$nameの現役続行への気迫はすごいな'],
                '見返すような活躍をしてほしい',
                '代打やワンポイントならまだまだ需要ありそう',
              ];
      case _MoveCase.contractExpired:
        return mine
            ? [
                if (name.isNotEmpty) ...['$name一度自由契約か、優先交渉で戻ってきてほしいな', '$nameの交渉うまくまとまりますように'],
                '年俸とか契約年数の調整中かな',
                '他球団に持っていかれる前に決着してほしい',
                '残留が決まれば安心なんやけど',
              ]
            : [
                if (name.isNotEmpty) '$nameが保留者名簿から外れたんやな',
                '交渉が決裂したらうちも獲得候補に入れたいな',
                '優先交渉権が切れるタイミングがカギやね',
              ];
      case _MoveCase.ikuseiTenderFree:
      case _MoveCase.released:
      case _MoveCase.other:
        return mine
            ? [if (name.isNotEmpty) ...['$name今までありがとう', '$nameには新天地で頑張ってほしい'], '寂しくなるな…', 'フロントの判断を信じるしかない', 'まだやれるところを見せてほしい', 'トライアウトから這い上がってこい']
            : [if (name.isNotEmpty) ...['$nameうちで拾ってくれんかな', '$nameはまだやれると思う'], '世代交代やな', '環境が変われば化けそうな選手や', '他球団の補強リストに入りそう'];
    }
  }

  /// 現役ドラフトまとめ記事（複数人の移籍で1人だけ顔を出さず一覧で整理）
  static ItemNews _activeDraft(String date, String text, Team? team, Random r, String critic) {
    final t = team == null ? '' : _short(team);
    final k = t.isEmpty ? '' : '【$t】';
    final idx = text.indexOf('：');
    final bodyPart = idx >= 0 ? text.substring(idx + 1).trim() : text;
    final items = bodyPart.split('、').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final head = items.length <= 1
        ? '${k}現役ドラフトで${items.isEmpty ? '新戦力を獲得' : items.first}'
        : '現役ドラフト開催！　計${items.length}選手が新天地へ移籍';
    final body = <String>[
      '今季の現役ドラフトが行われ、計${items.length}選手の移籍が決まった。',
      '■移籍決定一覧（${items.length}名）',
      for (final item in items) '・$item',
      '野球評論家の$critic氏は「出場機会に恵まれなかった選手にとっては大きな転機。新天地で一軍定着を掴む選手が出てくるか注目だ」と語る。',
    ];
    final mineLines = [
      '現役ドラフトええ制度やな、ワクワクするわ',
      '新天地で花開いてほしい選手ばかりやな',
      '1軍でバリバリ活躍する姿を見たい！',
      '移籍した選手たちの逆襲に期待',
      '来年この中からブレイク選手が出そう',
    ];
    final otherLines = [
      '今年の現役ドラフトも結構動いたな',
      '他球団に行った元選手も応援してるで',
      'どの球団が一番うまく補強したか見ものやな',
    ];
    return ItemNews(
      NewsTopic.transfer,
      date,
      body.first,
      head,
      body,
      null,
      team,
      fanList(r, mineLines, ['名無しの${t.isEmpty ? '野球' : t}ファン', '現地組', 'ライトスタンドの民', '野球好きの会社員'], positive: true),
      fanList(r, otherLines, ['他球団ファン', '中立の野球ファン', '昔からの野球ファン'], positive: true),
    );
  }

  /// 記事本文の1段落目（生のログ文言ではなくニュースらしいリード文に整形）
  static String _leadBody(String text, NewsTopic topic, _MoveCase mc, String name, String t) {
    final teamLabel = t.isEmpty ? '' : '$tは';
    if (name.isNotEmpty) {
      switch (mc) {
        case _MoveCase.postingStayRejected:
          return '$teamLabel$nameからのポスティング移籍の要望を認めず、来季も球団に残留することが決まった。';
        case _MoveCase.postingStayNoDeal:
          return 'ポスティングシステムでMLB移籍を目指していた${t.isEmpty ? '' : '$tの'}$nameは、交渉期限までにメジャー球団との契約合意に至らず残留が決まった。';
        case _MoveCase.postingApproved:
          return '$teamLabel$nameのポスティングシステムを利用したMLB移籍を容認すると発表した。';
        case _MoveCase.postingMoved:
          return text.replaceFirst(RegExp(r'^ポスティング：'), '').replaceFirst('得ました', '得た');
        case _MoveCase.postingWish:
          return '${t.isEmpty ? '' : '$tの'}$nameがポスティングシステムを利用したMLB挑戦を球団へ要望した。';
        case _MoveCase.overseasFaStay:
          return '海外FA権を行使してメジャー挑戦を目指していた${t.isEmpty ? '' : '$tの'}$nameは、大リーグ球団との契約に至らず残留が決まった。';
        case _MoveCase.overseasFaMoved:
          return text.contains('大リーグの')
              ? text.replaceFirst(RegExp(r'^海外FA：'), '')
              : '$teamLabel$nameが海外FA権を行使してMLBへ移籍することが決定した。';
        case _MoveCase.overseasFaDeclare:
          return '${t.isEmpty ? '' : '$tの'}$nameが海外FA権の行使を表明し、国内外の選択肢を探ることになった。';
        case _MoveCase.faDeclare:
          final rank = RegExp(r'([A-C]ランク)').firstMatch(text)?.group(1);
          return '${t.isEmpty ? '' : '$tの'}$nameが今季取得した国内FA権の行使を表明した${rank != null ? '（$rank）' : ''}。';
        case _MoveCase.faUnsigned:
          return 'FA宣言していた${t.isEmpty ? '' : '元$tの'}$nameは期限までに移籍先が決まらず、自由契約となった。';
        case _MoveCase.faStay:
          return text.startsWith('FA：') ? text.replaceFirst('FA：', '') : '$teamLabel FA宣言していた$nameの残留が決まった。';
        case _MoveCase.faSigned:
          return text.startsWith('FA：') ? text.replaceFirst('FA：', '') : text;
        case _MoveCase.faCompPlayer:
          return '$teamLabel FA移籍に伴う人的補償として$nameの獲得を発表した。';
        case _MoveCase.faCompPickOrMoney:
          return text.replaceFirst(RegExp(r'^補償：'), '');
        case _MoveCase.partnerJoin:
          return text.replaceFirst(RegExp(r'^提携枠：'), '').replaceFirst('迎えました', '迎えた');
        case _MoveCase.partnerStay:
          return text;
        case _MoveCase.partnerLeave:
          return text.replaceFirst(RegExp(r'^提携期間満了：'), '').replaceFirst('なりました', 'なった');
        case _MoveCase.ikuseiTenderSigned:
        case _MoveCase.ikuseiTenderFree:
          return text.replaceFirst(RegExp(r'^育成テンダー：'), '').replaceFirst('なりました', 'なった');
        case _MoveCase.promote:
          final num = RegExp(r'(?:背番号|「)(\d+)').firstMatch(text)?.group(1);
          return '$teamLabel育成選手の$nameを支配下選手として登録すると発表した${num != null ? '（新背番号は「$num」）' : ''}。';
        case _MoveCase.otherLeagueJoin:
          final from = RegExp(r'（(?:日本球界復帰・)?([^）]+)）').firstMatch(text)?.group(1);
          final ik = text.contains('育成') ? '育成' : '';
          if (text.contains('日本球界復帰')) {
            return '$teamLabel${from != null ? '$fromでプレーしていた' : ''}$nameと${ik}契約を結び、日本球界復帰が決定した。';
          }
          return '$teamLabel${from != null ? '$fromでプレーしていた' : ''}$nameと${ik}契約を結んだと発表した。';
        case _MoveCase.foreignSign:
          final ik = text.contains('育成');
          return '$teamLabel${ik ? '育成' : '新'}外国人選手として$nameと契約を結んだと発表した。';
        case _MoveCase.freeAgentSign:
          return '$teamLabel自由契約となっていた$nameの獲得を発表した。';
        case _MoveCase.retire:
          return text.replaceFirst('しました', 'した');
        case _MoveCase.contractHoldout:
          return '${t.isEmpty ? '' : '$tの'}$nameは契約更改交渉で球団と合意に至らず、自由契約で退団することとなった。';
        case _MoveCase.retireRefused:
          return '${t.isEmpty ? '' : '$tの'}$nameは球団からの引退勧告を拒み、他球団での現役続行を目指して退団した。';
        case _MoveCase.contractExpired:
          return '${t.isEmpty ? '' : '$tの'}$nameは今季限りで契約満了となり、自由契約選手となった（球団が優先交渉権を保持）。';
        case _MoveCase.reSignIkusei:
        case _MoveCase.reSignMain:
        case _MoveCase.released:
        case _MoveCase.other:
          break;
      }
    }
    return text;
  }

  /// 開幕前日の背番号変更・決定まとめ記事（1人だけを抜き出さず、全対象選手を箇条書きで見やすく整理）
  static ItemNews _numberChanges(String date, String text, Team? team, Random r, String critic) {
    final t = team == null ? '' : _short(team);
    final k = t.isEmpty ? '' : '【$t】';
    final bodyPart = text.contains('：') ? text.split('：').last.trim() : text;
    final items = bodyPart.split('、').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final formatted = <String>[];
    String? firstPlayerName;
    String? firstNewNum;
    var hasChange = false, hasDecide = false;
    for (final item in items) {
      final m = RegExp(r'^(.+?)\s+(\S+)→(\S+)$').firstMatch(item);
      if (m != null) {
        hasChange = true;
        firstPlayerName ??= m.group(1)!.trim();
        firstNewNum ??= m.group(3)!.trim();
        formatted.add('・${m.group(1)!.trim()}　${m.group(2)} → ${m.group(3)}');
        continue;
      }
      final dm = RegExp(r'^(.+?)\s+背番号(\S+)に決定$').firstMatch(item);
      if (dm != null) {
        hasDecide = true;
        firstPlayerName ??= dm.group(1)!.trim();
        firstNewNum ??= dm.group(2)!.trim();
        formatted.add('・${dm.group(1)!.trim()}　背番号 ${dm.group(2)}');
      } else {
        formatted.add('・$item');
      }
    }
    final kindLabel = (hasChange && hasDecide)
        ? '変更・決定'
        : (hasDecide ? '決定' : '変更');
    final head = (items.length <= 1 && firstPlayerName != null && firstNewNum != null)
        ? (hasDecide && !hasChange
            ? '$k$firstPlayerNameの背番号が「$firstNewNum」に決定！　開幕を前に新番号で始動'
            : '$k$firstPlayerNameの新背番号が決定！　今季から「$firstNewNum」で心機一転')
        : '$k新シーズンの背番号$kindLabelを発表！　${firstPlayerName != null ? '$firstPlayerNameら${items.length}選手が新番号に' : '計${items.length}選手が新番号で始動'}';
    final body = <String>[
      '${t.isEmpty ? '' : '$tは'}新シーズンの開幕を控え、背番号の$kindLabelを発表した。',
      '■背番号$kindLabel一覧（${items.length}名）',
      ...formatted,
      '野球評論家の$critic氏は「背番号の$kindLabelは球団の期待の表れ。新しい番号を背負う選手たちが今季どれだけチームを牽引できるか注目だ」と語る。',
    ];
    final mineLines = [
      if (firstPlayerName != null && firstNewNum != null) '$firstPlayerNameの「$firstNewNum」似合いそうやな',
      '新しい背番号のユニフォーム買い直さなきゃ！',
      '開幕直前に背番号が変わると気が引き締まるな',
      '主力番号を継ぐ選手たちの活躍に期待してるぞ',
      '心機一転、新背番号でキャリアハイ目指してほしい',
    ];
    final otherLines = [
      '${t.isEmpty ? '' : '$tの'}背番号シャッフルええな、期待の表れや',
      '新しい背番号を見ると開幕が近いと感じる',
      'こういう番号変更のニュース結構好き',
    ];
    return ItemNews(
      NewsTopic.transfer,
      date,
      body.first,
      head,
      body,
      null,
      team,
      fanList(r, mineLines, ['名無しの${t.isEmpty ? '' : t}ファン', '${t.isEmpty ? '' : t}党', 'ライトスタンドの民'], positive: true),
      fanList(r, otherLines, ['他球団ファン', '野球好きの会社員'], positive: true),
    );
  }

  /// ニュース種別・内容に応じたスポーツ紙風の見出し（「【球団】主見出し　副見出し」）を生成
  static String _buildHeadline(String text, NewsTopic topic, _MoveCase mc, Player? p, String t, Random r) {
    final name = p?.registeredName ?? '';
    final k = t.isEmpty ? '' : '【$t】';
    String pick(List<String> xs) => xs[r.nextInt(xs.length)];

    // 故障
    if (topic == NewsTopic.injury && p != null && p.injuryName.isNotEmpty) {
      return '$k$nameが${p.injuryName}で痛恨の離脱${p.injuryDays > 0 ? '　全治約${p.injuryDays}日の見込み' : ''}';
    }

    // 背番号の変更・決定（開幕前日フォールバック）
    if ((text.contains('背番号の変更') || text.contains('背番号の決定')) && name.isNotEmpty) {
      final bodyPart = text.contains('：') ? text.split('：').last : text;
      final items = bodyPart.split('、').where((s) => s.trim().isNotEmpty).toList();
      final arrow = RegExp(r'→([^\s、。]+)').firstMatch(bodyPart)?.group(1) ?? RegExp(r'背番号(\S+)に決定').firstMatch(bodyPart)?.group(1);
      if (items.length <= 1 && arrow != null) {
        return text.contains('背番号の決定')
            ? '$k$nameの背番号が「$arrow」に決定！　開幕を前に新番号で始動'
            : '$k$nameの新背番号が決定！　今季から「$arrow」で心機一転';
      }
      return '$k新シーズンの背番号${text.contains('背番号の決定') ? '決定' : '変更'}を発表！　$nameら${items.length}選手が新番号に';
    }

    if (mc == _MoveCase.faCompPickOrMoney) {
      return text.contains('金銭のみ') ? '${k}FA補償は金銭を選択　資金面の補強へ' : '${k}FA補償でドラフト指名権と金銭を獲得';
    }

    if ((topic == NewsTopic.transfer || topic == NewsTopic.release) && name.isNotEmpty) {
      switch (mc) {
        case _MoveCase.postingStayRejected:
          return '$k$name、球団のポスティング不承認で残留　来季もチームの主軸へ';
        case _MoveCase.postingStayNoDeal:
          return '$k$name、MLBとの契約に至らず残留決定　心機一転来季へ挑む';
        case _MoveCase.postingApproved:
          return '$k$nameのポスティング挑戦を球団が容認　今オフMLB移籍へ';
        case _MoveCase.postingMoved:
          final mlb = RegExp(r'(?:大リーグの|MLB[の・]?)([^\s、。（）]+?)(?=へ|に|と|\s|、|。|$)').firstMatch(text)?.group(1);
          return '$k$name、ポスティングで${mlb ?? 'MLB'}へ電撃移籍！　夢の舞台で新たな挑戦';
        case _MoveCase.postingWish:
          return '$k$nameがポスティングでのMLB挑戦を希望　球団の判断に注目';
        case _MoveCase.overseasFaStay:
          return '$k$name、大リーグとの契約に至らず残留　来季もチームの柱に';
        case _MoveCase.overseasFaMoved:
          return '$k$nameが海外FAでMLB移籍決定！　海を渡り新たなステージへ';
        case _MoveCase.overseasFaDeclare:
          return '$k$nameが海外FA権の行使を表明　メジャー挑戦も視野に動向注目';
        case _MoveCase.faDeclare:
          final rank = RegExp(r'([A-C]ランク)').firstMatch(text)?.group(1);
          return '$k$nameが国内FA権行使を表明　${rank != null ? '$rank、' : ''}複数球団の争奪戦必至か';
        case _MoveCase.faUnsigned:
          return '${k}FA宣言の$nameは未契約で自由契約に　今後の去就に注目';
        case _MoveCase.faStay:
          return '$k$name、FA宣言の末に残留決定！　ファン歓喜の一報';
        case _MoveCase.faSigned:
          return '$k$nameのFA獲得が決定！　大型補強で戦力大幅アップ';
        case _MoveCase.faCompPlayer:
          return '${k}FA人的補償で$nameを獲得！　新天地で飛躍を期す';
        case _MoveCase.faCompPickOrMoney:
          break;
        case _MoveCase.partnerJoin:
          return '$k提携枠で$nameが期限付き加入！　新戦力として期待';
        case _MoveCase.partnerStay:
          return '$k$name、提携期間満了後にそのまま残留！　来季も戦力に';
        case _MoveCase.partnerLeave:
          return '$k$nameが提携期間満了で退団　次のステージへ';
        case _MoveCase.ikuseiTenderSigned:
          return text.contains('移籍') ? '$k$name、育成テンダーで支配下移籍が決定！' : '$k$name、支配下契約で残留決定！　1軍舞台へ';
        case _MoveCase.ikuseiTenderFree:
          return '$k$name、育成テンダーで提示なく自由契約に';
        case _MoveCase.promote:
          final num = RegExp(r'(?:背番号|「)(\d+)').firstMatch(text)?.group(1);
          return '$k育成の$nameが支配下登録！　${num != null ? '背番号「$num」を背負い1軍へ' : '念願の2桁背番号を掴み取る'}';
        case _MoveCase.otherLeagueJoin:
          final otherClub = RegExp(r'（(?:日本球界復帰・)?([^）]+の[^）]+)）と(?:育成)?契約').firstMatch(text);
          final ik = text.contains('育成') || (p?.ikusei ?? false);
          final club = otherClub?.group(1) ?? '海外球団';
          if (text.contains('日本球界復帰')) {
            return '$k$nameが日本球界復帰！　$clubを経て${ik ? '育成から再出発' : '大型補強で合流'}';
          }
          if (ik) return '$k$clubから$nameを育成で獲得！　原石の覚醒に期待';
          return '$k$clubの$nameを獲得！　実績十分の助っ人が加入';
        case _MoveCase.foreignSign:
          final ik = text.contains('育成') || (p?.ikusei ?? false);
          final origin = (p != null && p.origin.isNotEmpty) ? '${p.origin}出身の' : '';
          if (ik) return '$k育成外国人・$nameと契約合意　$origin原石の覚醒に期待';
          final role = p?.isPitcher == true
              ? '${p!.throws == 'L' ? '左腕' : '剛腕'}、先発・救援での活躍に期待'
              : '長打力に期待がかかる助っ人スラッガー';
          return '$k新外国人$nameを獲得！　$origin$role';
        case _MoveCase.reSignIkusei:
          return '$k$nameと育成選手として再契約　支配下復帰へ再スタート';
        case _MoveCase.reSignMain:
          return '$k$nameが再契約で残留決定　慣れ親しんだ球団で再起を誓う';
        case _MoveCase.freeAgentSign:
          return '$k自由契約の$nameを獲得！　新天地で再起を期す';
        case _MoveCase.retire:
          return text.contains('就任') ? '$k$nameが現役引退、指導者へ転身　チーム支えた功労者に拍手' : '$k$nameが今季限りで現役引退　プロ生活に幕';
        case _MoveCase.contractHoldout:
          return '$k$nameが契約更改で合意せず退団へ　自由契約で新たな道';
        case _MoveCase.retireRefused:
          return '$k$nameが引退勧告を固辞して退団へ　他球団で現役続行を模索';
        case _MoveCase.contractExpired:
          return '$k$nameが契約満了で自由契約に　球団は優先交渉権を保持';
        case _MoveCase.released:
          return '$k$name、戦力外通告で退団へ　新天地でチャンスをつかみ取れるか';
        case _MoveCase.other:
          break;
      }
    }

    // 記録・表彰
    if (topic == NewsTopic.record && name.isNotEmpty) {
      if (text.contains('月間MVP')) return '$k$nameが月間MVPを受賞！　圧巻の活躍が高く評価';
      if (text.contains('交流戦')) return '$k$nameが交流戦で大暴れ！　${_headline(text)}';
      return '$k$nameが節目の記録達成！　${pick(['偉業にスタンドが沸く', 'チームメートからも祝福', 'さらなる記録更新へ'])}';
    }

    final raw = _headline(text);
    return k.isEmpty ? raw : '$k$raw';
  }

  /// トレード成立の記事：行き先の球団ごとに全員を取り上げ、評論家がどちらが得をしたかを話す
  static ItemNews _trade(String date, String text, List<(Player, Team?)> involved, String? myTeamId, Random r, String critic) {
    final byTeam = <String, (Team, List<Player>)>{};
    for (final (p, t) in involved) {
      if (t == null) continue;
      byTeam.putIfAbsent(t.id, () => (t, <Player>[])).$2.add(p);
    }
    final sides = byTeam.values.toList();
    if (sides.length < 2) {
      final (p, t) = involved.first;
      return of(date, text.replaceFirst('トレード成立', 'トレード'), NewsTopic.transfer, player: p, team: t, myTeamId: myTeamId);
    }
    // 行き先 A に入る選手（＝B から来た）と、行き先 B に入る選手
    final (ta, pa) = sides[0];
    final (tb, pb) = sides[1];
    final sa = pa.fold<int>(0, (s, p) => s + p.ovr), sb = pb.fold<int>(0, (s, p) => s + p.ovr);
    final star = [...pa, ...pb]..sort((x, y) => y.ovr.compareTo(x.ovr));
    final key = star.first;
    final keyTeam = pa.contains(key) ? ta : tb;
    final big = pa.length + pb.length >= 4;
    final head = '${_short(ta)}と${_short(tb)}が${pb.length}対${pa.length}の${big ? '大型' : ''}トレード　${key.registeredName}は${_short(keyTeam)}へ';
    final body = <String>[
      '${_short(ta)}と${_short(tb)}の間で、${pa.length + pb.length}選手が動く${big ? '大型' : ''}トレードが成立した。',
      for (final (t, ps) in [(ta, pa), (tb, pb)]) ...[
        '■${_short(t)}に加わる選手',
        for (final p in ps) '${NewsTalk.prof(p)}　${NewsTalk.stats(p)}${NewsTalk.insight(p, r)}。',
      ],
      '野球評論家の$critic氏は「${(sa - sb).abs() <= 8 ? '両球団の思惑が一致した、痛み分けのトレード' : '${_short(sa > sb ? ta : tb)}が得をした印象。ただ若手が化ければ評価は変わる'}。${_short(ta)}は${pa.map((p) => p.registeredName.split(' ').first).join('・')}、${_short(tb)}は${pb.map((p) => p.registeredName.split(' ').first).join('・')}の起用法がカギになる」と分析する。',
    ];
    final mine = myTeamId == tb.id ? tb : ta, other = mine == ta ? tb : ta;
    final gain = mine == ta ? pa : pb, lose = mine == ta ? pb : pa;
    List<String> lines(List<Player> inP, List<Player> outP) => [
          for (final p in inP) ...[
            '${p.registeredName}ようこそ！',
            '${p.registeredName}の${NewsTalk.strength(p)}に期待',
          ],
          for (final p in outP) ...[
            '${p.registeredName}今までありがとう',
            '${p.registeredName}出すのは痛い…',
          ],
          for (final p in [...inP, ...outP]) ...NewsTalk.fanInsight(p, r),
          '${inP.length}対${outP.length}か、数で勝負やな',
          'このトレードは数年後に評価が分かれそう',
          'どっちが得したか、シーズン終わってみんと分からん',
          ...(NewsTalk.generic(r.nextBool())..shuffle(r)).take(2),
        ];
    List<String> nm(Team t) => ['名無しの${_short(t)}ファン', '${_short(t)}一筋30年', '現地組', 'ライトスタンドの民'];
    return ItemNews(
      NewsTopic.transfer,
      date,
      text,
      head,
      body,
      null,
      mine,
      fanList(r, lines(gain, lose), nm(mine), positive: true, extra: 2),
      fanList(r, lines(other == ta ? pa : pb, other == ta ? pb : pa), nm(other), positive: true, extra: 1),
      playerTeam: other,
    );
  }

  /// 戦力外・育成満了の球団別まとめ記事（同日の複数人通告も全員を取り上げる）
  static ItemNews releaseBatch(String date, Team? team, List<Player> players, {String? myTeamId}) {
    final r = Random(Object.hash(date, team?.id, players.length, players.first.id));
    final critic = NewsTalk.critics[r.nextInt(NewsTalk.critics.length)];
    final t = team == null ? '' : _short(team);
    final lead = players.first;
    final head = players.length == 1
        ? '${t.isEmpty ? '' : '【$t】'}${lead.registeredName}に戦力外通告'
        : '${t.isEmpty ? '' : '【$t】'}${lead.registeredName}ら${players.length}選手に戦力外通告';
    final names = players.map((p) => '${p.registeredName}（${p.age}歳・${p.isPitcher ? '投手' : p.mainPosition}）').join('、');
    final body = <String>[
      '${t.isEmpty ? '' : '$tは'}$names${players.length > 1 ? 'の計${players.length}選手' : ''}に戦力外通告を行った。',
      if (players.length > 1) '■対象選手',
      for (final p in players) '${NewsTalk.prof(p)}　${NewsTalk.stats(p)}',
      '野球評論家の$critic氏は「${NewsTalk.strength(lead)}はまだ評価できる部分もある。${players.length > 1 ? '他球団を含め再起の場を見つけられるか注目したい' : '環境が変われば化ける可能性はある'}」と語る。',
    ];
    final mineLines = [
      for (final p in players.take(4)) '${p.registeredName}今までありがとう',
      if (players.length > 1) '${players.length}人も整理するか…',
      '寂しくなるな…',
      '新天地で頑張ってほしい',
      ...NewsTalk.fanInsight(lead, r),
    ];
    final otherLines = [
      for (final p in players.take(3)) '${p.registeredName}うちで拾ってくれんかな',
      'まだやれる選手おるやろ',
      '世代交代やな',
    ];
    final nmMine = ['名無しの${t.isEmpty ? '野球' : t}ファン', '${t.isEmpty ? '' : t}一筋30年', 'ライトスタンドの民'];
    final nmOther = ['他球団ファン', '野球好きの会社員', '中立の野球ファン'];
    return ItemNews(
      NewsTopic.release,
      date,
      body.first,
      head,
      body,
      players.length == 1 ? lead : null,
      team,
      fanList(r, mineLines, nmMine, positive: false),
      fanList(r, otherLines, nmOther, positive: true),
    );
  }

  /// 同一球団の複数選手まとめ記事（FA宣言・自由契約・支配下登録・育成/自由契約再契約）
  static ItemNews teamEventBatch(
    String date,
    Team? team,
    List<Player> players, {
    required String kind, // 'fa_declare' | 'free_release' | 'promote' | 're_sign'
    required NewsTopic topic,
    String? myTeamId,
  }) {
    final r = Random(Object.hash(date, team?.id, kind, players.length, players.first.id));
    final critic = NewsTalk.critics[r.nextInt(NewsTalk.critics.length)];
    final t = team == null ? '' : _short(team);
    final lead = players.first;
    final tag = t.isEmpty ? '' : '【$t】';
    final (action, head, positive, minePool, otherPool, comment) = switch (kind) {
      'fa_declare' => (
          'FA宣言',
          players.length == 1 ? '$tag${lead.registeredName}がFA宣言' : '$tag${lead.registeredName}ら${players.length}選手がFA宣言',
          false,
          [for (final p in players.take(4)) '${p.registeredName}には残ってほしい…', '宣言残留もあるはず', '誠意を見せて引き止めてくれ'],
          [for (final p in players.take(3)) '${p.registeredName}争奪戦になりそう', 'うちも獲りにいくべきやろ'],
          '他球団の評価を聞いた上での判断も含め、今後の交渉が注目される',
        ),
      'free_release' => (
          '自由契約',
          players.length == 1 ? '$tag${lead.registeredName}が自由契約' : '$tag${lead.registeredName}ら${players.length}選手が自由契約',
          false,
          [for (final p in players.take(4)) '${p.registeredName}どうなるんやろ', '育成再契約などの動きがあるかも'],
          [for (final p in players.take(3)) '${p.registeredName}まだやれるやろ', '調査する球団が出そう'],
          '今後、再契約や他球団からのオファーがあるか注目したい',
        ),
      'promote' => (
          '支配下登録',
          players.length == 1 ? '$tag${lead.registeredName}を支配下登録' : '$tag${lead.registeredName}ら${players.length}選手を支配下登録',
          true,
          [for (final p in players.take(4)) '${p.registeredName}支配下昇格おめでとう！', '1軍での活躍が楽しみ', '頑張って這い上がってきたな'],
          ['$tの育成からまた出てきたか', '層の厚さがすごいな'],
          '2軍・3軍でのアピールが実を結び、1軍戦力としての期待がかかる',
        ),
      _ => (
          '再契約',
          players.length == 1 ? '$tag${lead.registeredName}と再契約' : '$tag${lead.registeredName}ら${players.length}選手と再契約',
          true,
          [for (final p in players.take(4)) '${p.registeredName}また応援できる！', '来季の巻き返しに期待'],
          ['$tがしっかり戦力を残したな', '来季どう起用するか注目'],
          'チーム事情も踏まえた再契約となり、来季の奮起に期待がかかる',
        ),
    };
    final names = players.map((p) => '${p.registeredName}（${p.age}歳・${p.isPitcher ? '投手' : p.mainPosition}）').join('、');
    final body = <String>[
      '${t.isEmpty ? '' : '$tの'}$names${players.length > 1 ? 'の計${players.length}選手' : ''}について$actionが発表された。',
      if (players.length > 1) '■対象選手',
      for (final p in players) '${NewsTalk.prof(p)}　${NewsTalk.stats(p)}',
      '野球評論家の$critic氏は「${NewsTalk.strength(lead)}には光るものがある。$comment」と話す。',
    ];
    final nmMine = ['名無しの${t.isEmpty ? '野球' : t}ファン', '${t.isEmpty ? '' : t}一筋30年', 'ライトスタンドの民'];
    final nmOther = ['他球団ファン', '野球好きの会社員', '中立の野球ファン'];
    return ItemNews(
      topic,
      date,
      body.first,
      head,
      body,
      players.length == 1 ? lead : null,
      team,
      fanList(r, minePool, nmMine, positive: positive),
      fanList(r, otherPool, nmOther, positive: true),
    );
  }

  /// ドラフト指名結果の球団別まとめ記事（1人だけの羅列ではなく球団ごとに整理）
  static ItemNews draftSummary(String date, Team team, List<({String round, Player player, String school})> picks, {String? myTeamId}) {
    final r = Random(Object.hash(date, team.id, picks.length));
    final critic = NewsTalk.critics[r.nextInt(NewsTalk.critics.length)];
    final t = _short(team);
    final top = picks.first;
    final head = picks.length == 1
        ? '【$t】${top.round}で${top.player.registeredName}を指名'
        : '【$t】ドラフト${picks.length}選手を指名　1位は${top.player.registeredName}（${top.school}）';
    final body = <String>[
      '$tはドラフト会議で計${picks.length}選手の交渉権を獲得した。',
      '■指名選手一覧',
      for (final pk in picks) '${pk.round}　${pk.player.registeredName}（${pk.player.isPitcher ? '投手' : pk.player.mainPosition}・${pk.school}・${pk.player.age}歳）',
      '野球評論家の$critic氏は「目玉の${top.player.registeredName}を中心に、チームの補強ポイントに沿った指名になった」と評価する。',
    ];
    final mineLines = [
      '${top.player.registeredName}ようこそ$tへ！',
      '${picks.length}人とも1軍で見たいな',
      '今年のドラフトは楽しみな選手が多い',
      ...NewsTalk.fanInsight(top.player, r),
    ];
    final otherLines = [
      '$tのドラフトいい選手取ったな',
      '${top.player.registeredName}は将来の主力になりそう',
    ];
    return ItemNews(
      NewsTopic.draft,
      date,
      body.first,
      head,
      body,
      picks.length == 1 ? top.player : null,
      team,
      fanList(r, mineLines, ['名無しの${t}ファン', '${t}党', 'ライトスタンドの民'], positive: true),
      fanList(r, otherLines, ['他球団ファン', '野球好きの会社員'], positive: true),
    );
  }

  /// 試合終了後の記事（GameNews をニュースタブ一覧用の ItemNews に変換）
  static ItemNews fromMatch(Match m, Team home, Team away, {String? myTeamId, GameNewsContext? ctx}) {
    final g = GameNews.of(m, home, away, myTeamId: myTeamId, ctx: ctx);
    final aw = m.awayScore ?? 0, hm = m.homeScore ?? 0;
    final win = hm > aw ? home : (aw > hm ? away : (myTeamId == away.id ? away : home));
    final lose = win.id == home.id ? away : home;
    final mvpName = g.mvp?.name;
    final mvpPlayer = mvpName == null ? null : [...home.players, ...away.players].where((p) => p.registeredName == mvpName).firstOrNull;
    return ItemNews(
      NewsTopic.game,
      '${m.date.month}/${m.date.day}',
      g.lead,
      g.headline,
      [g.lead, ...g.body],
      mvpPlayer,
      win,
      g.homeFans,
      g.awayFans,
      playerTeam: lose,
      match: m,
      homeTeam: home,
      awayTeam: away,
    );
  }
}
