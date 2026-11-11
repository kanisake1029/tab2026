import 'dart:math';
import '../models/player.dart';
import '../utils/name_pool.dart';
import 'farm_engine.dart';
import 'pre_career.dart';

/// ゲーム開始前の架空の歴史（タイトル・ベストナイン・ゴールデングラブ・MVP・沢村賞）。
///  年・リーグごとに、それらしい成績の架空の受賞者（引退した OB）を作る。
///  その年にいた選手（推定の成績）が受賞者の成績を上回れば、その選手が受賞したことにする（11本で本塁打王、のようなことは起きない）
class LeagueHistory {
  /// 年 → リーグ → 表彰名 → 受賞者の文字列（「山田 太郎（球団）38本」。今いる選手は id も持つ）
  final Map<int, Map<String, Map<String, HistEntry>>> years = {};

  static const titles = <(String, bool)>[
    ('首位打者', false), ('本塁打王', false), ('打点王', false), ('盗塁王', false), ('最多安打', false),
    ('最優秀防御率', true), ('最多勝利', true), ('最多奪三振', true), ('最多セーブ', true), ('最優秀中継ぎ', true),
  ];

  /// 架空の受賞者の成績（年・リーグごとに毎回同じ値）
  static num _fakeValue(String title, Random r) {
    double u(double a, double b) => a + r.nextDouble() * (b - a);
    return switch (title) {
      '首位打者' => u(0.312, 0.352),
      '本塁打王' => u(27, 46).round(),
      '打点王' => u(86, 118).round(),
      '盗塁王' => u(24, 46).round(),
      '最多安打' => u(158, 192).round(),
      '最優秀防御率' => u(1.65, 2.55),
      '最多勝利' => u(13, 18).round(),
      '最多奪三振' => u(158, 225).round(),
      '最多セーブ' => u(30, 44).round(),
      '最優秀中継ぎ' => u(34, 48).round(),
      _ => 0,
    };
  }

  /// 今いる選手の成績（規定に届かなければ null）。大きいほど良い（防御率は符号を反転）
  static num? _value(String title, PlayerStats s) => switch (title) {
        '首位打者' => s.plateAppearances >= 443 ? s.battingAverage : null,
        '本塁打王' => s.homeRuns,
        '打点王' => s.rbi,
        '盗塁王' => s.stolenBases,
        '最多安打' => s.hits,
        '最優秀防御率' => s.inningsPitched >= 143 * 3 ? -s.era : null,
        '最多勝利' => s.wins,
        '最多奪三振' => s.pitcherStrikeouts,
        '最多セーブ' => s.saves,
        '最優秀中継ぎ' => s.holdPoints,
        _ => null,
      };

  static String _shown(String title, num v) => switch (title) {
        '首位打者' => '打率${v.toDouble().abs().toStringAsFixed(3).replaceFirst('0.', '.')}',
        '最優秀防御率' => '防御率${v.toDouble().abs().toStringAsFixed(2)}',
        '本塁打王' => '$v本',
        '打点王' => '$v打点',
        '盗塁王' => '$v盗塁',
        '最多安打' => '$v安打',
        '最多勝利' => '$v勝',
        '最多奪三振' => '$v奪三振',
        '最多セーブ' => '$vセーブ',
        '最優秀中継ぎ' => '${v}HP',
        _ => '$v',
      };

  static String _fakeName(Random r) {
    final last = r.nextDouble() < 0.7 ? NamePool.commonLast[r.nextInt(NamePool.commonLast.length)] : NamePool.midLast[r.nextInt(NamePool.midLast.length)];
    final given = NamePool.olderGivenNames[r.nextInt(NamePool.olderGivenNames.length)];
    return '$last $given';
  }

  static const _b9Pos = ['捕', '一', '二', '三', '遊', '外'];
  static const _ggPos = ['投', '捕', '一', '二', '三', '遊', '外'];
  static const _posOfMain = {'捕手': '捕', '一塁手': '一', '二塁手': '二', '三塁手': '三', '遊撃手': '遊', '左翼手': '外', '中堅手': '外', '右翼手': '外'};

