/* ============================================================
   3DMP Service · offline-cache.js (window.AppOfflineCache) — W36
   IndexedDB-кэш результатов чтения (справочники, рабочие списки) для офлайна.
   cached(key, loader, ttl): network-first, при отсутствии сети — кэш (любой давности).
   put/get/getMeta/clear. Фолбэк — localStorage.
   ============================================================ */
(function (g) {
  'use strict';
  var DB = '3dmp-cache', STORE = 'kv', VERSION = 1, LS = '3dmp:cache:';
  var dbp = null;
  var mem = {};

  function idbOK() { try { return !!g.indexedDB; } catch (e) { return false; } }
  function open() {
    if (dbp) return dbp;
    dbp = new Promise(function (res, rej) {
      var rq = g.indexedDB.open(DB, VERSION);
      rq.onupgradeneeded = function () { var db = rq.result; if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE, { keyPath: 'key' }); };
      rq.onsuccess = function () { res(rq.result); }; rq.onerror = function () { rej(rq.error); };
    });
    return dbp;
  }
  function lsGet(key) { try { var v = localStorage.getItem(LS + key); return v ? JSON.parse(v) : null; } catch (e) { return null; } }
  function lsPut(rec) { try { localStorage.setItem(LS + rec.key, JSON.stringify(rec)); } catch (e) {} }
  function lsDel(key) { try { localStorage.removeItem(LS + key); } catch (e) {} }

  function put(key, data) {
    var rec = { key: key, data: data, ts: Date.now() };
    mem[key] = rec;
    if (!idbOK()) { lsPut(rec); return Promise.resolve(); }
    return open().then(function (db) { return new Promise(function (res) {
      var tx = db.transaction(STORE, 'readwrite'); tx.objectStore(STORE).put(rec); tx.oncomplete = function () { res(); };
    }); }).catch(function () { lsPut(rec); });
  }
  function get(key) {
    if (mem[key]) return Promise.resolve(mem[key]);
    if (!idbOK()) { var r = lsGet(key); if (r) mem[key] = r; return Promise.resolve(r); }
    return open().then(function (db) { return new Promise(function (res) {
      var tx = db.transaction(STORE, 'readonly'), rq = tx.objectStore(STORE).get(key);
      rq.onsuccess = function () { var r = rq.result || lsGet(key); if (r) mem[key] = r; res(r); }; rq.onerror = function () { res(lsGet(key)); };
    }); }).catch(function () { return lsGet(key); });
  }

  /* network-first с офлайн-фолбэком на кэш */
  function cached(key, loader, ttlMs) {
    return Promise.resolve().then(loader).then(function (data) {
      put(key, data); return data;
    }).catch(function (err) {
      return get(key).then(function (rec) {
        if (rec && rec.data !== undefined) return rec.data;   // офлайн: отдаём кэш
        throw err;
      });
    });
  }
  function clear() {
    mem = {};
    try { Object.keys(localStorage).forEach(function (k) { if (k.indexOf(LS) === 0) localStorage.removeItem(k); }); } catch (e) {}
    if (!idbOK()) return Promise.resolve();
    return open().then(function (db) { return new Promise(function (res) { var tx = db.transaction(STORE, 'readwrite'); tx.objectStore(STORE).clear(); tx.oncomplete = function () { res(); }; }); }).catch(function () {});
  }

  g.AppOfflineCache = { cached: cached, put: put, get: get, clear: clear };
})(window);
