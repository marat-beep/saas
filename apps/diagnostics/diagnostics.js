/* ============================================================
   3DMP Service · apps/diagnostics — диагностика и self-test (P10)
   Проверяет конфигурацию, клиент и ключевые функции. Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, results = [];
  var SCHEMA = '0001…0023 (23 миграции)';

  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#msg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function checks() {
    return [
      ['Конфигурация config.js', function () { var c = window.APP_CONFIG || {}; if (!c.SUPABASE_URL || !c.SUPABASE_ANON_KEY) throw new Error('URL/ключ не заданы'); return c.SUPABASE_URL; }],
      ['supabase-js (CDN)', function () { if (!(window.supabase && window.supabase.createClient)) throw new Error('не загружен'); return 'загружен'; }],
      ['Клиент Supabase', function () { if (!SB) throw new Error(window.SB_ERROR || 'не создан'); return 'создан'; }],
      ['Текущий пользователь', function () { return rpc('app_me', { p_token: token }).then(function (d) { var r = d && d[0]; if (!r) throw new Error('сессия недействительна'); return r.login + ' · ' + r.role; }); }],
      ['Организация (tenant)', function () { return rpc('app_tenant_info', { p_token: token }).then(function (d) { var r = d && d[0]; if (!r) throw new Error('нет данных'); return r.name; }); }],
      ['Заявки', function () { return rpc('app_order_list', { p_token: token }).then(function (d) { return (d || []).length + ' зап.'; }); }],
      ['Экономика / KPI', function () { return rpc('app_economics', { p_token: token }).then(function (d) { if (!d || !d[0]) throw new Error('нет ответа'); return 'ок'; }); }],
      ['Аналитика (app_bi)', function () { return rpc('app_bi', { p_token: token }).then(function (d) { if (!d) throw new Error('нет ответа'); return 'ок'; }); }],
      ['Диспетчерская (MES)', function () { return rpc('app_mes_board', { p_token: token }).then(function (d) { return (d || []).length + ' заданий'; }); }],
      ['Качество / СМК', function () { return rpc('app_quality_kpi', { p_token: token }).then(function (d) { if (!d || !d[0]) throw new Error('нет ответа'); return 'ок'; }); }],
      ['База знаний', function () { return rpc('app_kb_list', { p_token: token }).then(function (d) { return (d || []).length + ' записей'; }); }]
    ];
  }

  function run() {
    results = [];
    var list = checks();
    $('#checks').innerHTML = list.map(function (c, i) { return '<li class="chk wait" id="chk-' + i + '"><span class="mark">…</span><span>' + esc(c[0]) + '</span><span class="t"></span></li>'; }).join('');
    var t0 = performance.now();
    var okCount = 0;
    var seq = Promise.resolve();
    list.forEach(function (c, i) {
      seq = seq.then(function () {
        var s = performance.now();
        return Promise.resolve().then(c[1]).then(function (info) {
          okCount++; mark(i, 'ok', info, performance.now() - s);
        }).catch(function (e) { mark(i, 'err', (e && e.message) || String(e), performance.now() - s); });
      });
    });
    seq.then(function () {
      var dt = Math.round(performance.now() - t0);
      results = { ok: okCount, total: list.length, ms: dt };
      renderKpi();
      msg(okCount === list.length ? 'Все проверки пройдены.' : 'Есть ошибки — см. список.', okCount === list.length ? 'ok' : 'err');
    });
  }
  function mark(i, st, info, ms) {
    var el = document.getElementById('chk-' + i);
    if (!el) return;
    el.className = 'chk ' + st;
    el.querySelector('.mark').textContent = (st === 'ok' ? '✓' : '✕');
    el.querySelector('.t').textContent = (Math.round(ms) + ' мс').toString();
    if (st === 'err') el.querySelector('span:nth-child(2)').textContent = el.querySelector('span:nth-child(2)').textContent + ' — ' + info;
    else if (info) el.querySelector('.t').textContent += ' · ' + info;
  }
  function renderKpi() {
    $('#kpis').innerHTML = kv(results.ok + ' / ' + results.total, 'Проверок пройдено') + kv(results.ms + ' мс', 'Время') +
      kv(esc(me ? me.tenant_name || '—' : '—'), 'Организация') + kv(esc(me ? me.role : '—'), 'Роль');
  }
  function kv(v, l) { return '<div class="kv"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>'; }

  function renderEnv() {
    $('#env').innerHTML =
      row('URL сервиса', location.origin + location.pathname) +
      row('Supabase', (window.APP_CONFIG || {}).SUPABASE_URL || '—') +
      row('Схема БД', SCHEMA) +
      row('Браузер', navigator.userAgent);
  }
  function row(k, v) { return '<div class="chk"><span>' + esc(k) + '</span><span class="t" style="max-width:60%;text-align:right;word-break:break-all;">' + esc(v) + '</span></div>'; }

  $('#run').addEventListener('click', run);
  $('#copy').addEventListener('click', function () {
    var lines = ['3DMP Service · отчёт диагностики', 'Дата: ' + new Date().toLocaleString('ru-RU'), 'Организация: ' + (me ? me.tenant_name : '—')];
    $$('#checks .chk').forEach(function (el) { lines.push(el.querySelector('.mark').textContent + ' ' + el.querySelector('span:nth-child(2)').textContent + ' [' + el.querySelector('.t').textContent + ']'); });
    var text = lines.join('\n');
    $('#report').style.display = 'block'; $('#report').textContent = text;
    try { navigator.clipboard.writeText(text); ui.toast('Отчёт скопирован'); } catch (e) { ui.toast('Отчёт сформирован'); }
  });
  $('#seed').addEventListener('click', function () {
    if (!token) return;
    rpc('app_order_create', { p_token: token, p_title: 'Тестовая заявка (диагностика)', p_description: 'Создана из self-test', p_source: 'diagnostics', p_customer: 'Диагностика', p_contact: '', p_priority: 'low' })
      .then(function (d) { var r = d && d[0]; ui.toast('Заявка ' + ((r && r.number) || '') + ' создана'); window.Auth.log('Диагностика: тестовая заявка', (r && r.number) || ''); })
      .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (['admin', 'owner', 'manager'].indexOf(s.role) < 0) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    renderEnv(); renderKpi();
    if (SB) run();
  });
})();
