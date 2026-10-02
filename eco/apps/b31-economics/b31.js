/* ============================================================
   B31 · Экономика заказа
   себестоимость, нормочас × операции, маржа, НДС, KPI
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  // если в B28 сохранён нормочас — берём его
  var saved = App.Store.get('machineHourRates', []);
  var NH = saved.length ? saved[0].price : 6200; // цена с НДС по умолчанию

  var ORDERS = [
    { num: '3DMP-2025-0142', title: 'Пресс-форма втулки', client: 'ООО «АвтоПласт»', materials: 210000, nh: 46, extra: 88000, price: 486000 },
    { num: '3DMP-2025-0141', title: 'Штамп гибочный', client: 'ЗАО «ТехноПарк»', materials: 132000, nh: 28, extra: 54000, price: 312000 },
    { num: '3DMP-2025-0138', title: 'Штамп вырубной', client: 'ООО «АвтоПласт»', materials: 96000, nh: 19, extra: 41000, price: 214500 },
    { num: '3DMP-2025-0150', title: 'Плита прижимная', client: 'ООО «Привод»', materials: 47000, nh: 9, extra: 21000, price: 74000 },
    { num: '3DMP-2025-0119', title: 'Вал-шестерня', client: 'ИП Смирнов', materials: 61000, nh: 11, extra: 24000, price: 132000 }
  ];

  function cost(o) { return o.materials + o.nh * NH + o.extra; }
  function margin(o) { var c = cost(o); return c ? Math.round((o.price - c) / o.price * 100) : 0; }

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderKpi() {
    var ms = ORDERS.map(margin);
    var avg = Math.round(ms.reduce(function (a, b) { return a + b; }, 0) / ms.length);
    $('#kMargin').textContent = avg + '%';
    $('#kProfit').textContent = ms.filter(function (m) { return m > 0; }).length;
    $('#kLoss').textContent = ms.filter(function (m) { return m <= 0; }).length;
    $('#oCount').textContent = ORDERS.length + ' заказов';
    $('#orderList').innerHTML = ORDERS.map(function (o, i) {
      var m = margin(o), ok = m > 0;
      return '<div class="o-row" data-i="' + i + '"><div><div style="font-weight:600;font-size:.84rem;">' + o.title + '</div><div class="faint" style="font-size:.66rem;">' + o.num + ' · ' + o.client + '</div></div><div style="text-align:right;"><b>' + money(o.price) + '</b><div class="badge ' + (ok ? 'success' : 'danger') + '" style="margin-top:4px;">маржа ' + m + '%</div></div></div>';
    }).join('');
    $$('#orderList .o-row').forEach(function (el) { el.addEventListener('click', function () { openO(parseInt(el.dataset.i, 10)); }); });
  }

  function openO(i) {
    var o = ORDERS[i], c = cost(o), m = margin(o), vat = o.price * 0.22 / 1.22, profit = o.price - c;
    $('#dNum').textContent = o.num + ' · ' + o.client;
    var b = $('#dMargin'); b.textContent = 'маржа ' + m + '%'; b.className = 'badge ' + (m > 0 ? 'success' : 'danger');
    $('#dTitle').textContent = o.title;
    $('#dCost').innerHTML =
      row('Материалы', money(o.materials)) +
      row('Нормочасы: ' + o.nh + ' × ' + money(NH), money(o.nh * NH)) +
      row('Прочие затраты', money(o.extra)) +
      '<div class="brk" style="padding-top:10px;border-top:2px solid var(--border);"><span><b>Себестоимость</b></span><b>' + money(c) + '</b></div>';
    $('#dPrice').innerHTML =
      row('Цена с НДС', money(o.price)) +
      row('НДС 22% (в цене)', money(vat)) +
      row('Цена без НДС', money(o.price - vat)) +
      row('Прибыль', money(profit), profit > 0 ? 'var(--success)' : 'var(--danger)') +
      '<div class="brk" style="padding-top:10px;border-top:2px solid var(--border);"><span><b>Маржа</b></span><b style="color:' + (m > 0 ? 'var(--success)' : 'var(--danger)') + ';">' + m + '%</b></div>';
    screens.go('s2');
  }
  function row(k, v, cls) { return '<div class="brk"><span class="muted">' + k + '</span><b' + (cls ? ' style="color:' + cls + '"' : '') + '>' + v + '</b></div>'; }

  $('#back1').addEventListener('click', function () { screens.go('s1'); });
  $('#backBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderKpi();
})();
