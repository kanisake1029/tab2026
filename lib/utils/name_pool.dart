import 'dart:math';
import '../models/player.dart';
import 'name_data.dart';

/// 選手・コーチの名前の素材。よくある姓・名に、珍しめのものを混ぜて多様にする。
class NamePool {
  /// よくある姓（多めに出る）
  static const commonLast = [
    '佐藤', '鈴木', '高橋', '田中', '伊藤', '渡辺', '山本', '中村', '小林', '加藤', '吉田', '山田', '佐々木', '山口', '松本', '井上', '木村', '林', '斎藤', '清水',
    '山崎', '森', '池田', '橋本', '阿部', '石川', '山下', '中島', '石井', '小川', '前田', '藤田', '岡田', '後藤', '長谷川', '村上', '近藤', '坂本', '遠藤', '青木',
    '藤井', '西村', '福田', '太田', '三浦', '藤原', '岡本', '松田', '中川', '原田', '小野', '田村', '竹内', '金子', '和田', '中山', '石田', '上田', '森田', '小島',
    '柴田', '原', '宮崎', '酒井', '工藤', '横山', '宮本', '内田', '高木', '安藤', '島田', '谷口', '大野', '丸山', '今井', '河野', '藤本', '村田', '武田', '上野',
  ];

  /// ふつうの姓
  static const midLast = [
    '杉山', '増田', '小山', '大塚', '平野', '菅野', '久保', '松井', '千葉', '松尾', '岩崎', '木下', '野口', '菊地', '新井', '渡部', '水野', '杉本', '西田', '桜井',
    '野村', '佐野', '大西', '高田', '服部', '吉川', '山内', '西川', '五十嵐', '北村', '安田', '中田', '川口', '平田', '川崎', '飯田', '本田', '久保田', '沢田', '辻',
    '関', '吉村', '渡邊', '岩田', '中西', '樋口', '福島', '川上', '永井', '松岡', '田口', '荒木', '中野', '浅野', '大久保', '野田', '小松', '秋山', '大石', '星野',
    '堀', '尾崎', '望月', '永田', '熊谷', '内藤', '松浦', '松下', '今村', '堀内', '大橋', '川村', '岡崎', '吉岡', '黒田', '松村', '片山', '菅原', '早川', '白石',
    '上原', '荒井', '岩本', '浜田', '細川', '堤', '富田', '河合', '大島', '小池', '矢野', '広瀬', '北川', '平井', '高野', '小西', '宮田', '島崎', '谷', '馬場',
    '吉野', '田辺', '関口', '古川', '水谷', '石原', '東', '奥村', '神田', '大川', '福井', '須藤', '土屋', '桑原', '栗原', '飯塚', '宮下', '岡', '岩井', '西尾',
    '奥田', '鎌田', '本間', '寺田', '片岡', '市川', '大谷', '村井', '小沢', '牧野', '若林', '千田', '岩瀬', '梅田', '徳永', '日高', '川端', '長尾', '戸田', '米田',
  ];

  /// 珍しめの姓（ときどき出る）
  static const rareLast = [
    '東海林', '四ノ宮', '御手洗', '勅使河原', '小鳥遊', '一ノ瀬', '九条', '鬼塚', '神宮寺', '月岡', '鷹野', '獅子堂', '天童', '朝比奈', '鳳', '白鳥', '雲母', '葛城', '霧島', '不破',
    '真壁', '剣持', '風間', '日向', '如月', '早乙女', '伊集院', '綾瀬', '柊', '榊原', '宗像', '三条', '宇佐美', '鶴見', '荻野', '仲宗根', '比嘉', '金城', '具志堅', '玉城',
    '新垣', '宮城', '大城', '島袋', '知念', '安里', '屋良', '与那嶺', '照屋', '喜屋武', '阿久津', '猪狩', '鮫島', '轟', '百瀬', '万代', '八木', '十河', '五島',
    '六車', '七海', '二階堂', '三輪', '雨宮', '嵐', '春日', '夏目', '秋元', '冬木', '桐生', '梶原', '笠井', '舘', '巽', '楠', '椎名', '柘植', '蒔田', '芦田',
    '駒田', '駿河', '鳴海', '浪岡', '潮田', '湊', '汐見', '岬', '磯部', '灘', '瀬尾', '滝沢', '泉谷', '源', '平', '橘', '藤堂', '結城', '真田', '武藤',
    '海老原', '鹿島', '熊田', '猿渡', '犬飼', '鷲尾', '鷺沼', '雉子牟田', '牛島', '馬渕', '羽生', '堀越', '岸', '戸叶', '矢作', '安達', '水口', '有馬', '青柳',
    '黒木', '白井', '緑川', '紺野', '金丸', '銀島', '銅谷', '鉄平', '石嶺', '砂田', '土橋', '木場', '林田', '森下', '杉浦', '柳田', '梅津', '桃井',
  ];

