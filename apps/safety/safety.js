/* ============================================================
   3DMP Service · apps/safety — Охрана труда/EHS (W21, 0168).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null;
  var BK = { intro: 'Вводный', primary: 'Первичный', repeat: 'Повторный', unscheduled: 'Внеплановый' };
  var WT = { hot: 'Огневые', height: 'На высоте', electric: 'Электро', confined: 'Замкнутое пространство', other: 'Прочее' };
  var PM = { draft: 'Черновик', approved: 'Утверждён', active: 'Действует', closed: 'Закрыт', cancelled: 'Отменён' };
  var IM = { microtrauma: 'Микротравма', incident: 'Инцидент', accident: 'Несчастный случай', fire: 'Пожар', eco: 'Экология' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dd(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }
  function tbl(head, rows) { return '<div class="tbl-wrap"><table class="tbl"><thead><tr>' + head + '</tr></thead><tbody>' + rows + '</tbody></table></div>'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'br') loadBr(); if (scr === 'pm') loadPm(); if (scr === 'ppe') loadPpe(); if (scr === 'med') loadMed(); if (scr === 'inc') loadInc();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_ehs_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Инструктажей', k.briefings || 0) + cell('Просрочено ОТ', k.briefings_overdue || 0) + cell('Активных допусков', k.permits_active || 0) + cell('СИЗ к замене', k.ppe_due || 0) + cell('Медосмотры', k.medical_due || 0) + cell('Инцидентов откр.', k.incidents_open || 0);
    }).catch(function () {});
  }

  function loadBr() { return rpc('app_briefing_list', { p_token: token }).then(function (r) { var l = r || []; $('#br').innerHTML = l.length ? tbl('<th>Сотрудник</th><th>Вид</th><th>Тема</th><th>Дата</th><th>Повтор</th>', l.map(function (x) { return '<tr><td>' + esc(x.employee_login || '') + '</td><td>' + esc(BK[x.kind] || x.kind) + '</td><td>' + esc(x.topic || '') + '</td><td>' + dd(x.brief_date) + '</td><td>' + dd(x.next_date) + '</td></tr>'; }).join('')) : '<span class="note">Нет данных.</span>'; }); }
  function addBr() { ui.formDialog({ title: 'Инструктаж', okText: 'Добавить', fields: [
    { name: 'employee', label: 'Сотрудник', type: 'text', required: true }, { name: 'kind', label: 'Вид', type: 'select', options: Object.keys(BK).map(function (k) { return { value: k, label: BK[k] }; }) },
    { name: 'topic', label: 'Тема', type: 'text' }, { name: 'date', label: 'Дата', type: 'date' }, { name: 'next', label: 'Следующий', type: 'date' } ], values: { kind: 'repeat', date: new Date().toISOString().slice(0, 10) } }).then(function (v) { if (!v) return; rpc('app_briefing_save', { p_token: token, p_id: null, p_employee: v.employee, p_kind: v.kind, p_topic: v.topic || null, p_date: v.date || null, p_instructor: null, p_next: v.next || null, p_note: null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadBr(); loadKpi(); }); }); }

  function loadPm() { return rpc('app_permit_list', { p_token: token }).then(function (r) { var l = r || []; $('#pm').innerHTML = l.length ? tbl('<th>№</th><th>Вид</th><th>Место</th><th>Срок</th><th>Статус</th><th></th>', l.map(function (x) { var a = ''; if (x.status === 'draft') a = '<button class="act" data-pst="approved" data-id="' + x.id + '">Утвердить</button>'; if (x.status === 'approved') a = '<button class="act" data-pst="active" data-id="' + x.id + '">В работу</button>'; if (x.status === 'active') a = '<button class="act" data-pst="closed" data-id="' + x.id + '">Закрыть</button>'; return '<tr><td>' + esc(x.number || '') + '</td><td>' + esc(WT[x.work_type] || x.work_type) + '</td><td>' + esc(x.location || '') + '</td><td>' + dd(x.valid_from) + '—' + dd(x.valid_to) + '</td><td>' + esc(PM[x.status] || x.status) + '</td><td>' + a + '</td></tr>'; }).join('')) : '<span class="note">Нет нарядов-допусков.</span>'; $$('#pm [data-pst]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_permit_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.pst }).then(function () { loadPm(); loadKpi(); }); }); }); }); }
  function addPm() { ui.formDialog({ title: 'Наряд-допуск', okText: 'Создать', fields: [
    { name: 'number', label: 'Номер', type: 'text' }, { name: 'work_type', label: 'Вид работ', type: 'select', options: Object.keys(WT).map(function (k) { return { value: k, label: WT[k] }; }) },
    { name: 'location', label: 'Место', type: 'text' }, { name: 'responsible', label: 'Ответственный', type: 'text' }, { name: 'workers', label: 'Исполнители', type: 'text' },
    { name: 'from', label: 'С', type: 'date' }, { name: 'to', label: 'По', type: 'date' } ], values: { work_type: 'hot' } }).then(function (v) { if (!v) return; rpc('app_permit_save', { p_token: token, p_id: null, p_number: v.number || null, p_work_type: v.work_type, p_location: v.location || null, p_responsible: v.responsible || null, p_workers: v.workers || null, p_from: v.from || null, p_to: v.to || null, p_note: null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadPm(); loadKpi(); }); }); }

  function loadPpe() { return rpc('app_ppe_list', { p_token: token }).then(function (r) { var l = r || []; $('#ppe').innerHTML = l.length ? tbl('<th>Сотрудник</th><th>СИЗ</th><th>Размер</th><th>Выдано</th><th>Замена до</th><th>Статус</th>', l.map(function (x) { return '<tr><td>' + esc(x.employee_login || '') + '</td><td>' + esc(x.item) + '</td><td>' + esc(x.size || '') + '</td><td>' + dd(x.issued_at) + '</td><td>' + dd(x.due_at) + '</td><td>' + esc(x.status) + '</td></tr>'; }).join('')) : '<span class="note">Нет СИЗ.</span>'; }); }
  function addPpe() { ui.formDialog({ title: 'Выдача СИЗ', okText: 'Добавить', fields: [
    { name: 'employee', label: 'Сотрудник', type: 'text' }, { name: 'item', label: 'СИЗ', type: 'text', required: true }, { name: 'size', label: 'Размер', type: 'text' },
    { name: 'issued', label: 'Выдано', type: 'date' }, { name: 'due', label: 'Замена до', type: 'date' } ], values: { issued: new Date().toISOString().slice(0, 10) } }).then(function (v) { if (!v) return; rpc('app_ppe_save', { p_token: token, p_id: null, p_employee: v.employee || null, p_item: v.item, p_size: v.size || null, p_issued: v.issued || null, p_due: v.due || null, p_status: 'issued', p_note: null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadPpe(); loadKpi(); }); }); }

  function loadMed() { return rpc('app_medical_list', { p_token: token }).then(function (r) { var l = r || []; $('#med').innerHTML = l.length ? tbl('<th>Сотрудник</th><th>Вид</th><th>Дата</th><th>Следующий</th><th>Результат</th>', l.map(function (x) { return '<tr><td>' + esc(x.employee_login || '') + '</td><td>' + esc(x.kind) + '</td><td>' + dd(x.check_date) + '</td><td>' + dd(x.next_date) + '</td><td>' + esc(x.result) + '</td></tr>'; }).join('')) : '<span class="note">Нет медосмотров.</span>'; }); }
  function addMed() { ui.formDialog({ title: 'Медосмотр', okText: 'Добавить', fields: [
    { name: 'employee', label: 'Сотрудник', type: 'text', required: true }, { name: 'kind', label: 'Вид', type: 'select', options: [{ value: 'prelim', label: 'Предварительный' }, { value: 'periodic', label: 'Периодический' }] },
    { name: 'date', label: 'Дата', type: 'date' }, { name: 'next', label: 'Следующий', type: 'date' }, { name: 'result', label: 'Результат', type: 'text' } ], values: { kind: 'periodic', date: new Date().toISOString().slice(0, 10), result: 'fit' } }).then(function (v) { if (!v) return; rpc('app_medical_save', { p_token: token, p_id: null, p_employee: v.employee, p_kind: v.kind, p_date: v.date || null, p_next: v.next || null, p_result: v.result || 'fit', p_clinic: null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadMed(); loadKpi(); }); }); }

  function loadInc() { return rpc('app_incident_list', { p_token: token }).then(function (r) { var l = r || []; $('#inc').innerHTML = l.length ? tbl('<th>Дата</th><th>Вид</th><th>Место</th><th>Описание</th><th>Тяжесть</th><th>Статус</th><th></th>', l.map(function (x) { return '<tr><td>' + dd(x.event_date) + '</td><td>' + esc(IM[x.kind] || x.kind) + '</td><td>' + esc(x.location || '') + '</td><td>' + esc(x.description || '') + '</td><td>' + esc(x.severity) + '</td><td>' + esc(x.status) + '</td><td>' + (x.status !== 'closed' ? '<button class="act" data-ist="closed" data-id="' + x.id + '">Закрыть</button>' : '') + '</td></tr>'; }).join('')) : '<span class="note">Нет инцидентов.</span>'; $$('#inc [data-ist]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_incident_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.ist }).then(function () { loadInc(); loadKpi(); }); }); }); }); }
  function addInc() { ui.formDialog({ title: 'Инцидент', okText: 'Зарегистрировать', fields: [
    { name: 'kind', label: 'Вид', type: 'select', options: Object.keys(IM).map(function (k) { return { value: k, label: IM[k] }; }) }, { name: 'date', label: 'Дата', type: 'date' },
    { name: 'location', label: 'Место', type: 'text' }, { name: 'description', label: 'Описание', type: 'textarea', rows: 2, required: true }, { name: 'severity', label: 'Тяжесть', type: 'select', options: [{ value: 'low', label: 'Низкая' }, { value: 'medium', label: 'Средняя' }, { value: 'high', label: 'Высокая' }] } ], values: { kind: 'incident', severity: 'low', date: new Date().toISOString().slice(0, 10) } }).then(function (v) { if (!v) return; rpc('app_incident_save', { p_token: token, p_id: null, p_kind: v.kind, p_date: v.date || null, p_location: v.location || null, p_description: v.description, p_severity: v.severity, p_actions: null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadInc(); loadKpi(); }); }); }

  $('#addBr').addEventListener('click', addBr);
  $('#addPm').addEventListener('click', addPm);
  $('#addPpe').addEventListener('click', addPpe);
  $('#addMed').addEventListener('click', addMed);
  $('#addInc').addEventListener('click', addInc);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadKpi(); loadBr();
  });
})();
