import 'dart:math';
import '../models/coach.dart';
import '../models/player.dart';
import '../models/team.dart';
import '../utils/name_pool.dart';
import 'growth_engine.dart';

/// 選手・コーチのタイプと相性、コーチの生成、練習効果の倍率
class CoachEngine {
  static const hitterTypes = ['打撃職人型', 'スラッガー型', '俊足巧打型', '守備職人型', '素材型', '万能型'];
  static const pitcherTypes = ['本格派', '技巧派', '剛腕派', 'イニングイーター'];

  /// 1軍・2軍のコーチの役職
  static const roles1G = ['ヘッド', '打撃', '投手', '守備走塁', 'バッテリー', '一塁', '三塁'];
  static const roles2G = ['2軍監督', '2軍打撃', '2軍投手', '2軍守備走塁', '3軍監督'];
  /// 3軍（育成選手）の練習を見るコーチ。この3つだけ複数人を雇える（仕様書 7.1）
  static const roles3G = ['3軍打撃', '3軍投手', '3軍守備走塁'];
  static bool multiRole(String role) => roles3G.contains(role) || isScout(role);
  static const allRoles = [...roles1G, ...roles2G, ...roles3G];

  /// 3軍コーチ1人が担当できる育成選手の数（仮）
  static const perThirdCoach = 6;

  /// 負荷による練習効果の係数（仕様書 7.2。仮）：負荷＝育成選手の人数÷（3軍コーチの人数×担当できる人数）
  static double loadFactor(int ikusei, int thirdCoaches) {
    if (ikusei == 0) return 1.0;
    final cap = thirdCoaches * perThirdCoach;
    if (cap == 0) return 0.8;
    final load = ikusei / cap;
    if (load > 1.0) return (1.0 - (load - 1.0) * 0.4).clamp(0.6, 0.95); // 上限を超えた分だけ下がる
    if (load > 0.8) return 1.0;
    if (load > 0.6) return 1.05;
    return 1.08;
  }
  /// スカウト：チーフ（1〜3人）は必ず置く。地区担当（地区ごとに最大2人）・海外担当（リーグごとに最大2人）は雇った分だけ
  static const scoutRoles = ['チーフスカウト'];
  static const regionScoutPrefix = '地区スカウト・', overseasScoutPrefix = '海外スカウト・';
  static bool isScout(String? role) => role != null && (role == 'チーフスカウト' || role.startsWith(regionScoutPrefix) || role.startsWith(overseasScoutPrefix));
  /// その役職に置ける人数
  static int maxOf(String role) => role == 'チーフスカウト' ? 3 : (isScout(role) ? 2 : 99);
  /// 役職ごとに主に見る能力（地区・海外のスカウトも眼力）
  static List<String> keysOf(String role) => roleKeys[role] ?? (isScout(role) ? const ['スカウト眼力'] : const ['人望']);
  /// スカウトの年俸の目安（眼力が高いほど高い。600万〜2,800万）
  static int scoutSalary(Coach c) => ((1000 + ((c.expected['スカウト眼力'] ?? 50) - 50) * 35).clamp(600, 2800) / 10).round() * 10;
  static const staffRoles = [...allRoles, ...scoutRoles];

  /// 役職ごとに主に見る能力（一覧に出す）
  static const roleKeys = {
    'ヘッド': ['人望', '代打判断', '継投判断'],
    '打撃': ['打撃', '人望'],
    '投手': ['球速球威', '制球', 'スタミナ', '継投判断'],
    '守備走塁': ['守備', '走塁', '守備交代判断'],
    'バッテリー': ['守備', '制球', '継投判断'],
    '一塁': ['走塁判断', '走塁'],
    '三塁': ['走塁判断', '走塁'],
    '2軍監督': ['育成眼', '人望', '代打判断', '継投判断'], // 育成眼：若手の伸びしろ（特に向上心）を見抜いて2軍で使い、練習を合わせる
    '2軍打撃': ['打撃', '人望'],
    '2軍投手': ['球速球威', '制球', 'スタミナ'],
    '2軍守備走塁': ['守備', '走塁'],
    '3軍打撃': ['打撃', '人望'],
    '3軍投手': ['球速球威', '制球', 'スタミナ'],
    '3軍守備走塁': ['守備', '走塁'],
    '3軍監督': ['育成眼', '人望', '代打判断'], // 3軍戦のオーダー（誰に試合経験を積ませるか）を決める
    'チーフスカウト': ['スカウト眼力'],
    'スカウト': ['スカウト眼力'],
    '監督': ['代打判断', '継投判断', '守備交代判断', '走塁判断', '育成眼'], // 育成眼：伸び盛りの若手を見抜いて1軍に抜擢する
  };

