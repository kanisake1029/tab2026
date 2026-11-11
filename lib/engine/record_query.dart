import '../models/player.dart';
import 'pre_career.dart';

/// 1試合分の選手の記録（ボックススコアの glog、無い試合は名前の付いた成績から）
class GameLine {
  final DateTime date;
  final int dh; // ダブルヘッダーの順（同じ日の並び）
  final String teamId, oppId;
  final Map<String, dynamic> v; // 打者：ab h 2b 3b hr rbi bb so sb r seq、投手：p{outs er so bb dec st}
  GameLine(this.date, this.dh, this.teamId, this.oppId, this.v);

  bool get batted => v.containsKey('ab') || (v['seq'] ?? '') != '';
  Map? get pit => v['p'] as Map?;
  int n(String k) => (v[k] ?? 0) as int;
  int pn(String k) => (pit?[k] ?? 0) as int;
  int get pa => n('ab') + n('bb') + ((v['seq'] ?? '') as String).replaceAll(RegExp('[^S]'), '').length;
}

/// 節目の種類：表示名 → (打者か、ゲームの記録の値、通算の値、しきい値の候補)
class MilestoneKind {
  final String label;
  final bool batter;
  final int Function(GameLine g) game;
  final int Function(PlayerStats s) total;
  final List<int> marks;
  const MilestoneKind(this.label, this.batter, this.game, this.total, this.marks);

  static final all = <MilestoneKind>[
    MilestoneKind('安打', true, (g) => g.n('h'), (s) => s.hits, const [100, 500, 1000, 1500, 2000, 2500, 3000]),
    MilestoneKind('本塁打', true, (g) => g.n('hr'), (s) => s.homeRuns, const [50, 100, 150, 200, 250, 300, 400, 500]),
    MilestoneKind('打点', true, (g) => g.n('rbi'), (s) => s.rbi, const [100, 500, 1000, 1500]),
    MilestoneKind('盗塁', true, (g) => g.n('sb'), (s) => s.stolenBases, const [50, 100, 200, 300, 400]),
    MilestoneKind('試合出場', true, (g) => g.batted ? 1 : 0, (s) => s.games, const [500, 1000, 1500, 2000, 2500]),
    MilestoneKind('勝利', false, (g) => g.pit?['dec'] == '勝' ? 1 : 0, (s) => s.wins, const [50, 100, 150, 200, 250]),
    MilestoneKind('奪三振', false, (g) => g.pn('so'), (s) => s.pitcherStrikeouts, const [500, 1000, 1500, 2000, 2500, 3000]),
    MilestoneKind('セーブ', false, (g) => g.pit?['dec'] == 'S' ? 1 : 0, (s) => s.saves, const [50, 100, 150, 200, 250, 300]),
    MilestoneKind('ホールド', false, (g) => g.pit?['dec'] == 'H' ? 1 : 0, (s) => s.holds, const [50, 100, 150, 200, 250, 300]),
    MilestoneKind('登板', false, (g) => g.pit != null ? 1 : 0, (s) => s.pitchApps, const [300, 500, 700, 800, 900]),
  ];
}

/// 節目を達成した1人
class MilestoneHit {
  final Player p;
  final int gameNo; // 何試合目（投手は何登板目）で達成
  final DateTime? date; // ゲームの中で達成した日（開始前は null）
  final int year;
  final int age;
  final bool estimated;
  MilestoneHit(this.p, this.gameNo, this.date, this.year, this.age, this.estimated);
}

/// 連続記録の1つ
class StreakHit {
  final Player p;
  final int len;
  final DateTime start, end;
  final bool active; // 継続中
  StreakHit(this.p, this.len, this.start, this.end, this.active);
}

class StreakKind {
  final String label;
  final bool batter;
  final String unit;
  const StreakKind(this.label, this.batter, this.unit);
  static const all = [
    StreakKind('連続試合安打', true, '試合'),
    StreakKind('連続試合出塁', true, '試合'),
    StreakKind('連続試合本塁打', true, '試合'),
    StreakKind('連続打数安打', true, '打数'),
    StreakKind('連続試合出場', true, '試合'),
    StreakKind('救援での連続試合無失点', false, '試合'),
    StreakKind('連続試合無失点のイニング', false, '回'),
  ];
}

