/* ============================================================
   M1 · Маркетплейс мощностей
   витрина (заказы ↔ мощности) → карточка → отклик → сделка
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var ITEMS = [
    /* ---- Спрос: заказы ---- */
    { id: 'D-301', type: 'demand', cat: 'cnc', icon: '🪚', title: 'Фрезеровка корпуса редуктора, 12 шт', region: 'Москва', due: '25.10.2025', amount: 158000, publisher: 'ООО «Привод»', rating: 4.8, unit: 'партия',
      tags: ['Сталь', '5 осей', 'Серия'], desc: 'Материал — чугун СЧ20. Точность ±0,03 мм, шероховатость Ra 1,6. Чертёж и 3D-модель прилагаются. Возможен субподряд с приёмкой по ОТК.' },
    { id: 'D-302', type: 'demand', cat: 'laser', icon: '🔦', title: 'Лазерная резка листа 6 мм, 40 деталей', region: 'Москва', due: '22.10.2025', amount: 64000, publisher: 'ЗАО «ТехноПарк»', rating: 4.6, unit: 'партия',
      tags: ['Сталь 09Г2С', 'Раскрой'], desc: '40 деталей по DXF, кромка без грата, допуск ±0,2 мм. Самовывоз материала со склада заказчика.' },
    { id: 'D-303', type: 'demand', cat: 'heat', icon: '🔥', title: 'Вакуумная закалка штампов, 300 кг', region: 'Москва', due: '28.10.2025', amount: 54000, publisher: 'ООО «АвтоПласт»', rating: 4.9, unit: 'партия',
      tags: ['58–62 HRC', 'Отпуск'], desc: 'Закалка + двойной отпуск, твёрдость 58–62 HRC. Требуется протокол термообработки.' },
    { id: 'D-304', type: 'demand', cat: 'sub', icon: '🧪', title: 'Гальваника: цинкование с хроматом, 500 кг', region: 'Москва', due: '30.10.2025', amount: 105000, publisher: 'ООО «Металлист»', rating: 4.4, unit: 'партия',
      tags: ['Цинк', 'Хромат'], desc: 'Цинкование с хроматированием, толщина 8–12 мкм, адгезия по ГОСТ 9.302.' },
    { id: 'D-305', type: 'demand', cat: 'cnc', icon: '🌀', title: 'Токарная обработка валов, 60 шт', region: 'Москва', due: '27.10.2025', amount: 132000, publisher: 'ИП Смирнов', rating: 4.7, unit: 'партия',
      tags: ['Сталь 40Х', 'Серия', 'Шлифовка'], desc: 'Валы Ø30×210, термообработка и шлифовка шеек. Приёмка по КИМ.' },

    /* ---- Предложение: свободные мощности ---- */
    { id: 'S-201', type: 'supply', cat: 'cnc', icon: '🛠', title: 'Свободна 5-осевая фрезеровка', region: 'Москва', due: 'до 200 ч/мес', amount: 2500, publisher: 'ООО «ЛазерПро-Юг»', rating: 4.9, unit: 'час',
      tags: ['DMG Mori', '5 осей', '±0,01'], desc: 'Два 5-осевых обрабатывающих центра. Загрузка ~60%, готовы брать субподряд и серии. Есть КИМ для контроля.' },
    { id: 'S-202', type: 'supply', cat: 'laser', icon: '🔦', title: 'Лазер 6 кВт, резка до 20 мм', region: 'Тула', due: 'до 400 ч/мес', amount: 1800, publisher: 'ООО «ЛазерПро-Юг»', rating: 4.8, unit: 'час',
      tags: ['6 кВт', 'до 20 мм', 'смена 24/7'], desc: 'Волоконный лазер 6 кВт, стол 3×1,5 м. Работаем в 2 смены, срочные заказы.' },
    { id: 'S-203', type: 'supply', cat: 'heat', icon: '🔥', title: 'Вакуумная печь, закалка до 1200 °C', region: 'Подольск', due: 'до 300 ч/мес', amount: 1400, publisher: 'ЗАО «Термообработка+»', rating: 4.7, unit: 'час',
      tags: ['Вакуум', 'до 1200 °C'], desc: 'Вакуумная закалка, отпуск, нормализация. Выдаём протоколы термообработки и сертификаты.' },
    { id: 'S-204', type: 'supply', cat: 'sub', icon: '🧪', title: 'Гальваническая линия: цинк и анодирование', region: 'Москва', due: 'до 2 т/мес', amount: 210, publisher: 'ООО «Гальваник»', rating: 4.6, unit: 'кг',
      tags: ['Цинк', 'Анодирование'], desc: 'Линия цинкования и анодирования алюминия с окрашиванием. Контроль толщины покрытия.' },
    { id: 'S-205', type: 'supply', cat: 'cnc', icon: '🌀', title: 'Токарные автоматы, серия от 100 шт', region: 'Москва', due: 'до 5000 шт/мес', amount: 180, publisher: 'АО «Урал-Штамп»', rating: 4.5, unit: 'шт',
      tags: ['Автоматы', 'Серия', 'Мелкие детали'], desc: 'Токарные автоматы продольного точения, детали Ø3–32 мм, серийные заказы от 100 шт.' }
  ];

  var mode = 'demand';
  var filter = 'all';
  var query = '';
  var current = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Режим ---------- */
  $('#modeToggle').addEventListener('click', function (e) {
    var el = e.target.closest('.mode'); if (!el) return;
    $$('.mode', this).forEach(function (m) { m.classList.toggle('active', m === el); });
    mode = el.dataset.m; renderList();
  });

  /* ---------- Фильтры ---------- */
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });
  $('#search').addEventListener('input', function () { query = this.value.trim().toLowerCase(); renderList(); });

  /* ---------- Витрина ---------- */
  function renderList() {
    var list = ITEMS.filter(function (it) {
      if (it.type !== mode) return false;
      if (filter !== 'all' && it.cat !== filter) return false;
      if (query && (it.title + ' ' + it.tags.join(' ') + ' ' + it.region).toLowerCase().indexOf(query) < 0) return false;
      return true;
    });
    $('#listTitle').firstChild.nodeValue = (mode === 'demand' ? 'Заказы ' : 'Мощности ');
    $('#listCount').textContent = list.length + ' позиций';
    if (!list.length) { $('#list').innerHTML = '<div class="callout info"><span class="ci">🔍</span><div>Ничего не найдено. Измените режим или фильтр.</div></div>'; return; }
    $('#list').innerHTML = list.map(function (it) {
      var main = it.type === 'demand'
        ? '<b>' + money(it.amount) + '</b>'
        : '<b style="color:var(--accent-700);">от ' + money(it.amount) + '/' + it.unit + '</b>';
      var meta = it.type === 'demand' ? ('⏱ до ' + it.due) : ('📦 ' + it.due);
      return '<div class="card clickable accent-left" data-id="' + it.id + '">' +
        '<div class="row between"><span class="badge ' + (it.type === 'demand' ? 'warning' : 'success') + '">' + (it.type === 'demand' ? 'Заказ' : 'Мощность') + '</span><span class="rating">★ ' + it.rating.toFixed(1) + '</span></div>' +
        '<h3 class="mt-8" style="font-size:.9rem;">' + it.icon + ' ' + it.title + '</h3>' +
        '<div class="tag-row">' + it.tags.map(function (t) { return '<span class="tag">' + t + '</span>'; }).join('') + '</div>' +
        '<div class="meta-row"><span>' + meta + ' · 📍 ' + it.region + '</span>' + main + '</div></div>';
    }).join('');
    $$('#list .card').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  /* ---------- Карточка ---------- */
  function openItem(id) {
    current = ITEMS.find(function (it) { return it.id === id; });
    var it = current;
    var b = $('#iType');
    b.textContent = it.type === 'demand' ? 'Заказ · ищу исполнителя' : 'Мощность · предлагаю';
    b.className = 'badge ' + (it.type === 'demand' ? 'warning' : 'success');
    $('#iRating').textContent = '★ ' + it.rating.toFixed(1);
    $('#iTitle').textContent = it.icon + ' ' + it.title;
    $('#iTags').innerHTML = it.tags.map(function (t) { return '<span class="tag">' + t + '</span>'; }).join('');
    $('#iInfo').innerHTML = it.type === 'demand'
      ? irow('Бюджет', money(it.amount)) + irow('Срок', it.due, true) + irow('Регион', it.region) + irow('Объём', it.unit)
      : irow('Ставка', 'от ' + money(it.amount) + '/' + it.unit) + irow('Доступно', it.due) + irow('Регион', it.region) + irow('Технология', it.tags[0]);
    $('#iDesc').innerHTML = '<p class="muted" style="font-size:.82rem;line-height:1.55;">' + it.desc + '</p>';
    $('#iPublisher').innerHTML =
      '<div class="row between"><div class="row"><span style="font-size:1.3rem;">🏭</span><div><div style="font-weight:700;font-size:.84rem;">' + it.publisher + '</div><div class="faint" style="font-size:.7rem;">Проверенный участник</div></div></div><span class="rating">★ ' + it.rating.toFixed(1) + '</span></div>';
    $('#respondBtn').textContent = it.type === 'demand' ? 'Предложить исполнение →' : 'Забронировать мощность →';
    screens.go('s2');
  }
  function irow(k, v, accent) { return '<div class="row between" style="padding:8px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;' + (accent ? 'color:var(--accent-700);' : '') + '">' + v + '</b></div>'; }

  /* ---------- Отклик ---------- */
  function updateTotal() {
    var p = parseFloat($('#rPrice').value) || 0;
    var d = parseFloat($('#rDays').value) || 0;
    $('#rTotal').textContent = money(p);
    $('#rHint').textContent = p > 0 ? ('Срок ' + d + ' дн. · ' + $('#rWarranty').value) : 'Укажите цену и срок';
    $('#sendBtn').disabled = !(p > 0 && d > 0);
  }
  ['rPrice', 'rDays'].forEach(function (id) { $('#' + id).addEventListener('input', updateTotal); });
  $('#rWarranty').addEventListener('change', updateTotal);

  $('#respondBtn').addEventListener('click', function () {
    $('#rPrice').value = current.type === 'demand' ? current.amount : current.amount * 8;
    $('#rDays').value = 7;
    updateTotal(); screens.go('s3');
  });
  $('#backItem').addEventListener('click', function () { screens.back(); });

  $('#sendBtn').addEventListener('click', function () {
    var num = 'DEAL-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    $('#dealNum').textContent = num;
    $('#succTitle').textContent = current.type === 'demand' ? 'Отклик отправлен!' : 'Мощность забронирована!';
    $('#succText').textContent = current.type === 'demand'
      ? 'Публикующий получит ваше предложение и сможет принять его.'
      : 'Заявка на резерв передана исполнителю. Он подтвердит слот.';
    screens.go('s4');
    App.toast('Сделка ' + num + ' создана');
  });

  $('#chatBtn').addEventListener('click', function () { App.toast('Демо: чат с участником'); });

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
