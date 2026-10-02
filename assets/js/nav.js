/* ============================================================
   3DMP Service · навигация в шапке (window.AppNav)
   Вставляет в .topbar кнопку «← Хаб» и меню модулей.
   Пути считаются от расположения самого скрипта → работают на любой глубине.
   Требует auth.js (window.Auth) для фильтра по роли.
   ============================================================ */
(function (g) {
  'use strict';

  var SELF = document.currentScript;

  function ready(fn) {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn);
    else fn();
  }

  function init() {
    var src = (SELF && SELF.src) || '';
    var idx = src.indexOf('assets/js/nav.js');
    if (idx < 0) return;
    var ROOT = src.substring(0, idx); // .../saas/

    var bar = document.querySelector('.topbar .brand') || document.querySelector('.topbar');
    if (!bar || document.getElementById('navWrap')) return;

    var role = (g.Auth && g.Auth.role) ? g.Auth.role() : null;

    var items = [
      ['🏠', 'Главная', ROOT + 'index.html', true],
      ['📊', 'Личный кабинет', ROOT + 'apps/dashboard/index.html', true],
      ['📦', 'Портал закупок', ROOT + 'apps/supplier/index.html', true],
      ['🌐', 'Прототипы экосистемы', ROOT + 'eco/index.html', true],
      ['🛡', 'Администрирование', ROOT + 'apps/admin/index.html', role === 'admin'],
      ['🔐', 'Вход', ROOT + 'apps/auth/index.html', !role]
    ];

    var links = items.filter(function (x) { return x[3]; }).map(function (x) {
      return '<a href="' + x[2] + '">' + x[0] + ' ' + x[1] + '</a>';
    }).join('<div class="sep"></div>');

    var rest = location.href.substring(ROOT.length).split(/[?#]/)[0];
    var isHub = (rest === '' || rest === 'index.html');

    var wrap = document.createElement('div');
    wrap.className = 'topnav';
    wrap.id = 'navWrap';
    wrap.innerHTML =
      (isHub ? '' : '<a class="navbtn" href="' + ROOT + 'index.html">← Хаб</a>') +
      '<div class="navmenu"><button class="navbtn" id="navToggle" type="button">☰ Меню</button>' +
      '<div class="navdrop" id="navDrop">' + links + '</div></div>';

    bar.parentNode.insertBefore(wrap, bar.nextSibling);

    var t = document.getElementById('navToggle');
    var d = document.getElementById('navDrop');
    if (t && d) {
      t.addEventListener('click', function (e) { e.stopPropagation(); d.classList.toggle('open'); });
      document.addEventListener('click', function () { d.classList.remove('open'); });
      d.addEventListener('click', function (e) { e.stopPropagation(); });
    }
  }

  ready(init);
  g.AppNav = { init: init };
})(window);
