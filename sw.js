// Service worker: cumple el requisito técnico de "instalable" (PWA/APK) y
// además recibe los avisos push. No guarda nada en caché a propósito, y
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

// ---- Avisos push (resultados cargados) ----
self.addEventListener('push', (event) => {
  let datos = {};
  try{ datos = event.data ? event.data.json() : {}; }
  catch(e){ datos = { title:'LotC4Pa', body: event.data ? event.data.text() : '' }; }
  const titulo = datos.title || 'LotC4Pa';
  const opciones = {
    body: datos.body || '',
    icon: 'icons/icon-192.png',
    badge: 'icons/icon-192.png',
    data: { url: datos.url || '/' }
  };
  event.waitUntil(self.registration.showNotification(titulo, opciones));
});
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    clients.matchAll({ type:'window', includeUncontrolled:true }).then((lista) => {
      for(const c of lista){ if('focus' in c) return c.focus(); }
      if(clients.openWindow) return clients.openWindow(url);
    })
  );
});
