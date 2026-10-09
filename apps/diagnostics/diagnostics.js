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

  /* ---------- W33: мониторинг доступности (SLA платформы) ---------- */
  function trendSvg(rows) {
    if (!rows || !rows.length) return '<span class="note">Нет данных мониторинга.</span>';
    var w = 720, h = 120, pad = 6, bw = (w - pad * 2) / rows.length, bars = '';
    rows.forEach(function (r, i) {
      var x = pad + i * bw, up = Number(r.uptime_pct) || 0;
      var bh = Math.round((h - 26) * (up / 100));
      var col = 'var(--danger)'; if (r.total === 0) col = '#e2e8f0'; else if (up >= 99) col = 'var(--accent)'; else if (up >= 90) col = 'var(--warning,#f59e0b)';
      var dd = String(r.day).substr(8, 2) + '.' + String(r.day).substr(5, 2);
      bars += '<rect x="' + x.toFixed(1) + '" y="' + (h - 18 - Math.max(bh, 2)) + '" width="' + (bw - 4).toFixed(1) + '" height="' + Math.max(bh, 2) + '" rx="3" fill="' + col + '"><title>' + dd + ': ' + up + '% (' + r.ok + '/' + r.total + ')</title></rect>';
      bars += '<text x="' + (x + bw / 2).toFixed(1) + '" y="' + (h - 6) + '" font-size="9" fill="#94a3b8" text-anchor="middle">' + dd + '</text>';
    });
    return '<svg viewBox="0 0 ' + w + ' ' + h + '" width="100%" height="120" role="img" aria-label="Тренд доступности">' + bars + '</svg>';
  }
  function alertRow(a) {
    var sev = a.severity === 'fail' ? 'err' : 'wait';
    var dt = a.last_seen ? String(a.last_seen).substr(0, 16).replace('T', ' ') : '';
    return '<li class="chk ' + sev + '"><span class="mark">' + (a.severity === 'fail' ? '✕' : '!') + '</span>' +
      '<span><b>' + esc(a.name) + '</b> <span class="note">' + esc(a.detail || '') + '</span></span>' +
      '<span class="t">×' + a.occurrences + ' · ' + esc(dt) + '</span>' +
      '<button class="btn secondary" data-resolve="' + a.id + '" style="width:auto;padding:5px 10px;margin-left:8px;">Закрыть</button></li>';
  }
  function loadMonitor() {
    if (!token) return;
    Promise.all([
      rpc('app_health_board', { p_token: token }),
      rpc('app_health_alerts_list', { p_token: token, p_status: 'open' }),
      rpc('app_health_trend', { p_token: token, p_days: 14 })
    ]).then(function (res) {
      var board = res[0] || [], alerts = res[1] || [], trend = res[2] || [];
      var ok = 0, warn = 0, fail = 0;
      board.forEach(function (b) { if (b.status === 'ok') ok++; else if (b.status === 'warn') warn++; else fail++; });
      var lastAt = board.length ? board[0].checked_at : null;
      var upSum = 0, upN = 0;
      trend.forEach(function (r) { if (r.total > 0) { upSum += Number(r.uptime_pct); upN++; } });
      var up = upN ? (upSum / upN).toFixed(1) : '—';
      $('#mKpis').innerHTML = kv(ok + ' ok', 'В норме') + kv(warn + ' warn', 'Предупреждений') +
        kv(fail + ' fail', 'Сбоев') + kv(alerts.length, 'Открытых алертов') + kv(up + '%', 'Uptime (14 дней)');
      $('#mWhen').textContent = lastAt ? ('Последняя проверка: ' + String(lastAt).substr(0, 16).replace('T', ' ')) : 'Проверок ещё не было';
      $('#mTrend').innerHTML = trendSvg(trend);
      $('#mAlerts').innerHTML = alerts.length ? alerts.map(alertRow).join('')
        : '<li class="chk ok"><span class="mark">✓</span><span>Открытых алертов нет</span></li>';
      $$('#mAlerts [data-resolve]').forEach(function (b) {
        b.addEventListener('click', function () { resolveAlert(b.getAttribute('data-resolve')); });
      });
    }).catch(function (e) {
      $('#mAlerts').innerHTML = '<li class="chk err"><span class="mark">✕</span><span>' + esc((e && e.message) || e) + '</span></li>';
    });
  }
  function resolveAlert(id) {
    rpc('app_health_alert_resolve', { p_token: token, p_id: id })
      .then(function () { ui.toast('Алерт закрыт'); loadMonitor(); })
      .catch(function (e) { ui.toast('Ошибка: ' + e.message); });
  }
  var mScan = $('#mScan'); if (mScan) mScan.addEventListener('click', function () {
    if (!token) return;
    msg('Проверка доступности…', 'info');
    rpc('app_health_scan', { p_token: token })
      .then(function () { msg('Проверка выполнена.', 'ok'); loadMonitor(); })
      .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  });
  var mRefresh = $('#mRefresh'); if (mRefresh) mRefresh.addEventListener('click', loadMonitor);

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
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    renderEnv(); renderKpi(); loadMonitor();
    if (SB) run();
  });
})();
