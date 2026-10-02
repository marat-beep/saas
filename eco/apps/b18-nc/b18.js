/* ============================================================
   B18 · УП и постпроцессоры (DNC)
   библиотека УП, версии, backplot, отправка/бэкап
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var PROGRAMS = [
    { id: 'NC-0142', name: 'KORPUS_142', machine: 'DMG Mori NHX', ctrl: 'Heidenhain', post: 'TNC640_5AX', order: '3DMP-2025-0142', part: 'Пресс-форма втулки', status: 'Проверена', size: '184 КБ', lastRun: '02.10',
      versions: [['v4', '02.10', 'А. Кузнецов', 'Коррекция чистовых проходов'], ['v3', '30.09', 'А. Кузнецов', 'Правка на стойке'], ['v2', '28.09', 'CAM', 'Первая отладка']] },
    { id: 'NC-0141', name: 'STAMP_141', machine: 'Haas VF-4', ctrl: 'Fanuc', post: 'FANUC_3AX', order: '3DMP-2025-0141', part: 'Штамп вырубной', status: 'Проверена', size: '96 КБ', lastRun: '01.10',
      versions: [['v2', '01.10', 'Д. Орлов', 'Ускорение врезания'], ['v1', '27.09', 'CAM', 'Черновая + чистовая']] },
    { id: 'NC-0119', name: 'VAL_119', machine: 'Okuma LB3000', ctrl: 'OSP', post: 'OSP_P300', order: '3DMP-2025-0119', part: 'Вал-шестерня', status: 'Черновик', size: '42 КБ', lastRun: '—',
      versions: [['v4', '29.09', 'В. Петров', 'Правка подачи'], ['v3', '25.09', 'CAM', 'Шлицы']] },
    { id: 'NC-0138', name: 'EDM_FORG_12', machine: 'Sodick AG', ctrl: 'Sodick', post: 'SODICK_LN2W', order: '3DMP-2025-0142', part: 'Электроды', status: 'На проверке', size: '18 КБ', lastRun: '30.09',
      versions: [['v2', '30.09', 'В. Петров', 'Режимы ЭЭО'], ['v1', '24.09', 'CAM', 'Черновик']] }
  ];

  var filter = 'all', query = '', current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    var list = PROGRAMS.filter(function (p) {
      if (filter !== 'all' && p.ctrl !== filter) return false;
      if (query && (p.name + ' ' + p.order + ' ' + p.part + ' ' + p.machine).toLowerCase().indexOf(query) < 0) return false;
      return true;
    });
    $('#ncCount').textContent = list.length + ' программ';
    $('#ncList').innerHTML = list.length ? list.map(function (p, i) {
      var badge = p.status === 'Проверена' ? 'success' : p.status === 'Черновик' ? 'warning' : 'info';
      return '<div class="nc-row" data-i="' + i + '"><div><div style="font-weight:600;font-size:.84rem;">' + p.name + ' <span class="faint" style="font-weight:400;">· ' + p.versions[0][0] + '</span></div><div class="faint" style="font-size:.68rem;">' + p.machine + ' · ' + p.order + ' · последний запуск ' + p.lastRun + '</div></div><span class="badge ' + badge + '">' + p.status + '</span></div>';
    }).join('') : '<div class="callout info"><span class="ci">🔍</span><div>Программы не найдены.</div></div>';
    $$('#ncList .nc-row').forEach(function (r) { r.addEventListener('click', function () { openP(PROGRAMS.indexOf(list[parseInt(r.dataset.i, 10)])); }); });
  }
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });
  $('#search').addEventListener('input', function () { query = this.value.trim().toLowerCase(); renderList(); });

  function openP(i) {
    current = PROGRAMS[i]; var p = current;
    $('#dId').textContent = p.id;
    var b = $('#dStatus'); b.textContent = p.status; b.className = 'badge ' + (p.status === 'Проверена' ? 'success' : p.status === 'Черновик' ? 'warning' : 'info');
    $('#dTitle').textContent = p.name;
    $('#dTags').innerHTML = '<span class="tag">🖥 ' + p.machine + '</span><span class="tag">' + p.ctrl + '</span><span class="tag">Пост: ' + p.post + '</span>';
    $('#dInfo').innerHTML = row('Заказ', p.order) + row('Деталь', p.part) + row('Постпроцессор', p.post) + row('Размер', p.size) + row('Последний запуск', p.lastRun) + row('Текущая версия', p.versions[0][0]);
    $('#dVersions').innerHTML = p.versions.map(function (v, idx) { return '<div class="ver"><span class="v">' + v[0] + '</span><div class="grow"><div style="font-weight:600;">' + v[3] + '</div><div class="faint" style="font-size:.68rem;">' + v[1] + ' · ' + v[2] + '</div></div>' + (idx === 0 ? '<span class="badge accent">active</span>' : '') + '</div>'; }).join('');
    screens.go('s2');
  }
  function row(k, v) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b style="text-align:right;">' + v + '</b></div>'; }
  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }

  $('#backplot').addEventListener('click', function () { App.toast('Демо: backplot и проверка столкновений пройдены'); });
  $('#sendBtn').addEventListener('click', function () { done('УП отправлена на станок', 'DNC: ' + current.versions[0][0] + ' передана на ' + current.machine + '.', current.id); });
  $('#backupBtn').addEventListener('click', function () { done('Бэкап со стойки', 'Считана текущая программа со стойки ' + current.machine + ', версии синхронизированы.', current.id); });
  $('#newVerBtn').addEventListener('click', function () {
    var nv = 'v' + (current.versions.length + 1);
    current.versions.unshift([nv, App.today().slice(0, 5), 'Вы', 'Новая версия из приложения']);
    openP(PROGRAMS.indexOf(current));
    done('Создана версия ' + nv, 'Новая версия ' + current.id + ' сохранена в библиотеке.', current.id);
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderList(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
