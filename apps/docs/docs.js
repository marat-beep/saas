/* ============================================================
   3DMP Service · apps/docs — Документы (КП/договор/техкарта/акт)
   CRM-заказчик, срок действия, исполнитель, подписание, версии.
   Данные: 0017+0030. Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, docs = [], orders = [], customers = [], cur = null, filter = '', q = '';

  var T = { kp: 'КП', contract: 'Договор', techcard: 'Техкарта', act: 'Акт', other: 'Другое' };
  var ST = { draft: 'Черновик', active: 'В работе', archived: 'Архив' };
  function esc(v) { return ui.esc(v); }
  function money(v) { return v == null || v === '' ? '—' : (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  /* ---------- Роли (data-cap) ---------- */
  var ALL = { edit: 1, reports: 1 };
  var CAPS = { admin: ALL, owner: ALL, director: ALL, manager: ALL, chief: { edit: 1, reports: 1 }, economist: { reports: 1 }, support: { reports: 1 }, default: { reports: 1 } };
  function can(c) { return !!(me && (CAPS[me.role] || CAPS['default'])[c]); }
  function applyCaps() { $$('[data-cap]').forEach(function (el) { var n = (el.dataset.cap || '').split('|'); if (!n.some(can)) el.style.display = 'none'; }); }

  /* ---------- Отчёт (документы) ---------- */
  function reportPdf() {
    if (!window.AppExport) { ui.toast('Экспорт недоступен'); return; }
    var sum = docs.reduce(function (s, d) { return s + (Number(d.amount) || 0); }, 0);
    var cols = [
      { key: 'number', label: '№' }, { key: 'doc_type', label: 'Тип', value: function (d) { return T[d.doc_type] || d.doc_type; } },
      { key: 'title', label: 'Название' }, { key: 'customer_name', label: 'Заказчик' },
      { key: 'status', label: 'Статус', value: function (d) { return ST[d.status] || d.status; } },
      { key: 'amount', label: 'Сумма', num: true, value: function (d) { return money(d.amount); } },
      { key: 'version', label: 'Версия', num: true },
      { key: 'created_at', label: 'Создан', value: function (d) { return fmt(d.created_at); } }
    ];
    AppExport.exportPdf('Документы — отчёт', AppExport.reportDocument({
      brand: '3DMP Service', title: 'Реестр документов', subtitle: new Date().toLocaleDateString('ru-RU'),
      kpis: [{ label: 'Документов', value: docs.length }, { label: 'Сумма', value: money(sum) }],
      sections: [{ title: 'Документы', columns: cols, rows: docs }],
      sign: ['Руководитель', 'Делопроизводство'], footer: '3DMP Service · документы'
    }));
  }
  $('#repBtn').addEventListener('click', reportPdf);

  function load() {
    return Promise.all([
      rpc('app_doc_list', { p_token: token, p_type: filter || null }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_customer_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      docs = r[0] || []; orders = r[1] || []; customers = r[2] || [];
      $('#fOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      fillCustomers('#fCustomerSel'); fillCustomers('#uCustomerSel');
      renderKpi(); render();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function fillCustomers(sel) {
    var el = $(sel); if (!el) return; var v = el.value;
    el.innerHTML = '<option value="">— не выбран —</option>' + customers.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + '</option>'; }).join('');
    el.value = v || '';
  }
  function renderKpi() {
    var c = { all: docs.length, kp: 0, contract: 0, act: 0, active: 0 };
    docs.forEach(function (d) { if (c[d.doc_type] != null) c[d.doc_type]++; if (d.status === 'active') c.active++; });
    $('#kpi').innerHTML =
      cell('Всего', c.all) + cell('КП', c.kp) + cell('Договоры', c.contract) + cell('Акты', c.act) + cell('В работе', c.active);
    function cell(t, v) { return '<div class="kpi"><small>' + t + '</small><b>' + v + '</b></div>'; }
  }
  function filtered() {
    var s = q.toLowerCase();
    return docs.filter(function (d) {
      if (!s) return true;
      return [d.number, d.title, d.counterparty, d.customer_name, d.order_number].join(' ').toLowerCase().indexOf(s) >= 0;
    });
  }
  function render() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Документов нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (d) {
      return '<div class="ocard" data-id="' + d.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
          '<span class="badge ' + d.status + '">' + (ST[d.status] || d.status) + '</span>' +
          '<span class="badge">' + (T[d.doc_type] || d.doc_type) + '</span>' +
          '<span class="note" style="margin-left:auto;">' + esc(d.number) + ' · v' + d.version + '</span></div>' +
        '<h3 style="font-size:.94rem;margin:8px 0 4px;">' + esc(d.title) + '</h3>' +
        '<div style="font-size:.78rem;color:var(--muted);">' +
          (d.customer_name || d.counterparty ? '🏢 ' + esc(d.customer_name || d.counterparty) + ' · ' : '') +
          (d.amount ? money(d.amount) + ' · ' : '') +
          (d.order_number ? '📥 ' + esc(d.order_number) + ' · ' : '') +
          (d.valid_until ? '⏳ до ' + esc(d.valid_until) + ' · ' : '') +
          fmt(d.updated_at) + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function openItem(id) {
    rpc('app_doc_get', { p_token: token, p_id: id }).then(function (r) {
      var d = r && r[0]; if (!d) { ui.toast('Документ не найден'); return; }
      cur = d;
      $('#doc').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
          '<span class="badge ' + d.status + '">' + (ST[d.status] || d.status) + '</span>' +
          '<span class="badge">' + (T[d.doc_type] || d.doc_type) + '</span>' +
          '<b style="margin-left:auto;">' + esc(d.number) + ' · v' + d.version + '</b></div>' +
        '<h1 style="font-size:1.15rem;margin:10px 0;">' + esc(d.title) + '</h1>' +
        kv('Заказчик', d.customer_name || d.counterparty) + kv('Заявка', d.order_number) +
        kv('Сумма', money(d.amount)) + kv('Срок действия', d.valid_until) +
        kv('Исполнитель', d.assignee) + kv('Подписан', d.signed_at ? fmt(d.signed_at) : '') +
        kv('Автор', d.created_login) + kv('Создан', fmt(d.created_at)) + kv('Обновлён', fmt(d.updated_at)) +
        (d.content ? '<div style="margin-top:10px;white-space:pre-wrap;font-size:.85rem;">' + esc(d.content) + '</div>' : '');
      $('#uTitle').value = d.title || ''; $('#uCounter').value = d.counterparty || '';
      $('#uAmount').value = d.amount != null ? d.amount : ''; $('#uContent').value = d.content || '';
      $('#uValid').value = d.valid_until || ''; $('#uAssignee').value = d.assignee || '';
      fillCustomers('#uCustomerSel'); $('#uCustomerSel').value = d.customer_id || '';
      clearMsg('#uMsg');
      loadVersions(id);
      if (window.AppFiles) window.AppFiles.mount({ token: token, entityType: 'document', entityId: id, el: '#filesBox' });
      screens.go('s-item');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function loadVersions(id) {
    rpc('app_doc_versions', { p_token: token, p_id: id }).then(function (list) {
      $('#versions').innerHTML = (list || []).map(function (v) {
        return '<div class="kvr"><span class="k">v' + v.version + '</span><b>' + esc(v.title || '') + '</b>' +
          '<span class="note" style="margin-left:auto;">' + fmt(v.created_at) + ' · ' + esc(v.by_login || '') + '</span></div>';
      }).join('') || '<span class="note">—</span>';
    });
  }

  $('#toNew').addEventListener('click', function () { clearMsg('#nMsg'); fillCustomers('#fCustomerSel'); screens.go('s-new'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; load();
  });
  $('#q').addEventListener('input', function () { q = this.value; render(); });

  $('#createBtn').addEventListener('click', function () {
    var title = $('#fTitle').value.trim(); if (!title) { msg('#nMsg', 'Укажите название.', 'err'); return; }
    var amt = parseFloat(($('#fAmount').value || '').replace(',', '.'));
    rpc('app_doc_create', {
      p_token: token, p_doc_type: $('#fType').value, p_title: title, p_order_id: $('#fOrder').value || null,
      p_counterparty: $('#fCounter').value.trim(), p_amount: isNaN(amt) ? null : amt, p_content: $('#fContent').value,
      p_customer_id: $('#fCustomerSel').value || null, p_valid_until: $('#fValid').value || null, p_assignee: $('#fAssignee').value.trim()
    }).then(function (d) {
      var row = d && d[0]; if (!row) { msg('#nMsg', 'Ошибка', 'err'); return; }
      window.Auth.log('Документ', row.number); ui.toast('Документ ' + row.number + ' создан');
      ['#fTitle', '#fCounter', '#fAmount', '#fContent', '#fValid', '#fAssignee'].forEach(function (s) { $(s).value = ''; });
      $('#fCustomerSel').value = ''; $('#fOrder').value = '';
      load().then(function () { openItem(row.id); });
    }).catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#saveBtn').addEventListener('click', function () {
    if (!cur) return;
    var amt = parseFloat(($('#uAmount').value || '').replace(',', '.'));
    rpc('app_doc_update', {
      p_token: token, p_id: cur.id, p_title: $('#uTitle').value.trim(), p_counterparty: $('#uCounter').value.trim(),
      p_amount: isNaN(amt) ? null : amt, p_content: $('#uContent').value,
      p_customer_id: $('#uCustomerSel').value || null, p_valid_until: $('#uValid').value || null, p_assignee: $('#uAssignee').value.trim()
    }).then(function (d) {
      var r = d && d[0]; msg('#uMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err');
      if (r && r.ok) { window.Auth.log('Правка документа', cur.number); load().then(function () { openItem(cur.id); }); }
    }).catch(function (e) { msg('#uMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#activeBtn').addEventListener('click', function () { setStatus('active'); });
  $('#archBtn').addEventListener('click', function () { setStatus('archived'); });
  function setStatus(st) {
    if (!cur) return;
    rpc('app_doc_set_status', { p_token: token, p_id: cur.id, p_status: st })
      .then(function (d) { var r = d && d[0]; if (r && r.ok) { window.Auth.log('Статус документа', cur.number + ' → ' + st); ui.toast(r.message); } load().then(function () { openItem(cur.id); }); });
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
