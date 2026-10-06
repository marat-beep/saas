/* ============================================================
   3DMP Service · навигация в шапке (window.AppNav)
   Меню строится из ЕДИНОГО источника — assets/js/catalog.js:
   группы и модули берутся из window.AppCatalog (с фолбэком).
   Пути считаются от расположения скрипта → работают на любой глубине.
   Требует auth.js (window.Auth) для фильтра по роли.
   ============================================================ */
(function (g) {
  'use strict';

  var SELF = document.currentScript;
  var CATALOG_V = '38';

  function ready(fn) {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn);
    else fn();
  }

  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }

  function init() {
    var src = (SELF && SELF.src) || '';
    var idx = src.indexOf('assets/js/nav.js');
    if (idx < 0) return;
    var ROOT = src.substring(0, idx); // .../saas/

    var bar = document.querySelector('.topbar .brand') || document.querySelector('.topbar');
    if (!bar || document.getElementById('navWrap')) return;

    var role = (g.Auth && g.Auth.role) ? g.Auth.role() : null;

    function link(a) {
      var st = (g.AppCatalog && g.AppCatalog.statusOf) ? g.AppCatalog.statusOf(a.id) : 'done';
      return '<a href="' + ROOT + a.href + '"><span class="mdot ' + st + '" title="' + st + '"></span>' + a.icon + ' ' + esc(a.title) + '</a>';
    }

    function buildFromCatalog(cat) {
      var list = cat.apps.filter(function (a) {
        if (role === 'client') return !!(a.roles && a.roles.indexOf('client') >= 0);
        if (!a.roles) return true;
        return role && a.roles.indexOf(role) >= 0;
      });
      var out = '<div class="navgrp-t">☁️ Продукт</div><a href="' + ROOT + 'apps/product/index.html">💳 Продукт и цены</a>';
      (cat.groups || []).forEach(function (grp) {
        var items = list.filter(function (a) { return a.group === grp.id; });
        if (!items.length) return;
        out += '<div class="navgrp-t">' + grp.icon + ' ' + esc(grp.title) + '</div>';
        out += items.map(link).join('');
      });
      var rest = list.filter(function (a) { return !a.group; });
      if (rest.length) out += rest.map(link).join('');
      return out;
    }

    // Фолбэк, пока каталог не загружен
    var FALLBACK =
      '<a href="' + ROOT + 'index.html">🏠 Главная</a>' +
      '<a href="' + ROOT + 'apps/product/index.html">💳 Продукт и цены</a>' +
      '<a href="' + ROOT + 'apps/panel/index.html">🎛 Пульт управления</a>' +
      '<a href="' + ROOT + 'apps/dashboard/index.html">📊 Личный кабинет</a>' +
      '<a href="' + ROOT + 'apps/orders/index.html">📥 Заявки</a>' +
      '<a href="' + ROOT + 'apps/guide/index.html">📖 Гид по системе</a>';

    var rest = location.href.substring(ROOT.length).split(/[?#]/)[0];
    var isHub = (rest === '' || rest === 'index.html');

    var wrap = document.createElement('div');
    wrap.className = 'topnav';
    wrap.id = 'navWrap';
    wrap.innerHTML =
      (isHub ? '' : '<a class="navbtn" href="' + ROOT + 'index.html">← Хаб</a>') +
      '<div class="navmenu"><button class="navbtn" id="navToggle" type="button">☰ Меню</button>' +
      '<div class="navdrop" id="navDrop">' + FALLBACK + '</div></div>';

    bar.parentNode.insertBefore(wrap, bar.nextSibling);

    var t = document.getElementById('navToggle');
    var d = document.getElementById('navDrop');
    if (t && d) {
      t.addEventListener('click', function (e) { e.stopPropagation(); d.classList.toggle('open'); });
      document.addEventListener('click', function () { d.classList.remove('open'); });
      d.addEventListener('click', function (e) { e.stopPropagation(); });
    }

    function upgrade() {
      if (d && g.AppCatalog && g.AppCatalog.apps) d.innerHTML = buildFromCatalog(g.AppCatalog);
    }

    if (g.AppCatalog && g.AppCatalog.apps) { upgrade(); }
    else {
      var s = document.createElement('script');
      s.src = ROOT + 'assets/js/catalog.js?v=' + CATALOG_V;
      s.onload = upgrade;
      document.head.appendChild(s);
    }
  }

  ready(init);
  g.AppNav = { init: init };
})(window);
