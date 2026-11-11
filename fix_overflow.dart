import 'dart:io';

void main() {
  File f = File('lib/widgets/player_detail_dialog.dart');
  String text = f.readAsStringSync();
  
  text = text.replaceAll(
    "child: IgnorePointer(ignoring: widget.isReadOnly, child: _buildFieldingDiamond()),",
    "child: IgnorePointer(ignoring: widget.isReadOnly, child: SingleChildScrollView(child: _buildFieldingDiamond())),"
  );
  
  f.writeAsStringSync(text);
}
