part of 'app_state.dart';

/// 背番号：ふだんの変更は「来季（開幕前日）から」の予約。入団・移籍した直後だけは、すぐに変えられる
///  開幕前日に予約した番号へまとめて変え、球団の記録（背番号の変遷）に残す。記録は2026年2月から（それより前の番号は入れない）
extension NumberOps on AppState {
  /// 背番号の記録を始めた日
  static const historyFrom = '2026-02-01';

  /// オフシーズン（11/1〜1/31）は背番号をすぐ変えられ、変更は経歴に残さない
  bool get isOffseasonNumberFree => currentDate.month >= 11 || currentDate.month == 1;

  /// 開幕前日より前か（オフ期間の入団・再契約・支配下登録等は開幕前日に背番号を確定する）
  bool isBeforeOpeningDay([DateTime? at]) {
    final d = DateUtils.dateOnly(at ?? currentDate);
    if (seasonFinished || seasonOver) return true;
    final (firstReg, _) = _regularRange();
    if (firstReg == null) return d.month >= 10 || d.month <= 3;
    return d.isBefore(DateUtils.dateOnly(firstReg).subtract(const Duration(days: 1)));
  }

  /// 入団・移籍した直後、またはオフ期間（11/1〜1/31）で背番号をすぐ変えられるか（特別に決めた日は全員）
  bool numberFreeNow(Player p) =>
      isOpeningNumberDay ||
      isOffseasonNumberFree ||
      p.numberPending ||
      (p.numberFreeUntil.isNotEmpty && p.numberFreeUntil.compareTo(ChronicleOps.ymd(currentDate)) >= 0);

  /// 今日は、全員の背番号をすぐ変えられる特別な日か（初期の背番号の扱い）
  bool get isOpeningNumberDay => openingNumberDay.isNotEmpty && openingNumberDay == ChronicleOps.ymd(currentDate);

  /// すぐ変える。初期の背番号・オフ期間（11/1〜1/31）・入団直後の変更は経歴に残さず、入団・支配下登録の記録の番号を書き換える
  void _changeNow(Team t, Player p, int n) {
    if (n == p.uniformNumber) return;
    if (p.numberPending) {
      p.uniformNumber = n;
      return;
    }
    if (numberFreeNow(p)) {
      final from = 'は${p.uniformText}。', to = 'は${uniformLabel(n)}。';
      final cutoff = isOpeningNumberDay ? historyFrom : ChronicleOps.ymd(currentDate.subtract(const Duration(days: 120)));
      for (final list in chronYears.values) {
        for (final c in list.reversed) {
          if (c['pid'] != p.id || c['team'] != t.id || !(c['k'] == 'join' || c['k'] == 'reg')) continue;
          final d = '${c['d']}';
          if (d.compareTo(historyFrom) < 0 || d.compareTo(cutoff) < 0) continue;
          c['t'] = '${c['t']}'.replaceFirst('背番号$from', '背番号$to');
          if (c['pt'] is String) c['pt'] = (c['pt'] as String).replaceFirst('背番号${p.uniformText}。', '背番号${uniformLabel(n)}。');
          if (!isOpeningNumberDay) break;
        }
      }
    } else {
      _numberChron(t, p, p.uniformNumber, n, currentDate);
    }
    p.uniformNumber = n;
  }

  /// 来季（次の2月1日）の背番号：予約があればそれ、なければ今の番号
  int numberNextSeason(Player p) => p.nextNumber ?? p.uniformNumber;

  /// 背番号の決まり（支配下は 00・0〜99、育成は 100〜999）。守っていなければその文
  String? numberRule(Player p, int n) {
    if (p.ikusei) return n >= 100 ? null : '育成選手の背番号は100〜999です';
    return n < 100 ? null : '支配下の選手の背番号は00・0〜99です';
  }

  /// 1人の背番号を変える。入団・移籍の直後ならすぐ、それ以外は2月1日からの予約。戻り値はエラーの文（null で成功）
  String? setNumber(Team t, Player p, int n) {
    final rule = numberRule(p, n);
    if (rule != null) return rule;
    if (numberFreeNow(p)) {
      final dup = t.players.where((x) => !identical(x, p) && x.uniformNumber == n).firstOrNull;
      if (dup != null) return '背番号${uniformLabel(n)}は${dup.registeredName}がつけています';
      _changeNow(t, p, n);
      p.nextNumber = null;
      return null;
    }
    final dup = t.players.where((x) => !identical(x, p) && numberNextSeason(x) == n).firstOrNull;
    if (dup != null) return '来季の背番号${uniformLabel(n)}は${dup.registeredName}がつけます';
    p.nextNumber = n == p.uniformNumber ? null : n;
    return null;
  }

