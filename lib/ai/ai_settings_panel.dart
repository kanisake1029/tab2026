import 'package:flutter/material.dart';
import 'ai_writer.dart';

/// 設定 → AI寸評（PC経由）
class AiSettingsPanel extends StatefulWidget {
  const AiSettingsPanel({super.key});

  @override
  State<AiSettingsPanel> createState() => _AiSettingsPanelState();
}

class _AiSettingsPanelState extends State<AiSettingsPanel> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _model = TextEditingController();
  bool _enabled = false;
  bool _ready = false;
  String _msg = '';
  bool _testing = false;

  AiWriter get w => AiWriter.instance;

  @override
  void initState() {
    super.initState();
    w.load().then((_) {
      if (!mounted) return;
      setState(() {
        _enabled = w.settings.enabled;
        _url.text = w.settings.url;
        _token.text = w.settings.token;
        _model.text = w.settings.model;
        _ready = true;
      });
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() => w.saveSettings(AiSettings(enabled: _enabled, url: _url.text, token: _token.text, model: _model.text.trim().isEmpty ? 'claude-haiku-5-5' : _model.text.trim()));

  @override
  Widget build(BuildContext context) {
    const sub = TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.6);
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('AI寸評（PC経由・Haiku 5.5）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 6),
      const Text(
        '試合総評・選手詳細の寸評・ドラフト／外国人候補の寸評・トレードのおすすめを、PC の Claude（Haiku 5.5）が書きます。'
        'PC で npb_pennant_app\\server\\start_server.bat を起動し、表示されたサーバーURLとトークンを入れてください。'
        'つながらないときや iPhone（Web）版では、これまでの自動作文を出します。書いた文章はこの端末に保存し、同じ内容なら作り直しません。',
        style: sub,
      ),
      if (!AiWriter.platformOk)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('この機能は S25 の開発者版（TAB 開発者版）だけで使えます。', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
        ),
      const SizedBox(height: 10),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('AI寸評を使う'),
        value: _enabled,
        onChanged: AiWriter.platformOk
            ? (v) async {
                setState(() => _enabled = v);
                await _save();
              }
            : null,
      ),
      TextField(controller: _url, decoration: const InputDecoration(labelText: 'サーバーURL（例 http://192.168.1.10:8788）', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.url, onChanged: (_) => _save()),
      const SizedBox(height: 10),
      TextField(controller: _token, decoration: const InputDecoration(labelText: 'トークン（8桁）', border: OutlineInputBorder(), isDense: true), onChanged: (_) => _save()),
      const SizedBox(height: 10),
      TextField(controller: _model, decoration: const InputDecoration(labelText: 'モデル', border: OutlineInputBorder(), isDense: true), onChanged: (_) => _save()),
      const SizedBox(height: 12),
      Row(children: [
        FilledButton.icon(
          onPressed: _testing
              ? null
              : () async {
                  setState(() {
                    _testing = true;
                    _msg = '';
                  });
                  await _save();
                  final e = await w.test();
                  if (!mounted) return;
                  setState(() {
                    _testing = false;
                    _msg = e ?? 'つながりました';
                  });
                },
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('接続テスト'),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(_msg, style: TextStyle(fontWeight: FontWeight.w700, color: _msg == 'つながりました' ? const Color(0xFF16A34A) : Colors.redAccent))),
      ]),
      const SizedBox(height: 16),
      ListenableBuilder(
        listenable: w,
        builder: (_, __) => Text(
          '保存してある AI の文章：${w.cacheCount}件　この起動中の呼び出し：${w.usedCalls}回\nPC に記録した文章と元データ：この起動中 ${w.corpusSent}件（未送信 ${w.corpusPending}件。PC の server\\data\\corpus に貯まります）${w.lastError.isEmpty ? '' : '\n最後のエラー：${w.lastError}'}',
          style: sub,
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () async {
            await w.clearCache();
            if (mounted) setState(() {});
          },
          child: const Text('保存した AI の文章を消す（次に開いたとき書き直す）'),
        ),
      ),
    ]);
  }
}
