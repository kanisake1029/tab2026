import 'dart:io';

void main() {
  File f = File('lib/widgets/player_detail_dialog.dart');
  String text = f.readAsStringSync();
  
  // Replace length
  text = text.replaceAll('length: 3,', 'length: 4,');
  
  // Add Tab
  text = text.replaceAll("Tab(text: '投手能力'),", "Tab(text: '投手能力'),\n                        const Tab(text: '成績'),");
  // Mojibake fallback just in case
  text = text.replaceAll("Tab(text: '謚墓焔閭ｽ蜉・),", "Tab(text: '投手能力'),\n                        const Tab(text: '成績'),");
  
  // Add View
  text = text.replaceAll("_buildPitcherTab(),", "_buildPitcherTab(),\n                          _buildStatsTab(),");
  
  // Add Method
  String statsMethod = """
  Widget _buildStatsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('野手成績', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const Divider(),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _statBox('試合', p.seasonStats.games.toString()),
              _statBox('打率', p.seasonStats.battingAverage.toStringAsFixed(3).replaceFirst('0.', '.')),
              _statBox('打席', p.seasonStats.atBats.toString()),
              _statBox('安打', p.seasonStats.hits.toString()),
              _statBox('本塁打', p.seasonStats.homeRuns.toString()),
              _statBox('打点', p.seasonStats.rbi.toString()),
              _statBox('三振', p.seasonStats.strikeouts.toString()),
              _statBox('四球', p.seasonStats.walks.toString()),
              _statBox('盗塁', p.seasonStats.stolenBases.toString()),
            ],
          ),
          const SizedBox(height: 24),
          const Text('投手成績', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
          const Divider(),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _statBox('登板', p.seasonStats.games.toString()),
              _statBox('防御率', p.seasonStats.era.toStringAsFixed(2)),
              _statBox('勝利', p.seasonStats.wins.toString()),
              _statBox('敗北', p.seasonStats.losses.toString()),
              _statBox('セーブ', p.seasonStats.saves.toString()),
              _statBox('ホールド', p.seasonStats.holds.toString()),
              _statBox('投球回', (p.seasonStats.inningsPitched / 3).toStringAsFixed(1)),
              _statBox('奪三振', p.seasonStats.pitcherStrikeouts.toString()),
              _statBox('与四球', p.seasonStats.pitcherWalks.toString()),
              _statBox('自責点', p.seasonStats.earnedRuns.toString()),
            ],
          )
        ],
      ),
    );
  }

  Widget _statBox(String label, String value) {
    return Container(
      width: 80,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300)
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }
}
""";

  text = text.replaceFirst("\n}\n\nclass BaseballFieldPainter", statsMethod + "\n\nclass BaseballFieldPainter");
  
  f.writeAsStringSync(text);
}
