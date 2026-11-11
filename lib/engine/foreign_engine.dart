import 'dart:math';
import 'velo.dart';
import '../utils/name_data.dart';
import '../models/player.dart';
import '../models/prospect.dart';
import '../utils/name_pool.dart';
import '../utils/player_traits.dart';
import '../utils/salary_utils.dart';
import 'draft_engine.dart';
import 'fielding_gen.dart';
import 'pitch_catalog.dart';

/// 外国人選手：毎年12月1日の一覧（支配下120人・育成60人）、出身国、海外での成績、環境適応力
///  支配下：今の能力は ±5 の幅、環境適応力はスカウトの眼力に応じた幅で分かる。入団時に能力へ倍率（D50×0.8・C60×0.9・B70×1.0）
///  育成：ドラフトと同じく才能・向上心の見立て
class ForeignEngine {
  static const mainCount = 120, ikuseiCount = 60;

  static double _g(Random r) => sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

  // ───────── 出身国 ─────────

  static const _latinLast = {
    'モラレス', 'ガルシア', 'サンタナ', 'クルーズ', 'リベラ', 'オルティス', 'ペーニャ', 'ロドリゲス', 'マルティネス', 'ヘルナンデス', 'ロペス', 'ゴンザレス', 'ペレス', 'サンチェス', 'ラミレス', 'トーレス',
    'フローレス', 'ディアス', 'レイエス', 'グティエレス', 'メンドーサ', 'カスティーヨ', 'バルガス', 'アルバレス', 'ナバーロ', 'エスコバル', 'カマーチョ', 'オロスコ', 'パディーヤ', 'ベラスケス', 'アギラール',
    'マドリガル', 'セラーノ', 'ロサリオ', 'フエンテス', 'カリーヨ', 'モンテロ', 'バティスタ', 'コルデロ',
  };
  static const _korean = {'朴', '金', '崔', '鄭', '姜', '尹'};

  static String _pick(Random r, List<(String, int)> w) {
    var x = r.nextInt(w.fold(0, (a, e) => a + e.$2));
    for (final e in w) {
      x -= e.$2;
      if (x < 0) return e.$1;
    }
    return w.last.$1;
  }

  /// 名前から出身国を決める（漢字＝韓国・台湾、スペイン語の姓＝中南米、それ以外＝米国・豪州・カナダ）
  static String originFor(Player p, Random r) {
    if (p.nameType == 'B') return (_korean.contains(p.lastName) || NameData.koreanLastSet.contains(p.lastName)) && !NameData.chineseLast.contains(p.lastName) ? '韓国' : (NameData.koreanLastSet.contains(p.lastName) && r.nextBool() ? '韓国' : '台湾');
    if (_latinLast.contains(p.lastName) || NameData.latinLastSet.contains(p.lastName)) return _pick(r, [('ドミニカ', 60), ('キューバ', 20), ('メキシコ', 20)]);
    if (NameData2.czechLast.contains(p.lastName)) return 'チェコ';
    return _pick(r, [('アメリカ', 88), ('オーストラリア', 12)]);
  }

  // ───────── 海外での成績 ─────────

  static const _avgAdj = {'MLB': -0.030, '3A': 0.0, '2A': 0.008, '1A': 0.015, '米独立': 0.020, 'メキシカンリーグ': 0.035, '豪州リーグ': 0.015, 'ドミニカンリーグ': -0.005, 'KBO': 0.020, 'CPBL': 0.030};
  static const _eraAdj = {'MLB': 0.9, '3A': 0.35, '2A': 0.0, '1A': -0.2, '米独立': -0.2, 'メキシカンリーグ': 0.8, '豪州リーグ': 0.2, 'ドミニカンリーグ': 0.0, 'KBO': 0.4, 'CPBL': 0.6};
  static const _hrMul = {'MLB': 0.75, '3A': 1.0, '2A': 0.85, '1A': 0.7, '米独立': 0.9, 'メキシカンリーグ': 1.25, '豪州リーグ': 0.9, 'ドミニカンリーグ': 0.7, 'KBO': 1.05, 'CPBL': 1.1};
  static const _usLadder = ['1A', '2A', '3A', 'MLB'];

