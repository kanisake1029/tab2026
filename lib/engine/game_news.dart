import 'dart:math';
import '../models/team.dart';
import '../utils/schedule_generator.dart';
import 'game_summary.dart';

/// 試合のMVP（1人）
class GameMvp {
  final String name;
  final bool home; // ホーム球団の選手か
  final String line; // 「4打数3安打1本塁打3打点」「7回1失点8奪三振」
  final bool pitcher;
  final int h, hr, rbi, er, outs;
  const GameMvp(this.name, this.home, this.line, this.pitcher, {this.h = 0, this.hr = 0, this.rbi = 0, this.er = 0, this.outs = 0});
}

/// 記事の材料になるチーム状況（公式戦のとき）とコーチ名。true がホーム球団
class GameNewsContext {
  final Map<bool, bool> opening; // 開幕戦
  final Map<bool, int?> rankBefore, rankAfter;
  final int leagueSize;
  final Map<bool, int> streak; // +連勝 / −連敗（この試合を含む）
  final Map<bool, int> prevStreak; // この試合の前の流れ
  final Map<bool, Map<String, String>> coaches; // 監督・打撃・投手 → 名前
  const GameNewsContext({this.opening = const {}, this.rankBefore = const {}, this.rankAfter = const {}, this.leagueSize = 6, this.streak = const {}, this.prevStreak = const {}, this.coaches = const {}});
}

/// ファンのコメント
class FanComment {
  final String user;
  final String text;
  final int likes;
  final String ago;
  final bool positive;
  const FanComment(this.user, this.text, this.likes, this.ago, this.positive);
}

/// ネットニュース風の試合記事：見出し・リード・本文（自動作文の総評）・MVPのコメント・ファンのコメント（両軍）。
///  試合の記録（ボックススコア・実況）から毎回同じ内容を作る（以前の試合にもそのまま使える）
class GameNews {
  final String headline;
  final String lead;
  final List<String> body;
  final GameMvp? mvp;
  final String? quote;
  final List<FanComment> awayFans, homeFans;
  GameNews(this.headline, this.lead, this.body, this.mvp, this.quote, this.awayFans, this.homeFans);

  static String _short(Team t) => t.shortName.isNotEmpty ? t.shortName : t.name;

  static String _ip(Object? x) {
    final t = '${x ?? '0'}'.trim();
    final m = RegExp(r'^(\d+)\.(\d)$').firstMatch(t);
    if (m == null) return '$t回';
    if (m.group(2) == '0') return '${m.group(1)}回';
    return m.group(1) == '0' ? '${m.group(2)}/3回' : '${m.group(1)}回${m.group(2)}/3';
  }

  static double _outs(Object? x) {
    final t = '${x ?? '0'}'.split('.');
    return (int.tryParse(t[0]) ?? 0) * 3.0 + (t.length > 1 ? (int.tryParse(t[1]) ?? 0) : 0);
  }

