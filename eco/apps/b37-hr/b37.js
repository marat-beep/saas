/* ============================================================
   B37 · Кадры: личные дела сотрудников с историей
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var LEVELS = { director: 'Директор', chief: 'Начальник цеха', master: 'Мастер', operator: 'Оператор', engineer: 'Инженер' };

  // сид структуры, если пусто
  (function seed() {
    if (AppData.staff.all().length) return;
    if (!AppData.departments.all().length) {
      AppData.departments.add({ name: 'Дирекция', type: 'Управление' });
      AppData.departments.add({ name: 'Цех механообработки', type: 'Цех' });
      AppData.departments.add({ name: 'Служба качества (ОТК)', type: 'Служба' });
    }
    var deps = AppData.departments.all();
    function dep(n) { return deps.filter(function (d) { return d.name === n; })[0].id; }
    AppData.staff.add({ name: 'Иванов И.И.', dept: dep('Дирекция'), level: 'director', position: 'Генеральный директор', phone: '+7 495 000-00-01', hired: '12.03.2015', history: [['Приём на работу', '12.03.2015', 'Принят генеральным директором'], ['Награда', '20.12.2023', 'Благодарность за развитие производства']] });
    AppData.staff.add({ name: 'Петров П.П.', dept: dep('Цех механообработки'), level: 'chief', position: 'Начальник цеха', phone: '+7 495 000-00-02', hired: '04.06.2018', history: [['Приём на работу', '04.06.2018', 'Мастер участка'], ['Повышение', '01.02.2022', 'Назначен начальником цеха'], ['Обучение', '15.05.2024', 'Курс «Бережливое производство»']] });
    AppData.staff.add({ name: 'Смирнов А.А.', dept: dep('Цех механообработки'), level: 'operator', position: 'Оператор ЧПУ 4 разряда', phone: '+7 495 000-00-03', hired: '10.09.2021', history: [['Приём на работу', '10.09.2021', 'Оператор ЧПУ 3 разряда'], ['Аттестация', '22.06.2024', 'Присвоен 4 разряд']] });
    AppData.staff.add({ name: 'Соколова О.О.', dept: dep('Служба качества (ОТК)'), level: 'master', position: 'Контролёр ОТК', phone: '+7 495 000-00-04', hired: '17.01.2020', history: [['Приём на работу', '17.01.2020', 'Контролёр ОТК'], ['Обучение', '03.03.2023', 'Курс по КИМ']] });
  })();

  var current = null;
  function depName(id) { var d = AppData.departments.all().filter(function (x) { return x.id === id; })[0]; return d ? d.name : '—'; }
  function initials(name) { return name.replace(/[^А-Яа-яA-Za-z]/g, ' ').trim().split(/\s+/).slice(0, 2).map(function (w) { return w[0] || ''; }).join('').toUpperCase(); }

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    var q = ($('#search').value || '').toLowerCase();
    var list = AppData.staff.all().filter(function (s) { return !q || (s.name + ' ' + (s.position || '') + ' ' + (LEVELS[s.level] || '')).toLowerCase().indexOf(q) >= 0; });
    $('#eCount').textContent = list.length + ' сотрудников';
    $('#empList').innerHTML = list.length ? list.map(function (s) {
      return '<div class="emp" data-id="' + s.id + '"><div class="row" style="gap:10px;"><div class="avatar">' + initials(s.name) + '</div><div><div style="font-weight:600;font-size:.84rem;">' + s.name + '</div><div class="faint" style="font-size:.68rem;">' + (s.position || LEVELS[s.level]) + ' · ' + depName(s.dept) + '</div></div></div><span class="badge accent">' + (LEVELS[s.level] || s.level) + '</span></div>';
    }).join('') : '<div class="faint">Нет сотрудников.</div>';
    $$('#empList .emp').forEach(function (el) { el.addEventListener('click', function () { openEmp(el.dataset.id); }); });
  }
  $('#search').addEventListener('input', renderList);

  function openEmp(id) {
    current = AppData.staff.all().filter(function (s) { return s.id === id; })[0];
    var s = current;
    $('#dAv').textContent = initials(s.name);
    $('#dName').textContent = s.name;
    $('#dRole').textContent = (s.position || LEVELS[s.level]) + ' · ' + depName(s.dept);
    $('#dTags').innerHTML = '<span class="tag">' + (LEVELS[s.level] || s.level) + '</span><span class="tag">Принят: ' + (s.hired || '—') + '</span>';
    $('#dInfo').innerHTML = row('Должность', s.position || LEVELS[s.level]) + row('Подразделение', depName(s.dept)) + row('Уровень', LEVELS[s.level] || s.level) + row('Телефон', s.phone || '—') + row('Дата приёма', s.hired || '—');
    var hist = (s.history || []).slice().sort(function (a, b) { return 0; });
    $('#dHistory').innerHTML = hist.length ? hist.map(function (h) { return '<div class="tl-item"><div class="dot"></div><div class="tl-t">' + h[0] + '</div><div class="tl-m">' + h[1] + ' · ' + h[2] + '</div></div>'; }).join('') : '<div class="faint" style="font-size:.8rem;">История пуста.</div>';
    $('#recDate').value = App.today();
    $('#recText').value = ''; $('#addRec').disabled = true;
    screens.go('s2');
  }
  function row(k, v) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b style="text-align:right;">' + v + '</b></div>'; }

  $('#recText').addEventListener('input', function () { $('#addRec').disabled = !this.value.trim(); });
  $('#addRec').addEventListener('click', function () {
    var hist = (current.history || []).slice();
    hist.push([$('#recType').value, $('#recDate').value || App.today(), $('#recText').value.trim()]);
    AppData.staff.update(current.id, { history: hist });
    AppData.log.add({ action: 'HR: запись в дело', detail: current.name + ' — ' + $('#recType').value });
    $('#actNum').textContent = current.name;
    screens.go('s3'); App.toast('Запись добавлена');
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderList(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
