import 'dart:io';
import 'dart:math';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/awards.dart';
import 'package:npb_pennant_app/engine/batting_splits.dart';
import 'package:npb_pennant_app/engine/career_path.dart';
import 'package:npb_pennant_app/engine/condition_engine.dart';
import 'package:npb_pennant_app/engine/foreign_engine.dart';
import 'package:npb_pennant_app/engine/game_news.dart';
import 'package:npb_pennant_app/engine/growth_curve.dart';
import 'package:npb_pennant_app/engine/item_news.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/engine/other_league_engine.dart';
import 'package:npb_pennant_app/engine/roster_engine.dart';
import 'package:npb_pennant_app/engine/trade_rumor.dart';
import 'package:npb_pennant_app/engine/transfer_engine.dart';
import 'package:npb_pennant_app/models/team.dart';
import 'package:npb_pennant_app/utils/schedule_generator.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/screens/awards_screen.dart';
import 'package:npb_pennant_app/screens/number_board_screen.dart';
import 'package:npb_pennant_app/screens/office_screen.dart';
import 'package:npb_pennant_app/screens/order_tabs/lineup_tab.dart';
import 'package:npb_pennant_app/screens/order_tabs/pitcher_tab.dart';
import 'package:npb_pennant_app/screens/reinforce_screens.dart';
import 'package:npb_pennant_app/screens/title_race.dart';
import 'package:npb_pennant_app/utils/app_theme.dart';
import 'package:npb_pennant_app/widgets/player_detail_dialog.dart';
import 'package:npb_pennant_app/widgets/scout_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('① テーマのフォントが BIZUDPGothic である', () {
    final t = AppTheme.modernLight;
    final c = AppTheme.compact(t);
    expect(t.textTheme.bodyMedium?.fontFamily, 'BIZUDPGothic');
    expect(t.appBarTheme.titleTextStyle?.fontFamily, 'BIZUDPGothic');
    expect(c.appBarTheme.titleTextStyle?.fontFamily, 'BIZUDPGothic');
  });

  testWidgets('② 別リーグ成績は寸評欄ではなく成績表に出る／③ 球団経歴は年表へ移籍経緯付きで載る', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    final t0 = app.teams[0], t1 = app.teams[1];
    final p = t0.players.firstWhere((x) => !x.isPitcher);
    p.abroad = ['2025　3A　110試合 打率.295 18本 65打点 OPS.860'];
    p.moves.add('2026年12月9日 現役ドラフトで${t1.shortName}へ（←${t0.shortName}）');
    final tl = await app.playerTimeline(p);
    expect(tl.any((e) => e.$2.contains('現役ドラフト')), isTrue);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.modernLight,
      home: Scaffold(body: SingleChildScrollView(child: ScoutReport(player: p, appState: app, onClose: () {}))),
    ));
    await tester.pumpAndSettle();

    // 寸評欄に「海外での成績」は出ない
    expect(find.textContaining('海外での成績'), findsNothing);

    // 経歴タブの成績表に 3A* の成績が出る（2025以前は憶測のため * とグレー）
    await tester.tap(find.text('経歴').first);
    await tester.pumpAndSettle();
    expect(find.text('3A*'), findsOneWidget);
    expect(find.text('.295'), findsOneWidget);

    // 年表タブに「移籍の歩み」は別枠で出ず、年表内に現役ドラフトが出る
    await tester.tap(find.text('年表'));
    await tester.pumpAndSettle();
    expect(find.text('移籍の歩み'), findsNothing);
    expect(find.textContaining('現役ドラフト'), findsOneWidget);
  });

  test('④ オフシーズン（11/1〜1/31）の背番号変更も予約となり、一律で開幕前日に反映される', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final t = app.teams.first;
    final p = t.players.firstWhere((x) => !x.ikusei);
    final oldNum = p.uniformNumber;
    final newNum = [for (var n = 1; n <= 99; n++) if (!t.players.any((x) => x.uniformNumber == n)) n].first;

    app.myTeamId = t.id;
    app.currentDate = DateTime(2026, 11, 15);
    app.chron.add({
      'd': '2026-11-10',
      'team': t.id,
      'k': 'join',
      't': '内野手 ${p.registeredName}(${p.age})が入団。背番号は${p.uniformText}。',
      'pid': p.id,
      'pt': '${t.name}に入団。背番号${p.uniformText}。',
    });

    final err = app.setNumber(t, p, newNum);
    expect(err, isNull);
    expect(p.uniformNumber, oldNum);
    expect(p.nextNumber, newNum);
    expect(app.chron.any((c) => c['pid'] == p.id && c['k'] == 'number'), isFalse);

    app.applyNextNumbers(DateTime(2027, 3, 25));
    expect(p.uniformNumber, newNum);
    expect(p.nextNumber, isNull);
    final tl = await app.playerTimeline(p);
    expect(tl.any((e) => e.$2.contains('背番号を${uniformLabel(oldNum)}から${uniformLabel(newNum)}に変更。')), isTrue);
    expect(tl.any((e) => e.$2.contains('背番号${uniformLabel(oldNum)}。')), isTrue);
  });

  test('④-2 シーズン途中の入団から1か月以内は即変更・入団時背番号書換、期間外と一括入替は開幕前日反映', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final t = app.teams.first;
    app.myTeamId = t.id;
    final p = t.players.firstWhere((x) => !x.ikusei);
    final q = t.players.firstWhere((x) => !x.ikusei && x.id != p.id);
    final n14 = [for (var n = 14; n <= 99; n++) if (!t.players.any((x) => x.uniformNumber == n)) n].first;
    final n53 = [for (var n = 53; n <= 99; n++) if (n != n14 && !t.players.any((x) => x.uniformNumber == n)) n].first;
    p.uniformNumber = n14;

    final joinDate = DateTime(2026, 4, 1);
    app.currentDate = DateTime(2026, 4, 15);
    app.markNumberFree(p, joinDate);
    expect(p.numberFreeUntil, '2026-05-01');
    expect(app.numberFreeNow(p), isTrue);
    app.chron.add({
      'd': '2026-04-01',
      'team': t.id,
      'k': 'join',
      't': '外野手 ${p.registeredName}(${p.age})が来日して入団。背番号は${uniformLabel(n14)}。',
      'pid': p.id,
      'pt': '来日して${t.name}に入団。背番号${uniformLabel(n14)}。',
    });

    // 1か月以内（4/15）は即座に空き番号へ変更され、入団時の背番号から書き換わる
    final err = app.setNumber(t, p, n53);
    expect(err, isNull);
    expect(p.uniformNumber, n53);
    expect(p.nextNumber, isNull);
    expect(app.chron.any((c) => c['pid'] == p.id && c['k'] == 'number'), isFalse);

    final tlGrace = await app.playerTimeline(p);
    expect(tlGrace.any((e) => e.$2.contains('来日して${t.name}に入団。背番号${uniformLabel(n53)}。')), isTrue);
    expect(tlGrace.any((e) => e.$2.contains('背番号${uniformLabel(n14)}')), isFalse);
    final histGrace = await app.numberHistory(t);
    expect(histGrace[n14]?.any((e) => e.$2 == p.registeredName) ?? false, isFalse);
    expect(histGrace[n53]?.any((e) => e.$1 == '2026-04-01' && e.$2 == p.registeredName), isTrue);

    // 1か月経過後（5/15）およびオフ期間の一括入替は予約となり、開幕前日に反映される
    app.currentDate = DateTime(2026, 5, 15);
    expect(app.numberFreeNow(p), isFalse);
    expect(app.setNumber(t, p, n14), isNull);
    expect(p.uniformNumber, n53);
    expect(p.nextNumber, n14);

    app.currentDate = DateTime(2026, 11, 15);
    final qOld = q.uniformNumber;
    final bulkErr = app.setNumbersBulk(t, {p.id: qOld, q.id: n53});
    expect(bulkErr, isNull);
    expect(p.uniformNumber, n53);
    expect(q.uniformNumber, qOld);
    expect(p.nextNumber, qOld);
    expect(q.nextNumber, n53);

    app.applyNextNumbers(DateTime(2027, 3, 25));
    expect(p.uniformNumber, qOld);
    expect(q.uniformNumber, n53);
    expect(p.nextNumber, isNull);
    expect(q.nextNumber, isNull);

    final tl = await app.playerTimeline(p);
    expect(tl.any((e) => e.$2.contains('来日して${t.name}に入団。背番号${uniformLabel(n53)}。')), isTrue);
    expect(tl.any((e) => e.$2.contains('背番号を${uniformLabel(n53)}から${uniformLabel(qOld)}に変更。')), isTrue);
  });

  testWidgets('支配下登録: 2027/6/12・支配下65人で選手詳細ダイアログから支配下登録できる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    app.myTeamId = app.teams.first.id;
    app.startYear = 2027;
    app.currentDate = DateTime(2027, 6, 12);
    app.seasonFinished = false;
    final my = app.myTeam!;
    final sh = my.players.where((p) => !p.ikusei).toList();
    while (sh.length > 65) {
      my.players.remove(sh.removeLast());
    }
    final ik = my.players.firstWhere((p) => p.ikusei, orElse: () {
      final p = my.players.last;
      p.ikusei = true;
      p.uniformNumber = 101;
      return p;
    });
    expect(RosterEngine.shihaikaCount(my), lessThanOrEqualTo(65));
    expect(ik.ikusei, isTrue);

    await tester.binding.setSurfaceSize(const Size(411, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showPlayerDetail(ctx, app, ik),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('支配下登録'), findsOneWidget);
    await tester.tap(find.text('支配下登録'));
    await tester.pumpAndSettle();

    expect(find.text('登録する'), findsOneWidget);
    await tester.tap(find.text('登録する'));
    await tester.pumpAndSettle();

    expect(ik.ikusei, isFalse);
    expect(ik.uniformNumber, lessThan(100));
  });

  test('海外球団3文字略称・外国人経歴の時系列整理・コース得手不得手', () {
    expect(OtherLeagueEngine.abbr3('ロサンゼルス・ドジャース'), 'LAD');
    expect(OtherLeagueEngine.abbr3('ソウル'), 'SEO');

    final f = Player(id: 'foreign_test', lastName: 'テスト', isPitcher: false, nationality: '海外', origin: 'アメリカ', mainPos: '外野手', age: 27, abroad: [
      '2024　3A・OKC　100試合 打率.290 15本 50打点 OPS.850',
      '2023　MLB・LAD　30試合 打率.210 2本 10打点 OPS.620',
      '2023　3A・OKC　80試合 打率.305 14本 48打点 OPS.900',
      '2022　3A・OKC　115試合 打率.280 18本 65打点 OPS.830',
    ]);
    final cp = CareerPath.of(f);
    expect(cp, ['出身　アメリカ', '3A・OKC（2022）*', 'MLB・LAD／3A・OKC（2023）*', '3A・OKC（2024）*']);

    // コース相性は -1.0〜1.0 に収まり、内外角/高低で符号が反転する
    final b = Player(id: 'batter_course_1', lastName: '打者', isPitcher: false, bats: 'R', mainPos: '一塁手');
    final a1 = BattingSplits.courseAffinity(b, -0.8, 0.8, 'R');
    final a2 = BattingSplits.courseAffinity(b, 0.8, -0.8, 'R');
    expect(a1, inInclusiveRange(-1.0, 1.0));
    expect(a2, inInclusiveRange(-1.0, 1.0));
    expect(a1, closeTo(-a2, 1e-9));
  });

  test('試合数118/143/156の交流戦・同一リーグ試合数内訳', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final leagueTeams = app.teams.where((t) => t.league == 'CL' || t.league == 'PL').toList();
    for (final total in [118, 143, 156]) {
      final ms = ScheduleGenerator.generateSeasonSchedule(2026, leagueTeams, games: total);
      final t0 = leagueTeams.first;
      final lgGames = ms.where((m) => m.matchType == 'LEAGUE' && (m.homeTeamId == t0.id || m.awayTeamId == t0.id)).length;
      final ilGames = ms.where((m) => m.matchType == 'INTERLEAGUE' && (m.homeTeamId == t0.id || m.awayTeamId == t0.id)).length;
      expect(lgGames + ilGames, total);
      if (total == 118) {
        expect(lgGames, 100);
        expect(ilGames, 18);
      } else if (total == 143) {
        expect(lgGames, 125);
        expect(ilGames, 18);
      } else if (total == 156) {
        expect(lgGames, 120);
        expect(ilGames, 36);
        final other = leagueTeams.firstWhere((t) => t.league != t0.league);
        final homeVs = ms.where((m) => m.matchType == 'INTERLEAGUE' && m.homeTeamId == t0.id && m.awayTeamId == other.id).length;
        final awayVs = ms.where((m) => m.matchType == 'INTERLEAGUE' && m.homeTeamId == other.id && m.awayTeamId == t0.id).length;
        expect(homeVs, 3);
        expect(awayVs, 3);
      }
    }
  });

  test('1年目のドラフトは現在のスカウト陣で1年間調べた状態で全候補が調査済みになる', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    app.myTeamId = app.teams.first.id;
    app.startYear = 2026;
    app.resetSeason();
    app.createDraftSession();
    expect(app.prospects, isNotEmpty);
    expect(app.prospects.every((p) => p.reports > 0 && p.talentLo != null), isTrue);
  });

  test('FA市場価値: B70≒1億未満〜1億・A80≒4〜5億・S90≒7〜9億（競合で6億/10億級）', () {
    Player makeBat(int ovr) => Player(
          id: 'fa_$ovr',
          lastName: '選手$ovr',
          isPitcher: false,
          mainPos: '左翼手',
          age: 29,
          proYears: 8,
          contactLeft: ovr,
          contactRight: ovr,
          power: ovr,
          eye: ovr,
          clutch: ovr,
          run: ovr,
          arm: ovr,
          throwAccuracy: ovr,
          catchSkill: ovr,
        );
    final b70 = TransferEngine.marketValue(makeBat(70), Random(1));
    final a80 = TransferEngine.marketValue(makeBat(80), Random(1));
    final s90 = TransferEngine.marketValue(makeBat(90), Random(1));
    expect(b70, inInclusiveRange(6000, 11000));
    expect(a80, inInclusiveRange(35000, 56000));
    expect(s90, inInclusiveRange(65000, 96000));
  });

  test('ニュース見出し: FA・海外FA・ポスティング・支配下登録・新外国人・戦力外がスポーツ紙風になり確定/憶測が区別される', () {
    final team = Team(id: 'T1', name: '東新', shortName: '東新', league: 'CL', players: []);
    final p = Player(id: 'p_news', lastName: '田中', firstName: '太郎', isPitcher: false, mainPos: '遊撃手', age: 27, proYears: 6, origin: 'ドミニカ共和国');

    final faDec = ItemNews.of('11/10', '東新の田中 太郎がFA宣言（Aランク）', NewsTopic.transfer, player: p, team: team);
    expect(faDec.headline, startsWith('【東新】'));
    expect(faDec.headline, contains('国内FA権行使を表明'));
    expect(faDec.headline, contains('Aランク'));
    expect(faDec.isConfirmed, isTrue);

    final overseas = ItemNews.of('12/2', '海外FA権を行使した田中 太郎のMLB移籍が決定', NewsTopic.transfer, player: p, team: team);
    expect(overseas.headline, startsWith('【東新】'));
    expect(overseas.headline, contains('海外FAでMLB移籍決定'));

    final posting = ItemNews.of('11/18', '田中 太郎のポスティング移籍を球団が容認', NewsTopic.transfer, player: p, team: team);
    expect(posting.headline, startsWith('【東新】'));
    expect(posting.headline, contains('ポスティング挑戦を球団が容認'));

    final promote = ItemNews.of('6/12', '田中 太郎を支配下登録（背番号「68」）', NewsTopic.transfer, player: p, team: team);
    expect(promote.headline, startsWith('【東新】'));
    expect(promote.headline, contains('支配下登録'));
    expect(promote.headline, contains('68'));

    final foreign = ItemNews.of('1/15', '東新が新外国人の田中 太郎（右投右打）と契約した', NewsTopic.transfer, player: p, team: team);
    expect(foreign.headline, startsWith('【東新】'));
    expect(foreign.headline, contains('新外国人'));
    expect(foreign.headline, contains('ドミニカ共和国'));

    final rel = ItemNews.of('10/12', '東新が田中 太郎に戦力外通告', NewsTopic.release, player: p, team: team);
    expect(rel.headline, startsWith('【東新】'));
    expect(rel.headline, contains('戦力外通告で退団へ'));

    final numText = '背番号の変更（開幕前日）：田中 太郎 25→7';
    final numTopic = ItemNews.topicOf(numText);
    expect(numTopic, NewsTopic.transfer);
    final numNews = ItemNews.of('3/27', numText, numTopic!, player: p, team: team);
    expect(numNews.headline, '【東新】田中 太郎の新背番号が決定！　今季から「7」で心機一転');
    expect(numNews.player, isNull);
    expect(numNews.body.any((b) => b.contains('■背番号変更一覧')), isTrue);
    expect(numNews.body.any((b) => b.contains('・田中 太郎　25 → 7')), isTrue);
    expect(numNews.teamFans.every((f) => !f.text.contains('トレード') && !f.text.contains('背番号何番')), isTrue);

    final rumor = ItemNews(NewsTopic.rumor, '11/12', '予想', '【東新】獲得調査へ', ['予想'], p, team, const [], const []);
    expect(rumor.isConfirmed, isFalse);
  });

  test('シーズン途中から開幕戦へ巻き戻すと今季成績・試合結果がリセットされ日付が開幕戦に戻る', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final app = AppState(db);
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    final firstReg = app.matches.where((m) => m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE').map((m) => m.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final firstMatch = app.matches.firstWhere((m) => m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE');
    firstMatch.isPlayed = true;
    firstMatch.homeScore = 4;
    firstMatch.awayScore = 2;
    app.currentDate = firstReg.add(const Duration(days: 5));
    final injured = app.teams.first.players.first;
    injured.seasonStats.atBats = 12;
    injured.seasonStats.hits = 4;
    injured.injuryName = '肉離れ';
    injured.injuryDays = 14;
    injured.injurySeverity = 2;
    await app.saveData();

    expect(app.rewindToOpeningDay(), isTrue);
    await app.saveData();
    final playedAfter = app.matches.where((m) => m.isPlayed && (m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE')).length;
    expect(playedAfter, 0);
    expect(app.currentDate, firstReg);
    expect(app.teams.first.players.every((p) => p.seasonStats.atBats == 0 && p.seasonStats.hits == 0 && p.injuryDays == 0 && p.injuryName.isEmpty), isTrue);
    final rows = await db.select(db.matchRows).get();
    expect(rows.any((r) => r.played), isFalse);
  });

  test('自動継投では延長戦や中継ぎ疲労時でも中継ぎを優先し、先発ローテ投手は中継ぎ不在時のみ登板する', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    final home = app.teams[0], away = app.teams[1];
    final sim = MatchSimulator();
    final session = sim.startGame(Match(homeTeamId: home.id, awayTeamId: away.id, date: DateTime(2026, 4, 10), matchType: 'LEAGUE'), home, away);
    session.state.inning = 12;
    session.state.isTop = true;
    final cur = session.homePitcher;
    session.gamePitchCounts[cur.id] = 130;

    final rotIds = home.rotation.take(home.rotationCount).toSet();
    final extraStarterId = rotIds.firstWhere((id) => id != cur.id);
    if (!home.active26.contains(extraStarterId)) home.active26.add(extraStarterId);
    final avail = sim.availablePitchers(session, true);
    final relievers = avail.where((p) => !rotIds.contains(p.id)).toList();
    final starters = avail.where((p) => rotIds.contains(p.id)).toList();
    expect(relievers, isNotEmpty);
    expect(starters, isNotEmpty);

    // 1) 中継ぎの体力が低くても先発ローテではなく中継ぎを選ぶ
    for (final r in relievers) {
      r.energy = (r.maxEnergy * 0.2).round();
    }
    for (final st in starters) {
      st.energy = st.maxEnergy;
    }
    sim.autoPitching(session, true);
    expect(rotIds.contains(session.homePitcher.id), isFalse);

    // 2) 中継ぎが全員登板済みで残っていないときだけ先発ローテ投手が登板する
    for (final r in relievers) {
      session.usedIds.add(r.id);
    }
    session.gamePitchCounts[session.homePitcher.id] = 130;
    sim.autoPitching(session, true);
    expect(rotIds.contains(session.homePitcher.id), isTrue);
  });

  test('強行出場の悪化率は抑えられており、怪我しにくさ(durability)が高いほど悪化しにくい', () {
    final t = Team(id: 'T1', name: '東新', shortName: '東新', league: 'CL', players: []);
    final iron = Player(id: 'p_iron', lastName: '鉄人', isPitcher: false, mainPos: '一塁手', durability: 90);
    final avg = Player(id: 'p_avg', lastName: '標準', isPitcher: false, mainPos: '一塁手', durability: 50);
    final glass = Player(id: 'p_glass', lastName: 'スペ', isPitcher: false, mainPos: '一塁手', durability: 20);
    final pIron = ConditionEngine.aggravationProb(iron, t);
    final pAvg = ConditionEngine.aggravationProb(avg, t);
    final pGlass = ConditionEngine.aggravationProb(glass, t);
    expect(pIron, lessThan(0.012));
    expect(pAvg, lessThan(0.04));
    expect(pIron, lessThan(pAvg));
    expect(pAvg, lessThan(pGlass));
    expect(ConditionEngine.injuryProb(avg, t), lessThanOrEqualTo(0.0025));
    expect(ConditionEngine.injuryProb(iron, t), lessThan(ConditionEngine.injuryProb(glass, t)));
  });

  test('MVP査定はサヨナラ・逆転・勝ち越し・同点に加点し、サヨナラ打者以外をサヨナラ見出しにしない', () {
    final home = Team(id: 'H', name: '東新', shortName: '東新', league: 'CL', players: []);
    final away = Team(id: 'A', name: '神戸', shortName: '神戸', league: 'CL', players: []);
    final m = Match(homeTeamId: 'H', awayTeamId: 'A', date: DateTime(2026, 5, 1), matchType: 'LEAGUE')
      ..isPlayed = true
      ..homeScore = 2
      ..awayScore = 1
      ..homeInningScores = [1, 0, 0, 0, 0, 0, 0, 0, 1]
      ..awayInningScores = [1, 0, 0, 0, 0, 0, 0, 0, 0]
      ..playByPlay = [
        '1回表 神戸 攻撃',
        '1回表 高橋がタイムリー 1点',
        '1回裏 東新 攻撃',
        '1回裏 佐藤がソロホームラン！ 1点',
        '9回裏 東新 攻撃',
        '9回裏 鈴木がサヨナラタイムリー！ 1点',
      ]
      ..boxScore = {
        'homeBatters': {
          '佐藤': {'ab': 4, 'h': 2, 'hr': 1, 'rbi': 1, 'bb': 0},
          '鈴木': {'ab': 4, 'h': 1, 'hr': 0, 'rbi': 1, 'bb': 0},
        },
        'awayBatters': {
          '高橋': {'ab': 4, 'h': 2, 'hr': 0, 'rbi': 1, 'bb': 0},
        },
        'homePitcher': {
          '山本': {'ip': '6.0', 'er': 1, 'so': 5, 'dec': ''},
        },
        'awayPitcher': {
          '中村': {'ip': '8.1', 'er': 2, 'so': 4, 'dec': '敗'},
        },
      };
    final mvp = GameNews.mvpOf(m);
    expect(mvp?.name, '鈴木');
    final g = GameNews.of(m, home, away);
    expect(g.headline, contains('鈴木'));
    expect(g.headline, isNot(contains('佐藤が劇的サヨナラ')));
  });

  test('現役ドラフトは前季出場数(prevGames/prevApps)で判定し、自球団自由契約の再契約は移籍扱いにならない', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    final my = app.teams.first;
    app.myTeamId = my.id;
    // 1) 現役ドラフト: 年俸5000万未満・プロ4年目・25歳でも前季40試合出場なら対象外
    final reg = Player(id: 'ad_reg', lastName: '主力', isPitcher: false, mainPos: '遊撃手', age: 25, proYears: 4, salary: 3000, prevGames: 40);
    final sub = Player(id: 'ad_sub', lastName: '控え', isPitcher: false, mainPos: '遊撃手', age: 25, proYears: 4, salary: 3000, prevGames: 10);
    expect(TransferEngine.activeDraftEligible(reg, 2027), isFalse);
    expect(TransferEngine.activeDraftEligible(sub, 2027), isTrue);

    // 投手: 前季30イニング未満（89アウト = 29回2/3）は対象、30イニング（90アウト）は対象外
    final pUnder30 = Player(id: 'ad_p_ok', lastName: '中継ぎ', isPitcher: true, mainPos: '投手', age: 25, proYears: 4, salary: 3000, prevApps: 25, prevInnings: 89);
    final pAt30 = Player(id: 'ad_p_no', lastName: '先発', isPitcher: true, mainPos: '投手', age: 25, proYears: 4, salary: 3000, prevApps: 5, prevInnings: 90);
    expect(TransferEngine.activeDraftEligible(pUnder30, 2027), isTrue);
    expect(TransferEngine.activeDraftEligible(pAt30, 2027), isFalse);

    // 2) 自球団自由契約→再契約（育成含む）は「再契約」になり移籍記事にならない
    final p = my.players.firstWhere((x) => !x.ikusei);
    my.players.remove(p);
    final fa = FreeAgent(p, my.id, '戦力外');
    app.freeAgents.add(fa);
    final err = app.signFreeAgent(fa, ikusei: true);
    expect(err, isNull);
    expect(p.ikusei, isTrue);
    expect(app.news.first, contains('再契約'));
    final newsItem = ItemNews.of('11/15', app.news.first, ItemNews.topicOf(app.news.first)!, player: p, team: my);
    expect(newsItem.headline, contains('再契約'));
  });

  test('外国人来日時の適応力は S100=1.20〜60=1.00 で平均60前後になる', () {
    expect(ForeignEngine.adaptMult(100), closeTo(1.20, 1e-9));
    expect(ForeignEngine.adaptMult(90), closeTo(1.15, 1e-9));
    expect(ForeignEngine.adaptMult(80), closeTo(1.10, 1e-9));
    expect(ForeignEngine.adaptMult(70), closeTo(1.05, 1e-9));
    expect(ForeignEngine.adaptMult(60), closeTo(1.00, 1e-9));
    expect(ForeignEngine.adaptMult(50), closeTo(0.95, 1e-9));

    final r = Random(42);
    var sum = 0;
    var maxAdapt = 0;
    const n = 2000;
    for (var i = 0; i < n; i++) {
      final p = ForeignEngine.make(2026, r, ikusei: false, age: 27, mean: 70);
      sum += p.adapt;
      if (p.adapt > maxAdapt) maxAdapt = p.adapt;
    }
    final avg = sum / n;
    expect(avg, inInclusiveRange(57.0, 63.0));
    expect(maxAdapt, greaterThan(95));
  });

  test('オフ期間の育成→自由契約→支配下再契約は入団時に背番号を確定せず開幕前日に決定する', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    final my = app.teams.first;
    app.myTeamId = my.id;
    app.seasonFinished = true;
    app.draftDoneYear = 2026;
    app.currentDate = DateTime(2026, 11, 20);
    expect(app.isBeforeOpeningDay(), isTrue);

    final pIk = my.players.firstWhere((x) => !x.ikusei);
    expect(app.reSignIkusei(pIk), isNull);
    await app.saveData();
    expect(pIk.ikusei, isTrue);
    expect(app.news.first, isNot(contains('背番号')));

    expect(app.releasePlayer(pIk), isNull);
    await app.saveData();
    final fa = app.freeAgents.last;
    expect(app.signFreeAgent(fa, ikusei: false), isNull);
    await app.saveData();
    expect(pIk.ikusei, isFalse);
    expect(pIk.uniformNumber, inInclusiveRange(-1, 99));
    expect(pIk.numberPending, isTrue);

    final joinChron = app.chron.lastWhere((c) => c['pid'] == pIk.id && c['k'] == 'join');
    expect('${joinChron['t']}', contains('自由契約から再契約'));
    expect('${joinChron['t']}', isNot(contains('背番号は')));

    // 仮番号を変更予約しても開幕前日までは仮番号のまま「変更」年表は残らず、開幕前日に決定する
    final tempNum = pIk.uniformNumber;
    final desired = RosterEngine.freeNumber(my, ikusei: false);
    expect(app.setNumber(my, pIk, desired), isNull);
    expect(pIk.uniformNumber, tempNum);
    expect(pIk.nextNumber, desired);
    expect(pIk.numberPending, isTrue);
    expect(app.chron.where((c) => c['pid'] == pIk.id && c['k'] == 'number'), isEmpty);

    // 開幕前日で背番号が正式決定し、年表・ニュース・背番号の変遷に「に決定」として記録される
    app.applyNextNumbers(DateTime(2027, 3, 25));
    expect(pIk.uniformNumber, desired);
    expect(pIk.nextNumber, isNull);
    expect(pIk.numberPending, isFalse);
    final numChron = app.chron.lastWhere((c) => c['pid'] == pIk.id && c['k'] == 'number');
    expect('${numChron['t']}', contains('の背番号が${uniformLabel(desired)}に決定。'));
    expect(app.news.first, contains('背番号の決定（開幕前日）：'));
    final newsItem = ItemNews.of('3/25', app.news.first, ItemNews.topicOf(app.news.first)!, team: my);
    expect(newsItem.headline, contains('に決定'));
    final hist = await app.numberHistory(my);
    expect(hist[desired]?.any((e) => e.$2 == pIk.registeredName && e.$3 == '背番号決定'), isTrue);
  });

  test('ニュース記事の順序（同日内・球団のかたまり）と複数人記事で1人だけピックアップされないこと', () async {
    final tA = Team(id: 'A', name: '球団A', shortName: 'A', league: 'CL', players: []);
    final tB = Team(id: 'B', name: '球団B', shortName: 'B', league: 'CL', players: []);
    final tC = Team(id: 'C', name: '球団C', shortName: 'C', league: 'PL', players: []);
    final p1 = Player(id: 'p1', lastName: '一', isPitcher: false, mainPos: '一塁手', age: 25, proYears: 4);
    final p2 = Player(id: 'p2', lastName: '二', isPitcher: false, mainPos: '二塁手', age: 26, proYears: 5);
    final d1 = DateTime(2026, 11, 15, 9, 0);
    final d1Later = DateTime(2026, 11, 15, 18, 0);
    final d2 = DateTime(2026, 11, 16);

    final feed = [
      (d1, ItemNews(NewsTopic.transfer, '11/15', 'A1', '【A】A1', ['A1'], p1, tA, const [], const [])),
      (d1, ItemNews(NewsTopic.transfer, '11/15', 'C1', '【C】C1', ['C1'], p2, tC, const [], const [])),
      (d1Later, ItemNews(NewsTopic.release, '11/15', 'B1', '【B】B1', ['B1'], p1, tB, const [], const [])),
      (d1, ItemNews(NewsTopic.transfer, '11/15', 'C2', '【C】C2', ['C2'], p1, tC, const [], const [])),
      (d1Later, ItemNews(NewsTopic.transfer, '11/15', 'A2', '【A】A2', ['A2'], p2, tA, const [], const [])),
      (d2, ItemNews(NewsTopic.transfer, '11/16', 'New', '【C】New', ['New'], p1, tC, const [], const [])),
    ];
    ItemNews.sortFeed(feed, leagueTeams: [tA, tB, tC], myTeamId: tB.id, groupByTeam: true);
    expect(feed.map((e) => e.$2.headline).toList(), ['【C】New', '【B】B1', '【A】A1', '【A】A2', '【C】C1', '【C】C2']);

    final relMulti = ItemNews.releaseBatch('11/10', tA, [p1, p2]);
    expect(relMulti.player, isNull);
    final relSingle = ItemNews.releaseBatch('11/10', tA, [p1]);
    expect(relSingle.player, p1);

    final draftMulti = ItemNews.draftSummary('10/31', tA, [
      (round: '1位', player: p1, school: '甲高校'),
      (round: '2位', player: p2, school: '乙大学'),
    ]);
    expect(draftMulti.player, isNull);

    final tradeNews = ItemNews.of(
      '12/1',
      'トレード成立：Aの一とBの二',
      NewsTopic.transfer,
      player: p1,
      team: tA,
      myTeamId: tA.id,
      involved: [(p1, tB), (p2, tA)],
    );
    expect(tradeNews.player, isNull);

    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    final rumors = TradeRumor.recent(app.teams, DateTime(2026, 11, 20), myTeamId: app.teams.first.id, count: 3);
    expect(rumors, isNotEmpty);
    for (final r in rumors) {
      expect(r.player, isNull);
      expect(r.team, isNotNull);
      expect(r.playerTeam, isNotNull);
    }
  });

  test('移籍・退団関連の記事はタイトル・本文・コメントが矛盾しない', () {
    final team = Team(id: 'T1', name: '東新', shortName: '東新', league: 'CL', players: []);
    final p = Player(id: 'p_consistency', lastName: '山本', firstName: '一郎', isPitcher: true, mainPos: '投手', age: 27, proYears: 7);

    // 1) ポスティング契約不成立で残留
    const postNoDealTxt = 'ポスティング：山本 一郎（東新）は大リーグの球団と契約に至らず、残留します';
    final postNoDeal = ItemNews.of('12/20', postNoDealTxt, ItemNews.topicOf(postNoDealTxt)!, player: p, team: team);
    expect(postNoDeal.headline, contains('残留'));
    expect(postNoDeal.headline, isNot(contains('移籍')));
    expect(postNoDeal.body.first, contains('契約合意に至らず残留'));
    expect(postNoDeal.teamFans.any((f) => f.text.contains('メジャーでも頑張って') || f.text.contains('穴は痛い')), isFalse);

    // 2) ポスティング不承認で残留
    const postRejTxt = 'ポスティング：東新の山本 一郎の希望を、球団が認めませんでした';
    final postRej = ItemNews.of('11/10', postRejTxt, ItemNews.topicOf(postRejTxt)!, player: p, team: team);
    expect(postRej.headline, contains('不承認で残留'));
    expect(postRej.body.first, contains('認めず'));

    // 3) ポスティングでMLB移籍決定
    const postMovedTxt = 'ポスティング：山本 一郎が東新から大リーグのLADへ移籍。東新は提携枠を1つ得ました';
    final postMoved = ItemNews.of('12/15', postMovedTxt, ItemNews.topicOf(postMovedTxt)!, player: p, team: team);
    expect(postMoved.headline, contains('LADへ電撃移籍'));

    // 4) 海外FA契約不成立で残留
    const ovStayTxt = '海外FA：山本 一郎（東新）は大リーグとの契約に至らず、残留しました';
    final ovStay = ItemNews.of('12/28', ovStayTxt, ItemNews.topicOf(ovStayTxt)!, player: p, team: team);
    expect(ovStay.headline, contains('残留'));
    expect(ovStay.headline, isNot(contains('移籍決定')));

    // 5) FA未契約で自由契約
    const faUnTxt = 'FA：山本 一郎（元東新）はどこの球団とも契約せず、自由契約になりました';
    final faUn = ItemNews.of('1/5', faUnTxt, ItemNews.topicOf(faUnTxt)!, player: p, team: team);
    expect(faUn.headline, contains('自由契約'));
    expect(faUn.headline, isNot(contains('FA獲得が決定')));
    expect(faUn.body.first, contains('自由契約となった'));

    // 6) 現役引退（コーチ就任含む）
    const retireTxt = '山本 一郎が現役を引退し、投手コーチに就任しました';
    final retire = ItemNews.of('10/25', retireTxt, ItemNews.topicOf(retireTxt)!, player: p, team: team);
    expect(retire.headline, contains('現役引退'));
    expect(retire.body.join('\n'), isNot(contains('起用法しだいで')));
    expect(retire.otherFans.every((f) => !f.text.contains('拾ってくれ') && !f.text.contains('新天地')), isTrue);

    // 7) 契約更改合意せず退団
    const holdoutTxt = '山本 一郎は契約更改で合意できず、退団しました（自由契約）';
    final holdout = ItemNews.of('12/2', holdoutTxt, ItemNews.topicOf(holdoutTxt)!, player: p, team: team);
    expect(holdout.headline, contains('契約更改で合意せず退団'));
    expect(holdout.headline, isNot(contains('戦力外通告')));
  });

  test('背番号変遷は同日内でも時系列が逆転せず、空白1日未満は「人 → 人」にまとまる', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    final t = app.teams.first;
    app.startYear = 2027;
    app.chronYears[2026] = [
      // #7: 2026年にAが着用開始 → 2027-03-26 にB(25→7)がA(7→1)より先に記録された場合
      {'d': '2026-04-01', 'team': t.id, 'k': 'join', 't': '内野手 選手A(24)が入団。背番号は7。'},
      // #8: Cが退団し翌日(gapDays == 1)にDが入団
      {'d': '2026-04-01', 'team': t.id, 'k': 'join', 't': '外野手 選手C(29)が入団。背番号は8。'},
      {'d': '2026-11-10', 'team': t.id, 'k': 'leave', 't': '外野手 選手C(29)が戦力外通告を受けて退団。'},
      {'d': '2026-11-11', 'team': t.id, 'k': 'join', 't': '外野手 選手D(22)がドラフト1位で入団。背番号は8。'},
      // #9: Eが退団し2日後(gapDays == 2)にFが入団 → 1日以上空白ありなので分かれる
      {'d': '2026-04-01', 'team': t.id, 'k': 'join', 't': '投手 選手E(31)が入団。背番号は9。'},
      {'d': '2026-11-10', 'team': t.id, 'k': 'leave', 't': '投手 選手E(31)が戦力外通告を受けて退団。'},
      {'d': '2026-11-12', 'team': t.id, 'k': 'join', 't': '投手 選手F(25)が自由契約から入団。背番号は9。'},
    ];
    app.chronYears[2027] = [
      {'d': '2027-03-26', 'team': t.id, 'k': 'number', 't': '外野手 選手Bの背番号を25から7に変更。'},
      {'d': '2027-03-26', 'team': t.id, 'k': 'number', 't': '内野手 選手Aの背番号を7から1に変更。'},
    ];

    final hist = await app.numberHistory(t);
    expect(hist[7], [
      ('2026-04-01', '選手A', '入団'),
      ('2027-03-26', '選手A → 選手B', '25から変更（選手Aは1へ変更）'),
    ]);
    expect(hist[8], [
      ('2026-04-01', '選手C', '入団'),
      ('2026-11-11', '選手C → 選手D', 'ドラフト1位で入団（選手Cは退団）'),
    ]);
    expect(hist[9], [
      ('2026-04-01', '選手E', '入団'),
      ('2026-11-10', '選手E', '退団（空き番号に）'),
      ('2026-11-12', '選手F', '自由契約から入団'),
    ]);
  });

  test('入退団記録パーサが年・日付・種別・球団・内容を正しく分解する', () {
    final tA = Team(id: 'A', name: '東新', shortName: '東新', league: 'CL', players: []);
    final tB = Team(id: 'B', name: '西川', shortName: '西川', league: 'PL', players: []);
    final teams = [tA, tB];

    final rDraft = parseTransaction('2026/10/31 東新 ドラフト1位（大学・甲大） 山田 太郎（投手）', teams);
    expect(rDraft.year, 2026);
    expect(rDraft.md, '10/31');
    expect(rDraft.kind, 'ドラフト');
    expect(rDraft.teamLabel, '東新');
    expect(rDraft.detail, 'ドラフト1位（大学・甲大） 山田 太郎（投手）');

    final rTrade = parseTransaction('2027/6/10 トレード 東新：佐藤 ⇄ 西川：鈴木', teams);
    expect(rTrade.kind, 'トレード');
    expect(rTrade.teamLabel, '東新⇄西川');
    expect(rTrade.teamIds, {'A', 'B'});
    expect(rTrade.detail, '佐藤 ⇄ 鈴木');

    final rFa = parseTransaction('2026/12/5 田中 FA 移籍 東新 → 西川（Aランク・2億円×3年）', teams);
    expect(rFa.kind, 'FA移籍');
    expect(rFa.teamLabel, '東新→西川');
    expect(rFa.teamIds, {'A', 'B'});

    final rRel = parseTransaction('2026/10 東新 高橋（31歳）戦力外通告', teams);
    expect(rRel.md, '10月');
    expect(rRel.kind, '戦力外');
    expect(rRel.teamLabel, '東新');

    final rRet = parseTransaction('2026/10/20 西川 伊藤 現役引退・打撃コーチに就任', teams);
    expect(rRet.kind, '引退');
    expect(rRet.group, '引退');

    final rRenew = parseTransaction('2026/11/15 東新 渡辺 契約更改 5,000万円→6,000万円', teams);
    expect(rRenew.kind, '更改');
    expect(rRenew.teamLabel, '東新');
  });

  testWidgets('タイトル画面の規定表示が崩れず、コーチとスカウトがタブ分離されている', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    final my = app.teams.first;
    app.myTeamId = my.id;

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: TitleRankingScreen(app: app, league: 'CL', initial: 0)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('規定打席'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CoachTab(app: app, team: my, onChanged: () {}))));
    await tester.pumpAndSettle();
    expect(find.text('1軍スタッフ'), findsOneWidget);
    expect(find.text('スカウト（ドラフト候補・海外の選手）'), findsNothing);

    await tester.pumpWidget(MaterialApp(home: ScoutScreen(app: app)));
    await tester.pumpAndSettle();
    expect(find.text('ドラフト候補'), findsOneWidget);
    expect(find.text('スカウト陣'), findsOneWidget);
    await tester.tap(find.text('スカウト陣'));
    await tester.pumpAndSettle();
    expect(find.text('スカウト（ドラフト候補・海外の選手）'), findsOneWidget);
  });

  test('3軍オーダーは全9守備位置を持ち、新旧セーブ形式で永続化・復元できる', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    final my = app.teams.first;
    final used = thirdUsed(my);
    final auto = app.effectiveThirdLineup(my, used: used);
    expect(auto.length, 9);
    expect(auto.map((e) => e.position).toSet(), {'捕', '一', '二', '三', '遊', '左', '中', '右', 'DH'});

    // 新形式で保存・復元
    my.thirdAuto = false;
    my.thirdLineup = [for (final e in auto) LineupEntry(playerId: e.playerId, position: e.position)];
    my.thirdRotation = app.effectiveThirdRotation(my, used: used);
    final json = my.toJson();
    final restored = Team.fromJson(json, (p) => Player.fromJson(Map<String, dynamic>.from(p as Map)));
    expect(restored.thirdAuto, isFalse);
    expect(restored.thirdLineup.length, 9);
    expect(restored.thirdLineup.first.position, auto.first.position);
    expect(restored.thirdRotation, my.thirdRotation);

    // 旧形式(List<String>)も読み込んで欠けた守備位置を補完できる
    final legacyJson = Map<String, dynamic>.from(json)..['thirdLineup'] = [for (final e in auto) e.playerId];
    final legacyTeam = Team.fromJson(legacyJson, (p) => Player.fromJson(Map<String, dynamic>.from(p as Map)));
    final effLegacy = app.effectiveThirdLineup(legacyTeam, used: used);
    expect(effLegacy.length, 9);
    expect(effLegacy.map((e) => e.position).toSet(), {'捕', '一', '二', '三', '遊', '左', '中', '右', 'DH'});
  });

  testWidgets('3軍オーダー画面は2軍と同じく守備位置の入替・守備フィールド・先発ローテ編集ができる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    final my = app.teams.first;
    app.myTeamId = my.id;
    final pmap = {for (final p in my.players) p.id: p};
    final before = app.effectiveThirdLineup(my, used: thirdUsed(my));
    final pos0 = before[0].position;
    final pos1 = before[1].position;

    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LineupTab(team: my, appState: app, onRosterChanged: () {}, playerMap: pmap, level: 3),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('守備位置'), findsOneWidget);

    // 1番打者の守備位置をタップし、2番打者の守備位置に変更すると両者が入れ替わる
    await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
    await tester.pumpAndSettle();
    final chipFinder = pos1 == 'DH' ? find.widgetWithText(ChoiceChip, '指') : find.byWidgetPredicate((w) => w is ChoiceChip && (w.label is Text) && ((w.label as Text).data?.startsWith('$pos1 ') ?? false));
    await tester.tap(chipFinder.first);
    await tester.pumpAndSettle();
    expect(my.thirdAuto, isFalse);
    expect(my.thirdLineup[0].position, pos1);
    expect(my.thirdLineup[1].position, pos0);

    // 3軍投手タブも2軍と同じ先発ローテ・中継ぎ構成で人数変更できる
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PitcherTab(team: my, appState: app, onRosterChanged: () {}, playerMap: pmap, level: 3),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('3軍の先発ローテ'), findsOneWidget);
    expect(find.textContaining('3軍の中継ぎ'), findsOneWidget);
    final beforeRotCount = my.thirdRotationCount;
    await tester.tap(find.byTooltip('先発を1人増やす'));
    await tester.pumpAndSettle();
    expect(my.thirdRotationCount, beforeRotCount + 1);
  });

  testWidgets('2軍・3軍の投手オーダー画面で年齢・全盛期・成長率が打者と同じサイズで並列表示され360px幅で溢れない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    final my = app.teams.first;
    app.myTeamId = my.id;
    final pmap = {for (final p in my.players) p.id: p};

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final lv in [2, 3]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PitcherTab(team: my, appState: app, onRosterChanged: () {}, playerMap: pmap, level: lv),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('年'), findsWidgets);
      expect(find.text('全盛'), findsWidgets);
      expect(find.text('成長'), findsWidgets);
      expect(find.text('登'), findsWidgets);
      expect(find.text('防御'), findsWidgets);
      expect(find.textContaining('歳・全盛'), findsNothing);

      final rotId = (lv == 2 ? my.farmRotation : my.thirdRotation).firstWhere((id) => pmap[id] != null, orElse: () => '');
      if (rotId.isNotEmpty) {
        final p = pmap[rotId]!;
        final (pa, pb) = GrowthCurve.primeRange(p);
        final primeFinder = find.text('$pa-$pb');
        final growthFinder = find.text(p.growthRate.toStringAsFixed(2));
        expect(primeFinder, findsWidgets);
        expect(growthFinder, findsWidgets);
        final primeText = tester.widget<Text>(primeFinder.first);
        final growthText = tester.widget<Text>(growthFinder.first);
        expect(primeText.style?.fontSize, 12);
        expect(growthText.style?.fontSize, 12);
      }
    }
  });

  testWidgets('背番号変更画面で選手名をタップすると選手詳細が開き、表彰画面の沢村賞が崩れず、表彰タブに三振(－)や二塁打・OPS・最多登板(＋)が表示される', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    final my = app.teams.first;
    app.myTeamId = my.id;
    final sortedOnBoard = my.players.toList()
      ..sort((a, b) => a.ikusei != b.ikusei ? (a.ikusei ? 1 : -1) : uniformSortKey(a.uniformNumber).compareTo(uniformSortKey(b.uniformNumber)));
    final topPlayer = sortedOnBoard.first;
    final batter = my.players.firstWhere((p) => !p.isPitcher && !p.ikusei);
    final pitcher = my.players.firstWhere((p) => p.isPitcher && !p.ikusei);

    // 1. 背番号変更画面から選手名をタップすると PlayerDetailDialog が開く
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: NumberBoardScreen(app: app, team: my),
    ));
    await tester.pumpAndSettle();
    expect(find.text(topPlayer.listName), findsOneWidget);
    await tester.tap(find.text(topPlayer.listName));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerDetailDialog), findsOneWidget);
    await tester.tap(find.byTooltip('閉じる'));
    await tester.pumpAndSettle();

    // 2. タイトル外シーズン1位記録（三振(－)・二塁打・三塁打・四球・長打率・OPS・最多登板(＋)）と沢村賞の集計・表示確認
    batter.seasonStats
      ..games = 143
      ..atBats = 500
      ..hits = 175
      ..doubles = 45
      ..triples = 12
      ..homeRuns = 38
      ..walks = 95
      ..strikeouts = 165
      ..rbi = 110;
    pitcher.seasonStats
      ..games = 70
      ..pitchApps = 70
      ..starts = 26
      ..inningsPitched = 195 * 3
      ..wins = 18
      ..losses = 4
      ..earnedRuns = 38
      ..pitcherStrikeouts = 220;

    final aw = AwardsEngine.compute(year: 2026, teams: app.teams, matches: app.matches, championId: my.id);
    final saw = aw['sawamura'] as Map<String, dynamic>;
    expect(saw['id'], pitcher.id);
    expect(saw['winners'], isA<List>());
    final lgAw = (aw['leagues'] as Map)[my.league] as Map<String, dynamic>;
    final leaders = (lgAw['leaders'] as List).cast<Map<String, dynamic>>();
    final leaderTitles = leaders.map((e) => e['title'] as String).toSet();
    expect(leaderTitles, containsAll(['最多二塁打', '最多三塁打', '最多四球', '最高長打率', '最高OPS', '最多三振', '最多登板']));

    // 選手に各記録を付与して選手詳細の「経歴 → 表彰」タブを確認
    batter.honors.addAll([
      '2026年11月1日 最多二塁打',
      '2026年11月1日 最多三塁打',
      '2026年11月1日 最多四球',
      '2026年11月1日 最高長打率',
      '2026年11月1日 最高OPS',
      '2026年11月1日 最多三振',
    ]);
    pitcher.honors.addAll([
      '2026年11月1日 沢村賞',
      '2026年11月1日 最多登板',
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayerDetailDialog(player: batter, appState: app, team: my, isReadOnly: true),
      ),
    ));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('経歴').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('表彰').first);
    await tester.pumpAndSettle();

    expect(find.text('記録(＋)'), findsWidgets);
    expect(find.text('記録(－)'), findsWidgets);
    expect(find.textContaining('最多二塁打（45二塁打）'), findsOneWidget);
    expect(find.textContaining('最多三塁打（12三塁打）'), findsOneWidget);
    expect(find.textContaining('最多四球（95四球）'), findsOneWidget);
    expect(find.textContaining('最高長打率（'), findsOneWidget);
    expect(find.textContaining('最高OPS（'), findsOneWidget);
    expect(find.textContaining('最多三振（165三振）'), findsOneWidget);

    // 3. AwardsScreen（タイトル発表画面）で沢村賞が360px幅でも崩れず、選手名タップで詳細が開く
    await tester.runAsync(() async {
      await app.db.setKv('awards_2026', '{"year":2026,"champion":"${my.id}","sawamura":{"id":"${pitcher.id}","name":"${pitcher.registeredName}","team":"${my.id}","teamName":"${my.shortName}","value":"18勝4敗 防御率1.75 220奪三振 195回","met":6},"leagues":{}}');
    });
    await tester.pumpWidget(MaterialApp(
      home: AwardsScreen(appState: app, year: 2026),
    ));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('沢村賞'), findsOneWidget);
    expect(find.text('基準6項目達成'), findsOneWidget);
    expect(find.textContaining('18勝4敗 防御率1.75 220奪三振 195回'), findsOneWidget);

    await tester.tap(find.text('${pitcher.registeredName}（${my.shortName}）'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerDetailDialog), findsOneWidget);
  });

  testWidgets('プロ年数はNPB在籍時はNPB年数・他リーグ在籍時はプロ入りからの総年数になり、成績表は高校・大学卒業後の独立・海外を含むプロ開始年からすべて表示される', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    final my = app.teams.first;
    app.myTeamId = my.id;
    app.startYear = 2026;

    // 1. 他リーグ在籍選手（2026年時点で25歳 → 19歳プロ入り=2020年開始・プロ7年目）
    final otherTeam = app.otherWorld!.teams.firstWhere((t) => t.leagueId == 'AAA');
    final otherBatter = otherTeam.players.firstWhere((p) => !p.isPitcher);
    otherBatter
      ..age = 25
      ..proYears = 3
      ..abroad = []
      ..abroadStats = [];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ScoutReport(player: otherBatter, appState: app, onClose: () {})),
      ),
    ));
    await tester.pumpAndSettle();

    // 他リーグ在籍中はプロ入り（19歳=2020年）からの総年数「7年目」と表示される
    expect(find.text('7年目'), findsOneWidget);

    // 経歴タブに切り替えるとプロ開始年（2020年）から2025年までの推定成績がすべて並ぶ
    await tester.tap(find.text('経歴').first);
    await tester.pumpAndSettle();
    for (int y = 2020; y <= 2025; y++) {
      expect(find.text('$y'), findsWidgets);
    }

    // 2. この他リーグ選手がNPB球団に入団すると、NPBでのプロ年数は1年目になる
    while (RosterEngine.freeSlots(my) <= 0) {
      my.players.removeLast();
    }
    app.currentDate = DateTime(2026, 5, 1);
    final hiSal = (app.otherSalary(otherBatter) * 2).clamp(1000, 30000);
    String? err = 'retry';
    for (int w = 0; w < 20 && err != null; w++) {
      app.currentDate = DateTime(2026, 5, 1 + w * 7);
      err = app.offerOtherPlayer(otherBatter, salary: hiSal, years: 1);
    }
    expect(err, isNull);
    expect(otherBatter.proYears, 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ScoutReport(player: otherBatter, appState: app, team: my, onClose: () {})),
      ),
    ));
    await tester.pumpAndSettle();
    // 能力タブに戻してNPB在籍時はNPB在籍年数の「1年目」と表示されることを確認
    await tester.tap(find.text('能力').first);
    await tester.pumpAndSettle();
    expect(find.text('1年目'), findsOneWidget);

    // 3. 高校・大学卒業後に独立リーグを経てNPB入りした日本人選手も、独立時代のプロ開始年から成績表に推定成績が残る
    final indieNpb = Player(
      id: 'indie_npb_test',
      lastName: '独立',
      firstName: '太郎',
      isPitcher: false,
      mainPos: '遊撃手',
      age: 24, // 2026年に24歳、NPB 2年目（2025年入団=23歳入団）
      proYears: 2,
      amPath: ['高校　明徳義塾高', '独立　四国・徳島'],
      draftInfo: '2024年 ドラフト4位（独立）',
    );
    my.players.add(indieNpb);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ScoutReport(player: indieNpb, appState: app, team: my, onClose: () {})),
      ),
    ));
    await tester.pumpAndSettle();
    // NPB在籍中なのでプロ年数はNPB年数の「2年目」
    expect(find.text('2年目'), findsOneWidget);

    // 経歴タブを開くと、高校卒業後（19歳=2021年）から2024年までの独立リーグ（四国・徳島*）推定成績と2025年のNPB成績が表示される
    await tester.tap(find.text('経歴').first);
    await tester.pumpAndSettle();
    for (int y = 2021; y <= 2025; y++) {
      expect(find.text('$y'), findsWidgets);
    }
    expect(find.text('四国・徳島*'), findsWidgets);
  });

  testWidgets('オープン戦期間中は選手詳細画面に2026(OP)として一時表示され通算に含まれず、開幕すると0から始まる', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    });
    final my = app.teams.first;
    app.myTeamId = my.id;
    app.startYear = 2026;

    // 公式戦初日より前（オープン戦期間）にする
    final firstOpen = app.matches.firstWhere((m) => m.matchType == 'OPEN');
    final firstReg = app.matches.where((m) => m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE').map((m) => m.date).reduce((a, b) => a.isBefore(b) ? a : b);
    app.currentDate = firstOpen.date;
    Player.showOpen = app.openPeriod;
    expect(app.openPeriod, isTrue);

    final batter = my.players.firstWhere((p) => !p.isPitcher && !p.ikusei);
    final preCareerHits = batter.career.hits;
    batter.openStats = PlayerStats(games: 8, atBats: 25, hits: 10, homeRuns: 2, rbi: 6);
    batter.farmStats = PlayerStats(games: 5, atBats: 15, hits: 6, homeRuns: 1, rbi: 3);
    batter.thirdStats = PlayerStats(games: 4, atBats: 12, hits: 4, homeRuns: 0, rbi: 2);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ScoutReport(player: batter, appState: app, team: my, onClose: () {})),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('経歴').first);
    await tester.pumpAndSettle();

    // オープン戦期間中は「2026(OP)」として一時表示される
    expect(find.text('2026(OP)'), findsOneWidget);

    // 開幕前日を経て開幕日（試合開始前）へ日付を進めると、オープン戦の一時表示は消え、2軍・3軍成績も0にリセットされる
    app.currentDate = firstReg.subtract(const Duration(days: 2));
    app.playNextDay(); // _nextStop() により開幕前日を通過して開幕日（firstReg）の試合前に到達
    expect(DateUtils.dateOnly(app.currentDate), DateUtils.dateOnly(firstReg));
    expect(app.openPeriod, isFalse);
    expect(Player.showOpen, isFalse);
    expect(batter.seasonStats.games, 0);
    expect(batter.farmStats.games, 0);
    expect(batter.thirdStats.games, 0);
    expect(batter.career.hits, preCareerHits);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ScoutReport(player: batter, appState: app, team: my, onClose: () {})),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('経歴').first);
    await tester.pumpAndSettle();
    expect(find.text('2026(OP)'), findsNothing);
  });

  test('オフシーズン入団・トレードは仮背番号となり正式決定まで経歴・背番号変遷に残らず開幕前日に一斉決定・移籍は空き番号に記載される', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState(AppDatabase(NativeDatabase.memory()));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    final my = app.teams[0];
    final partner = app.teams[1];
    app.myTeamId = my.id;
    app.seasonFinished = true;

    // 1. オフシーズン（10/31 ドラフト会議日）にドラフト新人が入団すると仮背番号を持ちつつ numberPending=true、年表には背番号が出ない
    app.currentDate = DateTime(2026, 10, 31);
    app.draftDoneYear = 2025; // 2026年のドラフトを実施可能にする
    expect(app.isBeforeOpeningDay(), isTrue);
    final beforeIds = {for (final p in my.players) p.id};
    app.runAutoDraft();
    await app.saveData();
    final rookies = my.players.where((p) => !beforeIds.contains(p.id)).toList();
    expect(rookies, isNotEmpty);
    final firstRookie = rookies.first;
    final tempRookieNum = firstRookie.uniformNumber;
    for (final r in rookies) {
      expect(r.uniformNumber, r.ikusei ? greaterThanOrEqualTo(100) : inInclusiveRange(-1, 99));
      expect(r.numberPending, isTrue);
      expect(r.numberFreeUntil, isEmpty);
      expect(app.numberFreeNow(r), isFalse);
    }
    final rookieJoin = app.chron.lastWhere((c) => c['pid'] == firstRookie.id && c['k'] == 'join');
    expect('${rookieJoin['t']}', isNot(contains('背番号は')));
    expect('${rookieJoin['pt']}', isNot(contains('背番号')));

    // 2. オフシーズン（11/15）のトレードで移籍してきた選手も仮背番号になり、元の球団の背番号変遷には「移籍で空き番号に」が出る
    app.currentDate = DateTime(2026, 11, 15);
    expect(app.isBeforeOpeningDay(), isTrue);
    final giveCands = my.players.where((p) => !p.ikusei && !p.numberPending).toList()
      ..sort((a, b) => RosterEngine.value(b).compareTo(RosterEngine.value(a)));
    final getCands = partner.players.where((p) => !p.ikusei).toList()
      ..sort((a, b) => RosterEngine.value(a).compareTo(RosterEngine.value(b)));
    final give0 = giveCands[0];
    final give0OldNum = give0.uniformNumber;
    final getP = getCands.first;
    final tradeErr = app.proposeTrade(partner, [giveCands[0], giveCands[1]], [getP], 0, givePicks: [(2, my.id)]);
    expect(tradeErr, isNull);
    await app.saveData();
    expect(my.players.contains(getP), isTrue);
    expect(getP.uniformNumber, inInclusiveRange(-1, 99));
    expect(getP.numberPending, isTrue);
    expect(getP.numberFreeUntil, isEmpty);
    expect(app.numberFreeNow(getP), isFalse);

    final myHistBefore = await app.numberHistory(my);
    expect(myHistBefore[tempRookieNum]?.any((e) => e.$2 == firstRookie.registeredName) ?? false, isFalse);
    expect(myHistBefore[give0OldNum]?.any((e) => e.$2 == give0.registeredName && e.$3 == '移籍で空き番号に'), isTrue);

    // 3. 既存選手の背番号変更予約（oldNum -> freeNew）と同時に、ドラフト新人(firstRookie)へ oldNum を予約する
    final existing = my.players.firstWhere((p) => !p.ikusei && !p.numberPending);
    final oldNum = existing.uniformNumber;
    final freeNew = RosterEngine.freeNumber(my, ikusei: false);
    expect(app.setNumber(my, existing, freeNew), isNull);
    expect(app.setNumber(my, firstRookie, oldNum), isNull);
    expect(existing.uniformNumber, oldNum);
    expect(firstRookie.uniformNumber, tempRookieNum);

    // 4. 開幕前日(2027/3/25)の適用で既存選手の変更と新人の正式決定が一斉に反映され、新人の仮番号は経歴・変遷に残らない
    app.applyNextNumbers(DateTime(2027, 3, 25));
    await app.saveData();
    expect(existing.uniformNumber, freeNew);
    expect(existing.nextNumber, isNull);
    expect(firstRookie.uniformNumber, oldNum);
    expect(firstRookie.numberPending, isFalse);
    expect(getP.numberPending, isFalse);

    final tlRookie = await app.playerTimeline(firstRookie);
    expect(tlRookie.any((e) => e.$2.contains('入団') && !e.$2.contains('背番号')), isTrue);
    expect(tlRookie.any((e) => e.$2 == '背番号が${uniformLabel(oldNum)}に決定。'), isTrue);
    expect(tlRookie.any((e) => e.$2.contains('${uniformLabel(tempRookieNum)}から')), isFalse);

    final myHistAfter = await app.numberHistory(my);
    expect(myHistAfter[tempRookieNum]?.any((e) => e.$2 == firstRookie.registeredName) ?? false, isFalse);
    expect(myHistAfter[oldNum]?.any((e) => e.$2.contains(firstRookie.registeredName)), isTrue);

    // 5. シーズン中（開幕後〜ドラフト会議前日：6/15）の支配下登録とトレードでは即座に確定背番号・1か月猶予期間が付与され、入団時の背番号から書き換わる
    app.seasonFinished = false;
    app.currentDate = DateTime(2026, 6, 15);
    expect(app.isBeforeOpeningDay(), isFalse);
    expect(app.isBeforeOpeningDay(DateTime(2026, 10, 30)), isFalse);
    expect(app.isBeforeOpeningDay(DateTime(2026, 10, 31)), isTrue);

    while (RosterEngine.freeSlots(my) <= 1) {
      my.players.removeWhere((p) => !p.ikusei && p.id != existing.id && p.id != firstRookie.id && p.id != getP.id && p.id != my.players.first.id);
      if (RosterEngine.freeSlots(my) <= 1) my.players.removeLast();
    }
    final ik = my.players.firstWhere((p) => p.ikusei, orElse: () => my.players.last..ikusei = true..uniformNumber = 120);
    expect(app.promoteIkusei(ik), isNull);
    await app.saveData();
    expect(ik.ikusei, isFalse);
    expect(ik.uniformNumber, inInclusiveRange(-1, 99));
    expect(ik.numberPending, isFalse);
    expect(ik.numberFreeUntil, '2026-07-15');
    expect(app.numberFreeNow(ik), isTrue);
    final ikOld = ik.uniformNumber;

    final giveSeason = my.players.where((p) => !p.ikusei && p.id != ik.id).toList()
      ..sort((a, b) => RosterEngine.value(b).compareTo(RosterEngine.value(a)));
    final getSeason = partner.players.where((p) => !p.ikusei).toList()
      ..sort((a, b) => RosterEngine.value(a).compareTo(RosterEngine.value(b)));
    final getInSeason = getSeason.first;
    app.lastTradeWith.remove(partner.id);
    expect(app.proposeTrade(partner, [giveSeason[0], giveSeason[1]], [getInSeason], 0, givePicks: [(3, my.id)]), isNull);
    await app.saveData();
    expect(getInSeason.numberPending, isFalse);
    expect(getInSeason.numberFreeUntil, '2026-07-15');
    expect(app.numberFreeNow(getInSeason), isTrue);
    final tradeOld = getInSeason.uniformNumber;

    // 猶予期間中（6/20）の個別変更・一括変更は即時反映され、入団/支配下登録記録が書き換わる
    app.currentDate = DateTime(2026, 6, 20);
    final swapIk = RosterEngine.freeNumber(my, ikusei: false);
    expect(app.setNumber(my, ik, swapIk), isNull);
    expect(ik.uniformNumber, swapIk);
    expect(ik.nextNumber, isNull);

    final swapTrade = RosterEngine.freeNumber(my, ikusei: false);
    expect(app.setNumbersBulk(my, {getInSeason.id: swapTrade}), isNull);
    expect(getInSeason.uniformNumber, swapTrade);
    expect(getInSeason.nextNumber, isNull);

    final tlIk = await app.playerTimeline(ik);
    expect(tlIk.any((e) => e.$2 == '支配下登録。背番号${uniformLabel(swapIk)}。'), isTrue);
    expect(tlIk.any((e) => e.$2.contains('変更')), isFalse);
    final tlTrade = await app.playerTimeline(getInSeason);
    expect(tlTrade.any((e) => e.$2.contains('移籍。背番号${uniformLabel(swapTrade)}。')), isTrue);
    expect(tlTrade.any((e) => e.$2.contains('変更')), isFalse);

    final myHistGrace = await app.numberHistory(my);
    expect(myHistGrace[ikOld]?.any((e) => e.$2.contains(ik.registeredName)) ?? false, isFalse);
    expect(myHistGrace[swapIk]?.any((e) => e.$2.contains(ik.registeredName) && e.$3.contains('支配下登録')), isTrue);
    expect(myHistGrace[tradeOld]?.any((e) => e.$2.contains(getInSeason.registeredName)) ?? false, isFalse);
    expect(myHistGrace[swapTrade]?.any((e) => e.$2.contains(getInSeason.registeredName)), isTrue);

    // 1か月経過後（7/20）は通常通り開幕前日予約に戻る
    app.currentDate = DateTime(2026, 7, 20);
    expect(app.numberFreeNow(ik), isFalse);
    expect(app.numberFreeNow(getInSeason), isFalse);
    final afterGrace = RosterEngine.freeNumber(my, ikusei: false);
    expect(app.setNumber(my, ik, afterGrace), isNull);
    expect(ik.uniformNumber, swapIk);
    expect(ik.nextNumber, afterGrace);
  });

  testWidgets('背番号一括変更画面に仮番号（開幕前日に決定）が表示され保存時に例外が出ない', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late AppState app;
    await tester.runAsync(() async {
      app = AppState(AppDatabase(NativeDatabase.memory()));
      while (!app.loaded) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      final my = app.teams[0];
      app.myTeamId = my.id;
      app.seasonFinished = true;
      app.currentDate = DateTime(2026, 10, 31);
      app.draftDoneYear = 2025;
      app.runAutoDraft();
    });
    final my = app.teams[0];
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: NumberBoardScreen(app: app, team: my)));
    await tester.pumpAndSettle();
    for (var i = 0; i < 40 && find.textContaining('仮番号（開幕前日に決定）').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('仮番号（開幕前日に決定）'), findsWidgets);
    await tester.tap(find.text('決める'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('既存セーブ（開発者版スロット1相当・joinFixV1済）が起動時に自動修復されオフ入団・移籍空き・30日以内変更・猶予期限が整う', () async {
    SharedPreferences.setMockInitialValues({});
    final tmpDir = Directory.systemTemp.createTempSync('slot1_mig_');
    addTearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });
    final dbFile = File('${tmpDir.path}/npb_pennant.sqlite');
    NativeDatabase openTestFileDb() => NativeDatabase(
          dbFile,
          setup: (rawDb) {
            rawDb.execute('PRAGMA journal_mode=WAL;');
            rawDb.execute('PRAGMA synchronous=OFF;');
          },
        );

    final app1 = AppState(AppDatabase(openTestFileDb(), false));
    while (!app1.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    final my = app1.teams[0];
    final partner = app1.teams[1];
    app1.myTeamId = my.id;
    app1.startYear = 2026;
    app1.currentDate = DateTime(2026, 5, 1);

    final initOta = partner.players.firstWhere((p) => !p.ikusei);
    final otaNum = initOta.uniformNumber;
    final rookie = Player(
      id: 'slot1_rookie_6',
      lastName: '新人',
      firstName: '六位',
      isPitcher: true,
      mainPos: '投手',
      age: 19,
      proYears: 1,
      uniformNumber: 23,
      draftInfo: '2026年ドラフト6位（高校・テスト高）',
      draftYear: 2026,
    );
    final inSeasonNew = Player(
      id: 'slot1_inseason_new',
      lastName: '途中',
      firstName: '助っ人',
      isPitcher: false,
      mainPos: '外野手',
      age: 27,
      proYears: 1,
      uniformNumber: 53,
      nationality: '海外',
      draftInfo: '外国人選手（2026年途中に自球団へ入団）',
    );
    final activeGrace = Player(
      id: 'slot1_active_grace',
      lastName: '猶予',
      firstName: '対象',
      isPitcher: true,
      mainPos: '投手',
      age: 24,
      proYears: 1,
      uniformNumber: 62,
      nationality: '海外',
      draftInfo: '外国人選手（2026年途中に自球団へ入団）',
    );
    my.players.addAll([rookie, inSeasonNew, activeGrace]);
    await app1.saveData(); // _rosterSnap へ登録（その後、旧セーブ状態として年表とフラグを上書き保存する）

    // 旧仕様の記録：
    // ・10/31 ドラフト入団に仮番号25が書かれ、開幕前に25→23へ変更
    // ・2/1 に太田が移籍（numなし）
    // ・4/10 シーズン中入団（45）→ 4/20 変更（45→53）の30日以内変更が残っている
    // ・4/20 シーズン中入団（62）で numberFreeUntil が空のまま現在5/1（30日以内）
    rookie.numberPending = false;
    rookie.numberFreeUntil = '';
    inSeasonNew.numberPending = false;
    inSeasonNew.numberFreeUntil = '';
    activeGrace.numberPending = false;
    activeGrace.numberFreeUntil = '';
    app1.chronYears[2026] = [
      {
        'd': '2025-10-31',
        'team': my.id,
        'k': 'join',
        't': '投手 ${rookie.registeredName}(18)がドラフト6位（高校・テスト高）で入団。背番号は25。',
        'pid': rookie.id,
        'pt': '高卒ドラフト6位で${my.name}に入団（テスト高）。背番号25。',
      },
      {
        'd': '2026-02-01',
        'team': my.id,
        'k': 'number',
        't': '投手 ${rookie.registeredName}の背番号を25から23に変更。',
        'pid': rookie.id,
        'pt': '背番号を25から23に変更。',
      },
      {
        'd': '2026-02-01',
        'team': partner.id,
        'k': 'leave',
        't': '${initOta.isPitcher ? '投手' : initOta.mainPosition} ${initOta.registeredName}(${initOta.age})がトレードで${my.shortName}へ移籍。',
        'pid': initOta.id,
      },
      {
        'd': '2026-04-10',
        'team': my.id,
        'k': 'join',
        't': '外野手 ${inSeasonNew.registeredName}(27)がテスト入団。背番号は45。',
        'pid': inSeasonNew.id,
        'pt': 'テスト入団で${my.name}に入団。背番号45。',
      },
      {
        'd': '2026-04-20',
        'team': my.id,
        'k': 'number',
        't': '外野手 ${inSeasonNew.registeredName}の背番号を45から53に変更。',
        'pid': inSeasonNew.id,
        'pt': '背番号を45から53に変更。',
      },
      {
        'd': '2026-04-20',
        'team': my.id,
        'k': 'join',
        't': '投手 ${activeGrace.registeredName}(24)がテスト入団。背番号は62。',
        'pid': activeGrace.id,
        'pt': 'テスト入団で${my.name}に入団。背番号62。',
      },
    ];
    app1.chronFirstYear = 2026;
    await app1.saveData();
    // すでに joinFixV1='1' かつ chronNumberFixV2 未適用の既存セーブ状態を再現して再起動
    await app1.db.setKv('joinFixV1', '1');
    await app1.db.deleteKv('chronNumberFixV2');
    await app1.db.close();

    final app = AppState(AppDatabase(openTestFileDb(), false));
    while (!app.loaded) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    await app.saveData();
    addTearDown(() async => app.db.close());

    final myReloaded = app.teams[0];
    final partnerReloaded = app.teams[1];
    final rReloaded = myReloaded.players.firstWhere((p) => p.id == rookie.id);
    final inNewReloaded = myReloaded.players.firstWhere((p) => p.id == inSeasonNew.id);
    final graceReloaded = myReloaded.players.firstWhere((p) => p.id == activeGrace.id);

    // 1. 新人の年表が「10/31 入団（背番号なし）」「3/25 背番号が23に決定。」になっていること
    final tl = await app.playerTimeline(rReloaded);
    expect(tl.any((e) => e.$1.month == 10 && e.$1.day == 31 && e.$2.contains('ドラフト6位') && !e.$2.contains('25')), isTrue);
    expect(tl.any((e) => e.$1.month == 3 && e.$2 == '背番号が23に決定。'), isTrue);
    expect(tl.any((e) => e.$2.contains('25から')), isFalse);

    // 2. 背番号変遷：25番に仮番号が残らず、23番に決定が記録され、太田の元番号は「移籍で空き番号に」として出ること
    final myHist = await app.numberHistory(myReloaded);
    expect(myHist[25]?.any((e) => e.$2 == rookie.registeredName) ?? false, isFalse);
    expect(myHist[23]?.any((e) => e.$2 == rookie.registeredName && e.$3 == '背番号決定'), isTrue);

    final pHist = await app.numberHistory(partnerReloaded);
    expect(pHist[otaNum]?.any((e) => e.$1 == '2026-02-01' && e.$2 == initOta.registeredName && e.$3 == '移籍で空き番号に'), isTrue);

    // 3. シーズン中の30日以内変更（45→53）が入団時の背番号（53）へ統合され、45番にも変更にも残らないこと
    final tlIn = await app.playerTimeline(inNewReloaded);
    expect(tlIn.any((e) => e.$2.contains('背番号53。')), isTrue);
    expect(tlIn.any((e) => e.$2.contains('45')), isFalse);
    expect(tlIn.any((e) => e.$2.contains('変更')), isFalse);
    expect(myHist[45]?.any((e) => e.$2 == inSeasonNew.registeredName) ?? false, isFalse);
    expect(myHist[53]?.any((e) => e.$1 == '2026-04-10' && e.$2 == inSeasonNew.registeredName), isTrue);

    // 4. 現在5/1時点で入団30日以内の選手に numberFreeUntil ('2026-05-20') が復元されていること
    expect(graceReloaded.numberFreeUntil, '2026-05-20');
    expect(app.numberFreeNow(graceReloaded), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
