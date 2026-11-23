part of 'app_state.dart';

/// 背番号：特別な初期設定日（isOpeningNumberDay）を除き、入団時期・オフ期間を問わず変更・決定は一律で「開幕前日」に反映する
///  開幕前日に予約した番号へまとめて変え、球団の記録（背番号の変遷）に残す。記録は2026年2月から（それより前の番号は入れない）
extension NumberOps on AppState {
  /// 背番号の記録を始めた日
  static const historyFrom = '2026-02-01';

  /// オフシーズン即時変更は廃止（入団時期・オフ期間を問わず一律で開幕前日に反映する）
  bool get isOffseasonNumberFree => false;

  /// 開幕前日より前（ドラフト会議日10/31〜3月の開幕前日）のオフシーズンか
  ///  シーズン中（3月の開幕〜ドラフト会議前日10/30）は false
  bool isBeforeOpeningDay([DateTime? at]) {
    final d = DateUtils.dateOnly(at ?? currentDate);
    if (d.month >= 11 || (d.month == 10 && d.day >= 31)) return true;
    final (firstReg, _) = _regularRange();
    if (firstReg == null) return d.month <= 3;
    final cut = DateUtils.dateOnly(firstReg).subtract(const Duration(days: 1));
    if (firstReg.year >= d.year) return d.isBefore(cut);
    return d.month <= 3;
  }

  /// 今日は特別な初期設定日（isOpeningNumberDay）のみ即座に変えられる。通常は入団時期・オフ期間を問わず一律で開幕前日反映
  bool numberFreeNow(Player p) => isOpeningNumberDay;

  /// 今日は、全員の背番号をすぐ変えられる特別な日か（初期の背番号の扱い）
  bool get isOpeningNumberDay => openingNumberDay.isNotEmpty && openingNumberDay == ChronicleOps.ymd(currentDate);

  /// すぐ変える（初期設定日 isOpeningNumberDay 専用）
  void _changeNow(Team t, Player p, int n) {
    if (n == p.uniformNumber) return;
    if (p.numberPending) {
      p.uniformNumber = n;
      p.numberPending = false;
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

  /// 開幕前日に適用される背番号：予約があればそれ、なければ今の番号
  int numberNextSeason(Player p) => p.nextNumber ?? p.uniformNumber;

  /// 背番号の決まり（支配下は 00・0〜99、育成は 100〜999）。守っていなければその文
  String? numberRule(Player p, int n) {
    if (p.ikusei) return n >= 100 ? null : '育成選手の背番号は100〜999です';
    return n < 100 ? null : '支配下の選手の背番号は00・0〜99です';
  }

  /// 1人の背番号を変える。特別な初期設定日以外は一律で開幕前日からの予約。戻り値はエラーの文（null で成功）
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
    if (dup != null) return '背番号${uniformLabel(n)}は${dup.registeredName}が予約・使用しています';
    p.nextNumber = n == p.uniformNumber ? null : n;
    return null;
  }

  /// 一括の変更（選手 id → 開幕前日からの背番号）。すべて決まりどおりで重ならないときだけ予約する。戻り値はエラーの文
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
    if (isOpeningNumberDay) {
      for (final p in t.players) {
        _changeNow(t, p, finalNum[p]!);
        p.nextNumber = null;
      }
      updateAndSave();
      return null;
    }
    for (final p in t.players) {
      final n = finalNum[p]!;
      p.nextNumber = n == p.uniformNumber ? null : n;
    }
    updateAndSave();
    return null;
  }

