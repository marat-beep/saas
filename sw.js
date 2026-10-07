/* ============================================================
   3DMP Service · sw.js — service worker (PWA, консервативный).
   Стратегия: network-first (данные всегда свежие), офлайн-фолбэк только
   для навигаций (index.html). Ничего агрессивно не кэшируем, чтобы не
   мешать деплою на FTP. Требуется HTTPS.
   ============================================================ */
'use strict';

var CACHE = '3dmp-offline-v1';
var OFFLINE = './index.html';

self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) { return c.add(OFFLINE).catch(function () {}); }));
  self.skipWaiting();
});

self.addEventListener('activate', function (e) {
  e.waitUntil((function () {
    return caches.keys().then(function (keys) {
      return Promise.all(keys.map(function (k) { return k === CACHE ? null : caches.delete(k); }));
    }).then(function () { return self.clients.claim(); });
  })());
});

self.addEventListener('fetch', function (e) {
  var req = e.request;
  if (req.method !== 'GET') return;
  var url;
  try { url = new URL(req.url); } catch (err) { return; }
  if (url.origin !== self.location.origin) return;

  e.respondWith(
    fetch(req).catch(function () {
      if (req.mode === 'navigate') return caches.match(OFFLINE);
      return caches.match(req);
    })
  );
});
