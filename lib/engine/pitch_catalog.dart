import 'dart:math';
import '../models/player.dart';

/// 球種1つの定義（docs/pitch_catalog.md と同じ表）
///  角度（右投手）：0＝利き腕側（シュート方向）、90＝真下、180＝グラブ側（スライダー方向）
///  球速差：ストレートとの差（km/h、負の値）。同じ球種なら速いほど変化量は小さい
class PitchSpec {
  final String name;
  final String group;
  final int dLo, dHi;   // 球速差の範囲（dLo が遅い側。例 −18〜−10）
  final int bLo, bHi;   // 変化量
  final int aLo, aHi;   // 角度
  final int hLo, hHi;   // 重さ
  final int sLo, sHi;   // キレ
  final double weight;  // 選ばれやすさ（普10・やや珍4・珍2・レア0.5）
  final String memo;    // 変化のしかた
  const PitchSpec(this.name, this.group, this.dLo, this.dHi, this.bLo, this.bHi, this.aLo, this.aHi, this.hLo, this.hHi, this.sLo, this.sHi, this.weight, this.memo);

  String get rarity => weight >= 10 ? '普' : weight >= 4 ? 'やや珍' : weight >= 2 ? '珍' : 'レア';
}

class PitchCatalog {
  static const groups = ['ストレート系', 'スライダー系', 'カーブ系', 'フォーク系', 'シンカー系'];
  static const _s = 'ストレート系', _sl = 'スライダー系', _c = 'カーブ系', _f = 'フォーク系', _sk = 'シンカー系';