  /// その年にプレーしたリーグ（1〜2つ）。q は来日前の総合力
  static List<String> _leagues(String origin, double q, int seasonsAgo, bool young, Random r) {
    final lift = -seasonsAgo * 0.8; // 昔ほど下のレベル
    switch (origin) {
      case '韓国':
        return ['KBO'];
      case '台湾':
        return ['CPBL'];
      case 'メキシコ':
        return [if (!young && q + lift >= 64 && r.nextDouble() < 0.4) '3A', 'メキシカンリーグ'];
      case 'オーストラリア':
        final lv = _usLevel(q + lift, young);
        return [lv, if (r.nextDouble() < 0.6) '豪州リーグ'];
    }
    // 米国・中南米：マイナーとメジャーのはしご。中南米はドミニカのウィンターリーグにも出る
    final latin = origin != 'アメリカ' && origin != 'カナダ';
    if (young && latin && seasonsAgo >= 1) return ['ドミニカンリーグ'];
    final lv = _usLevel(q + lift, young);
    final out = <String>[];
    if (lv == '米独立') {
      out.add('米独立');
    } else {
      final i = _usLadder.indexOf(lv);
      // 上のレベルにも昇格していた年（例：3A と MLB の両方）
      if (i < 3 && r.nextDouble() < 0.35 && q + lift >= 58 + i * 5) out.add(_usLadder[i + 1]);
      out.add(lv);
    }
    if (latin && r.nextDouble() < 0.45) out.add('ドミニカンリーグ');
    return out.toSet().toList();
  }

  static String _usLevel(double q, bool young) {
    if (young) return q >= 50 ? '2A' : '1A';
    if (q >= 72) return 'MLB';
    if (q >= 62) return '3A';
    if (q >= 55) return '2A';
    return q >= 50 ? '1A' : '米独立';
  }

