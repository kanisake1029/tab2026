import 'dart:io';

void main() {
  File file = File('lib/widgets/player_detail_dialog.dart');
  String text = file.readAsStringSync();

  String oldTraj = '''          IgnorePointer(
              ignoring: widget.isReadOnly,
              child: SizedBox(
                width: 60,
                child: DropdownButtonFormField<int>(
                value: p.trajectory,
                dropdownColor: const Color(0xFF1E293B),
                decoration: const InputDecoration(isDense: true),
                items: [1, 2, 3, 4].map((e) => DropdownMenuItem(value: e, child: Text(e.toString()))).toList(),
                onChanged: (val) => setState(() => p.trajectory = val!),
              ),
            ),
        ],''';

  String newTraj = '''          if (!widget.isReadOnly)
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
        ],''';

  text = text.replaceAll(oldTraj, newTraj);
  file.writeAsStringSync(text);
}
