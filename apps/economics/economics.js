/* ============================================================
   3DMP Service · apps/economics — экономика и KPI
   Данные: app_economics, app_order_cost, app_capacity (0013/0011). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, orders = [], cap = [];

  var ST = { new: 'Новая', in_progress: 'В работе', done: 'Выполнена', cancelled: 'Отменена' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return (Number(v) || 0).toLocaleString('ru-RU'); }
  function money(v) { return (Number(v) || 0).toLocaleString('ru-RU') + ' ₽'; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_economics', { p_token: token }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_capacity', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      var e = (r[0] && r[0][0]) || {};
      orders = r[1] || []; cap = r[2] || [];
      $('#kpis').innerHTML =
        kpi(num(e.orders_total), 'Заявок всего') + kpi(num(e.orders_open), 'Заявки в работе') +
        kpi(num(e.naryads_open), 'Наряды в работе') + kpi(num(e.naryads_closed), 'Наряды закрыты') +
        kpi(num(e.plan_hours), 'План-часов') + kpi(num(e.fact_hours), 'Факт-часов') +
        kpi(num(e.defects_open), 'Открытых дефектов') + kpi(num(e.low_stock), 'Позиций ниже минимума') +
        kpi(money(e.avg_rate), 'Средний нормочас');
      renderOrders(); renderCap();
    }).catch(function (err) { msg('#ordersMsg', 'Ошибка: ' + err.message, 'err'); });
  }
  function kpi(v, l) { return '<div class="kpi"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>'; }

  function renderOrders() {
    if (!orders.length) { $('#orders').innerHTML = '<tr><td class="note">Заявок нет.</td></tr>'; return; }
    $('#orders').innerHTML = '<thead><tr><th>Заявка</th><th>Тема</th><th>Статус</th><th></th></tr></thead><tbody>' +
      orders.map(function (o) {
        return '<tr data-oid="' + o.id + '"><td><b>' + esc(o.number) + '</b></td><td>' + esc(o.title) + '</td>' +
          '<td>' + (ST[o.status] || o.status) + '</td>' +
          '<td><button class="act" data-cost="' + o.id + '">Себестоимость</button></td></tr>';
      }).join('') + '</tbody>';
    $$('#orders [data-cost]').forEach(function (b) {
      b.addEventListener('click', function () { showCost(b.dataset.cost); });
    });
  }
  function showCost(oid) {
    rpc('app_order_cost', { p_token: token, p_order_id: oid }).then(function (r) {
      var c = r && r[0]; if (!c) return;
      var row = $('#orders tr[data-oid="' + oid + '"]');
      var old = row.next();
      if (old && old.classList.contains('costrow')) old.remove();
      var html = '<tr class="costrow"><td colspan="4">Работы: <b>' + money(c.work_cost) + '</b> · Материалы: <b>' + money(c.material_cost) +
        '</b> · Накладные (15%): <b>' + money(c.overhead) + '</b> · <b>Итого: ' + money(c.total) + '</b>' +
        (c.margin != null ? ' · Маржа: <b>' + money(c.margin) + '</b>' : '') +
        ' <span class="note">(план ' + num(c.plan_hours) + ' ч / факт ' + num(c.fact_hours) + ' ч)</span></td></tr>';
      row.after(html);
    }).catch(function (e) { msg('#ordersMsg', 'Ошибка расчёта: ' + e.message, 'err'); });
  }

  function renderCap() {
    if (!cap.length) { $('#cap').innerHTML = '<tr><td class="note">Центров нет.</td></tr>'; return; }
    $('#cap').innerHTML = '<thead><tr><th>Рабочий центр</th><th>Тип</th><th>Нормочас</th><th>Нарядов</th><th>План-часов</th><th>Факт-часов</th></tr></thead><tbody>' +
      cap.map(function (c) {
        return '<tr><td><b>' + esc(c.wc_name) + '</b></td><td>' + esc(c.kind || '—') + '</td><td>' + money(c.cost_hour) + '</td>' +
          '<td>' + c.active_naryads + '</td><td>' + num(c.plan_hours) + '</td><td>' + num(c.fact_hours) + '</td></tr>';
      }).join('') + '</tbody>';
  }

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (['admin', 'owner', 'manager'].indexOf(s.role) < 0) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#ordersMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
