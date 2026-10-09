/* ============================================================
   3DMP Service · mobile.js — мини-мобильный режим модулей (W31).
   Показывает нижнюю панель «быстрые действия» (из AppCatalog.quick для
   текущего модуля): переходы, мастера (AppWizards) и RPC-действия с
   офлайн-очередью (AppOffline). Режим: ?mobile=1 или переключатель 📱.
   Авто-загружается из shell.js (на всех страницах apps/).
   ============================================================ */
(function (g) {
  'use strict';
  var PREF = '3dmp:mobile';
  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }
  function toast(t) { if (g.AppUI && g.AppUI.toast) g.AppUI.toast(t); else alert(t); }
  function qs(s, r) { return (r || document).querySelector(s); }

  function ensureStyle() {
    if (document.getElementById('mobStyle')) return;
    var st = document.createElement('style'); st.id = 'mobStyle';
    st.textContent =
      '.mob-fab{position:fixed;left:14px;bottom:14px;z-index:8990;width:46px;height:46px;border-radius:50%;border:1px solid var(--border);background:#fff;box-shadow:0 8px 22px rgba(15,23,42,.2);font-size:1.2rem;cursor:pointer;display:none}' +
      'body.mob .mob-fab{display:inline-flex;align-items:center;justify-content:center}' +
      '.mob-fab.show{display:inline-flex;align-items:center;justify-content:center}' +
      '.mob-bar{position:fixed;left:0;right:0;bottom:0;z-index:8995;background:var(--surface,#fff);border-top:1px solid var(--border);box-shadow:0 -8px 24px rgba(15,23,42,.12);display:flex;gap:8px;padding:8px 10px calc(8px + env(safe-area-inset-bottom));overflow-x:auto;display:none}' +
      'body.mob .mob-bar{display:flex}' +
      '.mob-bar .mb-btn{flex:0 0 auto;display:inline-flex;flex-direction:column;align-items:center;gap:2px;min-width:78px;padding:9px 12px;border:1px solid var(--border);border-radius:12px;background:#fff;color:var(--text);font:600 .74rem/1.1 inherit;cursor:pointer;text-decoration:none;text-align:center}' +
      '.mob-bar .mb-btn:hover{border-color:var(--accent);background:var(--accent-100)}' +
      '.mob-bar .mb-btn .mb-ic{font-size:1.15rem}' +
      '.mob-bar .mb-home{background:var(--accent,#10b981);border-color:var(--accent);color:#fff}' +
      '.mob-hide{position:absolute;right:8px;top:6px;border:0;background:transparent;color:var(--muted);font-size:1rem;cursor:pointer}' +
      'body.mob{padding-bottom:74px}' +
      'body.mob .btn,body.mob .act,body.mob button{min-height:42px}' +
      'body.mob .topsearch{display:none}' +
      'body.mob .mod-info{display:none}' +
      '.mob-form{display:grid;gap:10px}' +
      '.mob-form label{display:block;font-size:.82rem;font-weight:600;margin-bottom:3px}' +
      '.mob-form input{width:100%;padding:11px 12px;border:1px solid var(--border);border-radius:10px;font:inherit;font-size:1rem}';
    document.head.appendChild(st);
  }

  function cat() { return g.AppCatalog || {}; }
  function moduleId() { return (location.pathname.match(/\/apps\/([\w-]+)\//) || [])[1]; }
  function rootPrefix() { return location.pathname.indexOf('/apps/') >= 0 ? '../../' : ''; }
  function quickFor(id) { return (cat().quick && cat().quick[id]) || null; }

  function prefOn() { try { return localStorage.getItem(PREF) === '1'; } catch (e) { return false; } }
  function setPref(on) { try { localStorage.setItem(PREF, on ? '1' : '0'); } catch (e) {} }

  function isMobile() { return document.body.classList.contains('mob'); }

  function ensureOffline() {
    if (g.AppOffline) return Promise.resolve();
    return new Promise(function (res) {
      var sc = document.createElement('script'); sc.src = rootPrefix() + 'assets/js/offline-queue.js?v=1';
      sc.onload = function () { res(); }; sc.onerror = function () { res(); };
      document.head.appendChild(sc);
    });
  }

  function argsFrom(spec, vals) {
    var a = { p_token: (g.Auth && g.Auth.token) ? g.Auth.token() : null };
    if (spec.static) for (var k in spec.static) a[k] = spec.static[k];
    (spec.fields || []).forEach(function (f) {
      var key = (spec.map && spec.map[f.name]) || f.name;
      var v = vals[f.name];
      a[key] = (f.type === 'number') ? (v === '' || v == null ? null : Number(v)) : (v || null);
    });
    return a;
  }

  function runRpcAction(spec) {
    var fields = (spec.fields || []).map(function (f) {
      return { name: f.name, label: f.label || f.name, type: f.type || 'text', required: !!f.req, hint: f.hint };
    });
    g.AppUI.formDialog({ title: spec.label, fields: fields, okText: 'Отправить' }).then(function (vals) {
      if (!vals) return;
      var args = argsFrom(spec, vals);
      var go = function () {
        if (!g.SB) { toast('Нет подключения'); return; }
        if (spec.offline && g.AppOffline && !g.AppOffline.online()) {
          g.AppOffline.add({ rpc: spec.rpc, args: args, label: spec.label }).then(function () { toast('Сохранено офлайн — отправится при связи'); });
          return;
        }
        g.SB.rpc(spec.rpc, args).then(function (r) {
          if (r.error) { toast('Ошибка: ' + r.error.message); return; }
          var row = Array.isArray(r.data) ? r.data[0] : r.data;
          if (row && row.ok === false) { toast(row.message || 'Ошибка'); return; }
          toast('Готово: ' + spec.label);
          if (spec.offline && g.AppOffline) g.AppOffline.flush();
        }).catch(function () {
          if (spec.offline && g.AppOffline) { g.AppOffline.add({ rpc: spec.rpc, args: args, label: spec.label }).then(function () { toast('Сохранено офлайн'); }); }
          else toast('Ошибка сети');
        });
      };
      if (spec.offline) ensureOffline().then(go); else go();
    });
  }

  function renderBar() {
    var bar = qs('#mobBar'); if (!bar) return;
    var id = moduleId(), actions = quickFor(id) || [];
    var home = '<a class="mb-btn mb-home" href="' + rootPrefix() + 'index.html"><span class="mb-ic">🏠</span>Хаб</a>';
    var list = actions.map(function (a, idx) {
      var ic = a.icon || '⚡';
      if (a.wizard) return '<button class="mb-btn" type="button" data-mb="wiz" data-mod="' + a.wizard + '"><span class="mb-ic">' + ic + '</span>' + esc(a.label) + '</button>';
      if (a.rpc) return '<button class="mb-btn" type="button" data-mb="rpc" data-i="' + idx + '"><span class="mb-ic">' + ic + '</span>' + esc(a.label) + '</button>';
      var href = a.href || (rootPrefix() + 'index.html');
      return '<a class="mb-btn" href="' + href + '"><span class="mb-ic">' + ic + '</span>' + esc(a.label) + '</a>';
    }).join('');
    bar.innerHTML = home + list + '<button class="mb-btn" type="button" data-mb="off"><span class="mb-ic">🖥</span>Обычный</button>';
    Array.prototype.forEach.call(bar.querySelectorAll('[data-mb="wiz"]'), function (b) {
      b.addEventListener('click', function () { if (g.AppWizards) g.AppWizards.open(b.getAttribute('data-mod')); else location.href = '../' + b.getAttribute('data-mod') + '/index.html'; });
    });
    Array.prototype.forEach.call(bar.querySelectorAll('[data-mb="rpc"]'), function (b) {
      b.addEventListener('click', function () { runRpcAction(actions[Number(b.getAttribute('data-i'))]); });
    });
    var off = bar.querySelector('[data-mb="off"]');
    if (off) off.addEventListener('click', function () { disable(); });
  }

  function enable() { document.body.classList.add('mob'); setPref(true); renderBar(); }
  function disable() { document.body.classList.remove('mob'); setPref(false); }
  function toggle() { if (isMobile()) disable(); else enable(); }

  function overlay() {
    if (qs('#mobBar')) return;
    var bar = document.createElement('div'); bar.id = 'mobBar'; bar.className = 'mob-bar'; document.body.appendChild(bar);
    var fab = document.createElement('button'); fab.id = 'mobFab'; fab.className = 'mob-fab'; fab.type = 'button'; fab.title = 'Мобильный режим'; fab.textContent = '📱';
    fab.addEventListener('click', function () { enable(); toast('Мобильный режим включён'); });
    document.body.appendChild(fab);
    // показать FAB вне мобильного режима, если есть быстрые действия/модуль
    if (moduleId()) fab.classList.add('show');
  }

  function pwa() {
    var deferred = null;
    g.addEventListener('beforeinstallprompt', function (e) { e.preventDefault(); deferred = e; });
    g.__mobInstall = function () { if (deferred) { deferred.prompt(); deferred = null; } };
  }

  function init() {
    if (!moduleId()) return; // только внутри модулей apps/
    ensureStyle(); overlay(); pwa();
    if (location.search.indexOf('mobile=1') >= 0 || prefOn()) enable();
    // каталог может подгрузиться позже — обновим панель
    if (!cat().quick) setTimeout(function () { if (isMobile()) renderBar(); }, 600);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
  g.AppMobile = { enable: enable, disable: disable, toggle: toggle, isMobile: isMobile, quick: quickFor, render: renderBar };
})(window);
