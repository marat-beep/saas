/* ============================================================
   3DMP Service · apps/bi — Аналитика (Chart.js)
   Данные: app_bi (0043). Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null, me = null, charts = {};

  var OST = { new: 'Новые', in_progress: 'В работе', done: 'Выполнены', cancelled: 'Отменены' };
  var IST = { draft: 'Черновик', sent: 'Отправлен', paid: 'Оплачен', overdue: 'Просрочен', cancelled: 'Отменён' };
  var QST = { draft: 'Черновик', passed: 'Годен', failed: 'Брак' };
  var TST = { open: 'Открыта', awarded: 'Победитель', closed: 'Закрыта' };
  var TYP = { single: 'Единичный', batch: 'Серийный', tooling: 'Оснастка', engineering: 'Инжиниринг' };
  var PAL = ['#10b981', '#3b82f6', '#f59e0b', '#ef4444', '#8b5cf6', '#64748b'];
  function money(v) { return (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 0 }) + ' ₽'; }
  function n(v) { return (Number(v) || 0).toLocaleString('ru-RU'); }
  function msg(t, k) { var e = $('#msg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(nm, a) { return SB.rpc(nm, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function mk(id, cfg) { if (charts[id]) charts[id].destroy(); if (!window.Chart) return; var el = document.getElementById(id); if (el) charts[id] = new Chart(el, cfg); }

  function load() {
    return Promise.all([
      rpc('app_bi', { p_token: token }),
      rpc('app_economics', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      var bi = r[0] || {}; var e = (r[1] && r[1][0]) || {};
      var eco = bi.economics || {};
      $('#kpis').innerHTML = cell('Сумма заявок', money(eco.amount)) + cell('Себестоимость', money(eco.cost)) +
        cell('Маржа', money(eco.margin), Number(eco.margin) < 0 ? '#b91c1c' : '#15803d') +
        cell('План / факт, ч', n(e.plan_hours) + ' / ' + n(e.fact_hours)) +
        cell('Стоимость запаса', money((bi.warehouse || {}).stock_value)) + cell('Ниже минимума', n((bi.warehouse || {}).low), Number((bi.warehouse || {}).low) ? '#b91c1c' : '');
      drawPay(bi.payments || []);
      drawDoughnut('cOrders', bi.orders || [], OST);
      drawDoughnut('cTypes', bi.orders_type || [], TYP, 'type');
      drawBar('cInv', bi.invoices || [], IST, 'sum', 'Сумма, ₽', '#3b82f6');
      drawProd(bi.production || []);
      drawDoughnut('cQual', bi.quality || [], QST);
      drawBar('cProc', bi.procurement || [], TST, 'count', 'Закупок', '#8b5cf6');
    }).catch(function (err) { msg('Ошибка: ' + err.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function drawPay(list) {
    mk('cPay', { type: 'line', data: { labels: list.map(function (x) { return x.m; }),
      datasets: [{ label: 'Оплаты', data: list.map(function (x) { return Number(x.sum) || 0; }), borderColor: '#10b981', backgroundColor: 'rgba(16,185,129,.15)', fill: true, tension: .3 }] },
      options: { plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } } });
  }
  function drawDoughnut(id, list, map, key) {
    key = key || 'status';
    mk(id, { type: 'doughnut', data: { labels: list.map(function (x) { return map[x[key]] || x[key]; }),
      datasets: [{ data: list.map(function (x) { return Number(x.count) || 0; }), backgroundColor: PAL }] },
      options: { plugins: { legend: { position: 'bottom' } } } });
  }
  function drawBar(id, list, map, valKey, label, color) {
    mk(id, { type: 'bar', data: { labels: list.map(function (x) { return map[x.status] || x.status; }),
      datasets: [{ label: label, data: list.map(function (x) { return Number(x[valKey]) || 0; }), backgroundColor: color }] },
      options: { plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } } });
  }
  function drawProd(list) {
    mk('cProd', { type: 'bar', data: { labels: list.map(function (c) { return c.wc || '—'; }),
      datasets: [
        { label: 'План', data: list.map(function (c) { return Number(c.plan) || 0; }), backgroundColor: '#93c5fd' },
        { label: 'Факт', data: list.map(function (c) { return Number(c.fact) || 0; }), backgroundColor: '#10b981' }
      ] },
      options: { plugins: { legend: { position: 'bottom' } }, scales: { y: { beginAtZero: true } } } });
  }

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    load();
  });
})();