  /// 名（平成〜令和生まれの選手向け）
  static const givenNames = [
    '翔太', '大樹', '健太', '拓也', '翼', '蓮', '大輔', '誠', '剛', '直樹', '達也', '和也', '翔', '大地', '大輝', '陽太', '陸', '駿', '海斗', '涼太',
    '悠真', '健', '一輝', '勇気', '雄大', '康平', '慎太郎', '光', '大空', '真', '大河', '和樹', '洋平', '健太郎', '聡', '裕太', '亮太', '智也', '悠', '蒼太',
    '優', '颯太', '歩', '大和', '優輝', '拓海', '琉生', '結翔', '陽向', '湊', '朝陽', '樹', '伊織', '陽翔', '碧', '律', '宗介', '健人', '直人', '和人',
    '海', '太陽', '大雅', '優人', '蒼空', '颯', '晴', '湊斗', '瑛太', '奏太', '悠人', '大翔', '樹生', '新', '朔', '凪', '岳', '航', '拓真', '玲央',
    '侑', '舜', '健斗', '遼', '尚輝', '一真', '勇人', '昂', '天馬', '光希', '凌', '壮真', '慧', '隼', '斗真', '和真', '晃大', '旭', '隼人', '翔平',
    '亮', '大介', '涼', '智', '雅也', '圭太', '恭平', '竜也', '龍之介', '虎太郎', '鷹斗', '陽介', '耕平', '修平', '純平', '祐介', '啓太', '貴之', '雄太', '翔吾',
    '凌太', '佑樹', '友哉', '将大', '将吾', '晃', '峻', '駿介', '俊介', '直輝', '尚哉', '匠', '巧', '丈', '壮', '仁', '迅', '響', '奏', '詠斗',
    '健吾', '圭吾', '大悟', '悟', '翔馬', '颯真', '遥斗', '春樹', '夏輝', '秋人', '冬馬', '一樹', '二郎', '三四郎', '吾郎', '大成', '泰成', '雄星', '流星', '昴',
    '銀河', '天翔', '飛翔', '空', '大夢', '拓夢', '勇翔', '勇吾', '剣', '剣斗', '武', '武蔵', '龍', '竜成', '龍星', '虎', '鉄平', '鉄也', '鋼', '豪',
    '豪太', '剛志', '剛士', '力', '力也', '勝也', '勝利', '克己', '克哉', '直哉', '尚人', '正樹', '正義', '義人', '義隆', '康介', '康太', '幸太', '幸輝', '福太郎',
    '健司', '賢治', '賢人', '賢太', '謙信', '信吾', '信太郎', '宏樹', '弘樹', '広大', '浩平', '航平', '航大', '公輔', '孝太', '考輝', '隆之介', '隆成', '貴大', '崇',
    '雅人', '雅樹', '昌平', '晶', '彰', '章吾', '翔一', '祥太', '将', '尚吾', '丞', '晋', '真吾', '慎吾', '新太', '進', '晴人', '晴輝', '清', '聖',
    '誠也', '静真', '拓斗', '琢磨', '卓也', '大吾', '太一', '泰介', '泰輔', '大貴', '一平', '一馬', '一希', '壱成', '海翔', '開', '凱', '楓', '要', '奏汰',
    'ジョージ', 'ケント', 'ルイ', 'レオ', 'ジョー',
  ];

  /// 名（昭和生まれのコーチ・OB向け）
  static const olderGivenNames = [
    '浩二', '博之', '和彦', '隆', '修', '茂', '正人', '克也', '秀樹', '勝', '昭', '剛', '豊', '学', '弘', '稔', '誠', '徹', '聡', '健一',
    '達夫', '康弘', '雅人', '信也', '英樹', '直人', '幸雄', '晃', '孝', '実', '一郎', '二郎', '三郎', '健二', '浩', '博', '清', '進', '功', '勲',
    '昌彦', '秀人', '光男', '義男', '敏夫', '正和', '和夫', '武志', '剛志', '重信', '忠', '仁', '譲', '肇', '満', '潤', '透', '亘', '恒夫', '靖',
    '真一', '伸二', '慎一', '純一', '幸一', '孝一', '健司', '賢一', '公一', '耕三', '晋三', '雄三', '正三', '栄治', '英治', '栄一', '和宏', '敦', '篤', '厚',
  ];

