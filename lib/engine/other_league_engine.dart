import 'dart:math';
import '../models/other_league.dart';
import '../models/player.dart';
import '../utils/name_pool.dart';
import 'draft_engine.dart';
import 'foreign_engine.dart';
import 'quick_game.dart';

/// 他リーグ（MLB とマイナー・海外・米独立・日本独立）の生成と、毎日の試合・シーズンの区切り
class OtherLeagueEngine {

  /// リーグの定義（球団数は divisionSizes の合計）
  static final List<(OLeague, List<int>)> defs = [
    (const OLeague(id: 'MLB', name: 'MLB', group: 'アメリカ', level: 'MLB', mean: 71, ageLo: 23, ageHi: 37, games: 162, startM: 3, startD: 22, endM: 9, endD: 28, divisions: ['ア・リーグ東地区', 'ア・リーグ中地区', 'ア・リーグ西地区', 'ナ・リーグ東地区', 'ナ・リーグ中地区', 'ナ・リーグ西地区']), [5, 5, 5, 5, 5, 5]),
    (const OLeague(id: 'AAA', name: '3A', group: 'アメリカ', level: '3A', mean: 63, ageLo: 22, ageHi: 33, games: 162, startM: 3, startD: 22, endM: 9, endD: 28, divisions: ['インターナショナル東地区', 'インターナショナル中地区', 'インターナショナル西地区', 'パシフィック東地区', 'パシフィック中地区', 'パシフィック西地区']), [5, 5, 5, 5, 5, 5]),
    (const OLeague(id: 'AA', name: '2A', group: 'アメリカ', level: '2A', mean: 56, ageLo: 20, ageHi: 28, games: 162, startM: 3, startD: 22, endM: 9, endD: 28, divisions: ['イースタン東地区', 'イースタン中地区', 'イースタン西地区', 'テキサス東地区', 'テキサス中地区', 'テキサス西地区']), [5, 5, 5, 5, 5, 5]),
    (const OLeague(id: 'A', name: '1A', group: 'アメリカ', level: '1A', mean: 49, ageLo: 18, ageHi: 25, games: 162, startM: 3, startD: 22, endM: 9, endD: 28, divisions: ['サウス東地区', 'サウス中地区', 'サウス西地区', 'ミッドウェスト東地区', 'ミッドウェスト中地区', 'ミッドウェスト西地区']), [5, 5, 5, 5, 5, 5]),
    (const OLeague(id: 'KBO', name: 'KBO', group: 'アジア', level: 'KBO', mean: 60, ageLo: 20, ageHi: 37, games: 144, startM: 3, startD: 22, endM: 10, endD: 1, divisions: ['']), [10]),
    (const OLeague(id: 'CPBL', name: 'CPBL', group: 'アジア', level: 'CPBL', mean: 56, ageLo: 20, ageHi: 37, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['']), [6]),
    (const OLeague(id: 'MEX', name: 'メキシカンリーグ', group: '中南米', level: 'メキシカンリーグ', mean: 57, ageLo: 21, ageHi: 39, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['北地区', '南地区']), [10, 10]),
    (const OLeague(id: 'ME', name: '中東リーグ', group: 'その他', level: '中東リーグ', mean: 45, ageLo: 19, ageHi: 35, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['']), [4]),
    (const OLeague(id: 'AUS', name: '豪州リーグ', group: 'その他', level: '豪州リーグ', mean: 50, ageLo: 18, ageHi: 35, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['']), [4]),
    (const OLeague(id: 'US1', name: '北東リーグ', group: '米独立', level: '米独立', mean: 53, ageLo: 21, ageHi: 35, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['北地区', '南地区']), [5, 5]),
    (const OLeague(id: 'US2', name: 'アメリカカナダリーグ', group: '米独立', level: '米独立', mean: 51, ageLo: 21, ageHi: 35, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['東地区', '西地区']), [6, 6]),
    (const OLeague(id: 'US3', name: '中西部リーグ', group: '米独立', level: '米独立', mean: 49, ageLo: 21, ageHi: 34, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['東地区', '西地区']), [9, 9]),
    (const OLeague(id: 'US4', name: '西部リーグ', group: '米独立', level: '米独立', mean: 48, ageLo: 21, ageHi: 34, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['']), [12]),
    (const OLeague(id: 'US5', name: 'ミシガン州リーグ', group: '米独立', level: '米独立', mean: 45, ageLo: 20, ageHi: 33, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['']), [4]),
    (const OLeague(id: 'US6', name: '西海岸リーグ', group: '米独立', level: '米独立', mean: 46, ageLo: 20, ageHi: 33, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['北地区', '中地区', '南地区']), [5, 5, 6]),
    (const OLeague(id: 'JP1', name: '四国リーグ', group: '日本独立', level: '日本独立', mean: 47, ageLo: 19, ageHi: 31, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['']), [4]),
    (const OLeague(id: 'JP2', name: 'BCリーグ', group: '日本独立', level: '日本独立', mean: 46, ageLo: 19, ageHi: 31, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['']), [9]),
    (const OLeague(id: 'JP3', name: '関西リーグ', group: '日本独立', level: '日本独立', mean: 43, ageLo: 19, ageHi: 30, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['']), [5]),
    (const OLeague(id: 'JP4', name: '北海道リーグ', group: '日本独立', level: '日本独立', mean: 42, ageLo: 19, ageHi: 30, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['北地区', '南地区']), [2, 4]),
    (const OLeague(id: 'JP5', name: '九州リーグ', group: '日本独立', level: '日本独立', mean: 44, ageLo: 19, ageHi: 30, games: 120, startM: 3, startD: 22, endM: 9, endD: 15, divisions: ['']), [4]),
    (const OLeague(id: 'JP6', name: '日本海リーグ', group: '日本独立', level: '日本独立', mean: 42, ageLo: 19, ageHi: 30, games: 120, startM: 3, startD: 22, endM: 9, endD: 30, divisions: ['']), [3]),
  ];

