/* ============================================================
   3DMP Service · apps/usage — P1 счётчики использования. Данные: 0093.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null;

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_counters_list', { p_token: token }),
      rpc('app_counters_kpi', { p_token: token })
    ]).then(function (r) {
      var rows = r[0] || [];
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Метрик', k.metrics || 0) + cell('Сумма', k.total || 0);
      $('#cnt').textContent = '(' + rows.length + ')';
      $('#list').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Метрика</th><th class="num">Значение</th><th>Обновлено</th></tr></thead><tbody>' +
        rows.map(function (c) { return '<tr><td>' + esc(c.metric) + '</td><td class="num">' + c.value + '</td><td>' + new Date(c.updated_at).toLocaleString('ru-RU') + '</td></tr>'; }).join('') + '</tbody></table>'
        : '<span class="note">Счётчиков нет.</span>';
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  $('#fBump').addEventListener('click', function () {
    rpc('app_counter_bump', { p_token: token, p_metric: $('#fMetric').value, p_delta: parseFloat($('#fDelta').value) || 1 })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? ('Метрика ' + x.metric + ' = ' + x.value) : 'Ошибка', x ? 'ok' : 'err'); load(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
