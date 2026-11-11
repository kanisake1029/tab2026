// TAB 2026（野球アプリ）用の AI 寸評サーバー。
// スマホ（S25）から受け取った指示文を `claude -p`（ログイン中のサブスク枠・Haiku 5.5）で処理し、出力をそのまま返す。
// 指示文はアプリが作る。このサーバーは実行するだけ。ツールは使わせない（文章を書くだけ）。
// 依存パッケージなし。起動: node server.js  （または start_server.bat をダブルクリック）

const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { spawn } = require('child_process');

const VERSION = 2;
const PORT = Number(process.env.PORT || 8788);
const CONCURRENCY = Number(process.env.CONCURRENCY || 3);
const DEFAULT_MODEL = process.env.CLAUDE_MODEL || 'claude-haiku-5-5';
const TIMEOUT_MS = 3 * 60 * 1000;
const DATA_DIR = path.join(__dirname, 'data');
const WORK_DIR = path.join(DATA_DIR, 'work'); // claude を動かすフォルダ（中身は空のまま）
const CONFIG_PATH = path.join(DATA_DIR, 'config.json');
// AI が書いた文章と、そのときの元データ（試合展開・選手の能力や成績）を種類ごとに1行1件で貯める。
// 将来、AI なしで寸評を書くための材料にする
const CORPUS_DIR = path.join(DATA_DIR, 'corpus');
const KEEP_JOBS_MS = 30 * 60 * 1000; // 終わったジョブは30分で忘れる

fs.mkdirSync(WORK_DIR, { recursive: true });
fs.mkdirSync(CORPUS_DIR, { recursive: true });

function corpusCounts() {
  const out = {};
  for (const f of fs.readdirSync(CORPUS_DIR)) {
    if (!f.endsWith('.jsonl')) continue;
    out[f.replace('.jsonl', '')] = fs.readFileSync(path.join(CORPUS_DIR, f), 'utf8').split('\n').filter((l) => l.trim()).length;
  }
  return out;
}

// ---- 認証トークン（初回起動時に生成） ----
let config = {};
if (fs.existsSync(CONFIG_PATH)) config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
if (!config.token) {
  config.token = crypto.randomBytes(4).toString('hex'); // 8桁。スマホで手入力しやすい長さ
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
}

// ---- ジョブ（メモリだけ。寸評は短いので、サーバーを止めたらアプリが出し直す） ----
const jobs = new Map(); // id -> { status, prompt, system, model, text, error, usage, doneAt }
const queue = [];
let running = 0;

function safeModel(m) {
  return /^[A-Za-z0-9._-]{1,64}$/.test(m || '') ? m : '';
}

function runJob(id) {
  const job = jobs.get(id);
  if (!job) return;
  job.status = 'running';
  running++;
  const model = safeModel(job.model) || DEFAULT_MODEL;
  const sys = (job.system || 'あなたはプロ野球の記者です。日本語で書きます。').replace(/"/g, '”').replace(/[%^&|<>!`$]/g, '').replace(/[\r\n]+/g, ' ').slice(0, 1500); // shell に渡すので記号は除く
  // 速く・安く：既定のシステムプロンプト・ツール・設定ファイル・MCP を使わない
  const args = ['-p', '--output-format', 'json', '--model', model, '--system-prompt', `"${sys}"`, '--tools', '""', '--strict-mcp-config', '--setting-sources', '""', '--no-session-persistence', '--effort', 'low'];
  // Windows の claude は .cmd/.ps1 なので shell 経由で起動。指示文は stdin で渡す。
  const child = spawn(['claude', ...args].join(' '), { cwd: WORK_DIR, shell: true, windowsHide: true });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (d) => (stdout += d));
  child.stderr.on('data', (d) => (stderr += d));
  child.stdin.end(job.prompt, 'utf8');
  const timer = setTimeout(() => child.kill(), TIMEOUT_MS);
  const started = Date.now();

  child.on('close', (code) => {
    clearTimeout(timer);
    running--;
    try {
      const out = JSON.parse(stdout);
      if (out.is_error) throw new Error(out.result || 'Claude がエラーを返しました');
      job.status = 'done';
      job.text = out.result || '';
      const u = out.usage || {};
      job.usage = { input_tokens: u.input_tokens || 0, output_tokens: u.output_tokens || 0, cache_creation_input_tokens: u.cache_creation_input_tokens || 0 };
    } catch (e) {
      job.status = 'error';
      job.error = `${e.message}${code ? ` (exit ${code})` : ''}${stderr ? '\n' + stderr.slice(-500) : ''}`;
    }
    job.doneAt = Date.now();
    job.prompt = '';
    log(`${job.label || 'job'} -> ${job.status}（${((Date.now() - started) / 1000).toFixed(1)}秒）${job.error ? ': ' + job.error.split('\n')[0] : ''}`);
    pump();
  });
}