  /// リーグの打率の水準を合わせる補正（MLB ≒ .250、KBO ≒ .265、CPBL ≒ .270、メキシカン ≒ .285）
  static const hitAdj = {'MLB': 0.015, 'AAA': 0.022, 'AA': 0.02, 'A': 0.018, 'KBO': 0.048, 'CPBL': 0.04, 'MEX': 0.012, 'ME': 0.05, 'AUS': 0.05, 'JP1': 0.0, 'JP2': 0.0, 'JP3': 0.0, 'JP4': 0.0, 'JP5': 0.0, 'JP6': 0.0};

  /// リーグごとの出身国の割合（日本独立は '日本' が日本人）
  static const _usMix = [('アメリカ', 66), ('ドミニカ', 16), ('キューバ', 5), ('メキシコ', 5), ('オーストラリア', 3), ('韓国', 2), ('台湾', 2), ('チェコ', 1)];
  static const _indyMix = [('アメリカ', 80), ('ドミニカ', 7), ('キューバ', 4), ('メキシコ', 4), ('オーストラリア', 3), ('チェコ', 2)];
  static const originMix = <String, List<(String, int)>>{
    'MLB': _usMix, 'AAA': _usMix, 'AA': _usMix, 'A': _usMix,
    'KBO': [('韓国', 88), ('アメリカ', 7), ('ドミニカ', 3), ('キューバ', 1), ('メキシコ', 1)],
    'CPBL': [('台湾', 88), ('アメリカ', 6), ('ドミニカ', 4), ('メキシコ', 2)],
    'MEX': [('メキシコ', 70), ('キューバ', 10), ('ドミニカ', 10), ('アメリカ', 10)],
    'ME': [('アメリカ', 35), ('チェコ', 20), ('オーストラリア', 15), ('ドミニカ', 15), ('キューバ', 15)],
    'AUS': [('オーストラリア', 75), ('アメリカ', 13), ('韓国', 4), ('台湾', 4), ('チェコ', 4)],
    'US1': _indyMix, 'US2': _indyMix, 'US3': _indyMix, 'US4': _indyMix, 'US5': _indyMix, 'US6': _indyMix,
  };
  static const _jpIndyForeign = [('アメリカ', 60), ('ドミニカ', 25), ('台湾', 8), ('韓国', 7)];

  /// 本塁打の出やすさの補正（打高のリーグ）
  static const hrAdj = {'KBO': 0.014, 'ME': 0.025, 'AUS': 0.025, 'MEX': 0.0};

  static final Map<String, OLeague> leagues = {for (final d in defs) d.$1.id: d.$1};
  static const groups = ['アメリカ', 'アジア', '中南米', 'その他', '米独立', '日本独立'];

  /// 選手の顔ぶれの目安：平均・上位10%の平均・上位3%の平均・最高（OVR）と、年齢層の割合（%。〜22・23〜26・27〜30・31〜34・35〜）
  static ({double avg, double top10, double top3, int max, List<int> ages}) profile(List<Player> ps) {
    if (ps.isEmpty) return (avg: 0, top10: 0, top3: 0, max: 0, ages: const [0, 0, 0, 0, 0]);
    final o = ps.map((p) => p.ovr).toList()..sort((a, b) => b.compareTo(a));
    double topAvg(double f) {
      final n = (o.length * f).ceil().clamp(1, o.length);
      return o.take(n).reduce((a, b) => a + b) / n;
    }

    final b = [0, 0, 0, 0, 0];
    for (final p in ps) {
      b[p.age <= 22 ? 0 : (p.age <= 26 ? 1 : (p.age <= 30 ? 2 : (p.age <= 34 ? 3 : 4)))]++;
    }
    return (avg: o.reduce((a, b) => a + b) / o.length, top10: topAvg(0.10), top3: topAvg(0.03), max: o.first, ages: [for (final x in b) (x * 100 / ps.length).round()]);
  }

