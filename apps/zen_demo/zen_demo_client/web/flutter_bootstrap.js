{{flutter_js}}
{{flutter_build_config}}

// The default bootstrap, plus the one thing it lacks: the jZen loading screen that
// flutter_native_splash writes into index.html stays on the page unless something removes it, so
// it is removed once the first frame has been drawn.
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    removeSplashFromWeb();
  },
});
