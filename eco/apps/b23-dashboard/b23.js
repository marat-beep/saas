/* ============================================================
   B23 · Дашборд руководителя
   KPI завода, динамика выручки, топы и алерты
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var KPIS = [
    { v: money(1950000), l: 'Выручка, мес', c: 'accent' },
    { v: '18', l: 'Заказов в работе', c: 'info' },
    { v: '72%', l: 'Ср. загрузка', c: 'success' },
    { v: '74%', l: 'OEE', c: 'accent' },
    { v: '3', l: 'Просрочено', c: 'warning' },
    { v: '1,8%', l: 'Брак', c: 'success' }
  ];
  var MONTHS = [['Май', 1.4], ['Июн', 1.6], ['Июл', 1.35], ['Авг', 1.72], ['Сен', 1.83], ['Окт', 1.95]];

  var TOP_MACH = [['DMG Mori NHX', 88], ['Haas VF-4', 74], ['Okuma LB3000', 58], ['Sodick AG', 41], ['КИМ Zeiss', 40]];
  var TOP_ORDERS = [
    ['3DMP-2025-0142', 'Пресс-форма втулки', 486000, 'В работе'],
    ['3DMP-2025-0141', 'Штамп гибочный', 312000, 'ОТК'],
    ['3DMP-2025-0138', 'Штамп вырубной', 214500, 'Доставка'],
    ['3DMP-2025-0150', 'Плита прижимная', 74000, 'Производство']
  ];
  var ALERTS = [
    ['danger', 'Sodick AG — авария ALM-412, простой'],
    ['warning', '3DMP-2025-0141 — срок под угрозой (ОТК)'],
    ['warning', 'Инструмент T01 Ø12 — износ 98%, заменить'],
    ['info', 'Дебиторка выросла до 1,2 млн ₽']
  ];

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's2'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function render() {
    $('#kpis').innerHTML = KPIS.map(function (k) { return '<div class="k"><div class="v ' + k.c + '" style="color:var(--' + (k.c === 'accent' ? 'accent-700' : k.c) + ');">' + k.v + '</div><div class="l">' + k.l + '</div></div>'; }).join('');
    var max = Math.max.apply(null, MONTHS.map(function (m) { return m[1]; }));
    $('#bars').innerHTML = MONTHS.map(function (m) { return '<div class="b" style="height:' + Math.round(m[1] / max * 100) + '%;"><span>' + m[1].toFixed(2) + '</span><i>' + m[0] + '</i></div>'; }).join('');
    $('#topMach').innerHTML = TOP_MACH.map(function (m) { return '<div class="rank-row"><span>' + m[0] + '</span><b>' + m[1] + '%</b></div>'; }).join('');
    $('#topOrders').innerHTML = TOP_ORDERS.map(function (o) { return '<div class="rank-row"><div><div style="font-weight:600;">' + o[1] + '</div><div class="faint" style="font-size:.68rem;">' + o[0] + ' · ' + o[3] + '</div></div><b>' + money(o[2]) + '</b></div>'; }).join('');
    $('#alerts').innerHTML = ALERTS.map(function (a) { return '<div class="callout ' + a[0] + ' mb-8"><span class="ci">' + (a[0] === 'danger' ? '⚠️' : a[0] === 'warning' ? '🟠' : 'ℹ️') + '</span><div>' + a[1] + '</div></div>'; }).join('');
  }

  $('#toDetail').addEventListener('click', function () { screens.go('s2'); });
  $('#backMain').addEventListener('click', function () { screens.go('s1'); });
  $('#backBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  render();
})();