function pump() {
  while (running < CONCURRENCY && queue.length) runJob(queue.shift());
  const now = Date.now();
  for (const [id, j] of jobs) if (j.doneAt && now - j.doneAt > KEEP_JOBS_MS) jobs.delete(id);
}

// ---- HTTP ----
function log(msg) {
  console.log(`[${new Date().toLocaleTimeString('ja-JP')}] ${msg}`);
}
function send(res, status, obj) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj));
}
function readBody(req, limit = 2 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        reject(new Error('too large'));
        req.destroy();
      } else chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x');
    if (req.headers['x-token'] !== config.token) return send(res, 401, { error: 'トークンが違います' });

    if (req.method === 'GET' && url.pathname === '/health') {
      return send(res, 200, { ok: true, app: 'tab2026', version: VERSION, model: DEFAULT_MODEL, queued: queue.length, running, corpus: corpusCounts() });
    }

    // 文章と元データを貯める: { entries: [{ key, kind, facts, features, text, model, at }] }
    if (req.method === 'POST' && url.pathname === '/corpus') {
      const body = JSON.parse(await readBody(req));
      const entries = Array.isArray(body.entries) ? body.entries : [];
      const byKind = {};
      for (const e of entries) {
        const kind = /^[a-z]{1,20}$/.test(e.kind || '') ? e.kind : 'other';
        (byKind[kind] = byKind[kind] || []).push(JSON.stringify({ ...e, savedAt: new Date().toISOString() }));
      }
      for (const [kind, lines] of Object.entries(byKind)) fs.appendFileSync(path.join(CORPUS_DIR, kind + '.jsonl'), lines.join('\n') + '\n', 'utf8');
      log('記録 ' + entries.length + '件（' + Object.entries(byKind).map(([k, v]) => k + ' ' + v.length).join('、') + '）');
      return send(res, 200, { ok: true, saved: entries.length });
    }

    // 新規ジョブ: { prompt, system?, model?, label? }
    if (req.method === 'POST' && url.pathname === '/jobs') {
      const body = JSON.parse(await readBody(req));
      if (typeof body.prompt !== 'string' || !body.prompt) return send(res, 400, { error: '指示文がありません' });
      const id = crypto.randomUUID();
      jobs.set(id, { status: 'queued', prompt: body.prompt, system: body.system || '', model: body.model || '', label: String(body.label || '').slice(0, 40) });
      queue.push(id);
      log(`${body.label || 'job'} 受付（待ち${queue.length}件）`);
      pump();
      return send(res, 200, { id, status: 'queued' });
    }

    const m = url.pathname.match(/^\/jobs\/([0-9a-f-]{36})$/);
    if (req.method === 'GET' && m) {
      const j = jobs.get(m[1]);
      if (!j) return send(res, 404, { status: 'missing', error: 'ジョブが見つかりません（サーバーを再起動しましたか？）' });
      return send(res, 200, { id: m[1], status: j.status, text: j.text ?? null, usage: j.usage ?? null, error: j.error || null });
    }

    send(res, 404, { error: 'not found' });
  } catch (e) {
    send(res, 500, { error: e.message });
  }
});

server.listen(PORT, '0.0.0.0', () => {
  const addrs = Object.values(os.networkInterfaces())
    .flat()
    .filter((a) => a && a.family === 'IPv4' && !a.internal)
    .map((a) => `http://${a.address}:${PORT}`);
  console.log('==============================================');
  console.log(' TAB 2026 AI寸評サーバー 起動中（' + DEFAULT_MODEL + '）');
  console.log(' アプリの 設定 → AI寸評（PC経由） に次を入力してください:');
  addrs.forEach((a) => console.log(`   サーバーURL: ${a}`));
  console.log(`   トークン   : ${config.token}`);
  console.log(' USBでつないでいるなら adb reverse tcp:' + PORT + ' tcp:' + PORT + ' のあと');
  console.log(`   サーバーURL: http://127.0.0.1:${PORT} でもつながります`);
  console.log(' (このウィンドウを閉じると停止します)');
  console.log('==============================================');
});
