/* ============================================================
   3DMP · shell.js — каркас навигации uCoz-типа (глобальный левый сайдбар).
   Меню строится из assets/js/catalog.js (группы-контуры → модули).
   Цвета — существующие переменные app.css (.sh-*). Требует auth.js.
   ============================================================ */
(function (g) {
  'use strict';
  var SELF = document.currentScript;
  var CATALOG_V = '48'; // версия каталога для внешних страниц

  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }
  function ready(fn) { if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn); else fn(); }
  function isLogged() { return !!(g.Auth && g.Auth.token && g.Auth.token()); }

  function init() {
    var src = (SELF && SELF.src) || '';
    var idx = src.indexOf('assets/js/shell.js');
    var ROOT = idx >= 0 ? src.substring(0, idx) : '';
    if (!ROOT) return;
    if (!isLogged()) return;                 // на странице входа не показываем
    if (document.getElementById('shSide')) return;

    var role = (g.Auth && g.Auth.role) ? g.Auth.role() : null;
    var collapsed = false; try { collapsed = localStorage.getItem('sh:collapsed') === '1'; } catch (e) {}

    var wrap = document.createElement('aside');
    wrap.id = 'shSide'; wrap.className = 'sh-side';
    document.body.appendChild(wrap);

    var btn = document.createElement('button');
    btn.className = 'tbtn sh-burger'; btn.type = 'button'; btn.setAttribute('aria-label', 'Меню'); btn.textContent = '☰';
    btn.addEventListener('click', function () {
      if (window.innerWidth <= 768) { document.body.classList.toggle('sh-open'); }
      else { collapsed = !collapsed; applyCollapsed(); }
    });
    var bar = document.querySelector('.topbar');
    if (bar) bar.insertBefore(btn, bar.firstChild ? bar.firstChild.nextSibling : null);

    /* Тема: светлая/тёмная (светлая палитра не меняется; тёмная — доп. режим) */
    function applyTheme(t) { document.documentElement.setAttribute('data-theme', t); try { localStorage.setItem('3dmp:theme', t); } catch (e) {} }
    var saved = ''; try { saved = localStorage.getItem('3dmp:theme') || ''; } catch (e) {}
    applyTheme(saved || 'light');
    if (bar) {
      var tb = document.createElement('button');
      tb.className = 'tbtn'; tb.type = 'button'; tb.title = 'Тема'; tb.setAttribute('aria-label', 'Переключить тему');
      tb.textContent = (document.documentElement.getAttribute('data-theme') === 'dark') ? '☀' : '🌙';
      tb.addEventListener('click', function () {
        var cur = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        applyTheme(cur); tb.textContent = cur === 'dark' ? '☀' : '🌙';
        if (g.AppNotify && g.AppNotify.info) g.AppNotify.info(cur === 'dark' ? 'Тёмная тема' : 'Светлая тема');
      });
      bar.appendChild(tb);
    }

    function applyCollapsed() {
      document.body.classList.toggle('sh-collapsed', collapsed);
      try { localStorage.setItem('sh:collapsed', collapsed ? '1' : '0'); } catch (e) {}
    }

    function link(href, icon, title, active) {
      return '<a class="sh-item' + (active ? ' on' : '') + '" href="' + ROOT + href + '" title="' + esc(title) + '">' +
        '<span class="sh-ic">' + icon + '</span><span class="sh-tx">' + esc(title) + '</span></a>';
    }

    function build(cat) {
      var list = cat.apps.filter(function (a) {
        if (role === 'client') return !!(a.roles && a.roles.indexOf('client') >= 0);
        if (!a.roles) return true;
        return role && a.roles.indexOf(role) >= 0;
      });
      var here = location.href.substring(ROOT.length).split(/[?#]/)[0];
      var out = '<div class="sh-brand"><span>3DMP</span><b>Service</b></div>';
      out += link('index.html', '🏠', 'Хаб', here === '' || here === 'index.html');
      out += link('apps/panel/index.html', '🎛', 'Пульт управления', here.indexOf('apps/panel') === 0);
      out += link('apps/adoption/index.html', '🚀', 'Карта внедрения', here.indexOf('apps/adoption') === 0);
      (cat.groups || []).forEach(function (grp) {
        var items = list.filter(function (a) { return a.group === grp.id; });
        if (!items.length) return;
        out += '<div class="sh-grp">' + grp.icon + ' ' + esc(grp.title) + '</div>';
        out += items.map(function (a) { return link(a.href, a.icon, a.title, here.indexOf(a.href) === 0); }).join('');
      });
      var rest = list.filter(function (a) { return !a.group; });
      if (rest.length) out += '<div class="sh-grp">Прочее</div>' + rest.map(function (a) { return link(a.href, a.icon, a.title, here.indexOf(a.href) === 0); }).join('');
      wrap.innerHTML = out;
    }

    document.body.classList.add('sh-has');
    applyCollapsed();

    var navWrap = document.getElementById('navWrap'); if (navWrap) navWrap.style.display = 'none'; // верхнее меню заменяем сайдбаром

    if (g.AppCatalog && g.AppCatalog.apps) build(g.AppCatalog);
    else { var s = document.createElement('script'); s.src = ROOT + 'assets/js/catalog.js?v=' + CATALOG_V; s.onload = function () { build(g.AppCatalog); }; document.head.appendChild(s); }

    document.addEventListener('click', function (e) { if (window.innerWidth <= 768 && e.target.closest && e.target.closest('.sh-item')) document.body.classList.remove('sh-open'); });
  }

  ready(init);
  g.AppShell = { init: init };
})(window);
