import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// AI 寸評：PC の中継サーバー（server/server.js）経由で Claude（Haiku 5.5）に文章を書かせる。
///  使えるのは Android 版（S25）だけ。iPhone（Web）版や、PC につながらないときは、これまでの自動作文をそのまま出す。
///  書いた文章は端末に保存し（キャッシュ）、同じ内容なら作り直さない。
///  画面に同時に出た依頼は、少し待ってから1回の呼び出しにまとめる。

/// 1件の依頼
class AiItem {
  final String key; // キャッシュの鍵（内容が変わったら変える）
  final String kind; // player / draft / foreign / trade / game
  final String facts; // AI に渡す事実（画面に出ている情報だけ）
  final Map<String, dynamic>? features; // 文章と組にして貯める元データ（試合展開・選手の能力や成績）
  const AiItem(this.key, this.kind, this.facts, {this.features});
}

class AiSettings {
  bool enabled;
  String url;
  String token;
  String model;
  AiSettings({this.enabled = false, this.url = '', this.token = '', this.model = 'claude-haiku-5-5'});
}

class AiWriter extends ChangeNotifier {
  AiWriter._();
  static final AiWriter instance = AiWriter._();

  /// AI 連動は 2026-10-26 にやめた（開発者版もデバッグ版と同じ。自動作文だけを使う）
  static bool get platformOk => false;

  AiSettings settings = AiSettings();
  final Map<String, String> _cache = {};
  final List<String> _order = []; // 古い順（多くなったら古いものから消す）
  static const _maxCache = 1500;
  bool _loaded = false;
  String lastError = '';
  DateTime? _backoffUntil; // つながらなかったら少し待ってから試す
  int usedCalls = 0;

