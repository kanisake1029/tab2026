import 'dart:math';
import 'match_simulator.dart' show PitchEvent;

/// 実況の1行。kind で見た目を変える
///  inning：回の見出し / pa：打者紹介 / situation：場面の説明 / pitch：1球 / result：打席の結果 / big：本塁打・逆転など
///  score：得点と現在のスコア / state：アウト・走者 / note：交代・盗塁など
class LiveLine {
  final String text;
  final String kind;
  final bool hit;   // 結果が安打・出塁（色分け用）
  const LiveLine(this.text, this.kind, {this.hit = false});
}

/// 一球速報の実況文を作る。試合の記録（1球ごとの場面つき PitchEvent）から、状況に応じた言い回しにする
class Commentator {
  final Random r;
  int _foulStreak = 0;
  int _lastPa = -1;
  Commentator([int seed = 0]) : r = Random(seed);

  String _p(List<String> xs) => xs[r.nextInt(xs.length)];

  static const _fielder = {'P': '投手', 'C': '捕手', '1B': 'ファースト', '2B': 'セカンド', '3B': 'サード', 'SS': 'ショート', 'LF': 'レフト', 'CF': 'センター', 'RF': 'ライト'};

  static String bases(List<bool> b) {
    final on = [if (b[0]) '一', if (b[1]) '二', if (b[2]) '三'];
    if (on.isEmpty) return '走者なし';
    if (on.length == 3) return '満塁';
    return '${on.join('、')}塁';
  }

  static String outs(int o) => o == 0 ? '無死' : '$o死';

  /// 場面の説明（例：一打逆転のチャンス）。攻撃側から見た点差と走者で決める
  static String? chance(PitchEvent e) {
    final b = e.basesBefore;
    final risp = (b[1] ? 1 : 0) + (b[2] ? 1 : 0);
    final on = b.where((x) => x).length;
    final d = e.defBefore - e.offBefore; // 攻撃側が何点負けているか
    final late = e.inning >= 7;
    if (on == 0) {
      if (d == 1 && late) return '一発が出れば同点';
      return null;
    }
    if (d < 0) return risp > 0 ? '追加点のチャンス' : null;
    if (d == 0) return risp > 0 ? '勝ち越しのチャンス' : (late ? '勝ち越しの走者が出塁' : null);
    if (d == 1 && risp >= 2) return '一打逆転のチャンス';
    if (d == 1 && risp >= 1) return '同点のチャンス';
    if (d >= 2 && on + 1 > d) return '一発出れば逆転の場面';
    if (d >= 2 && on + 1 == d) return '一発出れば同点の場面';
    if (risp > 0 && late) return '反撃のチャンス';
    return null;
  }

  /// コース（打者から見た内外角・高低）
  static (String, String, bool) course(PitchEvent e) {
    final inside = e.batterHand == 'L' ? e.x < -0.33 : e.x > 0.33;
    final outside = e.batterHand == 'L' ? e.x > 0.33 : e.x < -0.33;
    final h = e.z > 0.33 ? '高め' : (e.z < -0.33 ? '低め' : '');
    final w = inside ? '内角' : (outside ? '外角' : '');
    final edge = e.inZone && (e.x.abs() > 0.8 || e.z.abs() > 0.8);
    final text = (w.isEmpty && h.isEmpty) ? '真ん中' : '$w$h';
    return (text, w.isNotEmpty ? w : h, edge);
  }

  /// 打球の方向（m 単位の落下地点から）
  static String direction(PitchEvent e, {bool ground = false}) {
    final x = e.landX ?? 0, y = e.landY ?? 1;
    final deg = atan2(x, max(0.1, y)) * 180 / pi; // + がライト方向
    if (ground) {
      if (deg < -32) return '三塁線';
      if (deg < -16) return '三遊間';
      if (deg < -4) return 'ショート方向';
      if (deg < 4) return 'センター方向';
      if (deg < 16) return '二遊間';
      if (deg < 32) return '一二塁間';
      return '一塁線';
    }
    if (deg < -30) return 'レフト線';
    if (deg < -18) return 'レフト';
    if (deg < -7) return '左中間';
    if (deg < 7) return 'センター';
    if (deg < 18) return '右中間';
    if (deg < 30) return 'ライト';
    return 'ライト線';
  }