  /// 外国人（名・姓）
  static const foreignFirst = [
    'ジョシュ', 'マイク', 'カルロス', 'ルイス', 'デビッド', 'アンドリュー', 'ホセ', 'ライアン', 'タイラー', 'ブランドン', 'ミゲル', 'ケビン', 'エリック', 'ジャスティン', 'ラファエル', 'ネイト',
    'ジェイソン', 'マット', 'クリス', 'ダニエル', 'アレックス', 'ザック', 'コディ', 'トレバー', 'ディラン', 'ハビエル', 'フアン', 'ペドロ', 'アントニオ', 'エンリケ', 'ロベルト', 'ビクター',
    'フランシスコ', 'ヨアン', 'ユリエスキ', 'アドニス', 'ヤシエル', 'レアンドロ', 'ジョナサン', 'ニック', 'サム', 'ベン', 'ジェイク', 'ルーク', 'オースティン', 'カイル', 'ショーン', 'トミー',
  ];
  static const foreignLast = [
    'ハリントン', 'モラレス', 'ブラッドリー', 'ガルシア', 'ウォーカー', 'サンタナ', 'ベネット', 'クルーズ', 'フォスター', 'リベラ', 'マクレーン', 'オルティス', 'グレイソン', 'ペーニャ', 'コールマン', 'ダルトン',
    'ロドリゲス', 'マルティネス', 'ヘルナンデス', 'ロペス', 'ゴンザレス', 'ペレス', 'サンチェス', 'ラミレス', 'トーレス', 'フローレス', 'ディアス', 'レイエス', 'グティエレス', 'メンドーサ', 'カスティーヨ', 'バルガス',
    'スミス', 'ジョンソン', 'ウィリアムズ', 'ブラウン', 'ジョーンズ', 'ミラー', 'デービス', 'ウィルソン', 'アンダーソン', 'テイラー', 'トーマス', 'ムーア', 'マーティン', 'ジャクソン', 'トンプソン', 'ホワイト',
    'ハリス', 'クラーク', 'ルイス', 'ロビンソン', 'ヤング', 'アレン', 'キング', 'ライト', 'スコット', 'ヒル', 'グリーン', 'アダムス', 'ベイカー', 'ネルソン', 'カーター', 'ミッチェル',
    'ロバーツ', 'フィリップス', 'キャンベル', 'パーカー', 'エバンス', 'エドワーズ', 'コリンズ', 'スチュワート', 'モリス', 'マーフィー', 'クック', 'ロジャース', 'リード', 'ベル', 'ハワード', 'ワード',
    'アルバレス', 'ナバーロ', 'エスコバル', 'カマーチョ', 'オロスコ', 'パディーヤ', 'ベラスケス', 'アギラール', 'マドリガル', 'セラーノ', 'ロサリオ', 'フエンテス', 'カリーヨ', 'モンテロ', 'バティスタ', 'コルデロ',
  ];

  /// 台湾・韓国出身の選手（漢字の名前）
  static const asianLast = ['陳', '林', '王', '張', '李', '呉', '劉', '蔡', '楊', '黄', '郭', '許', '朴', '金', '崔', '鄭', '姜', '尹'];
  static const asianGiven = ['志明', '家銘', '俊廷', '宏偉', '冠霖', '承恩', '民浩', '在勲', '成俊', '東赫', '宇翔', '哲宇', '柏翰', '品豪', '志豪', '俊宇', '泰民', '賢宇'];

  static const _commonW = 35, _midW = 30, _rareW = 7, _genW = 28; // 出やすさの割合（%）。よくある字の組み合わせの姓（NameData）も混ぜる

  /// 日本人の姓。avoid に入っている姓はなるべく避ける（同じ球団での重複を減らす）
  static String jpLast(Random r, {Set<String> avoid = const {}}) {
    for (var i = 0; i < 12; i++) {
      final x = r.nextInt(_commonW + _midW + _rareW + _genW);
      final pool = x < _commonW ? commonLast : (x < _commonW + _midW ? midLast : (x < _commonW + _midW + _rareW ? rareLast : NameData.jpLastGen));
      final s = pool[r.nextInt(pool.length)];
      if (!avoid.contains(s)) return s;
    }
    return midLast[r.nextInt(midLast.length)];
  }

  static String jpFirst(Random r, {bool older = false}) {
    final pool = older ? olderGivenNames : (r.nextDouble() < 0.45 ? givenNames : NameData.jpGivenGen);
    return pool[r.nextInt(pool.length)];
  }

