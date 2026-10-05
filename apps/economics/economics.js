/* ============================================================
   3DMP Service · apps/economics — Экономика (себестоимость по факту)
   Данные: 0013+0042. Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, orders = [], cap = [], rates = [];

  var ST = { new: 'Новая', in_progress: 'В работе', done: 'Выполнена', cancelled: 'Отменена' };
  var KIND = { machine: 'Станок', labor: 'Труд', overhead: 'Накладные' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return v == null ? '—' : (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_economics', { p_token: token }),
      rpc('app_economics_orders', { p_token: token }).catch(function () { return []; }),
      rpc('app_capacity', { p_token: token }).catch(function () { return []; }),
      rpc('app_cost_rates_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      var e = (r[0] && r[0][0]) || {}; orders = r[1] || []; cap = r[2] || []; rates = r[3] || [];
      var margin = orders.reduce(function (s, o) { return s + num(o.margin); }, 0);
      $('#kpis').innerHTML = cell('Заявок', num(e.orders_total)) + cell('Сумма заявок', money(e.orders_amount_sum)) +
        cell('Себестоимость', money(e.cost_total)) + cell('Маржа (сумма)', money(margin), margin < 0 ? '#b91c1c' : '#15803d') +
        cell('Факт-часов', num(e.fact_hours)) + cell('Средний нормочас', money(e.avg_rate));
      renderOrders(); renderCap(); renderRates();
    }).catch(function (err) { msg('#ordersMsg', 'Ошибка: ' + err.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function renderOrders() {
    if (!orders.length) { $('#orders').innerHTML = '<tr><td class="note">Заявок нет.</td></tr>'; return; }
    $('#orders').innerHTML = '<thead><tr><th>Заявка</th><th>Тема</th><th>Статус</th><th>Сумма</th><th>Себестоимость</th><th>Маржа</th><th>Маржа %</th><th></th></tr></thead><tbody>' +
      orders.map(function (o) {
        return '<tr data-oid="' + o.id + '"><td><b>' + esc(o.number) + '</b></td><td>' + esc(o.title) + '</td>' +
          '<td>' + (ST[o.status] || o.status) + '</td><td>' + money(o.amount) + '</td><td>' + money(o.total) + '</td>' +
          '<td' + (num(o.margin) < 0 ? ' style="color:#b91c1c"' : '') + '>' + money(o.margin) + '</td>' +
          '<td>' + (o.margin_pct != null ? esc(o.margin_pct) + '%' : '—') + '</td>' +
          '<td><button class="act" data-cost="' + o.id + '">Детали</button></td></tr>';
      }).join('') + '</tbody>';
    $$('#orders [data-cost]').forEach(function (b) { b.addEventListener('click', function () { showCost(b.dataset.cost); }); });
  }
  function showCost(oid) {
    rpc('app_order_cost', { p_token: token, p_order_id: oid }).then(function (r) {
      var c = r && r[0]; if (!c) return;
      var row = $('#orders tr[data-oid="' + oid + '"]'); var old = row.next();
      if (old && old.classList.contains('costrow')) old.remove();
      var html = '<tr class="costrow"><td colspan="8">Работы: <b>' + money(c.work_cost) + '</b> · Материалы: <b>' + money(c.material_cost) +
        '</b>' + (c.materials_from_moves ? ' <span class="note">(по складу)</span>' : ' <span class="note">(по BOM)</span>') +
        ' · Накладные 15%: <b>' + money(c.overhead) + '</b> · <b>Итого: ' + money(c.total) + '</b>' +
        (c.margin != null ? ' · Маржа: <b>' + money(c.margin) + '</b>' + (c.margin_pct != null ? ' (' + c.margin_pct + '%)' : '') : '') +
        ' <span class="note">(план ' + num(c.plan_hours) + ' ч / факт ' + num(c.fact_hours) + ' ч)</span></td></tr>';
      row.after(html);
    }).catch(function (e) { msg('#ordersMsg', 'Ошибка расчёта: ' + e.message, 'err'); });
  }
  function renderCap() {
    if (!cap.length) { $('#cap').innerHTML = '<tr><td class="note">Центров нет.</td></tr>'; return; }
    $('#cap').innerHTML = '<thead><tr><th>Рабочий центр</th><th>Тип</th><th>Нормочас</th><th>Нарядов</th><th>План-часов</th><th>Факт-часов</th></tr></thead><tbody>' +
      cap.map(function (c) {
        return '<tr><td><b>' + esc(c.wc_name) + '</b></td><td>' + esc(c.kind || '—') + '</td><td>' + money(c.cost_hour) + '</td>' +
          '<td>' + num(c.active_naryads) + '</td><td>' + num(c.plan_hours) + '</td><td>' + num(c.fact_hours) + '</td></tr>';
      }).join('') + '</tbody>';
  }
  function renderRates() {
    if (!rates.length) { $('#rates').innerHTML = '<tr><td class="note">Ставок нет.</td></tr>'; return; }
    $('#rates').innerHTML = '<thead><tr><th>Тип</th><th>Название</th><th>Значение</th></tr></thead><tbody>' +
      rates.map(function (r) {
        return '<tr><td>' + (KIND[r.kind] || r.kind) + '</td><td>' + esc(r.name) + '</td><td>' +
          (r.kind === 'overhead' ? num(r.rate_hour) + ' %' : money(r.rate_hour) + '/ч') + '</td></tr>';
      }).join('') + '</tbody>';
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    ['ord', 'cap', 'rate'].forEach(function (t) { $('#t-' + t).style.display = (b.dataset.t === t) ? '' : 'none'; });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#ordersMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
