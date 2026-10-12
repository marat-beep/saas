/* ============================================================
   3DMP Service · apps/onboarding — Мастер настройки + демо + конфигурация (0207/0208).
   UI использует каталог (иконки/названия/контуры/пояснения).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, enabledMap = {};

  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function cat() { return (window.AppCatalog && window.AppCatalog.apps) ? window.AppCatalog : { apps: [], groups: [] }; }
  function appById(id) { return cat().apps.filter(function (a) { return a.id === id; })[0] || null; }
  function groupById(id) { return (cat().groups || []).filter(function (g) { return g.id === id; })[0] || null; }
  function iconOf(id) { var a = appById(id); return a ? a.icon : '•'; }
  function titleOf(id) { var a = appById(id); return a ? a.title : id; }
  function hintOf(id) { var a = appById(id); return a ? (a.desc || a.purpose || '') : ''; }

  function showTab(s) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === s); });
    $$('.screen').forEach(function (x) { x.classList.toggle('active', x.id === 'scr-' + s); });
    if (s === 'ready') loadReady();
    if (s === 'modules') loadModules();
    if (s === 'demo') loadDemo();
    if (s === 'config') loadConfig();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });
  var modTimer = null;
  if ($('#modFilter')) $('#modFilter').addEventListener('input', function () { if (modTimer) clearTimeout(modTimer); modTimer = setTimeout(loadModules, 250); });

  function loadReady() {
    return rpc('app_setup_readiness', { p_token: token }).then(function (rows) {
      rows = rows || [];
      var ready = rows.filter(function (r) { return r.ready; }).length;
      $('#kpis').innerHTML = cell('Пунктов', rows.length) + cell('Готово', ready) + cell('Прогресс', rows.length ? Math.round(100 * ready / rows.length) + '%' : '0%');
      $('#ready').innerHTML = rows.length ? rows.map(function (r) {
        var pct = r.target ? Math.min(100, Math.round(100 * r.cnt / r.target)) : (r.cnt ? 100 : 0);
        var hint = hintOf(r.module);
        return '<div class="kvr" style="display:flex;flex-wrap:nowrap;align-items:center;gap:10px;">' +
          '<span style="flex:0 0 24px;text-align:center;font-size:1.15rem;">' + iconOf(r.module) + '</span>' +
          '<div style="flex:1 1 auto;min-width:0;overflow:hidden;">' +
          '<b>' + esc(r.label) + '</b>' +
          '<div class="note" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">' + esc(r.module) + (hint ? ' · ' + esc(hint) : '') + '</div></div>' +
          '<span style="flex:0 0 170px;height:8px;background:#e5e7eb;border-radius:6px;overflow:hidden;"><i style="display:block;height:100%;width:' + pct + '%;background:var(--accent,#10b981);"></i></span>' +
          '<span class="badge ' + (r.ready ? 'done' : 'in_progress') + '" style="flex:0 0 auto;">' + r.cnt + ' / ' + r.target + (r.ready ? ' ✔' : '') + '</span>' +
          '<a class="act" href="../../' + esc(r.link) + '" style="flex:0 0 auto;">Перейти ↗</a></div>';
      }).join('') : '<span class="note">—</span>';
    }).catch(function (e) { $('#ready').innerHTML = '<span class="note">' + esc(e.message) + '</span>'; });
  }

  function loadModules() {
    return Promise.all([
      rpc('app_tenant_modules_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_org_profiles_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      (r[0] || []).forEach(function (m) { enabledMap[m.module] = m.enabled !== false; });
      var profiles = r[1] || [];
      var c = cat();
      var q = (($('#modFilter') && $('#modFilter').value) || '').trim().toLowerCase();
      var appsAll = (c.apps || []).filter(function (a) { return a.href && a.href.indexOf('apps/') === 0; });
      var apps = appsAll.slice();
      if (q) apps = apps.filter(function (a) { return ((a.title || '') + ' ' + (a.desc || '') + ' ' + (a.purpose || '') + ' ' + (a.id || '')).toLowerCase().indexOf(q) >= 0; });
      var byGroup = {};
      apps.forEach(function (a) { var g = a.group || '_'; (byGroup[g] = byGroup[g] || []).push(a); });
      var order = (c.groups || []).map(function (g) { return g.id; }).filter(function (id) { return byGroup[id]; });
      if (byGroup['_']) order.push('_');

      var profBar = '<div class="toolbar" style="gap:8px;flex-wrap:wrap;margin-bottom:6px;">' +
        '<span class="note">Профиль организации:</span>' +
        '<select id="modProfile" style="padding:8px;border:1px solid var(--border);border-radius:9px;">' +
        (profiles.length ? profiles.map(function (p) { return '<option value="' + esc(p.code) + '">' + esc(p.name) + '</option>'; }).join('') : '<option value="">— нет профилей —</option>') +
        '</select>' +
        '<select id="modMode" style="padding:8px;border:1px solid var(--border);border-radius:9px;"><option value="set">Набор (выключить лишнее)</option><option value="add">Добавить к текущим</option></select>' +
        '<button class="btn" id="applyProfile" style="width:auto;padding:8px 14px;">Применить профиль</button>' +
        '<span class="note" id="modMsg"></span></div>';

      var html = profBar;
      order.forEach(function (gid) {
        var g = groupById(gid) || { icon: '🗂', title: 'Прочее' };
        var items = byGroup[gid] || [];
        var onCount = items.filter(function (a) { return enabledMap[a.id] !== false; }).length;
        var allOn = onCount === items.length && items.length > 0;
        html += '<div class="note" style="margin:14px 0 4px;font-weight:700;display:flex;align-items:center;gap:8px;flex-wrap:wrap;">' + g.icon + ' ' + esc(g.title) +
          ' <span class="badge">' + onCount + ' / ' + items.length + '</span>' +
          '<button class="act" data-grp-on="' + esc(gid) + '">Весь контур: вкл</button>' +
          '<button class="act" data-grp-off="' + esc(gid) + '">выкл</button></div>';
        html += items.map(function (a) {
          var on = enabledMap[a.id] !== false;
          return '<div class="kvr" style="align-items:flex-start;"><span style="font-size:1.35rem;line-height:1.2;">' + a.icon + '</span>' +
            '<div style="flex:1;min-width:0;"><b>' + esc(a.title) + '</b>' +
            '<div class="note" style="font-size:.76rem;">' + esc(a.desc || a.purpose || '') + '</div></div>' +
            '<span class="m"><button class="act" data-cfg="' + esc(a.id) + '">Настроить</button>' +
            '<button class="act ' + (on ? 'danger' : '') + '" data-mod="' + esc(a.id) + '" data-on="' + (on ? 'false' : 'true') + '">' + (on ? 'Отключить' : 'Включить') + '</button>' +
            '<span class="badge ' + (on ? 'done' : 'cancelled') + '">' + (on ? 'включён' : 'выключен') + '</span></span></div>';
        }).join('');
      });
      $('#modules').innerHTML = html || '<span class="note">Каталог не загружен.</span>';
      var allIds = appsAll.map(function (a) { return a.id; });
      $$('#modules [data-cfg]').forEach(function (b) { b.addEventListener('click', function () { if (window.AppSetupWizard) window.AppSetupWizard.open(token, { module: b.dataset.cfg, onDone: loadModules }); }); });
      $$('#modules [data-mod]').forEach(function (b) {
        b.addEventListener('click', function () {
          rpc('app_tenant_module_set', { p_token: token, p_module: b.dataset.mod, p_enabled: b.dataset.on === 'true' })
            .then(function () { ui.toast('Модуль обновлён'); enabledMap[b.dataset.mod] = b.dataset.on === 'true'; loadModules(); })
            .catch(function (e) { ui.toast('Ошибка: ' + e.message); });
        });
      });
      function groupIds(gid) { return (byGroup[gid] || []).map(function (a) { return a.id; }); }
      $$('#modules [data-grp-on]').forEach(function (b) { b.addEventListener('click', function () { bulk(groupIds(b.dataset.grpOn), true); }); });
      $$('#modules [data-grp-off]').forEach(function (b) { b.addEventListener('click', function () { bulk(groupIds(b.dataset.grpOff), false); }); });
      function bulk(ids, en) { rpc('app_modules_set_bulk', { p_token: token, p_modules: ids, p_enabled: en }).then(function (rr) { var x = rr && rr[0]; ui.toast((x && x.message) || 'Готово', x && x.ok ? 'ok' : 'err'); loadModules(); }).catch(function (e) { ui.toast('Ошибка: ' + e.message); }); }
      var apb = $('#applyProfile');
      if (apb) apb.addEventListener('click', function () {
        var code = ($('#modProfile') && $('#modProfile').value) || '';
        if (!code) { ui.toast('Нет профилей'); return; }
        var mode = ($('#modMode') && $('#modMode').value) || 'set';
        if (mode === 'set' && !window.confirm('Применить профиль «' + code + '»? Модули вне профиля будут отключены.')) return;
        rpc('app_org_profile_apply', { p_token: token, p_code: code, p_all: mode === 'set' ? allIds : null })
          .then(function (rr) { var x = rr && rr[0]; ui.toast((x && x.message) || 'Профиль применён', x && x.ok ? 'ok' : 'err'); loadModules(); })
          .catch(function (e) { ui.toast('Ошибка: ' + e.message); });
      });
    }).catch(function (e) { $('#modules').innerHTML = '<span class="note">' + esc(e.message) + '</span>'; });
  }

  function loadDemo() {
    return rpc('app_demo_status', { p_token: token }).then(function (rows) {
      rows = rows || [];
      var total = rows.reduce(function (s, r) { return s + (Number(r.rows) || 0); }, 0);
      $('#demo').innerHTML = '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Модуль</th><th class="num">Демо-строк</th><th></th></tr></thead><tbody>' +
        rows.map(function (r) {
          return '<tr><td>' + iconOf(r.module) + ' ' + esc(titleOf(r.module)) + '</td><td class="num">' + (r.rows || 0) + '</td>' +
            '<td style="white-space:nowrap;"><button class="act" data-seed="' + esc(r.module) + '">＋ Заполнить</button>' +
            (r.rows > 0 ? '<button class="act danger" data-reset="' + esc(r.module) + '">✕ Удалить</button>' : '') + '</td></tr>';
        }).join('') + '</tbody><tfoot><tr><th>Итого</th><th class="num">' + total + '</th><th></th></tr></tfoot></table></div>';
      $$('#demo [data-seed]').forEach(function (b) { b.addEventListener('click', function () { demoOp('app_demo_seed', b.dataset.seed); }); });
      $$('#demo [data-reset]').forEach(function (b) { b.addEventListener('click', function () { if (!window.confirm('Удалить демо-данные модуля «' + titleOf(b.dataset.reset) + '»?')) return; demoOp('app_demo_reset', b.dataset.reset); }); });
    }).catch(function (e) { $('#demo').innerHTML = '<span class="note">' + esc(e.message) + '</span>'; });
  }
  function demoOp(fn, mod) { rpc(fn, { p_token: token, p_module: mod }).then(function (r) { var x = r && r[0]; ui.toast((x && x.message) || '', x && x.ok ? 'ok' : 'err'); loadDemo(); loadReady(); }); }
  $('#seedAll').addEventListener('click', function () { demoOp('app_demo_seed', 'all'); });
  $('#resetAll').addEventListener('click', function () { if (!window.confirm('Удалить ВСЕ демо-данные (по флагу is_demo)? Реальные данные не затрагиваются.')) return; demoOp('app_demo_reset', 'all'); });

  /* ---------- Мастер настройки (отдельная процедура) ---------- */
  function runWizard() { window.AppSetupWizard.open(token, { onDone: function () { loadReady(); loadDemo(); loadModules(); } }); }
  $('#wizBtn').addEventListener('click', runWizard);
  if (/[?#].*wizard/i.test(location.href)) setTimeout(runWizard, 400);

  /* ---------- Конфигурация: экспорт/импорт ---------- */
  function loadConfig() { var m = $('#cfgMsg'); if (m) m.textContent = ''; }
  $('#cfgExport').addEventListener('click', function () {
    rpc('app_config_export', { p_token: token }).then(function (r) {
      var cfg = r && r[0] && r[0].config; if (!cfg) { ui.toast('Нет данных'); return; }
      var blob = new Blob([JSON.stringify(cfg, null, 2)], { type: 'application/json' });
      var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = '3dmp-config-' + new Date().toISOString().slice(0, 10) + '.json';
      document.body.appendChild(a); a.click(); a.remove(); ui.toast('Конфигурация выгружена');
    }).catch(function (e) { ui.toast('Ошибка: ' + e.message); });
  });
  $('#cfgFile').addEventListener('change', function () {
    var f = this.files && this.files[0]; if (!f) return;
    var rd = new FileReader();
    rd.onload = function () {
      var cfg; try { cfg = JSON.parse(rd.result); } catch (e) { ui.toast('Некорректный JSON'); return; }
      rpc('app_config_import', { p_token: token, p_config: cfg }).then(function (r) { var x = r && r[0]; ui.toast((x && x.message) || '', x && x.ok ? 'ok' : 'err'); loadModules(); loadReady(); loadConfig(); })
        .catch(function (e) { ui.toast('Ошибка: ' + e.message); });
    };
    rd.readAsText(f); this.value = '';
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!(s.role === 'admin' || s.role === 'owner')) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { ui.toast('Supabase не подключён.'); return; }
    loadReady();
  });
})();
