import 'dart:io';

void main() {
  File file = File('lib/widgets/player_detail_dialog.dart');
  String text = file.readAsStringSync();

  int idx = text.indexOf('1軍枠は31人までです');
  if (idx != -1) {
    print(text.substring(idx - 600, idx + 1000));
  }
}
