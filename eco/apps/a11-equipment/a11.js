/* ============================================================
   A11 · Поставки оборудования
   каталог → карточка → запрос КП → успех
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var EQUIP = [
    { id: 'EQ-01', cat: 'cnc', icon: '🪚', title: 'Обрабатывающий центр 5 осей', brand: 'DMG Mori', price: 18500000, lead: '4–6 мес', tags: ['5 осей', 'Ø 630 мм', '18 000 об/мин'],
      specs: [['Перемещения X/Y/Z', '730 / 650 / 560 мм'], ['Скорость шпинделя', '18 000 об/мин'], ['Инструментов в магазине', '60'], ['Система ЧПУ', 'CELOS / Heidenhain']],
      desc: 'Универсальный 5-осевой центр для сложных корпусных деталей и пресс-форм. Поставка, пусконаладка, обучение.' },
    { id: 'EQ-02', cat: 'cnc', icon: '🌀', title: 'Токарный станок с приводным инструментом', brand: 'Okuma', price: 9800000, lead: '3–5 мес', tags: ['Ø 350 мм', 'Приводной инструмент', 'Фрезерный шпиндель'],
      specs: [['Макс. диаметр', '350 мм'], ['Длина обточки', '600 мм'], ['Приводной инструмент', 'да'], ['Ось Y', 'есть']],
      desc: 'Токарно-фрезерная обработка за один установ, высокая точность и производительность.' },
    { id: 'EQ-03', cat: 'laser', icon: '🔦', title: 'Волоконный лазер 6 кВт', brand: 'Trumpf', price: 14700000, lead: '3–5 мес', tags: ['6 кВт', 'до 20 мм', 'Стол 3×1,5 м'],
      specs: [['Мощность', '6 кВт'], ['Толщина резки', 'до 20 мм'], ['Рабочий стол', '3000 × 1500 мм'], ['Точность позиционирования', '±0,05 мм']],
      desc: 'Лазерный комплекс для высокопроизводительного раскроя листа с автоматизацией загрузки.' },
    { id: 'EQ-04', cat: 'meas', icon: '📐', title: 'Координатно-измерительная машина', brand: 'Zeiss', price: 11200000, lead: '3–4 мес', tags: ['КИМ', '0,9 мкм', 'Сканирование'],
      specs: [['Погрешность', '0,9 + L/350 мкм'], ['Диапазон', '700 × 900 × 600 мм'], ['Режим', 'Контактный + сканирующий'], ['ПО', 'CALYPSO']],
      desc: 'Высокоточный контроль геометрии и допусков для ответственных деталей и пресс-форм.' },
    { id: 'EQ-05', cat: 'tool', icon: '🧰', title: 'Комплект оснастки для ЧПУ', brand: 'Schunk', price: 1450000, lead: '4–8 нед', tags: ['Патроны', 'Тиски', 'Нулевой зажим'],
      specs: [['Состав', '20 позиций'], ['Тип зажима', 'Гидропатроны / кулачки'], ['Базирование', 'Нулевая точка'], ['Материал', 'Закалённая сталь']],
      desc: 'Комплект приспособлений для быстрой переналадки и повышения точности обработки.' },
    { id: 'EQ-06', cat: 'tool', icon: '🔩', title: 'Сменные модули для ЭЭО', brand: 'Sodick', price: 2600000, lead: '6–10 нед', tags: ['ЭЭО', 'Графит', 'Медь'],
      specs: [['Тип', 'Электроды и направляющие'], ['Материал', 'Графит / медь'], ['Совместимость', 'Станки Sodick'], ['Комплект', 'по ТЗ']],
      desc: 'Оснастка для электроэрозионной обработки сложных контуров.' },
    { id: 'EQ-07', cat: 'comp', icon: '⚙️', title: 'Шпиндельный узел (замена)', brand: 'Heidenhain', price: 1900000, lead: '8–14 нед', tags: ['Шпиндель', '16 000 об/мин'],
      specs: [['Скорость', '16 000 об/мин'], ['Охлаждение', 'жидкостное'], ['Интерфейс', 'HSK-A63'], ['Ресурс', '20 000 ч']],
      desc: 'Запасные шпиндельные узлы и комплектующие с гарантией и сервисом.' },
    { id: 'EQ-08', cat: 'laser', icon: '⚙️', title: 'Подающий автомат для лазера', brand: 'Bystronic', price: 4200000, lead: '2–4 мес', tags: ['Автоподача', 'Лист до 6 м'],
      specs: [['Формат листа', 'до 6000 мм'], ['Система', 'автоматическая'], ['Интеграция', 'с лазером'], ['Скорость', 'высокая']],
      desc: 'Автоматизация загрузки/выгрузки листа, повышение загрузки лазерного комплекса.' }
  ];

  var CAT_NAMES = { cnc: 'Станок ЧПУ', laser: 'Лазерный комплекс', meas: 'Измерительная система', tool: 'Оснастка', comp: 'Комплектующие' };

  var filter = 'all', query = '', current = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    var list = EQUIP.filter(function (e) {
      if (filter !== 'all' && e.cat !== filter) return false;
      if (query && (e.title + ' ' + e.brand + ' ' + e.tags.join(' ')).toLowerCase().indexOf(query) < 0) return false;
      return true;
    });
    $('#eqCount').textContent = list.length + ' позиций';
    $('#eqList').innerHTML = list.length ? list.map(function (e) {
      return '<div class="card clickable eq-card" data-id="' + e.id + '"><div class="row between"><span class="badge accent">' + CAT_NAMES[e.cat] + '</span><span class="faint" style="font-size:.72rem;font-weight:600;">' + e.brand + '</span></div><h3 class="mt-8" style="font-size:.9rem;">' + e.icon + ' ' + e.title + '</h3><div class="tag-row">' + e.tags.map(function (t) { return '<span class="tag">' + t + '</span>'; }).join('') + '</div><div class="meta-row"><span class="muted">Срок ' + e.lead + '</span><b>от ' + money(e.price) + '</b></div></div>';
    }).join('') : '<div class="callout info"><span class="ci">🔍</span><div>Оборудование не найдено.</div></div>';
    $$('#eqList .eq-card').forEach(function (c) { c.addEventListener('click', function () { openEq(c.dataset.id); }); });
  }
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });
  $('#search').addEventListener('input', function () { query = this.value.trim().toLowerCase(); renderList(); });

  function openEq(id) {
    current = EQUIP.find(function (e) { return e.id === id; });
    var e = current;
    $('#eCat').textContent = CAT_NAMES[e.cat];
    $('#eBrand').textContent = e.brand;
    $('#eTitle').textContent = e.icon + ' ' + e.title;
    $('#eTags').innerHTML = e.tags.map(function (t) { return '<span class="tag">' + t + '</span>'; }).join('');
    $('#eSpecs').innerHTML = e.specs.map(function (s) { return '<div class="spec-row"><span class="muted">' + s[0] + '</span><b>' + s[1] + '</b></div>'; }).join('');
    $('#eDesc').innerHTML = '<p class="muted" style="font-size:.82rem;line-height:1.55;">' + e.desc + '</p>';
    $('#ePrice').innerHTML = '<div class="row between"><span class="muted">Цена</span><b style="color:var(--accent-700);">от ' + money(e.price) + '</b></div><div class="row between mt-8"><span class="muted">Срок поставки</span><b>' + e.lead + '</b></div>';
    screens.go('s2');
  }

  /* ---------- Запрос КП ---------- */
  ['rContact'].forEach(function (id) { $('#' + id).addEventListener('input', checkReq); });
  function checkReq() { $('#sendReq').disabled = !$('#rContact').value.trim(); }
  $('#reqBtn').addEventListener('click', function () { $('#sendReq').disabled = true; screens.go('s3'); });
  $('#backEq').addEventListener('click', function () { screens.back(); });
  $('#sendReq').addEventListener('click', function () {
    var num = 'EQP-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    $('#reqNum').textContent = num;
    $('#reqCard').innerHTML =
      '<div class="row between"><span class="muted">Оборудование</span><b style="text-align:right;">' + current.title + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Количество</span><b>' + $('#rQty').value + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Срок</span><b>' + $('#rTerm').value + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Статус</span><span class="badge warning">Подбор КП</span></div>';
    App.Store.set('equipmentRequests', (App.Store.get('equipmentRequests', [])).concat([{ num: num, eq: current.title, created: App.today() }]));
    if (window.AppData) AppData.requests.add({ source: 'A11', title: current.title, amount: current.price * (parseFloat($('#rQty').value) || 1), ref: num });
    screens.go('s4');
    App.toast('Запрос ' + num + ' отправлен');
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toCatalog').addEventListener('click', function () { renderList(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