  bool get active => platformOk && settings.enabled && settings.url.isNotEmpty && settings.token.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (!platformOk) {
      // 以前の開発者版に残った AI の設定（接続先・トークン）と、AI が書いた文章の保存分を消す
      try {
        final sp = await SharedPreferences.getInstance();
        for (final k in sp.getKeys().where((k) => k.startsWith('ai_')).toList()) {
          await sp.remove(k);
        }
      } catch (_) {}
      return;
    }
    try {
      final sp = await SharedPreferences.getInstance();
      settings = AiSettings(
        enabled: sp.getBool('ai_enabled') ?? false,
        url: sp.getString('ai_url') ?? '',
        token: sp.getString('ai_token') ?? '',
        model: sp.getString('ai_model') ?? 'claude-haiku-5-5',
      );
      final pend = sp.getString('ai_corpus_pending_v3');
      if (pend != null) _corpus.addAll([for (final e in jsonDecode(pend) as List) Map<String, dynamic>.from(e as Map)]);
      final raw = sp.getString('ai_cache_v2');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          final k = e[0] as String;
          _cache[k] = e[1] as String;
          _order.add(k);
        }
      }
    } catch (e) {
      debugPrint('AI LOAD ERROR: $e');
    }
    notifyListeners();
  }

  Future<void> saveSettings(AiSettings s) async {
    settings = s;
    settings.url = settings.url.trim().replaceAll(RegExp(r'/+$'), '');
    settings.token = settings.token.trim();
    _backoffUntil = null;
    lastError = '';
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('ai_enabled', settings.enabled);
    await sp.setString('ai_url', settings.url);
    await sp.setString('ai_token', settings.token);
    await sp.setString('ai_model', settings.model);
    notifyListeners();
  }

  Timer? _saveTimer;
  void _persist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('ai_cache_v2', jsonEncode([for (final k in _order) [k, _cache[k]]]));
    });
  }

  Future<void> clearCache() async {
    _cache.clear();
    _order.clear();
    final sp = await SharedPreferences.getInstance();
    await sp.remove('ai_cache_v2');
    notifyListeners();
  }

  int get cacheCount => _cache.length;
  String? cached(String key) => platformOk ? _cache[key] : null;

  void _put(String key, String text) {
    if (!_cache.containsKey(key)) _order.add(key);
    _cache[key] = text;
    while (_order.length > _maxCache) {
      _cache.remove(_order.removeAt(0));
    }
    _persist();
  }

  // ---- 依頼をまとめる ----
  final Map<String, Completer<String?>> _waiting = {};
  final List<AiItem> _pending = [];
  Timer? _batchTimer;

  /// 文章を頼む（キャッシュがあればすぐ返す。使えないときは null）
  Future<String?> write(AiItem item) {
    final c = _cache[item.key];
    if (c != null) return Future.value(c);
    if (!active) return Future.value(null);
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) return Future.value(null);
    final w = _waiting[item.key];
    if (w != null) return w.future;
    final comp = Completer<String?>();
    _waiting[item.key] = comp;
    _pending.add(item);
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 400), _flush);
    return comp.future;
  }

  void _flush() {
    // 種類ごとに、6件ずつまとめて1回で頼む
    final byKind = <String, List<AiItem>>{};
    for (final it in _pending) {
      byKind.putIfAbsent(it.kind, () => []).add(it);
    }
    _pending.clear();
    for (final list in byKind.values) {
      for (var i = 0; i < list.length; i += 6) {
        _run(list.sublist(i, i + 6 > list.length ? list.length : i + 6));
      }
    }
  }

  Future<void> _run(List<AiItem> items) async {
    Map<String, String> got = {};
    try {
      final text = await _call(AiPrompts.build(items), AiPrompts.system, label: '${AiPrompts.kindLabel(items.first.kind)}×${items.length}');
      got = AiPrompts.parse(text, items);
      usedCalls++;
      lastError = '';
    } catch (e) {
      lastError = e.toString();
      _backoffUntil = DateTime.now().add(const Duration(seconds: 60));
      debugPrint('AI ERROR: $e');
    }
    final now = DateTime.now().toIso8601String();
    for (final it in items) {
      final t = got[it.key];
      if (t != null && t.isNotEmpty) {
        _put(it.key, t);
        _corpus.add({'key': it.key, 'kind': it.kind, 'facts': it.facts, 'features': it.features, 'text': t, 'model': settings.model, 'at': now, 'style': AiPrompts.styleVersion});
      }
      _waiting.remove(it.key)?.complete(t);
    }
    if (got.isNotEmpty) _sendCorpus();
    notifyListeners();
  }

  // ---- 文章と元データを PC に貯める（将来 AI なしで寸評を書くための材料） ----
  final List<Map<String, dynamic>> _corpus = []; // まだ PC に送れていない分（端末にも保存）
  bool _sending = false;
  int corpusSent = 0;
  int get corpusPending => _corpus.length;

  Future<void> _sendCorpus() async {
    if (_sending || _corpus.isEmpty || !active) {
      _persistCorpus();
      return;
    }
    _sending = true;
    final batch = List<Map<String, dynamic>>.of(_corpus.take(50));
    try {
      final r = await http.post(Uri.parse('${settings.url}/corpus'), headers: _headers, body: jsonEncode({'entries': batch})).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        _corpus.removeRange(0, batch.length);
        corpusSent += batch.length;
      }
    } catch (e) {
      debugPrint('CORPUS SEND ERROR: $e');
    }
    _sending = false;
    _persistCorpus();
    if (_corpus.isNotEmpty && corpusSent > 0 && batch.length == 50) _sendCorpus();
  }

  void _persistCorpus() {
    SharedPreferences.getInstance().then((sp) => sp.setString('ai_corpus_pending_v3', jsonEncode(_corpus)));
  }

  Map<String, String> get _headers => {'x-token': settings.token, 'content-type': 'application/json'};

  /// 接続テスト（成功なら null、失敗なら理由）
  Future<String?> test() async {
    try {
      final r = await http.get(Uri.parse('${settings.url}/health'), headers: _headers).timeout(const Duration(seconds: 5));
      if (r.statusCode == 401) return 'トークンが違います';
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['app'] != 'tab2026') return 'TAB 2026 用のサーバーではありません（npb_pennant_app/server の start_server.bat を起動してください）';
      _backoffUntil = null;
      _sendCorpus();
      return null;
    } catch (_) {
      return 'PCのサーバーに接続できません（URL・同じWi-Fiか・サーバーが起動しているかを確認）';
    }
  }

  Future<String> _call(String prompt, String system, {String label = ''}) async {
    final r = await http
        .post(Uri.parse('${settings.url}/jobs'), headers: _headers, body: jsonEncode({'prompt': prompt, 'system': system, 'model': settings.model, 'label': label}))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 401) throw Exception('トークンが違います');
    final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final id = body['id'] as String?;
    if (id == null) throw Exception(body['error']?.toString() ?? 'HTTP ${r.statusCode}');
    final until = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final g = await http.get(Uri.parse('${settings.url}/jobs/$id'), headers: _headers).timeout(const Duration(seconds: 8));
      final j = jsonDecode(utf8.decode(g.bodyBytes)) as Map<String, dynamic>;
      switch (j['status']) {
        case 'done':
          return (j['text'] as String?) ?? '';
        case 'error':
        case 'missing':
          throw Exception(j['error'] ?? 'エラー');
      }
    }
    throw Exception('時間がかかりすぎました');
  }
}

