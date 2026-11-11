import 'dart:convert';
import 'league_rules_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../widgets/initial_data_export.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';
import 'balance_lab_screen.dart';
import '../ai/ai_settings_panel.dart';

/// 設定・編集（デザイン案B：左メニュー＋右に中身）
///  左：編集（リーグ編成・チーム・選手編集）／データ（固有12を初期状態に戻す）／開発者オプション
///  右：選んだ項目の中身をそのまま表示する
///  狭い画面では、メニューの一覧から選ぶと中身を別ページで開く
///  開発者オプションは、デバッグ実行時か、タイトルを5回タップすると表示
class SettingsMenuScreen extends StatefulWidget {
  final AppState appState;
  const SettingsMenuScreen({super.key, required this.appState});

  @override
  State<SettingsMenuScreen> createState() => _SettingsMenuScreenState();
}

const _green = Color(0xFF0F3D2E);
const _mint = Color(0xFFE8F5EC);

enum _Item { league, editor, leagueRules, rules, ai, lab, backupOut, backupIn, reset, devEditor, devExport, devSkip }

class _SettingsMenuScreenState extends State<SettingsMenuScreen> {
  int _titleTaps = 0;
  bool get _devVisible => kDebugMode || _titleTaps >= 5; // タイトルを5回タップで開発者オプションを表示
  _Item _sel = _Item.editor;

  AppState get app => widget.appState;

