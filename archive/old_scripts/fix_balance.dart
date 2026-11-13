import 'dart:io';

void main() {
  File f = File('lib/engine/match_simulator.dart');
  String text = f.readAsStringSync();
  
  // We need to replace the entire physics section.
  // We will find the start and end of the block.
  int startIndex = text.indexOf("double baseZOffset = (_rand.nextDouble() - 0.5)");
  int endIndex = text.indexOf("pitchByPitch.add(pitchLog);", startIndex);
  
  if (startIndex != -1 && endIndex != -1) {
    String newBlock = """
        double hitChance = 0.29 + (bMeet - 60) * 0.004 - (pPitchPower - 60) * 0.002 - (pControl - 60) * 0.001;
        hitChance = hitChance.clamp(0.05, 0.60);
        
        double hrShare = (bPower / 60.0) * (bPower / 60.0) * (bTrajectory / 2.0) * 0.10;
        hrShare = hrShare.clamp(0.0, 0.40);
        
        double roll = _rand.nextDouble();
        
        if (roll < hitChance) {
           // It's a hit!
           double hitRoll = _rand.nextDouble();
           if (hitRoll < hrShare) {
              // Home Run
              int runs = 1;
              if (state.runner3B != null) runs++;
              if (state.runner2B != null) runs++;
              if (state.runner1B != null) runs++;
              state.runner1B = null; state.runner2B = null; state.runner3B = null;
              state.addScore(runs);
              if (state.isTop) awayHits++; else homeHits++;
              playByPlay.add('\${batter.registeredName}: ホームラン! (\$pitchCount球目) -\$runs点-');
              pitchLog += '打席(ホームラン \$runs点)';
              batter.seasonStats.homeRuns++;
              batter.seasonStats.hits++;
              batter.seasonStats.rbi += runs;
              pitcher.seasonStats.earnedRuns += runs;
              bStats['hr'] = (bStats['hr'] ?? 0) + 1;
              bStats['h'] = (bStats['h'] ?? 0) + 1;
              bStats['rbi'] = (bStats['rbi'] ?? 0) + runs;
              pStats['er'] = (pStats['er'] ?? 0) + runs;
           } else if (hitRoll < hrShare + 0.03) {
              // 3B
              int runs = 0;
              if (state.runner3B != null) { state.addScore(1); runs++; }
              if (state.runner2B != null) { state.addScore(1); runs++; }
              if (state.runner1B != null) { state.addScore(1); runs++; }
              state.runner1B = null; state.runner2B = null; state.runner3B = batter.registeredName;
              if (state.isTop) awayHits++; else homeHits++;
              playByPlay.add('\${batter.registeredName}: スリーベースヒット (\$pitchCount球目)');
              pitchLog += '打席(3塁打\${runs > 0 ? ' \$runs打点' : ''})';
              batter.seasonStats.hits++;
              batter.seasonStats.rbi += runs;
              pitcher.seasonStats.earnedRuns += runs;
              bStats['h'] = (bStats['h'] ?? 0) + 1;
              bStats['rbi'] = (bStats['rbi'] ?? 0) + runs;
              pStats['er'] = (pStats['er'] ?? 0) + runs;
           } else if (hitRoll < hrShare + 0.20) {
              // 2B
              int runs = 0;
              if (state.runner3B != null) { state.addScore(1); state.runner3B = null; runs++; }
              if (state.runner2B != null) { state.addScore(1); state.runner2B = null; runs++; }
              if (state.runner1B != null) { state.runner3B = state.runner1B; state.runner1B = null; }
              state.runner2B = batter.registeredName;
              if (state.isTop) awayHits++; else homeHits++;
              playByPlay.add('\${batter.registeredName}: ツーベースヒット (\$pitchCount球目)');
              pitchLog += '打席(2塁打\${runs > 0 ? ' \$runs打点' : ''})';
              batter.seasonStats.hits++;
              batter.seasonStats.rbi += runs;
              pitcher.seasonStats.earnedRuns += runs;
              bStats['h'] = (bStats['h'] ?? 0) + 1;
              bStats['rbi'] = (bStats['rbi'] ?? 0) + runs;
              pStats['er'] = (pStats['er'] ?? 0) + runs;
           } else {
              // 1B
              int runs = 0;
              if (state.runner3B != null) { state.addScore(1); state.runner3B = null; runs++; }
              if (state.runner2B != null) { state.runner3B = state.runner2B; state.runner2B = null; }
              if (state.runner1B != null) { state.runner2B = state.runner1B; }
              state.runner1B = batter.registeredName;
              if (state.isTop) awayHits++; else homeHits++;
              playByPlay.add('\${batter.registeredName}: ヒット (\$pitchCount球目)');
              pitchLog += '打席(ヒット\${runs > 0 ? ' \$runs打点' : ''})';
              batter.seasonStats.hits++;
              batter.seasonStats.rbi += runs;
              pitcher.seasonStats.earnedRuns += runs;
              bStats['h'] = (bStats['h'] ?? 0) + 1;
              bStats['rbi'] = (bStats['rbi'] ?? 0) + runs;
              pStats['er'] = (pStats['er'] ?? 0) + runs;
           }
           bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++;
           atBatOver = true;
        } else {
           // Out or Foul
           double foulProb = 0.30 + (bMeet * 0.001) - (pControl * 0.001);
           if (_rand.nextDouble() < foulProb) {
              playByPlay.add('\${batter.registeredName}: ファウル (\$pitchCount球目)');
              pitchLog += '打席(ファウル)';
              if (state.strikes < 2) state.strikes++;
           } else {
              // Out in play
              if (state.outs < 2 && state.runner1B != null && _rand.nextDouble() < 0.2) {
                 state.runner1B = null;
                 playByPlay.add('\${batter.registeredName}: ダブルプレー (\$pitchCount球目)');
                 pitchLog += '打席(併殺)';
                 int outsBefore = state.outs;
                 state.addOut();
                 if (outsBefore < 2) state.addOut();
              } else {
                 if (_rand.nextDouble() < 0.5) {
                    playByPlay.add('\${batter.registeredName}: ゴロアウト (\$pitchCount球目)');
                    pitchLog += '打席(ゴロ)';
                 } else {
                    playByPlay.add('\${batter.registeredName}: フライアウト (\$pitchCount球目)');
                    pitchLog += '打席(フライ)';
                 }
                 state.addOut();
              }
              bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++;
              atBatOver = true;
           }
        }
        
""";
    text = text.replaceRange(startIndex, endIndex, newBlock);
    f.writeAsStringSync(text);
    print("Patched physics with probability logic.");
  } else {
    print("Could not find bounds.");
  }
}
