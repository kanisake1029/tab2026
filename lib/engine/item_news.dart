import 'dart:math';
import '../models/player.dart';
import '../models/team.dart';
import 'game_news.dart' show FanComment;
import 'news_talk.dart';

/// 大リーグの選手（比べるコメント用）：選手・球団の略称・元のNPB球団（元NPB でなければ null）
typedef MlbStar = (Player, String, String?);

/// お知らせのうち、ネットニュース風の記事にするもの（移籍・怪我・記録）
enum NewsTopic { transfer, injury, record, rumor }

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
  /// 選手の今の球団（トレード予想では、記事の球団と違うことがある）
  final Team? playerTeam;
  ItemNews(this.topic, this.date, this.text, this.headline, this.body, this.player, this.team, this.teamFans, this.otherFans, {Team? playerTeam}) : playerTeam = playerTeam ?? team;

  static String label(NewsTopic t) => switch (t) { NewsTopic.transfer => '移籍', NewsTopic.injury => '故障', NewsTopic.record => '記録', NewsTopic.rumor => '予想' };

  /// お知らせの文から、記事にする種類を決める（登録・抹消・昇格などの入れ替えは記事にしない）
  static NewsTopic? topicOf(String t) {
    bool has(List<String> ws) => ws.any(t.contains);
    if (has(['リーグ規定', 'ポストシーズン', '雨天', '提案', 'キャンプ', 'スポンサー', 'グッズ', '施設'])) return null;
    if (has(['負傷', '悪化', '全治', '故障', '離脱'])) return NewsTopic.injury;
    if (has(['トレード', 'FA', '入団', '退団', '戦力外', '獲得', '移籍', 'ドラフト', '引退', '自由契約', '新外国人', '補償', '加入'])) return NewsTopic.transfer;
    if (has(['勝目', '本塁打', '記録', '達成', '猛打', '完封', 'MVP', 'タイトル', '連続', '号'])) return NewsTopic.record;
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
    final p = player;
    final body = <String>[text.endsWith('。') ? text : '$text。'];
    if (p != null) {
      body.add('${NewsTalk.prof(p)}${team != null ? '（${_short(team)}）' : ''}。${NewsTalk.stats(p)}');
      if (topic == NewsTopic.injury && p.injuryDays > 0) body.add('復帰までは約${p.injuryDays}日かかる見込みで、${pick(['チームにとっては痛い離脱となった', '首脳陣は戦力の穴埋めを迫られる', '早期の復帰が待たれる'])}。');
      if (topic == NewsTopic.record) body.add(pick(['チームメートからも祝福を受けた。', '節目の数字に、スタンドからは大きな拍手が送られた。', 'さらなる記録の更新に期待がかかる。']));
      if (topic == NewsTopic.transfer || topic == NewsTopic.record) body.add('野球評論家の$critic氏は「${NewsTalk.insight(p, r)}」と見る。');
    }
    final name = p?.registeredName ?? '';
    final t = team == null ? '' : _short(team);
    final out = ['戦力外', '自由契約', '退団', '引退', '放出'].any(text.contains);
    final inn = ['獲得', '入団', '加入', '新外国人', 'ドラフト', '指名'].any(text.contains);
    final stay = text.contains('残留');
    List<String> fanLines(bool mine) {
      switch (topic) {
        case NewsTopic.injury:
          return mine
              ? [if (name.isNotEmpty) ...['$name早く戻ってきて…', '$nameの離脱は痛すぎる', '$nameには無理せず治してほしい', '$nameおらんと打線が組めん'], '起用しすぎやったんちゃうか', 'ここで代わりの選手が出てきてほしい', '今年はけが人が多いな…', 'トレーナー陣どうなってんの', '若手にはチャンスや']
              : [if (name.isNotEmpty) ...['$nameお大事に', '$name、また元気な姿見せてくれ'], if (t.isNotEmpty) '$tにとっては痛いな', 'これはチャンスかもしれん', '主力の離脱はきついな', 'けがだけはどうしようもない'];
        case NewsTopic.rumor:
          return const [];
        case NewsTopic.record:
          return mine
              ? [if (name.isNotEmpty) ...['$nameすごすぎる！', '$nameおめでとう！', '$nameはうちの誇りや', '$nameの記念グッズ出してくれ'], 'こういうニュースは嬉しい', 'まだまだ記録伸ばしてほしい', '現地で見たかった']
              : [if (name.isNotEmpty) ...['$nameは敵ながらあっぱれ', '$nameはやっぱりすごい', '$nameに打たれる未来しか見えん'], 'うちにも欲しい選手やな', 'おめでとうございます'];
        case NewsTopic.transfer:
          if (text.contains('外国人') && p != null) {
            // 新外国人：育成は「今後に期待」「ジャパニーズドリーム」。大リーグの一流選手と比べるコメントも
            final ik = text.contains('育成') || p.ikusei;
            String? compare;
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
            if (mine) {
              return ik
                  ? ['今後に期待', 'ジャパニーズドリームをつかみ取ってくれ', '$nameの伸びしろに賭けたい', '育成からの下克上見たい', '${p.age}歳か、まだまだこれからやな', '支配下登録される日が楽しみ', if (compare != null) compare]
                  : ['$name当たり助っ人であってくれ', '${p.origin.isEmpty ? '' : '${p.origin}出身か、'}楽しみすぎる', p.isPitcher ? '$nameローテに入ってくれ' : '$name開幕4番いけるやろ', '助っ人ガチャ、今年こそ当たれ', '日本の野球に早く慣れてくれ', if (compare != null) compare];
            }
            return ik
                ? ['育成外国人は化けると怖い', '$nameええ素材らしいな', 'こういう育成外国人が数年後に大化けする', if (compare != null) compare]
                : ['$nameは嫌な助っ人になりそう', '${t.isEmpty ? '' : '$tの'}外国人補強は当たりが多いからな', '外国人は蓋を開けるまで分からん', if (compare != null) compare];
          }
          if (stay) {
            return mine
                ? [if (name.isNotEmpty) ...['$name残ってくれてありがとう！', '$nameの残留は一番の補強', '$nameこれからもよろしく', '$name、生涯${t.isEmpty ? '' : t}でいてくれ'], 'ほっとした…', 'フロントよく引き止めた']
                : [if (name.isNotEmpty) ...['$name残留か、狙ってたのに', '$nameは移籍すると思ってた'], '大物は動かんかったな'];
          }
          if (out) {
            return mine
                ? [if (name.isNotEmpty) ...['$name今までありがとう', '$nameの放出は早すぎる気がする', '$nameには新天地で頑張ってほしい', '$nameの思い出が蘇る…'], '寂しくなるな…', 'フロントの判断を信じるしかない']
                : [if (name.isNotEmpty) ...['$nameうちで拾ってくれんかな', '$nameはまだやれると思う', '$nameを安く取れたら大きい'], '世代交代やな'];
          }
          if (inn) {
            return mine
                ? [if (name.isNotEmpty) ...['$nameようこそ！', '$nameの活躍に期待', '$nameは補強ポイントにぴったり', '$nameのユニフォーム買う'], 'いい補強や', 'フロントよう動いた']
                : [if (name.isNotEmpty) ...['$nameいい選手取られたな', '$nameは脅威になりそう'], if (t.isNotEmpty) '$tの補強が本気やな', 'うちも負けてられん'];
          }
          return mine
              ? [if (name.isNotEmpty) ...['$nameの移籍は驚いた', '$nameがどう使われるか楽しみ'], 'このトレードは吉と出るか', 'フロントの狙いが気になる']
              : ['大きな動きやな', 'このトレードはどっちが得したんやろ', if (name.isNotEmpty) '$nameは新天地で化けそう'];
      }
    }

    final positive = topic == NewsTopic.record || (topic == NewsTopic.transfer && (inn || stay));
    List<FanComment> fans(bool mine) {
      final lines = [...fanLines(mine), if (p != null) ...NewsTalk.fanInsight(p, r), ...(NewsTalk.generic(positive)..shuffle(r)).take(2)];
      final names = mine
          ? ['名無しの${t.isEmpty ? '' : t}ファン', '${t.isEmpty ? '' : t}一筋30年', 'ライトスタンドの民', '現地組', '${t.isEmpty ? '野球' : t}党']
          : ['他球団ファン', '野球好きの会社員', '外野自由席', '中立の野球ファン', '昔からの野球ファン'];
      return fanList(r, lines, names, positive: positive || !mine);
    }

    // 見出し：故障は「〇〇・名前が肉離れで離脱　全治約14日」の形に
    var head = _headline(text);
    final released = topic == NewsTopic.transfer && p != null && ['自由契約', '戦力外'].any(text.contains) && !stay;
    if (released) {
      head = '${p.registeredName}、新天地でチャンスをつかみ取れるか${t.isEmpty ? '' : '　$tを離れる'}';
      body.add(p.age <= 28
          ? 'まだ${p.age}歳と若く、伸びしろは十分。'
          : (p.age >= 34 ? 'ベテランの経験は、若手の多い球団にとって貴重な戦力になりうる。' : '働き盛りの年齢で、出番さえあれば力を発揮できる。'));
      body.add('$critic氏は「${NewsTalk.strength(p)}は魅力。${pick(['環境が変われば化ける可能性はある', '獲得に動く球団が出てもおかしくない', '独立リーグや海外も含めて、どこで再出発するか注目したい'])}」とも話す。');
    }
    if (topic == NewsTopic.injury && p != null && p.injuryName.isNotEmpty) {
      head = '${t.isEmpty ? '' : '$t・'}${p.registeredName}が${p.injuryName}で離脱${p.injuryDays > 0 ? '　全治約${p.injuryDays}日' : ''}';
    }
    return ItemNews(topic, date, text, head, body, p, team, fans(true), fans(false));
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
      key,
      mine,
      fanList(r, lines(gain, lose), nm(mine), positive: true, extra: 2),
      fanList(r, lines(other == ta ? pa : pb, other == ta ? pb : pa), nm(other), positive: true, extra: 1),
      playerTeam: keyTeam,
    );
  }
}
