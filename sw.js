// Service worker mínimo: solo existe para que la app cumpla el requisito técnico
// de "instalable" (PWA). No guarda nada en caché porque la app necesita
// internet para funcionar (habla con la base de datos en tiempo real).
self.addEventListener('install', (event) => {
  self.skipWaiting();
});
self.addEventListener('activate', (event) => {
  self.clients.claim();
});
self.addEventListener('fetch', (event) => {
  // Siempre va directo a la red (sin caché), la app necesita datos frescos.
  event.respondWith(fetch(event.request));
});
