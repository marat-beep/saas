/* 3DMP Service · Пульт оператора — service worker (оболочка PWA) */
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });
self.addEventListener('fetch', function (e) {
  // сеть в приоритете; офлайн-оболочка подключается позже
  e.respondWith(fetch(e.request).catch(function () { return caches.match(e.request); }));
});
