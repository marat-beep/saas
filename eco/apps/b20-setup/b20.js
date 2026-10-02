/* ============================================================
   B20 · Наладка и оснастка
   карты наладки, системы координат, базы, чек-лист первого пуска
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var SETUPS = [
    { id: 'ST-142', order: '3DMP-2025-0142', machine: 'DMG Mori NHX', part: 'Пресс-форма втулки', fixture: 'Нулевой зажим 5-осевой, кулачки Ø120', probe: 'Щуп Renishaw OMP40',
      coords: [['G54', 'X0 Y0', 'Z-120'], ['G55', 'X+180', 'Z-120'], ['G56', '—', '—']],
      checklist: [['Очистка и проверка зоны', true], ['Установка оснастки по схеме', true], ['Привязка G54 через щуп', true], ['Проверка инструмента и корректоров', false], ['Пробный проход на холостом ходу', false], ['Замер первой детали', false]] },
    { id: 'ST-141', order: '3DMP-2025-0141', machine: 'Haas VF-4', part: 'Штамп вырубной', fixture: 'Тиски гидравлические 200 мм', probe: 'Щуп + индикатор',
      coords: [['G54', 'X-100 Y-50', 'Z-80'], ['G55', '—', '—'], ['G56', '—', '—']],
      checklist: [['Установка тисков и упоров', true], ['Привязка баз и G54', true], ['Проверка зазоров штампа', false], ['Пробный пуск', false]] },
    { id: 'ST-119', order: '3DMP-2025-0119', machine: 'Okuma LB3000', part: 'Вал-шестерня', fixture: 'Патрон 3-кулачковый + люнет', probe: '—',
      coords: [['G54', 'Z0 по торцу', 'X0 по центру'], ['G55', '—', '—'], ['G56', '—', '—']],
      checklist: [['Установка заготовки и люнета', true], ['Привязка Z0 по торцу', false], ['Проверка дисбаланса', false], ['Первый проход', false]] }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    $('#sCount').textContent = SETUPS.length + ' карт';
    $('#sList').innerHTML = SETUPS.map(function (s, i) {
      var done = s.checklist.filter(function (c) { return c[1]; }).length;
      var ready = done === s.checklist.length;
      return '<div class="s-row" data-i="' + i + '"><div><div style="font-weight:600;font-size:.84rem;">' + s.part + '</div><div class="faint" style="font-size:.68rem;">' + s.id + ' · ' + s.machine + ' · ' + done + '/' + s.checklist.length + '</div></div><span class="badge ' + (ready ? 'success' : 'warning') + '">' + (ready ? 'Готова' : 'В процессе') + '</span></div>';
    }).join('');
    $$('#sList .s-row').forEach(function (r) { r.addEventListener('click', function () { openS(parseInt(r.dataset.i, 10)); }); });
  }

  function openS(i) {
    current = SETUPS[i]; var s = current;
    $('#dOrder').textContent = s.id + ' · ' + s.order;
    var ready = s.checklist.every(function (c) { return c[1]; });
    var b = $('#dStatus'); b.textContent = ready ? 'Готова' : 'В процессе'; b.className = 'badge ' + (ready ? 'success' : 'warning');
    $('#dTitle').textContent = s.part;
    $('#dTags').innerHTML = '<span class="tag">🖥 ' + s.machine + '</span>';
    $('#dCoords').innerHTML = s.coords.map(function (c) { return '<div class="coord"><b>' + c[0] + '</b><span>' + c[1] + '</span><span>' + c[2] + '</span></div>'; }).join('');
    $('#dFixture').innerHTML = row('Оснастка', s.fixture) + row('Щуп', s.probe);
    $('#dCheck').innerHTML = s.checklist.map(function (c, idx) { return '<div class="chk ' + (c[1] ? 'done' : '') + '" data-i="' + idx + '"><span class="box">' + (c[1] ? '✓' : '') + '</span><span class="lbl">' + c[0] + '</span></div>'; }).join('');
    $$('#dCheck .chk').forEach(function (el) {
      el.addEventListener('click', function () {
        var idx = parseInt(el.dataset.i, 10);
        s.checklist[idx][1] = !s.checklist[idx][1];
        openS(i);
      });
    });
    $('#doneBtn').disabled = !ready;
    screens.go('s2');
  }
  function row(k, v) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b style="text-align:right;">' + v + '</b></div>'; }

  $('#doneBtn').addEventListener('click', function () {
    $('#actText').textContent = 'Наладка ' + current.id + ' завершена, первая деталь допущена к контролю ОТК (B3).';
    $('#actNum').textContent = current.id;
    renderList(); screens.go('s3'); App.toast('Наладка ' + current.id + ' завершена');
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderList(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
