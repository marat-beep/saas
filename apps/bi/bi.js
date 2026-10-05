/* ============================================================
   3DMP Service · apps/bi — аналитика (Chart.js)
   Данные: app_bi, app_economics, app_capacity. Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null, me = null;
  var charts = {};

  var OST = { new: 'Новые', in_progress: 'В работе', done: 'Выполнены', cancelled: 'Отменены' };
  var IST = { draft: 'Черновик', sent: 'Отправлен', paid: 'Оплачен', overdue: 'Просрочен', cancelled: 'Отменён' };
  var NST = { open: 'Открыт', in_progress: 'В работе', closed: 'Закрыт' };
  var PAL = ['#10b981', '#3b82f6', '#f59e0b', '#ef4444', '#8b5cf6', '#64748b'];
  function esc(v) { return ui.esc(v); }
  function money(v) { return (Number(v) || 0).toLocaleString('ru-RU'); }
  function msg(t, k) { var e = $('#msg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function mk(id, cfg) {
    if (charts[id]) charts[id].destroy();
    if (!window.Chart) return;
    charts[id] = new Chart(document.getElementById(id), cfg);
  }

  function load() {
    return Promise.all([
      rpc('app_bi', { p_token: token }),
      rpc('app_economics', { p_token: token }).catch(function () { return []; }),
      rpc('app_capacity', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      var bi = r[0] || {}; var e = (r[1] && r[1][0]) || {}; var cap = r[2] || [];
      $('#kpis').innerHTML = kpi(e.orders_total || 0, 'Заявок') + kpi(money(e.plan_hours), 'План-часов') + kpi(money(e.fact_hours), 'Факт-часов') +
        kpi(e.defects_open || 0, 'Открытых дефектов') + kpi(e.low_stock || 0, 'Ниже минимума');
      drawPay(bi.payments || []);
      drawOrders(bi.orders || []);
      drawInv(bi.invoices || []);
      drawCap(cap);
    }).catch(function (err) { msg('Ошибка: ' + err.message, 'err'); });
  }
  function kpi(v, l) { return '<div class="kpi"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>'; }

  function drawPay(list) {
    mk('cPay', { type: 'line', data: { labels: list.map(function (x) { return x.m; }),
      datasets: [{ label: 'Оплаты', data: list.map(function (x) { return Number(x.sum) || 0; }), borderColor: '#10b981', backgroundColor: 'rgba(16,185,129,.15)', fill: true, tension: .3 }] },
      options: { plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } } });
  }
  function drawOrders(list) {
    mk('cOrders', { type: 'doughnut', data: { labels: list.map(function (x) { return OST[x.status] || x.status; }),
      datasets: [{ data: list.map(function (x) { return x.count; }), backgroundColor: PAL }] },
      options: { plugins: { legend: { position: 'bottom' } } } });
  }
  function drawInv(list) {
    mk('cInv', { type: 'bar', data: { labels: list.map(function (x) { return IST[x.status] || x.status; }),
      datasets: [{ label: 'Сумма, ₽', data: list.map(function (x) { return Number(x.sum) || 0; }), backgroundColor: '#3b82f6' }] },
      options: { plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } } });
  }
  function drawCap(cap) {
    mk('cCap', { type: 'bar', data: { labels: cap.map(function (c) { return c.wc_name; }),
      datasets: [
        { label: 'План', data: cap.map(function (c) { return Number(c.plan_hours) || 0; }), backgroundColor: '#93c5fd' },
        { label: 'Факт', data: cap.map(function (c) { return Number(c.fact_hours) || 0; }), backgroundColor: '#10b981' }
      ] },
      options: { plugins: { legend: { position: 'bottom' } }, scales: { y: { beginAtZero: true } } } });
  }

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (['admin', 'owner', 'manager'].indexOf(s.role) < 0) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    load();
  });
})();
