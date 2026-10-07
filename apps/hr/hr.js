/* ============================================================
   3DMP Service · apps/hr — Кадры (сотрудники, смены, обучение)
   Связь сотрудник ↔ пользователь (логин/роль). Данные: 0016+0040.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, emps = [], shifts = [], trains = [], eq = '';

  var KINDS = { day: 'Дневная', night: 'Ночная', off: 'Выходной', vacation: 'Отпуск', sick: 'Больничный' };

  /* ---------- Роли (data-cap) ---------- */
  var ALL = { edit: 1, reports: 1 };
  var CAPS = { admin: ALL, owner: ALL, director: ALL, manager: ALL, chief: { edit: 1, reports: 1 }, hr: ALL, support: { reports: 1 }, default: {} };
  function can(c) { return !!(me && (CAPS[me.role] || CAPS['default'])[c]); }
  function applyCaps() { $$('[data-cap]').forEach(function (el) { var n = (el.dataset.cap || '').split('|'); if (!n.some(can)) el.style.display = 'none'; }); }
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? '—' : x.toLocaleDateString('ru-RU'); }
  function role(r) { return (window.Auth && window.Auth.roleLabel) ? window.Auth.roleLabel(r) : r; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_employees_list', { p_token: token }),
      rpc('app_shifts_list', { p_token: token, p_from: null, p_to: null }).catch(function () { return []; }),
      rpc('app_training_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_hr_kpi', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      emps = r[0] || []; shifts = r[1] || []; trains = r[2] || []; var k = (r[3] && r[3][0]) || {};
      $('#kpis').innerHTML = cell('Сотрудников', num(k.employees)) + cell('Смен за месяц', num(k.shifts_month)) +
        cell('Часов за месяц', num(k.hours_month)) + cell('Обучение (план)', num(k.trainings_planned)) + cell('Обучение (пройдено)', num(k.trainings_passed));
      var opts = emps.filter(function (e) { return e.active; }).map(function (e) { return '<option value="' + e.id + '">' + esc(e.full_name) + '</option>'; }).join('');
      $('#shEmp').innerHTML = opts; $('#trEmp').innerHTML = opts;
      renderEmps(); renderShifts(); renderTrains();
    }).catch(function (e) { msg('#eMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function renderEmps() {
    var list = emps.filter(function (e) { if (!eq) return true; var s = eq.toLowerCase(); return [e.full_name, e.job, e.dept, e.user_login].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#empCount').textContent = '(' + list.length + ')';
    $('#emps').innerHTML = list.length ? list.map(function (e) {
      return '<div class="kvr"><b>' + esc(e.full_name) + '</b>' +
        '<span class="note">' + esc(e.job || '') + (e.dept ? ' · ' + esc(e.dept) : '') + '</span>' +
        (e.role ? '<span class="badge">' + esc(role(e.role)) + '</span>' : '') +
        (!e.active ? '<span class="badge cancelled">неактивен</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + (e.user_login ? '🔑 ' + esc(e.user_login) + ' · ' : '') +
        'смен: ' + e.shifts_month + (e.trainings_open ? ' · обуч. открыто: ' + e.trainings_open : '') + (e.phone ? ' · ' + esc(e.phone) : '') + '</span></div>';
    }).join('') : '<span class="note">Сотрудников нет.</span>';
  }
  function renderShifts() {
    $('#shifts').innerHTML = shifts.length ? shifts.slice(0, 80).map(function (s) {
      return '<div class="kvr"><span class="note">' + fmt(s.shift_date) + '</span><b>' + esc(s.employee) + '</b>' +
        '<span class="note">' + (KINDS[s.kind] || s.kind) + ' · ' + num(s.hours) + ' ч</span>' +
        '<button class="chip" data-del="' + s.id + '" style="margin-left:auto;">✕</button></div>';
    }).join('') : '<span class="note">Смен нет.</span>';
    $$('#shifts [data-del]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_shift_delete', { p_token: token, p_id: b.dataset.del }).then(function () { ui.toast('Смена удалена'); load(); }); }); });
  }
  function renderTrains() {
    $('#trains').innerHTML = trains.length ? trains.map(function (t) {
      return '<div class="kvr"><b>' + esc(t.employee) + '</b><span>' + esc(t.title) + '</span>' +
        '<span class="badge ' + (t.status === 'passed' ? 'done' : 'in_progress') + '">' + (t.status === 'passed' ? 'пройдено' : 'запланировано') + '</span>' +
        '<span class="note">' + (t.train_date ? fmt(t.train_date) : '') + '</span>' +
        (t.status !== 'passed' ? '<button class="chip" data-pass="' + t.id + '" style="margin-left:auto;">Отметить пройдено</button>' : '') + '</div>';
    }).join('') : '<span class="note">Записей нет.</span>';
    $$('#trains [data-pass]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_training_set_status', { p_token: token, p_id: b.dataset.pass, p_status: 'passed' }).then(function () { load(); }); }); });
  }

  /* ---------- Отчёт (кадры) ---------- */
  function reportPdf() {
    if (!window.AppExport) { ui.toast('Экспорт недоступен'); return; }
    var cols = [
      { key: 'full_name', label: 'ФИО' }, { key: 'job', label: 'Должность' }, { key: 'dept', label: 'Подразделение' },
      { key: 'user_login', label: 'Логин' }, { key: 'role', label: 'Роль', value: function (e) { return e.role ? role(e.role) : ''; } },
      { key: 'shifts_month', label: 'Смен/мес', num: true, value: function (e) { return num(e.shifts_month); } },
      { key: 'trainings_open', label: 'Обуч. откр.', num: true, value: function (e) { return num(e.trainings_open); } },
      { key: 'active', label: 'Статус', value: function (e) { return e.active ? 'активен' : 'неактивен'; } }
    ];
    var passed = trains.filter(function (t) { return t.status === 'passed'; }).length;
    AppExport.exportPdf('Кадры — отчёт', AppExport.reportDocument({
      brand: '3DMP Service', title: 'Отчёт по персоналу (кадры)', subtitle: new Date().toLocaleDateString('ru-RU'),
      kpis: [{ label: 'Сотрудников', value: emps.length }, { label: 'Смен (всего)', value: shifts.length }, { label: 'Обучение пройдено', value: passed }],
      sections: [{ title: 'Сотрудники', columns: cols, rows: emps }],
      sign: ['Руководитель', 'Отдел кадров'], footer: '3DMP Service · кадры'
    }));
  }
  $('#repBtn').addEventListener('click', reportPdf);

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    ['emp', 'shift', 'train'].forEach(function (t) { $('#t-' + t).style.display = (b.dataset.t === t) ? '' : 'none'; });
  });
  $('#eq').addEventListener('input', function () { eq = this.value; renderEmps(); });

  $('#eAdd').addEventListener('click', function () {
    var name = $('#eName').value.trim(); if (!name) { msg('#eMsg', 'Укажите ФИО.', 'err'); return; }
    rpc('app_employee_save', { p_token: token, p_id: null, p_full_name: name, p_position: $('#eJob').value.trim(),
      p_dept: $('#eDept').value.trim(), p_phone: $('#ePhone').value.trim(), p_email: $('#eEmail').value.trim(),
      p_hired_at: $('#eHired').value || null, p_user_login: $('#eLogin').value.trim() })
      .then(function (d) { var r = d && d[0]; msg('#eMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err');
        if (r && r.ok) { window.Auth.log('Сотрудник', name); ['#eName', '#eJob', '#eDept', '#ePhone', '#eEmail', '#eHired', '#eLogin'].forEach(function (s) { $(s).value = ''; }); load(); } });
  });
  $('#shAdd').addEventListener('click', function () {
    var eid = $('#shEmp').value; if (!eid) { msg('#sMsg', 'Нет сотрудников.', 'err'); return; }
    var h = parseFloat(($('#shHours').value || '').replace(',', '.'));
    rpc('app_shift_add', { p_token: token, p_employee_id: eid, p_date: $('#shDate').value || null, p_kind: $('#shKind').value, p_hours: isNaN(h) ? 8 : h, p_note: '' })
      .then(function (d) { var r = d && d[0]; msg('#sMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) load(); });
  });
  $('#trAdd').addEventListener('click', function () {
    var title = $('#trTitle').value.trim(); if (!title) { msg('#tMsg', 'Укажите тему.', 'err'); return; }
    rpc('app_training_add', { p_token: token, p_employee_id: $('#trEmp').value, p_title: title, p_status: $('#trStatus').value, p_date: $('#trDate').value || null, p_note: '' })
      .then(function (d) { var r = d && d[0]; msg('#tMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { $('#trTitle').value = ''; load(); } });
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token; applyCaps();
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#eMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
