/* ============================================================
   3DMP · shell.js — каркас навигации uCoz-типа (глобальный левый сайдбар).
   Меню строится из assets/js/catalog.js (группы-контуры → модули).
   Цвета — существующие переменные app.css (.sh-*). Требует auth.js.
   ============================================================ */
(function (g) {
  'use strict';
  var SELF = document.currentScript;
  var CATALOG_V = '68'; // версия каталога для внешних страниц

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

    /* ---------- Системный поиск в шапке ---------- */
    (function globalSearch() {
      if (!bar || document.getElementById('gsWrap')) return;
      var box = document.createElement('div');
      box.id = 'gsWrap';
      box.style.cssText = 'position:relative;flex:1;max-width:440px;margin:0 10px;min-width:120px;';
      box.innerHTML = '<input id="gsInput" type="search" placeholder="Поиск по системе: заявки, станки, гарантии, БЗ…" autocomplete="off" ' +
        'style="width:100%;padding:9px 12px;border:1px solid var(--border);border-radius:10px;background:#fff;font:inherit;font-size:.86rem;">' +
        '<div id="gsDrop" style="display:none;position:absolute;left:0;right:0;top:calc(100% + 6px);z-index:960;background:var(--surface,#fff);border:1px solid var(--border);border-radius:12px;box-shadow:0 14px 34px rgba(15,23,42,.18);max-height:60vh;overflow-y:auto;"></div>';
      var spacer = bar.querySelector('.spacer');
      if (spacer) bar.insertBefore(box, spacer); else bar.appendChild(box);
      var input = box.querySelector('#gsInput'), drop = box.querySelector('#gsDrop'), timer = null, lastQ = '';
      var ICON = { kb: '📚', request: '🎫', equipment: '🏭', customer: '🏢', order: '📦' };
      function hide() { drop.style.display = 'none'; }
      function run() {
        var q = input.value.trim(); if (q.length < 2) { hide(); return; }
        if (q === lastQ) return; lastQ = q;
        if (!g.SB || !g.Auth || !g.Auth.token()) return;
        g.SB.rpc('app_global_search', { p_token: g.Auth.token(), p_q: q, p_limit: 12 }).then(function (r) {
          if (r.error) { hide(); return; }
          var rows = r.data || [];
          if (!rows.length) { drop.innerHTML = '<div style="padding:12px;color:#64748b;font-size:.82rem;">Ничего не найдено</div>'; drop.style.display = ''; return; }
          drop.innerHTML = rows.map(function (x) {
            return '<a href="' + ROOT + esc(x.url) + '" style="display:flex;gap:8px;align-items:center;padding:9px 12px;text-decoration:none;color:inherit;border-bottom:1px solid var(--border);">' +
              '<span>' + (ICON[x.kind] || '•') + '</span><span style="flex:1;min-width:0;"><b style="font-size:.84rem;">' + esc(x.title || '') + '</b>' +
              '<div style="font-size:.74rem;color:#64748b;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">' + esc(x.subtitle || '') + '</div></span></a>';
          }).join('');
          drop.style.display = '';
        }).catch(function () { hide(); });
      }
      input.addEventListener('input', function () { if (timer) clearTimeout(timer); timer = setTimeout(run, 300); });
      input.addEventListener('keydown', function (e) { if (e.key === 'Enter') run(); if (e.key === 'Escape') { hide(); input.blur(); } });
      document.addEventListener('click', function (e) { if (!box.contains(e.target)) hide(); });
    })();

    /* Тема: светлая/тёмная (светлая палитра не меняется; тёмная — доп. режим) */
    function applyTheme(t) { document.documentElement.setAttribute('data-theme', t); try { localStorage.setItem('3dmp:theme', t); } catch (e) {} }
    var saved = ''; try { saved = localStorage.getItem('3dmp:theme') || ''; } catch (e) {}
    applyTheme(saved || 'light');
    /* Кнопка темы и остальные кнопки топбара добавляются общим nav.js (единый вид). */

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
