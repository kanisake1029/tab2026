import 'package:flutter/material.dart';
import '../../models/player.dart';

/// Web 版：3D は Android 版のみ
Future<void> openPitch3D(BuildContext context, Player pitcher, {int teamColor = 0xFF1E3A8A, int oppColor = 0xFFDC2626}) async {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('3D の投球は Android 版のみです')));
}
