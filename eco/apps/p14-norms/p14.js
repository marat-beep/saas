/* ============================================================
   P14 · Нормирование PRO (SaaS)
   продукт-оболочка: карта модулей, тенант/план, дорожная карта
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;
  var C = window.AppCatalog;

  // модули «Нормирования PRO» → наши приложения (id) + статус: r=готово, p=частично, x=план
  var MODULES = [
    ['Расчёты, нормы, K-коэффициенты', 'B8', 'r'],
    ['Металлопрокат (масса, схема)', 'B34', 'r'],
    ['Спецификация (BOM)', 'B9', 'r'],
    ['Станки, слоты, Гант, эскалация', 'B10', 'p'],
    ['Прогноз загрузки', 'B39', 'r'],
    ['Производственный календарь РФ', 'B38', 'r'],
    ['Наряды (ежедневные, Word/PDF)', 'B11', 'r'],
    ['Экспорт PDF/DOC/CSV/JSON/ICS', 'P15', 'r'],
    ['История расчётов', null, 'x'],
    ['База аналогов', null, 'x'],
    ['Графики (SVG/PNG)', 'B23', 'p'],
    ['CRM-карточка клиента', 'A14', 'r'],
    ['Заказы', 'A3', 'r'],
    ['Счета, договоры, оплаты', 'P7', 'r'],
    ['Экономика, KPI, ТБУ', 'B31', 'r'],
    ['Справочники (движок)', 'B35', 'r'],
    ['Аналитика (сводная)', 'P3', 'p'],
    ['Отчёты (PDF)', 'P15', 'r'],
    ['Вложения / Storage', null, 'x'],
    ['Self-Test', 'P10', 'r'],
    ['Dev Mode', 'P10', 'r'],
    ['Роли и доступ', 'P13', 'r']
  ];

  var folder = {}; if (C) C.groups.forEach(function (g) { g.apps.forEach(function (a) { folder[a.id] = a.href.replace(/^apps\//, '').replace(/\/index\.html$/, ''); }); });
  function link(id) { return id && folder[id] ? '<a href="../' + folder[id] + '/index.html">' + id + '</a>' : '<span class="faint">—</span>'; }
  function badge(st) { return st === 'r' ? '<span class="badge r">готово</span>' : st === 'p' ? '<span class="badge p">частично</span>' : '<span class="badge x">план</span>'; }

  var screens = AppRouter.create({
    onShow: function (s) { $$('#nav button').forEach(function (b) { b.classList.toggle('active', b.dataset.s === s.id); }); window.scrollTo(0, 0); },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });
  $('#nav').addEventListener('click', function (e) { var b = e.target.closest('button'); if (!b) return; screens.go(b.dataset.s); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  var ready = MODULES.filter(function (m) { return m[2] === 'r'; }).length;
  var part = MODULES.filter(function (m) { return m[2] === 'p'; }).length;
  var plan = MODULES.filter(function (m) { return m[2] === 'x'; }).length;

  $('#kpi').innerHTML = kpi(String(ready), 'готово', 'accent') + kpi(String(part), 'частично', 'warning') + kpi(String(plan), 'в плане', 'info') + kpi(String(MODULES.length), 'модулей всего', 'accent');
  function kpi(v, l, c) { return '<div class="stat"><div class="num ' + c + '" style="font-size:1.4rem;">' + v + '</div><div class="label">' + l + '</div></div>'; }

  var row = function (m) { return '<div class="mrow"><span class="nm">' + m[0] + '</span>' + link(m[1]) + badge(m[2]) + '</div>'; };
  $('#ovList').innerHTML = MODULES.slice(0, 8).map(row).join('');
  $('#modList').innerHTML = MODULES.map(row).join('');

  var flags = (window.AppData ? AppData.settings.get('flags', {}) : {}) || {};
  var on = MODULES.filter(function (m) { return m[1] && flags[m[1]] !== false; }).length;
  $('#planCard').innerHTML = '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.84rem;"><span class="muted">Продукт</span><b>Нормирование PRO</b></div>' +
    '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.84rem;"><span class="muted">Тариф</span><b>Бизнес / Корпоративный</b></div>' +
    '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.84rem;"><span class="muted">Модулей доступно</span><b>' + on + ' из ' + ready + ' готовых</b></div>' +
    '<div class="row between" style="padding:8px 0;font-size:.84rem;"><span class="muted">Мультитенантность</span><b>да (P1), white-label (P6)</b></div>';
  $('#flagCard').innerHTML = MODULES.filter(function (m) { return m[1]; }).map(function (m) {
    var en = flags[m[1]] !== false;
    return '<div class="mrow"><span class="nm">' + m[0] + '</span><b style="font-size:.8rem;">' + m[1] + '</b><span class="badge ' + (en ? 'r' : 'x') + '">' + (en ? 'вкл' : 'выкл') + '</span></div>';
  }).join('');

  var ROAD = [
    ['A', 'Продукт-оболочка, календарь, прогноз, карта интеграции', 'сделано'],
    ['B', 'Центр экспорта (PDF/DOC/CSV/JSON/ICS) + конструктор отчётов — P15', 'сделано'],
    ['C', 'База аналогов + K-коэффициенты + авто-подбор в B8', 'план'],
    ['D', 'Слоты по времени + SLA-эскалация (B10/B24)', 'план'],
    ['E', 'Вложения/Storage + сводный журнал истории', 'план']
  ];
  $('#roadList').innerHTML = ROAD.map(function (r) {
    return '<div class="mrow"><b style="min-width:22px;">' + r[0] + '</b><span class="nm">' + r[1] + '</span>' + (r[2] === 'сделано' ? '<span class="badge r">сделано</span>' : '<span class="badge x">план</span>') + '</div>';
  }).join('');
})();
