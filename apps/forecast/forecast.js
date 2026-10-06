/* ============================================================
   3DMP Service · apps/forecast — B39 прогноз загрузки. Данные: 0076.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null;

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function d(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }

  function loadKpi() {
    return rpc('app_forecast_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Открытых нарядов', k.open_naryads || 0) + cell('Остаток часов', k.open_hours || 0) + cell('Мощность/день, ч', k.avg_daily_capacity || 0) + cell('Загрузка (14 дн)', (k.avg_load_pct || 0) + '%') + cell('Просрочено', k.overdue || 0);
    });
  }

  function loadLoad() {
    var days = parseInt($('#days').value, 10) || 14;
    return rpc('app_forecast_load', { p_token: token, p_days: days }).then(function (r) {
      var rows = r || [];
      $('#load').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Дата</th><th class="num">План, ч</th><th class="num">Мощность, ч</th><th>Загрузка</th></tr></thead><tbody>' +
        rows.map(function (x) {
          var pct = x.load_pct || 0, cls = pct > 100 ? 'over' : (pct > 85 ? 'warn' : '');
          return '<tr><td>' + esc(x.day) + '</td><td class="num">' + x.planned + '</td><td class="num">' + x.capacity + '</td>' +
            '<td style="min-width:140px;"><div class="bar"><i class="' + cls + '" style="width:' + Math.min(pct, 100) + '%"></i></div><span class="note">' + pct + '%</span></td></tr>';
        }).join('') + '</tbody></table>' : '<span class="note">Нет данных.</span>';
    }).catch(function (e) { msg('#lMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function loadOrders() {
    return rpc('app_forecast_orders', { p_token: token, p_limit: 100 }).then(function (r) {
      var rows = r || [];
      $('#cnt').textContent = '(' + rows.length + ')';
      $('#orders').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Наряд</th><th>Название</th><th>Центр</th><th>Заказ</th><th class="num">Остаток, ч</th><th class="num">ETA, дн</th><th>ETA</th><th>Срок</th><th>Риск</th></tr></thead><tbody>' +
        rows.map(function (o) {
          return '<tr><td>' + esc(o.number || '') + '</td><td>' + esc(o.title || '') + '</td><td>' + esc(o.center || '') + '</td><td>' + esc(o.order_number || '') + '</td>' +
            '<td class="num">' + o.remaining + '</td><td class="num">' + o.eta_days + '</td><td>' + d(o.eta_date) + '</td><td>' + d(o.due_date) + '</td>' +
            '<td class="risk-' + esc(o.risk) + '">' + esc(o.risk) + '</td></tr>';
        }).join('') + '</tbody></table>' : '<span class="note">Открытых нарядов нет.</span>';
    });
  }

  function refresh() { loadKpi(); loadLoad(); loadOrders(); }
  $('#refresh').addEventListener('click', refresh);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#lMsg', 'Supabase не подключён.', 'err'); return; }
    refresh();
  });
})();
