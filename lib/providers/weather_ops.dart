part of 'app_state.dart';

/// 改修1：試合数の選択・天候・雨天中止・順延・ダブルヘッダー
extension WeatherOps on AppState {
  /// その試合の天候（ホーム球団の本拠地の球場と所在地から。同じセーブ・同じ日ならいつも同じ）
  GameWeather? weatherOf(Match m) {
    final h = teams.where((t) => t.id == m.homeTeamId).firstOrNull;
    if (h == null) return null;
    return GameWeather.of(Stadium.byId(h.homeStadium), h.homePrefecture, m.date, seed: weatherSeed);
  }

  /// 試合数を変える。今の日程で公式戦がまだ 1 試合も行われていなければ、日程をすぐ作り直す（行われていれば次のシーズンから）
  bool setSeasonGames(int g) {
    if (!ScheduleGenerator.seasonLengths.contains(g)) return false;
    seasonGames = g;
    _applySeasonGames();
    final started = matches.any((m) => m.done && m.matchType != 'OPEN');
    if (!started && !seasonFinished) {
      // オープン戦（結果も）はそのままにして、公式戦だけ作り直す
      final open = [for (final m in matches) if (m.matchType == 'OPEN') m];
      _generateSchedule(keepDate: true);
      if (open.isNotEmpty) {
        matches = [...open, for (final m in matches) if (m.matchType != 'OPEN') m];
        _buildFarmMatches();
      }
    }
    updateAndSave();
    return !started;
  }

  /// 試合数に合わせた補正：156 試合（移動日が少ない）は投手の回復を 1.08 倍にして、中5〜6日で回るようにする
  void _applySeasonGames() {
    ConditionEngine.pitcherScheduleMul = seasonGames >= 156 ? 1.08 : 1.0;
    DailyWeather.saveSeed = weatherSeed;
  }

  /// その日の朝の雨天中止の判定：屋外の球場で大雨なら中止。
  ///  公式戦は「空き日（両球団とも試合がない月曜、または日程の最終日より後〜10/2 の予備日）」へ順延し、
  ///  空き日がなければ、同じカードの日にダブルヘッダー（第1試合 13:00・第2試合 18:00）として入れる。オープン戦は中止のみ
  void _rainoutsOn(DateTime d) {
    final day = DateUtils.dateOnly(d);
    final todays = matches.where((m) => DateUtils.isSameDay(m.date, day) && !m.done && (m.matchType == 'OPEN' || m.matchType == 'LEAGUE' || m.matchType == 'INTERLEAGUE')).toList();
    if (todays.isEmpty) return;
    final mine = <String>[];
    var others = 0;
    for (final m in todays) {
      final w = weatherOf(m);
      if (w == null || !w.rainout) continue;
      final h = teams.firstWhere((t) => t.id == m.homeTeamId), a = teams.firstWhere((t) => t.id == m.awayTeamId);
      // 中止の日は休養：体力は全回復、連投の数え直し
      for (final t in [h, a]) {
        for (final p in t.players) {
          p.energy = p.maxEnergy;
          p.consecDays = 0;
        }
      }
      final label = '${day.month}/${day.day}';
      final stName = Stadium.byId(h.homeStadium).name;
      String text;
      if (m.matchType == 'OPEN') {
        m.cancelled = true;
        m.note = '雨天中止';
        text = '$label ${h.name}−${a.name}（$stName）は雨天中止';
      } else {
        // 元の日がダブルヘッダーだったら、相手の試合は普通の試合に戻す
        if (m.dh != 0) {
          for (final x in matches) {
            if (!identical(x, m) && DateUtils.isSameDay(x.date, day) && x.homeTeamId == m.homeTeamId && x.awayTeamId == m.awayTeamId) x.dh = 0;
          }
          m.dh = 0;
        }
        final (nd, partner) = _makeupDate(m, day);
        if (nd == null) {
          m.cancelled = true;
          m.note = '$label 雨天中止（振替日なし）';
          text = '$label ${h.name}−${a.name}は雨天中止。振替日がないため打ち切り';
        } else {
          m.date = nd;
          m.note = '$label 雨天中止の振替';
          if (partner != null) {
            m.dh = 1;
            partner.dh = 2;
            text = '$label ${h.name}−${a.name}（$stName）は雨天中止 → ${nd.month}/${nd.day} にダブルヘッダー（13:00・18:00）';
          } else {
            text = '$label ${h.name}−${a.name}（$stName）は雨天中止 → ${nd.month}/${nd.day}（${_wd(nd)}）に振替';
          }
        }
      }
      if (m.homeTeamId == myTeamId || m.awayTeamId == myTeamId) {
        mine.add(text);
      } else {
        others++;
      }
      rainoutCount++;
    }
    if (mine.isEmpty && others == 0) return;
    _matchesReplaceAll = true; // 日付が変わった試合を保存し直す
    _addNews([...mine, if (others > 0) '${day.month}/${day.day} ほかの球場で$others試合が雨天中止（振替）']);
  }

  static String _wd(DateTime d) => const ['月', '火', '水', '木', '金', '土', '日'][d.weekday - 1];

  /// 振替の日：(日付, ダブルヘッダーの相手の試合)。空き日なら相手は null。どこにも入らなければ (null, null)
  (DateTime?, Match?) _makeupDate(Match m, DateTime from) {
    final ids = {m.homeTeamId, m.awayTeamId};
    final official = matches.where((x) => x.matchType == 'LEAGUE' || x.matchType == 'INTERLEAGUE').map((x) => x.date);
    final lastRegular = official.isEmpty ? from : official.reduce((x, y) => x.isAfter(y) ? x : y);
    final limit = DateTime(from.year, 10, 2);
    bool busy(DateTime day) => matches.any((x) => !identical(x, m) && !x.cancelled && DateUtils.isSameDay(x.date, day) && (x.matchType == 'ALLSTAR' || ids.contains(x.homeTeamId) || ids.contains(x.awayTeamId)));
    // ① 空き日：月曜（ふだんの休み）か、日程の最終日より後の予備日
    for (var day = from.add(const Duration(days: 1)); !day.isAfter(limit); day = day.add(const Duration(days: 1))) {
      if (busy(day)) continue;
      if (day.weekday == DateTime.monday || day.isAfter(lastRegular)) return (day, null);
    }
    // ② ダブルヘッダー：同じカードがある日（まだダブルヘッダーでない日）
    final same = matches
        .where((x) => !identical(x, m) && !x.done && x.dh == 0 && x.date.isAfter(from) && !x.date.isAfter(limit) && ids.contains(x.homeTeamId) && ids.contains(x.awayTeamId))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final x in same) {
      final dayGames = matches.where((y) => !y.cancelled && DateUtils.isSameDay(y.date, x.date) && (ids.contains(y.homeTeamId) || ids.contains(y.awayTeamId))).length;
      if (dayGames == 1) return (x.date, x);
    }
    return (null, null);
  }

  /// 日程の一覧に出す天気（その日にホームで試合がある球場の天気）
  String weatherIcon(Match m) {
    final w = weatherOf(m);
    if (w == null) return '';
    if (w.roof == RoofType.dome) return '';
    return w.outside.icon;
  }
}
