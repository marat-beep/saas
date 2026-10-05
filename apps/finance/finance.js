/* ============================================================
   3DMP Service · apps/finance — счета и платежи
   Данные: app_invoice_*, app_payment_*, app_finance_kpi (0015). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, inv = [], orders = [], cur = null;

  var ST = { draft: 'Черновик', sent: 'Отправлен', paid: 'Оплачен', overdue: 'Просрочен', cancelled: 'Отменён' };
  function esc(v) { return ui.esc(v); }
  function money(v) { return (Number(v) || 0).toLocaleString('ru-RU') + ' ₽'; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? '—' : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return Promise.all([
      rpc('app_invoice_list', { p_token: token }),
      rpc('app_finance_kpi', { p_token: token }).catch(function () { return []; }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      inv = r[0] || []; var k = (r[1] && r[1][0]) || {}; orders = r[2] || [];
      $('#kpis').innerHTML =
        kpi(k.invoices_total || 0, 'Счетов') + kpi(money(k.sum_total), 'Выставлено') +
        kpi(money(k.sum_paid), 'Оплачено') + kpi(money(k.receivable), 'Дебиторка') + kpi(k.overdue || 0, 'Просрочено');
      $('#fOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      render();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function kpi(v, l) { return '<div class="kpi"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>'; }
  function render() {
    if (!inv.length) { $('#list').innerHTML = '<span class="note">Счетов нет.</span>'; return; }
    $('#list').innerHTML = inv.map(function (i) {
      var rest = (Number(i.amount) || 0) - (Number(i.paid) || 0);
      return '<div class="icard" data-id="' + i.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;"><span class="b ' + i.status + '">' + (ST[i.status] || i.status) + '</span>' +
        '<span class="note" style="margin-left:auto;">' + esc(i.number) + '</span></div>' +
        '<h3 style="font-size:.94rem;margin:8px 0 4px;">' + esc(i.customer || 'Счёт') + '</h3>' +
        '<div style="font-size:.78rem;color:var(--muted);">' + money(i.amount) + ' · оплачено ' + money(i.paid) +
        (rest > 0 ? ' · остаток <b>' + money(rest) + '</b>' : '') + (i.due_date ? ' · до ' + fmt(i.due_date) : '') + '</div></div>';
    }).join('');
    $$('#list .icard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function openItem(id) {
    cur = inv.filter(function (i) { return i.id === id; })[0]; if (!cur) return;
    var rest = (Number(cur.amount) || 0) - (Number(cur.paid) || 0);
    $('#invoice').innerHTML =
      '<div style="display:flex;gap:8px;align-items:center;"><span class="b ' + cur.status + '">' + (ST[cur.status] || cur.status) + '</span>' +
      '<b style="margin-left:auto;">' + esc(cur.number) + '</b></div>' +
      '<h1 style="font-size:1.1rem;margin:10px 0;">' + esc(cur.customer || 'Счёт') + '</h1>' +
      kv('Сумма', money(cur.amount)) + kv('Оплачено', money(cur.paid)) + kv('Остаток', money(rest)) +
      kv('Заявка', cur.order_number) + kv('Срок', fmt(cur.due_date));
    $('#pAmount').value = rest > 0 ? rest : '';
    clearMsg('#pMsg'); $('#sendBtn').disabled = cur.status === 'paid';
    loadPayments();
    screens.go('s-item');
  }
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function loadPayments() {
    rpc('app_payment_list', { p_token: token, p_invoice_id: cur.id }).then(function (list) {
      list = list || [];
      $('#payments').innerHTML = list.length ? list.map(function (p) {
        return '<div class="kvr"><b>' + money(p.amount) + '</b><span class="note">' + esc(p.method) + (p.note ? ' · ' + esc(p.note) : '') + '</span>' +
          '<span class="note" style="margin-left:auto;">' + fmt(p.created_at) + ' · ' + esc(p.by_login || '') + '</span></div>';
      }).join('') : '<span class="note">Платежей нет.</span>';
    });
  }

  $('#toNew').addEventListener('click', function () { clearMsg('#nMsg'); screens.go('s-new'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  $('#createBtn').addEventListener('click', function () {
    var amt = parseFloat($('#fAmount').value.replace(',', '.'));
    if (!amt || amt <= 0) { msg('#nMsg', 'Укажите сумму больше нуля.', 'err'); return; }
    rpc('app_invoice_create', { p_token: token, p_order_id: $('#fOrder').value || null, p_customer: $('#fCustomer').value.trim(), p_amount: amt, p_due_date: $('#fDue').value || null, p_note: $('#fNote').value.trim() })
      .then(function (d) { var row = d && d[0]; if (!row) { msg('#nMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('Счёт', row.number); ui.toast('Счёт ' + row.number + ' создан');
        ['#fCustomer', '#fAmount', '#fNote'].forEach(function (s) { $(s).value = ''; });
        load().then(function () { openItem(row.id); }); })
      .catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#payBtn').addEventListener('click', function () {
    if (!cur) return;
    var amt = parseFloat($('#pAmount').value.replace(',', '.'));
    if (!amt || amt <= 0) { msg('#pMsg', 'Сумма платежа > 0.', 'err'); return; }
    rpc('app_payment_add', { p_token: token, p_invoice_id: cur.id, p_amount: amt, p_method: $('#pMethod').value, p_note: $('#pNote').value.trim() })
      .then(function (d) { var r = d && d[0]; if (!r || !r.ok) { msg('#pMsg', (r && r.message) || 'Ошибка', 'err'); return; }
        window.Auth.log('Платёж', cur.number + ' ' + amt); ui.toast('Платёж добавлен'); $('#pNote').value = '';
        if (window.AppNotify) window.AppNotify.refresh(true);
        load().then(function () { openItem(cur.id); }); })
      .catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#sendBtn').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_invoice_set_status', { p_token: token, p_id: cur.id, p_status: 'sent' })
      .then(function () { window.Auth.log('Счёт отправлен', cur.number); load().then(function () { openItem(cur.id); }); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
