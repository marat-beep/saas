/* ============================================================
   3DMP · Общие утилиты
   Форматирование, генерация номеров, работа с DOM, моки.
   ============================================================ */

(function (global) {
  'use strict';

  var App = global.App || {};

  /* ---------- Форматирование ---------- */
  function money(value, opts) {
    opts = opts || {};
    var n = Number(value) || 0;
    var formatted = n.toLocaleString('ru-RU', {
      minimumFractionDigits: opts.decimals == null ? 0 : opts.decimals,
      maximumFractionDigits: opts.decimals == null ? 0 : opts.decimals
    });
    return formatted + ' ₽';
  }

  function number(value, decimals) {
    var n = Number(value) || 0;
    return n.toLocaleString('ru-RU', {
      minimumFractionDigits: decimals || 0,
      maximumFractionDigits: decimals || 0
    });
  }

  function pad(n, len) { n = String(n); while (n.length < (len || 2)) n = '0' + n; return n; }

  function today() {
    var d = new Date();
    return pad(d.getDate()) + '.' + pad(d.getMonth() + 1) + '.' + d.getFullYear();
  }

  function nowTime() {
    var d = new Date();
    return pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  function addDays(days) {
    var d = new Date();
    d.setDate(d.getDate() + days);
    return pad(d.getDate()) + '.' + pad(d.getMonth() + 1) + '.' + d.getFullYear();
  }

  function plural(n, one, few, many) {
    n = Math.abs(n) % 100;
    var n1 = n % 10;
    if (n > 10 && n < 20) return many;
    if (n1 > 1 && n1 < 5) return few;
    if (n1 === 1) return one;
    return many;
  }

  /* ---------- Номера документов ---------- */
  function orderNumber(prefix, seq) {
    return (prefix || '3DMP') + '-' + pad(seq, 4);
  }

  function randomTicket(prefix) {
    var d = new Date();
    var stamp = String(d.getFullYear()).slice(2) + pad(d.getMonth() + 1);
    var rnd = Math.floor(1000 + Math.random() * 9000);
    return (prefix || 'REQ') + '-' + stamp + '-' + rnd;
  }

  /* ---------- DOM ---------- */
  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  /* Делегирование клика по элементам с data-атрибутом */
  function on(root, event, selector, handler) {
    (root || document).addEventListener(event, function (e) {
      var el = e.target.closest(selector);
      if (el && (root || document).contains(el)) handler.call(el, e, el);
    });
  }

  function show(el) { if (el) el.classList.remove('hidden'); }
  function hide(el) { if (el) el.classList.add('hidden'); }
  function toggle(el, onFlag) { if (el) el.classList.toggle('hidden', !onFlag); }

  /* ---------- Toast ---------- */
  function toast(message) {
    var el = document.createElement('div');
    el.textContent = message;
    el.style.cssText = 'position:fixed;left:50%;bottom:32px;transform:translateX(-50%) translateY(20px);' +
      'background:#0f172a;color:#fff;padding:11px 18px;border-radius:10px;font-size:.82rem;font-weight:600;' +
      'box-shadow:0 10px 30px rgba(0,0,0,.3);z-index:9999;opacity:0;transition:opacity .25s, transform .25s;max-width:90vw;text-align:center;';
    document.body.appendChild(el);
    requestAnimationFrame(function () { el.style.opacity = '1'; el.style.transform = 'translateX(-50%) translateY(0)'; });
    setTimeout(function () {
      el.style.opacity = '0'; el.style.transform = 'translateX(-50%) translateY(20px)';
      setTimeout(function () { el.remove(); }, 260);
    }, 2400);
  }

  /* ---------- Простое хранилище прототипа (in-memory + localStorage) ---------- */
  var Store = {
    key: function (k) { return '3dmp:' + k; },
    get: function (k, def) {
      try { var v = localStorage.getItem(this.key(k)); return v == null ? def : JSON.parse(v); }
      catch (e) { return def; }
    },
    set: function (k, v) {
      try { localStorage.setItem(this.key(k), JSON.stringify(v)); } catch (e) {}
      return v;
    },
    remove: function (k) { try { localStorage.removeItem(this.key(k)); } catch (e) {} }
  };

  /* ---------- Черновик заявки (cross-app) ---------- */
  var Draft = {
    set: function (data) { return Store.set('draft', data); },
    get: function () { return Store.get('draft', null); },
    clear: function () { Store.remove('draft'); }
  };

  App.money = money;
  App.number = number;
  App.pad = pad;
  App.today = today;
  App.nowTime = nowTime;
  App.addDays = addDays;
  App.plural = plural;
  App.orderNumber = orderNumber;
  App.randomTicket = randomTicket;
  App.$ = $;
  App.$$ = $$;
  App.on = on;
  App.show = show;
  App.hide = hide;
  App.toggle = toggle;
  App.toast = toast;
  App.Store = Store;
  App.Draft = Draft;

  global.App = App;
})(window);