  /// 一括の変更（選手 id → 来季の背番号）。すべて決まりどおりで重ならないときだけ変える。戻り値はエラーの文
  ///  入団・移籍の直後の選手は、すぐ変える
  String? setNumbersBulk(Team t, Map<String, int> next) {
    final finalNum = <Player, int>{for (final p in t.players) p: next[p.id] ?? numberNextSeason(p)};
    for (final e in finalNum.entries) {
      final r = numberRule(e.key, e.value);
      if (r != null) return '${e.key.registeredName}：$r';
    }
    final seen = <int, Player>{};
    for (final e in finalNum.entries) {
      final o = seen[e.value];
      if (o != null) return '背番号${uniformLabel(e.value)}が${o.registeredName}と${e.key.registeredName}で重なっています';
      seen[e.value] = e.key;
    }
    if (isOpeningNumberDay || isOffseasonNumberFree) {
      for (final p in t.players) {
        _changeNow(t, p, finalNum[p]!);
        p.nextNumber = null;
      }
      updateAndSave();
      return null;
    }
    // すぐ変えられる選手は、今の番号で重ならないときだけすぐ（重なるときは来季の予約に）
    for (final p in t.players) {
      final n = finalNum[p]!;
      if (numberFreeNow(p) && n != p.uniformNumber && !t.players.any((x) => !identical(x, p) && x.uniformNumber == n)) {
        _changeNow(t, p, n);
        p.nextNumber = null;
      } else {
        p.nextNumber = n == p.uniformNumber ? null : n;
      }
    }
    updateAndSave();
    return null;
  }

  /// 開幕前日：予約した背番号に変え、未確定の入団・昇格選手の背番号を確定する（全球団）
  void applyNextNumbers(DateTime d) {
    final mine = <String>[];
    for (final t in leagueTeams) {
      final targets = t.players.where((p) => p.nextNumber != null || p.numberPending).toList();
      if (targets.isEmpty) continue;
      final finalNum = {for (final p in t.players) p: p.nextNumber ?? p.uniformNumber};
      final count = <int, int>{};
      for (final n in finalNum.values) {
        count[n] = (count[n] ?? 0) + 1;
      }
      for (final p in targets) {
        final next = p.nextNumber;
        if (next != null) {
          if ((count[next] ?? 0) > 1 || numberRule(p, next) != null) {
            if (t.id == myTeamId) mine.add('${p.registeredName}の背番号${uniformLabel(next)}は、ほかの選手と重なるため変えませんでした');
            p.nextNumber = null;
          } else {
            if (!p.numberPending) {
              _numberChron(t, p, p.uniformNumber, next, d);
              if (t.id == myTeamId) mine.add('${p.registeredName} ${uniformLabel(p.uniformNumber)}→${uniformLabel(next)}');
            }
            p.uniformNumber = next;
            p.nextNumber = null;
          }
        }
        if (p.numberPending) {
          p.numberPending = false;
          _chron(d, t.id, 'number', '${_pos(p)} ${p.registeredName}の背番号が${p.uniformText}に決定。', pid: p.id, pt: '背番号が${p.uniformText}に決定。');
          if (t.id == myTeamId) mine.add('${p.registeredName} 背番号${p.uniformText}に決定');
        }
      }
    }
    if (mine.isNotEmpty) {
      final hasChange = mine.any((s) => s.contains('→'));
      _addNews(['${hasChange ? '背番号の変更' : '背番号の決定'}（開幕前日）：${mine.join('、')}']);
    }
  }

  /// 入団・移籍した選手（自球団）：しばらくは背番号をすぐ変えられる
  void markNumberFree(Player p, DateTime d) {
    p.numberFreeUntil = ChronicleOps.ymd(d.add(const Duration(days: 30)));
  }

  void _numberChron(Team t, Player p, int from, int to, DateTime d) {
    _chron(d, t.id, 'number', '${_pos(p)} ${p.registeredName}の背番号を${uniformLabel(from)}から${uniformLabel(to)}に変更。', pid: p.id, pt: '背番号を${uniformLabel(from)}から${uniformLabel(to)}に変更。');
  }

