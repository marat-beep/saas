/* ============================================================
   3DMP Service · sw.js v2 — service worker (PWA, консервативный).
   Стратегия: network-first (данные всегда свежие), офлайн-фолбэк для
   навигаций и статики. Не мешает деплою на FTP (кэш — только фолбэк).
   Требуется HTTPS.
   ============================================================ */
'use strict';

var CACHE = '3dmp-offline-v2';
var OFFLINE = './index.html';
var SHELL = [
  './index.html',
  './manifest.webmanifest',
  './assets/css/app.css',
  './assets/js/config.js',
  './assets/js/supabase-client.js',
  './assets/js/ui.js',
  './assets/js/auth.js',
  './assets/js/offline-queue.js'
];

self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) {
    return Promise.all(SHELL.map(function (u) { return c.add(u).catch(function () {}); }));
  }));
  self.skipWaiting();
});

self.addEventListener('activate', function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.map(function (k) { return k === CACHE ? null : caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

self.addEventListener('fetch', function (e) {
  var req = e.request;
  if (req.method !== 'GET') return;
  var url;
  try { url = new URL(req.url); } catch (err) { return; }
  if (url.origin !== self.location.origin) return;

  e.respondWith(
    fetch(req).then(function (resp) {
      // кэшируем статику и навигации для офлайн-фолбэка
      if (resp && resp.ok && (req.mode === 'navigate' || /\.(?:css|js|svg|png|webmanifest)$/.test(url.pathname))) {
        var copy = resp.clone();
        caches.open(CACHE).then(function (c) { c.put(req, copy).catch(function () {}); });
      }
      return resp;
    }).catch(function () {
      if (req.mode === 'navigate') return caches.match(OFFLINE).then(function (r) { return r || caches.match(req); });
      return caches.match(req);
    })
  );
});
