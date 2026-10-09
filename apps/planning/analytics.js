/* ============================================================
   3DMP Service · apps/planning/analytics.js (W42) — аналитика производства:
   APS-очередь, предиктивный ТОиР, SPC-сигналы.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB, token = null;
  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function msg(t, k) { var e = $('#anaMsg'); if (e) { e.className = 'msg show ' + (k || 'info'); e.textContent = t; } }
  function table(cols, rows) {
    return '<table class="atbl"><thead><tr>' + cols.map(function (c) { return '<th>' + esc(c) + '</th>'; }).join('') + '</tr></thead><tbody>' +
      ((rows && rows.length) ? rows.map(function (r) { return '<tr>' + r.map(function (v) { return '<td>' + esc(v == null ? '' : v) + '</td>'; }).join('') + '</tr>'; }).join('')
        : '<tr><td colspan="' + cols.length + '" class="note">Нет данных</td></tr>') + '</tbody></table>';
  }
  function aps() {
    rpc('app_aps_optimize', { p_token: token }).then(function (l) {
      $('#anaOut').innerHTML = '<h3>Рекомендованная очередь (APS)</h3>' +
        table(['№', 'Наряд', 'Название', 'Приоритет', 'Срок', 'План,ч', 'Причина'], (l || []).map(function (x) { return [x.seq, x.number, x.title, x.priority, x.due_date, x.plan_hours, x.reason]; }));
      msg('Нарядов в очереди: ' + (l ? l.length : 0), 'ok');
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function mnt() {
    rpc('app_mnt_predictive', { p_token: token }).then(function (l) {
      $('#anaOut').innerHTML = '<h3>Предиктивный ТОиР (по вибрации)</h3>' +
        table(['Оборудование', 'Последнее', 'Среднее', 'Порог', 'Тренд', 'Дней до', 'Риск'], (l || []).map(function (x) { return [x.equipment, x.last_value, x.avg_value, x.threshold, x.trend, x.days_to, x.risk]; }));
      msg('Оборудования: ' + (l ? l.length : 0), 'ok');
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function spc() {
    rpc('app_spc_signals', { p_token: token, p_param: null }).then(function (l) {
      $('#anaOut').innerHTML = '<h3>SPC-сигналы (вне 2σ/3σ)</h3>' +
        table(['Параметр', 'Значение', 'Время', 'Сигнал'], (l || []).map(function (x) { return [x.param, x.value, x.ts, x.signal]; }));
      msg('Сигналов: ' + (l ? l.length : 0), 'ok');
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function load() { if (!token) return; if (!$('#anaOut').dataset.done) { aps(); $('#anaOut').dataset.done = '1'; } }
  window.AppProdAnalytics = { load: load, aps: aps, mnt: mnt, spc: spc };
  window.addEventListener('load', function () {
    var s = window.Auth && window.Auth.session && window.Auth.session(); if (s) token = s.token;
    var a = $('#anaAps'); if (a) a.addEventListener('click', aps);
    var m = $('#anaMnt'); if (m) m.addEventListener('click', mnt);
    var sp = $('#anaSpc'); if (sp) sp.addEventListener('click', spc);
  });
})();