  /// all：選手 id → 推定の年度。players：id → 選手。leagueOf：球団 → リーグ。teamsOf：リーグ → 球団名（架空の受賞者の所属）
  ///  realHonors：実際の表彰（その年・その表彰があれば作らない）
  static LeagueHistory build(Map<String, List<PreYear>> all, Map<String, Player> players, String Function(String teamId) leagueOf,
      Map<String, List<String>> teamsOf, Set<String> realHonors) {
    final h = LeagueHistory();
    final groups = <String, List<(Player, PreYear)>>{};
    for (final e in all.entries) {
      final p = players[e.key];
      if (p == null) continue;
      for (final y in e.value) {
        groups.putIfAbsent('${y.year}|${leagueOf(y.teamId)}', () => []).add((p, y));
      }
    }
    final yearsAll = <int>{for (final k in groups.keys) int.parse(k.split('|').first)};
    final leagues = teamsOf.keys.toList()..sort();
    for (final year in yearsAll.toList()..sort()) {
      final sawa = <(double, Player, PreYear)>[];
      for (final lg in leagues) {
        final r = Random(year * 7919 + lg.hashCode);
        final cands = groups['$year|$lg'] ?? const <(Player, PreYear)>[];
        final teamNames = teamsOf[lg] ?? const ['−'];
        String fake() => '${_fakeName(r)}（${teamNames[r.nextInt(teamNames.length)]}）';
        final out = h.years.putIfAbsent(year, () => {}).putIfAbsent(lg, () => {});
        void award(String title, Player? p, PreYear? y, String text) {
          if (p != null && y != null) {
            y.honors.add('$year年 $title');
            out[title] = HistEntry('${p.registeredName}　$text', p.id);
          } else {
            out[title] = HistEntry(text);
          }
        }

        // タイトル：架空の受賞者の成績を上回れば、今いる選手が受賞
        for (final (title, _) in titles) {
          if (realHonors.contains('$year年 $title')) continue;
          final fv = _fakeValue(title, r);
          final fakeWho = fake();
          final cmpF = title == '最優秀防御率' ? -fv : fv;
          (Player, PreYear)? best;
          num? bv;
          for (final c in cands) {
            final v = _value(title, c.$2.stats);
            if (v == null) continue;
            if (bv == null || v > bv) {
              bv = v;
              best = c;
            }
          }
          if (best != null && bv! > cmpF) {
            award(title, best.$1, best.$2, _shown(title, bv));
          } else {
            award(title, null, null, "$fakeWho　${_shown(title, cmpF)}");
          }
        }

        // ベストナイン：守備位置ごと（外野は3人）。100試合以上の野手の OPS が、架空の受賞者を上回れば
        for (final pos in _b9Pos) {
          final slots = pos == '外' ? 3 : 1;
          final list = [
            for (final c in cands)
              if (!c.$1.isPitcher && _posOfMain[c.$1.mainPosition] == pos && c.$2.stats.games >= 100 && c.$2.stats.atBats >= 300) c,
          ]..sort((a, b) => b.$2.stats.ops.compareTo(a.$2.stats.ops));
          for (var i = 0; i < slots; i++) {
            final fOps = (pos == '捕' ? 0.68 : (pos == '二' || pos == '遊' ? 0.73 : 0.80)) + r.nextDouble() * 0.12;
            final key = 'ベストナイン（${pos == '外' ? '外野手${i + 1}' : '${pos == '捕' ? '捕' : '$pos塁'}手'.replaceAll('遊塁', '遊撃')}）';
            final c = i < list.length ? list[i] : null;
            if (c != null && c.$2.stats.ops > fOps) {
              c.$2.honors.add('$year年 ベストナイン');
              out[key] = HistEntry('${c.$1.registeredName}　OPS${c.$2.stats.ops.toStringAsFixed(3).replaceFirst('0.', '.')}', c.$1.id);
            } else {
              out[key] = HistEntry('${fake()}　OPS${fOps.toStringAsFixed(3).replaceFirst('0.', '.')}');
            }
          }
        }

        // ゴールデングラブ：その位置で多く出た選手の守備力（いまの能力）が、架空の受賞者を上回れば
        for (final pos in _ggPos) {
          final slots = pos == '外' ? 3 : 1;
          final list = <(Player, PreYear, int)>[
            for (final c in cands)
              if (pos == '投' ? (c.$1.isPitcher && c.$2.stats.inningsPitched >= 120 * 3) : (!c.$1.isPitcher && _posOfMain[c.$1.mainPosition] == pos && c.$2.stats.games >= 100))
                (c.$1, c.$2, pos == '投' ? c.$1.catchSkill : FarmEngine.fieldingAt(c.$1, pos == '外' ? (c.$1.mainPosition == '中堅手' ? '中' : (c.$1.mainPosition == '左翼手' ? '左' : '右')) : pos)),
          ]..sort((a, b) => b.$3.compareTo(a.$3));
          for (var i = 0; i < slots; i++) {
            final fv = 68 + r.nextInt(14);
            final key = 'ゴールデングラブ（${pos == '外' ? '外野手${i + 1}' : (pos == '投' ? '投手' : (pos == '捕' ? '捕手' : (pos == '遊' ? '遊撃手' : '$pos塁手')))}）';
            final c = i < list.length ? list[i] : null;
            if (c != null && c.$3 > fv) {
              c.$2.honors.add('$year年 ゴールデングラブ');
              out[key] = HistEntry(c.$1.registeredName, c.$1.id);
            } else {
              out[key] = HistEntry(fake());
            }
          }
        }

        // MVP：打者は OPS と試合数、投手は勝利と防御率。架空の受賞者の成績を上回れば
        {
          (double, Player, PreYear)? best;
          for (final c in cands) {
            final s = c.$2.stats;
            double v = 0;
            if (!c.$1.isPitcher && s.games >= 120) v = (s.ops - 0.80) * 400 + s.homeRuns * 1.2 + s.rbi * 0.3;
            if (c.$1.isPitcher && s.inningsPitched >= 150 * 3) v = s.wins * 6 + (3.2 - s.era) * 25 + s.pitcherStrikeouts * 0.15;
            if (best == null || v > best.$1) best = (v, c.$1, c.$2);
          }
          final fv = 115 + r.nextDouble() * 35;
          if (!realHonors.contains('$year年 MVP')) {
            if (best != null && best.$1 > fv) {
              award('MVP', best.$2, best.$3, best.$2.isPitcher ? '${best.$3.stats.wins}勝 防御率${best.$3.stats.era.toStringAsFixed(2)}' : 'OPS${best.$3.stats.ops.toStringAsFixed(3).replaceFirst('0.', '.')} ${best.$3.stats.homeRuns}本');
            } else {
              award('MVP', null, null, fake());
            }
          }
        }
        // 沢村賞の候補（両リーグから1人）
        for (final c in cands) {
          final s = c.$2.stats;
          if (!c.$1.isPitcher || s.inningsPitched < 170 * 3 || s.wins < 14 || s.era > 2.6) continue;
          sawa.add((s.wins * 8 + (3.0 - s.era) * 30 + s.pitcherStrikeouts * 0.1 + s.completeGames * 3, c.$1, c.$2));
        }
      }
      // 沢村賞：基準（15勝・防御率2.50以下・180回など）に近い今いる投手が、架空の受賞者より上なら
      if (!realHonors.contains('$year年 沢村賞')) {
        final r = Random(year * 31 + 7);
        sawa.sort((a, b) => b.$1.compareTo(a.$1));
        final fv = 130 + r.nextDouble() * 40;
        final lg = leagues.isEmpty ? '' : leagues[r.nextInt(leagues.length)];
        final out = h.years.putIfAbsent(year, () => {}).putIfAbsent('両リーグ', () => {});
        if (sawa.isNotEmpty && sawa.first.$1 > fv) {
          final b = sawa.first;
          b.$3.honors.add('$year年 沢村賞');
          out['沢村賞'] = HistEntry('${b.$2.registeredName}　${b.$3.stats.wins}勝 防御率${b.$3.stats.era.toStringAsFixed(2)}', b.$2.id);
        } else {
          final names = teamsOf[lg] ?? const ['−'];
          out['沢村賞'] = HistEntry('${_fakeName(r)}（${names[r.nextInt(names.length)]}）');
        }
      }
    }
    return h;
  }
}

class HistEntry {
  final String text;
  final String? playerId; // 今いる選手が受賞した年
  const HistEntry(this.text, [this.playerId]);
}
