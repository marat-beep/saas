/* ============================================================
   3DMP Service · apps/hr — Кадры (X1: штат, график смен, отсутствия)
   Сотрудники ↔ пользователь (логин/роль), табель, обучение.
   Отпуск → приказ в КЭДО. Данные: 0016, 0040, 0187.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null;
  var emps = [], staffing = [], sched = [], absences = [], shifts = [], trains = [], depts = [], kpi = {};
  var eq = '', abStatus = '';
  var scFrom = '', scTo = '';

  var KINDS = { day: 'Дневная', night: 'Ночная', off: 'Выходной', vacation: 'Отпуск', sick: 'Больничный' };
  var SHIFTS = { '1': '1-я смена', '2': '2-я смена', '3': '3-я смена', day: 'Дневная', night: 'Ночная', off: 'Выходной' };
  var ABS = { vacation: 'Отпуск', sick: 'Больничный', leave: 'Отгул', unpaid: 'Без сохранения ЗП', other: 'Прочее' };
  var ABS_ST = { requested: 'Запрошено', approved: 'Утверждено', rejected: 'Отклонено', closed: 'Закрыто' };

  /* ---------- Роли (data-cap) ---------- */
  var ALL = { edit: 1, reports: 1 };
  var CAPS = { admin: ALL, owner: ALL, director: ALL, manager: ALL, chief: { edit: 1, reports: 1 }, hr: ALL, support: { reports: 1 }, default: {} };
  function can(c) { return !!(me && (CAPS[me.role] || CAPS['default'])[c]); }
  function applyCaps() { $$('[data-cap]').forEach(function (el) { var n = (el.dataset.cap || '').split('|'); if (!n.some(can)) el.style.display = 'none'; }); }
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? '—' : x.toLocaleDateString('ru-RU'); }
  function role(r) { return (window.Auth && window.Auth.roleLabel) ? window.Auth.roleLabel(r) : r; }
  function msg(id, t, k) { var e = $(id); if (e) { e.className = 'msg show ' + (k || 'info'); e.textContent = t; } }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function isoToday() { return new Date().toISOString().slice(0, 10); }
  function addDays(s, d) { var x = new Date(s); x.setDate(x.getDate() + d); return x.toISOString().slice(0, 10); }

  function load() {
    var f = scFrom || isoToday(), t = scTo || addDays(isoToday(), 14);
    return Promise.all([
      rpc('app_employees_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_hr_dashboard', { p_token: token }).catch(function () { return []; }),
      rpc('app_staffing_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_shift_schedule_list', { p_token: token, p_from: f, p_to: t, p_department: null }).catch(function () { return []; }),
      rpc('app_absence_list', { p_token: token, p_status: null }).catch(function () { return []; }),
      rpc('app_shifts_list', { p_token: token, p_from: null, p_to: null }).catch(function () { return []; }),
      rpc('app_training_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_departments_list', { p_token: token, p_q: null }).catch(function () { return []; })
    ]).then(function (r) {
      emps = r[0] || []; kpi = (r[1] && r[1][0]) || {}; staffing = r[2] || []; sched = r[3] || [];
      absences = r[4] || []; shifts = r[5] || []; trains = r[6] || []; depts = (r[7] || []).filter(function (d) { return d.active !== false; });
      renderKpi(); renderEmps(); renderStaffing(); renderSched(); renderAbs(); renderTabel(); renderTrain(); renderCaps();
    }).catch(function (e) { msg('#m', 'Ошибка: ' + e.message, 'err'); });
  }

  function cell(l, v) { return '<div class="kpi"><small class="l">' + l + '</small><b class="v">' + v + '</b></div>'; }
  function renderKpi() {
    $('#kpis').innerHTML =
      cell('Сотрудников', num(kpi.employees)) + cell('Активных', num(kpi.active)) +
      cell('Принято (мес)', num(kpi.hired_month)) + cell('Уволено (мес)', num(kpi.fired_month)) +
      cell('Текучесть (год)', num(kpi.turnover_pct) + '%') + cell('В отпуске сейчас', num(kpi.on_vacation_now)) +
      cell('Заявки отсутствий', num(kpi.absences_pending)) + cell('Смен в графике', num(kpi.shifts_plan_month)) +
      cell('Штат: план', num(kpi.staffing_headcount)) + cell('Штат: факт', num(kpi.staffing_fact));
  }

  /* ---------- Сотрудники ---------- */
  function empOptions() {
    return emps.filter(function (e) { return e.active; }).map(function (e) { return { value: e.id, label: e.full_name + (e.job ? ' · ' + e.job : '') }; });
  }
  function deptOptions() {
    return [{ value: '', label: '— без подразделения —' }].concat(depts.map(function (d) { return { value: d.id, label: d.name }; }));
  }
  function renderEmps() {
    var list = emps.filter(function (e) { if (!eq) return true; var s = eq.toLowerCase(); return [e.full_name, e.job, e.dept, e.user_login].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#empCount').textContent = '(' + list.length + ')';
    $('#emps').innerHTML = list.length ? list.map(function (e) {
      return '<div class="kvr"><b>' + esc(e.full_name) + '</b>' +
        '<span class="note">' + esc(e.job || '') + (e.dept ? ' · ' + esc(e.dept) : '') + '</span>' +
        (e.role ? '<span class="badge">' + esc(role(e.role)) + '</span>' : '') +
        (!e.active ? '<span class="badge cancelled">неактивен</span>' : '') +
        '<span class="m note">' + (e.user_login ? '🔑 ' + esc(e.user_login) + ' · ' : '') + 'смен: ' + num(e.shifts_month) +
        (e.phone ? ' · ' + esc(e.phone) : '') + '</span></div>';
    }).join('') : '<span class="note">Сотрудников нет.</span>';
  }
  $('#eq').addEventListener('input', function () { eq = this.value; renderEmps(); });

  $('#eAdd').addEventListener('click', function () {
    ui.formDialog({
      title: 'Новый сотрудник',
      fields: [
        { name: 'full_name', label: 'ФИО', required: true, placeholder: 'Иванов И.И.' },
        { name: 'position', label: 'Должность', placeholder: 'Оператор ЧПУ' },
        { name: 'dept', label: 'Отдел/цех', placeholder: 'Механообработка' },
        { name: 'phone', label: 'Телефон' },
        { name: 'email', label: 'E-mail' },
        { name: 'hired_at', label: 'Дата приёма', type: 'date', value: isoToday() },
        { name: 'user_login', label: 'Логин пользователя', hint: 'Роль подтянется из системы' }
      ]
    }).then(function (v) {
      if (!v) return;
      rpc('app_employee_save', { p_token: token, p_id: null, p_full_name: v.full_name, p_position: v.position, p_dept: v.dept,
        p_phone: v.phone, p_email: v.email, p_hired_at: v.hired_at || null, p_user_login: v.user_login })
        .then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово', r && r.ok ? 'ok' : 'err');
          if (r && r.ok) { window.Auth.log('Сотрудник', v.full_name); load(); } });
    });
  });

  /* ---------- Штатное расписание ---------- */
  function renderStaffing() {
    $('#staffing').innerHTML = staffing.length ? staffing.map(function (s) {
      var plan = num(s.headcount), fact = num(s.fact), dev = fact - plan;
      return '<div class="kvr"><b>' + esc(s.pos_title) + '</b>' +
        '<span class="note">' + esc(s.department || '—') + '</span>' +
        '<span class="badge">' + fact + ' / ' + plan + '</span>' +
        (dev < 0 ? '<span class="badge cancelled">недобор ' + (-dev) + '</span>' : (dev > 0 ? '<span class="badge done">сверх ' + dev + '</span>' : '')) +
        '<span class="m note">' + (s.rate ? 'ставка ' + num(s.rate) : '') + (s.salary ? ' · оклад ' + num(s.salary) + ' ₽' : '') + (s.note ? ' · ' + esc(s.note) : '') + '</span>' +
        '<button class="act" data-stedit="' + s.id + '" aria-label="Изменить" title="Изменить">✎</button>' +
        (can('edit') ? '<button class="act danger" data-stdel="' + s.id + '" aria-label="Удалить" title="Удалить">✕</button>' : '') + '</div>';
    }).join('') : '<span class="note">Штатное расписание пусто.</span>';
    $$('#staffing [data-stedit]').forEach(function (b) { b.addEventListener('click', function () { editStaffing(b.dataset.stedit); }); });
    $$('#staffing [data-stdel]').forEach(function (b) { b.addEventListener('click', function () { delStaffing(b.dataset.stdel); }); });
  }
  function staffForm(row) {
    ui.formDialog({
      title: row ? 'Строка штата' : 'Новая строка штата',
      fields: [
        { name: 'department_id', label: 'Подразделение', type: 'select', options: deptOptions(), value: row ? (row.department_id || '') : '' },
        { name: 'position', label: 'Должность', required: true, value: row ? row.pos_title : '' },
        { name: 'rate', label: 'Ставка', type: 'number', value: row ? row.rate : 1 },
        { name: 'salary', label: 'Оклад, ₽', type: 'number', value: row ? row.salary : '' },
        { name: 'count', label: 'Плановая численность', type: 'number', value: row ? row.headcount : 1 },
        { name: 'note', label: 'Примечание', value: row ? (row.note || '') : '' }
      ]
    }).then(function (v) {
      if (!v) return;
      rpc('app_staffing_save', { p_token: token, p_id: row ? row.id : null, p_department_id: v.department_id || null,
        p_department: '', p_position: v.position, p_rate: v.rate ? num(v.rate) : 1, p_salary: v.salary ? num(v.salary) : null,
        p_count: v.count ? parseInt(v.count, 10) : 1, p_note: v.note })
        .then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово', r && r.ok ? 'ok' : 'err'); if (r && r.ok) load(); });
    });
  }
  function editStaffing(id) { var row = staffing.filter(function (x) { return x.id === id; })[0]; if (row) staffForm(row); }
  function delStaffing(id) { ui.confirmDialog('Удалить строку штата?').then(function (ok) { if (!ok) return;
    rpc('app_staffing_delete', { p_token: token, p_id: id }).then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово', r && r.ok ? 'ok' : 'err'); if (r && r.ok) load(); }); }); }
  $('#stAdd').addEventListener('click', function () { staffForm(null); });

  /* ---------- График смен ---------- */
  function renderSched() {
    $('#sched').innerHTML = sched.length ? sched.map(function (s) {
      return '<div class="kvr"><span class="note">' + fmt(s.shift_date) + '</span><b>' + esc(s.employee) + '</b>' +
        '<span class="note">' + esc(s.department || '') + '</span>' +
        '<span class="badge">' + (SHIFTS[s.shift_type] || s.shift_type) + ' · ' + num(s.hours) + ' ч</span>' +
        (s.absence ? '<span class="badge cancelled">отсутствие: ' + esc(ABS[s.absence] || s.absence) + '</span>' : '') +
        '<span class="m">' + (s.note ? '<span class="note">' + esc(s.note) + '</span>' : '') +
        (can('edit') ? '<button class="act danger" data-scdel="' + s.id + '" aria-label="Удалить" title="Удалить">✕</button>' : '') + '</span></div>';
    }).join('') : '<span class="note">Смен в периоде нет.</span>';
    $$('#sched [data-scdel]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_shift_schedule_delete', { p_token: token, p_id: b.dataset.scdel }).then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово', r && r.ok ? 'ok' : 'err'); if (r && r.ok) load(); }); }); });
  }
  $('#scLoad').addEventListener('click', function () { scFrom = $('#scFrom').value; scTo = $('#scTo').value; load(); });
  $('#scAdd').addEventListener('click', function () {
    ui.formDialog({
      title: 'Смена в график',
      fields: [
        { name: 'employee_id', label: 'Сотрудник', type: 'select', required: true, options: empOptions() },
        { name: 'date', label: 'Дата', type: 'date', required: true, value: isoToday() },
        { name: 'shift_type', label: 'Смена', type: 'select', options: [{ value: '1', label: '1-я смена' }, { value: '2', label: '2-я смена' }, { value: '3', label: '3-я смена' }, { value: 'off', label: 'Выходной' }] },
        { name: 'hours', label: 'Часы', type: 'number', value: 8 },
        { name: 'note', label: 'Примечание' }
      ]
    }).then(function (v) {
      if (!v) return;
      rpc('app_shift_schedule_save', { p_token: token, p_id: null, p_employee_id: v.employee_id, p_date: v.date,
        p_shift_type: v.shift_type, p_hours: v.hours ? num(v.hours) : 8, p_note: v.note })
        .then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово', r && r.ok ? 'ok' : 'err'); if (r && r.ok) load(); });
    });
  });

  /* ---------- Отсутствия ---------- */
  function renderAbs() {
    var list = absences.filter(function (a) { return !abStatus || a.status === abStatus; });
    $('#abs').innerHTML = list.length ? list.map(function (a) {
      return '<div class="kvr"><b>' + esc(a.employee) + '</b>' +
        '<span class="badge">' + esc(ABS[a.kind] || a.kind) + '</span>' +
        '<span class="note">' + fmt(a.date_from) + '–' + fmt(a.date_to) + ' · ' + num(a.days) + ' дн.</span>' +
        '<span class="badge ' + (a.status === 'approved' ? 'done' : (a.status === 'rejected' ? 'cancelled' : 'in_progress')) + '">' + (ABS_ST[a.status] || a.status) + '</span>' +
        (a.hr_doc_number ? '<span class="note">приказ ' + esc(a.hr_doc_number) + '</span>' : '') +
        '<span class="m">' +
        (can('edit') && a.status !== 'approved' ? '<button class="act" data-abok="' + a.id + '">Утвердить</button>' : '') +
        (can('edit') && a.status !== 'rejected' ? '<button class="act danger" data-abno="' + a.id + '">Отклонить</button>' : '') +
        (can('edit') ? '<button class="act" data-absedit="' + a.id + '" aria-label="Изменить" title="Изменить">✎</button>' : '') + '</span></div>';
    }).join('') : '<span class="note">Отсутствий нет.</span>';
    $$('#abs [data-abok]').forEach(function (b) { b.addEventListener('click', function () { setAbs(b.dataset.abok, 'approved'); }); });
    $$('#abs [data-abno]').forEach(function (b) { b.addEventListener('click', function () { setAbs(b.dataset.abno, 'rejected'); }); });
    $$('#abs [data-absedit]').forEach(function (b) { b.addEventListener('click', function () { editAbs(b.dataset.absedit); }); });
  }
  function setAbs(id, st) {
    rpc('app_absence_set_status', { p_token: token, p_id: id, p_status: st }).then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово', r && r.ok ? 'ok' : 'err'); if (r && r.ok) load(); });
  }
  function absForm(row) {
    ui.formDialog({
      title: row ? 'Отсутствие' : 'Новое отсутствие',
      fields: [
        { name: 'employee_id', label: 'Сотрудник', type: 'select', required: true, options: empOptions(), value: row ? (row.employee_id || '') : '' },
        { name: 'kind', label: 'Вид', type: 'select', options: [{ value: 'vacation', label: 'Отпуск' }, { value: 'sick', label: 'Больничный' }, { value: 'leave', label: 'Отгул' }, { value: 'unpaid', label: 'Без сохранения ЗП' }, { value: 'other', label: 'Прочее' }], value: row ? row.kind : 'vacation' },
        { name: 'from', label: 'С даты', type: 'date', required: true, value: row ? row.date_from : isoToday() },
        { name: 'to', label: 'По дату', type: 'date', required: true, value: row ? row.date_to : isoToday() },
        { name: 'status', label: 'Статус', type: 'select', options: [{ value: 'requested', label: 'Запрошено' }, { value: 'approved', label: 'Утверждено' }, { value: 'rejected', label: 'Отклонено' }, { value: 'closed', label: 'Закрыто' }], value: row ? row.status : 'requested' },
        { name: 'note', label: 'Примечание', value: row ? (row.note || '') : '' }
      ]
    }).then(function (v) {
      if (!v) return;
      rpc('app_absence_save', { p_token: token, p_id: row ? row.id : null, p_employee_id: v.employee_id, p_kind: v.kind,
        p_from: v.from, p_to: v.to, p_status: v.status, p_note: v.note })
        .then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово', r && r.ok ? 'ok' : 'err'); if (r && r.ok) load(); });
    });
  }
  function editAbs(id) { var row = absences.filter(function (x) { return x.id === id; })[0]; if (row) absForm(row); }
  $('#abAdd').addEventListener('click', function () { absForm(null); });
  $('#abStatus').addEventListener('change', function () { abStatus = this.value; renderAbs(); });
  $('#scanBtn').addEventListener('click', function () {
    rpc('app_absence_scan', { p_token: token }).then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Проверено', r && r.ok !== false ? 'ok' : 'err'); });
  });

  /* ---------- Табель (факт) ---------- */
  function renderTabel() {
    $('#tabel').innerHTML = shifts.length ? shifts.slice(0, 80).map(function (s) {
      return '<div class="kvr"><span class="note">' + fmt(s.shift_date) + '</span><b>' + esc(s.employee) + '</b>' +
        '<span class="note">' + (KINDS[s.kind] || s.kind) + ' · ' + num(s.hours) + ' ч</span>' +
        (can('edit') ? '<span class="m"><button class="act danger" data-tbdel="' + s.id + '" aria-label="Удалить" title="Удалить">✕</button></span>' : '') + '</div>';
    }).join('') : '<span class="note">Записей табеля нет.</span>';
    $$('#tabel [data-tbdel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_shift_delete', { p_token: token, p_id: b.dataset.tbdel }).then(function () { ui.toast('Удалено'); load(); }); }); });
  }
  $('#tbAdd').addEventListener('click', function () {
    ui.formDialog({
      title: 'Запись табеля',
      fields: [
        { name: 'employee_id', label: 'Сотрудник', type: 'select', required: true, options: empOptions() },
        { name: 'date', label: 'Дата', type: 'date', required: true, value: isoToday() },
        { name: 'kind', label: 'Тип', type: 'select', options: [{ value: 'day', label: 'Дневная' }, { value: 'night', label: 'Ночная' }, { value: 'off', label: 'Выходной' }, { value: 'vacation', label: 'Отпуск' }, { value: 'sick', label: 'Больничный' }] },
        { name: 'hours', label: 'Часы', type: 'number', value: 8 }
      ]
    }).then(function (v) {
      if (!v) return;
      rpc('app_shift_add', { p_token: token, p_employee_id: v.employee_id, p_date: v.date, p_kind: v.kind, p_hours: v.hours ? num(v.hours) : 8, p_note: '' })
        .then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово', r && r.ok ? 'ok' : 'err'); if (r && r.ok) load(); });
    });
  });

  /* ---------- Обучение ---------- */
  function renderTrain() {
    $('#train').innerHTML = trains.length ? trains.map(function (t) {
      return '<div class="kvr"><b>' + esc(t.employee) + '</b><span>' + esc(t.title) + '</span>' +
        '<span class="badge ' + (t.status === 'passed' ? 'done' : 'in_progress') + '">' + (t.status === 'passed' ? 'пройдено' : 'запланировано') + '</span>' +
        '<span class="note">' + (t.train_date ? fmt(t.train_date) : '') + '</span>' +
        (t.status !== 'passed' && can('edit') ? '<span class="m"><button class="act" data-pass="' + t.id + '">Отметить пройдено</button></span>' : '') + '</div>';
    }).join('') : '<span class="note">Записей нет.</span>';
    $$('#train [data-pass]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_training_set_status', { p_token: token, p_id: b.dataset.pass, p_status: 'passed' }).then(function () { load(); }); }); });
  }
  $('#trAdd').addEventListener('click', function () {
    ui.formDialog({
      title: 'Обучение',
      fields: [
        { name: 'employee_id', label: 'Сотрудник', type: 'select', required: true, options: empOptions() },
        { name: 'title', label: 'Тема', required: true, placeholder: 'Охрана труда' },
        { name: 'status', label: 'Статус', type: 'select', options: [{ value: 'planned', label: 'Запланировано' }, { value: 'passed', label: 'Пройдено' }] },
        { name: 'date', label: 'Дата', type: 'date' }
      ]
    }).then(function (v) {
      if (!v) return;
      rpc('app_training_add', { p_token: token, p_employee_id: v.employee_id, p_title: v.title, p_status: v.status, p_date: v.date || null, p_note: '' })
        .then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово', r && r.ok ? 'ok' : 'err'); if (r && r.ok) load(); });
    });
  });

  /* ---------- Доступ по ролям ---------- */
  function renderCaps() {
    var rows = ['admin', 'owner', 'director', 'manager', 'chief', 'hr', 'support'];
    $('#caps').innerHTML = '<div class="tbl-wrap"><table class="matrix"><thead><tr><th>Роль</th><th>Правка</th><th>Отчёты</th></tr></thead><tbody>' +
      rows.map(function (r) { var c = CAPS[r] || {}; return '<tr><td>' + esc(role(r)) + '</td><td>' + (c.edit ? '✔' : '—') + '</td><td>' + (c.reports ? '✔' : '—') + '</td></tr>'; }).join('') +
      '</tbody></table></div>';
  }

  /* ---------- Отчёт ---------- */
  function reportPdf() {
    if (!window.AppExport) { ui.toast('Экспорт недоступен'); return; }
    var cols = [
      { key: 'full_name', label: 'ФИО' }, { key: 'job', label: 'Должность' }, { key: 'dept', label: 'Подразделение' },
      { key: 'user_login', label: 'Логин' }, { key: 'role', label: 'Роль', value: function (e) { return e.role ? role(e.role) : ''; } },
      { key: 'shifts_month', label: 'Смен/мес', num: true, value: function (e) { return num(e.shifts_month); } },
      { key: 'active', label: 'Статус', value: function (e) { return e.active ? 'активен' : 'неактивен'; } }
    ];
    AppExport.exportPdf('Кадры — отчёт', AppExport.reportDocument({
      brand: '3DMP Service', title: 'Численность и текучесть', subtitle: new Date().toLocaleDateString('ru-RU'),
      kpis: [
        { label: 'Сотрудников', value: num(kpi.employees) }, { label: 'Активных', value: num(kpi.active) },
        { label: 'Принято (мес)', value: num(kpi.hired_month) }, { label: 'Уволено (мес)', value: num(kpi.fired_month) },
        { label: 'Текучесть (год), %', value: num(kpi.turnover_pct) }, { label: 'Штат: план/факт', value: num(kpi.staffing_headcount) + ' / ' + num(kpi.staffing_fact) }
      ],
      sections: [
        { title: 'Сотрудники', columns: cols, rows: emps },
        { title: 'Штатное расписание', columns: [
          { key: 'department', label: 'Подразделение' }, { key: 'pos_title', label: 'Должность' },
          { key: 'headcount', label: 'План', num: true }, { key: 'fact', label: 'Факт', num: true }, { key: 'salary', label: 'Оклад', num: true }
        ], rows: staffing }
      ],
      sign: ['Руководитель', 'Отдел кадров'], footer: '3DMP Service · кадры'
    }));
  }
  $('#repBtn').addEventListener('click', reportPdf);

  /* ---------- Навигация ---------- */
  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + b.dataset.scr); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  /* R4·PROP-21: расчёт зарплаты и подбор персонала */
  var hrlPr = [], hrlVac = [], hrlCand = [];
  var CST = { new: 'Новый', interview: 'Интервью', offer: 'Оффер', hired: 'Принят', rejected: 'Отказ' };
  function rub(v) { return (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 0 }) + ' ₽'; }
  function loadHrl() {
    return Promise.all([
      rpc('app_payroll_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_vacancy_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_candidate_list', { p_token: token, p_vacancy: null }).catch(function () { return []; })
    ]).then(function (r) { hrlPr = r[0] || []; hrlVac = r[1] || []; hrlCand = r[2] || []; renderHrl(); });
  }
  function renderHrl() {
    var host = $('#hrl'); if (!host) return;
    var fund = hrlPr.reduce(function (s, p) { return s + (Number(p.total) || 0); }, 0);
    var pay = '<div class="card"><h2>Расчёт зарплаты</h2>' +
      '<div class="kpi-row"><div class="kpi"><small>Ведомостей</small><b>' + hrlPr.length + '</b></div><div class="kpi"><small>Фонд (итог)</small><b>' + rub(fund) + '</b></div></div>' +
      '<div class="grid3"><div class="field"><label>Период</label><input type="date" id="prPer"></div><div class="field"><label>Сотрудник *</label><input type="text" id="prEmp"></div><div class="field"><label>Оклад, ₽</label><input type="text" id="prBase" inputmode="decimal"></div></div>' +
      '<div class="grid3"><div class="field"><label>Премия, ₽</label><input type="text" id="prBon" inputmode="decimal"></div><div class="field"><label>Удержание, ₽</label><input type="text" id="prDed" inputmode="decimal"></div><div class="field" style="display:flex;align-items:flex-end;"><button class="btn" id="prAdd" style="width:auto;">Добавить</button></div></div>' +
      (hrlPr.length ? '<div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Период</th><th>Сотрудник</th><th class="num">Оклад</th><th class="num">Премия</th><th class="num">Удерж.</th><th class="num">Итог</th><th></th></tr></thead><tbody>' +
        hrlPr.map(function (p) { return '<tr><td>' + esc(p.period) + '</td><td><b>' + esc(p.employee) + '</b></td><td class="num">' + rub(p.base) + '</td><td class="num">' + rub(p.bonus) + '</td><td class="num">' + rub(p.deduction) + '</td><td class="num"><b>' + rub(p.total) + '</b></td><td><button class="act danger" data-prdel="' + p.id + '" aria-label="Удалить" title="Удалить">✕</button></td></tr>'; }).join('') + '</tbody></table></div>'
        : '<span class="note">Ведомостей нет.</span>') + '</div>';
    var vac = '<div class="card"><h2>Подбор персонала</h2>' +
      '<div class="grid3"><div class="field"><label>Вакансия *</label><input type="text" id="vcTitle"></div><div class="field"><label>Отдел</label><input type="text" id="vcDept"></div><div class="field" style="display:flex;align-items:flex-end;"><button class="btn" id="vcAdd" style="width:auto;">Открыть вакансию</button></div></div>' +
      (hrlVac.length ? '<div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Вакансия</th><th>Отдел</th><th>Статус</th><th class="num">Канд.</th></tr></thead><tbody>' + hrlVac.map(function (v) { return '<tr><td><b>' + esc(v.title) + '</b></td><td>' + esc(v.dept || '—') + '</td><td>' + (v.status === 'open' ? 'открыта' : 'закрыта') + '</td><td class="num">' + num(v.candidates) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Вакансий нет.</span>') +
      '<h3 style="margin:10px 0 4px;font-size:.82rem;">Кандидаты</h3>' +
      '<div class="grid3"><div class="field"><label>Вакансия</label><select id="cdVac"><option value="">— без привязки —</option>' + hrlVac.map(function (v) { return '<option value="' + v.id + '">' + esc(v.title) + '</option>'; }).join('') + '</select></div><div class="field"><label>Имя *</label><input type="text" id="cdName"></div><div class="field" style="display:flex;align-items:flex-end;"><button class="btn" id="cdAdd" style="width:auto;">Добавить кандидата</button></div></div>' +
      (hrlCand.length ? '<div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Кандидат</th><th>Вакансия</th><th>Этап</th><th></th></tr></thead><tbody>' +
        hrlCand.map(function (c) { var v = hrlVac.filter(function (x) { return x.id === c.vacancy_id; })[0]; var nx = c.stage === 'new' ? 'interview' : c.stage === 'interview' ? 'offer' : c.stage === 'offer' ? 'hired' : null;
          return '<tr><td><b>' + esc(c.name) + '</b></td><td>' + esc(v ? v.title : '—') + '</td><td>' + esc(CST[c.stage] || c.stage) + '</td>' +
            '<td style="white-space:nowrap;">' + (nx ? '<button class="act" data-cdadv="' + c.id + '" data-next="' + nx + '">→ ' + CST[nx] + '</button>' : '') + '<button class="act danger" data-cdrej="' + c.id + '" title="Отказ">✕</button></td></tr>'; }).join('') + '</tbody></table></div>'
        : '<span class="note">Кандидатов нет.</span>') + '</div>';
    host.innerHTML = '<div class="cols2" style="display:grid;grid-template-columns:1fr 1fr;gap:16px;align-items:start;">' + pay + vac + '</div>';
    $('#prAdd').addEventListener('click', function () {
      rpc('app_payroll_save', { p_token: token, p_id: null, p_period: $('#prPer').value || null, p_employee: $('#prEmp').value.trim(), p_base: parseFloat($('#prBase').value.replace(',', '.')) || 0, p_bonus: parseFloat($('#prBon').value.replace(',', '.')) || 0, p_deduction: parseFloat($('#prDed').value.replace(',', '.')) || 0, p_note: null })
        .then(function (r) { var x = r && r[0]; ui.toast(x ? x.message : ''); if (x && x.ok) loadHrl(); }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
    });
    ui.qsa('#hrl [data-prdel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_payroll_delete', { p_token: token, p_id: b.dataset.prdel }).then(loadHrl); }); });
    $('#vcAdd').addEventListener('click', function () {
      rpc('app_vacancy_save', { p_token: token, p_id: null, p_title: $('#vcTitle').value.trim(), p_dept: $('#vcDept').value.trim() || null, p_status: 'open' })
        .then(function (r) { var x = r && r[0]; ui.toast(x ? x.message : ''); if (x && x.ok) loadHrl(); }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
    });
    $('#cdAdd').addEventListener('click', function () {
      rpc('app_candidate_save', { p_token: token, p_id: null, p_vacancy: $('#cdVac').value || null, p_name: $('#cdName').value.trim(), p_stage: 'new', p_note: null })
        .then(function (r) { var x = r && r[0]; ui.toast(x ? x.message : ''); if (x && x.ok) loadHrl(); }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
    });
    ui.qsa('#hrl [data-cdadv]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_candidate_set_stage', { p_token: token, p_id: b.dataset.cdadv, p_stage: b.dataset.next }).then(loadHrl); }); });
    ui.qsa('#hrl [data-cdrej]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Отклонить кандидата?')) return; rpc('app_candidate_set_stage', { p_token: token, p_id: b.dataset.cdrej, p_stage: 'rejected' }).then(loadHrl); }); });
  }

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token; applyCaps();
    loadHrl();
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#m', 'Supabase не подключён.', 'err'); return; }
    $('#scFrom').value = isoToday(); $('#scTo').value = addDays(isoToday(), 14);
    load();
  });
})();
