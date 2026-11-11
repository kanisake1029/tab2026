/// ユニフォーム（体とは別の層。球団ごとに複数着。グッズと連動させる予定）
///  型（シルエット）・模様・文字（胸・背ネーム・番号）・マーク・小物の層に分けて持つ
///  色は 0xAARRGGBB
class Uniform {
  String id, name; // 例：'home'・'ホーム'
  // ───── 型 ─────
  String front; // 'ボタン'・'プルオーバー'
  String collar; // '無し'・'Vネック'・'ヘンリー'
  String pants; // 'ロング'・'ショート'（ストッキングを見せる）
  // ───── 模様 ─────
  int base; // 地の色
  Stripe? pinstripe;
  List<Trim> trims; // 袖口・襟・ボタン列・パンツ脇などのライン
  // ───── 文字 ─────
  Lettering chest; // 胸の文字
  Lettering backName; // 背ネーム（文字列は選手の登録名から）
  Lettering number; // 背番号（胸番号・袖番号の有無は下）
  bool chestNumber, sleeveNumber;
  // ───── マーク・小物 ─────
  int capBase, capBrim, capButton, capLogo;
  String capLogoText;
  int helmet, undershirt, socks, belt, shoes, glove;

  Uniform({
    this.id = 'home',
    this.name = 'ホーム',
    this.front = 'ボタン',
    this.collar = '無し',
    this.pants = 'ロング',
    this.base = 0xFFF8F8F6,
    this.pinstripe,
    List<Trim>? trims,
    Lettering? chest,
    Lettering? backName,
    Lettering? number,
    this.chestNumber = false,
    this.sleeveNumber = false,
    this.capBase = 0xFF1E3A8A,
    this.capBrim = 0xFF1E3A8A,
    this.capButton = 0xFF1E3A8A,
    this.capLogo = 0xFFFFFFFF,
    this.capLogoText = '',
    this.helmet = 0xFF1E3A8A,
    this.undershirt = 0xFF1E3A8A,
    this.socks = 0xFF1E3A8A,
    this.belt = 0xFF1E3A8A,
    this.shoes = 0xFF111111,
    this.glove = 0xFF6B3A1E,
  })  : trims = trims ?? [],
        chest = chest ?? Lettering(text: ''),
        backName = backName ?? Lettering(text: ''),
        number = number ?? Lettering(text: '');

