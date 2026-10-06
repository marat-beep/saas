/* ============================================================
   3DMP Service · apps/industry — P3 отраслевая аналитика. Данные: 0070.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null, bench = [], q = '';

  var NAME = { normohour_rate: 'Нормочас', oee_pct: 'OEE', defect_pct: 'Брак', margin_pct: 'Маржа', lead_days: 'Срок изготовления', utilization_pct: 'Загрузка' };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function num(v) { return v == null ? '—' : Number(v).toLocaleString('ru-RU'); }

  function load() {
    rpc('app_industry_compare', { p_token: token }).then(function (rows) {
      rows = rows || [];
      $('#compare').innerHTML = '<table class="mini"><thead><tr><th>Показатель</th><th class="num">Ваше</th><th class="num">Отрасль</th><th class="num">Отклонение</th><th>Ед.</th></tr></thead><tbody>' +
        rows.map(function (r) {
          var d = r.delta_pct;
          var cls = d == null ? '' : (d >= 0 ? 'pos' : 'neg');
          return '<tr><td>' + esc(NAME[r.metric] || r.metric) + '</td><td class="num">' + num(r.own) + '</td><td class="num">' + num(r.benchmark) + '</td>' +
            '<td class="num ' + cls + '">' + (d == null ? '—' : (d > 0 ? '+' : '') + d + '%') + '</td><td>' + esc(r.unit || '') + '</td></tr>';
        }).join('') + '</tbody></table>';
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });

    rpc('app_industry_stats', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#statsCard').style.display = 'block';
      $('#stats').innerHTML = '<div class="kpi"><small>Организаций</small><b>' + (k.tenants || 0) + '</b></div>' +
        '<div class="kpi"><small>Активных</small><b>' + (k.active_tenants || 0) + '</b></div>' +
        '<div class="kpi"><small>Пользователей</small><b>' + (k.users || 0) + '</b></div>' +
        '<div class="kpi"><small>Заявок</small><b>' + (k.orders || 0) + '</b></div>' +
        '<div class="kpi"><small>Нарядов</small><b>' + (k.naryads || 0) + '</b></div>' +
        '<div class="kpi"><small>Эскроу выпл.</small><b>' + num(k.escrow_released) + '</b></div>';
    }).catch(function () { /* не админ — скрыто */ });

    rpc('app_industry_benchmarks_list', { p_token: token, p_metric: null }).then(function (r) { bench = r || []; render(); });
  }

  function render() {
    var s = q.toLowerCase();
    var rows = bench.filter(function (b) { return !s || ((b.metric || '') + ' ' + (b.category || '')).toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#bench').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Метрика</th><th>Категория</th><th class="num">Значение</th><th>Ед.</th><th>Период</th><th>Источник</th></tr></thead><tbody>' +
      rows.map(function (b) {
        return '<tr><td>' + esc(NAME[b.metric] || b.metric) + '</td><td>' + esc(b.category || '—') + '</td><td class="num">' + num(b.value) + '</td><td>' + esc(b.unit || '') + '</td><td>' + esc(b.period || '') + '</td><td>' + esc(b.source || '') + '</td></tr>';
      }).join('') + '</tbody></table>' : '<span class="note">Бенчмарков нет.</span>';
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#cMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
