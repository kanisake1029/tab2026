import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npb_pennant_app/engine/match_simulator.dart';
import 'package:npb_pennant_app/models/stadium.dart';
import 'package:npb_pennant_app/widgets/pitch3d/board_art.dart';

/// ビジョンの中身を PNG にする（調べ用。OUT を指定したときだけ）
void main() {
  test('ビジョンの絵', () async {
    const out = String.fromEnvironment('OUT');
    if (out.isEmpty) return;
    Directory(out).createSync(recursive: true);
    // 日本語の字（PC の字体を読む。テストの初期の字体は四角になる）
    final fl = FontLoader('NotoJP')..addFont(Future.value(ByteData.sublistView(File('C:/Windows/Fonts/NotoSansJP-VF.ttf').readAsBytesSync())));
    await fl.load();
    BoardArt.font = 'NotoJP';
    final e = PitchEvent(paIndex: 12, pitchNo: 3, battingHome: false, batter: '佐々木 健太', batterHand: 'R', pitcher: '高橋 翔', pitchName: 'スライダー', speed: 138, x: 0, z: 0, inZone: true, balls: 2, strikes: 1)
      ..inning = 4
      ..top = true
      ..outsBefore = 1
      ..basesBefore = [true, false, true]
      ..offBefore = 3
      ..defBefore = 2
      ..pitcherCount = 57
      ..homeName = '神戸'
      ..awayName = 'ラクテル'
      ..batterToday = '2打数1安打'
      ..homeLine = [for (var i = 0; i < 9; i++) '${['中', '二', '右', '一', '左', '三', '遊', '捕', '投'][i]}|山田 太郎$i|${i + 1}|.2${80 + i}|${i * 2}']
      ..awayLine = [for (var i = 0; i < 9; i++) '${['遊', '中', '左', '一', '右', '三', '二', '捕', '投'][i]}|${i == 3 ? '佐々木 健太' : '鈴木 一郎$i'}|${i + 10}|.3${i}1|${i + 3}'];
    final d = BoardData(
        e: e, stadium: '鳴尾浜球場', home: const Color(0xFFFACC15), away: const Color(0xFF7F1D2D),
        ads: const [('ノースビール', 0xFFB91C1C), ('ほくと電機', 0xFF1D4ED8), ('はまなす銀行', 0xFF0F766E), ('北ガス', 0xFFEA580C)],
        runs: const {'1T': 0, '1B': 1, '2T': 2, '2B': 0, '3T': 1, '3B': 1, '4T': 0}, rH: 2, rA: 3, hH: 5, hA: 7, eH: 0, eA: 1);
    final boards = <(String, Vision)>[];
    for (final st in Stadium.all) {
      for (final v in [if (st.showMainVision) st.vision, ...st.moreVisions]) {
        boards.add(('${st.id}_${v.content}_${v.width.round()}x${v.height.round()}', v));
      }
    }
    for (final (name, v) in boards) {
      final w = (BoardArt.h * v.width / v.height).clamp(80.0, 6000.0);
      final img = BoardArt.paint(v.content, w, d).toImageSync(w.round(), BoardArt.h.round());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    final rib = BoardArt.ribbon('神戸', const Color(0xFFFACC15), d.ads);
    File('$out/ribbon.png').writeAsBytesSync((await rib.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
  });
}