  /// CPU 監督の傾向（0〜100）。bunt=バント、steal=盗塁、bullpen=継投の早さ、youth=若手起用
  static Map<String, int> managerStyle(Coach c, Random r) {
    int v(num base) => (base + r.nextInt(31) - 15).round().clamp(5, 95).toInt();
    final small = c.type == '俊足巧打型' || c.type == '守備職人型' || c.type == '技巧派';
    final power = c.type == 'スラッガー型' || c.type == '剛腕派';
    return {
      'bunt': v(small ? 65 : (power ? 30 : 48)),
      'steal': v(c.type == '俊足巧打型' ? 70 : (power ? 35 : 50)),
      'bullpen': v(c.pitcherBg ? 55 : 48),
      'youth': v(c.age < 52 ? 58 : 45),
      'potential': v(c.age < 50 ? 60 : 42), // 選手を見る目：0=実績・現在重視、100=将来性重視
    };
  }

  /// 傾向の言葉
  static String styleText(Map<String, int> s) {
    final out = <String>[];
    if ((s['bunt'] ?? 50) >= 62) out.add('バント多用');
    if ((s['bunt'] ?? 50) <= 35) out.add('強攻');
    if ((s['steal'] ?? 50) >= 62) out.add('機動力');
    if ((s['bullpen'] ?? 50) >= 62) out.add('継投が早い');
    if ((s['bullpen'] ?? 50) <= 35) out.add('先発を引っぱる');
    if ((s['youth'] ?? 50) >= 62) out.add('若手起用');
    if ((s['potential'] ?? 50) >= 62) out.add('将来性重視');
    if ((s['potential'] ?? 50) <= 38) out.add('実績重視');
    return out.isEmpty ? '堅実' : out.join('・');
  }

  /// 投手出身が向く役職
  static bool pitcherRole(String role) => role == '投手' || role == '2軍投手' || role == '3軍投手' || role == 'バッテリー';

  // ───────── タイプ ─────────

  static int _fieldMain(Player p) {
    switch (p.mainPosition) {
      case '捕手': return p.fieldC;
      case '一塁手': return p.field1B;
      case '二塁手': return p.field2B;
      case '三塁手': return p.field3B;
      case '遊撃手': return p.fieldSS;
      case '左翼手': return p.fieldLF;
      case '中堅手': return p.fieldCF;
      case '右翼手': return p.fieldRF;
    }
    return 50;
  }

  static int _breaking(Player p) {
    final bs = p.pitches.where((x) => x.breakLevel > 0).toList();
    if (bs.isEmpty) return 40;
    return (bs.map((x) => (x.sharpness + x.breakLevel) / 2).reduce((a, b) => a + b) / bs.length).round().clamp(1, 100);
  }

  /// 能力の傾向からタイプを1つ決める（平均との差が大きい組み合わせ。どれも突出していなければ万能型・本格派）
  static String playerType(Player p) {
    // 指定があればそれ（投手・野手に合うものだけ）
    if (p.typeSet.isNotEmpty && (p.isPitcher ? pitcherTypes : hitterTypes).contains(p.typeSet)) return p.typeSet;
    return autoType(p);
  }

