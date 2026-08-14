// Service worker mínimo: solo existe para que la app cumpla el requisito técnico
// de "instalable" (PWA/APK). No guarda nada en caché a propósito, y además
// fuerza a que cada petición (incluida la página principal) vaya siempre
// directo a la red, sin usar la caché del navegador/WebView del APK.
self.addEventListener('install', (event) => {
  self.skipWaiting();
});
self.addEventListener('activate', (event) => {
  // Si el celular tenía una versión más vieja de este archivo que sí guardaba
  // cosas en caché (de antes de dejarlo "sin caché a propósito"), esa caché
  // vieja se queda guardada en el teléfono hasta que algo la borre. Este
  // bloque la borra automáticamente apenas se activa esta versión nueva, así
  // ningún celular queda pegado mostrando una versión antigua de la app.
  event.waitUntil(
    Promise.all([
      caches.keys().then((nombres) => Promise.all(nombres.map((n) => caches.delete(n)))),
      self.clients.claim()
    ])
  );
});
self.addEventListener('fetch', (event) => {
  event.respondWith(
    fetch(event.request, { cache: 'no-store' }).catch(() => fetch(event.request))
  );
});

