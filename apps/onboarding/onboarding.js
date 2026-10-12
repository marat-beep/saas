/* ============================================================
   3DMP Service · apps/onboarding — Мастер настройки + демо-данные (0207)
   Готовность справочников, шаги мастера, включение модулей, демо-сид/сброс.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null;

  var MODLBL = { refs: 'Справочники', hr: 'Персонал', orders: 'Заявки', production: 'Производство', qc: 'Качество', service: 'Сервис', projects: 'Проекты', docs: 'Документы', courses: 'Обучение' };

  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#msg'); if (!e) return; e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function showTab(s) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === s); });
    $$('.screen').forEach(function (x) { x.classList.toggle('active', x.id === 'scr-' + s); });
    if (s === 'ready') loadReady();
    if (s === 'modules') loadModules();
    if (s === 'demo') loadDemo();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadReady() {
    return rpc('app_setup_readiness', { p_token: token }).then(function (rows) {
      rows = rows || [];
      var ready = rows.filter(function (r) { return r.ready; }).length;
      $('#kpis').innerHTML = cell('Пунктов', rows.length) + cell('Готово', ready) + cell('Прогресс', rows.length ? Math.round(100 * ready / rows.length) + '%' : '0%');
      $('#ready').innerHTML = rows.length ? rows.map(function (r) {
        var pct = r.target ? Math.min(100, Math.round(100 * r.cnt / r.target)) : (r.cnt ? 100 : 0);
        return '<div class="kvr"><b>' + esc(r.label) + '</b><span class="note">' + esc(r.module) + '</span>' +
          '<span style="flex:1;max-width:240px;" class="bar"><i style="width:' + pct + '%"></i></span>' +
          '<span class="badge ' + (r.ready ? 'done' : 'in_progress') + '">' + r.cnt + ' / ' + r.target + (r.ready ? ' ✔' : '') + '</span>' +
          '<a class="act" href="../../' + esc(r.link) + '">Перейти ↗</a></div>';
      }).join('') : '<span class="note">—</span>';
    }).catch(function (e) { $('#ready').innerHTML = '<span class="note">' + esc(e.message) + '</span>'; });
  }

  function loadModules() {
    return rpc('app_tenant_modules_list', { p_token: token }).then(function (rows) {
      rows = rows || [];
      if (!rows.length) { $('#modules').innerHTML = '<span class="note">Нет данных о модулях.</span>'; return; }
      $('#modules').innerHTML = rows.map(function (m) {
        var on = m.enabled !== false && m.enabled !== 'false';
        return '<div class="kvr"><b>' + esc(m.title || m.module || m.id) + '</b>' +
          '<span class="m"><button class="act ' + (on ? '' : '') + '" data-mod="' + esc(m.module || m.id) + '" data-on="' + (on ? 'false' : 'true') + '">' + (on ? 'Отключить' : 'Включить') + '</button>' +
          '<span class="badge ' + (on ? 'done' : 'cancelled') + '">' + (on ? 'включён' : 'выключен') + '</span></span></div>';
      }).join('');
      $$('#modules [data-mod]').forEach(function (b) {
        b.addEventListener('click', function () {
          rpc('app_tenant_module_set', { p_token: token, p_module: b.dataset.mod, p_enabled: b.dataset.on === 'true' })
            .then(function () { ui.toast('Модуль обновлён'); loadModules(); })
            .catch(function (e) { ui.toast('Ошибка: ' + e.message); });
        });
      });
    }).catch(function (e) { $('#modules').innerHTML = '<span class="note">' + esc(e.message) + '</span>'; });
  }

  function loadDemo() {
    return rpc('app_demo_status', { p_token: token }).then(function (rows) {
      rows = rows || [];
      var total = rows.reduce(function (s, r) { return s + (Number(r.rows) || 0); }, 0);
      $('#demo').innerHTML = '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Модуль</th><th class="num">Демо-строк</th><th></th></tr></thead><tbody>' +
        rows.map(function (r) {
          return '<tr><td>' + esc(MODLBL[r.module] || r.label || r.module) + '</td><td class="num">' + (r.rows || 0) + '</td>' +
            '<td style="white-space:nowrap;"><button class="act" data-seed="' + esc(r.module) + '">＋ Заполнить</button>' +
            (r.rows > 0 ? '<button class="act danger" data-reset="' + esc(r.module) + '">✕ Удалить</button>' : '') + '</td></tr>';
        }).join('') + '</tbody><tfoot><tr><th>Итого</th><th class="num">' + total + '</th><th></th></tr></tfoot></table></div>';
      $$('#demo [data-seed]').forEach(function (b) { b.addEventListener('click', function () { demoOp('app_demo_seed', b.dataset.seed, 'Демо добавлены'); }); });
      $$('#demo [data-reset]').forEach(function (b) { b.addEventListener('click', function () {
        if (!window.confirm('Удалить демо-данные модуля «' + (MODLBL[b.dataset.reset] || b.dataset.reset) + '»?')) return;
        demoOp('app_demo_reset', b.dataset.reset, 'Демо удалены');
      }); });
    }).catch(function (e) { $('#demo').innerHTML = '<span class="note">' + esc(e.message) + '</span>'; });
  }
  function demoOp(fn, mod, okMsg) {
    rpc(fn, { p_token: token, p_module: mod }).then(function (r) { var x = r && r[0]; ui.toast((x && x.message) || okMsg, x && x.ok ? 'ok' : 'err'); loadDemo(); loadReady(); });
  }
  $('#seedAll').addEventListener('click', function () { demoOp('app_demo_seed', 'all', 'Демо добавлены'); });
  $('#resetAll').addEventListener('click', function () {
    if (!window.confirm('Удалить ВСЕ демо-данные (по флагу is_demo)? Реальные данные не затрагиваются.')) return;
    demoOp('app_demo_reset', 'all', 'Демо удалены');
  });

    /* ---------- Мастер настройки (отдельная процедура) ---------- */
  function runWizard() { window.AppSetupWizard.open(token, { onDone: function () { loadReady(); loadDemo(); } }); }
  $('#wizBtn').addEventListener('click', runWizard);
  if (/[?#].*wizard/i.test(location.href)) setTimeout(runWizard, 400);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!(s.role === 'admin' || s.role === 'owner')) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.'); return; }
    loadReady();
  });
})();