  // ───────── 名前（架空） ─────────
  static const _usCities = ['ボストン', 'ニューヨーク', 'フィラデルフィア', 'ボルチモア', 'ピッツバーグ', 'クリーブランド', 'デトロイト', 'シカゴ', 'ミルウォーキー', 'ミネアポリス', 'セントルイス', 'カンザスシティ', 'シンシナティ', 'アトランタ', 'マイアミ', 'タンパ', 'ヒューストン', 'ダラス', 'デンバー', 'フェニックス', 'ソルトレイク', 'シアトル', 'ポートランド', 'サンフランシスコ', 'オークランド', 'ロサンゼルス', 'サンディエゴ', 'ラスベガス', 'ナッシュビル', 'シャーロット',
    'インディアナポリス', 'コロンバス', 'バッファロー', 'ロチェスター', 'シラキュース', 'スクラントン', 'リーハイバレー', 'ノーフォーク', 'リッチモンド', 'ダーラム', 'メンフィス', 'ルイビル', 'トレド', 'アイオワ', 'オマハ', 'オクラホマシティ', 'アルバカーキ', 'エルパソ', 'リノ', 'サクラメント', 'タコマ', 'フレズノ', 'スポケーン', 'ボイシ', 'ビロクシ', 'モンゴメリー', 'チャタヌーガ', 'ジャクソンビル', 'ペンサコーラ', 'アマリロ',
    'ハリスバーグ', 'エリー', 'アルトゥーナ', 'ポートランドME', 'ハートフォード', 'ニューハンプシャー', 'トレントン', 'レディング', 'アクロン', 'ボウイ', 'タルサ', 'ウィチタ', 'スプリングフィールド', 'ノースウェストアーカンソー', 'コーパスクリスティ', 'サンアントニオ', 'ミッドランド', 'フリスコ', 'ヒルズボロ', 'ユージーン', 'エバレット', 'モデスト', 'ストックトン', 'ランカスター', 'インランドエンパイア', 'レイクエルシノア', 'バイセイリア', 'デイトン', 'グリーンビル', 'アッシュビル'];
  static const _nick = ['ハーバーズ', 'ノーザンズ', 'コメッツ', 'マリナーズ', 'パイオニアーズ', 'ローバーズ', 'サンダーズ', 'クリッパーズ', 'ナイツ', 'ブルズ', 'フォックス', 'ホークス', 'イーグルス', 'ベアーズ', 'ウルブズ', 'スターズ', 'ロケッツ', 'アイアンズ', 'レンジャーズ', 'スチーマーズ', 'エクスプレス', 'バイソンズ', 'ステッパーズ', 'ハンマーズ', 'フラッシュ', 'ウェーブ', 'コンドルズ', 'ストーム', 'サンズ', 'リバードッグス', 'ガルズ', 'キャニオンズ', 'ブレイザーズ', 'ドラゴンズ', 'ジャガーズ', 'ラトラーズ', 'マーリンズ', 'オウルズ', 'ベルズ', 'ラムズ'];
  static const _krCities = ['ソウル', '仁川', '水原', '大田', '大邱', '光州', '釜山', '昌原', '蔚山', '清州'];
  static const _twCities = ['台北', '桃園', '新竹', '台中', '台南', '高雄'];
  static const _mxCities = ['モンテレイ', 'ティフアナ', 'モンクローバ', 'サルティーヨ', 'チワワ', 'ドゥランゴ', 'ラレド', 'アグアスカリエンテス', 'メキシコシティ', 'プエブラ', 'オアハカ', 'ユカタン', 'カンペチェ', 'タバスコ', 'キンタナロー', 'ベラクルス', 'レオン', 'ハリスコ', 'トレオン', 'ケレタロ'];
  static const _meCities = ['ドバイ', 'アブダビ', 'ドーハ', 'リヤド'];
  static const _auCities = ['シドニー', 'メルボルン', 'ブリスベン', 'パース'];
  static const _usIndCities = ['ロングアイランド', 'サマセット', 'ヨーク', 'ゲーリー', 'ウィニペグ', 'スーフォールズ', 'シャンバーグ', 'ケイン郡', 'ゲートウェイ', 'ジョリエット', 'エバンズビル', 'フロレンス', 'ワシントンPA', 'ロックランド', 'トロワリビエール', 'ケベック', 'オタワ', 'ニュージャージー', 'スタテン島', 'ハイポイント', 'ガストニア', 'レキシントン', 'チャールストンWV', 'ハガーズタウン', 'ファーゴ', 'クリーブランドTN', 'レイクカントリー', 'カンザスシティKS', 'ミルウォーキーWI', 'シカゴ郊外', 'ソノマ', 'サンラファエル', 'ナパ', 'モントレー', 'ビスタ', 'ベーカーズフィールド', 'グレンデール', 'ツーソン', 'ラスクルーセス', 'ヒューストン郊外', 'ロッキーマウンテン', 'ボールダー', 'ユタ', 'アイダホフォールズ', 'ミズーラ', 'ビリングス', 'グレートフォールズ', 'オグデン', 'グランドジャンクション', 'カスパー', 'ラピッドシティ', 'ランシング', 'ポートヒューロン', 'トラバースシティ', 'カラマズー', 'グランドラピッズ', 'サギノー', 'フリント', 'ユーリカ', 'メドフォード', 'セーラム', 'アストリア', 'ベリンガム', 'レッドウッド', 'サンタローザ', 'チコ', 'レディング', 'バイセイリアCA', 'マリポサ', 'サンタバーバラ', 'オックスナード', 'ベンチュラ'];
  static const _jpTeams = {
    'JP1': ['徳島', '香川', '愛媛', '高知'],
    'JP2': ['新潟', '信濃', '富山', '石川', '福井', '群馬', '埼玉', '茨城', '栃木'],
    'JP3': ['兵庫', '大阪', '京都', '奈良', '和歌山'],
    'JP4': ['札幌', '旭川', '函館', '帯広', '釧路', '苫小牧'],
    'JP5': ['福岡', '熊本', '大分', '宮崎'],
    'JP6': ['鳥取', '島根', '山口'],
  };
  static const _jpNick = ['インディゴソックス', 'ブルースターズ', 'ファイティングマウンテンズ', 'ドラゴンファイターズ', 'アルビレックス', 'グランセローズ', 'サンダーバーズ', 'ミリオンスターズ', 'ワイルドラプターズ', 'ダイヤモンドペガサス', 'ヒートベアーズ', 'アストロプラネッツ', 'ゴールデンゴールズ', 'ブレイズ', 'シーホース', 'ディアーズ', 'ハーツ', 'ウィンズ', 'ネイチャーズ', 'ライナーズ', 'ホワイトベアーズ', 'ノーザンレッツ', 'スターマインズ', 'ブルーオーシャンズ', 'サンビームス', 'ファルコンズ', 'ブリッツ', 'ドリームス', 'フェニックス', 'サムライズ', 'オーシャンズ'];

