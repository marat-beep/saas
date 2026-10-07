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
  var CATALOG_V = '72';

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

  // Единая правая группа кнопок топбара: Тема · Сервер · Вход · Пользователь
  function setupPills(bar, ROOT) {
    if (!bar || document.getElementById('srvBtn') || document.getElementById('npSrvBtn')) return; // на хабе кнопки уже есть
    try { var t0 = localStorage.getItem('3dmp:theme'); if (t0) document.documentElement.setAttribute('data-theme', t0); } catch (e) {}
    function mk(tag, cls, html) { var e = document.createElement(tag); e.className = cls; if (html != null) e.innerHTML = html; return e; }
    function bind(btn, drop) {
      btn.addEventListener('click', function (e) { e.stopPropagation(); drop.style.display = (drop.style.display === 'none' || !drop.style.display) ? 'block' : 'none'; });
      document.addEventListener('click', function (e) { if (!(e.target.closest && (e.target.closest('#' + drop.id) || e.target.closest('#' + btn.id)))) drop.style.display = 'none'; });
    }
    var theme = mk('button', 'srvbtn', (document.documentElement.getAttribute('data-theme') === 'dark') ? '☀' : '🌙'); theme.type = 'button'; theme.id = 'npThemeBtn'; theme.title = 'Тема';
    theme.addEventListener('click', function () {
      var next = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', next); try { localStorage.setItem('3dmp:theme', next); } catch (e) {}
      theme.textContent = next === 'dark' ? '☀' : '🌙';
    });
    var srv = mk('button', 'srvbtn', '🟢 <span>Сервер</span>'); srv.type = 'button'; srv.id = 'npSrvBtn'; srv.title = 'Статус сервера';
    var srvD = mk('div', 'srvdrop', '<div class="status" id="conn"><span class="dot wait"></span><span class="status-text">Проверка…</span></div><ul class="checklist" data-checklist></ul>'); srvD.id = 'npSrvDrop'; srvD.style.display = 'none';
    var ent = mk('button', 'srvbtn', '🎛 <span>Вход</span>'); ent.type = 'button'; ent.id = 'npEntBtn'; ent.title = 'Единая точка входа';
    var entD = mk('div', 'srvdrop', '<div class="btn-row">' +
      '<a class="btn" href="' + ROOT + 'apps/panel/index.html" style="width:auto;padding:10px 14px;">🎛 Пульт</a>' +
      '<a class="btn secondary" href="' + ROOT + 'apps/product/index.html" style="width:auto;padding:10px 14px;">💳 Продукт и цены</a>' +
      '<a class="btn secondary" href="' + ROOT + 'apps/guide/index.html" style="width:auto;padding:10px 14px;">📖 Гид</a></div>'); entD.id = 'npEntDrop'; entD.style.display = 'none';
    var usr = mk('button', 'userbtn', '<span class="uava" id="npAva">?</span> <span id="npLogin">…</span>'); usr.type = 'button'; usr.id = 'npUserBtn'; usr.title = 'Аккаунт';
    var usrD = mk('div', 'userdrop', '<div class="cab-info"><h1 id="npName">…</h1><div class="note" id="npSub"></div><div class="cab-badges mt" id="npBadges"></div></div>' +
      '<div class="btn-row mt"><a class="btn secondary" href="' + ROOT + 'apps/dashboard/index.html" style="width:auto;padding:9px 14px;">Открыть кабинет</a>' +
      '<button class="btn secondary" id="npOut" type="button" style="width:auto;padding:9px 14px;">Выйти</button></div>'); usrD.id = 'npUserDrop'; usrD.style.display = 'none';
    bar.appendChild(theme); bar.appendChild(srv); bar.appendChild(srvD); bar.appendChild(ent); bar.appendChild(entD); bar.appendChild(usr); bar.appendChild(usrD);
    bind(srv, srvD); bind(ent, entD); bind(usr, usrD);
    function fill() {
      var s = (g.Auth && g.Auth.session) ? g.Auth.session() : null; if (!s) return;
      var nm = s.full_name || s.login || '';
      var ini = (nm.trim().split(/\s+/).map(function (w) { return w[0] || ''; }).slice(0, 2).join('') || (s.login || '?').slice(0, 1)).toUpperCase();
      var ava = document.getElementById('npAva'); if (ava) ava.textContent = ini;
      var lg = document.getElementById('npLogin'); if (lg) lg.textContent = s.login || '';
      var nEl = document.getElementById('npName'); if (nEl) nEl.textContent = nm;
      var sEl = document.getElementById('npSub'); if (sEl) sEl.textContent = (s.tenant_name ? s.tenant_name + ' · ' : '') + ((g.Auth.roleLabel && g.Auth.roleLabel(s.role)) || s.role || '');
      var bEl = document.getElementById('npBadges'); if (bEl) bEl.innerHTML = '<span class="badge">' + esc((g.Auth.roleLabel && g.Auth.roleLabel(s.role)) || s.role || '') + '</span>' + (s.tenant_name ? '<span class="badge">' + esc(s.tenant_name) + '</span>' : '');
    }
    fill();
    if (g.Auth && g.Auth.refresh) { g.Auth.refresh().then(fill).catch(function () {}); }
    var out = document.getElementById('npOut'); if (out) out.addEventListener('click', function () { g.Auth.logout(); location.href = ROOT + 'index.html'; });
    if (g.AppStatus && g.AppStatus.render) { try { g.AppStatus.render('#conn'); } catch (e) {} }
    else { var cn = document.getElementById('conn'); if (cn) cn.innerHTML = '<span class="dot done"></span><span class="status-text">OK</span>'; }
    var who = document.getElementById('who'); if (who) who.style.display = 'none';
    var lo = document.getElementById('logout'); if (lo) lo.style.display = 'none';
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

    setupPills(document.querySelector('.topbar') || bar, ROOT);

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