  static const all = <PitchSpec>[
    // ストレート系
    PitchSpec('ストレート', _s, 0, 0, 0, 0, 90, 90, 30, 80, 30, 80, 0, '基準になる直球'),
    PitchSpec('ツーシーム', _s, -7, -3, 15, 35, 20, 40, 55, 85, 35, 65, 10, '利き腕側へ少しずれて沈む。ゴロを打たせる'),
    PitchSpec('ワンシーム', _s, -7, -3, 20, 40, 40, 60, 55, 85, 35, 65, 4, '縫い目1本に指をかける。ツーシームより沈む'),
    PitchSpec('シュート', _s, -14, -8, 25, 50, 0, 20, 45, 75, 40, 70, 10, '利き腕側へ横に曲がる。懐を突く'),
    PitchSpec('高速シュート', _s, -6, -2, 15, 30, 5, 20, 50, 80, 40, 70, 4, '直球に近い速さで小さく利き腕側へ'),
    PitchSpec('ムービングファスト', _s, -4, -1, 8, 20, 0, 180, 55, 85, 35, 65, 4, '手元で小さく不規則に動き、芯を外す'),
    PitchSpec('イーファスピッチ', _s, -70, -50, 60, 90, 90, 90, 10, 30, 20, 50, 0.5, '山なりの超スローボール'),
    // スライダー系
    PitchSpec('スイーパー', _sl, -22, -15, 55, 85, 175, 190, 35, 60, 45, 80, 10, 'ほぼ真横に大きく滑る'),
    PitchSpec('スライダー', _sl, -18, -10, 35, 65, 155, 175, 40, 65, 45, 80, 10, '横に曲がりながら少し落ちる'),
    PitchSpec('ハードスライダー', _sl, -12, -6, 25, 45, 150, 170, 50, 75, 50, 80, 10, '速く、短く鋭く曲がる'),
    PitchSpec('カットボール', _sl, -8, -3, 12, 30, 170, 185, 55, 80, 45, 75, 10, '直球に近い速さで、手元で小さくグラブ側へ'),
    PitchSpec('スパイクジャイロ', _sl, -14, -8, 25, 45, 100, 120, 45, 70, 55, 85, 2, 'ジャイロ回転。横にはあまり曲がらず、すっと落ちる'),
    PitchSpec('スロースライダー', _sl, -30, -22, 45, 70, 145, 165, 25, 50, 40, 70, 4, '遅くて大きく曲がり、タイミングを外す'),
    PitchSpec('ナックルスライダー', _sl, -18, -12, 40, 65, 135, 155, 40, 65, 50, 80, 2, '立てた指で握る。遅れて斜め下へ鋭く曲がる'),
    PitchSpec('縦スライダー', _sl, -14, -7, 30, 55, 95, 115, 45, 70, 50, 80, 10, '縦に鋭く落ちるスライダー。空振りを取りやすい'),
    PitchSpec('スラッター', _sl, -12, -6, 30, 50, 100, 125, 50, 75, 50, 80, 4, 'スライダーとカットの中間。横は小さく縦に落ちる'),
    PitchSpec('スラーブ', _sl, -26, -18, 50, 75, 135, 150, 30, 55, 45, 75, 10, 'スライダーとカーブの中間。斜めに大きく曲がる'),
    // カーブ系
    PitchSpec('カーブ', _c, -35, -25, 50, 75, 125, 140, 25, 50, 45, 75, 10, '浮いてから斜めに大きく落ちる'),
    PitchSpec('スローカーブ', _c, -45, -35, 60, 85, 120, 135, 15, 40, 40, 70, 10, 'さらに遅く、大きな弧を描く'),
    PitchSpec('超スローカーブ', _c, -65, -50, 75, 95, 105, 125, 10, 30, 35, 65, 0.5, 'ふわっと浮く放物線。タイミングを大きく外す'),
    PitchSpec('ナックルカーブ', _c, -26, -18, 50, 75, 100, 120, 35, 60, 55, 85, 4, '立てた指で強く回転をかける。速く縦に鋭く落ちる'),
    PitchSpec('ドロップカーブ', _c, -35, -25, 55, 85, 90, 105, 25, 50, 45, 75, 10, '真上から真下へ落ちる'),
    PitchSpec('パワーカーブ', _c, -22, -14, 40, 65, 115, 135, 45, 70, 50, 80, 4, '速いカーブ。変化は小さめで鋭い'),
    // フォーク系
    PitchSpec('フォーク', _f, -18, -10, 50, 85, 85, 95, 45, 70, 45, 80, 10, '回転が少なく、手元でストンと落ちる'),
    PitchSpec('スプリット', _f, -10, -5, 30, 55, 80, 95, 55, 80, 45, 75, 10, '浅く挟む。速く、小さく落ちる'),
    PitchSpec('スプリットファスト', _f, -5, -2, 20, 35, 80, 95, 60, 85, 45, 70, 4, 'ほぼ直球の速さで、手元でわずかに沈む'),
    PitchSpec('スポンカー', _f, -7, -3, 35, 60, 50, 70, 60, 90, 50, 80, 2, 'シンカーの速さとスプリットの落ち方。利き腕側へ沈む'),
    PitchSpec('ジャイロフォーク', _f, -16, -10, 45, 70, 90, 100, 40, 65, 55, 85, 2, 'ジャイロ回転。横の変化はほぼなく、遅れて鋭く落ちる'),
    PitchSpec('ナックル', _f, -50, -40, 40, 90, 0, 360, 10, 30, 20, 60, 0.5, 'ほぼ無回転で、揺れながら不規則に変化する（毎球向きが変わる）'),
    PitchSpec('スプリットチェンジ', _f, -22, -15, 40, 65, 70, 85, 45, 70, 45, 75, 4, 'スプリットの握りのチェンジアップ。遅く、少し利き腕側へ落ちる'),
    // シンカー系
    PitchSpec('チェンジアップ', _sk, -22, -15, 30, 55, 55, 75, 45, 70, 40, 70, 10, '直球と同じ腕の振りで遅い球。利き腕側へ沈む'),
    PitchSpec('チェンジオブペース', _sk, -30, -20, 15, 35, 70, 90, 30, 55, 30, 60, 10, '変化はほとんどなく、球速の差だけでタイミングを外す'),
    PitchSpec('シンカー', _sk, -20, -12, 40, 65, 40, 60, 50, 75, 45, 75, 10, '利き腕側へ曲がりながら落ちる'),
    PitchSpec('スローシンカー', _sk, -32, -22, 50, 75, 45, 65, 35, 60, 40, 70, 4, '遅く、大きく利き腕側へ沈む'),
    PitchSpec('ハードシンカー', _sk, -10, -5, 25, 45, 30, 50, 60, 85, 45, 75, 10, '速く、利き腕側へ沈む。ゴロを打たせる'),
    PitchSpec('サークルチェンジ', _sk, -24, -16, 35, 60, 45, 65, 45, 70, 45, 75, 10, 'OKサインの握り。利き腕側へ逃げながら沈む'),
    PitchSpec('バルカンチェンジ', _sk, -20, -14, 40, 65, 70, 90, 45, 70, 50, 80, 2, '中指と薬指の間に挟む。フォークのように落ちる'),
    PitchSpec('エアベンダー', _sk, -20, -14, 50, 80, 15, 35, 35, 60, 60, 90, 0.5, '横回転で、利き腕側へ大きく曲がりながら沈む魔球'),
  ];