  /// 開幕前日：予約した背番号に変え、仮背番号だった入団・移籍・昇格選手の背番号を一斉に決定・変更する（全球団）
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
      // Pass 1: 予約された背番号の変更・決定を反映（空き番号の移動先が被らないよう先に確定させる）
      for (final p in targets) {
        final next = p.nextNumber;
        if (next == null) continue;
        if ((count[next] ?? 0) > 1 || numberRule(p, next) != null) {
          if (t.id == myTeamId) mine.add('${p.registeredName}の背番号${uniformLabel(next)}は、ほかの選手と重なるため変えませんでした');
          p.nextNumber = null;
        } else {
          final hadFixed = !p.numberPending && p.uniformNumber >= -1;
          if (hadFixed) {
            _numberChron(t, p, p.uniformNumber, next, d);
            if (t.id == myTeamId) mine.add('${p.registeredName} ${uniformLabel(p.uniformNumber)}→${uniformLabel(next)}');
          }
          p.uniformNumber = next;
          p.nextNumber = null;
          if (!hadFixed) {
            p.numberPending = false;
            _chron(d, t.id, 'number', '${_pos(p)} ${p.registeredName}の背番号が${p.uniformText}に決定。', pid: p.id, pt: '背番号が${p.uniformText}に決定。');
            if (t.id == myTeamId) mine.add('${p.registeredName} 背番号${p.uniformText}に決定');
          }
        }
      }
      // Pass 2: 予約が無く仮番号のままの選手を正式決定する（万一確定済み選手と重複していれば空き番号へ）
      for (final p in targets) {
        if (p.numberPending) {
          final dup = t.players.any((x) => !identical(x, p) && !x.numberPending && x.uniformNumber == p.uniformNumber);
          if (dup || p.uniformNumber <= -2 || (p.ikusei != (p.uniformNumber >= 100))) {
            p.uniformNumber = RosterEngine.freeNumber(t, ikusei: p.ikusei);
          }
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

  /// 一律で開幕前日反映となったため、入団直後の即時変更期限は設定しない（既存テスト等との互換用）
  void markNumberFree(Player p, DateTime d) {
    p.numberFreeUntil = '';
  }

  void _numberChron(Team t, Player p, int from, int to, DateTime d) {
    _chron(d, t.id, 'number', '${_pos(p)} ${p.registeredName}の背番号を${uniformLabel(from)}から${uniformLabel(to)}に変更。', pid: p.id, pt: '背番号を${uniformLabel(from)}から${uniformLabel(to)}に変更。');
  }

  /// 背番号の変遷（2026年2月から）：背番号 → (日付, 選手名または引き継ぎ, できごと) の古い順
  Future<Map<int, List<(String, String, String)>>> numberHistory(Team t) async {
    int? numOf(String s) => s == '00' ? -1 : int.tryParse(s);
    DateTime? parseYmd(String s) => DateTime.tryParse(s);
    final re = RegExp(r'^(\S+) (.+?)\(\d+\)');

    final raw = <(String d, int kindOrder, int seq, String k, String text, int? leaveNum)>[];
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
        raw.add((d, kindOrder, seq++, k, '${e['t']}', (e['num'] as num?)?.toInt()));
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
      final (d, _, s, k, text, leaveNum) = e;
      if (k == 'join' || k == 'reg') {
        final m = RegExp(r'背番号は(00|\d+)').firstMatch(text);
        final n = m == null ? null : numOf(m.group(1)!);
        if (n == null) continue;
        final nm = re.firstMatch(text)?.group(2) ?? '';
        final how = k == 'reg' ? '支配下登録' : (RegExp(r'\)が(.+?)。').firstMatch(text)?.group(1) ?? '入団');
        holderNumber[nm] = n;
        addEv(n, d, nm, how, false, s);
      } else if (k == 'number') {
        final m = RegExp(r'^\S+ (.+)の背番号を(00|\d+)から(00|\d+)に変更').firstMatch(text);
        if (m != null) {
          final nm = m.group(1)!;
          final from = numOf(m.group(2)!), to = numOf(m.group(3)!);
          if (from != null) addEv(from, d, nm, '${m.group(3)}へ変更', true, s);
          if (to != null) {
            holderNumber[nm] = to;
            addEv(to, d, nm, '${m.group(2)}から変更', false, s);
          }
        } else {
          final m2 = RegExp(r'^\S+ (.+)の背番号が(00|\d+)に決定').firstMatch(text);
          final n = m2 == null ? null : numOf(m2.group(2)!);
          if (n != null) {
            final nm = m2!.group(1)!;
            holderNumber[nm] = n;
            addEv(n, d, nm, '背番号決定', false, s);
          }
        }
      } else if (k == 'leave') {
        final nm = re.firstMatch(text)?.group(2) ?? '';
        final what = text.contains('移籍') ? '移籍' : (text.contains('引退') ? '引退' : '退団');
        final tracked = holderNumber.remove(nm);
        final n = leaveNum ?? tracked;
        if (n != null) addEv(n, d, nm, what, true, s);
      }
    }

    final out = <int, List<(String, String, String)>>{};
    for (final entry in byNum.entries) {
      final events = entry.value;
      events.sort((a, b) {
        final dc = a.$1.compareTo(b.$1);
        if (dc != 0) return dc;
        // 同日内は必ず「手放す（変更元・退団・移籍）」を先、「受け取る（変更先・決定・入団）」を後に並べる
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
          if (cur.$3 == '移籍' || cur.$3 == '引退') {
            merged.add((cur.$1, cur.$2, '${cur.$3}で空き番号に'));
          } else {
            merged.add((cur.$1, cur.$2, '${cur.$3}（空き番号に）'));
          }
        } else {
          merged.add((cur.$1, cur.$2, cur.$3));
        }
      }
      out[entry.key] = merged;
    }
    return out;
  }
}
