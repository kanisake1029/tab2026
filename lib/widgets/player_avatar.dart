import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/player.dart';
import 'condition_face.dart';
import '../models/face_look.dart';

/// 顔のセット（Stable Diffusion・Animagine XL 4.0 で作った架空の人物のアイコン。tools/faces で作る）
///  選手ごとに、顔データ（FaceLook：年齢・肌・髪型・髪の色・ひげ・メガネ・輪郭）に一番近い顔を割り当てる。同じ選手はいつも同じ顔
class FaceSet {
  FaceSet._();
  static final FaceSet instance = FaceSet._();

  List<Map<String, dynamic>> _faces = const [];
  bool _loaded = false;
  final Map<String, String> _assigned = {};

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final s = await rootBundle.loadString('assets/faces/faces.json');
      _faces = [for (final e in jsonDecode(s) as List) Map<String, dynamic>.from(e as Map)];
    } catch (_) {
      _faces = const [];
    }
  }

  bool get ready => _faces.isNotEmpty;

  /// 選手の球団（ユニフォームの色とロゴ）。main で AppState から設定する
  (Color, String)? Function(Player p)? uniformOf;

  static double _lum(int argb) => (0.299 * ((argb >> 16) & 0xff) + 0.587 * ((argb >> 8) & 0xff) + 0.114 * (argb & 0xff));

  /// 選手に合う顔のファイル名（無ければ null）
  String? faceOf(Player p) {
    if (_faces.isEmpty) return null;
    final hit = _assigned[p.id];
    if (hit != null) return hit;
    final f = FaceLook.ofPlayer(p);
    final foreign = p.nationality == '海外';
    final skinL = _lum(f.skin), hairL = _lum(f.hair);
    final skin = !foreign ? 'asian' : (skinL < 130 ? 'dark' : (skinL < 185 ? 'tan' : 'white'));
    final age = p.age < 24 ? 'young' : (p.age <= 31 ? 'prime' : 'veteran');
    final color = hairL < 40 ? 'black' : (hairL < 70 ? 'dark_brown' : (hairL < 140 ? 'brown' : 'blonde'));
    const ages = ['young', 'prime', 'veteran'];
    var best = -1e9;
    var pickId = '';
    final salt = p.id.hashCode;
    for (final c in _faces) {
      var s = 0.0;
      if (c['skin'] != skin) s -= (skin == 'asian' || c['skin'] == 'asian') ? 12 : 6;
      s -= (ages.indexOf(c['age'] as String) - ages.indexOf(age)).abs() * 3.0;
      if (c['hair'] != f.hairStyle) s -= 3;
      if (c['color'] != color && !(c['color'] == 'grey' && age == 'veteran')) s -= 2;
      final b = c['beard'] as int;
      if ((b == 0) != (f.beard == 0)) {
        s -= 5;
      } else if (b != f.beard) {
        s -= 1.5;
      }
      if ((c['glasses'] == true) != (f.accessory == 4)) s -= 6;
      if (c['face'] != f.faceShape) s -= 1;
      // 同点は選手ごとにばらす（同じ条件の選手が同じ顔ばかりにならないように）
      s += ((('${c['id']}'.hashCode ^ salt) & 0xffff) / 0xffff) * 0.9;
      if (s > best) {
        best = s;
        pickId = c['id'] as String;
      }
    }
    return _assigned[p.id] = pickId;
  }
}

/// 選手の丸い顔アイコン。date を渡すと、右下に調子の顔マークを小さく重ねる
class PlayerAvatar extends StatelessWidget {
  final Player player;
  final double size;
  final DateTime? date;
  const PlayerAvatar(this.player, {super.key, this.size = 30, this.date});

  @override
  Widget build(BuildContext context) {
    final id = FaceSet.instance.faceOf(player);
    final uni = FaceSet.instance.uniformOf?.call(player);
    final color = uni?.$1 ?? const Color(0xFF64748B);
    final light = color.computeLuminance() > 0.55;
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFE2E8F0), border: Border.all(color: Colors.white, width: 1.2)),
      child: id == null
          ? Icon(Icons.person, size: size * 0.7, color: const Color(0xFF94A3B8))
          : ClipOval(
              child: Stack(fit: StackFit.expand, children: [
                // シャツの陰影に球団の色をかけてユニフォームに
                ColorFiltered(colorFilter: ColorFilter.mode(color, BlendMode.modulate), child: Image.asset('assets/faces/${id}_s.webp', fit: BoxFit.cover, filterQuality: FilterQuality.medium)),
                if (size >= 44 && uni != null)
                  Align(
                    alignment: const Alignment(0, 0.86),
                    child: Text(uni.$2,
                        maxLines: 1,
                        style: TextStyle(fontSize: size * 0.13, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, height: 1, color: light ? const Color(0xFF1C1917) : Colors.white)),
                  ),
                Image.asset('assets/faces/$id.webp', fit: BoxFit.cover, filterQuality: FilterQuality.medium),
              ]),
            ),
    );
    if (date == null) return circle;
    final badge = size * 0.48;
    return SizedBox(
      width: size + badge * 0.25,
      height: size + badge * 0.15,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 0, top: 0, child: circle),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            padding: const EdgeInsets.all(1),
            child: ConditionFace(level: player.conditionAt(date!), size: badge),
          ),
        ),
      ]),
    );
  }
}

/// お知らせの文に名前が出てくる選手（いちばん長い名前で一致した選手。いなければ null）
Player? playerInText(String text, List<Player> players) {
  Player? best;
  for (final p in players) {
    final n = p.registeredName;
    if (n.length >= 2 && text.contains(n) && (best == null || n.length > best.registeredName.length)) best = p;
  }
  return best;
}