  /// 出身国に合わせた名前（アメリカ・オーストラリアは英語圏、メキシコ・キューバ・ドミニカは中南米、台湾・韓国は漢字、チェコ）
  static ({String last, String first, String nameType}) forOrigin(String origin, Random r) {
    switch (origin) {
      case '台湾':
        final n = chinese(r);
        return (last: n.last, first: n.first, nameType: 'B');
      case '韓国':
        final n = korean(r);
        return (last: n.last, first: n.first, nameType: 'B');
      case 'チェコ':
        return (last: NameData2.czechLast[r.nextInt(NameData2.czechLast.length)], first: NameData2.czechFirst[r.nextInt(NameData2.czechFirst.length)], nameType: 'F');
      case 'メキシコ' || 'キューバ' || 'ドミニカ':
        final last = r.nextDouble() < 0.8 ? NameData.latinLast[r.nextInt(NameData.latinLast.length)] : NameData.latinLastSet.elementAt(r.nextInt(NameData.latinLastSet.length));
        final first = r.nextDouble() < 0.7 ? NameData.latinFirst[r.nextInt(NameData.latinFirst.length)] : NameData.latinDoubleFirst[r.nextInt(NameData.latinDoubleFirst.length)];
        return (last: last, first: first, nameType: 'F');
      default:
        final last = r.nextDouble() < 0.6 ? NameData.engLast[r.nextInt(NameData.engLast.length)] : NameData.engLastAll[r.nextInt(NameData.engLastAll.length)];
        return (last: last, first: NameData.engFirst[r.nextInt(NameData.engFirst.length)], nameType: 'F');
    }
  }

  /// 出身国を割合から選ぶ（[(国, 重み)]）
  static String pickCountry(Random r, List<(String, int)> mix) {
    var x = r.nextInt(mix.fold(0, (a, e) => a + e.$2));
    for (final e in mix) {
      x -= e.$2;
      if (x < 0) return e.$1;
    }
    return mix.last.$1;
  }

  /// 出身地（都道府県。人口のおよその割合で）
  static String prefecture(Random r) => pickCountry(r, NameData2.prefectures);

  /// 中国・台湾の名前
  static ({String last, String first}) chinese(Random r) => (last: NameData.chineseLast[r.nextInt(NameData.chineseLast.length)], first: NameData.chineseGiven[r.nextInt(NameData.chineseGiven.length)]);

  /// 韓国の名前
  static ({String last, String first}) korean(Random r) => (last: NameData.koreanLast[r.nextInt(NameData.koreanLast.length)], first: NameData.koreanGiven[r.nextInt(NameData.koreanGiven.length)]);

  /// 外国人の名前（姓・名・表示名パターン）。15% は台湾・韓国出身（漢字）
  ///  姓が中南米なら名も中南米（二つ名も）、英語圏なら英語圏の名にそろえる
  static ({String last, String first, String nameType}) foreign(Random r, {Set<String> avoid = const {}}) {
    if (r.nextInt(100) < 15) {
      final n = r.nextDouble() < 0.5 ? chinese(r) : korean(r);
      return (last: n.last, first: n.first, nameType: 'B');
    }
    String pickLast() => r.nextDouble() < 0.6
        ? (r.nextBool() ? NameData.engLast[r.nextInt(NameData.engLast.length)] : NameData.latinLast[r.nextInt(NameData.latinLast.length)])
        : NameData.foreignLastGen[r.nextInt(NameData.foreignLastGen.length)];
    var last = pickLast();
    for (var i = 0; i < 8 && avoid.contains(last); i++) {
      last = pickLast();
    }
    final latin = NameData.latinLastSet.contains(last);
    final String first;
    if (latin) {
      final l = NameData.latinDoubleFirst;
      first = r.nextDouble() < 0.7 ? NameData.latinFirst[r.nextInt(NameData.latinFirst.length)] : l[r.nextInt(l.length)];
    } else {
      first = NameData.engFirst[r.nextInt(NameData.engFirst.length)];
    }
    return (last: last, first: first, nameType: 'F');
  }

  /// 1人の名前を国籍に合わせて付け直す。used は同じ球団で使った姓（重複を減らす）
  static void assign(Player p, Random r, {Set<String>? used}) {
    final avoid = used ?? <String>{};
    if (p.nationality == '海外') {
      final n = foreign(r, avoid: avoid);
      p.lastName = n.last;
      p.firstName = n.first;
      p.nameType = n.nameType;
    } else {
      p.lastName = jpLast(r, avoid: avoid);
      p.firstName = jpFirst(r);
      p.nameType = 'A';
    }
    p.customName = '';
    used?.add(p.lastName);
  }

  /// 球団の全選手の名前を付け直す
  static void assignTeam(Iterable<Player> players, Random r) {
    final used = <String>{};
    for (final p in players) {
      assign(p, r, used: used);
    }
  }
}
