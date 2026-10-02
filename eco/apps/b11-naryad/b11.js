/* ============================================================
   B11 · Наряды
   список → состав операций и итоги смены → печать/закрытие
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var NARYADS = [
    { id: 'NR-0512', order: '3DMP-2025-0142', date: '02.10.2025', shift: '1-я смена', master: 'А. Кузнецов', status: 'Открыт',
      ops: [{ op: 'Фрезеровка 5 осей — черновая', worker: 'А. Кузнецов', hours: 6, done: true }, { op: 'Фрезеровка 5 осей — чистовая', worker: 'А. Кузнецов', hours: 4, done: false }] },
    { id: 'NR-0511', order: '3DMP-2025-0141', date: '02.10.2025', shift: '1-я смена', master: 'Д. Орлов', status: 'Открыт',
      ops: [{ op: 'Шлифовка плоскостей', worker: 'Д. Орлов', hours: 5, done: true }, { op: 'Заточка пуансонов', worker: 'Д. Орлов', hours: 3, done: true }] },
    { id: 'NR-0510', order: '3DMP-2025-0119', date: '01.10.2025', shift: '2-я смена', master: 'В. Петров', status: 'Закрыт',
      ops: [{ op: 'Токарная — шейки', worker: 'В. Петров', hours: 7, done: true }, { op: 'Фрезеровка шлицев', worker: 'В. Петров', hours: 3, done: true }] },
    { id: 'NR-0509', order: '3DMP-2025-0150', date: '01.10.2025', shift: '1-я смена', master: 'А. Кузнецов', status: 'Закрыт',
      ops: [{ op: 'Фрезеровка плоскостей', worker: 'А. Кузнецов', hours: 8, done: true }] }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    $('#nCount').textContent = NARYADS.length + ' нарядов';
    $('#nList').innerHTML = NARYADS.map(function (n, i) {
      var total = n.ops.reduce(function (a, o) { return a + o.hours; }, 0);
      var badge = n.status === 'Открыт' ? 'warning' : 'success';
      return '<div class="card clickable accent-left" data-i="' + i + '"><div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + n.id + '</span><span class="badge ' + badge + '">' + n.status + '</span></div><h3 class="mt-8" style="font-size:.9rem;">' + n.order + '</h3><div class="meta-row"><span>👤 ' + n.master + ' · ' + n.shift + ' · ' + n.date + '</span><b>' + total + ' ч</b></div></div>';
    }).join('');
    $$('#nList .card').forEach(function (c) { c.addEventListener('click', function () { openNaryad(parseInt(c.dataset.i, 10)); }); });
  }

  function openNaryad(i) {
    current = NARYADS[i];
    var n = current;
    $('#nNum').textContent = n.id;
    var b = $('#nBadge'); b.textContent = n.status; b.className = 'badge ' + (n.status === 'Открыт' ? 'warning' : 'success');
    $('#nTitle').textContent = 'Наряд ' + n.order;
    $('#nTags').innerHTML = '<span class="tag">' + n.shift + '</span><span class="tag">📅 ' + n.date + '</span><span class="tag">👤 ' + n.master + '</span>';
    $('#opCount').textContent = n.ops.length + ' операций';
    $('#nOps').innerHTML = n.ops.map(function (o, idx) {
      return '<div class="op-line"><div class="row"><div class="on">' + (idx + 1) + '</div><div><div style="font-weight:600;font-size:.82rem;">' + o.op + '</div><div class="faint" style="font-size:.68rem;">' + o.worker + '</div></div></div><div style="text-align:right;"><b>' + o.hours + ' ч</b><div>' + (o.done ? '<span class="badge success">Выполнено</span>' : '<span class="badge warning">В работе</span>') + '</div></div></div>';
    }).join('');
    var total = n.ops.reduce(function (a, o) { return a + o.hours; }, 0);
    var done = n.ops.filter(function (o) { return o.done; }).length;
    $('#nTotals').innerHTML =
      trow('Всего часов', total + ' ч') + trow('Операций', n.ops.length + '') + trow('Выполнено', done + ' из ' + n.ops.length) + trow('Готовность', Math.round(done / n.ops.length * 100) + '%');
    $('#closeBtn').disabled = n.status === 'Закрыт';
    screens.go('s2');
  }
  function trow(k, v) { return '<div class="row between" style="padding:7px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }

  $('#printBtn').addEventListener('click', function () { App.toast('Демо: наряд ' + current.id + ' отправлен на печать'); });
  $('#closeBtn').addEventListener('click', function () {
    current.status = 'Закрыт';
    current.ops.forEach(function (o) { o.done = true; });
    $('#actTitle').textContent = 'Наряд закрыт'; $('#actText').textContent = 'Часы внесены, операции отмечены выполненными.'; $('#actNum').textContent = current.id;
    renderList(); screens.go('s3'); App.toast('Наряд ' + current.id + ' закрыт');
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderList(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