  /// 能力から決まるタイプ
  static String autoType(Player p) {
    // リーグのおおよその平均との差で比べる（選手自身の平均だと、全員が同じ値の能力に引っぱられるため）
    if (p.isPitcher) {
      final v = {'velo': p.velocityNorm, 'power': p.pitchPower, 'control': p.control, 'stamina': p.stamina, 'break': _breaking(p)};
      double d(String k) => (v[k]! - _refP[k]!).toDouble();
      final score = {
        '技巧派': (d('control') + d('break')) / 2,
        '剛腕派': (d('velo') + d('power')) / 2,
        'イニングイーター': (d('velo') + d('stamina') * 1.5) / 2.5,
      };
      final best = score.entries.reduce((a, b) => a.value >= b.value ? a : b);
      return best.value >= 6 ? best.key : '本格派';
    }
    final f = _fieldMain(p);
    final v = {'contact': p.contact, 'power': p.power, 'eye': p.eye, 'clutch': p.clutch, 'run': p.run, 'arm': p.arm, 'throw': p.throwAccuracy, 'catch': p.catchSkill, 'field': f};
    double d(String k) => (v[k]! - _refB[k]!).toDouble();
    final score = {
      '打撃職人型': (d('contact') * 2 + d('eye') + d('clutch')) / 4,
      'スラッガー型': (d('contact') + d('power') * 2) / 3,
      '俊足巧打型': (d('contact') + d('run') + d('field')) / 3,
      '守備職人型': (d('field') + d('throw') + d('catch')) / 3,
      '素材型': (d('power') + d('run') + d('arm')) / 3,
    };
    final best = score.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value >= 4 ? best.key : '万能型';
  }

  static const _refB = {'contact': 64, 'power': 62, 'eye': 50, 'clutch': 60, 'run': 62, 'arm': 62, 'throw': 60, 'catch': 60, 'field': 60};
  static const _refP = {'velo': 62, 'power': 60, 'control': 66, 'stamina': 64, 'break': 55};

  static const _near = {
    '打撃職人型': {'俊足巧打型', 'スラッガー型'},
    'スラッガー型': {'打撃職人型', '素材型'},
    '俊足巧打型': {'打撃職人型', '守備職人型', '素材型'},
    '守備職人型': {'俊足巧打型'},
    '素材型': {'スラッガー型', '俊足巧打型'},
    '剛腕派': {'イニングイーター'},
    'イニングイーター': {'剛腕派'},
  };
  static const _far = {
    '守備職人型': {'スラッガー型', '素材型'},
    'スラッガー型': {'守備職人型'},
    '打撃職人型': {'素材型'},
    '素材型': {'打撃職人型', '守備職人型'},
    '技巧派': {'剛腕派'},
    '剛腕派': {'技巧派'},
  };

  /// 相性の係数（同じ ×1.2、近い ×1.05、遠い ×0.9。万能型・本格派はどれとも少し合う。野手と投手の組み合わせは ×0.95）
  static double affinity(String coachType, String playerType) {
    final cp = pitcherTypes.contains(coachType), pp = pitcherTypes.contains(playerType);
    if (cp != pp) return 0.95;
    if (coachType == playerType) return 1.2;
    if (coachType == '万能型' || coachType == '本格派' || playerType == '万能型' || playerType == '本格派') return 1.05;
    if (_near[coachType]?.contains(playerType) ?? false) return 1.05;
    if (_far[coachType]?.contains(playerType) ?? false) return 0.9;
    return 1.0;
  }

  /// 相性の言葉
  static String affinityLabel(double a) => a >= 1.2 ? '◎' : (a >= 1.05 ? '○' : (a <= 0.9 ? '×' : '−'));

  // ───────── 練習効果の倍率 ─────────

