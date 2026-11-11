{{flutter_js}}
{{flutter_build_config}}

(function() {
  const startTime = Date.now();
  const statusEl = document.getElementById('loading-status');
  let stepText = '起動準備中';

  // WasmGC 対応チェック
  let supportsWasmGC = false;
  try {
    supportsWasmGC = WebAssembly.validate(new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,95,1,120,0]));
  } catch (_) {}

  const forceJs = new URLSearchParams(location.search).has('js');
  const modeLabel = (!forceJs && supportsWasmGC) ? 'Wasm' : 'JS';

  const timer = setInterval(() => {
    if (!statusEl) return;
    const sec = ((Date.now() - startTime) / 1000).toFixed(1);
    statusEl.textContent = `[${modeLabel}] ${stepText} (${sec}s)`;
  }, 200);

  function setStep(text) {
    stepText = text;
    if (statusEl) {
      const sec = ((Date.now() - startTime) / 1000).toFixed(1);
      statusEl.textContent = `[${modeLabel}] ${stepText} (${sec}s)`;
    }
  }

  // 古い Service Worker がキャッシュを詰まらせるのを防ぐためバックグラウンドで解除
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistrations().then((regs) => {
      for (const r of regs) {
        r.unregister().catch(() => {});
      }
    }).catch(() => {});
  }

  const flutterConfig = {
    wasmAllowList: {
      blink: true,
      webkit: true,
      gecko: true,
      unknown: true,
    },
    suppressMultithreadingWarning: true,
  };
  if (forceJs) {
    flutterConfig.renderer = 'canvaskit';
  }

  setStep('1/3 エンジン読込中...');

  _flutter.loader.load({
    config: flutterConfig,
    onEntrypointLoaded: async function(engineInitializer) {
      setStep('2/3 アプリ初期化中...');
      const appRunner = await engineInitializer.initializeEngine(flutterConfig);
      setStep('3/3 画面構築中...');
      await appRunner.runApp();
      clearInterval(timer);
      const loading = document.getElementById('loading');
      if (loading) loading.remove();
    }
  }).catch((err) => {
    clearInterval(timer);
    if (statusEl) {
      statusEl.style.color = '#F2C230';
      statusEl.textContent = `エラー: ${err}`;
    }
  });
})();
