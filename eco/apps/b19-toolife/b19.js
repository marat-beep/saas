/* ============================================================
   B19 · Инструмент и стойкость
   магазин, корректоры T/H/D, износ, замена, заказ
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var TOOLS = [
    { id: 'T01', name: 'Фреза концевая Ø12', holder: 'HSK-A63', mag: 'Магазин 1 / поз. 12', T: 'T01', H: 'H01', D: 'D01', used: 118, limit: 120, part: 'KORPUS_142' },
    { id: 'T02', name: 'Фреза сферическая Ø8', holder: 'HSK-A63', mag: 'Магазин 1 / поз. 08', T: 'T02', H: 'H02', D: 'D02', used: 64, limit: 90, part: 'KORPUS_142' },
    { id: 'T03', name: 'Сверло Ø5,1', holder: 'BT40', mag: 'Магазин 2 / поз. 03', T: 'T03', H: 'H03', D: 'D03', used: 22, limit: 80, part: 'STAMP_141' },
    { id: 'T04', name: 'Метчик М6', holder: 'BT40', mag: 'Магазин 2 / поз. 07', T: 'T04', H: 'H04', D: 'D04', used: 47, limit: 60, part: 'STAMP_141' },
    { id: 'T05', name: 'Резец проходной', holder: 'VDI30', mag: 'Револьвер / поз. 01', T: 'T05', H: 'H05', D: 'D05', used: 30, limit: 100, part: 'VAL_119' }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function pct(t) { return Math.min(100, Math.round(t.used / t.limit * 100)); }
  function cls(t) { var p = pct(t); return p >= 95 ? 'var(--danger)' : p >= 75 ? 'var(--warning)' : 'var(--success)'; }

  function renderList() {
    var low = TOOLS.filter(function (t) { return pct(t) >= 75 && pct(t) < 95; }).length;
    var crit = TOOLS.filter(function (t) { return pct(t) >= 95; }).length;
    $('#kT').textContent = TOOLS.length;
    $('#kLow').textContent = low;
    $('#kCrit').textContent = crit;
    $('#tCount').textContent = TOOLS.length + ' позиций';
    $('#tList').innerHTML = TOOLS.map(function (t, i) {
      var p = pct(t), c = cls(t);
      return '<div class="t-row" data-i="' + i + '"><div class="grow"><div class="row between"><b style="font-size:.82rem;">' + t.id + ' · ' + t.name + '</b><span style="font-size:.76rem;color:' + c + ';font-weight:700;">' + p + '%</span></div><div class="faint" style="font-size:.66rem;">' + t.mag + ' · ' + t.part + '</div><div class="life"><i style="width:' + p + '%;background:' + c + ';"></i></div></div></div>';
    }).join('');
    $$('#tList .t-row').forEach(function (r) { r.addEventListener('click', function () { openT(parseInt(r.dataset.i, 10)); }); });
  }

  function openT(i) {
    current = TOOLS[i]; var t = current;
    var p = pct(t);
    $('#dId').textContent = t.id + ' · ' + t.holder;
    var b = $('#dStatus'); b.textContent = p >= 95 ? 'Критичный износ' : p >= 75 ? 'На пределе' : 'ОК'; b.className = 'badge ' + (p >= 95 ? 'danger' : p >= 75 ? 'warning' : 'success');
    $('#dTitle').textContent = t.name;
    $('#dTags').innerHTML = '<span class="tag">' + t.mag + '</span><span class="tag">Программа ' + t.part + '</span>';
    $('#dOffsets').innerHTML = '<div><span class="faint">Инструмент</span><b>' + t.T + '</b></div><div><span class="faint">Корректор H</span><b>' + t.H + '</b></div><div><span class="faint">Корректор D</span><b>' + t.D + '</b></div>';
    $('#dLife').innerHTML = row('Наработано', t.used + ' мин') + row('Ресурс', t.limit + ' мин') + row('Остаток', (t.limit - t.used) + ' мин') + row('Износ', p + '%', p >= 95);
    screens.go('s2');
  }
  function row(k, v, alert) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b style="' + (alert ? 'color:var(--danger);' : '') + '">' + v + '</b></div>'; }
  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }

  $('#replaceBtn').addEventListener('click', function () { current.used = 0; renderList(); done('Инструмент заменён', current.id + ' установлен новый, стойкость сброшена.', current.id); });
  $('#orderBtn').addEventListener('click', function () {
    if (window.AppData) AppData.requests.add({ source: 'B19', title: 'Заказ инструмента: ' + current.name, ref: current.id });
    done('Заявка на закупку', current.name + ' направлен в снабжение (B14).', current.id);
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