  /// 練習効果の倍率 ＝（指導力÷60）× 相性 × 人望の補正（0.85〜1.15）。0.6〜1.8
  ///  ※企画書は「指導力÷50」だが、生成するコーチの平均がおよそ60なので、平均で1倍になるよう60で割る
  ///  育成選手は3軍のコーチ（複数人なら平均）が見て、負荷の係数をかける。3軍のコーチがいなければ2軍のコーチ（×0.9）
  static double practiceMultiplier(Player p, GrowthStat s, Team t, Map<String, Coach> staff, {Map<String, List<Coach>> third = const {}, int ikuseiCount = 0}) {
    final farm = !t.roster1G.contains(p.id);
    final ik = p.ikusei;
    String role;
    String key;
    switch (s.group) {
      case 'bat':
        role = ik ? '3軍打撃' : (farm ? '2軍打撃' : '打撃');
        key = '打撃';
        break;
      case 'field':
        role = ik ? '3軍守備走塁' : (farm ? '2軍守備走塁' : '守備走塁');
        key = s.key == 'run' ? '走塁' : '守備';
        break;
      case 'pitch':
        role = ik ? '3軍投手' : (farm ? '2軍投手' : '投手');
        key = const {'velocity': '球速球威', 'pitchPower': '球速球威', 'control': '制球', 'clutchPitching': '制球', 'stamina': 'スタミナ'}[s.key] ?? (s.key.endsWith('heaviness') ? '球速球威' : '制球'); // 球種の重さは球威、キレ・変化量は制球の指導力
        break;
      default:
        return 1.0;
    }
    double one(Coach c) {
      final abil = c.trueAbil[key] ?? 50;
      final rep = 0.85 + (c.trueAbil['人望'] ?? 50) / 100 * 0.3;
      return (abil / 60) * affinity(c.type, playerType(p)) * rep;
    }

    if (ik) {
      final list = third[role] ?? const <Coach>[];
      final n = third.values.fold<int>(0, (a, l) => a + l.length);
      final lf = loadFactor(ikuseiCount, n);
      if (list.isEmpty) {
        final c2 = staff[role.replaceFirst('3軍', '2軍')];
        return ((c2 == null ? 0.9 : one(c2) * 0.9) * lf).clamp(0.6, 1.8);
      }
      final avg = list.map(one).reduce((a, b) => a + b) / list.length;
      return (avg * lf).clamp(0.6, 1.8);
    }
    final c = staff[role];
    if (c == null) return 0.9; // 空席
    return one(c).clamp(0.6, 1.8);
  }

  // ───────── 生成 ─────────


  static int _c(num v) => v.round().clamp(20, 95).toInt();

  /// 架空のコーチ・OBを1人作る
  /// 育成眼（1〜100）。以前のセーブのコーチには無いので、id から固定で決めて足す
  static int devEye(Coach c) {
    final v = c.trueAbil['育成眼'];
    if (v != null) return v;
    final r = Random(c.id.hashCode ^ 0x6e1d);
    final e = _c(38 + (c.age - 45) * 0.4 + r.nextInt(42));
    c.expected['育成眼'] = e;
    c.trueAbil['育成眼'] = _c((e + 30 + r.nextInt(61)) / 2);
    return c.trueAbil['育成眼']!;
  }

