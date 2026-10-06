/* ============================================================
   3DMP · screenshot.client.js — клиент сервиса снимков «/shot».
   Публичный API: window.Screenshot
     .endpoint() / .setEndpoint(url) / .token() / .setToken(t) / .clear()
     .available()               — настроен ли backend
     .shotOptions()             — {shotEndpoint, shotHeaders, shotParams} для PageRemarks.init
     .capture(url, opts)        — Promise<dataURL> (PNG) через backend
     .isBlockedHost(hostname)   — клиентская проверка (defence-in-depth; основная — на сервере)
   Конфигурация (по приоритету):
     1) window.SHOT_CONFIG = { endpoint, token, width, fullPage }
     2) <meta name="shot-endpoint" content="https://.../shot">  (+ <meta name="shot-token">)
     3) localStorage 'pr:shot:endpoint' / 'pr:shot:token'
   Без настроенного endpoint модуль «Замечания» работает в демо/same-origin режиме.
   Backend-пример — в основной директории проекта: `backend-example/` (вне FTP-набора).
   v1.0.
   ============================================================ */
(function (g) {
  'use strict';

  var LS_EP = 'pr:shot:endpoint', LS_TK = 'pr:shot:token';

  function meta(name) {
    var m = document.querySelector && document.querySelector('meta[name="' + name + '"]');
    return m ? (m.getAttribute('content') || '').trim() : '';
  }
  function lsGet(k) { try { return localStorage.getItem(k) || ''; } catch (e) { return ''; } }
  function lsSet(k, v) { try { v ? localStorage.setItem(k, v) : localStorage.removeItem(k); } catch (e) {} }

  function cfg() {
    var c = g.SHOT_CONFIG || {};
    return {
      endpoint: (c.endpoint || meta('shot-endpoint') || lsGet(LS_EP) || '').trim(),
      token: (c.token || meta('shot-token') || lsGet(LS_TK) || '').trim(),
      width: c.width || 1280,
      fullPage: c.fullPage !== false
    };
  }

  /* Клиентская защита от SSRF (грубая). Сервер обязан проверять заново и строже. */
  function isBlockedHost(hostname) {
    if (!hostname) return true;
    var h = String(hostname).toLowerCase().replace(/^\[|\]$/g, '');
    if (h === 'localhost' || h === 'metadata.google.internal') return true;
    if (/\.(local|internal|localhost)$/.test(h)) return true;
    // IPv4 приватные/спец диапазоны
    var m = h.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
    if (m) {
      var a = +m[1], b = +m[2];
      if (a === 0 || a === 10 || a === 127 || a >= 224) return true;
      if (a === 169 && b === 254) return true;              // link-local / cloud metadata
      if (a === 172 && b >= 16 && b <= 31) return true;
      if (a === 192 && b === 168) return true;
      if (a === 100 && b >= 64 && b <= 127) return true;    // CGNAT
      return false;
    }
    // IPv6 loopback/link-local/unique-local
    if (h === '::1' || /^fe80:/i.test(h) || /^f[cd][0-9a-f]{2}:/i.test(h)) return true;
    return false;
  }

  function normalizeUrl(u) {
    u = (u || '').trim();
    if (!u) return '';
    if (!/^https?:\/\//i.test(u)) u = 'https://' + u;
    return u;
  }

  function safeUrl(u) {
    var abs = new URL(normalizeUrl(u));
    if (abs.protocol !== 'http:' && abs.protocol !== 'https:') throw new Error('Разрешены только http/https');
    if (isBlockedHost(abs.hostname)) throw new Error('Адрес заблокирован (приватная/служебная зона)');
    return abs.href;
  }

  function headers() {
    var c = cfg(), h = {};
    if (c.token) h['Authorization'] = 'Bearer ' + c.token;
    return h;
  }

  function capture(url, opts) {
    opts = opts || {};
    var c = cfg();
    if (!c.endpoint) return Promise.reject(new Error('Backend /shot не настроен'));
    var safe;
    try { safe = safeUrl(url); } catch (e) { return Promise.reject(e); }
    var qs = '?url=' + encodeURIComponent(safe) + '&width=' + (opts.width || c.width) + '&fullPage=' + ((opts.fullPage != null ? opts.fullPage : c.fullPage) ? 'true' : 'false');
    var ctrl = ('AbortController' in g) ? new AbortController() : null;
    var to = opts.timeout || 30000;
    var timer = ctrl ? setTimeout(function () { ctrl.abort(); }, to) : null;
    return fetch(c.endpoint + qs, { headers: headers(), signal: ctrl ? ctrl.signal : undefined })
      .then(function (r) {
        if (!r.ok) throw new Error('shot: ' + r.status);
        var ct = r.headers.get('content-type') || '';
        if (ct.indexOf('image/') < 0) throw new Error('shot: неожиданный тип ответа (' + ct + ')');
        return r.blob();
      })
      .then(function (b) {
        return new Promise(function (res, rej) {
          var fr = new FileReader();
          fr.onload = function () { res(fr.result); };
          fr.onerror = function () { rej(new Error('Не удалось прочитать снимок')); };
          fr.readAsDataURL(b);
        });
      })
      .finally(function () { if (timer) clearTimeout(timer); });
  }

  var Screenshot = {
    config: cfg,
    endpoint: function () { return cfg().endpoint; },
    token: function () { return cfg().token; },
    setEndpoint: function (u) { lsSet(LS_EP, (u || '').trim()); },
    setToken: function (t) { lsSet(LS_TK, (t || '').trim()); },
    clear: function () { lsSet(LS_EP, ''); lsSet(LS_TK, ''); },
    available: function () { return !!cfg().endpoint; },
    shotOptions: function () {
      var c = cfg();
      return { shotEndpoint: c.endpoint, shotHeaders: headers(), shotParams: { width: c.width, fullPage: c.fullPage } };
    },
    isBlockedHost: isBlockedHost,
    safeUrl: safeUrl,
    capture: capture
  };

  g.Screenshot = Screenshot;
})(window);