  // ───────── 生成 ─────────

  /// 全リーグの球団と選手を作る（ゲーム開始時・以前のセーブで初めて開いたとき）
  static OtherWorld generate(DateTime today, int seasonYear) {
    final r = Random(seasonYear * 7919 + 13);
    final teams = <OTeam>[];
    final usedNames = <String>{};
    String pick(List<String> l, int i) => l[i % l.length];
    // MLB と、その傘下の 3A・2A・1A（同じ地区の並び）
    final mlbIds = <String>[];
    var cityIdx = 0;
    for (final lg in ['MLB', 'AAA', 'AA', 'A']) {
      final sizes = defs.firstWhere((d) => d.$1.id == lg).$2;
      var k = 0;
      for (var div = 0; div < sizes.length; div++) {
        for (var j = 0; j < sizes[div]; j++) {
          final city = pick(_usCities, cityIdx++);
          var nick = _nick[(k * 7 + lg.length * 3 + div) % _nick.length];
          var name = '$city・$nick';
          for (var g = 1; usedNames.contains(name); g++) {
            nick = _nick[(k * 7 + g * 11 + div) % _nick.length];
            name = '$city・$nick';
          }
          usedNames.add(name);
          final id = '${lg}_$k';
          if (lg == 'MLB') mlbIds.add(id);
          teams.add(OTeam(id: id, name: name, short: city, leagueId: lg, division: div, org: lg == 'MLB' ? '' : mlbIds[k]));
          k++;
        }
      }
    }
    void simple(String lg, List<String> cities) {
      final sizes = defs.firstWhere((d) => d.$1.id == lg).$2;
      var k = 0;
      for (var div = 0; div < sizes.length; div++) {
        for (var j = 0; j < sizes[div]; j++) {
          final city = cities[k % cities.length];
          final nick = _nick[(k * 5 + lg.hashCode) % _nick.length];
          teams.add(OTeam(id: '${lg}_$k', name: '$city・$nick', short: city, leagueId: lg, division: div));
          k++;
        }
      }
    }

    simple('KBO', _krCities);
    simple('CPBL', _twCities);
    simple('MEX', _mxCities);
    simple('ME', _meCities);
    simple('AUS', _auCities);
    var ui = 0;
    for (final lg in ['US1', 'US2', 'US3', 'US4', 'US5', 'US6']) {
      final sizes = defs.firstWhere((d) => d.$1.id == lg).$2;
      var k = 0;
      for (var div = 0; div < sizes.length; div++) {
        for (var j = 0; j < sizes[div]; j++) {
          final city = _usIndCities[ui % _usIndCities.length];
          final nick = _nick[(ui * 3 + 17) % _nick.length];
          ui++;
          teams.add(OTeam(id: '${lg}_$k', name: '$city・$nick', short: city, leagueId: lg, division: div));
          k++;
        }
      }
    }
    var ji = 0;
    for (final e in _jpTeams.entries) {
      final sizes = defs.firstWhere((d) => d.$1.id == e.key).$2;
      var k = 0;
      for (var div = 0; div < sizes.length; div++) {
        for (var j = 0; j < sizes[div]; j++) {
          final city = e.value[k];
          final nick = _jpNick[ji++ % _jpNick.length];
          teams.add(OTeam(id: '${e.key}_$k', name: '$city$nick', short: city, leagueId: e.key, division: div));
          k++;
        }
      }
    }
    for (final t in teams) {
      fillRoster(t, seasonYear, r);
    }
    return OtherWorld(teams: teams, simDate: DateTime(today.year, today.month, today.day), seasonYear: seasonYear);
  }

