/* ============================================================
   B15 · ТОиР и простои
   дашборд → оборудование (регламенты/история) → ТО/простой
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var EQUIP = [
    { id: 'EQ-01', name: 'DMG Mori NHX', hours: 4200, nextTO: '05.10', status: 'soon', down: 6,
      regs: [['Ежедневно', 'Проверка масла и СОЖ', 'Оператор'], ['Ежемесячно', 'Смазка направляющих', 'Слесарь'], ['Ежегодно', 'Проверка геометрии', 'Сервис']],
      history: [['ТО-2', 'Смазка и чистка', '28.09'], ['Простой', 'Замена инструмента', '25.09'], ['ТО-1', 'Проверка СОЖ', '20.09']] },
    { id: 'EQ-02', name: 'Haas VF-4', hours: 3100, nextTO: '12.10', status: 'ok', down: 2,
      regs: [['Ежедневно', 'Осмотр рабочей зоны', 'Оператор'], ['Ежемесячно', 'Смазка', 'Слесарь']],
      history: [['ТО-1', 'Проверка и смазка', '29.09']] },
    { id: 'EQ-03', name: 'Sodick AG (ЭЭО)', hours: 2600, nextTO: '28.09', status: 'overdue', down: 12,
      regs: [['Еженедельно', 'Чистка ванны и фильтров', 'Оператор'], ['Ежемесячно', 'Проверка генератора', 'Сервис']],
      history: [['Простой', 'Замена фильтра', '27.09'], ['ТО-1', 'Чистка ванны', '21.09']] },
    { id: 'EQ-04', name: 'Okuma LB', hours: 3800, nextTO: '08.10', status: 'soon', down: 4,
      regs: [['Ежедневно', 'Проверка масла', 'Оператор'], ['Ежемесячно', 'Калибровка', 'Сервис']],
      history: [['ТО-1', 'Проверка масла', '30.09']] },
    { id: 'EQ-05', name: 'КИМ Zeiss', hours: 1200, nextTO: '18.10', status: 'ok', down: 0,
      regs: [['Ежедневно', 'Прогрев и референс', 'Контролёр'], ['Ежегодно', 'Поверка', 'Метролог']],
      history: [['ТО-1', 'Референс', '29.09']] }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    $('#kSoon').textContent = EQUIP.filter(function (e) { return e.status === 'soon'; }).length;
    $('#kOver').textContent = EQUIP.filter(function (e) { return e.status === 'overdue'; }).length;
    $('#kDown').textContent = EQUIP.reduce(function (a, e) { return a + e.down; }, 0);
    $('#eqCount').textContent = EQUIP.length + ' единиц';
    $('#eqList').innerHTML = EQUIP.map(function (e, i) {
      var st = e.status === 'overdue' ? ['danger', 'ТО просрочено'] : e.status === 'soon' ? ['warning', 'ТО скоро'] : ['success', 'В норме'];
      return '<div class="eq-row" data-i="' + i + '"><div><div style="font-weight:600;font-size:.84rem;">' + e.name + '</div><div class="faint" style="font-size:.68rem;">№' + e.id + ' · ' + App.number(e.hours) + ' ч · простои ' + e.down + ' ч</div></div><span class="badge ' + st[0] + '">' + st[1] + '</span></div>';
    }).join('');
    $$('#eqList .eq-row').forEach(function (r) { r.addEventListener('click', function () { openEq(parseInt(r.dataset.i, 10)); }); });
  }

  function openEq(i) {
    current = EQUIP[i];
    var e = current;
    $('#eqNum').textContent = e.id;
    var b = $('#eqBadge'); b.textContent = e.status === 'overdue' ? 'ТО просрочено' : e.status === 'soon' ? 'ТО скоро' : 'В норме'; b.className = 'badge ' + (e.status === 'overdue' ? 'danger' : e.status === 'soon' ? 'warning' : 'success');
    $('#eqTitle').textContent = e.name;
    $('#eqTags').innerHTML = '<span class="tag">⏱ ' + App.number(e.hours) + ' ч</span><span class="tag">🔧 ТО до ' + e.nextTO + '</span><span class="tag">⛔ ' + e.down + ' ч простоев</span>';
    $('#eqRegs').innerHTML = e.regs.map(function (r) { return '<div class="reg"><span><b>' + r[0] + '</b> — ' + r[1] + '</span><span class="muted">' + r[2] + '</span></div>'; }).join('');
    $('#eqHistory').innerHTML = e.history.map(function (h) { return '<div class="row between" style="padding:7px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><span>' + h[0] + ' — ' + h[1] + '</span><span class="muted">' + h[2] + '</span></div>'; }).join('');
    screens.go('s2');
  }

  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }

  $('#toBtn').addEventListener('click', function () {
    current.history.unshift(['ТО', 'Плановое обслуживание', App.today()]);
    current.nextTO = App.addDays(30); current.status = 'ok';
    renderList(); done('ТО отмечено', 'Плановое обслуживание зафиксировано, следующее ТО через 30 дней.', current.id);
  });
  $('#downBtn').addEventListener('click', function () {
    current.down += 2; current.status = current.status === 'ok' ? 'soon' : current.status;
    current.history.unshift(['Простой', 'Незапланированный простой', App.today()]);
    renderList(); done('Простой зарегистрирован', 'Простой +2 ч учтён в статистике оборудования.', current.id);
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderList(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
