import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return a;
}

/// 他リーグの選手に声をかける：独立リーグの NPB 未経験者はドラフトを通す・3A のくすぶりは受けやすい・契約すると NPB へ
void main() {
  test('声をかける', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    a.myTeamId = a.teams[1].id;
    final w = a.otherWorld!;
    final indie = w.teamsOf('JP1').first.players.first;
    expect(a.otherOfferBlock(indie), contains('ドラフト'));
    final aaa = w.teamsOf('AAA').expand((t) => t.players).where((p) => p.age >= 27).first;
    final mlbStar = w.teamsOf('MLB').expand((t) => t.players).reduce((x, y) => x.ovr > y.ovr ? x : y);
    expect(a.otherAcceptChance(aaa), greaterThan(a.otherAcceptChance(mlbStar)));
    // 元NPB の印があると受けやすい
    final before = a.otherAcceptChance(aaa);
    w.fromNpb[aaa.id] = 'テスト';
    expect(a.otherAcceptChance(aaa), greaterThan(before));
    // 受けてくれるまで（週ごとの乱数なので、日付をずらして）申し込む
    String? err = 'x';
    for (var i = 0; i < 30 && err != null; i++) {
      err = a.offerOtherPlayer(aaa);
      if (err != null && !err.contains('断られ')) break;
      a.currentDate = a.currentDate.add(const Duration(days: 7));
    }
    expect(err, isNull, reason: '$err');
    expect(a.myTeam!.players.contains(aaa), true);
    expect(a.otherPlayer(aaa.id), isNull);
    expect(w.fromNpb.containsKey(aaa.id), false);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
