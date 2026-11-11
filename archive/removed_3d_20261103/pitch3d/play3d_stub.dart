import 'package:flutter/material.dart';
import '../../engine/match_simulator.dart';

/// Web 版：3D は Android 版のみ
Future<void> openPlay3D(BuildContext context, List<PitchEvent> plays, {int index = -1, int homeColor = 0xFF1E3A8A, int awayColor = 0xFFDC2626, List<String> sponsors = const []}) async {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('3D のプレーは Android 版のみです')));
}