  static int _seq = 0;
  /// MLB のスターの割合
  static const starRate = 0.06;

  /// 1人作る（リーグに合わせた国籍・名前・力）
  static Player makePlayer(OLeague lg, int year, Random r, {required bool pitcher, String? pos, double? mean, int? age}) {
    final young = lg.id == 'AAA' || lg.id == 'AA' || lg.id == 'A' || lg.group == '米独立' || lg.group == '日本独立';
    final a = age ?? lg.ageLo + ((lg.ageHi - lg.ageLo + 1) * pow(r.nextDouble(), young ? 1.5 : 1.0)).floor().clamp(0, lg.ageHi - lg.ageLo);
    // 若い選手は伸びしろがある分、今の力は少し低い。全盛期（27〜30）が一番
    final ageAdj = a < 25 ? -(25 - a) * 1.2 : (a > 31 ? -(a - 31) * 1.0 : 0.0);
    var m = (mean ?? lg.mean) + ageAdj + _g(r) * 5;
    if (lg.id == 'MLB' && mean == null && r.nextDouble() < starRate) m += 12 + r.nextDouble() * 7; // MLB のスター
    if (lg.id == 'MLB') m = min(m, 93);
    final id = 'OL${year}_${lg.id}_${DateTime.now().microsecondsSinceEpoch % 100000000}_${_seq++}';
    Player p;
    // 日本独立リーグは95%が日本人（5%は外国人）
    final jp = lg.group == '日本独立' && r.nextDouble() < 0.95;
    final origin = lg.group == '日本独立' ? NamePool.pickCountry(r, _jpIndyForeign) : NamePool.pickCountry(r, originMix[lg.id] ?? _usMix);
    if (jp) {
      // 日本人の独立リーグの選手（ドラフト候補の作り方で）
      p = DraftEngine.makeAmateur(r, year, id, '独立').player;
      for (var i = 0; i < 40 && p.isPitcher != pitcher; i++) {
        p = DraftEngine.makeAmateur(r, year, id, '独立').player;
      }
      p.age = a;
      _shift(p, m - p.ovr);
      p.nationality = '日本';
    } else {
      p = ForeignEngine.make(year, r, ikusei: false, age: a, mean: m, id: id, origin: origin);
      // 投手か野手かを合わせる（作り直し）
      for (var i = 0; i < 40 && p.isPitcher != pitcher; i++) {
        p = ForeignEngine.make(year, r, ikusei: false, age: a, mean: m, id: id, origin: origin);
      }
      // 前のシーズンまでの来歴（出身に合わせて作る。ここからは実際の成績が足されていく）
      p.abroad = ForeignEngine.abroadRecord(p, p.origin, year - 1, r, young: a <= 23);
    }
    p.draftInfo = '';
    p.salary = 0;
    p.proYears = max(1, a - (lg.group == '日本独立' ? 20 : 19));
    setPotential(p, lg, r); // 日本の独立リーグの日本人選手も
    return p;
  }

  /// リーグでの伸びやすさ（MLB＝1.2）。2A・1A・アジア・豪州などは伸びにくい（才能はあっても、環境で伸び切らない。日本に来ると化ける）
  static double growMult(String leagueId) => switch (leagueId) {
        'MLB' => 1.2,
        'AAA' => 0.85,
        'MEX' => 0.6,
        'AA' => 0.6,
        'A' => 0.55,
        'KBO' => 0.55,
        'CPBL' => 0.5,
        'AUS' || 'ME' => 0.45,
        _ => (leagues[leagueId]?.group == '日本独立') ? 0.7 : 0.6,
      };

  /// 海外の選手の才能・向上心：MLB・3A はやや高め、2A・1A・アジア・豪州などは「素質はあるが、まだ伸び切っていない」選手が多い（若いほど高い）
  static void setPotential(Player p, OLeague lg, Random r) {
    final raw = growMult(lg.id) < 0.8;
    final indie = lg.group == '米独立' || lg.group == '日本独立';
    final young = (25 - p.age).clamp(-6, 8);
    p.talent = ((indie ? 64 : (raw ? 62 : 57)) + young * 1.2 + _g(r) * (raw ? 13 : 10)).round().clamp(20, 99);
    p.ambition = ((indie ? 64 : (raw ? 60 : 56)) + _g(r) * 13).round().clamp(20, 99);
  }

