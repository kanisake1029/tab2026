
class GradeUtils {
  static String getGrade(int val) {
    if (val >= 90) return 'S';
    if (val >= 80) return 'A';
    if (val >= 70) return 'B';
    if (val >= 60) return 'C';
    if (val >= 50) return 'D';
    if (val >= 40) return 'E';
    if (val >= 20) return 'F';
    return 'G';
  }

  // Trajectory is 1-4, no alphabet
  static String getTrajectoryDisplay(int val) {
    return val.toString();
  }
}

/// 守備位置の表示（指名打者は「指」。データの上では 'DH' のまま）
String posLabel(String pos) => pos == 'DH' ? '指' : pos;
