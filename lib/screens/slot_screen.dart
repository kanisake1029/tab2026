import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/app_database.dart';
import '../providers/app_state.dart';
import 'start_screen.dart';

/// いま開いているプレイデータ（顔アイコンのユニフォームなど、アプリ全体から使う）
AppState? currentApp;

/// 最初の画面：プレイデータ1〜3を選ぶ。保存があれば続きから、空いていれば新しく始める。消去するとその枠が空く
class SlotScreen extends StatefulWidget {
  /// 開いたプレイデータの本編の画面
  final Widget Function(AppState app) mainOf;
  const SlotScreen({super.key, required this.mainOf});

  @override
  State<SlotScreen> createState() => _SlotScreenState();
}

class _Slot {
  final bool has;
  final Map<String, dynamic>? sum;
  const _Slot(this.has, this.sum);
}

class _SlotScreenState extends State<SlotScreen> {
  static const _green = Color(0xFF0F2A1D);
  static const _greenText = Color(0xFF9CC7AE);
  static const _gold = Color(0xFFF2C230);
  static const slots = [1, 2, 3];

  final Map<int, _Slot> _info = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    for (final n in slots) {
      final s = prefs.getString('slotSummary_$n');
      Map<String, dynamic>? sum;
      if (s != null) {
        try {
          sum = jsonDecode(s) as Map<String, dynamic>;
        } catch (_) {}
      }
      var has = false;
      if (currentApp?.slot == n) {
        has = currentApp!.teams.isNotEmpty;
      } else if (sum != null) {
        has = true;
      } else if (n == 1) {
        // プレイデータ1のみ、要約キャッシュが無い古い形式や初期データの存在をDBで確認する
        if (prefs.getString('teamsData') != null) {
          has = true;
        } else {
          final db = AppDatabase.forSlot(n);
          try {
            has = await db.hasData().timeout(const Duration(seconds: 5), onTimeout: () => false);
          } catch (_) {}
          try {
            await db.close().timeout(const Duration(seconds: 2));
          } catch (_) {}
        }
      }
      // 開いただけで始めていない枠は空き扱い（要約は球団を決めて始めると書かれる）。プレイデータ1の以前の保存は除く
      if (has && sum == null && n != 1) has = false;
      _info[n] = _Slot(has, has ? sum : null);
    }
    if (mounted) setState(() {});
  }

  Future<AppState> _load(int n) async {
    final cur = currentApp;
    if (cur != null && cur.slot == n) return cur;
    if (cur != null) {
      await cur.saveData();
      await cur.db.close();
      currentApp = null;
    }
    final a = AppState(AppDatabase.forSlot(n), n);
    while (!a.loaded) {
      await Future.delayed(const Duration(milliseconds: 30));
    }
    currentApp = a;
    return a;
  }

  Future<void> _open(int n) async {
    if (_busy) return;
    setState(() => _busy = true);
    final has = _info[n]?.has ?? false;
    final a = await _load(n);
    final cont = has && a.teams.any((t) => t.id == a.myTeamId);
    if (!cont) await a.addStoredTeams(); // 新しく始める：新規作成チーム（ほかのプレイデータの球団も）を選べるように
    if (!mounted) return;
    setState(() => _busy = false);
    if (cont) {
      // 続きから
      a.onTeamChosen();
      a.updateAndSave();
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => widget.mainOf(a)));
    } else {
      // 新しく始める（年度・球団を選ぶ）
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StartScreen(appState: a, mainAppScreen: widget.mainOf(a), newOnly: true)));
    }
    _refresh();
  }

  Future<void> _erase(int n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('プレイデータ$n を消去'),
        content: const Text('このプレイデータの試合・成績・選手の移籍などがすべて消え、枠が空きます。元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('やめる')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(c, true), child: const Text('消去する')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    if (currentApp?.slot == n) {
      await currentApp!.db.close();
      currentApp = null;
    }
    final db = AppDatabase.forSlot(n);
    // 消す前に、この枠の新規作成チームの初期状態を残す（ほかの枠で新しく始めるときに使える）
    try {
      await AppState.templatesFromDb(db);
    } catch (_) {}
    await db.wipeAll();
    await db.close();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('slotSummary_$n');
    if (n == 1) await prefs.remove('teamsData'); // 古い形式の保存も消す
    _busy = false;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _green,
      body: SafeArea(
        child: Stack(children: [
          ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 24), children: [
            const Text('The Authentic', style: TextStyle(color: Color(0xFFEAF5EE), fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const Text('Baseball 2026', style: TextStyle(color: Color(0xFFEAF5EE), fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 1.2, height: 1.1)),
            const Row(
              children: [
                Text('プロ野球ペナントシミュレーション', style: TextStyle(color: _greenText, fontSize: 13)),
                SizedBox(width: 8),
                Text('v1.0.4', style: TextStyle(color: _gold, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 24),
            const Text('プレイデータを選ぶ', style: TextStyle(color: _greenText, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final n in slots) Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(n)),
          ]),
          if (_busy) const ColoredBox(color: Color(0x66000000), child: Center(child: CircularProgressIndicator())),
        ]),
      ),
    );
  }

  Widget _card(int n) {
    final s = _info[n];
    final has = s?.has ?? false;
    final sum = s?.sum;
    String sub = '';
    if (sum != null) {
      final d = DateTime.tryParse(sum['date'] as String? ?? '');
      sub = '${d == null ? '' : '${d.year}年${d.month}月${d.day}日'}　${sum['w']}勝${sum['l']}敗${sum['d']}分';
    }
    return Material(
      color: has ? _gold : const Color(0xFF1C4430),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: s == null ? null : () => _open(n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: has ? _green : Colors.transparent, border: has ? null : Border.all(color: _greenText)),
              child: Text('$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: has ? _gold : _greenText)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  s == null ? '読み込み中…' : (has ? (sum?['team'] as String? ?? 'プレイデータ$n') : '空き　新しく始める'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: has ? _green : const Color(0xFFEAF5EE)),
                ),
                Text(
                  has ? (sub.isEmpty ? '保存あり（開くと続きから）' : sub) : 'リーグ・自球団・年度を決めて始めます',
                  style: TextStyle(fontSize: 12, color: has ? _green : _greenText),
                ),
              ]),
            ),
            if (has)
              IconButton(
                tooltip: '消去',
                icon: const Icon(Icons.delete_outline, color: _green),
                onPressed: () => _erase(n),
              ),
          ]),
        ),
      ),
    );
  }
}
