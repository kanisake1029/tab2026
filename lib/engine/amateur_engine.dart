import 'dart:math';
import '../models/amateur.dart';
import '../utils/name_data.dart';
import '../utils/town_data.dart';
import 'other_league_engine.dart';
import 'amateur_season.dart';

/// アマチュア球界（高校3,400校・大学54校・社会人）の生成と、毎年4月の切り替え
class AmateurEngine {
  static const hsCount = 3400;
  static const univPerRegion = 18; // 1地区3リーグ×6校
  static const leaguesPerRegion = 3;
  /// 作り方の版（上がったら、発掘した選手がいなければ作り直す）
  static const genVersion = 2;
  static const corpPerRegion = 10;

  static double _g(Random r) => sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

  // 学校名の部品（架空。2文字の地名ふう）
  static const _a = ['青', '白', '桜', '緑', '東', '西', '南', '北', '朝', '光', '若', '清', '明', '星', '高', '大', '新', '古', '松', '竹', '梅', '鶴', '亀', '龍', '鳳', '翠', '紫', '金', '銀', '玉', '日', '月', '春', '秋', '泉', '雲'];
  static const _b = ['葉', '峰', '丘', '陵', '海', '風', '山', '川', '谷', '原', '野', '台', '浜', '崎', '島', '田', '沢', '森', '里', '岡', '陽', '城'];
  static const _hsPublic = ['', '', '', '東', '西', '南', '北', '中央', '商業', '工業', '農業', '第一', '第二', '総合', '北陵', '南陵', '西陵', '東陵', '清陵', '桜丘', '緑丘', '水産', '高原', '台', '丘'];
  static const _hsPrivate = ['学園', '学院', '実業', '大附属', '国際', '義塾', '学館', '工大附属', '商科大附属', '第一学院', '中央学院', '育英', '明徳', '創志'];
  static const _univSuffix = ['大', '大', '学院大', '工業大', '経済大', '国際大', '体育大', '産業大', '商科大', '文化大'];
  /// 1文字の地名・区の名前などは都道府県の名前を前に付ける（「北高」ではなく「大阪北高」）
  static String _town(int pf, String t) {
    if (t.length > 1 && !const ['中央', '北区', '南区'].contains(t)) return t;
    final p = NameData2.prefectures[pf].$1;
    return '${p == '北海道' ? '北海' : p.substring(0, p.length - 1)}$t';
  }
  static const _corp = ['重工', '製鉄', 'ガス', '電機', '自動車', '鉄道', '通運', '生命', '化学', '製紙', '電力', '銀行', '建設', '薬品', '食品', '物産'];

  /// 都道府県ごとの高校の数（人口の割合＋どの県にも一定数。合計 3,400）
  static List<int> hsPerPref() {
    final w = [for (final p in NameData2.prefectures) p.$2];
    final sum = w.fold<int>(0, (a, b) => a + b);
    final raw = [for (final x in w) hsCount * (0.35 / w.length + 0.65 * x / sum)];
    final out = [for (final x in raw) x.floor()];
    // 端数の大きい順に1校ずつ足して 3,400 にそろえる
    final order = List.generate(w.length, (i) => i)..sort((a, b) => (raw[b] - out[b]).compareTo(raw[a] - out[a]));
    var left = hsCount - out.fold<int>(0, (a, b) => a + b);
    for (var i = 0; left > 0; i = (i + 1) % order.length, left--) {
      out[order[i]]++;
    }
    return out;
  }

  /// アマチュア球界を作る
  static AmWorld generate(int year, Random r) {
    final used = <String>{};
    String stem() => '${_a[r.nextInt(_a.length)]}${_b[r.nextInt(_b.length)]}';
    String unique(String Function() f) {
      for (var i = 0; i < 200; i++) {
        final s = f();
        if (used.add(s)) return s;
      }
      // 万一ぶつかり続けたら番号を付ける
      var k = 2;
      final base = f();
      while (!used.add('$base$k')) {
        k++;
      }
      return '$base$k';
    }

    final teams = <AmTeam>[];
    // 高校：私学の強豪がわずかにいる山型
    final per = hsPerPref();
    var n = 0;
    for (var pf = 0; pf < per.length; pf++) {
      final towns = TownData.towns[pf];
      for (var i = 0; i < per[pf]; i++) {
        final private = r.nextDouble() < 0.3;
        final power = r.nextDouble() < (private ? 0.12 : 0.02);
        final s = (power ? 70 + _g(r) * 8 : 32 + _g(r) * 12).round().clamp(5, 95);
        // 町の名前は、まだ使っていない町から先に使う（どの町にも1校はある）
        final town = _town(pf, towns[i < towns.length ? i : r.nextInt(towns.length)]);
        final name = unique(() => '$town${private ? _hsPrivate[r.nextInt(_hsPrivate.length)] : _hsPublic[r.nextInt(_hsPublic.length)]}高');
        teams.add(AmTeam(id: 'H${n++}', name: name, kind: '高校', pref: pf, region: amPrefRegion[pf], strength: s, prestige: s));
      }
    }
    // 大学：9地区×6校。所在地は地区の中で人口の多い県ほど多い
    for (var rg = 0; rg < amRegions.length; rg++) {
      final prefs = [for (var i = 0; i < amPrefRegion.length; i++) if (amPrefRegion[i] == rg) i];
      for (var i = 0; i < univPerRegion; i++) {
        final pf = _pickPref(prefs, r);
        final s = (48 + _g(r) * 12).round().clamp(15, 92);
        final tw = TownData.towns[pf];
        final name = unique(() => '${_town(pf, tw[r.nextInt(min(tw.length, 25))])}${_univSuffix[r.nextInt(_univSuffix.length)]}');
        teams.add(AmTeam(id: 'U${rg}_$i', name: name, kind: '大学', pref: pf, region: rg, strength: s, prestige: s));
      }
      // 社会人（企業チーム）
      for (var i = 0; i < corpPerRegion; i++) {
        final pf = _pickPref(prefs, r);
        final s = (52 + _g(r) * 10).round().clamp(20, 92);
        final name = unique(() => '${stem()}${_corp[r.nextInt(_corp.length)]}');
        teams.add(AmTeam(id: 'C${rg}_$i', name: name, kind: '社会人', pref: pf, region: rg, strength: s, prestige: s));
      }
    }
    final w = AmWorld(year: year, teams: teams, gen: genVersion);
    AmateurSeason.setupYear(w, r);
    return w;
  }

