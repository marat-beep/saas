/* ============================================================
   3DMP · shell.js — каркас навигации uCoz-типа (глобальный левый сайдбар).
   Меню строится из assets/js/catalog.js (группы-контуры → модули).
   Цвета — существующие переменные app.css (.sh-*). Требует auth.js.
   ============================================================ */
(function (g) {
  'use strict';
  var SELF = document.currentScript;
  var CATALOG_V = '55'; // версия каталога для внешних страниц

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

    var backdrop = document.createElement('div');
    backdrop.className = 'sh-backdrop'; backdrop.id = 'shBackdrop';
    backdrop.addEventListener('click', function () { document.body.classList.remove('sh-open'); });
    document.body.appendChild(backdrop);

    var btn = document.createElement('button');
    btn.className = 'tbtn sh-burger'; btn.type = 'button'; btn.setAttribute('aria-label', 'Меню'); btn.textContent = '☰';
    btn.addEventListener('click', function () { document.body.classList.toggle('sh-open'); });
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

    /* Кнопки топбара: Сервер · Вход · Пользователь (как на главной) */
    if (bar) {
      function mk(tag, cls, html) { var e = document.createElement(tag); e.className = cls; if (html != null) e.innerHTML = html; return e; }
      function bindPair(btn, drop) {
        btn.addEventListener('click', function (e) { e.stopPropagation(); drop.style.display = (drop.style.display === 'none' || !drop.style.display) ? 'block' : 'none'; });
        document.addEventListener('click', function (e) { if (!(e.target.closest && (e.target.closest('#' + drop.id) || e.target.closest('#' + btn.id)))) drop.style.display = 'none'; });
      }
      var srv = mk('button', 'srvbtn', '🟢 <span>Сервер</span>'); srv.type = 'button'; srv.id = 'shSrvBtn'; srv.title = 'Статус сервера';
      var srvD = mk('div', 'srvdrop', '<div class="status" id="conn"><span class="dot wait"></span><span class="status-text">Проверка…</span></div><ul class="checklist" data-checklist></ul>'); srvD.id = 'shSrvDrop'; srvD.style.display = 'none';
      var ent = mk('button', 'srvbtn', '🎛 <span>Вход</span>'); ent.type = 'button'; ent.id = 'shEntBtn'; ent.title = 'Единая точка входа';
      var entD = mk('div', 'srvdrop', '<div class="btn-row">' +
        '<a class="btn" href="' + ROOT + 'apps/panel/index.html" style="width:auto;padding:10px 14px;">🎛 Пульт</a>' +
        '<a class="btn secondary" href="' + ROOT + 'apps/product/index.html" style="width:auto;padding:10px 14px;">💳 Продукт и цены</a>' +
        '<a class="btn secondary" href="' + ROOT + 'apps/guide/index.html" style="width:auto;padding:10px 14px;">📖 Гид</a></div>'); entD.id = 'shEntDrop'; entD.style.display = 'none';
      var usr = mk('button', 'userbtn', '<span class="uava" id="shAva">?</span> <span id="shLogin">…</span>'); usr.type = 'button'; usr.id = 'shUserBtn'; usr.title = 'Аккаунт';
      var usrD = mk('div', 'userdrop', '<div class="cab-info"><h1 id="shName">…</h1><div class="note" id="shSub"></div><div class="cab-badges mt" id="shBadges"></div></div>' +
        '<div class="btn-row mt"><a class="btn secondary" href="' + ROOT + 'apps/dashboard/index.html" style="width:auto;padding:9px 14px;">Открыть кабинет</a>' +
        '<button class="btn secondary" id="shOut" type="button" style="width:auto;padding:9px 14px;">Выйти</button></div>'); usrD.id = 'shUserDrop'; usrD.style.display = 'none';
      bar.appendChild(srv); bar.appendChild(srvD); bar.appendChild(ent); bar.appendChild(entD); bar.appendChild(usr); bar.appendChild(usrD);
      bindPair(srv, srvD); bindPair(ent, entD); bindPair(usr, usrD);
      var s = (g.Auth && g.Auth.session) ? g.Auth.session() : null;
      if (s) {
        var nm = s.full_name || s.login || '';
        var ini = (nm.trim().split(/\s+/).map(function (w) { return w[0] || ''; }).slice(0, 2).join('') || (s.login || '?').slice(0, 1)).toUpperCase();
        var ava = document.getElementById('shAva'); if (ava) ava.textContent = ini;
        var lg = document.getElementById('shLogin'); if (lg) lg.textContent = s.login || '';
        var nEl = document.getElementById('shName'); if (nEl) nEl.textContent = nm;
        var sEl = document.getElementById('shSub'); if (sEl) sEl.textContent = (s.tenant_name ? s.tenant_name + ' · ' : '') + ((g.Auth.roleLabel && g.Auth.roleLabel(s.role)) || s.role || '');
        var bEl = document.getElementById('shBadges'); if (bEl) bEl.innerHTML = '<span class="badge">' + esc((g.Auth.roleLabel && g.Auth.roleLabel(s.role)) || s.role || '') + '</span>' + (s.tenant_name ? '<span class="badge">' + esc(s.tenant_name) + '</span>' : '');
      }
      var out = document.getElementById('shOut'); if (out) out.addEventListener('click', function () { g.Auth.logout(); location.href = ROOT + 'index.html'; });
      if (g.AppStatus && g.AppStatus.render) g.AppStatus.render('#conn');
      else { var cn = document.getElementById('conn'); if (cn) cn.innerHTML = '<span class="dot done"></span><span class="status-text">OK</span>'; }
      var who = document.getElementById('who'); if (who) who.style.display = 'none';
      var lo = document.getElementById('logout'); if (lo) lo.style.display = 'none';
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
        var activeIn = items.some(function (a) { return here.indexOf(a.href) === 0; });
        out += '<div class="sh-group' + (activeIn ? ' active' : '') + '">' +
          '<button class="sh-grp" type="button"><span>' + grp.icon + ' ' + esc(grp.title) + '</span><span class="sh-cnt">' + items.length + ' <i class="sh-cv">▸</i></span></button>' +
          '<div class="sh-group-body">' + items.map(function (a) { return link(a.href, a.icon, a.title, here.indexOf(a.href) === 0); }).join('') + '</div></div>';
      });
      var rest = list.filter(function (a) { return !a.group; });
      if (rest.length) out += '<div class="sh-group"><button class="sh-grp" type="button"><span>🗂 Прочее</span><span class="sh-cnt">' + rest.length + ' <i class="sh-cv">▾</i></span></button><div class="sh-group-body">' + rest.map(function (a) { return link(a.href, a.icon, a.title, here.indexOf(a.href) === 0); }).join('') + '</div></div>';
      wrap.innerHTML = out;
      // Выпадающее меню группы: открыта максимум одна
      Array.prototype.forEach.call(wrap.querySelectorAll('.sh-grp'), function (b) {
        b.addEventListener('click', function () {
          var g = b.closest('.sh-group'); if (!g) return;
          var wasOpen = g.classList.contains('open');
          Array.prototype.forEach.call(wrap.querySelectorAll('.sh-group.open'), function (x) { x.classList.remove('open'); });
          if (!wasOpen) g.classList.add('open');
        });
      });
      document.addEventListener('click', function (e) {
        if (e.target.closest && e.target.closest('.sh-side')) return;
        Array.prototype.forEach.call(wrap.querySelectorAll('.sh-group.open'), function (x) { x.classList.remove('open'); });
      });
    }

    /* ---------- White-label: бренд по поддомену/своему домену (P6) ---------- */
    function shade(hex, f) {
      try {
        var n = String(hex).replace('#', '');
        if (n.length === 3) n = n[0] + n[0] + n[1] + n[1] + n[2] + n[2];
        var h = function (x) { x = Math.max(0, Math.min(255, Math.round(x))).toString(16); return x.length < 2 ? '0' + x : x; };
        return '#' + h(parseInt(n.slice(0, 2), 16) * f) + h(parseInt(n.slice(2, 4), 16) * f) + h(parseInt(n.slice(4, 6), 16) * f);
      } catch (e) { return hex; }
    }
    function applyBrand(row) {
      if (!row) return;
      var brand = row.brand || {}, theme = row.theme || {};
      var accent = theme.accent || brand.color || brand.accent;
      if (accent) {
        document.documentElement.style.setProperty('--accent', accent);
        document.documentElement.style.setProperty('--accent-700', shade(accent, 0.8));
      }
      var logo = brand.logo || theme.logo, name = brand.name || theme.name || row.name;
      if (logo || name) {
        var sb = wrap.querySelector('.sh-brand');
        if (sb) sb.innerHTML = '<span>' + esc(logo || '🏭') + '</span> <b>' + esc(name || '') + '</b>';
      }
      if (name) { var tb = document.querySelector('.topbar .brand a'); if (tb) tb.textContent = name; }
      if (theme.slogan) document.documentElement.setAttribute('data-brand-slogan', theme.slogan);
    }
    function resolveBrand() {
      if (!g.SB || !g.SB.rpc) return;
      var host = (location.hostname || '').toLowerCase();
      if (!host || host === 'localhost' || /^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return;
      var cands = [host];
      if (host.split('.').length > 2) cands.push(host.split('.')[0]);
      var ck = '3dmp:brand:' + host, cached = '';
      try { cached = sessionStorage.getItem(ck) || ''; } catch (e) {}
      if (cached) { try { applyBrand(JSON.parse(cached)); } catch (e) {} return; }
      (function next(i) {
        if (i >= cands.length) return;
        g.SB.rpc('app_whitelabel_resolve', { p_subdomain: cands[i] }).then(function (r) {
          if (r.error) return;
          var row = r.data && r.data[0];
          if (row) { try { sessionStorage.setItem(ck, JSON.stringify(row)); } catch (e) {} applyBrand(row); }
          else next(i + 1);
        }).catch(function () {});
      })(0);
    }

    document.body.classList.add('sh-has');
    applyCollapsed();

    var navWrap = document.getElementById('navWrap'); if (navWrap) navWrap.style.display = 'none'; // верхнее меню заменяем сайдбаром

    /* Стили выпадающего меню контуров — встраиваем из JS (устойчиво к кэшу CSS) */
    (function () {
      if (document.getElementById('shFlyStyle')) return;
      var st = document.createElement('style'); st.id = 'shFlyStyle';
      st.textContent =
        '.sh-side .sh-group{position:relative}' +
        '.sh-side .sh-group-body{position:absolute;left:100%;top:0;margin-left:6px;min-width:240px;max-width:340px;max-height:76vh;overflow:auto;background:var(--surface);border:1px solid var(--border);border-radius:12px;box-shadow:0 14px 34px rgba(15,23,42,.18);padding:6px;display:none;z-index:970}' +
        '.sh-side .sh-group.open .sh-group-body{display:block}' +
        '@media(max-width:680px){.sh-side .sh-group-body{position:static;left:auto;margin-left:0;box-shadow:none;border:0;border-radius:0;padding:2px 0 6px;min-width:0;max-width:none;max-height:none}}';
      document.head.appendChild(st);
    })();

    if (g.AppCatalog && g.AppCatalog.apps) build(g.AppCatalog);
    else { var s = document.createElement('script'); s.src = ROOT + 'assets/js/catalog.js?v=' + CATALOG_V; s.onload = function () { build(g.AppCatalog); }; document.head.appendChild(s); }
    resolveBrand();
    try {
      if (!document.querySelector('link[rel="manifest"]')) { var lk = document.createElement('link'); lk.rel = 'manifest'; lk.href = ROOT + 'manifest.webmanifest'; document.head.appendChild(lk); }
      if ('serviceWorker' in navigator && location.protocol === 'https:') { navigator.serviceWorker.register(ROOT + 'sw.js', { scope: ROOT }).catch(function () {}); }
    } catch (e) {}

    document.addEventListener('click', function (e) { if (window.innerWidth <= 768 && e.target.closest && e.target.closest('.sh-item')) document.body.classList.remove('sh-open'); });
  }

  ready(init);
  g.AppShell = { init: init };
})(window);
