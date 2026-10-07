/* ============================================================
   3DMP Service · module-info.js — панель «О модуле» (описание + подсказки).
   Берёт данные из каталога (purpose/features/connects) и вставляет
   сворачиваемый блок в начало страницы модуля. Работает на всех apps/<id>/.
   ============================================================ */
(function (g) {
  'use strict';
  var SKIP = { auth: 1, dashboard: 1, panel: 1 };
  function ready(fn) { if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn); else fn(); }
  function esc(s) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(s) : String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

  ready(function () {
    try {
      var m = location.pathname.match(/\/apps\/([a-z0-9_]+)\//i);
      if (!m) return;
      var id = m[1];
      if (SKIP[id]) return;
      if (document.querySelector('.mod-info')) return;

      function render() {
        var C = g.AppCatalog; if (!C || !C.apps) return;
        var a = null; C.apps.forEach(function (x) { if (x.id === id) a = x; });
        if (!a) return;
        var byId = {}; C.apps.forEach(function (x) { byId[x.id] = x.title; });
        var feats = (a.features || []).map(function (f) { return '<li>' + esc(f) + '</li>'; }).join('');
        var conns = (a.connects || []).map(function (cid) {
          var t = byId[cid] || cid;
          return '<a class="mi-chip" href="../' + cid + '/index.html">' + esc(t) + '</a>';
        }).join('');
        var el = document.createElement('details');
        el.className = 'mod-info';
        el.innerHTML =
          '<summary><span class="mi-ic">' + (a.icon || 'ℹ️') + '</span>' +
            '<span class="mi-tt"><b>' + esc(a.title) + '</b><span class="note">' + esc(a.desc || '') + '</span></span>' +
            '<span class="mi-chev">▾</span></summary>' +
          '<div class="mi-body">' +
            (a.purpose ? '<p class="mi-purpose">' + esc(a.purpose) + '</p>' : '') +
            '<div class="mi-cols">' +
              (feats ? '<div><h4>Возможности</h4><ul class="mi-feat">' + feats + '</ul></div>' : '') +
              (conns ? '<div><h4>Связи</h4><div class="mi-links">' + conns + '</div></div>' : '') +
            '</div>' +
            '<p class="note mi-hint">Подсказка: заполняйте поля по порядку; данные сохраняются через кнопки действия. Полный гид — «Путеводитель» (apps/guide).</p>' +
          '</div>';
        var wrapEl = document.querySelector('main.wrap') || document.querySelector('main') || document.body;
        wrapEl.insertBefore(el, wrapEl.firstChild);
      }

      if (g.AppCatalog) render();
      else {
        var s = document.createElement('script');
        s.src = '../../assets/js/catalog.js?v=56';
        s.onload = render;
        document.head.appendChild(s);
      }
    } catch (e) {}
  });
})(window);