  static int _pickPref(List<int> prefs, Random r) {
    final w = [for (final p in prefs) NameData2.prefectures[p].$2];
    var x = r.nextInt(w.fold<int>(0, (a, b) => a + b));
    for (var i = 0; i < prefs.length; i++) {
      x -= w[i];
      if (x < 0) return prefs[i];
    }
    return prefs.last;
  }

  /// 卒業の学年（高校3年・大学4年）。社会人はなし
  static int finalGrade(String kind) => kind == '高校' ? 3 : (kind == '大学' ? 4 : 99);

  /// 4月1日：年度の切り替え。今年の成績を記録に残し、強さ・名門度・パイプを動かし、進級・卒業・進路を決める
  ///  戻り値：進路のメモ（デバッグ・ニュース用）
  static List<String> newYear(AmWorld w, int year, Random r) {
    final notes = <String>[];
    for (final t in w.teams) {
      if (t.w + t.l + t.d > 0) t.history.add('${w.year} ${t.w}勝${t.l}敗${t.d > 0 ? '${t.d}分' : ''}');
      if (t.history.length > 30) t.history.removeAt(0);
      t.w = t.l = t.d = 0;
      // 強さは名門度へ戻りながら揺れる。名門度は強さに少しずつついていく
      t.strength = (t.strength * 0.55 + t.prestige * 0.45 + _g(r) * 7).round().clamp(5, 95);
      t.prestige = (t.prestige * 0.9 + t.strength * 0.1).round().clamp(5, 95);
      t.pipe.updateAll((_, v) => v * 0.8);
      t.pipe.removeWhere((_, v) => v < 0.05);
      t.hid = -1;
      t.gen = 0;
    }
    final univs = w.ofKind('大学').toList(), corps = w.ofKind('社会人').toList();
    AmTeam pickNear(List<AmTeam> list, int region) {
      // 同じ地区を優先し、強いチームほど選ばれやすい
      final near = list.where((t) => t.region == region).toList();
      final pool = r.nextDouble() < 0.7 && near.isNotEmpty ? near : list;
      final tot = pool.fold<double>(0, (a, t) => a + t.strength);
      var x = r.nextDouble() * tot;
      for (final t in pool) {
        x -= t.strength;
        if (x < 0) return t;
      }
      return pool.last;
    }

    final gone = <AmPlayer>[];
    for (final ap in w.players) {
      final t = w.team(ap.teamId);
      if (t == null) {
        gone.add(ap);
        continue;
      }
      final p = ap.player;
      p.age++;
      final grow = p.age <= 22 ? 3.0 + (p.talent - 50) * 0.07 : (p.age <= 26 ? 1.5 + (p.talent - 50) * 0.04 : (p.age <= 30 ? 0.0 : -1.0));
      OtherLeagueEngine.shiftAbility(p, grow + _g(r) * 1.5);
      if (ap.grade >= finalGrade(t.kind)) {
        // 卒業（指名された選手は、指名のときにもう抜けている）
        final x = r.nextDouble();
        if (t.kind == '高校' && x < 0.45) {
          final u = pickNear(univs, t.region);
          ap.record.add('${w.year + 1} ${u.name}に進学');
          p.amPath.add('大学　${u.name}');
          ap.teamId = u.id;
          ap.grade = 1;
        } else if (x < (t.kind == '高校' ? 0.75 : 0.55)) {
          final c = pickNear(corps, t.region);
          ap.record.add('${w.year + 1} ${c.name}に入社');
          p.amPath.add('社会人　${c.name}');
          ap.teamId = c.id;
          ap.grade = 1;
        } else {
          gone.add(ap);
          notes.add('${p.registeredName}（${t.name}）が野球をやめた');
        }
      } else {
        ap.grade++;
        // 社会人は年齢が上がるとやめていく
        if (t.kind == '社会人' && p.age >= 28 && r.nextDouble() < 0.4) gone.add(ap);
      }
    }
    w.players.removeWhere(gone.contains);
    w.year = year;
    w.visits = {};
    w.flags = {};
    AmateurSeason.setupYear(w, r); // 今年の大会・リーグ（去年のものは消える）
    return notes;
  }
}
