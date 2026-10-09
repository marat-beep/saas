/* ============================================================
   3DMP Service · apps/elearning — e-Learning (W26, 0174).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, courses = [], tests = [], cur = null;
  var EN = { assigned: 'Назначено', in_progress: 'В процессе', done: 'Завершено' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function tbl(head, rows) { return '<div class="tbl-wrap"><table class="tbl"><thead><tr>' + head + '</tr></thead><tbody>' + rows + '</tbody></table></div>'; }

  function showTab(scr) { $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); }); $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); }); if (scr === 'cr') loadCr(); if (scr === 'en') loadEn(); if (scr === 'ts') loadTs(); }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() { return rpc('app_elearning_kpi', { p_token: token }).then(function (r) { var k = (r && r[0]) || {}; $('#kpis').innerHTML = cell('Курсов', k.courses || 0) + cell('Активных', k.active_courses || 0) + cell('Назначений', k.enrollments || 0) + cell('Завершено', k.done || 0) + cell('Тестов', k.tests || 0) + cell('Попыток', k.attempts || 0) + cell('Сдано, %', k.pass_rate != null ? k.pass_rate : '—'); }); }

  function loadCr() {
    return rpc('app_courses_list', { p_token: token }).then(function (r) {
      courses = r || [];
      $('#cr').innerHTML = courses.length ? tbl('<th>Код</th><th>Курс</th><th>Категория</th><th class="num">Часов</th><th class="num">Уроков</th><th class="num">Назначено</th><th></th>', courses.map(function (c) { return '<tr><td>' + esc(c.code || '') + '</td><td><b>' + esc(c.name) + '</b></td><td>' + esc(c.category || '') + '</td><td class="num">' + (c.hours || 0) + '</td><td class="num">' + c.lessons + '</td><td class="num">' + c.enrolled + '</td>' +
        '<td style="white-space:nowrap;"><button class="act" data-ls="' + c.id + '">Уроки</button><button class="act danger" data-del="' + c.id + '">Удалить</button></td></tr>'; }).join('')) : '<span class="note">Курсов нет.</span>';
      $$('#cr [data-ls]').forEach(function (b) { b.addEventListener('click', function () { openLessons(courses.filter(function (x) { return x.id === b.dataset.ls; })[0]); }); });
      $$('#cr [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить курс?')) return; rpc('app_course_delete', { p_token: token, p_id: b.dataset.del }).then(function () { $('#crPanel').innerHTML = ''; loadCr(); loadKpi(); }); }); });
    });
  }
  function openLessons(c) {
    if (!c) return; cur = c;
    return rpc('app_course_lessons_list', { p_token: token, p_course_id: c.id }).then(function (r) {
      var list = r || [];
      $('#crPanel').innerHTML = '<h4>Уроки: ' + esc(c.name) + '</h4><div class="toolbar"><button class="btn" id="lsAdd" style="width:auto;padding:6px 10px;">＋ Урок</button></div>' +
        (list.length ? tbl('<th class="num">№</th><th>Урок</th><th class="num">Мин</th><th></th>', list.map(function (l) { return '<tr><td class="num">' + l.ord + '</td><td>' + esc(l.name) + '</td><td class="num">' + l.minutes + '</td><td><button class="act danger" data-ldel="' + l.id + '">Удалить</button></td></tr>'; }).join('')) : '<span class="note">Уроков нет.</span>');
      $('#lsAdd').addEventListener('click', addLesson);
      $$('#crPanel [data-ldel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_course_lesson_delete', { p_token: token, p_id: b.dataset.ldel }).then(function () { openLessons(c); loadCr(); }); }); });
    });
  }
  function addLesson() { ui.formDialog({ title: 'Урок', okText: 'Добавить', fields: [{ name: 'name', label: 'Название', type: 'text', required: true }, { name: 'ord', label: 'Порядок', type: 'number' }, { name: 'minutes', label: 'Минут', type: 'number' }, { name: 'content', label: 'Содержание', type: 'textarea', rows: 3 }], values: { ord: 1 } }).then(function (v) { if (!v) return; rpc('app_course_lesson_save', { p_token: token, p_id: null, p_course_id: cur.id, p_name: v.name, p_ord: v.ord ? parseInt(v.ord, 10) : 1, p_minutes: v.minutes ? Number(v.minutes) : 0, p_content: v.content || null }).then(function () { openLessons(cur); loadCr(); loadKpi(); }); }); }
  function crForm() { ui.formDialog({ title: 'Курс', okText: 'Создать', fields: [{ name: 'code', label: 'Код', type: 'text' }, { name: 'name', label: 'Название', type: 'text', required: true }, { name: 'category', label: 'Категория', type: 'text' }, { name: 'hours', label: 'Часов', type: 'number' }, { name: 'description', label: 'Описание', type: 'textarea', rows: 2 }], values: {} }).then(function (v) { if (!v) return; rpc('app_course_save', { p_token: token, p_id: null, p_code: v.code || null, p_name: v.name, p_category: v.category || null, p_hours: v.hours ? Number(v.hours) : 0, p_active: true, p_description: v.description || null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadCr(); loadKpi(); }); }); }

  function loadEn() {
    return rpc('app_enrollments_list', { p_token: token, p_course_id: null, p_employee: null }).then(function (r) {
      var list = r || [];
      $('#en').innerHTML = list.length ? tbl('<th>Курс</th><th>Сотрудник</th><th>Статус</th><th class="num">Прогресс</th><th class="num">Оценка</th><th></th>', list.map(function (x) { return '<tr><td>' + esc(x.course || '') + '</td><td>' + esc(x.employee_login || '') + '</td><td>' + esc(EN[x.status] || x.status) + '</td><td class="num">' + x.progress + '%</td><td class="num">' + (x.score != null ? x.score : '—') + '</td>' +
        '<td style="white-space:nowrap;">' + (x.status !== 'done' ? '<button class="act" data-prog="' + x.id + '">Отметить</button>' : '') + '</td></tr>'; }).join('')) : '<span class="note">Назначений нет.</span>';
      $$('#en [data-prog]').forEach(function (b) { b.addEventListener('click', function () { var x = list.filter(function (y) { return y.id === b.dataset.prog; })[0]; ui.formDialog({ title: 'Прогресс', okText: 'Сохранить', fields: [{ name: 'status', label: 'Статус', type: 'select', options: Object.keys(EN).map(function (k) { return { value: k, label: EN[k] }; }) }, { name: 'progress', label: '%', type: 'number' }, { name: 'score', label: 'Оценка', type: 'number' }], values: { status: x.status, progress: x.progress, score: x.score != null ? x.score : '' } }).then(function (v) { if (!v) return; rpc('app_enrollment_save', { p_token: token, p_id: x.id, p_course_id: null, p_employee: x.employee_login, p_status: v.status, p_progress: v.progress ? parseInt(v.progress, 10) : 0, p_score: v.score === '' ? null : Number(v.score) }).then(function () { loadEn(); loadKpi(); }); }); }); });
    });
  }
  function enForm() { ui.formDialog({ title: 'Назначить курс', okText: 'Назначить', fields: [{ name: 'course_id', label: 'Курс', type: 'select', options: courses.map(function (c) { return { value: c.id, label: c.name }; }), required: true }, { name: 'employee', label: 'Сотрудник (логин)', type: 'text', required: true }], values: {} }).then(function (v) { if (!v) return; rpc('app_enrollment_save', { p_token: token, p_id: null, p_course_id: v.course_id, p_employee: v.employee, p_status: 'assigned', p_progress: 0, p_score: null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadEn(); loadKpi(); }); }); }

  function loadTs() {
    return rpc('app_course_tests_list', { p_token: token, p_course_id: null }).then(function (r) {
      tests = r || [];
      $('#ts').innerHTML = tests.length ? tbl('<th>Курс</th><th>Тест</th><th class="num">Порог</th><th class="num">Вопросов</th><th></th>', tests.map(function (t) { return '<tr><td>' + esc(t.course || '') + '</td><td><b>' + esc(t.name) + '</b></td><td class="num">' + t.pass_score + '</td><td class="num">' + ((t.questions || []).length) + '</td>' +
        '<td><button class="act" data-att="' + t.id + '">Попытка</button></td></tr>'; }).join('')) : '<span class="note">Тестов нет.</span>';
      $$('#ts [data-att]').forEach(function (b) { b.addEventListener('click', function () { attempt(b.dataset.att); }); });
    });
  }
  function tsForm() { ui.formDialog({ title: 'Тест', okText: 'Создать', fields: [{ name: 'course_id', label: 'Курс', type: 'select', options: courses.map(function (c) { return { value: c.id, label: c.name }; }), required: true }, { name: 'name', label: 'Название', type: 'text', required: true }, { name: 'pass', label: 'Порог, %', type: 'number' }], values: { pass: 70 } }).then(function (v) { if (!v) return; rpc('app_course_test_save', { p_token: token, p_id: null, p_course_id: v.course_id, p_name: v.name, p_pass: v.pass ? parseInt(v.pass, 10) : 70, p_questions: [] }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadTs(); loadKpi(); }); }); }
  function attempt(id) { ui.formDialog({ title: 'Результат попытки', okText: 'Записать', fields: [{ name: 'employee', label: 'Сотрудник (логин)', type: 'text', required: true }, { name: 'score', label: 'Балл, %', type: 'number', required: true }], values: {} }).then(function (v) { if (!v) return; rpc('app_test_attempt_add', { p_token: token, p_test_id: id, p_employee: v.employee, p_score: v.score ? parseInt(v.score, 10) : 0, p_answers: {} }).then(function (r) { var x = r && r[0]; msg(x ? ('Результат: ' + x.message) : '', x && x.passed ? 'ok' : 'err'); loadKpi(); }); }); }

  $('#addCr').addEventListener('click', crForm);
  $('#addEn').addEventListener('click', enForm);
  $('#addTs').addEventListener('click', tsForm);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadKpi(); loadCr();
  });
})();