  static String _f3(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');

  /// share：その年にそのリーグで出た割合（2つのレベルを行き来した年は 1 未満）
  static String _line(Player p, String lg, int year, double share, Random r) {
    final winter = lg == 'ドミニカンリーグ' || lg == '豪州リーグ';
    if (p.isPitcher) {
      final q = (p.pitchPower + p.control) / 2;
      final era = (4.1 - (q - 60) * 0.06 + (_eraAdj[lg] ?? 0) + _g(r) * 0.55).clamp(1.10, 7.80);
      final starter = p.stamina >= 55;
      var games = starter ? 14 + r.nextInt(17) : 28 + r.nextInt(36);
      if (share < 1) games = (games * share).round().clamp(3, 40);
      if (winter) games = (games * 0.45).round().clamp(4, 30);
      final ip = games * (starter ? 4.8 + r.nextDouble() * 1.2 : 0.9 + r.nextDouble() * 0.3);
      final k = (ip * (0.72 + (p.pitchPower - 55) * 0.012 + _g(r) * 0.06)).round().clamp(0, 400);
      final dec = starter ? games * 0.62 : games * 0.18;
      final wr = (0.5 + (4.2 - era) * 0.07).clamp(0.2, 0.8);
      final w = (dec * wr).round(), l = (dec * (1 - wr)).round();
      final sv = !starter && p.pitchPower >= 65 && r.nextDouble() < 0.4 ? (games * (0.3 + r.nextDouble() * 0.3)).round() : 0;
      return '$year　$lg　$games試合 $w勝$l敗${sv > 0 ? '$sv S' : ''} 防御率${era.toStringAsFixed(2)} ${(ip * 3).round() ~/ 3}${(ip * 3).round() % 3 == 0 ? '' : '.${(ip * 3).round() % 3}'}回 $k奪三振';
    }
    var games = 95 + r.nextInt(50);
    if (lg == 'KBO') games = 100 + r.nextInt(45);
    if (lg == 'CPBL') games = 80 + r.nextInt(40);
    if (share < 1) games = (games * share).round().clamp(8, 120);
    if (winter) games = 18 + r.nextInt(28);
    final avg = (0.248 + (p.contact - 60) * 0.0028 + (_avgAdj[lg] ?? 0) + _g(r) * 0.016).clamp(0.170, 0.370);
    final ab = (games * (3.4 + r.nextDouble() * 0.5)).round();
    final hr = max(0, (games * max(0.015, (p.power - 45) * 0.0055) * (_hrMul[lg] ?? 1) + _g(r) * 3).round());
    final rbi = (hr * 2.5 + games * 0.22 + _g(r) * 6).round().clamp(hr, 200);
    final obp = avg + 0.062 + (p.eye - 55) * 0.0012;
    final slg = avg + hr / max(1, ab) * 3.1 + 0.075 + (p.power - 60) * 0.0015;
    return '$year　$lg　$games試合 打率${_f3(avg)} $hr本 $rbi打点 OPS${_f3(obp + slg)}';
  }

  /// 来日前の成績（新しい順）。lastYear は来日前の最後のシーズン
  static List<String> abroadRecord(Player p, String origin, int lastYear, Random r, {bool young = false, double? quality}) {
    final q = quality ?? p.ovr.toDouble();
    final maxSeasons = young ? (p.age - 17).clamp(1, 3) : 3 + r.nextInt(3);
    final out = <String>[];
    for (var k = 0; k < maxSeasons; k++) {
      final lgs = _leagues(origin, q, k, young, r);
      // 2つのレベルを行き来した年は、試合数を分け合う（冬のリーグは別）
      final main = lgs.where((l) => l != 'ドミニカンリーグ' && l != '豪州リーグ').toList();
      final up = 0.25 + r.nextDouble() * 0.4;
      for (final lg in lgs) {
        final share = main.length < 2 || !main.contains(lg) ? 1.0 : (lg == main.first ? up : 1.0 - up + 0.1);
        out.add(_line(p, lg, lastYear - k, share, r));
      }
    }
    return out;
  }

  // ───────── 環境適応力 ─────────

  /// 入団時の倍率（D50×0.8・C60×0.9・B70×1.0。上は ×1.1、下は ×0.6 まで）
  static double adaptMult(int a) => (0.8 + (a - 50) * 0.01).clamp(0.6, 1.1);

  /// 入団時に適応力の倍率をかける（打撃・投球の能力と球種のキレ。球速・走力・肩・守備・スタミナは体のものなので変えない）
  static void applyAdapt(Player p) {
    final m = adaptMult(p.adapt);
    int f(int v) => (v * m).round().clamp(1, 100);
    p.contactLeft = f(p.contactLeft);
    p.contactRight = f(p.contactRight);
    p.power = f(p.power);
    p.eye = f(p.eye);
    p.clutch = f(p.clutch);
    if (p.isPitcher) {
      p.pitchPower = f(p.pitchPower);
      p.control = f(p.control);
      p.clutchPitching = f(p.clutchPitching);
      for (final x in p.pitches) {
        x.sharpness = f(x.sharpness);
      }
    }
  }

  /// 見立ての中心のずれ（選手ごとに固定。本当の値は必ず幅に入る）
  static double _bias(Player p, int salt) => (Random(p.id.hashCode ^ salt).nextDouble() * 2 - 1) * 0.8;

  static (int, int) _range(Player p, int v, int eye, int salt) {
    final err = DraftEngine.traitError(eye);
    final c = v + _bias(p, salt) * err;
    return ((c - err).round().clamp(1, 100), (c + err).round().clamp(1, 100));
  }

  /// 環境適応力の見立て（スカウトの眼力が高いほど狭い）
  static (int, int) adaptRange(Player p, int eye) => _range(p, p.adapt, eye, 0xada);

  /// 一覧の画面用に、ドラフト候補と同じ形の見立てを作る（今の能力 ±5、育成は才能・向上心）
  static Prospect view(Player p, int eye, int year) {
    final pr = Prospect(
      player: p,
      year: year,
      category: p.origin.isEmpty ? '海外' : p.origin,
      school: p.abroad.isEmpty ? '' : p.abroad.first.split('　')[1],
      ikuseiTier: p.ikusei,
      curBias: (Random(p.id.hashCode ^ 0xcb).nextInt(9)) - 4,
      reports: 1,
      memo: p.abroad,
    );
    if (p.ikusei) {
      final (tl, th) = _range(p, p.talent, eye, 0x51);
      final (al, ah) = _range(p, p.ambition, eye, 0x52);
      pr.talentLo = tl;
      pr.talentHi = th;
      pr.ambitionLo = al;
      pr.ambitionHi = ah;
    }
    return pr;
  }

  /// CPU 球団の見立てでの「入団後の総合力」（支配下）
  static double perceivedOvr(Player p, int eye) {
    final (lo, hi) = adaptRange(p, eye);
    return p.ovr * adaptMult(((lo + hi) / 2).round());
  }

  // ───────── 一覧（12月1日） ─────────

  static List<Player> market(int year, Random r) {
    final out = <Player>[];
    for (var i = 0; i < mainCount + ikuseiCount; i++) {
      final ikusei = i >= mainCount;
      // 支配下は上位ほど強い（上位は入団してすぐスタメン級）。育成は若く、伸びしろで勝負
      final age = ikusei ? 18 + r.nextInt(8) : 26 + r.nextInt(7);
      final mean = ikusei ? 42 + (age - 18) * 1.2 + _g(r) * 4 : 73 - i * 0.16 + _g(r) * 3;
      out.add(make(year, r, ikusei: ikusei, age: age, mean: mean));
    }
    return out;
  }

  /// 提携枠の候補（仕様書 3.3）：流出した選手を獲った大リーグ球団が出すプロスペクト。
  ///  value（流出した選手の価値）に釣り合わせる：価値が高いほど、今の力も才能も高い若手
  static List<Player> partnerProspects(int year, Random r, double value, String mlbTeam, {int count = 5}) {
    final out = <Player>[];
    for (var i = 0; i < count; i++) {
      final age = 20 + r.nextInt(6); // 25歳以下
      final mean = (44 + (value - 65) * 0.6 + (age - 20) * 1.5 + _g(r) * 3).clamp(38.0, 68.0);
      final p = make(year, r, ikusei: false, age: age, mean: mean);
      p.talent = (60 + (value - 65) * 0.8 + _g(r) * 8).round().clamp(40, 99);
      p.ambition = (60 + _g(r) * 12).round().clamp(30, 99);
      // 提携の候補は成長率1.50以上
      while (p.growthRate < 1.5 && (p.talent < 99 || p.ambition < 99)) {
        p.talent = (p.talent + 3).clamp(1, 99);
        p.ambition = (p.ambition + 3).clamp(1, 99);
      }
      p.salary = round50(estimateSalary(p) * 0.6);
      p.draftInfo = '提携選手（$mlbTeamから・$year年）';
      out.add(p);
    }
    return out;
  }

  /// 外国人選手を1人作る（mean：能力の平均の目安）
  /// NPB に来る外国人の出身国の割合
  static const npbMix = [('アメリカ', 45), ('ドミニカ', 20), ('キューバ', 8), ('メキシコ', 7), ('台湾', 6), ('韓国', 6), ('オーストラリア', 5), ('チェコ', 3)];

  static Player make(int year, Random r, {required bool ikusei, required int age, required double mean, String? id, String? origin}) {
    final org = origin ?? NamePool.pickCountry(r, npbMix);
    int s(double m, double sd, {int lo = 20, int hi = 95}) => (m + _g(r) * sd).round().clamp(lo, hi);
    {
      final isPitcher = r.nextDouble() < 0.5;
      final pos = isPitcher ? '投手' : ['一塁手', '一塁手', '左翼手', '右翼手', '三塁手', '中堅手', '二塁手', '遊撃手', '捕手'][r.nextInt(9)];
      final pid = id ?? 'F${year}_${r.nextInt(1 << 30)}';
      final name = NamePool.forOrigin(org, r);
      Player p;
      if (isPitcher) {
        final vn = s(mean - 2, 7); // 来日する投手でも 160km 超えはまれ
        p = Player(
          id: pid, isPitcher: true, firstName: name.first, lastName: name.last, nameType: name.nameType, nationality: '海外', mainPos: '投手', age: age,
          height: 178 + r.nextInt(20), throws: r.nextInt(3) == 0 ? 'L' : 'R',
          contactLeft: s(25, 5), contactRight: s(25, 5), power: s(30, 6), run: s(40, 8), arm: s(60, 8), throwAccuracy: s(55, 8), catchSkill: s(55, 8),
          eye: s(25, 5), clutch: s(50, 8),
          velocity: 120 + vn ~/ 2, pitchPower: s(mean + 3, 6), control: s(mean - 4, 7), stamina: s(mean, 9), clutchPitching: s(mean, 7),
        );
        Velo.liftNew(p); // 海外のプロ：プロの水準に底上げ
        p.pitches = PitchCatalog.generate(p, r, starter: p.stamina >= mean);
      } else {
        final c = s(mean - 2, 6);
        p = Player(
          id: pid, isPitcher: false, firstName: name.first, lastName: name.last, nameType: name.nameType, nationality: '海外', mainPos: pos, age: age,
          height: 176 + r.nextInt(22), bats: ['R', 'L', 'R'][r.nextInt(3)], trajectory: [3, 3, 4, 4, 2][r.nextInt(5)],
          contactLeft: c, contactRight: (c + _g(r) * 3).round().clamp(20, 95), power: s(mean + 9, 7), run: s(mean - 6, 8), arm: s(mean, 8),
          throwAccuracy: s(mean - 4, 7), catchSkill: s(mean - 4, 7), eye: s(mean + 8, 8), clutch: s(mean - 2, 8),
          velocity: 130, pitchPower: 20, control: 20, stamina: 20,
        );
      }
      final f = FieldingGen.generate(p.mainPosition, r);
      p.fieldP = f['投手']!;
      p.fieldC = f['捕手']!;
      p.field1B = f['一塁手']!;
      p.field2B = f['二塁手']!;
      p.field3B = f['三塁手']!;
      p.fieldSS = f['遊撃手']!;
      p.fieldLF = f['左翼手']!;
      p.fieldCF = f['中堅手']!;
      p.fieldRF = f['右翼手']!;
      FieldingGen.blendSkill(p);
      assignTraits(p, r);
      p.quick = (p.quick + 10).clamp(1, 99); // クイックは平均60
      p.proYears = 1;
      p.faService = 0;
      p.ikusei = ikusei;
      p.draftInfo = '外国人選手（$year年${ikusei ? '・育成' : ''}）';
      p.adapt = (60 + _g(r) * 13).round().clamp(20, 95);
      p.origin = org;
      p.abroad = abroadRecord(p, p.origin, year - 1, r, young: ikusei);
      if (ikusei) {
        // 育成：ドラフトと同じく才能・向上心で勝負（若いほどばらつく）
        p.talent = (55 + _g(r) * (age <= 20 ? 16 : 12)).round().clamp(1, 100);
        p.ambition = (55 + _g(r) * 15).round().clamp(1, 100);
        p.salary = 300 + r.nextInt(4) * 100;
      } else {
        p.salary = round50(estimateSalary(p) * (0.55 + r.nextDouble() * 0.3));
        p.ambition = (p.ambition * 0.8).round().clamp(1, 100); // ほぼ完成している（向上心は控えめ）
      }
      return p;
    }
  }

  /// 以前のデータの外国人（球団にいる選手）に、出身国と来日前の成績を付ける
  static void fillMissing(Player p, int currentYear) {
    if (p.nationality != '海外' || p.abroad.isNotEmpty) return;
    final r = Random(p.id.hashCode ^ 0xab70ad);
    if (p.origin.isEmpty) p.origin = originFor(p, r);
    final int joined = currentYear - max(1, p.proYears).toInt() + 1;
    final int ageAtJoin = p.age - (currentYear - joined);
    final young = ageAtJoin <= 24;
    final saveAge = p.age;
    p.age = ageAtJoin;
    p.abroad = abroadRecord(p, p.origin, joined - 1, r, young: young, quality: p.ovr / 0.9);
    p.age = saveAge;
  }
}