  /// 試合のMVP：勝った球団（引き分けは両軍）の打者・投手から、いちばん活躍した1人
  static GameMvp? mvpOf(Match m) {
    final box = m.boxScore;
    if (box == null || m.homeScore == null) return null;
    final hs = m.homeScore!, as = m.awayScore ?? 0;
    final sides = hs == as ? [true, false] : [hs > as];
    GameMvp? best;
    var bestScore = -1e9;
    for (final home in sides) {
      final bats = (box[home ? 'homeBatters' : 'awayBatters'] as Map?) ?? const {};
      for (final e in bats.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final h = (v['h'] ?? 0) as int, hr = (v['hr'] ?? 0) as int, rbi = (v['rbi'] ?? 0) as int, ab = (v['ab'] ?? 0) as int, bb = (v['bb'] ?? 0) as int;
        final sc = hr * 4.0 + rbi * 2.0 + h * 1.5 + bb * 0.5 - (ab - h) * 0.3;
        if (sc > bestScore) {
          bestScore = sc;
          best = GameMvp('${e.key}', home, '$ab打数$h安打${hr > 0 ? '$hr本塁打' : ''}${rbi > 0 ? '$rbi打点' : ''}', false, h: h, hr: hr, rbi: rbi);
        }
      }
      final pits = (box[home ? 'homePitcher' : 'awayPitcher'] as Map?) ?? const {};
      for (final e in pits.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final outs = _outs(v['ip']);
        final er = (v['er'] ?? 0) as int, so = (v['so'] ?? 0) as int;
        final sc = outs / 3 * 1.3 - er * 2.0 + so * 0.4 + (v['dec'] == '勝' ? 1.5 : 0) + (v['dec'] == 'S' ? 1.0 : 0) - 3.0;
        if (sc > bestScore) {
          bestScore = sc;
          best = GameMvp('${e.key}', home, '${_ip(v['ip'])}$er失点${so > 0 ? '$so奪三振' : ''}', true, er: er, outs: outs.round());
        }
      }
    }
    // オールスターなどで決めてあれば、その選手
    final fixed = box['mvp'];
    if (fixed is String && fixed.isNotEmpty) {
      final inHome = ((box['homeBatters'] as Map?)?.containsKey(fixed) ?? false) || ((box['homePitcher'] as Map?)?.containsKey(fixed) ?? false);
      if (best == null || best.name != fixed) return GameMvp(fixed, inHome, best?.name == fixed ? best!.line : '', false);
    }
    return best;
  }

  /// 見出し（約6割）：「東新 河野 玲央が劇的満塁弾でサヨナラ勝ち　ソフトクリームは痛恨の5連敗」の形。MVP が勝った球団の選手のとき
  static String _mvpHeadline(Match m, Team home, Team away, String base, GameMvp? mvp, GameNewsContext? c, Random r) {
    final hs = m.homeScore ?? 0, as = m.awayScore ?? 0;
    if (mvp == null || hs == as || mvp.home != (hs > as) || r.nextDouble() >= 0.6) return base;
    final win = mvp.home ? home : away, lose = mvp.home ? away : home;
    final walkOff = (m.playByPlay ?? const []).any((l) => l.contains('サヨナラ'));
    // 勝ち方（自動作文の見出しの「、」と「（」の間）
    var kind = '勝利';
    final i = base.indexOf('、'), j = base.lastIndexOf('（');
    if (i > 0 && j > i) kind = base.substring(i + 1, j).replaceAll('延長', '延長戦の末').trim();
    if (kind.endsWith('を制す')) kind = kind.replaceAll('を制す', 'を制した');
    String feat;
    if (mvp.pitcher) {
      final inn = mvp.outs ~/ 3;
      feat = mvp.er == 0 && mvp.outs >= 27 ? '完封' : (inn >= 7 ? '$inn回${mvp.er}失点の快投' : '好投');
    } else {
      final hrs = GameSummary.homeRuns(m, home, away).where((h) => h.$2 == mvp.name).toList();
      final grand = hrs.any((h) => h.$3.contains('満塁'));
      if (mvp.hr >= 2) {
        feat = '${mvp.hr}発';
      } else if (mvp.hr == 1) {
        feat = '${walkOff ? '劇的' : '決勝'}${grand ? '満塁弾' : (hrs.isNotEmpty && hrs.first.$3.contains('ソロ') ? 'ソロ' : 'アーチ')}';
      } else if (mvp.rbi >= 3) {
        feat = '${mvp.rbi}打点の活躍';
      } else if (mvp.h >= 3) {
        feat = '猛打賞';
      } else {
        feat = walkOff ? 'サヨナラ打' : '勝負強い打撃';
      }
    }
    // 負けた側の状況
    String tail = '';
    final ls = c?.streak[mvp.home ? false : true] ?? 0, lp = c?.prevStreak[mvp.home ? false : true] ?? 0;
    final lr = c?.rankAfter[mvp.home ? false : true], lb = c?.rankBefore[mvp.home ? false : true];
    if (ls <= -3) {
      tail = '${_short(lose)}は痛恨の${-ls}連敗';
    } else if (lr != null && lr == c?.leagueSize && lb != lr) {
      tail = '${_short(lose)}は最下位転落';
    } else if (lp >= 3) {
      tail = '${_short(lose)}は連勝が$lpでストップ';
    }
    final head = feat == '完封' ? '${_short(win)} ${mvp.name}が完封勝利' : '${_short(win)} ${mvp.name}が$featで$kind';
    return tail.isEmpty ? head : '$head　$tail';
  }

