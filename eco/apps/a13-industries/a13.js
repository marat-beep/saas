/* ============================================================
   A13 · Отраслевые решения
   отрасли → задачи/компетенции/сервисы → заявка
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var INDUSTRIES = [
    { id: 'aviation', icon: '✈️', name: 'Авиация и турбины', desc: 'Лопатки ГТД, жаропрочные сплавы, высокая точность',
      tasks: ['Обработка пера и замка лопаток', '5-осевая обработка', 'Контроль профиля на КИМ', 'Реверс и восстановление деталей'],
      comp: ['Обработка лопаток турбин', '5-осевые центры', 'ЭЭО и шлифовка', 'Аттестация и КИМ'],
      apps: ['A6 Реверс', 'A10 Измерения', 'A11 Оборудование', 'B6 Паспорт', 'B18 УП/DNC'] },
    { id: 'medtech', icon: '🩺', name: 'Медицинская техника', desc: 'Прецизионные детали, нержавейка, чистота',
      tasks: ['Корпусные детали из нержавейки', 'Инструмент из нержавеющих сталей', 'Спец-технологии (покрытия)', 'Прослеживаемость партий'],
      comp: ['Инструмент из нержавейки', 'Мобильный ОТК', 'Цифровой паспорт', 'Спец-технологии'],
      apps: ['A8 Спец-технологии', 'A9 Документация', 'B3 ОТК', 'B6 Паспорт'] },
    { id: 'auto', icon: '🚗', name: 'Автопром', desc: 'Штампы, пресс-формы, серийные детали',
      tasks: ['Штампы последовательного действия', 'Пресс-формы', 'Серийная обработка', 'Автоматизация участков'],
      comp: ['Штампы и пресс-формы', 'Канбан производства', 'Планирование и Гант', 'АРМ'],
      apps: ['A1 Калькулятор', 'A12 АРМ', 'B1 Канбан', 'B10 Планирование'] },
    { id: 'energy', icon: '⚡', name: 'Энергетика', desc: 'Крупногабаритные детали, термообработка',
      tasks: ['Корпусные детали', 'Термообработка и покрытия', 'Контроль геометрии', 'Сервис оборудования'],
      comp: ['Термообработка', 'Мехобработка', 'Сервис', 'Измерения'],
      apps: ['A4 Сервис', 'A10 Измерения', 'B15 ТОиР'] },
    { id: 'oilgas', icon: '🛢️', name: 'Нефтегаз', desc: 'Износостойкость, вулканизация, покрытия',
      tasks: ['Гуммирование и вулканизация', 'Запорная арматура', 'Ремонт и восстановление', 'Субподряд и кооперация'],
      comp: ['Вулканизация', 'Сварка и восстановление', 'Кооперация мощностей', 'Реверс-инжиниринг'],
      apps: ['A6 Реверс', 'A8 Спец-технологии', 'M1 Маркетплейс', 'C2 Партнёры'] }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#indList').innerHTML = INDUSTRIES.map(function (i, idx) {
    return '<div class="ind" data-i="' + idx + '"><span class="ii">' + i.icon + '</span><div><b style="font-size:.9rem;">' + i.name + '</b><div class="faint" style="font-size:.72rem;">' + i.desc + '</div></div></div>';
  }).join('');
  $$('#indList .ind').forEach(function (el) { el.addEventListener('click', function () { openInd(parseInt(el.dataset.i, 10)); }); });

  function openInd(i) {
    current = INDUSTRIES[i]; var ind = current;
    $('#dIcon').textContent = ind.icon;
    $('#dName').textContent = ind.name;
    $('#dDesc').textContent = ind.desc;
    $('#dTasks').innerHTML = ind.tasks.map(function (t) { return '<div class="li">🔹 <span>' + t + '</span></div>'; }).join('');
    $('#dComp').innerHTML = ind.comp.map(function (c) { return '<div class="li">✅ <span>' + c + '</span></div>'; }).join('');
    $('#dApps').innerHTML = ind.apps.map(function (a) { return '<span class="chip-app">' + a + '</span>'; }).join('');
    screens.go('s2');
  }

  $('#reqBtn').addEventListener('click', function () {
    var ticket = App.randomTicket('IND');
    if (window.AppData) AppData.requests.add({ source: 'A13', title: 'Отрасль: ' + current.name, ref: ticket });
    $('#ticketNum').textContent = ticket;
    screens.go('s3'); App.toast('Заявка ' + ticket + ' создана');
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
