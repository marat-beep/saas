/* ============================================================
   3DMP Service · apps/orders — Заявки и заказы (эталонный модуль)
   CRM-заказчики, срок/приоритет/исполнитель/сумма, позиции,
   связи (документы/маршруты/наряды/счета). Данные: 0006+0009+0027.
   Стандарт модуля: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, orders = [], customers = [], filter = 'all', q = '', cur = null;

  var ST = { new: 'Новая', in_progress: 'В работе', done: 'Выполнена', cancelled: 'Отменена' };
  var PR = { high: 'Высокий', normal: 'Обычный', low: 'Низкий' };
  var TYP = { single: 'Единичный', batch: 'Серийный', tooling: 'Оснастка/штамп', engineering: 'Инжиниринг' };
  var typeF = '';
  var ROLE_SEE_ALL = ['admin', 'owner', 'manager'];

  function esc(v) { return ui.esc(v); }
  function b(cls, t) { return '<span class="badge ' + cls + '">' + t + '</span>'; }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function money(v) { return v == null || v === '' ? '' : (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function today() { var d = new Date(); return d.toISOString().slice(0, 10); }
  function isOverdue(o) { return o.due_date && o.due_date < today() && o.status !== 'done' && o.status !== 'cancelled'; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  var screens = AppRouter.create({
    onShow: function () { window.scrollTo(0, 0); },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Список ---------- */
  function load() {
    return Promise.all([
      rpc('app_order_list', { p_token: token }),
      rpc('app_customer_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_order_sla_check', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      var sla = (r[2] && r[2][0] && r[2][0].notified) || 0;
      if (Number(sla) > 0) { ui.toast('Просрочено заявок: ' + sla + ' — уведомление отправлено'); if (window.AppNotify) window.AppNotify.refresh(true); }
      orders = r[0] || []; customers = r[1] || [];
      fillCustomerSelect();
      renderKpi(); render();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    var c = { all: orders.length, new: 0, in_progress: 0, done: 0, cancelled: 0, overdue: 0 };
    orders.forEach(function (o) { c[o.status] = (c[o.status] || 0) + 1; if (isOverdue(o)) c.overdue++; });
    $('#kpi').innerHTML =
      cell('Всего', c.all) + cell('Новые', c.new) + cell('В работе', c.in_progress) +
      cell('Выполнены', c.done) + cell('Просрочены', c.overdue, c.overdue ? 'overdue' : '');
    function cell(t, v, cls) { return '<div class="kpi"><small>' + t + '</small><b' + (cls ? ' style="color:#b91c1c"' : '') + '>' + v + '</b></div>'; }
  }
  function filtered() {
    var s = q.toLowerCase();
    return orders.filter(function (o) {
      var okF = filter === 'all' || (filter === 'overdue' ? isOverdue(o) : o.status === filter);
      if (!okF) return false;
      if (typeF && o.order_type !== typeF) return false;
      if (!s) return true;
      return [o.number, o.title, o.customer_name, o.customer, o.assignee, o.source].join(' ').toLowerCase().indexOf(s) >= 0;
    });
  }
  function render() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Заявок нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (o) {
      return '<div class="ocard" data-id="' + o.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
          b(o.status, ST[o.status] || o.status) + b(o.priority, PR[o.priority] || o.priority) +
          (o.order_type ? b('', TYP[o.order_type] || o.order_type) : '') +
          (isOverdue(o) ? b('overdue', 'просрочено') : '') +
          '<span class="note" style="margin-left:auto;">' + esc(o.number) + '</span></div>' +
        '<h3 style="font-size:.95rem;margin:8px 0 4px;">' + esc(o.title) + '</h3>' +
        '<div style="font-size:.76rem;color:var(--muted);">' +
          (o.customer_name || o.customer ? '🏢 ' + esc(o.customer_name || o.customer) + ' · ' : '') +
          (o.assignee ? '👤 ' + esc(o.assignee) + ' · ' : '') +
          (o.due_date ? '📅 ' + esc(o.due_date) + ' · ' : '') +
          (o.amount ? '💰 ' + money(o.amount) + ' · ' : '') +
          fmt(o.created_at) + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openDetail(c.dataset.id); }); });
  }

  /* ---------- Карточка ---------- */
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function mkDoc(fn, label) {
    if (!cur) return;
    rpc(fn, { p_token: token, p_order_id: cur.id }).then(function (d) {
      var r = d && d[0]; if (!r) { ui.toast('Ошибка'); return; }
      window.Auth.log(label, r.number); ui.toast(r.message + ': ' + r.number);
      if (window.AppNotify) window.AppNotify.refresh(true);
      openDetail(cur.id);
    }).catch(function (e) { ui.toast('Ошибка: ' + e.message); });
  }
  function openDetail(id) {
    cur = null;
    Promise.all([
      rpc('app_order_get', { p_token: token, p_id: id }),
      rpc('app_order_history_list', { p_token: token, p_id: id }),
      rpc('app_order_items_list', { p_token: token, p_id: id }).catch(function () { return []; }),
      rpc('app_order_docs', { p_token: token, p_id: id }).catch(function () { return []; }),
      rpc('app_order_routes', { p_token: token, p_id: id }).catch(function () { return []; }),
      rpc('app_order_naryads', { p_token: token, p_id: id }).catch(function () { return []; }),
      rpc('app_order_invoices', { p_token: token, p_id: id }).catch(function () { return []; })
    ]).then(function (r) {
      var o = r[0] && r[0][0]; if (!o) { ui.toast('Заявка не найдена'); return; }
      cur = o;
      $('#detail').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
          b(o.status, ST[o.status] || o.status) + b(o.priority, PR[o.priority] || o.priority) +
          (o.order_type ? b('', TYP[o.order_type] || o.order_type) : '') +
          (isOverdue(o) ? b('overdue', 'просрочено') : '') +
          '<b style="margin-left:auto;">' + esc(o.number) + '</b></div>' +
        '<h1 style="font-size:1.2rem;margin:10px 0;">' + esc(o.title) + '</h1>' +
        (o.description ? '<p style="color:var(--muted);line-height:1.6;margin-bottom:10px;white-space:pre-wrap;">' + esc(o.description) + '</p>' : '') +
        kv('Заказчик', o.customer_name || o.customer) + kv('Контакт', o.contact) + kv('Тип заказа', TYP[o.order_type] || o.order_type) + kv('Источник', o.source) +
        kv('Срок', o.due_date) + kv('Исполнитель', o.assignee) + kv('Сумма', money(o.amount)) +
        kv('Автор', o.created_login) + kv('Создана', fmt(o.created_at)) + kv('Обновлена', fmt(o.updated_at)) +
        '<div class="toolbar mt"><button class="btn secondary" id="mkQuote" style="width:auto;padding:9px 16px;">Создать КП</button>' +
        '<button class="btn secondary" id="mkInv" style="width:auto;padding:9px 16px;">Создать счёт</button></div>';
      $('#stStatus').value = o.status;
      var qb = $('#mkQuote'), ib = $('#mkInv');
      if (qb) qb.addEventListener('click', function () { mkDoc('app_order_create_quote', 'КП'); });
      if (ib) ib.addEventListener('click', function () { mkDoc('app_order_create_invoice', 'Счёт'); });
      renderItems(r[2] || []);
      renderLinks(r[3] || [], r[4] || [], r[5] || [], r[6] || []);
      $('#history').innerHTML = (r[1] || []).map(function (x) {
        return '<div class="kvr"><span class="k">' + fmt(x.created_at) + '</span><b>' + (ST[x.status] || x.status) + '</b>' +
          '<span class="note" style="margin-left:auto;">' + esc(x.by_login || '') + (x.comment ? ' · ' + esc(x.comment) : '') + '</span></div>';
      }).join('') || '<span class="note">—</span>';
      clearMsg('#stMsg'); clearMsg('#itMsg');
      screens.go('s-detail');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderItems(items) {
    $('#items').innerHTML = '<thead><tr><th>Наименование</th><th>Кол-во</th><th>Ед.</th><th>Цена</th><th>Сумма</th><th></th></tr></thead><tbody>' +
      (items.length ? items.map(function (i) {
        return '<tr><td>' + esc(i.name) + '</td><td>' + (Number(i.qty) || 0) + '</td><td>' + esc(i.unit || '') + '</td>' +
          '<td>' + money(i.price) + '</td><td>' + money(i.amount) + '</td>' +
          '<td><button class="chip" data-del="' + i.id + '">✕</button></td></tr>';
      }).join('') : '<tr><td colspan="6"><span class="note">Позиций нет.</span></td></tr>') + '</tbody>';
    $$('#items [data-del]').forEach(function (b2) {
      b2.addEventListener('click', function () {
        rpc('app_order_item_remove', { p_token: token, p_id: b2.dataset.del })
          .then(function () { openDetail(cur.id); }).catch(function (e) { msg('#itMsg', e.message, 'err'); });
      });
    });
  }
  function renderLinks(docs, routes, naryads, invoices) {
    $('#lnDocs').innerHTML = docs.length ? docs.map(function (d) {
      return '<a class="link-item" href="../docs/index.html">' + b(d.status || '', d.doc_type || '') + '<b>' + esc(d.number) + '</b> · ' + esc(d.title) + (d.amount ? ' · ' + money(d.amount) : '') + '</a>';
    }).join('') : '<span class="note">Нет документов. Создайте КП/договор в модуле «Документы» с указанием заявки.</span>';
    $('#lnRoutes').innerHTML = routes.length ? routes.map(function (r) {
      return '<a class="link-item" href="../registry/index.html">' + b(r.status || '', 'маршрут') + '<b>' + esc(r.number) + '</b> · ' + esc(r.name) + ' · ' + money(r.total_cost) + '</a>';
    }).join('') : '<span class="note">Нет маршрутов. Создайте в «Справочниках» → вкладка «Маршруты».</span>';
    $('#lnNaryads').innerHTML = naryads.length ? naryads.map(function (n) {
      return '<a class="link-item" href="../production/index.html">' + b(n.status || '', n.route_number ? 'из маршрута' : 'наряд') + '<b>' + esc(n.number) + '</b> · ' + esc(n.title) + ' · план ' + (Number(n.plan_hours) || 0) + ' ч</a>';
    }).join('') : '<span class="note">Нет нарядов. Создайте в «Производстве» (в т.ч. из маршрута).</span>';
    $('#lnInvoices').innerHTML = invoices.length ? invoices.map(function (i) {
      return '<a class="link-item" href="../finance/index.html">' + b(i.status || '', 'счёт') + '<b>' + esc(i.number) + '</b> · ' + money(i.amount) + (i.due_date ? ' · до ' + esc(i.due_date) : '') + '</a>';
    }).join('') : '<span class="note">Нет счетов. Выставьте в «Финансах» по заявке.</span>';
  }

  /* ---------- CRM ---------- */
  function fillCustomerSelect() {
    var sel = $('#fCustomerSel'); if (!sel) return;
    var v = sel.value;
    sel.innerHTML = '<option value="">— не выбран —</option>' + customers.map(function (c) {
      return '<option value="' + c.id + '">' + esc(c.name) + (c.inn ? ' (ИНН ' + esc(c.inn) + ')' : '') + '</option>';
    }).join('');
    sel.value = v || '';
  }
  $('#ncSave').addEventListener('click', function () {
    var name = $('#ncName').value.trim(); if (!name) { msg('#ncMsg', 'Укажите название.', 'err'); return; }
    rpc('app_customer_save', {
      p_token: token, p_id: null, p_name: name, p_inn: $('#ncInn').value.trim(),
      p_contact_person: $('#ncContact').value.trim(), p_phone: $('#ncPhone').value.trim(),
      p_email: $('#ncEmail').value.trim(), p_address: '', p_note: ''
    }).then(function (d) {
      var r = d && d[0]; if (!r) { msg('#ncMsg', 'Ошибка', 'err'); return; }
      msg('#ncMsg', r.message, 'ok');
      window.Auth.log('Добавлен заказчик', name);
      customers.push({ id: r.id, name: name });
      fillCustomerSelect();
      $('#fCustomerSel').value = r.id;
      ['#ncName', '#ncInn', '#ncContact', '#ncPhone', '#ncEmail'].forEach(function (s) { $(s).value = ''; });
    }).catch(function (e) { msg('#ncMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  /* ---------- Создание ---------- */
  $('#toCreate').addEventListener('click', function () { clearMsg('#cMsg'); fillCustomerSelect(); screens.go('s-create'); });
  $('#backToList1').addEventListener('click', function () { screens.go('s-list'); });
  $('#backToList2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  $('#createBtn').addEventListener('click', function () {
    var title = $('#fTitle').value.trim();
    if (!title) { msg('#cMsg', 'Укажите тему заявки.', 'err'); return; }
    var amt = parseFloat(($('#fAmount').value || '').replace(',', '.'));
    rpc('app_order_create', {
      p_token: token, p_title: title, p_description: $('#fDesc').value.trim(),
      p_source: $('#fSource').value.trim(), p_customer: '', p_contact: $('#fContact').value.trim(),
      p_priority: $('#fPriority').value, p_customer_id: $('#fCustomerSel').value || null,
      p_due_date: $('#fDue').value || null, p_assignee: $('#fAssignee').value.trim(),
      p_amount: isNaN(amt) ? null : amt, p_order_type: $('#fType').value
    }).then(function (d) {
      var row = d && d[0];
      window.Auth.log('Создана заявка', (row && row.number) || title);
      if (window.AppNotify) window.AppNotify.refresh(true);
      ui.toast('Заявка ' + ((row && row.number) || '') + ' создана');
      ['#fTitle', '#fDesc', '#fSource', '#fContact', '#fAssignee', '#fAmount', '#fDue'].forEach(function (s) { $(s).value = ''; });
      $('#fCustomerSel').value = '';
      load().then(function () { screens.go('s-list'); });
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  /* ---------- Позиции ---------- */
  $('#itAdd').addEventListener('click', function () {
    if (!cur) return;
    var name = $('#itName').value.trim(); if (!name) { msg('#itMsg', 'Укажите наименование.', 'err'); return; }
    var qty = parseFloat(($('#itQty').value || '').replace(',', '.'));
    var price = parseFloat(($('#itPrice').value || '').replace(',', '.'));
    rpc('app_order_item_add', {
      p_token: token, p_order_id: cur.id, p_name: name,
      p_qty: isNaN(qty) ? 1 : qty, p_unit: $('#itUnit').value.trim(), p_price: isNaN(price) ? null : price
    }).then(function (d) {
      var r = d && d[0]; if (r && r.ok) { ['#itName', '#itQty', '#itUnit', '#itPrice'].forEach(function (s) { $(s).value = ''; }); openDetail(cur.id); }
      else msg('#itMsg', (r && r.message) || 'Ошибка', 'err');
    }).catch(function (e) { msg('#itMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  /* ---------- Статус ---------- */
  $('#stBtn').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_order_set_status', { p_token: token, p_id: cur.id, p_status: $('#stStatus').value, p_comment: $('#stComment').value.trim() })
      .then(function (d) {
        var row = d && d[0];
        if (!row || !row.ok) { msg('#stMsg', (row && row.message) || 'Не удалось', 'err'); return; }
        window.Auth.log('Статус заявки', cur.number + ' → ' + $('#stStatus').value);
        ui.toast('Статус обновлён');
        $('#stComment').value = '';
        openDetail(cur.id);
      }).catch(function (e) { msg('#stMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  /* ---------- Фильтры и поиск ---------- */
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; render();
  });
  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fTypeF').addEventListener('change', function () { typeF = this.value; render(); });

  /* ---------- Старт ---------- */
  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + (s.role ? ' · ' + s.role : '');
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