  static double _g(Random r) => sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

  /// 力を全体に d だけ動かす（アマチュア球界の成長にも使う）
  static void shiftAbility(Player p, double d) => _shift(p, d);

  /// 能力をまとめて上げ下げする（今の力をリーグに合わせる）
  static void _shift(Player p, double d) {
    final k = d.round();
    if (k == 0) return;
    int c(int v) => (v + k).clamp(15, 95);
    if (p.isPitcher) {
      p.pitchPower = c(p.pitchPower);
      p.control = c(p.control);
      p.stamina = c(p.stamina);
    } else {
      p.contactLeft = c(p.contactLeft);
      p.contactRight = c(p.contactRight);
      p.power = c(p.power);
      p.eye = c(p.eye);
      p.run = c(p.run);
    }
  }

  /// 1球団26人（投手13・野手13）にそろえる
  static void fillRoster(OTeam t, int year, Random r) {
    final lg = leagues[t.leagueId]!;
    const posNeed = ['捕手', '捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手', '二塁手', '遊撃手', '中堅手', '一塁手'];
    final pitchers = t.players.where((p) => p.isPitcher).length;
    for (var i = pitchers; i < 13; i++) {
      t.players.add(makePlayer(lg, year, r, pitcher: true));
    }
    final have = [for (final p in t.players.where((p) => !p.isPitcher)) p.mainPosition];
    for (final pos in posNeed) {
      if (have.remove(pos)) continue;
      if (t.players.where((p) => !p.isPitcher).length >= 13) break;
      final p = makePlayer(lg, year, r, pitcher: false);
      p.mainPos = pos;
      t.players.add(p);
    }
  }

  // ───────── 試合 ─────────

  /// 1チームの今日の顔ぶれ：守備位置ごとに一番の選手＋指名打者、先発は5人のローテ
  static QuickSide side(OTeam t) {
    final bats = t.players.where((p) => !p.isPitcher && p.injuryDays <= 0).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final lineup = <Player>[];
    for (final pos in const ['捕手', '一塁手', '二塁手', '三塁手', '遊撃手', '左翼手', '中堅手', '右翼手']) {
      final p = bats.where((p) => p.mainPosition == pos && !lineup.contains(p)).firstOrNull ?? bats.where((p) => !lineup.contains(p)).firstOrNull;
      if (p != null) lineup.add(p);
    }
    final dh = bats.where((p) => !lineup.contains(p)).firstOrNull;
    if (dh != null) lineup.add(dh);
    // 打順：出塁・長打のある順に（簡易）
    lineup.sort((a, b) => (b.contactLeft + b.contactRight + b.power + b.eye).compareTo(a.contactLeft + a.contactRight + a.power + a.eye));
    final pits = t.players.where((p) => p.isPitcher).toList()..sort((a, b) => (b.stamina * 0.6 + b.ovr * 0.4).compareTo(a.stamina * 0.6 + a.ovr * 0.4));
    final rot = pits.take(5).toList();
    final starter = rot.isEmpty ? pits.first : rot[t.rotation % rot.length];
    final pen = pits.where((p) => !rot.contains(p)).toList()..sort((a, b) => b.ovr.compareTo(a.ovr));
    final closer = pen.isEmpty ? null : pen.first;
    final rest = pen.skip(1).toList()..shuffle(Random(t.rotation * 31 + t.w + t.l));
    return QuickSide(lineup, starter, rest, closer);
  }

  /// その日の試合（シーズン中のリーグだけ。試合のある日は、試合数÷日数の割合で決まる）
  static void playDay(OtherWorld w, DateTime d) {
    final r = Random(d.millisecondsSinceEpoch ~/ 86400000 * 131 + 7);
    for (final lg in leagues.values) {
      if (!lg.inSeason(d)) continue;
      final ts = w.teamsOf(lg.id)..shuffle(r);
      // 球団数が奇数のリーグは毎回1球団が休むので、その分だけ試合の日を増やす
      final rate = (lg.games / lg.daysIn(d.year) * (ts.length.isOdd ? ts.length / (ts.length - 1) : 1)).clamp(0.0, 1.0);
      // 試合の日はシーズンの中で均等に（日数×割合が1つ増える日）
      final start = OLeague.opening(d.year);
      final k = DateTime(d.year, d.month, d.day).difference(start).inDays;
      if ((k + 1) * rate ~/ 1 == k * rate ~/ 1) continue;
      // 同じ地区どうしを多めに（6割）
      ts.sort((a, b) => a.division.compareTo(b.division));
      final pairs = <(OTeam, OTeam)>[];
      final pool = List.of(ts);
      while (pool.length >= 2) {
        final a = pool.removeAt(0);
        var j = pool.indexWhere((b) => b.division == a.division);
        if (j < 0 || r.nextDouble() < 0.4) j = r.nextInt(pool.length);
        pairs.add((a, pool.removeAt(j)));
      }
      final g = QuickGame(r, (p) => p.seasonStats, hitAdj: hitAdj[lg.id] ?? 0.02, hrAdj: hrAdj[lg.id] ?? 0);
      for (final (a, h) in pairs) {
        final (sa, sh) = g.play(side(a), side(h));
        for (final (t, mine, theirs) in [(a, sa, sh), (h, sh, sa)]) {
          if (mine > theirs) {
            t.w++;
          } else if (mine < theirs) {
            t.l++;
          } else {
            t.d++;
          }
          t.rotation++;
        }
      }
    }
  }