  /// リードに足すチーム状況（首位・最下位・連勝・連敗・開幕戦）
  static String _situation(GameNewsContext? c, bool homeWin, Team win, Team lose) {
    if (c == null) return '';
    final out = <String>[];
    final w = homeWin, l = !homeWin;
    if (c.opening[w] == true) out.add('${_short(win)}は開幕戦を白星で飾った。');
    if (c.rankAfter[w] == 1) out.add(c.rankBefore[w] == 1 ? '${_short(win)}は首位をキープ。' : '${_short(win)}は首位に浮上した。');
    if ((c.streak[w] ?? 0) >= 3) out.add('${_short(win)}は${c.streak[w]}連勝。');
    if ((c.prevStreak[w] ?? 0) <= -2) out.add('${_short(win)}は連敗を${-(c.prevStreak[w] ?? 0)}で止めた。');
    if ((c.prevStreak[l] ?? 0) >= 2) out.add('${_short(lose)}の連勝は${c.prevStreak[l]}で止まった。');
    if (c.rankAfter[l] == c.leagueSize && c.rankBefore[l] != c.leagueSize) out.add('敗れた${_short(lose)}は最下位に転落した。');
    if ((c.streak[l] ?? 0) <= -3) out.add('${_short(lose)}は${-(c.streak[l] ?? 0)}連敗となった。');
    return out.join();
  }

