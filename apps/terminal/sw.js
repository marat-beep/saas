/* 3DMP Service · Пульт оператора — service worker v2 (офлайн-оболочка PWA) */
'use strict';
var CACHE = '3dmp-terminal-v2';
var SHELL = [
  './index.html',
  './manifest.webmanifest',
  './terminal.js',
  '../../assets/css/app.css',
  '../../assets/js/config.js',
  '../../assets/js/supabase-client.js',
  '../../assets/js/ui.js',
  '../../assets/js/auth.js',
  '../../assets/js/offline-queue.js',
  '../../assets/js/notify.js',
  '../../assets/js/nav.js'
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
  e.respondWith(
    fetch(req).then(function (resp) {
      if (resp && resp.ok && req.url.indexOf(self.location.origin) === 0) {
        var copy = resp.clone(); caches.open(CACHE).then(function (c) { c.put(req, copy).catch(function () {}); });
      }
      return resp;
    }).catch(function () {
      if (req.mode === 'navigate') return caches.match('./index.html').then(function (r) { return r || caches.match(req); });
      return caches.match(req);
    })
  );
});