  /// タイトルの上位3人の行（「本塁打　41本 山田 太郎（ヤンキース）／…」）。規定は試合数×3.1打席・×1回
  static List<String> leaderLines(List<OTeam> ts) {
    final games = ts.isEmpty ? 0 : ts.map((t) => t.w + t.l + t.d).reduce(max);
    final all = [for (final t in ts) for (final p in t.players) (t, p)];
    int pa(PlayerStats s) => s.atBats + s.walks + s.sacFlies;
    final qPa = (games * 3.1).floor(), qOuts = games * 3;
    String r3(double v) => v.toStringAsFixed(3).replaceFirst('0.', '.');
    String one(String title, bool Function(Player) f, num Function(PlayerStats) v, String Function(PlayerStats) txt, {bool low = false}) {
      final l = all.where((x) => f(x.$2)).toList()..sort((a, b) => low ? v(a.$2.seasonStats).compareTo(v(b.$2.seasonStats)) : v(b.$2.seasonStats).compareTo(v(a.$2.seasonStats)));
      if (l.isEmpty) return '';
      return '$title　${l.take(3).map((x) => '${txt(x.$2.seasonStats)} ${x.$2.registeredName}（${x.$1.short}）').join('／')}';
    }

    return [
      one('打率', (p) => !p.isPitcher && pa(p.seasonStats) >= qPa && qPa > 0, (s) => s.battingAverage, (s) => r3(s.battingAverage)),
      one('本塁打', (p) => !p.isPitcher && p.seasonStats.homeRuns > 0, (s) => s.homeRuns, (s) => '${s.homeRuns}本'),
      one('打点', (p) => !p.isPitcher && p.seasonStats.rbi > 0, (s) => s.rbi, (s) => '${s.rbi}'),
      one('盗塁', (p) => !p.isPitcher && p.seasonStats.stolenBases > 0, (s) => s.stolenBases, (s) => '${s.stolenBases}'),
      one('防御率', (p) => p.isPitcher && p.seasonStats.inningsPitched >= qOuts && qOuts > 0, (s) => s.era, (s) => s.era.toStringAsFixed(2), low: true),
      one('勝利', (p) => p.isPitcher && p.seasonStats.wins > 0, (s) => s.wins, (s) => '${s.wins}勝'),
      one('セーブ', (p) => p.isPitcher && p.seasonStats.saves > 0, (s) => s.saves, (s) => '${s.saves}S'),
      one('奪三振', (p) => p.isPitcher && p.seasonStats.pitcherStrikeouts > 0, (s) => s.pitcherStrikeouts, (s) => '${s.pitcherStrikeouts}'),
    ].where((x) => x.isNotEmpty).toList();
  }

  /// リーグのシーズンが終わった次の日：順位・優勝を記録し、選手の今季成績を来歴の行にして、成績を0に戻す
  static void closeSeason(OtherWorld w, OLeague lg, int year) {
    final ts = w.teamsOf(lg.id);
    if (ts.every((t) => t.w + t.l + t.d == 0)) return;
    for (var div = 0; div < lg.divisions.length; div++) {
      final dt = ts.where((t) => t.division == div).toList()..sort((a, b) => b.pct.compareTo(a.pct));
      for (var i = 0; i < dt.length; i++) {
        final t = dt[i];
        t.history.insert(0, '$year　${lg.divisions[div]}${i + 1}位　${t.w}勝${t.l}敗${t.d > 0 ? '${t.d}分' : ''}');
        if (t.history.length > 10) t.history.removeLast();
      }
    }
    final champ = (List.of(ts)..sort((a, b) => b.pct.compareTo(a.pct))).first;
    // 年ごとの記録：順位表とタイトル（上位3人）
    final st = <String>[];
    for (var div = 0; div < lg.divisions.length; div++) {
      final dt = ts.where((t) => t.division == div).toList()..sort((a, b) => b.pct.compareTo(a.pct));
      if (lg.divisions[div].isNotEmpty) st.add('【${lg.divisions[div]}】');
      for (var i = 0; i < dt.length; i++) {
        final t = dt[i];
        st.add('${i + 1}位　${t.name}　${t.w}勝${t.l}敗${t.d > 0 ? '${t.d}分' : ''}　勝率${t.pct.toStringAsFixed(3).replaceFirst('0.', '.')}');
      }
    }
    w.seasons.putIfAbsent(lg.id, () => []).insert(0, {'y': year, 'st': st, 'ld': leaderLines(ts)});
    if (w.seasons[lg.id]!.length > 60) w.seasons[lg.id]!.removeLast();
    w.champions.insert(0, '$year　${lg.name}　${champ.name}（${champ.w}勝${champ.l}敗）');
    if (w.champions.length > 300) w.champions.removeLast();
    for (final t in ts) {
      for (final p in t.players) {
        final s = p.seasonStats;
        if (s.games > 0) {
          p.abroad.insert(0, recordLine(p, lg, t, year));
          p.abroadStats.insert(0, PlayerStats.fromJson(s.toJson()));
        }
        if (p.abroad.length > 12) p.abroad.removeLast();
        if (p.abroadStats.length > 12) p.abroadStats.removeLast();
        p.seasonStats = PlayerStats(); // 通算（NPB の1軍）には足さない。他リーグの成績は来歴の行に残る
      }
      t.w = 0;
      t.l = 0;
      t.d = 0;
    }
  }