  /// 背番号の変遷（2026年2月から）：背番号 → (日付, 選手名または引き継ぎ, できごと) の古い順
  Future<Map<int, List<(String, String, String)>>> numberHistory(Team t) async {
    int? num(String s) => s == '00' ? -1 : int.tryParse(s);
    DateTime? parseYmd(String s) => DateTime.tryParse(s);
    final re = RegExp(r'^(\S+) (.+?)\(\d+\)');

    final raw = <(String d, int kindOrder, int seq, String k, String text)>[];
    var seq = 0;
    for (var y = 2026; y <= startYear; y++) {
      for (final e in await chronicleOf(y)) {
        final d = '${e['d']}';
        if (e['team'] != t.id || d.compareTo(historyFrom) < 0) continue;
        final k = '${e['k'] ?? ''}';
        if (k != 'leave' && k != 'number' && k != 'join' && k != 'reg') continue;
        final kindOrder = switch (k) {
          'leave' => 0,
          'number' => 1,
          _ => 2,
        };
        raw.add((d, kindOrder, seq++, k, '${e['t']}'));
      }
    }
    raw.sort((a, b) {
      final dc = a.$1.compareTo(b.$1);
      if (dc != 0) return dc;
      final kc = a.$2.compareTo(b.$2);
      if (kc != 0) return kc;
      return a.$3.compareTo(b.$3);
    });

    final holderNumber = <String, int>{};
    final byNum = <int, List<(String d, String name, String what, bool vacate, int seq)>>{};
    void addEv(int n, String d, String name, String what, bool vacate, int s) =>
        byNum.putIfAbsent(n, () => []).add((d, name, what, vacate, s));

    for (final e in raw) {
      final (d, _, s, k, text) = e;
      if (k == 'join' || k == 'reg') {
        final m = RegExp(r'背番号は(00|\d+)').firstMatch(text);
        final n = m == null ? null : num(m.group(1)!);
        if (n == null) continue;
        final nm = re.firstMatch(text)?.group(2) ?? '';
        final how = k == 'reg' ? '支配下登録' : (RegExp(r'\)が(.+?)。').firstMatch(text)?.group(1) ?? '入団');
        holderNumber[nm] = n;
        addEv(n, d, nm, how, false, s);
      } else if (k == 'number') {
        final m = RegExp(r'^\S+ (.+)の背番号を(00|\d+)から(00|\d+)に変更').firstMatch(text);
        if (m != null) {
          final nm = m.group(1)!;
          final from = num(m.group(2)!), to = num(m.group(3)!);
          if (from != null) addEv(from, d, nm, '${m.group(3)}へ変更', true, s);
          if (to != null) {
            holderNumber[nm] = to;
            addEv(to, d, nm, '${m.group(2)}から変更', false, s);
          }
        } else {
          final m2 = RegExp(r'^\S+ (.+)の背番号が(00|\d+)に決定').firstMatch(text);
          final n = m2 == null ? null : num(m2.group(2)!);
          if (n != null) {
            final nm = m2!.group(1)!;
            holderNumber[nm] = n;
            addEv(n, d, nm, '背番号決定', false, s);
          }
        }
      } else if (k == 'leave') {
        final nm = re.firstMatch(text)?.group(2) ?? '';
        final n = holderNumber.remove(nm);
        if (n != null) addEv(n, d, nm, '退団', true, s);
      }
    }

    final out = <int, List<(String, String, String)>>{};
    for (final entry in byNum.entries) {
      final events = entry.value;
      events.sort((a, b) {
        final dc = a.$1.compareTo(b.$1);
        if (dc != 0) return dc;
        // 同日内は必ず「手放す（変更元・退団）」を先、「受け取る（変更先・決定・入団）」を後に並べる
        final vc = (a.$4 ? 0 : 1).compareTo(b.$4 ? 0 : 1);
        if (vc != 0) return vc;
        return a.$5.compareTo(b.$5);
      });
      final merged = <(String, String, String)>[];
      for (var i = 0; i < events.length; i++) {
        final cur = events[i];
        if (cur.$4) {
          if (i + 1 < events.length && !events[i + 1].$4) {
            final next = events[i + 1];
            final dtOut = parseYmd(cur.$1), dtIn = parseYmd(next.$1);
            final gapDays = (dtOut != null && dtIn != null) ? dtIn.difference(dtOut).inDays : 999;
            if (gapDays <= 1) {
              final label = cur.$2 == next.$2 ? next.$2 : '${cur.$2} → ${next.$2}';
              final desc = cur.$2 == next.$2 ? '${next.$3}（${cur.$3}）' : '${next.$3}（${cur.$2}は${cur.$3}）';
              merged.add((next.$1, label, desc));
              i++;
              continue;
            }
          }
          merged.add((cur.$1, cur.$2, '${cur.$3}（空き番号に）'));
        } else {
          merged.add((cur.$1, cur.$2, cur.$3));
        }
      }
      out[entry.key] = merged;
    }
    return out;
  }
}