  /// 球団の色から作る基本の1着（ホームは白地、ビジターは灰色地）
  factory Uniform.basic(int teamColor, {bool home = true, String chestText = ''}) {
    final c = teamColor | 0xFF000000;
    return Uniform(
      id: home ? 'home' : 'away',
      name: home ? 'ホーム' : 'ビジター',
      base: home ? 0xFFF8F8F6 : 0xFF9CA3AF,
      trims: [Trim('袖口', c, 0.012), Trim('パンツ脇', c, 0.012)],
      chest: Lettering(text: chestText, fill: c, outline1: 0xFFFFFFFF, outline1W: 0.004),
      backName: Lettering(text: '', fill: c),
      number: Lettering(text: '', fill: c, outline1: 0xFFFFFFFF, outline1W: 0.005),
      capBase: c, capBrim: c, capButton: c, helmet: c, undershirt: c, socks: c, belt: c,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'front': front, 'collar': collar, 'pants': pants, 'base': base,
        if (pinstripe != null) 'pin': pinstripe!.toJson(),
        'trims': [for (final t in trims) t.toJson()],
        'chest': chest.toJson(), 'backName': backName.toJson(), 'number': number.toJson(), 'chestNo': chestNumber, 'sleeveNo': sleeveNumber,
        'cap': [capBase, capBrim, capButton, capLogo], 'capText': capLogoText,
        'parts': [helmet, undershirt, socks, belt, shoes, glove],
      };

  factory Uniform.fromJson(Map<String, dynamic> j) {
    final cap = (j['cap'] as List?)?.cast<int>() ?? const [0xFF1E3A8A, 0xFF1E3A8A, 0xFF1E3A8A, 0xFFFFFFFF];
    final parts = (j['parts'] as List?)?.cast<int>() ?? const [0xFF1E3A8A, 0xFF1E3A8A, 0xFF1E3A8A, 0xFF1E3A8A, 0xFF111111, 0xFF6B3A1E];
    return Uniform(
      id: j['id'] ?? 'home', name: j['name'] ?? 'ホーム', front: j['front'] ?? 'ボタン', collar: j['collar'] ?? '無し', pants: j['pants'] ?? 'ロング', base: j['base'] ?? 0xFFF8F8F6,
      pinstripe: j['pin'] is Map ? Stripe.fromJson(Map<String, dynamic>.from(j['pin'])) : null,
      trims: [for (final t in (j['trims'] as List? ?? const [])) Trim.fromJson(Map<String, dynamic>.from(t))],
      chest: Lettering.fromJson(Map<String, dynamic>.from(j['chest'] ?? const {})),
      backName: Lettering.fromJson(Map<String, dynamic>.from(j['backName'] ?? const {})),
      number: Lettering.fromJson(Map<String, dynamic>.from(j['number'] ?? const {})),
      chestNumber: j['chestNo'] ?? false, sleeveNumber: j['sleeveNo'] ?? false,
      capBase: cap[0], capBrim: cap[1], capButton: cap[2], capLogo: cap[3], capLogoText: j['capText'] ?? '',
      helmet: parts[0], undershirt: parts[1], socks: parts[2], belt: parts[3], shoes: parts[4], glove: parts[5],
    );
  }
}

/// ピンストライプ（色・間隔・太さ m）
class Stripe {
  int color;
  double gap, width;
  Stripe(this.color, {this.gap = 0.025, this.width = 0.002});
  Map<String, dynamic> toJson() => {'c': color, 'g': gap, 'w': width};
  factory Stripe.fromJson(Map<String, dynamic> j) => Stripe(j['c'] ?? 0xFF1E3A8A, gap: (j['g'] ?? 0.025).toDouble(), width: (j['w'] ?? 0.002).toDouble());
}

/// ライン（場所・色・太さ m・本数）
class Trim {
  String place; // '袖口'・'襟'・'ボタン列'・'パンツ脇'・'肩'・'脇'
  int color;
  double width;
  int count;
  Trim(this.place, this.color, this.width, {this.count = 1});
  Map<String, dynamic> toJson() => {'p': place, 'c': color, 'w': width, 'n': count};
  factory Trim.fromJson(Map<String, dynamic> j) => Trim(j['p'] ?? '袖口', j['c'] ?? 0xFF1E3A8A, (j['w'] ?? 0.01).toDouble(), count: j['n'] ?? 1);
}

/// 文字（胸の文字・背ネーム・番号）：字体・並べ方・大きさ・塗り・縁取り2重・影
class Lettering {
  String text; // 背ネームは空なら選手の登録名（ローマ字など、形式は別に選ぶ）
  String font; // 'ブロック'・'筆記体'・'セリフ'・'ゴシック'・'明朝' など
  String layout; // 'まっすぐ'・'アーチ'・'斜め'
  double height; // 文字の高さ（m）
  double spacing; // 字間（文字の高さに対する比）
  int fill, outline1, outline2, shadow;
  double outline1W, outline2W, shadowDx, shadowDy;
  Lettering({
    required this.text,
    this.font = 'ブロック',
    this.layout = 'まっすぐ',
    this.height = 0.08,
    this.spacing = 0.05,
    this.fill = 0xFF1E3A8A,
    this.outline1 = 0,
    this.outline2 = 0,
    this.shadow = 0,
    this.outline1W = 0,
    this.outline2W = 0,
    this.shadowDx = 0,
    this.shadowDy = 0,
  });
  Map<String, dynamic> toJson() => {
        't': text, 'f': font, 'l': layout, 'h': height, 'sp': spacing, 'fill': fill, 'o1': outline1, 'o2': outline2, 'sh': shadow, 'o1w': outline1W, 'o2w': outline2W, 'sdx': shadowDx, 'sdy': shadowDy,
      };
  factory Lettering.fromJson(Map<String, dynamic> j) => Lettering(
        text: j['t'] ?? '', font: j['f'] ?? 'ブロック', layout: j['l'] ?? 'まっすぐ', height: (j['h'] ?? 0.08).toDouble(), spacing: (j['sp'] ?? 0.05).toDouble(),
        fill: j['fill'] ?? 0xFF1E3A8A, outline1: j['o1'] ?? 0, outline2: j['o2'] ?? 0, shadow: j['sh'] ?? 0,
        outline1W: (j['o1w'] ?? 0).toDouble(), outline2W: (j['o2w'] ?? 0).toDouble(), shadowDx: (j['sdx'] ?? 0).toDouble(), shadowDy: (j['sdy'] ?? 0).toDouble(),
      );
}