  Future<void> _skipSeason() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Expanded(child: Text('シーズンを進めています…'))])),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50)); // ダイアログを先に描く
    await app.playUntilSeasonEnd();
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.seasonOver ? 'シーズンを最後まで進めました。ホームで「シーズンを終えて来季へ」を押せます' : '進められませんでした（${app.unplayedSummary()}）')));
  }

  Future<void> _exportBackup() async {
    final d = app.currentDate;
    final name = 'npb_save_${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.json';
    try {
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(app.exportSaveJson())),
        mimeType: 'application/json',
        dialogTitle: 'バックアップの保存先',
      );
      if (mounted && uri != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name を書き出しました')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('書き出せませんでした: $e')));
    }
  }

  Future<void> _importBackup() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.any, dialogTitle: 'バックアップを選ぶ');
      if (f == null || !mounted) return;
      final ok = await app.importSaveJson(utf8.decode(await f.readAsBytes()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'バックアップを読み込みました' : 'このファイルは読み込めません（このゲームのバックアップではありません）')));
      if (ok) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('読み込めませんでした: $e')));
    }
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('固有12を初期状態に戻しますか？'),
        content: const Text('固有12球団の名前・選手・能力・オーダーの編集内容がすべて破棄され、シーズンも最初からになります。新規作成したチームは残ります。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('初期状態に戻す')),
        ],
      ),
    );
    if (ok == true) {
      await app.resetToInitialTeams();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('固有12を初期状態に戻しました')));
        setState(() {});
      }
    }
  }

  List<(String, _Item, String, String)> get _menu => [
        ('編集', _Item.league, 'リーグ編成', '各リーグの6球団を選ぶ'),
        ('', _Item.editor, 'チーム・選手編集', '能力・持ち球・年俸／新しいチーム'),
        ('', _Item.leagueRules, 'リーグ規定', '試合数・DH・外国人枠（オフに変更）'),
        ('', _Item.rules, 'ゲームの設定', 'オーナーによる解任'),
        ('', _Item.lab, 'バランス検証', '投球・打球・守備・走塁・環境を試合の写しで確かめる'),
        ('データ', _Item.backupOut, 'バックアップを書き出す', 'セーブデータをファイルに保存'),
        ('', _Item.backupIn, 'バックアップを読み込む', '保存したファイルから復元'),
        ('', _Item.reset, '固有12を初期状態に戻す', '元に戻せません'),
        if (_devVisible) ('開発者', _Item.devEditor, '固有12 初期データを編集', '同梱データを書き換え'),
        if (_devVisible) ('', _Item.devExport, '固有12 初期データを書き出し', 'ソースとして出力'),
        if (_devVisible) ('', _Item.devSkip, 'シーズンを最後まで進める', '確認用：全試合を自動で消化'),
      ];

  Widget _content(_Item item, {required bool embedded}) {
    switch (item) {
      case _Item.ai:
        return const AiSettingsPanel();
      case _Item.lab:
        return BalanceLabPanel(app: app);
      case _Item.league:
        return SettingsScreen(appState: app, embedded: embedded);
      case _Item.editor:
      case _Item.devEditor:
        return EditorScreen(key: ValueKey(item), appState: app, embedded: embedded);
      case _Item.leagueRules:
        return LeagueRulesPanel(app: app);
      case _Item.rules:
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('ゲームの設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('オーナーによる解任'),
            subtitle: const Text('オン：満足度が20未満、または2年続けて35未満だと解任されます（他球団のオファーを受けるか、はじめからやり直す）\nオフ：解任されません'),
            value: app.ownerFiring,
            onChanged: (v) {
              setState(() => app.ownerFiring = v);
              app.updateAndSave();
            },
          ),
        ]);
      case _Item.backupOut:
        return _panel(
          title: 'バックアップを書き出す',
          body: 'いまのセーブデータ（チーム・選手・日程・試合結果）を、1つのファイルに保存します。\n機種を変えるときや、ブラウザの保存領域が消えたときの備えにしてください。',
          button: '書き出す',
          onPressed: _exportBackup,
        );
      case _Item.backupIn:
        return _panel(
          title: 'バックアップを読み込む',
          body: '書き出したファイルを選ぶと、いまのセーブデータをそのファイルの内容に置き換えます。\n元に戻せないので、必要なら先に書き出しておいてください。',
          button: 'ファイルを選ぶ',
          onPressed: _importBackup,
        );
      case _Item.reset:
        return _panel(
          title: '固有12を初期状態に戻す',
          danger: true,
          body: '固有12球団の名前・選手・能力・オーダーの編集内容をすべて破棄し、シーズンも最初からにします。\n新規作成したチームは残ります。この操作は元に戻せません。',
          button: '初期状態に戻す',
          onPressed: _confirmReset,
        );
      case _Item.devSkip:
        return _panel(
          title: 'シーズンを最後まで進める',
          body: '確認用の機能です。今日以降の全試合を自動で消化して、シーズンの終わり（年度更新）を試せるようにします。\n自チームの試合も自動で進みます。',
          button: '最後まで進める',
          onPressed: _skipSeason,
        );
      case _Item.devExport:
        return _panel(
          title: '固有12 初期データを書き出し',
          body: 'いまの固有12のデータを、ゲームに同梱する初期データ（Dart のソース）としてコピーできる形で出力します。\n開発者向けの機能です。',
          button: '書き出す',
          onPressed: () => showInitialDataExport(context, app),
        );
    }
  }

  Widget _panel({required String title, required String body, required String button, required VoidCallback onPressed, bool danger = false}) {
    return Container(
      color: const Color(0xFFEEF1F5),
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: danger ? const Color(0xFFFCA5A5) : const Color(0xFFDCE2EA)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text(body, style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF475569))),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(backgroundColor: danger ? const Color(0xFFB91C1C) : const Color(0xFF4338CA), minimumSize: const Size(160, 46)),
              child: Text(button, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }

  String _titleOf(_Item item) => _menu.firstWhere((m) => m.$2 == item, orElse: () => ('', item, '設定・編集', '')).$3;

  Widget _sidebar({required bool narrow}) {
    final tiles = <Widget>[];
    for (final m in _menu) {
      if (m.$1.isNotEmpty) {
        tiles.add(Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
          child: Text(m.$1, style: const TextStyle(fontSize: 11, letterSpacing: 2, color: Color(0xFF86C9A0))),
        ));
      }
      final sel = !narrow && _sel == m.$2;
      final danger = m.$2 == _Item.reset;
      tiles.add(Material(
        color: sel ? _mint : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (narrow) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => m.$2 == _Item.league || m.$2 == _Item.editor || m.$2 == _Item.devEditor
                    ? _content(m.$2, embedded: false)
                    : Scaffold(appBar: AppBar(title: Text(m.$3)), body: _content(m.$2, embedded: true)),
              ));
            } else {
              setState(() => _sel = m.$2);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.$3, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: sel ? _green : (danger ? const Color(0xFFFCA5A5) : _mint))),
                  Text(m.$4, style: TextStyle(fontSize: 11.5, color: sel ? _green.withValues(alpha: 0.75) : _mint.withValues(alpha: 0.7))),
                ]),
              ),
              if (narrow) Icon(Icons.chevron_right, color: _mint.withValues(alpha: 0.7)),
            ]),
          ),
        ),
      ));
    }
    return Container(
      color: _green,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: _mint),
                tooltip: 'スタート画面へ戻る',
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _titleTaps++),
                  child: const Text('設定・編集', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            ...tiles,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 760) {
        return Scaffold(backgroundColor: _green, body: _sidebar(narrow: true));
      }
      if (!_menu.any((m) => m.$2 == _sel)) _sel = _Item.editor;
      return Scaffold(
        body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 290, child: _sidebar(narrow: false)),
          Expanded(
            child: Semantics(label: _titleOf(_sel), child: _content(_sel, embedded: true)),
          ),
        ]),
      );
    });
  }
}
