import '../models/player.dart';
import '../models/team.dart';

/// リーグ規定（オフ〜オープン戦の間に変えられる）：リーグごとの DH の有無、外国人枠（1軍登録・ベンチ入り。null＝廃止）
class LeagueRules {
  static bool dhCL = true; // A リーグ
  static bool dhPL = true; // B リーグ
  static int? foreign1G = 5; // 1軍に登録できる外国人枠の選手（null＝制限なし）
  static int? foreignBench = 4; // そのうち試合のベンチに入れる人数（null＝制限なし）

  static const foreign1GChoices = <int?>[3, 4, 5, 6, 7, null];
  static const foreignBenchChoices = <int?>[2, 3, 4, 5, 6, null];

  /// その試合で DH を使うか：ホーム球団のリーグの規定（交流戦・日本シリーズも同じ）。オールスターは使う
  static bool dhFor(Team home, String matchType) {
    if (matchType == 'ALLSTAR' || home.id.endsWith('_ALLSTAR')) return true;
    return home.league == 'CL' ? dhCL : dhPL;
  }

  static bool under1G(int count) => foreign1G == null || count < foreign1G!;
  static bool underBench(int count) => foreignBench == null || count < foreignBench!;
  static int benchCap(int fallback) => foreignBench ?? fallback;

  static String limitText(int? v) => v == null ? '制限なし（廃止）' : '$v人まで';

  static Map<String, dynamic> toJson() => {'dhCL': dhCL, 'dhPL': dhPL, 'f1': foreign1G ?? -1, 'fb': foreignBench ?? -1};

  static void load(Map<String, dynamic>? j) {
    dhCL = j?['dhCL'] ?? true;
    dhPL = j?['dhPL'] ?? true;
    final f1 = j?['f1'] ?? 5, fb = j?['fb'] ?? 4;
    foreign1G = f1 is int && f1 >= 0 ? f1 : null;
    foreignBench = fb is int && fb >= 0 ? fb : null;
  }

  /// 試合用のオーダー：DH の有無をその試合の規定に合わせる
  ///  DH なし：DH を外し、先発投手が 9 番に入る。DH あり（投手が打順にいる）：ベンチの打者から 1 人を投手の打順に入れる
  static List<LineupEntry> gameLineup(Team t, Player starter, bool dh) {
    final l = [for (final e in t.lineup) LineupEntry(playerId: e.playerId, position: e.position)];
    final pi = l.indexWhere((e) => e.position == '投');
    final di = l.indexWhere((e) => e.position == 'DH');
    if (!dh) {
      if (di >= 0) {
        l.removeAt(di);
        l.add(LineupEntry(playerId: starter.id, position: '投'));
      } else if (pi >= 0) {
        l[pi].playerId = starter.id; // 今日の先発が打つ
      }
    } else if (pi >= 0) {
      final used = {for (final e in l) e.playerId};
      final byId = {for (final p in t.players) p.id: p};
      final bench = [
        for (final id in t.active26.isNotEmpty ? t.active26 : t.roster1G)
          if (byId[id] != null && !byId[id]!.isPitcher && !used.contains(id) && byId[id]!.injuryDays == 0) byId[id]!,
      ]..sort((a, b) => (b.contact + b.power).compareTo(a.contact + a.power));
      if (bench.isNotEmpty) l[pi] = LineupEntry(playerId: bench.first.id, position: 'DH');
    }
    return l;
  }
}
