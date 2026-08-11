// Service worker mínimo: solo existe para que la app cumpla el requisito técnico
// de "instalable" (PWA/APK). No guarda nada en caché a propósito, y además
// fuerza a que cada petición (incluida la página principal) vaya siempre
// directo a la red, sin usar la caché del navegador/WebView del APK.
self.addEventListener('install', (event) => {
  self.skipWaiting();
});
self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});
self.addEventListener('fetch', (event) => {
  event.respondWith(
    fetch(event.request, { cache: 'no-store' }).catch(() => fetch(event.request))
  );
});