  static Coach generate(Random r, String id, {required bool pitcherBg, required String formerTeamId, required int age}) {
    final type = pitcherBg
        ? const ['本格派', '技巧派', '剛腕派', 'イニングイーター'][r.nextInt(4)]
        : const ['打撃職人型', 'スラッガー型', '俊足巧打型', '守備職人型', '素材型', '万能型'][r.nextInt(6)];
    final career = <String, int>{};
    final exp = <String, int>{};
    double fame;
    if (pitcherBg) {
      final reliever = r.nextDouble() < 0.4;
      final games = 120 + r.nextInt(560);
      final wins = reliever ? 5 + r.nextInt(50) : 10 + r.nextInt(200);
      final saves = reliever ? r.nextInt(260) : r.nextInt(10);
      final era = 260 + r.nextInt(200);
      career.addAll({'games': games, 'wins': wins, 'saves': saves, 'era': era});
      fame = (wins / 200 + saves / 250).clamp(0, 1.2);
      exp['球速球威'] = _c(48 + (type == '剛腕派' ? 16 : 0) + (type == 'イニングイーター' ? 6 : 0) + wins / 220 * 12);
      exp['制球'] = _c(48 + (type == '技巧派' ? 16 : 0) + (era < 320 ? 6 : 0));
      exp['スタミナ'] = _c(46 + (type == 'イニングイーター' ? 16 : 0) + (reliever ? -4 : 6));
      exp['変化球'] = _c(48 + (type == '技巧派' ? 14 : 0) + (type == '本格派' ? 5 : 0));
      exp['打撃'] = _c(32 + r.nextInt(18));
      exp['守備'] = _c(38 + r.nextInt(20));
      exp['走塁'] = _c(32 + r.nextInt(18));
    } else {
      final games = 300 + r.nextInt(2100);
      final avg = 230 + r.nextInt(80);
      final hits = (games * 3.2 * avg / 1000).round();
      final hr = (games * (type == 'スラッガー型' ? 0.16 : (type == '素材型' ? 0.10 : 0.05)) * (0.6 + r.nextDouble() * 0.8)).round();
      career.addAll({'games': games, 'hits': hits, 'hr': hr, 'avg': avg});
      fame = (hits / 2000 + hr / 400).clamp(0, 1.2);
      exp['打撃'] = _c(44 + hits / 2500 * 28 + (avg - 260) * 0.12 + (type == '打撃職人型' || type == 'スラッガー型' ? 6 : 0));
      exp['守備'] = _c(48 + (type == '守備職人型' ? 18 : 0) + (type == '俊足巧打型' ? 6 : 0));
      exp['走塁'] = _c(46 + (type == '俊足巧打型' ? 18 : 0) + (type == '素材型' ? 8 : 0));
      exp['球速球威'] = _c(32 + r.nextInt(16));
      exp['制球'] = _c(32 + r.nextInt(16));
      exp['スタミナ'] = _c(32 + r.nextInt(16));
      exp['変化球'] = _c(32 + r.nextInt(16));
    }
    exp['人望'] = _c(44 + fame * 16 + r.nextInt(21) - 10);
    for (final k in ['代打判断', '継投判断', '守備交代判断', '走塁判断']) {
      exp[k] = _c(40 + (age - 40) * 0.5 + r.nextInt(26) - 8);
    }
    exp['スカウト眼力'] = _c(38 + r.nextInt(42));
    exp['育成眼'] = _c(38 + (age - 45) * 0.4 + r.nextInt(42));
    // 本当の値 ＝ 予想 50% ＋ 隠れた値 50%
    final tr = <String, int>{};
    for (final k in Coach.abilityKeys) {
      final hidden = 30 + r.nextInt(61);
      tr[k] = _c((exp[k]! + hidden) / 2);
    }
    final c = Coach(
      id: id,
      lastName: NamePool.jpLast(r),
      firstName: NamePool.jpFirst(r, older: true),
      age: age,
      pitcherBg: pitcherBg,
      type: type,
      formerTeamId: formerTeamId,
      career: career,
      trueAbil: tr,
      expected: exp,
    );
    c.salary = askingSalary(c, formerTeamId);
    return c;
  }

  /// 年俸の目安（予想される指導力から。古巣以外の球団には ×1.3）
  static int askingSalary(Coach c, String teamId) {
    final vals = Coach.teachKeys.map((k) => c.expected[k] ?? 50).toList()..sort((a, b) => b.compareTo(a));
    final m = (vals[0] + vals[1] + (c.expected['人望'] ?? 50)) / 3;
    var s = 800 + (m - 50) * 60;
    if (teamId.isNotEmpty && c.formerTeamId != teamId) s *= 1.3;
    return ((s.clamp(400, 4000)) / 10).round() * 10;
  }

  /// 1球団分のコーチを作る（すべての役職）
  static List<Coach> staffFor(Team t, Random r, int Function() nextId) {
    final out = <Coach>[];
    for (final role in staffRoles) {
      final c = generate(r, 'CO${nextId()}', pitcherBg: pitcherRole(role) || ((role == 'ヘッド' || scoutRoles.contains(role)) && r.nextBool()), formerTeamId: r.nextDouble() < 0.7 ? t.id : '', age: 40 + r.nextInt(25));
      c.teamId = t.id;
      c.role = role;
      c.seasonsWithTeam = 1 + r.nextInt(4);
      c.known = true; // 長く在籍しているコーチは能力が分かっている
      c.salary = askingSalary(c, t.id);
      out.add(c);
    }
    return out;
  }
}