/// 指示文
class AiPrompts {
  /// 書き方の版（記録に残す。1=最初の版、2=名鑑・新聞短評の書き方、3=選手寸評は骨組みに沿って書く）
  static const styleVersion = 3;

  static const system = 'あなたは日本のプロ野球ゲーム「The Authentic Baseball 2026」の中で、記者・スカウトとして文章を書きます。'
      '登場する球団・選手はすべて架空です。実在の選手名・球団名は出さないでください。'
      '与えられた事実だけを使い、数字や出来事を作らないでください。前置きや挨拶は書かず、指定の形式だけを出力します。'
      '世界観：2026年にプロ野球のリーグが再編され、Aリーグ・Bリーグの新しい体制になった。2026年がその最初のシーズン。'
      '指示の中の「例」に出てくる球団名・選手名・数字は文体の見本なので、文章には使わない。'
      '数字に合った評価をする（失点や自責が多い投手を「安定」「好投」と書かない、打率が低い打者を「好調」と書かないなど）。';

  static String kindLabel(String k) => const {'player': '選手寸評', 'draft': 'ドラフト寸評', 'foreign': '外国人寸評', 'trade': 'トレード推薦', 'game': '試合寸評', 'pregame': '試合前の見どころ'}[k] ?? k;

  static const _howTo = {
    'player': '選手名鑑の紹介文を書きます。160〜240字の1段落。各選手の「骨組み」の【】の項目を、その順番どおりに、名鑑の文章としてなめらかにつなげます（【】の見出しは書かない）。'
        '骨組みに無い事実・役割・成績・出来事・数字は足さない。役割（先発・中継ぎ・抑えなど）は骨組みの言葉どおりに書く。【締め】は指示どおりの方向で、期待を1文で書く。'
        '例：「昨季は後半戦に度重なる故障があったものの、4年連続で規定打席に到達。打率.277の成績を残し、2度のサヨナラ打もマークした。股関節の手術を経て臨む今季は状態をいち早く整え、チームを引っ張りたい。」'
        '選手名は書き出さず、文末は「〜した」「〜だ」「〜したい」の名鑑の口調。',
    'draft': 'ドラフト候補へのスカウトの寸評を書きます。80〜150字。見立ては幅のある推定値なので「〜と見る」「〜の可能性」のように断定を避け、どんな選手に育ちそうか、指名する価値をスカウトの口調で述べてください。',
    'foreign': '新外国人候補へのスカウトの寸評を書きます。100〜160字。見立ては幅のある推定値です。海外での成績と環境適応力の見立てに触れ、日本の野球で通用しそうか、どんな起用が合うかをスカウトの口調で述べてください。',
    'trade': '自球団の監督に向けた、スカウトのトレード推薦コメントを書きます。100〜160字。相手球団で出番が少ない理由、自球団の補強ポイントにどう合うか、獲る価値をスカウトの口調で述べてください。',
    'game': '試合寸評を書きます。新聞の試合短評のように、150〜230字の1段落。見出しは付けない。'
        '1文目で試合の大勢（どちらが勝ったか。シリーズなら「王手をかけた」「勝ち抜けを決めた」、順位争いなら首位浮上など）を伝え、次に得点経過を回の順に、選手名とともに簡潔に書く。最後に「投げては、先発・○○が7回1失点の力投。」のように勝った側の投手、「敗れた○○は、〜」で負けた側の惜しかった場面や反撃を書く。'
        '例：「DeNAがファイナルステージ進出に王手をかけた。DeNAは初回、牧のソロで先制する。直後に同点とされるも、9回表に度会のソロが飛び出し、勝ち越しに成功した。投げては、先発・東が7回1失点の力投。敗れた巨人は、最終回に一打同点の好機をつくるも、あと1本が出なかった。」'
        '選手は姓だけで書く（外国人は登録名）。',
    'pregame': '試合前の「見どころ」を書きます。200〜300字の1段落。シリーズや順位の状況があれば冒頭で触れ、まず一方の先発投手の直近の投球内容を数字で紹介し「今日も〜できるか」と期待を書く。次に「対する○○の注目は△△。」として相手の注目打者を、この球場での成績・前の試合・今日の先発との対戦などの数字で紹介し、「〜したい」で締める。'
        '例：「後がなくなった巨人は竹丸が先発マウンドに上がる。9月以降は4試合に先発し、計23回2/3を投げて1失点32奪三振と力強い投球を見せていた。今日もスコアボードにゼロを並べ、試合の流れを引き寄せられるか。対するDeNAの注目は牧。東京ドームでは今季のレギュラーシーズンで打率.333をマークしており、昨日は初回に先制ソロが飛び出した。この試合でも敵地で快音を響かせ、チームを3年連続となるファイナルステージ進出に導きたい。」'
        '選手は姓だけで書く（外国人は登録名）。与えられていない数字は書かない。',
  };

