/* ============================================================
   3DMP Service · offline-queue.js (window.AppOffline) — PWA офлайн-очередь
   Копит RPC-действия (терминал/ОТК) при отсутствии сети в IndexedDB
   (фолбэк — localStorage) и повторяет их при восстановлении связи.
   Факт синхронизации пишется в журнал app_offline_sync (0120).
   ============================================================ */
(function (g) {
  'use strict';
  var DB = '3dmp-offline', STORE = 'queue', VERSION = 1, LS = '3dmp:offlineq', CID = '3dmp:clientId';
  var APPLIED = '3dmp:offlineq:applied', SEQ = '3dmp:offlineq:seq';
  var dbp = null;
  function appliedRead() { try { return JSON.parse(localStorage.getItem(APPLIED) || '[]'); } catch (e) { return []; } }
  function appliedHas(idem) { return idem && appliedRead().indexOf(idem) >= 0; }
  function appliedAdd(idem) { if (!idem) return; var a = appliedRead(); if (a.indexOf(idem) < 0) { a.push(idem); if (a.length > 500) a = a.slice(-500); try { localStorage.setItem(APPLIED, JSON.stringify(a)); } catch (e) {} } }
  function nextSeq() { var n = 0; try { n = parseInt(localStorage.getItem(SEQ) || '0', 10) || 0; } catch (e) {} n++; try { localStorage.setItem(SEQ, String(n)); } catch (e) {} return n; }

  function idbOK() { try { return !!g.indexedDB; } catch (e) { return false; } }
  function open() {
    if (dbp) return dbp;
    dbp = new Promise(function (res, rej) {
      var rq = g.indexedDB.open(DB, VERSION);
      rq.onupgradeneeded = function () { var db = rq.result; if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE, { keyPath: 'id' }); };
      rq.onsuccess = function () { res(rq.result); };
      rq.onerror = function () { rej(rq.error); };
    });
    return dbp;
  }
  function lsRead() { try { return JSON.parse(localStorage.getItem(LS) || '[]'); } catch (e) { return []; } }
  function lsWrite(a) { try { localStorage.setItem(LS, JSON.stringify(a)); } catch (e) {} }
  function genId() { return 'q' + Date.now() + '-' + Math.random().toString(36).slice(2, 8); }

  function add(item) {
    item = item || {}; item.id = item.id || genId(); item.ts = item.ts || Date.now();
    item.idem = item.idem || (clientId() + '#' + nextSeq()); // идемпотентность: ключ операции
    if (!idbOK()) { var a = lsRead(); a.push(item); lsWrite(a); updateBadge(); return Promise.resolve(); }
    return open().then(function (db) {
      return new Promise(function (res) {
        var tx = db.transaction(STORE, 'readwrite'); tx.objectStore(STORE).put(item);
        tx.oncomplete = function () { updateBadge(); res(); };
      });
    }).catch(function () { var a = lsRead(); a.push(item); lsWrite(a); updateBadge(); });
  }
  function all() {
    if (!idbOK()) return Promise.resolve(lsRead());
    return open().then(function (db) {
      return new Promise(function (res) {
        var tx = db.transaction(STORE, 'readonly'), rq = tx.objectStore(STORE).getAll();
        rq.onsuccess = function () { res(rq.result || []); }; rq.onerror = function () { res(lsRead()); };
      });
    }).catch(function () { return lsRead(); });
  }
  function remove(id) {
    if (!idbOK()) { lsWrite(lsRead().filter(function (x) { return x.id !== id; })); return Promise.resolve(); }
    return open().then(function (db) {
      return new Promise(function (res) { var tx = db.transaction(STORE, 'readwrite'); tx.objectStore(STORE).delete(id); tx.oncomplete = function () { res(); }; });
    }).catch(function () {});
  }
  function clear() {
    if (!idbOK()) { lsWrite([]); updateBadge(); return Promise.resolve(); }
    return open().then(function (db) { return new Promise(function (res) { var tx = db.transaction(STORE, 'readwrite'); tx.objectStore(STORE).clear(); tx.oncomplete = function () { updateBadge(); res(); }; }); }).catch(function () {});
  }
  function count() { return all().then(function (a) { return a.length; }); }
  function online() { return g.navigator ? g.navigator.onLine !== false : true; }
  function clientId() { var c = ''; try { c = localStorage.getItem(CID) || ''; } catch (e) {} if (!c) { c = genId(); try { localStorage.setItem(CID, c); } catch (e) {} } return c; }

  function logSync(acc) {
    if (!g.SB || !g.Auth || !g.Auth.token()) return;
    var labels = (acc.labels || []).slice(0, 20).join('; ');
    try {
      g.SB.rpc('app_offline_log', { p_token: g.Auth.token(), p_client_id: clientId(), p_ops_count: (acc.done + acc.failed), p_failed: acc.failed, p_detail: labels, p_device: (g.navigator && g.navigator.userAgent) || '' }).catch(function () {});
    } catch (e) {}
  }

  function flush() {
    if (!g.SB) return Promise.resolve({ done: 0, failed: 0, pending: 0 });
    return all().then(function (items) {
      var acc = { done: 0, failed: 0, pending: items.length, stop: false, labels: [] }, i = 0;
      function step() {
        if (i >= items.length || acc.stop) return Promise.resolve();
        var it = items[i++];
        // идемпотентность: если операция уже применялась (сбой между отправкой и удалением) — не повторяем
        if (appliedHas(it.idem)) { acc.done++; return remove(it.id).then(step); }
        return g.SB.rpc(it.rpc, it.args || {}).then(function (r) {
          if (r && r.error) { acc.failed++; acc.conflicts = (acc.conflicts || 0) + 1; }
          else { acc.done++; appliedAdd(it.idem); }
          acc.labels.push(it.label || it.rpc);
          return remove(it.id).then(step);
        }).catch(function () { acc.stop = true; });
      }
      return step().then(function () {
        return count().then(function (p) { acc.pending = p; if (acc.done + acc.failed > 0) logSync(acc); updateBadge(); return acc; });
      });
    });
  }

  function badge() {
    var el = document.getElementById('oqBadge');
    if (!el) {
      el = document.createElement('div'); el.id = 'oqBadge';
      el.style.cssText = 'position:fixed;right:14px;bottom:14px;z-index:9000;font:700 12px/1 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;' +
        'padding:8px 12px;border-radius:999px;color:#fff;background:#f59e0b;box-shadow:0 6px 18px rgba(0,0,0,.25);display:none;cursor:pointer;';
      el.title = 'Офлайн-очередь: нажмите для синхронизации';
      el.addEventListener('click', function () { flush().then(function (r) { if (r.done + r.failed > 0 && g.AppUI) g.AppUI.toast('Синхронизировано: ' + (r.done + r.failed)); }); });
      if (document.body) document.body.appendChild(el); else document.addEventListener('DOMContentLoaded', function () { document.body.appendChild(el); });
    }
    return el;
  }
  function updateBadge() {
    count().then(function (n) {
      var el = badge();
      if (!online() || n > 0) {
        el.style.display = '';
        el.style.background = online() ? '#f59e0b' : '#ef4444';
        el.textContent = (online() ? '⟳ ' : '⚡ офлайн · ') + n;
      } else { el.style.display = 'none'; }
    });
  }

  function init() {
    updateBadge();
    g.addEventListener('online', function () { if (g.AppUI) g.AppUI.toast('Связь восстановлена — синхронизация'); flush().then(updateBadge); });
    g.addEventListener('offline', function () { updateBadge(); if (g.AppUI) g.AppUI.toast('Нет сети — действия сохраняются локально'); });
    if (online()) flush().then(updateBadge);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();

  g.AppOffline = { add: add, flush: flush, count: count, all: all, clear: clear, online: online, clientId: clientId, updateBadge: updateBadge };
})(window);
