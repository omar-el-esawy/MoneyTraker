{{flutter_js}}
{{flutter_build_config}}

(async () => {
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map((registration) => registration.unregister()));
  }

  if ('caches' in window) {
    const names = await caches.keys();
    await Promise.all(
      names
        .filter((name) => name.startsWith('flutter-'))
        .map((name) => caches.delete(name)),
    );
  }

  await _flutter.loader.load();
})();
