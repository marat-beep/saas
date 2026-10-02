/* ============================================================
   P13 · Подразделения и иерархия
   цеха/участки/службы, сотрудники по уровням, схема, доступы
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var LEVELS = { director: 'Директор', chief: 'Начальник цеха', master: 'Мастер', operator: 'Оператор', engineer: 'Инженер' };
  var TYPES = ['Управление', 'Цех', 'Участок', 'Служба', 'Отдел'];

  // демо-структура
  AppData.departments.add && (function seed() {
    if (AppData.departments.all().length) return;
    AppData.departments.add({ name: 'Дирекция', type: 'Управление' });
    AppData.departments.add({ name: 'Цех механообработки', type: 'Цех' });
    AppData.departments.add({ name: 'Инструментальный участок', type: 'Участок' });
    AppData.departments.add({ name: 'Служба качества (ОТК)', type: 'Служба' });
    AppData.departments.add({ name: 'Снабжение и склад', type: 'Отдел' });
    var deps = AppData.departments.all();
    function dep(n) { return deps.filter(function (d) { return d.name === n; })[0].id; }
    AppData.staff.add({ name: 'Иванов И.И.', dept: dep('Дирекция'), level: 'director' });
    AppData.staff.add({ name: 'Петров П.П.', dept: dep('Цех механообработки'), level: 'chief' });
    AppData.staff.add({ name: 'Сидоров С.С.', dept: dep('Цех механообработки'), level: 'master' });
    AppData.staff.add({ name: 'Смирнов А.А.', dept: dep('Цех механообработки'), level: 'operator' });
    AppData.staff.add({ name: 'Кузнецова Е.Е.', dept: dep('Инструментальный участок'), level: 'engineer' });
    AppData.staff.add({ name: 'Соколова О.О.', dept: dep('Служба качества (ОТК)'), level: 'master' });
  })();

  var tab = 'org';
  var C = window.AppCatalog;
  function depName(id) { var d = AppData.departments.all().filter(function (x) { return x.id === id; })[0]; return d ? d.name : '—'; }

  var screens = AppRouter.create({ onShow: function () {}, onBackEmpty: function () { location.href = '../../index.html'; } });

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('button', this).forEach(function (x) { x.classList.toggle('active', x === b); });
    tab = b.dataset.t; render();
  });

  function render() {
    if (tab === 'org') return renderOrg();
    if (tab === 'staff') return renderStaff();
    if (tab === 'chart') return renderChart();
    if (tab === 'access') return renderAccess();
  }

  function renderOrg() {
    var deps = AppData.departments.all();
    $('#body').innerHTML =
      '<div class="card mb-12"><div class="input-row"><div class="field"><label>Название</label><input type="text" id="dName" placeholder="Напр. Цех №2"></div><div class="field"><label>Тип</label><select id="dType">' + TYPES.map(function (t) { return '<option>' + t + '</option>'; }).join('') + '</select></div></div><button class="btn btn-primary btn-sm" id="addDep" disabled>＋ Добавить подразделение</button></div>' +
      '<div class="card">' + (deps.length ? deps.map(function (d) {
        var cnt = AppData.staff.byDept(d.id).length;
        return '<div class="row2"><div><div style="font-weight:600;">' + d.name + '</div><div class="faint" style="font-size:.68rem;">' + d.type + ' · сотрудников: ' + cnt + '</div></div><button class="btn btn-ghost btn-sm" data-del="' + d.id + '">Удалить</button></div>';
      }).join('') : '<div class="faint">Подразделений нет.</div>') + '</div>';
    $('#dName').addEventListener('input', function () { $('#addDep').disabled = !this.value.trim(); });
    $('#addDep').addEventListener('click', function () { AppData.departments.add({ name: $('#dName').value.trim(), type: $('#dType').value }); renderOrg(); });
    $$('#body [data-del]').forEach(function (b) { b.addEventListener('click', function () { AppData.departments.remove(b.dataset.del); renderOrg(); }); });
  }

  function renderStaff() {
    var staff = AppData.staff.all(), deps = AppData.departments.all();
    var opts = deps.map(function (d) { return '<option value="' + d.id + '">' + d.name + '</option>'; }).join('');
    var lvls = Object.keys(LEVELS).map(function (k) { return '<option value="' + k + '">' + LEVELS[k] + '</option>'; }).join('');
    $('#body').innerHTML =
      '<div class="card mb-12"><div class="input-row"><div class="field"><label>ФИО</label><input type="text" id="sName" placeholder="Иванов И.И."></div><div class="field"><label>Подразделение</label><select id="sDept">' + opts + '</select></div></div><div class="field"><label>Уровень (иерархия)</label><select id="sLevel">' + lvls + '</select></div><button class="btn btn-primary btn-sm" id="addStaff" disabled>＋ Добавить сотрудника</button></div>' +
      '<div class="card">' + (staff.length ? staff.map(function (s) {
        return '<div class="row2"><div><div style="font-weight:600;">' + s.name + '</div><div class="faint" style="font-size:.68rem;">' + (LEVELS[s.level] || s.level) + ' · ' + depName(s.dept) + '</div></div><button class="btn btn-ghost btn-sm" data-del="' + s.id + '">Удалить</button></div>';
      }).join('') : '<div class="faint">Сотрудников нет.</div>') + '</div>';
    $('#sName').addEventListener('input', function () { $('#addStaff').disabled = !this.value.trim(); });
    $('#addStaff').addEventListener('click', function () { AppData.staff.add({ name: $('#sName').value.trim(), dept: $('#sDept').value, level: $('#sLevel').value }); renderStaff(); });
    $$('#body [data-del]').forEach(function (b) { b.addEventListener('click', function () { AppData.staff.remove(b.dataset.del); renderStaff(); }); });
  }

  function renderChart() {
    var deps = AppData.departments.all(), staff = AppData.staff.all();
    var director = staff.filter(function (s) { return s.level === 'director'; })[0];
    var html = '<div class="card tree">';
    html += '<div class="n0">🎯 ' + (director ? director.name + ' — Директор' : 'Директор') + '</div>';
    deps.filter(function (d) { return d.type !== 'Управление'; }).forEach(function (d) {
      html += '<div class="n1">🏢 ' + d.name + ' <span class="faint" style="font-weight:400;">(' + d.type + ')</span></div>';
      var team = staff.filter(function (s) { return s.dept === d.id; });
      team.forEach(function (s) { html += '<div class="n2">👤 ' + s.name + ' — ' + (LEVELS[s.level] || s.level) + '</div>'; });
      if (!team.length) html += '<div class="n2 faint">— нет сотрудников —</div>';
    });
    html += '</div>';
    $('#body').innerHTML = html;
  }

  function renderAccess() {
    var levels = window.AppAuth ? AppAuth.staffLevels() : Object.keys(LEVELS);
    $('#body').innerHTML = '<div class="card">' + levels.map(function (l) {
      var ids = window.AppAuth ? AppAuth.appsForLevel(l) : [];
      var chips;
      if (ids === 'all') chips = '<span class="tag">все модули сотрудников</span>';
      else chips = ids.map(function (id) {
        var a = null; if (C) C.groups.forEach(function (g) { g.apps.forEach(function (x) { if (x.id === id) a = x; }); });
        return '<span class="tag" style="margin:3px 4px 0 0;">' + id + ' ' + (a ? a.title : '') + '</span>';
      }).join('');
      return '<div style="padding:10px 0;border-bottom:1px solid var(--border-2);"><b style="font-size:.84rem;">' + (LEVELS[l] || l) + '</b><div style="margin-top:6px;">' + chips + '</div></div>';
    }).join('') + '</div>';
  }

  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
  render();
})();
