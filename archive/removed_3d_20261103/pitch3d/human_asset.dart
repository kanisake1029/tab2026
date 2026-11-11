import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Blender（MPFB）から書き出した人体（assets/body/body.bin）
///  形（体・目・眉・まつ毛・髪）・骨・体格と顔の調整ごとの差分。座標は Blender のまま（m、Z が上、人は −Y を向く）
class HumanAsset {
  final List<AssetBone> bones;
  final Map<String, AssetPart> parts;
  final Map<String, AssetDelta> deltas;
  final Map<String, String> skins; // 'young_asian' → 画像
  HumanAsset._(this.bones, this.parts, this.deltas, this.skins);

  static HumanAsset? _cache;
  static Future<HumanAsset> load() async {
    if (_cache != null) return _cache!;
    final bd = await rootBundle.load('assets/body/body.bin');
    return _cache = parse(bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes));
  }

  static HumanAsset parse(Uint8List all) {
    final b = ByteData.sublistView(all);
    final headLen = b.getUint32(0, Endian.little);
    final head = Uint8List.sublistView(all, 4, 4 + headLen);
    final data = Uint8List.sublistView(all, 4 + headLen);
    if (String.fromCharCodes(head.sublist(0, 4)) != 'TBDY') throw const FormatException('body.bin ではありません');
    final hb = ByteData.sublistView(head);
    final jsLen = hb.getUint32(8, Endian.little);
    final meta = jsonDecode(utf8.decode(head.sublist(12, 12 + jsLen))) as Map<String, dynamic>;
    ByteData at(List r) => ByteData.sublistView(data, r[0] as int, (r[0] as int) + (r[1] as int));
    Float32List f32(List r) {
      final bd = at(r);
      final out = Float32List(bd.lengthInBytes ~/ 4);
      for (var i = 0; i < out.length; i++) {
        out[i] = bd.getFloat32(i * 4, Endian.little);
      }
      return out;
    }

    final bones = [
      for (final x in meta['bones'] as List)
        AssetBone(x['name'], x['parent'], _v(x['head']), _v(x['tail']), [for (final row in x['matrix'] as List) for (final v in row as List) (v as num).toDouble()]),
    ];
    final parts = <String, AssetPart>{};
    for (final p in meta['parts'] as List) {
      final n = p['count'] as int;
      final jw = at(p['jw']);
      final joints = Uint8List(n * 4), weights = Float32List(n * 4);
      for (var i = 0; i < n; i++) {
        for (var k = 0; k < 4; k++) {
          joints[i * 4 + k] = jw.getUint8(i * 8 + k);
          weights[i * 4 + k] = jw.getUint8(i * 8 + 4 + k) / 255.0;
        }
      }
      final ib = at(p['idx']);
      final idx = Uint16List(ib.lengthInBytes ~/ 2);
      for (var i = 0; i < idx.length; i++) {
        idx[i] = ib.getUint16(i * 2, Endian.little);
      }
      parts[p['name']] = AssetPart(p['name'], n, f32(p['pos']), f32(p['uv']), joints, weights, idx, p['tex']);
    }
    final deltas = <String, AssetDelta>{};
    for (final d in meta['deltas'] as List) {
      final pd = <String, PartDelta>{};
      (d['parts'] as Map<String, dynamic>).forEach((name, v) {
        final n = v['n'] as int, sc = (v['scale'] as num).toDouble();
        final bd = at(v['data']);
        final idx = Uint32List(n), xyz = Float32List(n * 3);
        for (var i = 0; i < n; i++) {
          idx[i] = bd.getUint16(i * 2, Endian.little);
        }
        final o = n * 2;
        for (var i = 0; i < n * 3; i++) {
          xyz[i] = bd.getInt16(o + i * 2, Endian.little) * sc;
        }
        pd[name] = PartDelta(idx, xyz);
      });
      deltas[d['name']] = AssetDelta(d['name'], pd, f32(d['bones']));
    }
    return HumanAsset._(bones, parts, deltas, Map<String, String>.from(meta['skins'] as Map));
  }

  static List<double> _v(List x) => [for (final v in x) (v as num).toDouble()];

  int boneIndex(String name) => bones.indexWhere((b) => b.name == name);

  /// 調整の重み（'muscle+'：0.4 など）から、形と骨を作る
  BakedHuman bake(Map<String, double> w, {required List<String> partNames}) {
    final pos = <String, Float32List>{};
    for (final pn in partNames) {
      final p = parts[pn];
      if (p == null) continue;
      pos[pn] = Float32List.fromList(p.pos);
    }
    final bonePts = Float32List(bones.length * 6);
    for (var i = 0; i < bones.length; i++) {
      for (var k = 0; k < 3; k++) {
        bonePts[i * 6 + k] = bones[i].head[k];
        bonePts[i * 6 + 3 + k] = bones[i].tail[k];
      }
    }
    w.forEach((name, wt) {
      if (wt.abs() < 1e-4) return;
      final d = deltas[name];
      if (d == null) return;
      d.parts.forEach((pn, pd) {
        final out = pos[pn];
        if (out == null) return;
        for (var i = 0; i < pd.idx.length; i++) {
          final v = pd.idx[i] * 3;
          out[v] += pd.xyz[i * 3] * wt;
          out[v + 1] += pd.xyz[i * 3 + 1] * wt;
          out[v + 2] += pd.xyz[i * 3 + 2] * wt;
        }
      });
      for (var i = 0; i < bonePts.length && i < d.bones.length; i++) {
        bonePts[i] += d.bones[i] * wt;
      }
    });
    return BakedHuman(this, pos, bonePts);
  }
}

class AssetBone {
  final String name;
  final int parent;
  final List<double> head, tail;
  final List<double> matrix; // 4×4（行ごと）。Blender の骨の向き（Y が骨の向き）
  AssetBone(this.name, this.parent, this.head, this.tail, this.matrix);
}

class AssetPart {
  final String name;
  final int count;
  final Float32List pos, uv, weights;
  final Uint8List joints;
  final Uint16List idx;
  final String? tex;
  AssetPart(this.name, this.count, this.pos, this.uv, this.joints, this.weights, this.idx, this.tex);
}

class PartDelta {
  final Uint32List idx;
  final Float32List xyz;
  PartDelta(this.idx, this.xyz);
}

class AssetDelta {
  final String name;
  final Map<String, PartDelta> parts;
  final Float32List bones; // 骨の頭・尾の差（骨の数×6）
  AssetDelta(this.name, this.parts, this.bones);
}

/// 1人分に組み立てた形（Blender の座標）
class BakedHuman {
  final HumanAsset asset;
  final Map<String, Float32List> pos;
  final Float32List bonePts;
  BakedHuman(this.asset, this.pos, this.bonePts);

  List<double> head(int i) => [bonePts[i * 6], bonePts[i * 6 + 1], bonePts[i * 6 + 2]];
  List<double> tail(int i) => [bonePts[i * 6 + 3], bonePts[i * 6 + 4], bonePts[i * 6 + 5]];
  List<double> headOf(String n) => head(asset.boneIndex(n));
  List<double> tailOf(String n) => tail(asset.boneIndex(n));

  /// 体の高さ（足の裏〜頭のてっぺん）
  double get height {
    final p = pos['body']!;
    var lo = 1e9, hi = -1e9;
    for (var i = 2; i < p.length; i += 3) {
      lo = math.min(lo, p[i]);
      hi = math.max(hi, p[i]);
    }
    return hi - lo;
  }

  double dist(List<double> a, List<double> b) => math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2) + math.pow(a[2] - b[2], 2));
}
