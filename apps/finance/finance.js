/* ============================================================
   3DMP Service · apps/finance — Финансы (счета/оплаты, дебиторка)
   CRM-заказчик, связь с заявкой/договором, остаток и просрочка.
   Данные: 0015+0031. Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, inv = [], orders = [], customers = [], cur = null, filter = '', q = '';

  var ST = { draft: 'Черновик', sent: 'Отправлен', paid: 'Оплачен', overdue: 'Просрочен', cancelled: 'Отменён' };
  function esc(v) { return ui.esc(v); }
  function money(v) { return v == null ? '—' : (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? '—' : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  /* ---------- Роли (data-cap) ---------- */
  var ALL = { edit: 1, reports: 1 };
  var CAPS = { admin: ALL, owner: ALL, director: ALL, manager: ALL, economist: ALL, chief: { reports: 1 }, default: { reports: 1 } };
  function can(c) { return !!(me && (CAPS[me.role] || CAPS['default'])[c]); }
  function applyCaps() { $$('[data-cap]').forEach(function (el) { var n = (el.dataset.cap || '').split('|'); if (!n.some(can)) el.style.display = 'none'; }); }

  /* ---------- Отчёт (финансы) ---------- */
  function reportPdf() {
    if (!window.AppExport) { ui.toast('Экспорт недоступен'); return; }
    var sum = inv.reduce(function (s, i) { return s + (Number(i.amount) || 0); }, 0);
    var paid = inv.reduce(function (s, i) { return s + (Number(i.paid) || 0); }, 0);
    var cols = [
      { key: 'number', label: 'Счёт' }, { key: 'customer_name', label: 'Заказчик' },
      { key: 'status', label: 'Статус', value: function (i) { return ST[i.status] || i.status; } },
      { key: 'amount', label: 'Сумма', num: true, value: function (i) { return money(i.amount); } },
      { key: 'paid', label: 'Оплачено', num: true, value: function (i) { return money(i.paid); } },
      { key: 'due_date', label: 'Срок', value: function (i) { return i.due_date ? String(i.due_date).slice(0, 10) : ''; } },
      { key: 'is_overdue', label: 'Просрочка', value: function (i) { return i.is_overdue ? 'да' : ''; } }
    ];
    AppExport.exportPdf('Финансы — отчёт', AppExport.reportDocument({
      brand: '3DMP Service', title: 'Реестр счетов и оплат', subtitle: new Date().toLocaleDateString('ru-RU'),
      kpis: [{ label: 'Счетов', value: inv.length }, { label: 'Выставлено', value: money(sum) }, { label: 'Оплачено', value: money(paid) }, { label: 'Дебиторка', value: money(sum - paid) }],
      sections: [{ title: 'Счета', columns: cols, rows: inv }],
      sign: ['Финансовый директор', 'Главный бухгалтер'], footer: '3DMP Service · финансы'
    }));
  }
  $('#repBtn').addEventListener('click', reportPdf);

  function load() {
    return Promise.all([
      rpc('app_invoice_list', { p_token: token }),
      rpc('app_finance_kpi', { p_token: token }).catch(function () { return []; }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_customer_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      inv = r[0] || []; var k = (r[1] && r[1][0]) || {}; orders = r[2] || []; customers = r[3] || [];
      $('#kpis').innerHTML =
        cell('Счетов', k.invoices_total || 0) + cell('Выставлено', money(k.sum_total)) + cell('Оплачено', money(k.sum_paid)) +
        cell('Дебиторка', money(k.receivable)) + cell('Просрочено', k.overdue || 0, (k.overdue ? '#b91c1c' : ''));
      $('#fOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      $('#fCustomerSel').innerHTML = '<option value="">— не выбран —</option>' + customers.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + '</option>'; }).join('');
      render();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v, color) { return '<div class="kpi"><small>' + l + '</small><b' + (color ? ' style="color:' + color + '"' : '') + '>' + v + '</b></div>'; }
  function filtered() {
    var s = q.toLowerCase();
    return inv.filter(function (i) {
      var okF = !filter || (filter === 'overdue' ? i.is_overdue : i.status === filter);
      if (!okF) return false;
      if (!s) return true;
      return [i.number, i.customer, i.customer_name, i.order_number].join(' ').toLowerCase().indexOf(s) >= 0;
    });
  }
  function render() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Счетов нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (i) {
      var bal = Number(i.balance) || 0;
      return '<div class="ocard" data-id="' + i.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
          '<span class="badge ' + (i.is_overdue ? 'overdue' : i.status) + '">' + (i.is_overdue ? 'Просрочен' : (ST[i.status] || i.status)) + '</span>' +
          '<span class="note" style="margin-left:auto;">' + esc(i.number) + '</span></div>' +
        '<h3 style="font-size:.94rem;margin:8px 0 4px;">' + esc(i.customer_name || i.customer || 'Счёт') + '</h3>' +
        '<div style="font-size:.78rem;color:var(--muted);">' +
          money(i.amount) + ' · оплачено ' + money(i.paid) +
          (bal > 0 ? ' · остаток <b>' + money(bal) + '</b>' : '') +
          (i.due_date ? ' · до ' + fmt(i.due_date) : '') +
          (i.order_number ? ' · 📥 ' + esc(i.order_number) : '') +
          (i.document_number ? ' · 📄 ' + esc(i.document_number) : '') + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function openItem(id) {
    rpc('app_invoice_get', { p_token: token, p_id: id }).then(function (r) {
      var i = r && r[0]; if (!i) { ui.toast('Счёт не найден'); return; }
      cur = i;
      var bal = Number(i.balance) || 0;
      $('#invoice').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
          '<span class="badge ' + (i.is_overdue ? 'overdue' : i.status) + '">' + (i.is_overdue ? 'Просрочен' : (ST[i.status] || i.status)) + '</span>' +
          '<b style="margin-left:auto;">' + esc(i.number) + '</b></div>' +
        '<h1 style="font-size:1.1rem;margin:10px 0;">' + esc(i.customer_name || i.customer || 'Счёт') + '</h1>' +
        kv('Сумма', money(i.amount)) + kv('Оплачено', money(i.paid)) + kv('Остаток', money(bal)) +
        kv('Заявка', i.order_number) + kv('Договор', i.document_number) + kv('Срок', fmt(i.due_date)) +
        kv('Исполнитель', i.assignee) + kv('Примечание', i.note) + kv('Автор', i.created_login) + kv('Оплачен', i.paid_at ? fmt(i.paid_at) : '');
      $('#pAmount').value = bal > 0 ? bal : '';
      clearMsg('#pMsg');
      $('#sendBtn').disabled = (i.status === 'paid');
      $('#cancelBtn').disabled = (i.status === 'paid' || i.status === 'cancelled');
      loadPayments();
      screens.go('s-item');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
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
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; render();
  });
  $('#q').addEventListener('input', function () { q = this.value; render(); });

  $('#createBtn').addEventListener('click', function () {
    var amt = parseFloat(($('#fAmount').value || '').replace(',', '.'));
    if (!amt || amt <= 0) { msg('#nMsg', 'Укажите сумму больше нуля.', 'err'); return; }
    rpc('app_invoice_create', {
      p_token: token, p_order_id: $('#fOrder').value || null, p_customer: $('#fCustomer').value.trim(),
      p_amount: amt, p_due_date: $('#fDue').value || null, p_note: $('#fNote').value.trim(),
      p_customer_id: $('#fCustomerSel').value || null, p_document_id: null, p_assignee: $('#fAssignee').value.trim()
    }).then(function (d) {
      var row = d && d[0]; if (!row) { msg('#nMsg', 'Ошибка', 'err'); return; }
      window.Auth.log('Счёт', row.number); ui.toast('Счёт ' + row.number + ' создан');
      ['#fCustomer', '#fAmount', '#fNote', '#fDue', '#fAssignee'].forEach(function (s) { $(s).value = ''; });
      $('#fCustomerSel').value = ''; $('#fOrder').value = '';
      load().then(function () { openItem(row.id); });
    }).catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#payBtn').addEventListener('click', function () {
    if (!cur) return;
    var amt = parseFloat(($('#pAmount').value || '').replace(',', '.'));
    if (!amt || amt <= 0) { msg('#pMsg', 'Сумма платежа > 0.', 'err'); return; }
    rpc('app_payment_add', { p_token: token, p_invoice_id: cur.id, p_amount: amt, p_method: $('#pMethod').value, p_note: $('#pNote').value.trim() })
      .then(function (d) {
        var r = d && d[0]; if (!r || !r.ok) { msg('#pMsg', (r && r.message) || 'Ошибка', 'err'); return; }
        window.Auth.log('Платёж', cur.number + ' ' + amt); ui.toast('Платёж добавлен'); $('#pNote').value = '';
        if (window.AppNotify) window.AppNotify.refresh(true);
        load().then(function () { openItem(cur.id); });
      }).catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#sendBtn').addEventListener('click', function () { setStatus('sent'); });
  $('#cancelBtn').addEventListener('click', function () { setStatus('cancelled'); });
  function setStatus(st) {
    if (!cur) return;
    rpc('app_invoice_set_status', { p_token: token, p_id: cur.id, p_status: st })
      .then(function (d) { var r = d && d[0]; if (r && !r.ok) { msg('#pMsg', r.message, 'err'); return; } window.Auth.log('Статус счёта', cur.number + ' → ' + st); load().then(function () { openItem(cur.id); }); })
      .catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token; applyCaps();
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
