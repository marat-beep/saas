/* ============================================================
   B10 · Планирование производства (станки, слоты, Гант, эскалация)
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var DAYS = 10;
  var MACHINES = [
    { name: 'DMG Mori NHX', load: 88, slots: [{ o: '3DMP-0142', op: 'Фрезеровка 5 осей', start: 1, dur: 3, status: 'В работе' }, { o: '3DMP-0145', op: 'Фрезеровка 5 осей', start: 5, dur: 2, status: 'План' }, { o: '3DMP-0147', op: 'Фрезеровка 3 оси', start: 8, dur: 2, status: 'План' }] },
    { name: 'Haas VF-4', load: 74, slots: [{ o: '3DMP-0141', op: 'Штамп — фрезеровка', start: 1, dur: 2, status: 'В работе' }, { o: '3DMP-0150', op: 'Плита прижимная', start: 4, dur: 3, status: 'План' }] },
    { name: 'Sodick AG (ЭЭО)', load: 61, slots: [{ o: '3DMP-0142', op: 'ЭЭО формообразующих', start: 4, dur: 4, status: 'План' }] },
    { name: 'Okuma LB (токарный)', load: 52, slots: [{ o: '3DMP-0119', op: 'Вал-шестерня', start: 2, dur: 3, status: 'В работе' }, { o: '3DMP-0151', op: 'Втулки', start: 7, dur: 2, status: 'План' }] },
    { name: 'КИМ Zeiss', load: 40, slots: [{ o: '3DMP-0138', op: 'Контроль ОТК', start: 6, dur: 1, status: 'План' }] }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderPlan() {
    var avg = Math.round(MACHINES.reduce(function (a, m) { return a + m.load; }, 0) / MACHINES.length);
    var free = MACHINES.reduce(function (a, m) { return a + (DAYS - m.slots.reduce(function (b, s) { return b + s.dur; }, 0)); }, 0);
    var late = MACHINES.filter(function (m) { return m.load > 80; }).length;
    $('#mLoad').textContent = avg + '%';
    $('#mLate').textContent = late;
    $('#mFree').textContent = free;

    $('#loadList').innerHTML = MACHINES.map(function (m) {
      var col = m.load > 80 ? 'var(--danger)' : m.load > 60 ? 'var(--warning)' : 'var(--success)';
      return '<div class="machine-load"><div class="ml"><span style="font-weight:600;">' + m.name + '</span><b>' + m.load + '%</b></div><div class="progress"><span style="width:' + m.load + '%;background:' + col + ';"></span></div></div>';
    }).join('');

    // Gantt
    var html = '<div class="h"></div>';
    for (var d = 1; d <= DAYS; d++) html += '<div class="h">Д' + d + '</div>';
    MACHINES.forEach(function (m, mi) {
      html += '<div class="m">' + m.name + '</div>';
      var cells = [];
      for (var day = 1; day <= DAYS; day++) cells.push({ day: day, slot: null });
      m.slots.forEach(function (s) { for (var k = 0; k < s.dur; k++) { var idx = s.start + k - 1; if (cells[idx]) cells[idx].slot = s; } });
      var skip = 0;
      for (var c = 0; c < DAYS; c++) {
        if (skip > 0) { skip--; continue; }
        var s = cells[c].slot;
        if (s) {
          var cls = s.status === 'Риск' ? ' warn' : s.status === 'Готово' ? ' done' : '';
          html += '<div class="bar' + cls + '" data-mi="' + mi + '" data-start="' + s.start + '" style="grid-column:span ' + s.dur + ';">' + s.o + '</div>';
          skip = s.dur - 1;
        } else { html += '<div class="cell"></div>'; }
      }
    });
    $('#gantt').innerHTML = html;

    $$('#gantt .bar').forEach(function (b) {
      b.addEventListener('click', function () { openSlot(parseInt(b.dataset.mi, 10), parseInt(b.dataset.start, 10)); });
    });
  }

  function openSlot(mi, start) {
    var m = MACHINES[mi];
    var s = m.slots.find(function (x) { return x.start === start; });
    current = { machine: m, slot: s };
    $('#slNum').textContent = s.o;
    var b = $('#slStatus'); b.textContent = s.status; b.className = 'badge ' + (s.status === 'В работе' ? 'success' : s.status === 'Риск' ? 'danger' : 'info');
    $('#slTitle').textContent = s.op;
    $('#slInfo').innerHTML =
      irow('Станок', m.name) + irow('Заказ', s.o) + irow('Операция', s.op) + irow('Окно', 'Д' + s.start + ' – Д' + (s.start + s.dur - 1)) + irow('Длительность', s.dur + ' дн') + irow('Статус', s.status);
    screens.go('s2');
  }
  function irow(k, v) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }

  function done(title, text, num) {
    $('#actTitle').textContent = title; $('#actText').textContent = text; $('#actNum').textContent = num; screens.go('s3');
  }
  $('#shiftBtn').addEventListener('click', function () { current.slot.start = Math.min(DAYS, current.slot.start + 1); renderPlan(); done('Срок сдвинут', 'Слот перенесён на следующий день.', current.slot.o); });
  $('#escBtn').addEventListener('click', function () { current.slot.status = 'Риск'; renderPlan(); done('Задержка эскалирована', 'Уведомление отправлено мастеру и менеджеру.', current.slot.o); App.toast('Эскалация по ' + current.slot.o); });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toPlan').addEventListener('click', function () { screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderPlan();
})();
