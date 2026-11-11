{{flutter_js}}
{{flutter_build_config}}

const flutterConfig = {
  wasmAllowList: {
    blink: true,
    webkit: true,
    gecko: true,
  },
  suppressMultithreadingWarning: true,
};

_flutter.loader.load({
  config: flutterConfig,
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine(flutterConfig);
    const loading = document.getElementById('loading');
    if (loading) loading.remove();
    await appRunner.runApp();
  }
});
