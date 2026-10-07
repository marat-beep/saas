/* ============================================================
   3DMP Service · навигация в шапке (window.AppNav)
   Панель «☰ Меню»: только КОНТУРЫ; клик по контуру раскрывает его состав
   (аккордеон, один открыт). Источник — assets/js/catalog.js.
   Пути считаются от расположения скрипта → работают на любой глубине.
   Требует auth.js (window.Auth) для фильтра по роли.
   ============================================================ */
(function (g) {
  'use strict';

  var SELF = document.currentScript;
  var CATALOG_V = '56';

  function ready(fn) {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn);
    else fn();
  }

  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }

  // Стили меню встраиваем из JS (устойчиво к кэшу CSS)
  function ensureStyle() {
    if (document.getElementById('navMenuStyle')) return;
    var st = document.createElement('style'); st.id = 'navMenuStyle';
    st.textContent =
      '.nav-body{display:none} .nav-grp.open .nav-body{display:block}' +
      '.nav-grp .navgrp-t{width:100%;text-align:left;background:none;border:0;cursor:pointer;font:inherit;font-weight:700;color:var(--muted);' +
      'text-transform:uppercase;letter-spacing:.03em;font-size:.7rem;display:flex;align-items:center;justify-content:space-between;gap:8px;padding:8px 10px;border-radius:8px}' +
      '.nav-grp .navgrp-t:hover{background:var(--accent-100,#e8f5ee);color:var(--text)}' +
      '.nav-grp .nav-cv{font-style:normal;transition:transform .15s;display:inline-block}' +
      '.nav-grp.open .nav-cv{transform:rotate(180deg)}' +
      '.nav-grp .nav-body a{display:block}';
    document.head.appendChild(st);
  }

  function init() {
    var src = (SELF && SELF.src) || '';
    var idx = src.indexOf('assets/js/nav.js');
    if (idx < 0) return;
    var ROOT = src.substring(0, idx); // .../saas/

    var bar = document.querySelector('.topbar .brand') || document.querySelector('.topbar');
    if (!bar || document.getElementById('navWrap')) return;
    ensureStyle();

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
      var out = '<a class="nav-grp-link" href="' + ROOT + 'apps/product/index.html">💳 Продукт и цены</a>';
      (cat.groups || []).forEach(function (grp) {
        var items = list.filter(function (a) { return a.group === grp.id; });
        if (!items.length) return;
        out += '<div class="nav-grp" data-g="' + grp.id + '">' +
          '<button class="navgrp-t" type="button">' + grp.icon + ' ' + esc(grp.title) + ' <span class="nav-cv">▾</span></button>' +
          '<div class="nav-body">' + items.map(link).join('') + '</div></div>';
      });
      var rest = list.filter(function (a) { return !a.group; });
      if (rest.length) out += '<div class="nav-grp"><button class="navgrp-t" type="button">🗂 Прочее <span class="nav-cv">▾</span></button><div class="nav-body">' + rest.map(link).join('') + '</div></div>';
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

    function bindGroups() {
      var grps = d.querySelectorAll('.nav-grp .navgrp-t');
      Array.prototype.forEach.call(grps, function (b) {
        b.addEventListener('click', function () {
          var gEl = b.closest('.nav-grp'); if (!gEl) return;
          var was = gEl.classList.contains('open');
          Array.prototype.forEach.call(d.querySelectorAll('.nav-grp.open'), function (x) { x.classList.remove('open'); });
          if (!was) gEl.classList.add('open');
        });
      });
    }

    function upgrade() {
      if (d && g.AppCatalog && g.AppCatalog.apps) { d.innerHTML = buildFromCatalog(g.AppCatalog); bindGroups(); }
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
