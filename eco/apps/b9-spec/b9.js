/* ============================================================
   B9 · Спецификации и BOM
   список → позиции и смета → КП
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var SPECS = {
    'S-0142': { order: '3DMP-2025-0142', title: 'Пресс-форма втулки', status: 'В работе', items: [
      { name: 'Формообразующая плита', op: 'Фрезеровка 5 осей', mat: 'Инструментальная сталь', norm: 320, cost: 17000, sale: 24500, qty: 1 },
      { name: 'Плита матрицы', op: 'Фрезеровка 3 оси', mat: 'Сталь конструкционная', norm: 210, cost: 7700, sale: 10800, qty: 1 },
      { name: 'Электроды ЭЭО', op: 'Электроэрозия', mat: 'Графит', norm: 140, cost: 6000, sale: 8900, qty: 4 },
      { name: 'Направляющие втулки', op: 'Токарная', mat: 'Нержавеющая сталь', norm: 90, cost: 2800, sale: 4100, qty: 4 }
    ] },
    'S-0141': { order: '3DMP-2025-0141', title: 'Штамп вырубной', status: 'Смета', items: [
      { name: 'Плита верхняя', op: 'Фрезеровка 3 оси', mat: 'Сталь конструкционная', norm: 180, cost: 5600, sale: 8100, qty: 1 },
      { name: 'Пуансон', op: 'Шлифовка', mat: 'Инструментальная сталь', norm: 120, cost: 4000, sale: 5800, qty: 6 }
    ] },
    'S-0150': { order: '3DMP-2025-0150', title: 'Плита прижимная', status: 'Черновик', items: [
      { name: 'Плита', op: 'Фрезеровка 3 оси', mat: 'Сталь конструкционная', norm: 150, cost: 5500, sale: 7800, qty: 8 }
    ] }
  };

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  // Черновик из B8
  var draft = App.Store.get('specItems', []);
  if (draft.length) {
    SPECS['S-DRAFT'] = { order: 'Черновик нормирования', title: 'Новые позиции (B8)', status: 'Черновик', items: draft.map(function (d) { return { name: d.op, op: d.op, mat: d.material, norm: d.normMin, cost: Math.round(d.sale * 0.7), sale: d.sale, qty: d.qty }; }) };
  }

  function renderList() {
    var keys = Object.keys(SPECS);
    $('#specCount').textContent = keys.length + ' спецификаций';
    $('#specList').innerHTML = keys.map(function (k) {
      var s = SPECS[k];
      var total = s.items.reduce(function (a, i) { return a + i.sale * i.qty; }, 0);
      var badge = s.status === 'В работе' ? 'success' : s.status === 'Смета' ? 'info' : 'neutral';
      return '<div class="card clickable accent-left" data-id="' + k + '"><div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + s.order + '</span><span class="badge ' + badge + '">' + s.status + '</span></div><h3 class="mt-8" style="font-size:.9rem;">' + s.title + '</h3><div class="meta-row"><span class="muted">' + s.items.length + ' позиций</span><b>' + money(total) + '</b></div></div>';
    }).join('');
    $$('#specList .card').forEach(function (c) { c.addEventListener('click', function () { openSpec(c.dataset.id); }); });
  }

  function openSpec(id) {
    current = { id: id, data: SPECS[id] };
    var s = current.data;
    $('#dOrder').textContent = s.order;
    var b = $('#dStatus'); b.textContent = s.status; b.className = 'badge ' + (s.status === 'В работе' ? 'success' : s.status === 'Смета' ? 'info' : 'neutral');
    $('#dTitle').textContent = s.title;
    $('#dItemsCount').textContent = s.items.length + ' позиций';
    $('#dItems').innerHTML = s.items.map(function (i) {
      return '<div class="item-row"><div><div style="font-weight:600;">' + i.name + '</div><div class="faint" style="font-size:.68rem;">' + i.op + ' · ' + i.mat + ' · норма ' + i.norm + ' мин</div></div><div style="text-align:right;"><b>' + money(i.sale) + '</b><div class="faint" style="font-size:.68rem;">× ' + i.qty + ' шт</div></div></div>';
    }).join('');

    var sale = s.items.reduce(function (a, i) { return a + i.sale * i.qty; }, 0);
    var cost = s.items.reduce(function (a, i) { return a + i.cost * i.qty; }, 0);
    var vat = sale * 0.22;
    var margin = sale ? Math.round((sale - cost) / sale * 100) : 0;
    $('#dTotals').innerHTML =
      trow('Себестоимость', money(cost)) + trow('Цена без НДС', money(sale)) + trow('НДС 22%', money(vat)) +
      trow('Маржа', margin + '%') +
      '<div class="row between" style="padding-top:10px;margin-top:6px;border-top:1px solid var(--border-2);"><b>Итого с НДС</b><b style="color:var(--accent-700);">' + money(sale + vat) + '</b></div>';
    screens.go('s2');
  }
  function trow(k, v) { return '<div class="k-chip" style="display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }

  $('#kpBtn').addEventListener('click', function () {
    var num = 'SPEC-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    $('#specNum').textContent = num;
    var sale = current.data.items.reduce(function (a, i) { return a + i.sale * i.qty; }, 0);
    $('#specCard').innerHTML = '<div class="row between"><span class="muted">Заказ</span><b>' + current.data.order + '</b></div><div class="row between mt-8"><span class="muted">Позиций</span><b>' + current.data.items.length + '</b></div><div class="row between mt-8"><span class="muted">Сумма с НДС</span><b style="color:var(--accent-700);">' + money(sale * 1.22) + '</b></div>';
    App.Store.set('specifications', (App.Store.get('specifications', [])).concat([{ num: num, order: current.data.order, sum: Math.round(sale * 1.22), created: App.today() }]));
    screens.go('s3');
    App.toast('Спецификация ' + num + ' сформирована');
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderList(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
