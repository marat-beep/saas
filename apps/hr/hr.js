/* ============================================================
   3DMP Service · apps/hr — кадры (сотрудники, смены, обучение)
   Данные: app_employee_*, app_shift_*, app_training_*, app_hr_kpi (0016).
   Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, emps = [], shifts = [], trains = [];

  var KINDS = { day: 'Дневная', night: 'Ночная', off: 'Выходной', vacation: 'Отпуск', sick: 'Больничный' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return (Number(v) || 0); }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? '—' : x.toLocaleDateString('ru-RU'); }
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
      $('#kpis').innerHTML = kpi(num(k.employees), 'Сотрудников') + kpi(num(k.shifts_month), 'Смен за месяц') +
        kpi(num(k.hours_month), 'Часов за месяц') + kpi(num(k.trainings_planned), 'Обучение (план)') + kpi(num(k.trainings_passed), 'Обучение (пройдено)');
      var opts = emps.map(function (e) { return '<option value="' + e.id + '">' + esc(e.full_name) + '</option>'; }).join('');
      $('#shEmp').innerHTML = opts; $('#trEmp').innerHTML = opts;
      renderEmps(); renderShifts(); renderTrains();
    }).catch(function (e) { msg('#eMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function kpi(v, l) { return '<div class="kpi"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>'; }

  function renderEmps() {
    $('#empCount').textContent = '(' + emps.length + ')';
    $('#emps').innerHTML = emps.length ? emps.map(function (e) {
      return '<div class="row"><b>' + esc(e.full_name) + '</b><span class="note">' + esc(e.job || '') + (e.dept ? ' · ' + esc(e.dept) : '') + '</span>' +
        '<span class="note" style="margin-left:auto;">смен: ' + e.shifts_month + (e.phone ? ' · ' + esc(e.phone) : '') + '</span></div>';
    }).join('') : '<span class="note">Сотрудников нет.</span>';
  }
  function renderShifts() {
    $('#shifts').innerHTML = shifts.length ? shifts.slice(0, 60).map(function (s) {
      return '<div class="row"><span class="note">' + fmt(s.shift_date) + '</span><b>' + esc(s.employee) + '</b>' +
        '<span class="note">' + (KINDS[s.kind] || s.kind) + ' · ' + num(s.hours) + ' ч</span>' +
        '<button class="act danger" data-del="' + s.id + '" style="margin-left:auto;">✕</button></div>';
    }).join('') : '<span class="note">Смен нет.</span>';
    $$('#shifts [data-del]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_shift_delete', { p_token: token, p_id: b.dataset.del }).then(function () { ui.toast('Смена удалена'); load(); });
      });
    });
  }
  function renderTrains() {
    $('#trains').innerHTML = trains.length ? trains.map(function (t) {
      return '<div class="row"><b>' + esc(t.employee) + '</b><span>' + esc(t.title) + '</span>' +
        '<span class="note">' + (t.status === 'passed' ? 'пройдено' : 'запланировано') + (t.train_date ? ' · ' + fmt(t.train_date) : '') + '</span>' +
        (t.status !== 'passed' ? '<button class="act" data-pass="' + t.id + '" style="margin-left:auto;">Отметить пройдено</button>' : '') + '</div>';
    }).join('') : '<span class="note">Записей нет.</span>';
    $$('#trains [data-pass]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_training_set_status', { p_token: token, p_id: b.dataset.pass, p_status: 'passed' }).then(function () { load(); });
      });
    });
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    ['emp', 'shift', 'train'].forEach(function (t) { $('#t-' + t).style.display = (b.dataset.t === t) ? '' : 'none'; });
  });

  $('#eAdd').addEventListener('click', function () {
    var name = $('#eName').value.trim(); if (!name) { msg('#eMsg', 'Укажите ФИО.', 'err'); return; }
    rpc('app_employee_save', { p_token: token, p_id: null, p_full_name: name, p_position: $('#eJob').value.trim(), p_dept: $('#eDept').value.trim(), p_phone: $('#ePhone').value.trim() })
      .then(function () { ui.toast('Сотрудник добавлен'); ['#eName', '#eJob', '#eDept', '#ePhone'].forEach(function (s) { $(s).value = ''; }); load(); });
  });
  $('#shAdd').addEventListener('click', function () {
    var eid = $('#shEmp').value; if (!eid) { msg('#sMsg', 'Нет сотрудников.', 'err'); return; }
    var h = parseFloat($('#shHours').value.replace(',', '.'));
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
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#eMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
