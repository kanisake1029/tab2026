import 'dart:math';

// ==========================================
// 物理演算ベースの野球エンジン（たたき台）
// ==========================================

class PhysicalEngineDemo {
  final Random rand = Random();

  void simulateAtBat(Map<String, dynamic> pitcher, Map<String, dynamic> batter) {
    print("【試合開始】 投手: ${pitcher['name']} vs 打者: ${batter['name']}");
    print("--------------------------------------------------");

    int balls = 0;
    int strikes = 0;

    while (strikes < 3 && balls < 4) {
      // 1. 投球の決定（球種・球速・コース）
      // 制球(control)が高いほど、ストライクゾーンの境界（厳しいコース）を狙える
      double targetX = (rand.nextDouble() - 0.5) * 2.0; // -1.0(内角) ~ 1.0(外角)
      double targetY = (rand.nextDouble() - 0.5) * 2.0; // -1.0(低め) ~ 1.0(高め)
      
      // コントロールのブレ（制球が低いほどブレが大きい）
      double controlError = (100 - pitcher['control']) * 0.005;
      double actualX = targetX + (rand.nextDouble() - 0.5) * controlError;
      double actualY = targetY + (rand.nextDouble() - 0.5) * controlError;
      
      bool isStrikeZone = actualX.abs() <= 1.0 && actualY.abs() <= 1.0;
      double actualVelocity = pitcher['velocity'] - rand.nextDouble() * 5.0; // マックス球速からのブレ

      print("⚾ 投球: ${actualVelocity.toStringAsFixed(1)}km/h | コース(X: ${actualX.toStringAsFixed(2)}, Y: ${actualY.toStringAsFixed(2)}) | ${isStrikeZone ? 'ストライクゾーン' : 'ボールゾーン'}");

      // 2. スイング判定
      // ストライクゾーンなら基本振る。ボールゾーンは選球眼（ミートに依存）で見極める
      bool willSwing = false;
      if (isStrikeZone) {
        willSwing = true;
      } else {
        // ミートが高いほどボール球に手を出さない（見極め確率）
        double eyeSkill = batter['meet'] / 100.0;
        if (rand.nextDouble() > eyeSkill) willSwing = true; // 振らされる
      }

      if (!willSwing) {
        if (isStrikeZone) {
          strikes++;
          print("   👉 見逃しストライク ($balls-$strikes)");
        } else {
          balls++;
          print("   👉 見逃しボール ($balls-$strikes)");
        }
        continue;
      }

      // 3. コンタクト判定（バットに当たるか）
      // ミート90ならコンタクト率98%の物理計算
      double contactProb = 0.50 + (batter['meet'] / 100.0) * 0.48; // ミート100で98%
      // 変化球のキレ(sharpness)や球速(velocity)でコンタクト率が下がる
      contactProb -= (actualVelocity - 130) * 0.002;
      contactProb -= (pitcher['sharpness'] / 100.0) * 0.1;

      if (rand.nextDouble() > contactProb) {
        strikes++;
        print("   👉 空振りストライク！ ($balls-$strikes)");
        continue;
      }

      // 4. 当たり所（ミートポイント）の計算
      // バットの中心(0.0)からどれだけズレたか
      // ミートが高いほどバットの芯で捉えやすい
      double batRadius = 0.3 + (batter['meet'] / 100.0) * 0.2; // バットの有効幅
      double hitOffsetX = (rand.nextDouble() - 0.5) * (1.0 - batter['meet'] / 100.0); // 左右のズレ
      double hitOffsetY = (rand.nextDouble() - 0.5) * (1.0 - batter['meet'] / 100.0); // 上下のズレ

      // 5. 打球の物理演算（打球速度と角度）
      // 【打球速度 (Exit Velocity)】 投手の球速＋打者のパワー － 投手の球威(重さ) － 芯外しによる減衰
      double baseExitVelocity = actualVelocity * 0.2 + (batter['power'] * 0.8);
      double heavinessPenality = pitcher['pitchPower'] * 0.3; // 球威による押し込み
      double missHitPenalty = (hitOffsetX.abs() + hitOffsetY.abs()) * 50.0; // 芯を外すと大きく減衰
      
      double exitVelocity = baseExitVelocity - heavinessPenality - missHitPenalty;
      if (exitVelocity < 40) exitVelocity = 40; // 最小速度

      // 【打球角度 (Launch Angle)】 打者の弾道(1-4)と、ボールの下を叩いたか上を叩いたか(hitOffsetY)で決定
      double baseAngle = batter['trajectory'] * 10.0; // 弾道1: 10度, 弾道4: 40度
      double launchAngle = baseAngle - (hitOffsetY * 50.0); // 下を叩く(マイナス)とフライになる

      print("   💥 コンタクト！ ズレ(X: ${hitOffsetX.toStringAsFixed(2)}, Y: ${hitOffsetY.toStringAsFixed(2)})");
      print("   📊 打球速度: ${exitVelocity.toStringAsFixed(1)}km/h, 角度: ${launchAngle.toStringAsFixed(1)}度");

      // 6. 飛距離の計算 (簡易物理: V^2 * sin(2θ) / g)
      double vMetersPerSec = exitVelocity * 1000 / 3600;
      double angleRad = launchAngle * pi / 180;
      double gravity = 9.8;
      
      // 空気抵抗を考慮した簡易係数
      double distance = (vMetersPerSec * vMetersPerSec * sin(2 * angleRad)) / gravity * 0.75;
      if (distance < 0) distance = 0; // ゴロ
      
      print("   📏 飛距離: ${distance.toStringAsFixed(1)} m");

      // 7. 守備判定（全ステータス関与）
      if (distance > 110) {
        print("   🔥🔥 スタンドイン！ ホームラン！！");
        return;
      } else if (launchAngle <= 10) {
        // 内野ゴロ
        print("   💨 内野へのゴロ...");
        double runnerTime = 4.0 - (batter['run'] * 0.01); // 走力で一塁到達時間を計算
        double fielderTime = 2.0 - (pitcher['catchSkill'] * 0.005) - (pitcher['throwAccuracy'] * 0.005); // ※内野手の捕球・送球で処理時間計算
        if (runnerTime < fielderTime) {
          print("   🏃‍♂️ 内野安打！ (走力: ${batter['run']})");
        } else {
          print("   ❌ アウト！");
        }
        return;
      } else {
        // 外野フライ or ヒット
        if (distance > 60 && distance < 110) {
          // 滞空時間の計算
          double hangTime = (2 * vMetersPerSec * sin(angleRad)) / gravity;
          
          // 外野手が追いつける距離（守備範囲）
          // ※本来は外野手のステータスを用いる
          double fielderRange = 15.0 + (pitcher['run'] * 0.2); 
          
          if (hangTime > 3.0 && fielderRange > 25.0) {
            print("   🧤 外野手フライキャッチ！ アウト！");
          } else {
            print("   ⚾ 外野の前に落ちるヒット！");
            // 【肩力テスト】 肩力vs走力で二塁打になるか判定
            if (batter['run'] > pitcher['arm']) {
               print("   🏃‍♂️ 俊足を飛ばしてツーベースヒット！！");
            }
          }
          return;
        } else {
           print("   ❌ 凡打（アウト）");
           return;
        }
      }
    }
    
    if (balls >= 4) {
      print("   🚶‍♂️ フォアボール");
    } else {
      print("   ❌ 三振");
    }
  }
}

void main() {
  var engine = PhysicalEngineDemo();
  
  var pitcher = {
    'name': '菅野',
    'velocity': 153, // 球速
    'pitchPower': 85, // 球威
    'control': 90,   // 制球
    'sharpness': 80, // 変化球のキレ
    // 以下守備の代理
    'catchSkill': 80,
    'throwAccuracy': 85,
    'run': 60,
    'arm': 80,
  };

  var batter = {
    'name': '岡本',
    'meet': 75,       // ミート
    'power': 95,      // パワー
    'run': 65,        // 走力
    'trajectory': 4,  // 弾道 (1-4)
  };

  print("=== テスト1: 強打者 vs エース ===");
  engine.simulateAtBat(pitcher, batter);
  
  print("\n=== テスト2: 俊足巧打者 ===");
  var batter2 = {
    'name': '近本',
    'meet': 92,
    'power': 55,
    'run': 95,
    'trajectory': 2,
  };
  engine.simulateAtBat(pitcher, batter2);
}