  static String build(List<AiItem> items) {
    final b = StringBuffer();
    b.writeln(_howTo[items.first.kind] ?? '');
    b.writeln();
    b.writeln('次の${items.length}件について、それぞれ書いてください。出力の形式は、件ごとに「===ID===」の行（IDは下の各件のID）を置き、その次の行から文章を書きます。ほかには何も書かないでください。');
    for (var i = 0; i < items.length; i++) {
      b.writeln();
      b.writeln('---- ID: ${i + 1} ----');
      b.writeln(items[i].facts.trim());
    }
    return b.toString();
  }

  static Map<String, String> parse(String text, List<AiItem> items) {
    // 区切りの書き方の揺れに対応：「===1===」「===ID: 1===」「===ID===」の次の行に「1」、「=====」だけの行は捨てる
    final out = <String, String>{};
    final marker = RegExp(r'^\s*=+\s*(?:ID)?\s*[:：]?\s*(\d*)\s*=*\s*$');
    final lines = text.split('\n');
    int? cur;
    var auto = 0; // 番号の無い区切りは順番に数える
    final buf = <int, List<String>>{};
    for (var i = 0; i < lines.length; i++) {
      final m = marker.firstMatch(lines[i]);
      if (m != null && lines[i].contains('=')) {
        var n = int.tryParse(m.group(1) ?? '');
        if (n == null && lines[i].contains('ID') && i + 1 < lines.length && RegExp(r'^\s*\d+\s*$').hasMatch(lines[i + 1])) {
          n = int.parse(lines[i + 1].trim());
          i++;
        }
        if (n == null && lines[i].contains('ID')) n = auto + 1;
        if (n != null) {
          cur = n;
          auto = n;
        }
        continue; // 「=====」だけの行は飛ばす
      }
      if (cur != null) buf.putIfAbsent(cur, () => []).add(lines[i]);
    }
    buf.forEach((n, ls) {
      final body = ls.join('\n').trim();
      if (n >= 1 && n <= items.length && body.isNotEmpty) out[items[n - 1].key] = body;
    });
    // 1件だけで区切りが無いときは、全体をその文章とみなす
    if (out.isEmpty && items.length == 1) {
      final body = lines.where((l) => !marker.hasMatch(l) || !l.contains('=')).join('\n').trim();
      if (body.isNotEmpty) out[items.first.key] = body;
    }
    return out;
  }
}
