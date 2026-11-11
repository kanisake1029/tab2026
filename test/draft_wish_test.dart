import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/draft_wish.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  return a;
}

/// 仕様書 1.2・1.3：志望届・希望球団・国内FA の短縮
void main() {
  test('志望届と国内FA の短縮', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await boot(AppDatabase(NativeDatabase.memory()));
    a.myTeamId = a.teams[1].id;
    final s = a.createDraftSession();
    expect(a.prospects.every((p) => p.wishFiled), true, reason: 'ドラフト会議の前に全員が志望届を出す');
    final none = a.prospects.where((p) => p.wishes.isEmpty).length;
    expect(none, greaterThan(20), reason: '希望なしもいる');
    expect(none, lessThan(a.prospects.length ~/ 2));
    expect(a.prospects.every((p) => p.wishes.length <= 3), true);
    // 希望が特定の球団に偏りすぎない
    final firsts = <String, int>{};
    for (final p in a.prospects.where((p) => p.wishes.isNotEmpty)) {
      firsts[p.wishes.first] = (firsts[p.wishes.first] ?? 0) + 1;
    }
    expect(firsts.length, greaterThanOrEqualTo(8), reason: '1希望が多くの球団に散らばる: $firsts');
    s.runAll();
    a.applyDraft(s);
    for (final pk in s.picks) {
      final p = a.teams.expand((t) => t.players).firstWhere((x) => x.id == pk.prospect.id);
      expect(p.faShort, DraftWish.faShortFor(pk.prospect, pk.teamId));
      expect(p.faNeed, Player.faYears - p.faShort);
    }
    expect(s.picks.any((pk) => DraftWish.faShortFor(pk.prospect, pk.teamId) == 2), true, reason: '希望外の入団もある');
  });
}
