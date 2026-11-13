import 'dart:io';

void main() {
  File file = File('lib/widgets/player_detail_dialog.dart');
  String text = file.readAsStringSync();

  String replacement = '''  Widget _buildTrajectoryStat() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8),
      child: Row(
        children: [
          const SizedBox(width: 80, child: Text('弾道', style: TextStyle(fontSize: 16))),
          const SizedBox(width: 16),
          Text(p.trajectory.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.getTrajectoryColor(p.trajectory))),
          const Spacer(),
          if (!widget.isReadOnly)
            SizedBox(
              width: 60,
              child: DropdownButtonFormField<int>(
                value: p.trajectory,
                dropdownColor: const Color(0xFF1E293B),
                decoration: const InputDecoration(isDense: true),
                items: [1, 2, 3, 4].map((e) => DropdownMenuItem(value: e, child: Text(e.toString()))).toList(),
                onChanged: (val) => setState(() => p.trajectory = val!),
              ),
            ),
        ],
      ),
    );
  }''';

  text = text.replaceAll(RegExp(r'  Widget _buildTrajectoryStat\(\) \{.*?\n  \}', dotAll: true), replacement);
  file.writeAsStringSync(text);
}