  static final Map<String, PitchSpec> _byName = {for (final s in all) s.name: s};
  static PitchSpec? of(String name) => _byName[name];

  /// 采配のボタン用の短い球種名：ハード→H・ナックル→K・スロー→S・縦→V・パワー→P・ジャイロ→G・サークル→C（例 ハードスライダー→Hスライダー）。
  ///  その名前だけの球（ナックルなど）はそのまま
  static String short(String name) {
    const pre = [('超スロー', '超S'), ('ハード', 'H'), ('ナックル', 'K'), ('スロー', 'S'), ('縦', 'V'), ('パワー', 'P'), ('ジャイロ', 'G'), ('サークル', 'C')];
    for (final (a, b) in pre) {
      if (name.startsWith(a) && name.length > a.length) return '$b${name.substring(a.length)}';
    }
    return name;
  }
  static String groupOf(String name) => _byName[name]?.group ?? '';

  /// 直球のように扱う球（配球・狙い球の判定用）。表に無い球種は変化量で判断する
  static bool isFastLike(Pitch p) {
    final s = _byName[p.name];
    if (s == null) return p.breakLevel <= 20;
    if (s.name == 'イーファスピッチ' || s.name == 'シュート') return false;
    return s.group == _s || s.name == 'カットボール' || s.name == 'スプリットファスト';
  }

