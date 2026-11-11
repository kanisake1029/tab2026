import 'dart:io';

void main() {
  File file = File('lib/screens/order_screen.dart');
  String text = file.readAsStringSync();
  List<String> parts = text.split(RegExp(r'// ==============.*?=============='));
  
  if (parts.length < 5) return;
  
  String header = parts[0];
  String lineup = parts[1];
  String pitcher = parts[2];
  String roster = parts[3];
  String allPlayers = parts[4];
  
  // Create shared utilities file
  File('lib/screens/order_tabs/order_shared.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/team.dart';
import '../../providers/app_state.dart';
import '../../utils/app_theme.dart';
import '../../utils/grade_utils.dart';
import '../../widgets/player_detail_dialog.dart';

Widget buildCyberText(String text, {double size = 14, Color color = Colors.white, bool glow = true}) {
  return Text(
    text,
    style: TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.bold,
      shadows: glow ? [Shadow(color: color, blurRadius: 4)] : null,
    ),
  );
}

Widget buildPlayerInfo(BuildContext context, Player p, AppState appState, Team team, VoidCallback onRosterChanged, [String? pos]) {
  if (p.id.isEmpty) return const Text('未設定', style: TextStyle(color: Colors.grey));
  String grade = GradeUtils.getGrade(p.ovr);
  Color gradeColor = AppTheme.getGradeColor(grade);
  return InkWell(
    onTap: () async {
      await showDialog(
        context: context,
        builder: (context) => PlayerDetailDialog(
          player: p,
          appState: appState,
          team: team,
          isReadOnly: true,
          onRosterChanged: onRosterChanged
        ),
      );
      onRosterChanged();
    },
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '#\${p.uniformNumber} \${p.registeredName}', 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white), 
                      overflow: TextOverflow.ellipsis
                    ),
                  ),
                  if (p.nationality == '海外')
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: Colors.pinkAccent, borderRadius: BorderRadius.circular(4)),
                      child: const Text('外', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '\${pos ?? (p.isPitcher ? '投手' : p.mainPosition)} / \${p.age}歳 / プロ\${p.proYears}年目', 
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('OVR', style: TextStyle(fontSize: 8, color: Colors.grey.shade500)),
            Text(grade, style: TextStyle(color: gradeColor, fontWeight: FontWeight.bold, fontSize: 18, shadows: [Shadow(color: gradeColor, blurRadius: 4)])),
            Text(p.ovr.toString(), style: const TextStyle(color: Colors.white, fontSize: 10)),
          ],
        )
      ],
    ),
  );
}

Widget buildStatItem(String label, int val) {
  Color c = AppTheme.getStatColor(val);
  return Column(
    children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 9)),
      Text(val.toString(), style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 14, shadows: [Shadow(color: c, blurRadius: 2)])),
    ],
  );
}

Widget buildTrajectoryStat(int traj) {
  Color c = AppTheme.getTrajectoryColor(traj);
  return Column(
    children: [
      const Text('弾道', style: TextStyle(color: Colors.grey, fontSize: 9)),
      Text(traj.toString(), style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 14, shadows: [Shadow(color: c, blurRadius: 2)])),
    ],
  );
}

Widget buildPitcherInfo(BuildContext context, Player p, AppState appState, Team team, VoidCallback onRosterChanged) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          buildStatItem('球速', p.pitchSpeed),
          buildStatItem('コントロール', p.control),
          buildStatItem('スタミナ', p.stamina),
        ],
      ),
      const SizedBox(height: 4),
      if (p.breakingPitches.isNotEmpty)
        Wrap(
          spacing: 4,
          children: List.generate(p.breakingPitches.length, (i) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.blueGrey.shade800, borderRadius: BorderRadius.circular(4)),
              child: Text('\${p.breakingPitches[i]} \${p.breakingLevels[i]}', style: const TextStyle(fontSize: 9, color: Colors.cyanAccent)),
            );
          }),
        )
    ],
  );
}
''');

  // I will just create a basic structure for now
}