  /// 打者紹介（打席の最初の1球の前に出す）
  List<LiveLine> paIntro(PitchEvent e, {required int order, required String hand, required String pitcher}) {
    final out = <LiveLine>[];
    final today = e.batterToday.isEmpty || e.batterToday.startsWith('0打数0') ? '今日初打席' : '今日 ${e.batterToday}';
    out.add(LiveLine('$order番 ${e.batter}（$hand）　$today', 'pa'));
    final ch = chance(e);
    final sit = '${outs(e.outsBefore)}${bases(e.basesBefore)}';
    final sc = e.offBefore == e.defBefore ? '同点' : (e.offBefore > e.defBefore ? '${e.offBefore - e.defBefore}点リード' : '${e.defBefore - e.offBefore}点を追う');
    out.add(LiveLine('$sit・$sc${ch == null ? '' : '　$ch！'}　投手 $pitcher（${e.pitcherCount}球）', 'situation'));
    return out;
  }

  /// 1球の実況（打席の結果・得点・アウトの状況も含む）
  List<LiveLine> pitch(PitchEvent e, {required String offense, required String defense}) {
    if (e.paIndex != _lastPa) {
      _lastPa = e.paIndex;
      _foulStreak = 0;
    }
    final out = <LiveLine>[];
    final (c, side, edge) = course(e);
    final head = e.pitchName == 'スクイズ' ? '${e.pitchNo}球目' : '${e.pitchNo}球目 $c ${e.speed.round()}km ${e.pitchName}';
    final desc = e.desc;
    final ch = chance(e);
    final runs = e.offAfter - e.offBefore;
    final end = e.outsAfter != e.outsBefore || runs > 0 || e.result == 'インプレー' || e.result == 'バント' || desc.contains('四球') || desc.contains('死球') || desc.contains('三振');
    String res;
    var kind = 'pitch';
    var hit = false;

    if (e.result == '見逃し') {
      if (desc.contains('三振')) {
        kind = 'result';
        res = ch != null && r.nextBool() ? '$chも見逃し三振…' : _p(['見逃し三振！', '手が出ない！見逃し三振', '最後は$cの${e.pitchName}、見逃し三振！']);
      } else {
        res = edge ? _p(['$sideいっぱい、見逃してストライク', '$sideのコーナーに決まってストライク']) : _p(['見逃してストライク', 'ストライクを見送る']);
      }
    } else if (e.result == '空振り') {
      if (desc.contains('三振')) {
        kind = 'result';
        final low = e.z < -0.5 && e.speed < 140;
        res = ch != null && r.nextBool()
            ? '$chも空振り三振…'
            : low
                ? _p(['低めの${e.pitchName}にバットが空を切る、空振り三振！', '落ちる球に空振り三振！'])
                : _p(['空振り三振！', '${e.speed.round()}kmに空振り三振！', 'バットが空を切る、空振り三振']);
      } else {
        res = _p(['空振り', 'バットが空を切る', '振っていくも空振り']);
      }
    } else if (e.result == 'ファウル') {
      if (desc.contains('ファウルフライ')) {
        kind = 'result';
        res = _p(['打ち上げてファウルフライ、捕ってアウト', 'ファウルフライに倒れる']);
      } else if (e.strikes == 2) {
        _foulStreak++;
        res = _foulStreak >= 3 ? _p(['粘る！これで$_foulStreak球連続ファウル', 'しぶとい！$_foulStreak球続けてカット']) : _p(['この球も粘ってファウル', 'カットしてファウル', '追い込まれながら食らいつく']);
      } else {
        res = _p(['ファウル', '打ち返すもファウル', 'タイミングが合わずファウル']);
      }
    } else if (e.result == '死球') {
      kind = 'result';
      hit = true;
      res = _p(['死球！ 痛そうな表情で一塁へ', '内角の球が当たってデッドボール']);
    } else if (e.result == 'ボール') {
      if (desc.contains('四球')) {
        kind = 'result';
        hit = true;
        res = desc.contains('押し出し') || runs > 0
            ? '押し出しの四球！'
            : (e.pitchNo == 4 && e.strikes == 0)
                ? 'ストレートの四球'
                : _p(['四球を選んで出塁', 'よく見て四球', '歩かせました、フォアボール']);
      } else {
        final near = e.x.abs() < 1.2 && e.z.abs() < 1.2;
        res = near ? _p(['わずかに外れてボール', '際どいところ、ボール']) : _p(['外れてボール', '$sideに外れてボール']);
      }
    } else {
      kind = 'result';
      (res, hit) = _inPlay(e, desc, runs);
      if (e.outcome == 'ホームラン') kind = 'big';
    }

    final count = kind == 'pitch' ? '（${e.ballsAfter}-${e.strikesAfter}）' : '';
    out.add(LiveLine('$head　$res$count', kind, hit: hit));

    if (runs > 0) {
      final before = (e.offBefore - e.defBefore).sign, after = (e.offAfter - e.defAfter).sign;
      final tag = before < 0 && after > 0
          ? '逆転！'
          : (before < 0 && after == 0)
              ? '同点！'
              : (before == 0 && after > 0)
                  ? '勝ち越し！'
                  : '';
      out.add(LiveLine('$offense $runs点${tag.isEmpty ? '' : '　$tag'}　$offense ${e.offAfter} − ${e.defAfter} $defense', tag.isEmpty ? 'score' : 'big'));
    }
    if (desc.contains('サヨナラ')) out.add(const LiveLine('サヨナラ！！ 試合終了', 'big'));
    if (end && !desc.contains('サヨナラ')) {
      out.add(LiveLine(e.outsAfter >= 3 ? 'スリーアウト、チェンジ' : '${outs(e.outsAfter)}${bases(e.basesAfter)}', 'state'));
    }
    return out;
  }