class RecordQuery {
  static int ageAt(Player p, DateTime d) {
    final b = DateTime.tryParse(p.birthDate);
    if (b == null) return p.age;
    var a = d.year - b.year;
    if (d.month < b.month || (d.month == b.month && d.day < b.day)) a--;
    return a;
  }

  /// 節目の達成者（試合数・年齢・日付を付けて）。total：今の通算、logs：ゲームの中の試合（古い順）、pre：開始前の推定の年度
  static MilestoneHit? milestone(Player p, MilestoneKind k, int mark, PlayerStats total, List<GameLine> logs, List<PreYear> pre) {
    final have = k.total(total);
    if (have < mark) return null;
    int apps(GameLine g) => k.batter ? (g.batted ? 1 : 0) : (g.pit != null ? 1 : 0);
    final logSum = logs.fold<int>(0, (a, g) => a + k.game(g));
    final logApps = logs.fold<int>(0, (a, g) => a + apps(g));
    final base = (have - logSum).clamp(0, 1 << 30);
    final baseApps = ((k.batter ? total.games : total.pitchApps) - logApps).clamp(0, 1 << 30);
    if (base >= mark) {
      // ゲーム開始前に達成：推定の年度から、その年の途中の何試合目かを見積もる
      var cum = 0, cumApps = 0;
      for (final y in pre) {
        final v = k.total(y.stats), a = k.batter ? y.stats.games : y.stats.pitchApps;
        if (cum + v >= mark && v > 0) {
          final frac = (mark - cum) / v;
          final b = DateTime.tryParse(p.birthDate);
          return MilestoneHit(p, cumApps + (a * frac).ceil().clamp(1, a == 0 ? 1 : a), null, y.year, b == null ? p.age : y.year - b.year, true);
        }
        cum += v;
        cumApps += a;
      }
      return MilestoneHit(p, baseApps, null, 0, p.age, true);
    }
    var cum = base, g = baseApps;
    for (final l in logs) {
      g += apps(l);
      cum += k.game(l);
      if (cum >= mark) return MilestoneHit(p, g, l.date, l.date.year, ageAt(p, l.date), false);
    }
    return null;
  }

  /// 連続記録（ゲームの中の試合から）。teamGames：球団 → 公式戦の日（並び順のキー）。minLen 以上をすべて
  static List<StreakHit> streaks(Player p, StreakKind k, List<GameLine> logs, Map<String, List<String>> teamGames, int minLen) {
    final out = <StreakHit>[];
    var len = 0;
    DateTime? s0, s1;
    void close({bool active = false}) {
      if (len >= minLen && s0 != null) out.add(StreakHit(p, len, s0!, s1!, active));
      len = 0;
      s0 = null;
    }

    void step(bool ok, DateTime d, {int add = 1}) {
      if (ok) {
        if (len == 0) s0 = d;
        len += add;
        s1 = d;
      } else {
        close();
      }
    }

    String key(GameLine g) => '${g.date.toIso8601String().substring(0, 10)}#${g.dh}';
    GameLine? prev;
    for (final g in logs) {
      switch (k.label) {
        case '連続試合安打':
          if (g.pa > 0) step(g.n('h') > 0, g.date);
        case '連続試合出塁':
          if (g.pa > 0) step(g.n('h') + g.n('bb') + ((g.v['seq'] ?? '') as String).replaceAll(RegExp('[^B]'), '').length > 0, g.date);
        case '連続試合本塁打':
          if (g.pa > 0) step(g.n('hr') > 0, g.date);
        case '連続打数安打':
          for (final c in ((g.v['seq'] ?? '') as String).split('')) {
            if (c == 'H') step(true, g.date);
            if (c == 'O' || c == 'K') step(false, g.date);
          }
        case '連続試合出場':
          if (!g.batted) break;
          // 同じ球団の公式戦が間にあれば途切れている
          if (prev != null) {
            final tg = teamGames[g.teamId] ?? const <String>[];
            final i0 = tg.indexOf(key(prev)), i1 = tg.indexOf(key(g));
            if (prev.teamId != g.teamId || i0 < 0 || i1 != i0 + 1) close();
          }
          step(true, g.date);
          prev = g;
        case '救援での連続試合無失点':
          if (g.pit != null && g.pn('st') == 0) step(g.pn('er') == 0, g.date);
        case '連続試合無失点のイニング':
          if (g.pit != null) step(g.pn('er') == 0, g.date, add: g.pn('outs'));
      }
    }
    close(active: true);
    return out;
  }
}