  static String _f3(double v) => v.toStringAsFixed(3).replaceFirst(RegExp(r'^0'), '');

  /// 来歴の1行（ForeignEngine と同じ形「2026　3A　120試合 打率.280 15本 60打点 OPS.800」）。球団名を足す
  static String recordLine(Player p, OLeague lg, OTeam t, int year) {
    final s = p.seasonStats;
    if (p.isPitcher) {
      final ip = s.inningsPitched;
      final era = ip == 0 ? 0.0 : s.earnedRuns * 27 / ip;
      return '$year　${lg.name}・${t.short}　${s.pitchApps}試合 ${s.wins}勝${s.losses}敗${s.saves > 0 ? '${s.saves} S' : ''} 防御率${era.toStringAsFixed(2)} ${ip ~/ 3}${ip % 3 == 0 ? '' : '.${ip % 3}'}回 ${s.pitcherStrikeouts}奪三振';
    }
    final pa = s.atBats + s.walks + s.sacFlies;
    final obp = pa == 0 ? 0.0 : (s.hits + s.walks) / pa;
    final slg = s.atBats == 0 ? 0.0 : s.totalBases / s.atBats;
    return '$year　${lg.name}・${t.short}　${s.games}試合 打率${s.atBats == 0 ? '-' : _f3(s.battingAverage)} ${s.homeRuns}本 ${s.rbi}打点 OPS${_f3(obp + slg)}';
  }

  /// 1月1日：年を取り、力が変わり（若手は伸び、ベテランは落ちる）、引退・昇格と降格・新しい選手の補充
  static List<String> newYear(OtherWorld w, int year, Random r) {
    final notes = <String>[];
    for (final t in w.teams) {
      final gm = growMult(t.leagueId);
      for (final p in t.players) {
      p.age++;
      p.proYears++;
      var grow = p.age <= 24 ? 2.5 + (p.talent - 50) * 0.06 : (p.age <= 28 ? 1.0 + (p.talent - 50) * 0.03 : (p.age <= 31 ? 0.0 : -(p.age - 31) * 1.2));
      if (grow > 0) grow *= gm; // リーグで伸びやすさが違う
      _shift(p, grow + _g(r) * 1.5);
      }
    }
    // 引退：年齢と力。独立リーグは若くてもやめていく
    for (final t in w.teams) {
      final lg = leagues[t.leagueId]!;
      t.players.removeWhere((p) {
        final old = p.age > lg.ageHi + 2 || (p.age >= 34 && p.ovr < lg.mean - 6);
        final indy = (lg.group == '米独立' || lg.group == '日本独立') && p.age >= 27 && r.nextDouble() < 0.18;
        final gone = old || indy || r.nextDouble() < 0.04;
        if (gone && w.fromNpb.containsKey(p.id)) notes.add('${p.registeredName}（元NPB）が${t.name}を最後に引退');
        return gone;
      });
    }
    // MLB の球団ごとに、1A→2A→3A→MLB の昇格・降格（力の順に）
    for (final mlb in w.teamsOf('MLB')) {
      final chain = [mlb, ...['AAA', 'AA', 'A'].map((lg) => w.teams.firstWhere((t) => t.leagueId == lg && t.org == mlb.id))];
      for (final pitcher in [true, false]) {
        final pool = [for (final t in chain) ...t.players.where((p) => p.isPitcher == pitcher)];
        for (final t in chain) {
          t.players.removeWhere((p) => p.isPitcher == pitcher);
        }
        pool.sort((a, b) => b.ovr.compareTo(a.ovr));
        // 若い選手は下から（同じ力なら若手は下のレベルで育てる）
        var i = 0;
        for (final t in chain) {
          for (var k = 0; k < 13 && i < pool.length; k++) {
            t.players.add(pool[i++]);
          }
        }
      }
    }
    // 足りない分を補充（1A は若い新人、ほかはそのリーグの力で）
    for (final t in w.teams) {
      fillRoster(t, year, r);
    }
    return notes;
  }
}
