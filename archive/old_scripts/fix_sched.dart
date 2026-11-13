import 'dart:io';

void main() {
  File file = File('lib/screens/schedule_screen.dart');
  String text = file.readAsStringSync();

  // Find the exact _buildMatchInfo string up to the end of the file.
  int startIndex = text.indexOf('  Widget _buildMatchInfo(Match m)');
  if (startIndex != -1) {
    text = text.substring(0, startIndex);
  }

  String newFunc = '''  Widget _buildMatchInfo(Match m) {
    bool isMine = m.homeTeamId == widget.appState.myTeamId || m.awayTeamId == widget.appState.myTeamId;
    
    String label = '';
    Color c = Colors.white;
    if (m.matchType == 'OPEN') { label = 'OP '; c = Colors.greenAccent; }
    else if (m.matchType == 'INTERLEAGUE') { label = '交 '; c = Colors.orangeAccent; }
    else if (m.matchType == 'ALLSTAR') { label = 'AS '; c = Colors.purpleAccent; }

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(2),
      decoration: isMine ? BoxDecoration(color: Colors.cyan.withOpacity(0.3), borderRadius: BorderRadius.circular(2)) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (label.isNotEmpty) Text(label, style: TextStyle(color: c, fontSize: 8, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              '\ - \',
              style: TextStyle(fontSize: 9, fontWeight: isMine ? FontWeight.bold : FontWeight.normal),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
''';

  file.writeAsStringSync(text + newFunc);
}
