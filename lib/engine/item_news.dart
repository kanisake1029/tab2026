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

  /// お知らせの文から、記事にする種類を決める（登録・抹消・昇格などの入れ替えやまとめ行は個別に扱う）
  static NewsTopic? topicOf(String t) {
    bool has(List<String> ws) => ws.any(t.contains);
    if (has(['リーグ規定', 'ポストシーズン', '雨天', '提案', 'キャンプ', 'スポンサー', 'グッズ', '施設'])) return null;
    if (has(['負傷', '悪化', '全治', '故障', '離脱'])) return NewsTopic.injury;
    if (has(['ポスティング', '海外FA', 'FA宣言', 'FA 宣言', 'FA：', 'トレード', '新外国人', '補償', '支配下登録', '育成再契約', '再契約', 'と契約', 'と育成契約', '背番号の変更'])) return NewsTopic.transfer;
    if (has(['戦力外', '自由契約', '退団', '引退', '育成契約満了'])) return NewsTopic.release;
    if (has(['ドラフト'])) return NewsTopic.draft;
    if (has(['FA', '入団', '獲得', '移籍', '加入', '育成選手'])) return NewsTopic.transfer;
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
    // 背番号変更：1人だけをピックアップせず一覧で見やすく整理する
    if (text.contains('背番号の変更')) return _numberChanges(date, text, team, r, critic);
    final p = player;
    final name = p?.registeredName ?? '';
    final t = team == null ? '' : _short(team);
    final leadText = _leadBody(text, topic, name, t);
    final body = <String>[leadText.endsWith('。') ? leadText : '$leadText。'];
    if (p != null) {
      body.add('${NewsTalk.prof(p)}${team != null ? '（${_short(team)}）' : ''}。${NewsTalk.stats(p)}');
      if (topic == NewsTopic.injury && p.injuryDays > 0) body.add('復帰までは約${p.injuryDays}日かかる見込みで、${pick(['チームにとっては痛い離脱となった', '首脳陣は戦力の穴埋めを迫られる', '早期の復帰が待たれる'])}。');
      if (topic == NewsTopic.record) body.add(pick(['チームメートからも祝福を受けた。', '節目の数字に、スタンドからは大きな拍手が送られた。', 'さらなる記録の更新に期待がかかる。']));
      if (topic == NewsTopic.transfer || topic == NewsTopic.record) body.add('野球評論家の$critic氏は「${NewsTalk.insight(p, r)}」と見る。');
    }
    final stay = text.contains('残留') || text.contains('再契約');
    final out = topic == NewsTopic.release && !stay && !['契約', 'FA宣言', 'FA 宣言'].any(text.contains);
    final inn = ['獲得', '入団', '加入', '新外国人', 'ドラフト', '指名', '契約'].any(text.contains);
    List<String> fanLines(bool mine) {
      switch (topic) {
        case NewsTopic.injury:
          return mine
              ? [if (name.isNotEmpty) ...['$name早く戻ってきて…', '$nameの離脱は痛すぎる', '$nameには無理せず治してほしい', '$nameおらんと打線が組めん'], '起用しすぎやったんちゃうか', 'ここで代わりの選手が出てきてほしい', '今年はけが人が多いな…', 'トレーナー陣どうなってんの', '若手にはチャンスや']
              : [if (name.isNotEmpty) ...['$nameお大事に', '$name、また元気な姿見せてくれ'], if (t.isNotEmpty) '$tにとっては痛いな', 'これはチャンスかもしれん', '主力の離脱はきついな', 'けがだけはどうしようもない'];
        case NewsTopic.rumor:
        case NewsTopic.game:
          return const [];
        case NewsTopic.draft:
          return mine
              ? [if (name.isNotEmpty) ...['$nameようこそ！', '$nameの将来性に期待'], '良い指名できたな', '将来の主軸候補や']
              : [if (name.isNotEmpty) '$nameいい選手取ったな', '今年のドラフトは豊作やな'];
        case NewsTopic.release:
          return mine
              ? [if (name.isNotEmpty) ...['$name今までありがとう', '$nameには新天地で頑張ってほしい'], '寂しくなるな…', 'フロントの判断を信じるしかない']
              : [if (name.isNotEmpty) ...['$nameうちで拾ってくれんかな', '$nameはまだやれると思う'], '世代交代やな'];
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
          if (text.contains('ポスティング') || text.contains('海外FA')) {
            final mlbMove = text.contains('決定') || text.contains('移籍') || text.contains('入団') || text.contains('契約');
            if (stay || text.contains('見送')) {
              return mine
                  ? [if (name.isNotEmpty) ...['$name残ってくれてありがとう！', '$nameが残留してくれるのはデカい'], '来季も全力で応援するぞ']
                  : [if (name.isNotEmpty) '$name残留か、メジャーで見たい気もしたけどな', 'NPBが盛り上がるから嬉しい'];
            }
            if (mlbMove) {
              return mine
                  ? [if (name.isNotEmpty) ...['$nameメジャーでも頑張って！', '$nameの穴は痛いが応援するしかない'], '寂しくなるな…日本から応援してるぞ', '若手はこのチャンスを掴んでくれ']
                  : [if (name.isNotEmpty) '$nameがMLBでどこまで通用するか楽しみ', '流石に日本を代表する選手やな'];
            }
            return mine
                ? [if (name.isNotEmpty) ...['$nameついにメジャー挑戦か', '$nameの夢を応援したい'], '容認するなら見返りも大事やな', '引き留めは難しいやろな']
                : [if (name.isNotEmpty) '$nameポスティングか、いくらの契約になるんやろ', 'チームとしては痛い流出になりそうやな'];
          }
          if (text.contains('FA宣言') || text.contains('FA 宣言')) {
            return mine
                ? [if (name.isNotEmpty) ...['$name宣言か…残ってほしいな', '$nameの決断を待ちたい'], '宣言残留もあるからまだ分からん', '全力で引き留めてくれフロント！']
                : [if (name.isNotEmpty) ...['$nameうちが獲りに行かんかな', '$nameは人気銘柄になりそうやな'], 'FA市場が動き出したな'];
          }
          if (text.contains('支配下登録')) {
            return mine
                ? [if (name.isNotEmpty) ...['$nameおめでとう！やっと支配下だ！', '${name}1軍で見るの楽しみにしてるぞ'], '育成からの這い上がり最高やな', '2桁背番号がかっこいい']
                : [if (name.isNotEmpty) '$nameって育成やったんや、いい選手やな', '育成が育つチームは強いな'];
          }
          if (text.contains('自由契約') && (text.contains('契約') || text.contains('獲得'))) {
            return mine
                ? [if (name.isNotEmpty) ...['$nameまだやれるはず、期待してるぞ！', '$name環境が変われば一花咲かせられる'], '良い補強になったな', 'こういう選手の復活劇を見たい']
                : [if (name.isNotEmpty) '$name拾われたか、頑張ってほしいな', '戦力外からの逆襲なるか注目や'];
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

    final positive = topic == NewsTopic.record || topic == NewsTopic.draft || (topic == NewsTopic.transfer && (inn || stay));
    List<FanComment> fans(bool mine) {
      final lines = [...fanLines(mine), if (p != null) ...NewsTalk.fanInsight(p, r), ...(NewsTalk.generic(positive)..shuffle(r)).take(2)];
      final names = mine
          ? ['名無しの${t.isEmpty ? '' : t}ファン', '${t.isEmpty ? '' : t}一筋30年', 'ライトスタンドの民', '現地組', '${t.isEmpty ? '野球' : t}党']
          : ['他球団ファン', '野球好きの会社員', '外野自由席', '中立の野球ファン', '昔からの野球ファン'];
      return fanList(r, lines, names, positive: positive || !mine);
    }

    final head = _buildHeadline(text, topic, p, t, stay, r);
    final released = topic == NewsTopic.release && p != null && ['自由契約', '戦力外'].any(text.contains) && !stay && !['契約', 'FA宣言', 'FA 宣言', '育成選手として'].any(text.contains);
    if (released) {
      body.add(p.age <= 28
          ? 'まだ${p.age}歳と若く、伸びしろは十分。'
          : (p.age >= 34 ? 'ベテランの経験は、若手の多い球団にとって貴重な戦力になりうる。' : '働き盛りの年齢で、出番さえあれば力を発揮できる。'));
      body.add('$critic氏は「${NewsTalk.strength(p)}は魅力。${pick(['環境が変われば化ける可能性はある', '獲得に動く球団が出てもおかしくない', '独立リーグや海外も含めて、どこで再出発するか注目したい'])}」とも話す。');
    }
    return ItemNews(topic, date, text, head, body, p, team, fans(true), fans(false));
  }

  /// 記事本文の1段落目（生のログ文言ではなくニュースらしいリード文に整形）
  static String _leadBody(String text, NewsTopic topic, String name, String t) {
    final teamLabel = t.isEmpty ? '' : '$tは';
    if (name.isNotEmpty) {
      if (text.contains('支配下登録')) {
        final num = RegExp(r'(?:背番号|「)(\d+)').firstMatch(text)?.group(1);
        return '$teamLabel育成選手の$nameを支配下選手として登録すると発表した${num != null ? '（新背番号は「$num」）' : ''}。';
      }
      if (text.contains('FA宣言') || text.contains('FA 宣言')) {
        final rank = RegExp(r'([A-C]ランク)').firstMatch(text)?.group(1);
        return '${t.isEmpty ? '' : '$tの'}$nameが今季取得した国内FA権の行使を表明した${rank != null ? '（$rank）' : ''}。';
      }
      if (text.contains('ポスティング') && text.contains('容認')) {
        return '$teamLabel$nameのポスティングシステムを利用したMLB移籍を容認すると発表した。';
      }
      if (text.contains('自由契約') && (text.contains('契約') || text.contains('獲得'))) {
        return '$teamLabel自由契約となっていた$nameの獲得を発表した。';
      }
    }
    return text;
  }

  /// 開幕前日の背番号変更まとめ記事（1人だけを抜き出さず、全変更選手を箇条書きで見やすく整理）
  static ItemNews _numberChanges(String date, String text, Team? team, Random r, String critic) {
    final t = team == null ? '' : _short(team);
    final k = t.isEmpty ? '' : '【$t】';
    final bodyPart = text.contains('：') ? text.split('：').last.trim() : text;
    final items = bodyPart.split('、').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final formatted = <String>[];
    String? firstPlayerName;
    String? firstNewNum;
    for (final item in items) {
      final m = RegExp(r'^(.+?)\s+(\S+)→(\S+)$').firstMatch(item);
      if (m != null) {
        firstPlayerName ??= m.group(1)!.trim();
        firstNewNum ??= m.group(3)!.trim();
        formatted.add('・${m.group(1)!.trim()}　${m.group(2)} → ${m.group(3)}');
      } else {
        formatted.add('・$item');
      }
    }
    final head = items.length <= 1 && firstPlayerName != null && firstNewNum != null
        ? '$k$firstPlayerNameの新背番号が決定！　今季から「$firstNewNum」で心機一転'
        : '$k新シーズンの背番号変更を発表！　${firstPlayerName != null ? '$firstPlayerNameら${items.length}選手が新番号に' : '計${items.length}選手が新番号で始動'}';
    final body = <String>[
      '${t.isEmpty ? '' : '$tは'}新シーズンの開幕を控え、背番号の変更を発表した。',
      '■背番号変更一覧（${items.length}名）',
      ...formatted,
      '野球評論家の$critic氏は「背番号の変更は球団の期待の表れ。新しい番号を背負う選手たちが今季どれだけチームを牽引できるか注目だ」と語る。',
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
  static String _buildHeadline(String text, NewsTopic topic, Player? p, String t, bool stay, Random r) {
    final name = p?.registeredName ?? '';
    final k = t.isEmpty ? '' : '【$t】';
    String pick(List<String> xs) => xs[r.nextInt(xs.length)];

    // 戦力外・自由契約（退団）
    final released = topic == NewsTopic.release && p != null && ['自由契約', '戦力外'].any(text.contains) && !stay && !['契約', 'FA宣言', 'FA 宣言', '育成選手として'].any(text.contains);
    if (released) {
      return '$k$name、戦力外通告で退団へ　新天地でチャンスをつかみ取れるか';
    }

    // 故障
    if (topic == NewsTopic.injury && p != null && p.injuryName.isNotEmpty) {
      return '$k$nameが${p.injuryName}で痛恨の離脱${p.injuryDays > 0 ? '　全治約${p.injuryDays}日の見込み' : ''}';
    }

    // ポスティング
    if (text.contains('ポスティング') && name.isNotEmpty) {
      if (text.contains('決定') || text.contains('入団') || text.contains('契約') || text.contains('移籍した')) {
        final mlb = RegExp(r'MLB[の・]?([^\s、。]+)').firstMatch(text)?.group(1);
        return '$k$name、ポスティングで${mlb ?? 'MLB'}へ電撃移籍！　夢の舞台で新たな挑戦';
      }
      if (text.contains('容認')) return '$k$nameのポスティング挑戦を球団が容認　今オフMLB移籍へ';
      if (text.contains('見送') || stay) return '$k$name、ポスティング見送りで残留　来季もチームの柱に';
      return '$k$nameがポスティングでのMLB挑戦を希望　球団の判断に注目';
    }

    // 海外FA
    if (text.contains('海外FA') && name.isNotEmpty) {
      if (text.contains('決定') || text.contains('移籍') || text.contains('入団') || text.contains('契約')) {
        return '$k$nameが海外FAでMLB移籍決定！　海を渡り新たなステージへ';
      }
      if (stay) return '$k$name、海外FA権行使せず残留　「このチームで優勝したい」';
      return '$k$nameが海外FA権の行使を表明　メジャー挑戦も視野に動向注目';
    }

    // 国内FA（宣言・移籍・残留・補償）
    if ((text.contains('FA宣言') || text.contains('FA 宣言')) && name.isNotEmpty) {
      final rank = RegExp(r'([A-C]ランク)').firstMatch(text)?.group(1);
      return '$k$nameが国内FA権行使を表明　${rank != null ? '$rank、' : ''}複数球団の争奪戦必至か';
    }
    if (text.contains('人的補償') && name.isNotEmpty) {
      return '${k}FA人的補償で$nameを獲得！　新天地で飛躍を期す';
    }
    if (text.contains('金銭補償')) {
      return '${k}FA補償は金銭を選択　資金面の補強へ';
    }
    if (text.contains('FA') && name.isNotEmpty) {
      if (stay) return '$k$name、FA宣言の末に残留決定！　ファン歓喜の一報';
      if (text.contains('獲得') || text.contains('移籍') || text.contains('入団') || text.contains('合意') || text.contains('契約')) {
        return '$k$nameのFA獲得が決定！　大型補強で戦力大幅アップ';
      }
    }

    // 背番号の変更（開幕前日）
    if (text.contains('背番号の変更') && name.isNotEmpty) {
      final bodyPart = text.contains('：') ? text.split('：').last : text;
      final items = bodyPart.split('、').where((s) => s.trim().isNotEmpty).toList();
      final arrow = RegExp(r'→([^\s、。]+)').firstMatch(bodyPart)?.group(1);
      if (items.length <= 1 && arrow != null) {
        return '$k$nameの新背番号が決定！　今季から「$arrow」で心機一転';
      }
      return '$k新シーズンの背番号変更を発表！　$nameら${items.length}選手が新番号に';
    }

    // 育成から支配下昇格
    if (text.contains('支配下登録') && name.isNotEmpty) {
      final num = RegExp(r'(?:背番号|「)(\d+)').firstMatch(text)?.group(1);
      return '$k育成の$nameが支配下登録！　${num != null ? '背番号「$num」を背負い1軍へ' : '念願の2桁背番号を掴み取る'}';
    }

    // 新外国人獲得
    if (text.contains('外国人') && (text.contains('契約') || text.contains('獲得') || text.contains('入団')) && name.isNotEmpty) {
      final ik = text.contains('育成') || (p?.ikusei ?? false);
      final origin = (p != null && p.origin.isNotEmpty) ? '${p.origin}出身の' : '';
      if (ik) {
        return '$k育成外国人・$nameと契約合意　$origin原石の覚醒に期待';
      }
      final role = p?.isPitcher == true
          ? '${p!.throws == 'L' ? '左腕' : '剛腕'}、先発・救援での活躍に期待'
          : '長打力に期待がかかる助っ人スラッガー';
      return '$k新外国人$nameを獲得！　$origin$role';
    }

    // 育成再契約・再契約・自由契約からの獲得
    if ((text.contains('育成再契約') || (text.contains('育成') && text.contains('再契約'))) && name.isNotEmpty) {
      return '$k$nameと育成選手として再契約　支配下復帰へ再スタート';
    }
    if (text.contains('再契約') && name.isNotEmpty) {
      return '$k$nameが再契約で残留決定　慣れ親しんだ球団で再起を誓う';
    }
    if (text.contains('自由契約') && (text.contains('契約') || text.contains('獲得')) && name.isNotEmpty) {
      return '$k自由契約の$nameを獲得！　新天地で再起を期す';
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
      key,
      mine,
      fanList(r, lines(gain, lose), nm(mine), positive: true, extra: 2),
      fanList(r, lines(other == ta ? pa : pb, other == ta ? pb : pa), nm(other), positive: true, extra: 1),
      playerTeam: keyTeam,
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
      lead,
      team,
      fanList(r, mineLines, nmMine, positive: false),
      fanList(r, otherLines, nmOther, positive: true),
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
      top.player,
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
