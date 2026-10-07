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

  /* ---------- Роли (data-cap) ---------- */
  var ALL = { reports: 1 };
  var CAPS = { admin: ALL, owner: ALL, director: ALL, manager: ALL, chief: ALL, economist: ALL, default: {} };
  function can(c) { return !!(me && (CAPS[me.role] || CAPS['default'])[c]); }
  function applyCaps() { $$('[data-cap]').forEach(function (el) { var n = (el.dataset.cap || '').split('|'); if (!n.some(can)) el.style.display = 'none'; }); }
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
    Promise.all([
      rpc('app_order_cost', { p_token: token, p_order_id: oid }),
      rpc('app_order_cost_plan_fact', { p_token: token, p_order_id: oid }).catch(function () { return null; })
    ]).then(function (res) {
      var c = res[0] && res[0][0]; if (!c) return;
      var pf = res[1] && res[1][0];
      var row = $('#orders tr[data-oid="' + oid + '"]'); var old = row.next();
      if (old && old.classList.contains('costrow')) old.remove();
      var dev = pf ? num(pf.labor_dev) : 0;
      var html = '<tr class="costrow"><td colspan="8">Работы: <b>' + money(c.work_cost) + '</b> · Материалы: <b>' + money(c.material_cost) +
        '</b>' + (c.materials_from_moves ? ' <span class="note">(по складу)</span>' : ' <span class="note">(по BOM)</span>') +
        ' · Накладные 15%: <b>' + money(c.overhead) + '</b> · <b>Итого: ' + money(c.total) + '</b>' +
        (c.margin != null ? ' · Маржа: <b>' + money(c.margin) + '</b>' + (c.margin_pct != null ? ' (' + c.margin_pct + '%)' : '') : '') +
        ' <span class="note">(план ' + num(c.plan_hours) + ' ч / факт ' + num(c.fact_hours) + ' ч)</span>' +
        (pf ? '<div class="note" style="margin-top:4px;">План/факт по труду: часы ' + num(pf.plan_hours) + ' → <b>' + num(pf.fact_hours) + '</b> (откл. ' + num(pf.hours_dev) + '); ставка ' + money(pf.rate_avg) + '/ч; труд план ' + money(pf.plan_labor) + ' → факт <b>' + money(pf.fact_labor) + '</b> (откл. <b' + (dev > 0 ? ' style="color:#b91c1c"' : '') + '>' + money(pf.labor_dev) + '</b>)</div>' : '') +
        '</td></tr>';
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

  /* ---------- Отчёт (себестоимость/маржа) ---------- */
  function reportPdf() {
    if (!window.AppExport) { ui.toast('Экспорт недоступен'); return; }
    var sumAmount = orders.reduce(function (s, o) { return s + num(o.amount); }, 0);
    var sumCost = orders.reduce(function (s, o) { return s + num(o.total); }, 0);
    var sumMargin = orders.reduce(function (s, o) { return s + num(o.margin); }, 0);
    var cols = [
      { key: 'number', label: 'Заявка' }, { key: 'title', label: 'Тема' },
      { key: 'status', label: 'Статус', value: function (o) { return ST[o.status] || o.status; } },
      { key: 'amount', label: 'Сумма', num: true, value: function (o) { return money(o.amount); } },
      { key: 'total', label: 'Себестоимость', num: true, value: function (o) { return money(o.total); } },
      { key: 'margin', label: 'Маржа', num: true, value: function (o) { return money(o.margin); } },
      { key: 'margin_pct', label: 'Маржа %', num: true, value: function (o) { return o.margin_pct != null ? o.margin_pct + '%' : '—'; } }
    ];
    AppExport.exportPdf('Экономика — отчёт', AppExport.reportDocument({
      brand: '3DMP Service', title: 'Отчёт по экономике заявок', subtitle: new Date().toLocaleDateString('ru-RU'),
      kpis: [{ label: 'Заявок', value: orders.length }, { label: 'Сумма', value: money(sumAmount) }, { label: 'Себестоимость', value: money(sumCost) }, { label: 'Маржа', value: money(sumMargin) }],
      sections: [{ title: 'Себестоимость и маржа', columns: cols, rows: orders }],
      sign: ['Экономист', 'Руководитель'], footer: '3DMP Service · экономика'
    }));
  }
  $('#repBtn').addEventListener('click', reportPdf);

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    ['ord', 'cap', 'rate'].forEach(function (t) { $('#t-' + t).style.display = (b.dataset.t === t) ? '' : 'none'; });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token; applyCaps();
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#ordersMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
