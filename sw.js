/* ============================================================
   3DMP Service · sw.js v3 — service worker (PWA).
   Стратегии по маршрутам:
     • навигации/HTML — network-first (свежие данные), фолбэк — кэш/OFFLINE;
     • статика (js/css/img/manifest, в т.ч. ?v=N) — stale-while-revalidate
       (мгновенно из кэша, фон обновляет; версии ?v=N исключают устаревание);
     • прочее same-origin GET — network-first с фолбэк-кэшем.
   Не мешает деплою на FTP. Требуется HTTPS.
   ============================================================ */
'use strict';

var CACHE = '3dmp-offline-v3';
var OFFLINE = './index.html';
var SHELL = [
  './index.html',
  './manifest.webmanifest',
  './assets/css/app.css',
  './assets/js/config.js',
  './assets/js/supabase-client.js',
  './assets/js/ui.js',
  './assets/js/auth.js',
  './assets/js/offline-queue.js',
  './assets/js/offline-cache.js'
];
var STATIC_RE = /\.(?:css|js|mjs|svg|png|jpg|jpeg|gif|webp|ico|woff2?|ttf|webmanifest)$/;

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

function put(req, resp) {
  if (resp && resp.ok) { var copy = resp.clone(); caches.open(CACHE).then(function (c) { c.put(req, copy).catch(function () {}); }); }
}

self.addEventListener('fetch', function (e) {
  var req = e.request;
  if (req.method !== 'GET') return;
  var url;
  try { url = new URL(req.url); } catch (err) { return; }
  if (url.origin !== self.location.origin) return;

  var isNav = req.mode === 'navigate';
  var isStatic = STATIC_RE.test(url.pathname) || /[?&]v=\d+/.test(url.search);

  if (isStatic && !isNav) {
    // stale-while-revalidate
    e.respondWith(caches.match(req).then(function (cached) {
      var net = fetch(req).then(function (resp) { put(req, resp); return resp; }).catch(function () { return cached; });
      return cached || net;
    }));
    return;
  }

  // network-first (+ offline fallback)
  e.respondWith(
    fetch(req).then(function (resp) { put(req, resp); return resp; })
      .catch(function () {
        if (isNav) return caches.match(OFFLINE).then(function (r) { return r || caches.match(req); });
        return caches.match(req);
      })
  );
});
