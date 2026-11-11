import 'dart:math';

import 'physics_engine.dart';

class PitchState {
  double x, y, z;
  double vx, vy, vz;
  double time;
  PitchState({required this.x, required this.y, required this.z, required this.vx, required this.vy, required this.vz, required this.time});
}

class PitchTrajectory {
  List<PitchState> states;
  Vector3D platePosition;
  PitchTrajectory(this.states, this.platePosition);
}

class PitchPhysics {
  static PitchTrajectory simulatePitch({
    required double initialSpeedKmh,
    required double hBreak,
    required double vBreak,
    required double targetX,
    required double targetZ,
    double releaseX = 0.0,
    double releaseZ = 0.25,
  }) {
    double yStart = 18.44; 
    double yEnd = 0.0;     
    
    double initialVy = -(initialSpeedKmh / 3.6);
    double flightTime = yStart / initialVy.abs();
    
    double expectedVx = (targetX - releaseX) / flightTime;
    double expectedVz = (targetZ - releaseZ) / flightTime;
    
    double gravity = 9.81;
    double drag = 0.005; 
    
    double accelX = (hBreak / 100.0) * 2.0; 
    double accelZ = (vBreak / 100.0) * 2.0; 
    
    double magnusZ = gravity - 4.5 + accelZ; 
    
    double x = releaseX;
    double y = yStart;
    double z = releaseZ;
    double vx = expectedVx;
    double vy = initialVy;
    double vz = expectedVz + (0.5 * gravity * flightTime) - (0.5 * magnusZ * flightTime);
    
    double dt = 0.01;
    double t = 0.0;
    
    List<PitchState> states = [];
    
    while (y > yEnd) {
      states.add(PitchState(x: x, y: y, z: z, vx: vx, vy: vy, vz: vz, time: t));
      
      double speed = sqrt(vx*vx + vy*vy + vz*vz);
      
      double ax = -drag * speed * vx + accelX;
      double ay = -drag * speed * vy;
      double az = -gravity + magnusZ - drag * speed * vz;
      
      vx += ax * dt;
      vy += ay * dt;
      vz += az * dt;
      
      x += vx * dt;
      y += vy * dt;
      z += vz * dt;
      t += dt;
    }
    
    states.add(PitchState(x: x, y: y, z: z, vx: vx, vy: vy, vz: vz, time: t));
    
    return PitchTrajectory(states, Vector3D(x, y, z, vx, vy, vz));
  }

  static final Random _noiseRand = Random();

  static double _gauss() {
    double u1 = 1.0 - _noiseRand.nextDouble();
    double u2 = _noiseRand.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  static List<double> calculateBatOffset({
    required PitchTrajectory actualPitch,
    required double bMeet,
    required double bEye,
    required double prevSpeedKmh,
    required double currentSpeedKmh,
    required double sharpness,
    double breakAmount = 0.0,       // 球種の変化量(0〜100)
    double locationDifficulty = 0.0, // ゾーン外れ具合(0=ゾーン内、大きいほど外)
  }) {
    double totalTime = actualPitch.states.last.time;
    double reactionDelay = 0.15 + (sharpness / 100.0) * 0.05; 
    double commitTime = totalTime - reactionDelay;
    
    PitchState commitState = actualPitch.states.firstWhere((s) => s.time >= commitTime, orElse: () => actualPitch.states.last);
    
    double remainingTime = totalTime - commitState.time;
    double gravity = 9.81;
    double expectedX = commitState.x + (commitState.vx * remainingTime);
    double expectedZ = commitState.z + (commitState.vz * remainingTime) - 0.5 * (gravity - 4.5) * remainingTime * remainingTime;
    
    double errorX = actualPitch.platePosition.x - expectedX;
    double errorZ = actualPitch.platePosition.z - expectedZ;
    return finishOffset(errorX: errorX, errorZ: errorZ, bMeet: bMeet, bEye: bEye, prevSpeedKmh: prevSpeedKmh, currentSpeedKmh: currentSpeedKmh, sharpness: sharpness, breakAmount: breakAmount, locationDifficulty: locationDifficulty);
  }

  /// 打者の予測のずれ（errorX・errorZ：球の終盤の変化で生まれた分 m）に、緩急・選球眼・ミート・スイングのブレを加える
  static List<double> finishOffset({
    required double errorX,
    required double errorZ,
    required double bMeet,
    required double bEye,
    required double prevSpeedKmh,
    required double currentSpeedKmh,
    required double sharpness,
    double breakAmount = 0.0,
    double locationDifficulty = 0.0,
  }) {
    // 緩急（前球との球速差）によるタイミングずれ
    double speedDiff = currentSpeedKmh - prevSpeedKmh;
    errorZ += (speedDiff / 20.0) * -0.05;

    // 選球眼・ミートによる補正
    double eyeFactor = 1.0 - (bEye / 100.0) * 0.5; 
    double meetFactor = 1.0 - (bMeet / 100.0) * 0.4;
    errorX *= eyeFactor * meetFactor;
    errorZ *= eyeFactor * meetFactor;

    // スイングのブレ（ミートが高いほど小さい。キレ・変化量・球速・ボール球ほど大きい）
    double sigma = 0.0232 + (100 - bMeet) * 0.00012;
    sigma *= 0.60 + (sharpness / 100.0) * 0.80;
    sigma *= 1.0 + (breakAmount / 100.0) * 0.50;
    sigma *= 1.0 + ((currentSpeedKmh - 145.0) / 100.0) * 1.2;
    sigma *= 1.0 + locationDifficulty * 0.9;
    errorX += _gauss() * sigma;
    errorZ += _gauss() * sigma;
    
    return [errorX, errorZ];
  }
}
