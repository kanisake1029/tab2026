import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/app_state.dart';

/// 固有12球団の現在の内容を initial_teams_data.dart 形式で書き出す（クリップボードにコピー）。
/// 出力を lib/utils/initial_teams_data.dart に貼り替えると、固有12の初期データが更新される。
Future<void> showInitialDataExport(BuildContext context, AppState appState) async {
  final src = appState.exportInitialDataSource();
  await Clipboard.setData(ClipboardData(text: src));
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('初期データを書き出しました'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('固有12球団 ${src.length ~/ 1024} KB 分のソースをクリップボードにコピーしました。'),
            const SizedBox(height: 8),
            const Text('lib/utils/initial_teams_data.dart の中身をこの内容に置き換えると、固有12の初期データとして反映されます。'),
            const SizedBox(height: 8),
            Container(
              height: 120,
              padding: const EdgeInsets.all(8),
              color: Colors.black.withAlpha(12),
              child: SingleChildScrollView(child: SelectableText(src.substring(0, src.length < 600 ? src.length : 600), style: const TextStyle(fontSize: 11))),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('閉じる'))],
    ),
  );
}
