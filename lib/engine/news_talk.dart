import 'dart:math';
import '../models/player.dart';

/// ニュース記事の言葉の部品：成績の文・評論家の見立て（才能・向上心まで見抜く）・ファンのコメント
class NewsTalk {
  static const critics = ['山根 誠一', '大川 剛', '佐伯 修', '黒沢 透', '森本 健吾', '石倉 秀明'];

  static String pos(Player p) => p.isPitcher ? '投手' : p.mainPosition;
  static String prof(Player p) => '${p.registeredName}（${p.age}歳・${pos(p)}）';

  /// 今季・通算の成績の文
  static String stats(Player p) {
    final s = p.seasonStats, c = p.career;
    if (p.isPitcher) {
      final now = s.pitchApps > 0 ? '今季は${s.pitchApps}登板で${s.wins}勝${s.losses}敗${s.saves > 0 ? '${s.saves}S' : ''}${s.holds > 0 ? '${s.holds}H' : ''}、防御率${s.era.toStringAsFixed(2)}。' : '';
      final car = c.pitchApps > 0 ? 'プロ通算${c.pitchApps}登板${c.wins}勝${c.losses}敗。' : '';
      return '$now$car${now.isEmpty && car.isEmpty ? '一軍での実績はまだない。' : ''}';
    }
    final now = s.atBats > 0 ? '今季は${s.games}試合で打率${s.battingAverage.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '')}・${s.homeRuns}本・${s.rbi}打点。' : '';
    final car = c.atBats > 0 ? 'プロ通算${c.hits}安打・${c.homeRuns}本塁打。' : '';
    return '$now$car${now.isEmpty && car.isEmpty ? '一軍での実績はまだない。' : ''}';
  }

  /// いちばんの持ち味
  static String strength(Player p) {
    final m = p.isPitcher
        ? {'最速${p.velocity}km/hの直球': p.velocity - 80, '制球力': p.control, 'スタミナ': p.stamina}
        : {'ミート力': (p.contactLeft + p.contactRight) ~/ 2, '長打力': p.power, '俊足': p.run, '強肩': p.arm};
    return m.entries.reduce((x, y) => x.value >= y.value ? x : y).key;
  }

  /// 評論家の見立て（才能・向上心・年齢）
  static String insight(Player p, Random r) {
    final t = p.talent, a = p.ambition;
    if (t >= 75 && a >= 70) return '才能も向上心も一級品。数年後には球界を代表する選手になっていてもおかしくない';
    if (t >= 75 && a < 40) return '素材は抜群だが、練習への姿勢に課題があると聞く。環境が変わって目の色が変われば化ける';
    if (t < 40 && a >= 75) return '素材は平凡だが、とにかく練習の虫。努力で這い上がってきたタイプだ';
    if (t < 35 && a < 35) return '正直、伸びしろは大きくない。今の力でどこまでやれるか';
    if (p.age >= 34) return '衰えは隠せないが、経験は若手にとって何よりの手本になる';
    if (p.age <= 23) return '${strength(p)}は若手の中でも目を引く。じっくり育てたい';
    return ['${strength(p)}は一軍でも十分に通用する', '使い続ければ結果を出せる力はある', '起用法しだいで、まだまだ伸びる'][r.nextInt(3)];
  }

  /// ファンが才能・向上心を見抜くコメント（目立つときだけ）
  static List<String> fanInsight(Player p, Random r) {
    final name = p.registeredName;
    final out = <String>[];
    if (p.talent >= 75) out.add(['$nameは素材が違う。数年後えぐいことになる', '$nameは才能だけなら球界トップクラスやろ', '$nameの身体能力は別格'][r.nextInt(3)]);
    if (p.talent >= 70 && p.ambition < 40) out.add(['$name、才能あるのに伸びない典型なんよな', '$nameはもっと練習したら化けるのに', '$name向上心なさそうなのがもったいない'][r.nextInt(3)]);
    if (p.ambition >= 75) out.add(['$nameは練習の虫らしいから化けるで', '$nameの野球に対する姿勢は見習いたい', '$name、オフも毎日練習してるらしい'][r.nextInt(3)]);
    if (p.talent < 40 && p.ambition < 40) out.add(['$name、正直伸びしろは感じない', '$nameは今がピークやろ'][r.nextInt(2)]);
    if (p.age <= 22 && p.talent >= 60) out.add('$nameはまだ若いし、ここからやで');
    return out;
  }

  /// どの記事にも使える一般的なコメント
  static List<String> generic(bool positive) => positive
      ? ['フロント仕事したな', 'これはワクワクする', 'ユニフォーム姿が楽しみ', '背番号何番になるんやろ', '今年はいけそうな気がする', 'ファンとしては嬉しいニュース', '早く球場で見たい']
      : ['なんか不安やな', 'フロントの考えがよう分からん', 'これで大丈夫なんか', '去年も同じこと言ってた気がする', 'もう少し様子見たい', '期待しすぎは禁物'];
}
