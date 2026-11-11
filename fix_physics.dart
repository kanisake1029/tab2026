import 'dart:io';

void main() {
  File f = File('lib/engine/match_simulator.dart');
  String text = f.readAsStringSync();
  
  int startIndex = text.indexOf("double hitChance = 0.29");
  int endIndex = text.indexOf("pitchByPitch.add(pitchLog);\n        state.resetCount();");
  
  if (startIndex != -1 && endIndex != -1) {
    String newBlock = """
        // --- NEW REALISTIC PHYSICS ENGINE ---
        
        // Use Box-Muller transform for Gaussian random numbers
        double randGaussian() {
          double u1 = _rand.nextDouble();
          double u2 = _rand.nextDouble();
          if (u1 == 0.0) u1 = 0.0001;
          return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
        }

        // Calculate swing prediction error (standard deviation in meters)
        // bMeet 60 vs pitcher 60 -> ~0.038m (3.8cm)
        double batterSkill = bMeet / 100.0;
        double pitcherSkill = (pPitchPower + pControl + pBreakAmt) / 300.0;
        double stdDev = 0.015 + (1.0 - batterSkill) * 0.035 + pitcherSkill * 0.015;

        // Calculate actual contact offset
        double diffX = randGaussian() * stdDev;
        double diffZ = randGaussian() * stdDev;
        double R = sqrt(diffX * diffX + diffZ * diffZ);

        if (R > 0.069) { // 6.9cm is the combined radius of bat and ball
           // WHIFF (Swing and miss)
           state.addStrike();
           pitchLog += '空振り';
           if (state.strikes >= 3) {
              playByPlay.add('\${batter.registeredName}: 空振り三振 (\$pitchCount球目)');
              batter.seasonStats.strikeouts++;
              pitcher.seasonStats.pitcherStrikeouts++;
              bStats['so'] = (bStats['so'] ?? 0) + 1;
              bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++;
              pStats['so'] = (pStats['so'] ?? 0) + 1;
              atBatOver = true;
              state.addOut();
           }
           pitchByPitch.add(pitchLog);
           continue; 
        }

        // CONTACT MADE
        // Calculate Angles
        double verticalContactAngle = asin(diffZ / 0.069) * 180.0 / pi;
        double horizontalAngle = -asin(diffX / 0.069) * 180.0 / pi;
        double swingPlaneAngle = (bTrajectory - 1) * 6.0;
        double launchAngle = swingPlaneAngle - verticalContactAngle;

        // Foul ball check
        if (horizontalAngle < -45.0 || horizontalAngle > 45.0) {
           playByPlay.add('\${batter.registeredName}: ファウル (\$pitchCount球目)');
           pitchLog += '打席(ファウル)';
           if (state.strikes < 2) state.strikes++;
           pitchByPitch.add(pitchLog);
           continue;
        }

        // Calculate Exit Velocity
        double vPitch = currentSpeed / 3.6; // m/s
        double vBat = 28.0 + (bPower / 100.0) * 18.0; // 38.8m/s at 60 power
        double penalty = cos((R / 0.069) * (pi / 2.0)); 
        double vExit = (0.15 * vPitch + 1.05 * vBat) * (0.5 + 0.5 * penalty);
        double vExitKmh = vExit * 3.6;

        // Calculate Flight Distance
        double distance = 0.0;
        if (launchAngle > 0) {
           distance = (vExit * vExit * sin(launchAngle * pi / 180.0 * 2.0)) / 9.81 * 0.70;
        }

        // Evaluate Outcome (Statcast-style)
        double hitProb = 0.0;
        String contactType = "ゴロ";
        if (launchAngle < 10) {
           contactType = "ゴロ";
           hitProb = (vExitKmh > 140) ? 0.40 : 0.15;
        } else if (launchAngle < 25) {
           contactType = "ライナー";
           hitProb = (vExitKmh > 125) ? 0.70 : 0.35;
        } else if (launchAngle < 45) {
           contactType = "フライ";
           if (distance > 105) {
              hitProb = 1.0; // HR
           } else {
              hitProb = (vExitKmh > 130) ? 0.30 : 0.05;
           }
        } else {
           contactType = "ポップフライ";
           hitProb = 0.01;
        }

        bool isHit = _rand.nextDouble() < hitProb;
        
        if (isHit) {
           if (distance > 105 && launchAngle > 15 && launchAngle < 45) {
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
           } else if (distance > 90 && vExitKmh > 120 && _rand.nextDouble() < 0.1) {
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
           } else if (vExitKmh > 115 && _rand.nextDouble() < 0.3) {
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
           // Out in play
           if (state.outs < 2 && state.runner1B != null && contactType == "ゴロ" && _rand.nextDouble() < 0.25) {
              state.runner1B = null;
              playByPlay.add('\${batter.registeredName}: ダブルプレー (\$pitchCount球目)');
              pitchLog += '打席(併殺)';
              int outsBefore = state.outs;
              state.addOut();
              if (outsBefore < 2) state.addOut();
           } else {
              playByPlay.add('\${batter.registeredName}: \$contactTypeアウト (\$pitchCount球目)');
              pitchLog += '打席(\$contactType)';
              state.addOut();
           }
           bStats['ab'] = (bStats['ab'] ?? 0) + 1; batter.seasonStats.atBats++;
           atBatOver = true;
        }

        """;
    text = text.replaceRange(startIndex, endIndex, newBlock);
    f.writeAsStringSync(text);
    print("Fixed logic.");
  } else {
    print("Could not find bounds: \$startIndex \$endIndex");
  }
}
