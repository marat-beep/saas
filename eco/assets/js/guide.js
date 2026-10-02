/* ============================================================
   3DMP · Гид по системе
   Кнопка + модальное окно. Строится из window.AppCatalog,
   поэтому автоматически обновляется при изменении каталога.
   Подключение на странице: catalog.js + guide.js.
   Открыть можно: кликом на ❓, по кнопке [data-guide] или openGuide().
   ============================================================ */
(function () {
  'use strict';

  var inApp = /[\\/]apps[\\/]/.test(location.pathname) || /\/apps\//.test(location.pathname.replace(/\\/g, '/'));
  var base = inApp ? '../../' : '';

  function el(tag, cls, html) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html != null) e.innerHTML = html;
    return e;
  }

  function injectCss() {
    if (document.getElementById('guideStyle')) return;
    var css = ''
      + '.gd-fab{position:fixed;right:16px;bottom:16px;z-index:9998;display:flex;align-items:center;gap:8px;'
      + 'background:linear-gradient(135deg,#0f172a,#334155);color:#fff;border:none;border-radius:999px;'
      + 'padding:11px 16px;font:700 .82rem/1 -apple-system,Segoe UI,Roboto,sans-serif;cursor:pointer;'
      + 'box-shadow:0 10px 26px rgba(15,23,42,.35);}'
      + '.gd-fab:hover{transform:translateY(-2px);}'
      + '.gd-overlay{position:fixed;inset:0;z-index:9999;background:rgba(15,23,42,.55);'
      + 'display:flex;align-items:center;justify-content:center;padding:20px;opacity:0;transition:opacity .2s;}'
      + '.gd-overlay.open{opacity:1;}'
      + '.gd-modal{width:100%;max-width:720px;max-height:88vh;overflow:hidden;background:#fff;border-radius:18px;'
      + 'display:flex;flex-direction:column;box-shadow:0 30px 80px rgba(0,0,0,.4);'
      + 'font:400 .9rem/1.5 -apple-system,Segoe UI,Roboto,sans-serif;color:#0f172a;}'
      + '.gd-head{background:linear-gradient(135deg,#064e3b,#10b981);color:#fff;padding:16px 20px;display:flex;align-items:center;gap:12px;}'
      + '.gd-head b{font-size:1.05rem;} .gd-head .s{font-size:.72rem;opacity:.85;}'
      + '.gd-x{margin-left:auto;width:32px;height:32px;border-radius:50%;border:none;background:rgba(255,255,255,.18);color:#fff;cursor:pointer;font-size:1rem;}'
      + '.gd-x:hover{background:rgba(255,255,255,.3);}'
      + '.gd-body{padding:18px 20px;overflow-y:auto;}'
      + '.gd-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:18px;}'
      + '.gd-stat{background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:12px;text-align:center;}'
      + '.gd-stat b{display:block;font-size:1.4rem;} .gd-stat span{font-size:.64rem;color:#64748b;text-transform:uppercase;letter-spacing:.4px;}'
      + '.gd-legend{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:16px;}'
      + '.gd-leg{display:inline-flex;align-items:center;gap:6px;font-size:.72rem;font-weight:600;background:#f8fafc;border:1px solid #e2e8f0;border-radius:999px;padding:4px 10px;}'
      + '.gd-leg i{width:9px;height:9px;border-radius:50%;display:inline-block;}'
      + '.gd-sec{font-size:.74rem;font-weight:800;text-transform:uppercase;letter-spacing:.5px;color:#475569;margin:18px 0 10px;display:flex;align-items:center;gap:8px;}'
      + '.gd-apps{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:8px;}'
      + '.gd-app{display:flex;gap:9px;align-items:flex-start;padding:9px 11px;border:1px solid #e2e8f0;border-radius:10px;text-decoration:none;color:#0f172a;transition:.15s;}'
      + '.gd-app:hover{border-color:#10b981;background:#f0fdf4;transform:translateY(-1px);}'
      + '.gd-app .ic{font-size:1.1rem;line-height:1.2;}'
      + '.gd-app .t{font-weight:700;font-size:.78rem;}'
      + '.gd-app .id{font-size:.62rem;color:#94a3b8;font-family:ui-monospace,monospace;}'
      + '.gd-scn{display:flex;gap:10px;padding:10px 0;border-bottom:1px solid #f1f5f9;}'
      + '.gd-scn:last-child{border-bottom:none;}'
      + '.gd-scn .si{font-size:1.2rem;} .gd-scn b{font-size:.8rem;} .gd-scn p{font-size:.74rem;color:#475569;margin-top:2px;}'
      + '.gd-foot{padding:12px 20px;border-top:1px solid #e2e8f0;font-size:.68rem;color:#94a3b8;text-align:center;}'
      + '.gd-search{width:100%;padding:11px 14px;border:2px solid #e2e8f0;border-radius:10px;font:400 .86rem/1.3 inherit;margin-bottom:6px;}'
      + '.gd-search:focus{outline:none;border-color:#10b981;}'
      + '.gd-group.hide{display:none;}'
      + '.gd-app.hide{display:none;}'
      + '.gd-empty{color:#94a3b8;font-size:.8rem;padding:14px 0;text-align:center;}'
      + 'html[data-theme="dark"] .gd-modal{background:#111827;color:#e5e7eb;}'
      + 'html[data-theme="dark"] .gd-stat{background:#0f172a;border-color:#1f2937;}'
      + 'html[data-theme="dark"] .gd-app{border-color:#1f2937;color:#e5e7eb;}'
      + 'html[data-theme="dark"] .gd-app:hover{background:#052e16;}'
      + 'html[data-theme="dark"] .gd-search{background:#0f172a;border-color:#1f2937;color:#e5e7eb;}'
      + 'html[data-theme="dark"] .gd-foot{border-color:#1f2937;}'
      + 'html[data-theme="dark"] .gd-sec{color:#94a3b8;}'
      + '@media(max-width:560px){.gd-modal{max-height:94vh;}.gd-apps{grid-template-columns:1fr;}}';
    var style = document.createElement('style');
    style.id = 'guideStyle';
    style.textContent = css;
    document.head.appendChild(style);
  }

  function appLink(a, groupAudience) {
    var aud = a.audience || groupAudience;
    return '<a class="gd-app" href="' + base + a.href + '" data-audience="' + aud + '">'
      + '<span class="ic">' + a.icon + '</span>'
      + '<span><span class="t">' + a.title + '</span><br><span class="id">' + a.id + '</span></span></a>';
  }

  var overlay = null;

  function build() {
    var C = window.AppCatalog;
    if (!C) return null;

    overlay = el('div', 'gd-overlay');
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');

    var modal = el('div', 'gd-modal');
    var head = el('div', 'gd-head',
      '<span style="font-size:1.5rem;">🧭</span>'
      + '<div><b>Гид по системе 3DMP</b><div class="s">Экосистема цифровых сервисов · версия ' + C.version + '</div></div>'
      + '<button class="gd-x" type="button" data-theme-toggle title="Светлая / тёмная тема" style="margin-left:auto;">🌙</button>'
      + '<button class="gd-x" type="button" aria-label="Закрыть">✕</button>');
    var themeBtn = head.querySelector('[data-theme-toggle]');
    if (themeBtn) themeBtn.addEventListener('click', function () { if (window.toggleTheme) window.toggleTheme(); });
    modal.appendChild(head);

    var body = el('div', 'gd-body');

    var stats = ''
      + '<div class="gd-stat"><b>' + C.countApps() + '</b><span>Приложений</span></div>'
      + '<div class="gd-stat"><b>' + C.countModules() + '</b><span>Модулей SaaS</span></div>'
      + '<div class="gd-stat"><b>' + C.countGroups() + '</b><span>Групп</span></div>';
    body.appendChild(el('div', 'gd-stats', stats));

    body.appendChild(el('p', null,
      'Единая экосистема для производственной компании: расчёт и подбор, кабинет заказчика, производственный контур, CRM, партнёрские кабинеты и облачная платформа (SaaS + маркетплейс + платежи). Каждое приложение открывается из этого окна и из хаба.'));

    var search = el('input', 'gd-search');
    search.type = 'search';
    search.placeholder = 'Поиск: название или номер (A1, B8, P1, маркетплейс)…';
    body.appendChild(search);

    body.appendChild(el('div', 'gd-sec', '🎨 Цвета аудиторий'));
    body.appendChild(el('div', 'gd-legend', (C.audienceLegend || []).map(function (l) {
      return '<span class="gd-leg"><i style="background:' + l.color + '"></i>' + l.label + '</span>';
    }).join('')));

    C.groups.forEach(function (g) {
      var grp = el('div', 'gd-group');
      grp.appendChild(el('div', 'gd-sec', g.icon + ' ' + g.title + ' <span style="color:#94a3b8;font-weight:600;text-transform:none;letter-spacing:0;">· ' + g.apps.length + '</span>'));
      grp.appendChild(el('div', 'gd-apps', g.apps.map(function (a) { return appLink(a, g.audience); }).join('')));
      body.appendChild(grp);
    });

    var empty = el('div', 'gd-empty hide', 'Ничего не найдено. Попробуйте другой запрос.');
    empty.id = 'gdEmpty';
    body.appendChild(empty);

    search.addEventListener('input', function () {
      var q = search.value.trim().toLowerCase();
      var any = false;
      body.querySelectorAll('.gd-group').forEach(function (grp) {
        var shown = 0;
        grp.querySelectorAll('.gd-app').forEach(function (a) {
          var match = !q || a.textContent.toLowerCase().indexOf(q) >= 0;
          a.classList.toggle('hide', !match);
          if (match) shown++;
        });
        grp.classList.toggle('hide', shown === 0);
        if (shown > 0) any = true;
      });
      empty.classList.toggle('hide', any || !q);
    });

    body.appendChild(el('div', 'gd-sec', '🔗 Типовые сценарии'));
    body.appendChild(el('div', null, (C.scenarios || []).map(function (s) {
      return '<div class="gd-scn"><span class="si">' + s.icon + '</span><div><b>' + s.title + '</b><p>' + s.steps + '</p></div></div>';
    }).join('')));

    modal.appendChild(body);
    modal.appendChild(el('div', 'gd-foot', 'Обновлено: ' + C.updated + ' · Гид строится автоматически из каталога системы'));

    overlay.appendChild(modal);

    head.querySelector('.gd-x').addEventListener('click', close);
    overlay.addEventListener('click', function (e) { if (e.target === overlay) close(); });

    return overlay;
  }

  function open() {
    injectCss();
    if (!overlay) overlay = build();
    if (!overlay) return;
    if (!overlay.parentNode) document.body.appendChild(overlay);
    requestAnimationFrame(function () { overlay.classList.add('open'); });
    document.addEventListener('keydown', onEsc);
  }
  function close() {
    if (overlay) overlay.classList.remove('open');
    document.removeEventListener('keydown', onEsc);
  }
  function onEsc(e) { if (e.key === 'Escape') close(); }

  function makeFab() {
    if (document.querySelector('.gd-fab')) return;
    var fab = el('button', 'gd-fab', '❓ <span>Гид</span>');
    fab.type = 'button';
    fab.title = 'Гид по системе 3DMP';
    fab.addEventListener('click', open);
    document.body.appendChild(fab);
  }

  function bindTriggers() {
    document.querySelectorAll('[data-guide], #guideBtn').forEach(function (b) {
      b.addEventListener('click', function (e) { e.preventDefault(); open(); });
    });
  }

  window.openGuide = open;

  function start() { injectCss(); makeFab(); bindTriggers(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