  static GameNews of(Match m, Team home, Team away, {String? myTeamId, GameNewsContext? ctx}) {
    final r = Random(Object.hash(m.date.millisecondsSinceEpoch, m.homeTeamId, m.awayTeamId, 7));
    String pick(List<String> xs) => xs[r.nextInt(xs.length)];
    final hs = m.homeScore ?? 0, as = m.awayScore ?? 0;
    final draw = hs == as, homeWin = hs > as;
    final win = homeWin ? home : away, lose = homeWin ? away : home;
    final full = GameSummary.generate(m, home, away);
    final parts = full.split('\n').where((x) => x.trim().isNotEmpty).toList();
    final headline = parts.isEmpty ? '${_short(away)} $as−$hs ${_short(home)}' : parts.first;
    final body = parts.length > 1 ? parts.sublist(1) : <String>[];
    final mvp = mvpOf(m);
    final mvpTeam = mvp == null ? null : (mvp.home ? home : away);
    final headline2 = _mvpHeadline(m, home, away, headline, mvp, ctx, r);
    final lead = draw
        ? '${m.date.month}月${m.date.day}日の${_short(away)}−${_short(home)}戦は$as−$hsの引き分けに終わった。'
        : '${_short(win)}が${max(hs, as)}−${min(hs, as)}で${_short(lose)}を下した。${mvp != null ? 'この日の主役は${_short(mvpTeam!)}の${mvp.name}${mvp.line.isEmpty ? '' : '（${mvp.line}）'}。' : ''}${_situation(ctx, homeWin, win, lose)}';
    String? quote;
    if (mvp != null) {
      quote = mvp.pitcher
          ? pick(['「キャッチャーのリードを信じて投げました。${draw ? '勝ちきれなかったのは悔しいです' : 'チームが勝ててよかったです'}」', '「先頭打者を出さないことだけ考えていました。次も同じように投げたいです」', '「調子はそこまで良くなかったけど、守備に助けられました」'])
          : pick(['「打ったのは${pick(['真っすぐ', '変化球', '甘く入った球'])}。必死に食らいつきました」', '「チャンスで回ってきたので、何とかしたかった。最高の結果になりました」', '「ファンの声援が力になりました。明日も打ちます」']);
    }
    // 名前の材料
    final box = m.boxScore ?? const {};
    String? decOf(bool homeSide, String d) {
      final ps = (box[homeSide ? 'homePitcher' : 'awayPitcher'] as Map?) ?? const {};
      for (final e in ps.entries) {
        if (e.value is Map && (e.value as Map)['dec'] == d) return '${e.key}';
      }
      return null;
    }

    String? starterOf(bool homeSide) {
      final ps = (box[homeSide ? 'homePitcher' : 'awayPitcher'] as Map?) ?? const {};
      return ps.isEmpty ? null : '${ps.keys.first}';
    }

    String? heroOf(bool homeSide) {
      final bs = (box[homeSide ? 'homeBatters' : 'awayBatters'] as Map?) ?? const {};
      String? best;
      var sc = 0.0;
      for (final e in bs.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final s = ((v['hr'] ?? 0) as int) * 3.0 + ((v['rbi'] ?? 0) as int) * 1.5 + ((v['h'] ?? 0) as int);
        if (s > sc) {
          sc = s;
          best = '${e.key}';
        }
      }
      return best;
    }

    final hrs = GameSummary.homeRuns(m, home, away);
    List<FanComment> fans(bool homeSide) {
      final t = homeSide ? home : away;
      final won = !draw && homeSide == homeWin;
      final lost = !draw && !won;
      final rr = Random(Object.hash(m.date.millisecondsSinceEpoch, t.id, 31));
      String p(List<String> xs) => xs[rr.nextInt(xs.length)];
      final my = homeSide ? hs : as, opp = homeSide ? as : hs;
      final hero = heroOf(homeSide), sp = starterOf(homeSide), wp = decOf(homeSide, '勝'), sv = decOf(homeSide, 'S'), lp = decOf(homeSide, '敗');
      final myHr = hrs.where((x) => x.$1 == homeSide).map((x) => x.$2).toList();
      // 投手の中身（先発の回と自責、救援の失点）
      final pRows = ((box[homeSide ? 'homePitcher' : 'awayPitcher'] as Map?) ?? const {}).entries.where((e) => e.value is Map).toList();
      final spRow = pRows.isEmpty ? null : pRows.first.value as Map;
      final spOuts = spRow == null ? 0.0 : _outs(spRow['ip']);
      final spEr = spRow == null ? 0 : (spRow['er'] ?? 0) as int;
      final relieverRuns = pRows.skip(1).fold<int>(0, (a, e) => a + ((e.value as Map)['er'] ?? 0) as int);
      final usedRelief = pRows.length > 1;
      final lpIsRelief = lp != null && pRows.isNotEmpty && pRows.first.key != lp;
      final c = ctx;
      final rankA = c?.rankAfter[homeSide], rankB = c?.rankBefore[homeSide];
      final st = c?.streak[homeSide] ?? 0;
      final prev = c?.prevStreak[homeSide] ?? 0;
      final coach = c?.coaches[homeSide] ?? const <String, String>{};
      final mgr = coach['監督'], batC = coach['打撃'], pitC = coach['投手'];
      final good = <String>[
        if (mvp != null && mvp.home == homeSide) ...['${mvp.name}最高！今日のヒーロー', '${mvp.name}やっぱりこの人よ', '${mvp.name}にお立ち台は確定やな'],
        if (myHr.isNotEmpty) ...['${myHr.first}のホームラン気持ちよすぎた', '${myHr.first}の一発で球場の空気変わったな'],
        if (wp != null) '$wpナイスピッチ！',
        if (sv != null) '$svが締めてくれると安心感ある',
        if (hero != null) '$heroの当たりが戻ってきてる',
        if (my >= 5) '打線がつながると強いわ',
        if (my >= 5) '$my点も取れば勝てるわな',
        if (won && spEr <= 2 && spOuts >= 18) '${sp ?? '先発'}が試合をつくってくれた',
        if (won && usedRelief && relieverRuns == 0) '中継ぎ陣が完璧やった',
        if (won && my <= 2) '少ない点を守り切った投手陣に感謝',
        if (won) ...['この勢いで連勝いこう', '今日はビールがうまい', 'やっぱり${_short(t)}が一番や'],
        if (draw) '負けなかっただけ良しとしよう',
        // チーム状況
        if (c?.opening[homeSide] == true && won) '開幕戦勝利！幸先いいスタートや',
        if (won && rankA == 1 && rankB != 1) 'ついに首位浮上きた！！',
        if (won && rankA == 1 && rankB == 1) '首位がっちりキープ',
        if (st >= 3) '$st連勝！止まらんわ',
        if (st >= 5) 'この連勝、どこまで伸びるんや',
        if (st == 2) '連勝！この流れ続けてくれ',
        if (won && prev <= -2) '${-prev}連敗でストップ！やっと勝てた',
        if (won && prev <= -4) '長いトンネルやった…ほんまに嬉しい',
        if (lost && prev >= 2) '$prev連勝もここまでか。また明日から',
        if (draw && prev <= -2) '連敗は止めたけど勝ちたかった',
        // コーチ
        if (won && mgr != null) '$mgr監督の采配ズバリやったな',
        if (won && batC != null && my >= 5) '${batC}コーチの指導が実ってきてる',
        if (won && pitC != null && usedRelief && relieverRuns == 0) '${pitC}コーチの継投完璧',
      ];
      final bad = <String>[
        if (lp != null) ...['$lp何してんの…', '$lpは一回二軍で調整した方がいい'],
        if (sp != null && lost && (spOuts < 15 || (spEr >= 4 && spOuts < 18))) '$spもう少し粘ってほしかった',
        if (myHr.isEmpty && lost && my <= 1) '打線が完全に沈黙…',
        if (lost && my <= 3) '$my点じゃ勝てんよ',
        if (lost && opp >= 6) '$opp点も取られたら無理',
        if (lost) ...['チャンスで一本が出ないのが今年の${_short(t)}', 'また負けた。切り替えられん'],
        if (won && relieverRuns >= 2) '勝ったけど中継ぎがヒヤヒヤした',
        if (won && (my - opp).abs() <= 1) 'もっと点差つけて楽に勝ってほしい',
        if (draw) ...['勝ちきれんかったな…', '引き分けは実質負け'],
        // チーム状況
        if (c?.opening[homeSide] == true && lost) '開幕戦から負けるとか先が思いやられる',
        if (lost && rankA != null && rankA == c?.leagueSize && rankB != rankA) '最下位転落…どうなってんの',
        if (lost && rankA != null && rankA == c?.leagueSize && rankB == rankA) '最下位から抜け出せん',
        if (lost && rankB == 1 && rankA != 1) '首位陥落か…',
        if (st <= -3) '${-st}連敗…もう見てられん',
        if (st <= -5) '${-st}連敗はさすがにやばい。何か手を打って',
        if (st == -2) '連敗か…嫌な流れ',
        if (lost && prev >= 3) '連勝止まって一気に崩れそうで怖い',
        if (won && prev >= 2 && st >= 3) '勝ち方がいい。今の${_short(t)}は強い',
        // コーチ
        if (lost && mgr != null) '$mgr監督の采配が謎すぎる',
        if (lost && pitC != null && (lpIsRelief || spEr >= 4)) '${pitC}コーチ、継投が遅すぎる',
        if (lost && batC != null && my <= 2) '${batC}コーチ、この打線何とかして',
      ];
      final n = 7 + rr.nextInt(4);
      final posRate = won ? 0.78 : (lost ? 0.25 : 0.5);
      final names = ['名無しの${_short(t)}ファン', '${_short(t)}一筋30年', 'ライトスタンドの民', '外野自由席', '球場のビール売り', '${_short(t)}党', '昔からのファン', 'にわか応援団', '野球好きの会社員', '現地組'];
      final out = <FanComment>[];
      final used = <String>{};
      for (var i = 0; i < n; i++) {
        final positive = rr.nextDouble() < posRate;
        final pool = (positive ? good : bad).where((x) => !used.contains(x)).toList();
        if (pool.isEmpty) continue;
        final text = p(pool);
        used.add(text);
        final likes = (positive == won ? 40 : 5) + rr.nextInt(positive == won ? 400 : 120);
        out.add(FanComment(p(names), text, likes, '${1 + rr.nextInt(58)}分前', positive));
      }
      out.sort((a, b) => b.likes.compareTo(a.likes));
      return out;
    }

    return GameNews(headline2, lead, body, mvp, quote, fans(false), fans(true));
  }
}