  static double _g(Random r) => sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());
  static int _lerp(int lo, int hi, double t) => (lo + (hi - lo) * t.clamp(0.0, 1.0)).round();

  /// 投手の持ち球を作る。先発は4〜8球種、中継ぎ・抑えは3〜5球種。ストレートは必ず入る
  ///  キレは制球と変化球のセンス、重さは球威に寄せる。決め球の1球はキレ＋5〜10
  /// 1つの球種を、その投手（球速・制球・球威）に合わせて作る（割合は0。編集画面で球種を足すとき）
  static Pitch fromSpec(Player p, PitchSpec s, Random r) {
    final sharpBase = (0.5 + (p.control - 60) / 70.0).clamp(0.05, 0.95);
    final heavyBase = (0.5 + (p.pitchPower - 60) / 70.0).clamp(0.05, 0.95);
    final tSpeed = r.nextDouble();
    final diff = _lerp(s.dLo, s.dHi, tSpeed);
    final int speed = max(70, p.velocity + diff);
    final int brk = s.name == 'ストレート' ? 0 : (s.bHi - (s.bHi - s.bLo) * tSpeed + (sharpBase - 0.5) * 8).round().clamp(max(0, s.bLo - 5), min(100, s.bHi + 5)).toInt();
    final angle = s.name == 'ナックル' ? 90 : s.aLo + r.nextInt(s.aHi - s.aLo + 1);
    return Pitch(name: s.name, breakLevel: brk, angle: angle, speed: speed, ratio: 0, sharpness: _lerp(s.sLo, s.sHi, sharpBase), heaviness: _lerp(s.hLo, s.hHi, heavyBase));
  }

  static List<Pitch> generate(Player p, Random r, {bool? starter}) {
    final isStarter = starter ?? p.stamina >= 60;
    int pickCount(List<int> values, List<double> w) {
      var x = r.nextDouble() * w.reduce((a, b) => a + b);
      for (var i = 0; i < values.length; i++) {
        x -= w[i];
        if (x <= 0) return values[i];
      }
      return values.last;
    }

    final n = isStarter ? pickCount([4, 5, 6, 7, 8], [30, 30, 22, 12, 6]) : pickCount([3, 4, 5], [40, 40, 20]);
    final chosen = <PitchSpec>[_byName['ストレート']!];
    final perGroup = <String, int>{_s: 1};
    while (chosen.length < n) {
      final cands = all.where((s) => !chosen.contains(s) && s.weight > 0 && (perGroup[s.group] ?? 0) < 2).toList();
      if (cands.isEmpty) break;
      // まだ持っていない系統を少し選びやすく（球種の幅が出るように）
      double w(PitchSpec s) => s.weight * ((perGroup[s.group] ?? 0) == 0 ? 1.6 : 1.0);
      var x = r.nextDouble() * cands.fold<double>(0, (a, s) => a + w(s));
      var pick = cands.last;
      for (final s in cands) {
        x -= w(s);
        if (x <= 0) {
          pick = s;
          break;
        }
      }
      chosen.add(pick);
      perGroup[pick.group] = (perGroup[pick.group] ?? 0) + 1;
    }

    // 能力の寄せ：キレは制球、重さは球威（0〜1。0.5 が平均的）
    final sharpBase = (0.5 + (p.control - 60) / 70.0).clamp(0.05, 0.95);
    final heavyBase = (0.5 + (p.pitchPower - 60) / 70.0).clamp(0.05, 0.95);
    final pitches = <Pitch>[];
    for (final s in chosen) {
      final tSpeed = r.nextDouble(); // 0＝遅い側、1＝速い側
      final diff = _lerp(s.dLo, s.dHi, tSpeed);
      final int speed = max(70, p.velocity + diff);
      final int brk = s.name == 'ストレート' ? 0 : (s.bHi - (s.bHi - s.bLo) * tSpeed + _g(r) * 4 + (sharpBase - 0.5) * 8).round().clamp(max(0, s.bLo - 5), min(100, s.bHi + 5)).toInt();
      final angle = s.name == 'ナックル' ? 90 : s.aLo + r.nextInt(s.aHi - s.aLo + 1);
      final sharp = _lerp(s.sLo, s.sHi, sharpBase + _g(r) * 0.18);
      final heavy = _lerp(s.hLo, s.hHi, heavyBase + _g(r) * 0.18);
      pitches.add(Pitch(name: s.name, breakLevel: brk, angle: angle, speed: speed, ratio: 0, sharpness: sharp, heaviness: heavy));
    }
    // 決め球：変化球でキレのいちばん高いもの
    final breaking = pitches.skip(1).toList();
    Pitch? ace;
    if (breaking.isNotEmpty) {
      ace = breaking.reduce((a, b) => a.sharpness >= b.sharpness ? a : b);
      ace.sharpness = (ace.sharpness + 5 + r.nextInt(6)).clamp(1, 99);
    }
    // 投球割合：直球系の合計 35〜55%、残りを重みで分ける（決め球は多め、イーファスは 2%）
    final fastTotal = 35 + r.nextInt(21);
    final fastOnes = pitches.where((x) => groupOf(x.name) == _s && x.name != 'イーファスピッチ').toList();
    final others = pitches.where((x) => !fastOnes.contains(x)).toList();
    final fw = [for (final x in fastOnes) x.name == 'ストレート' ? 3.0 : 1.0 + r.nextDouble()];
    final ow = [for (final x in others) x.name == 'イーファスピッチ' ? 0.0 : (identical(x, ace) ? 1.8 : 1.0) * (0.6 + r.nextDouble())];
    final fSum = fw.fold<double>(0, (a, b) => a + b), oSum = ow.fold<double>(0, (a, b) => a + b);
    var used = 0;
    for (var i = 0; i < fastOnes.length; i++) {
      fastOnes[i].ratio = max(3, (fastTotal * fw[i] / fSum).round());
      used += fastOnes[i].ratio;
    }
    final eephus = others.where((x) => x.name == 'イーファスピッチ').toList();
    for (final x in eephus) {
      x.ratio = 2;
      used += 2;
    }
    final rest = max(0, 100 - used);
    for (var i = 0; i < others.length; i++) {
      if (others[i].name == 'イーファスピッチ') continue;
      others[i].ratio = oSum == 0 ? 0 : max(3, (rest * ow[i] / oSum).round());
    }
    // 合計を100にそろえる（ストレートで調整）
    final total = pitches.fold<int>(0, (a, x) => a + x.ratio);
    pitches.first.ratio = max(10, pitches.first.ratio + 100 - total);
    return pitches;
  }
}