  (String, bool) _inPlay(PitchEvent e, String desc, int runs) {
    final ground = e.contact == 'ゴロ';
    final dir = direction(e, ground: ground);
    final dist = sqrt(pow(e.landX ?? 0, 2) + pow(e.landY ?? 0, 2));
    final f = _fielder[e.fielder] ?? '';
    final timely = runs > 0;
    if (e.result == 'バント' || e.pitchName == 'スクイズ') {
      if (desc.contains('スクイズ成功')) return ('スクイズ成功！三塁走者が生還', true);
      if (desc.contains('スクイズ失敗')) return ('スクイズ失敗！', false);
      if (desc.contains('ヒット')) return ('セーフティバント成功、内野安打！', true);
      if (desc.contains('失敗')) return ('バント失敗…', false);
      return (_p(['送りバント成功', 'きっちり送りバント']), false);
    }
    switch (e.outcome) {
      case 'ホームラン':
        final k = runs >= 4 ? '満塁ホームラン' : (runs == 1 ? 'ソロホームラン' : '$runsランホームラン');
        final d = direction(e);
        return ('${_p(['打った！大きい！', '捉えた！', '高々と舞い上がった！', '弾丸ライナー！'])}$dスタンドへ${_p(['飛び込む', '突き刺さる', '消えていく'])}$k！（${dist.round()}m）', true);
      case '三塁打':
        return ('${timely ? 'タイムリー' : ''}$dirを破った！${_p(['一気に三塁へ、スリーベース！', '俊足を飛ばして三塁打！'])}', true);
      case '二塁打':
        return (timely ? '$dirを破るタイムリーツーベース！' : _p(['$dirを破るツーベース！', '$dirへの長打、二塁打！']), true);
      case '単打':
        if (ground && dist < 38) return ('${f.isEmpty ? '' : '$fへの'}当たり、内野安打！', true);
        if (timely) return (_p(['$dir${ground ? 'を破る' : 'へ運ぶ'}タイムリーヒット！', '$dirへ弾き返すタイムリー！']), true);
        if (ground) return (_p(['$dirを破るヒット', '$dirを抜けていくヒット']), true);
        if (e.contact == 'ライナー') return ('$dir前へ鋭いライナー、ヒット', true);
        return ('$dir前にポトリと落ちるヒット', true);
      case '併殺':
        return ('${f.isEmpty ? '' : '$f'}ゴロ、${_p(['ダブルプレー！', 'ゲッツー！'])}', false);
      case '野選':
        return ('フィルダースチョイス、オールセーフ', true);
    }
    if (e.errorBy.isNotEmpty) return ('${_fielder[e.errorBy] ?? ''}がエラー！出塁', true);
    if (desc.contains('犠牲フライ')) return ('$dirへのフライ、タッチアップ！犠牲フライで生還', false);
    if (ground) return (timely ? '$fゴロの間に走者生還' : _p(['$fゴロ', '$f正面のゴロ、アウト', '$fがさばいてアウト']), false);
    if (e.contact == 'ライナー') return (_p(['$fライナー、好捕！', '鋭い当たりも$fの正面']), false);
    if (e.contact == 'ポップフライ') return (_p(['$fへの内野フライ', '打ち上げた、$fフライ']), false);
    if (dist > 95) return ('大きな当たり！…しかし$dirが${_p(['フェンス際で捕球', '下がって捕った'])}', false);
    return (_p(['$dirへのフライ、捕ってアウト', '$dirフライ']), false);
  }
}
