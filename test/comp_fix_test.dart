import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/db/app_database.dart';
import 'package:npb_pennant_app/engine/roster_engine.dart';
import 'package:npb_pennant_app/engine/transfer_engine.dart';
import 'package:npb_pennant_app/models/player.dart';
import 'package:npb_pennant_app/providers/app_state.dart';
import 'package:npb_pennant_app/utils/standings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> boot(AppDatabase db) async {
  final a = AppState(db);
  while (!a.loaded) { await Future.delayed(const Duration(milliseconds: 10)); }
  return a;
}

void main() {
  test('そのオフに獲った選手は人的補償の対象外・誤った補償の取り消し・同じ選手が2球団にいるときの整理・外国人の8年', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    final a = await boot(db);
    a.autoMode = true;
    a.myTeamId = a.teams.first.id;
    final y = a.offseasonYear;
    final A = a.teams[1], B = a.teams[2], C = a.teams[3];
    // 1) そのオフに獲った選手は対象外
    final x = A.players.firstWhere((p) => !p.ikusei && !p.foreignSlot && p.draftYear != y);
    expect(TransferEngine.protectEligible(A, y).contains(x), isTrue);
    x.offJoin = y;
    expect(TransferEngine.protectEligible(A, y).contains(x), isFalse);
    // 2) 誤った補償：A が FA で獲った x が、補償で B に移っていた
    x.moves.add('$y年12月1日 FA 移籍でAへ');
    final fa = A.players.firstWhere((p) => p.id != x.id && !p.ikusei);
    a.transactions.insert(0, '$y/11/20 ${fa.registeredName} FA 移籍 ${teamShort(B)} → ${teamShort(A)}（Aランク・1億×3年）');
    RosterEngine.removePlayer(A, x);
    RosterEngine.addPlayer(B, x);
    a.transactions.insert(0, '$y/12/3 ${x.registeredName} 人的補償 ${teamShort(A)} → ${teamShort(B)}（${fa.registeredName}の補償）');
    // 3) 同じ選手が2球団に（自球団と C）
    final dup = a.teams.first.players.firstWhere((p) => !p.isPitcher);
    C.players.add(dup);
    // 4) 外国人：国内FA と同じ8年で日本人扱い
    final f = a.teams.expand((t) => t.players).firstWhere((p) => p.nationality == '海外');
    f.faService = Player.faYears - 1;
    expect(f.foreignSlot, isTrue);
    f.faService = Player.faYears;
    expect(f.foreignSlot, isFalse);
    expect(f.hasFA, f.ikusei ? isFalse : isTrue);
    await a.saveData();
    final b = await boot(db);
    final bA = b.teams[1], bB = b.teams[2], bC = b.teams[3];
    expect(bA.players.any((p) => p.id == x.id), isTrue, reason: '補償は取り消されて A に戻る');
    expect(bB.players.any((p) => p.id == x.id), isFalse);
    expect(b.transactions.any((l) => l.contains('${x.registeredName} 人的補償')), isFalse);
    expect(bC.players.any((p) => p.id == dup.id), isFalse, reason: '重複は自球団だけに残す');
    expect(b.teams.first.players.any((p) => p.id == dup.id), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
