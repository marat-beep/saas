/* ============================================================
   B2 · Библиотека техпроцессов и чертежей
   каталог + поиск + фильтры → карточка техпроцесса (3D, операции, файлы)
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var CATS = [
    { id: 'stamp', icon: '🔨', name: 'Штампы', count: 127 },
    { id: 'mold', icon: '🧱', name: 'Пресс-формы', count: 84 },
    { id: 'tooling', icon: '🛠', name: 'Оснастка', count: 63 },
    { id: 'cnc', icon: '🪚', name: 'ЧПУ-обработка', count: 211 }
  ];

  var TECHS = [
    { id: 'TP-0231', cat: 'stamp', title: 'Штамп вырубной для скобы', badge: 'Оригинал', icon: '🔨', material: 'Сталь Х12МФ', precision: '±0,05 мм', life: '120 000 ударов', hardness: '58–60 HRC', customer: 'ЗАО «ТехноПарк»', uses: 14, favorite: true,
      ops: ['Отрезка заготовки', 'Черновая фрезеровка', 'Термообработка', 'Шлифовка баз', 'Сборка и отладка'], files: ['TP-0231.dwg', 'TP-0231.step', 'Карта техпроцесса.pdf'] },
    { id: 'TP-0228', cat: 'mold', title: 'Пресс-форма втулки Ø42', badge: 'Оригинал', icon: '🧱', material: 'Сталь 1.2344', precision: '±0,02 мм', life: '500 000 циклов', hardness: '48–50 HRC', customer: 'ООО «АвтоПласт»', uses: 9, favorite: false,
      ops: ['Проектирование', 'Фрезеровка формообразующих', 'ЭЭО', 'Полировка', 'Термообработка', 'Испытания'], files: ['TP-0228.dwg', 'TP-0228.step'] },
    { id: 'TP-0221', cat: 'tooling', title: 'Оснастка для лазерного раскроя', badge: 'Опытный', icon: '🛠', material: 'Алюминий 7075', precision: '±0,1 мм', life: '—', hardness: '—', customer: 'ООО «ЛазерПро»', uses: 4, favorite: false,
      ops: ['Раскрой', 'Фрезеровка пазов', 'Сборка', 'Контроль'], files: ['TP-0221.dwg'] },
    { id: 'TP-0215', cat: 'cnc', title: 'Корпус редуктора — обработка', badge: 'Оригинал', icon: '🪚', material: 'Чугун СЧ20', precision: '±0,03 мм', life: '—', hardness: '—', customer: 'ООО «Привод»', uses: 22, favorite: true,
      ops: ['Базирование', 'Фрезеровка плоскостей', 'Расточка отверстий', 'Сверление', 'Контроль КИМ'], files: ['TP-0215.dwg', 'УП.nc'] },
    { id: 'TP-0209', cat: 'mold', title: 'Форма для силиконовой манжеты', badge: 'Опытный', icon: '🧱', material: 'Сталь 40Х', precision: '±0,05 мм', life: '80 000 циклов', hardness: '45 HRC', customer: 'ИП Смирнов', uses: 2, favorite: false,
      ops: ['Фрезеровка', 'Шлифовка', 'Термообработка'], files: ['TP-0209.step'] },
    { id: 'TP-0202', cat: 'stamp', title: 'Штамп гибочный двухпозиционный', badge: 'Оригинал', icon: '🔨', material: 'Сталь 5ХНМ', precision: '±0,08 мм', life: '300 000 ударов', hardness: '52 HRC', customer: 'ЗАО «ТехноПарк»', uses: 11, favorite: false,
      ops: ['Проектирование', 'Фрезеровка', 'Шлифовка', 'Сборка', 'Отладка'], files: ['TP-0202.dwg', 'TP-0202.step'] },
    { id: 'TP-0198', cat: 'cnc', title: 'Вал-шестерня — токарно-фрезерная обработка', badge: 'Оригинал', icon: '🌀', material: 'Сталь 40Х', precision: '±0,02 мм', life: '—', hardness: '48 HRC', customer: 'ИП Смирнов', uses: 31, favorite: true,
      ops: ['Токарная черновая', 'Токарная чистовая', 'Фрезеровка шлицев', 'Термообработка', 'Шлифовка'], files: ['TP-0198.dwg', 'TP-0198.step', 'УП.nc'] },
    { id: 'TP-0195', cat: 'tooling', title: 'Кондуктор сверлильный 8 отверстий', badge: 'Оригинал', icon: '🛠', material: 'Сталь 20', precision: '±0,05 мм', life: '—', hardness: '—', customer: 'ООО «Привод»', uses: 7, favorite: false,
      ops: ['Проектирование', 'Фрезеровка', 'Термообработка', 'Шлифовка', 'Сборка'], files: ['TP-0195.dwg'] },
    { id: 'TP-0191', cat: 'mold', title: 'Пресс-форма колпачка Ø55', badge: 'Оригинал', icon: '🧱', material: 'Сталь 1.2343', precision: '±0,02 мм', life: '600 000 циклов', hardness: '50 HRC', customer: 'ООО «АвтоПласт»', uses: 5, favorite: false,
      ops: ['Проектирование', 'Фрезеровка', 'ЭЭО', 'Полировка', 'Термообработка', 'Испытания'], files: ['TP-0191.dwg', 'TP-0191.step'] },
    { id: 'TP-0187', cat: 'stamp', title: 'Штамп пробивной однооперационный', badge: 'Опытный', icon: '🔨', material: 'Сталь Х12МФ', precision: '±0,1 мм', life: '90 000 ударов', hardness: '56 HRC', customer: 'ЗАО «ТехноПарк»', uses: 3, favorite: false,
      ops: ['Фрезеровка', 'Термообработка', 'Шлифовка', 'Сборка'], files: ['TP-0187.dwg'] },
    { id: 'TP-0183', cat: 'cnc', title: 'Фланец — обработка с 4-й осью', badge: 'Оригинал', icon: '🪚', material: 'Алюминий АМг6', precision: '±0,05 мм', life: '—', hardness: '—', customer: 'ООО «ЛазерПро»', uses: 18, favorite: true,
      ops: ['Базирование', 'Фрезеровка карманов', 'Сверление по кондуктору', 'Контроль КИМ'], files: ['TP-0183.dwg', 'TP-0183.step'] },
    { id: 'TP-0179', cat: 'tooling', title: 'Призма установочная шлифованная', badge: 'Оригинал', icon: '🛠', material: 'Сталь У8А', precision: '±0,01 мм', life: '—', hardness: '60 HRC', customer: 'ООО «Металлист»', uses: 9, favorite: false,
      ops: ['Фрезеровка', 'Термообработка', 'Плоское шлифование', 'Разметка'], files: ['TP-0179.dwg'] },
    { id: 'TP-0175', cat: 'mold', title: 'Форма для уплотнительного кольца', badge: 'Оригинал', icon: '🧱', material: 'Сталь 1.2344', precision: '±0,03 мм', life: '400 000 циклов', hardness: '48 HRC', customer: 'ООО «Привод»', uses: 6, favorite: false,
      ops: ['Проектирование', 'Фрезеровка', 'ЭЭО', 'Полировка', 'Сборка'], files: ['TP-0175.dwg', 'TP-0175.step'] },
    { id: 'TP-0171', cat: 'stamp', title: 'Штамп для отбортовки патрубка', badge: 'Опытный', icon: '🔨', material: 'Сталь 5ХНМ', precision: '±0,12 мм', life: '150 000 ударов', hardness: '50 HRC', customer: 'ИП Смирнов', uses: 2, favorite: false,
      ops: ['Проектирование', 'Фрезеровка', 'Шлифовка', 'Отладка'], files: ['TP-0171.dwg'] }
  ];

  var filter = 'all', query = '', current = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Категории ---------- */
  $('#cats').innerHTML = CATS.map(function (c) {
    return '<div class="cat-card" data-cat="' + c.id + '"><div class="ci">' + c.icon + '</div><div class="cn">' + c.name + '</div><div class="cc">' + c.count + ' записей</div></div>';
  }).join('');
  $('#cats').addEventListener('click', function (e) {
    var c = e.target.closest('.cat-card'); if (!c) return;
    setFilter(c.dataset.cat);
    $$('#quick .chip').forEach(function (x) { x.classList.toggle('active', x.dataset.f === c.dataset.cat); });
    renderList();
  });

  function setFilter(f) { filter = f; }

  $('#quick').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });

  $('#search').addEventListener('input', function () { query = this.value.trim().toLowerCase(); renderList(); });

  /* ---------- Список ---------- */
  function renderList() {
    var list = TECHS.filter(function (t) {
      if (filter === 'favorite' && !t.favorite) return false;
      if (['stamp', 'mold', 'tooling', 'cnc'].indexOf(filter) >= 0 && t.cat !== filter) return false;
      if (query) {
        var hay = (t.id + ' ' + t.title + ' ' + t.material + ' ' + t.customer).toLowerCase();
        if (hay.indexOf(query) < 0) return false;
      }
      return true;
    });
    $('#listCount').textContent = list.length + ' шт';
    if (!list.length) { $('#list').innerHTML = '<div class="callout info"><span class="ci">🔍</span><div>Ничего не найдено. Измените запрос или фильтр.</div></div>'; return; }
    $('#list').innerHTML = list.map(function (t) {
      return '<div class="card clickable accent-left" data-id="' + t.id + '">' +
        '<div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + t.id + '</span>' +
        '<span class="badge ' + (t.badge === 'Оригинал' ? 'accent' : 'warning') + '">' + t.badge + '</span></div>' +
        '<h3 class="mt-8" style="font-size:.9rem;">' + t.icon + ' ' + t.title + '</h3>' +
        '<div class="tag-row">' + '<span class="tag">' + t.material + '</span><span class="tag">' + t.precision + '</span><span class="tag">' + (t.favorite ? '★ Избранное' : 'Применений: ' + t.uses) + '</span>' + '</div></div>';
    }).join('');
    $$('#list .card').forEach(function (c) { c.addEventListener('click', function () { openTech(c.dataset.id); }); });
  }

  /* ---------- Карточка ---------- */
  function openTech(id) {
    current = TECHS.find(function (t) { return t.id === id; });
    $('#p3Model').textContent = current.icon;
    $('#tpNum').textContent = current.id;
    var b = $('#tpBadge'); b.textContent = current.badge; b.className = 'badge ' + (current.badge === 'Оригинал' ? 'accent' : 'warning');
    $('#tpTitle').textContent = current.icon + ' ' + current.title;
    $('#tpParams').innerHTML =
      irow('Материал', current.material) + irow('Точность', current.precision) + irow('Ресурс', current.life) + irow('Твёрдость', current.hardness) + irow('Заказчик', current.customer) + irow('Применений', current.uses + ' раз');
    $('#tpOps').innerHTML = current.ops.map(function (o, i) { return '<div class="op-item"><span class="op-n">' + (i + 1) + '</span><span style="font-size:.84rem;">' + o + '</span></div>'; }).join('');
    $('#tpFiles').innerHTML = current.files.map(function (f) {
      return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);"><span style="font-size:.82rem;">📄 ' + f + '</span><span style="color:var(--accent-600);font-weight:700;">↓</span></div>';
    }).join('');
    screens.go('s2');
  }
  function irow(k, v) { return '<div class="row between" style="padding:7px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;">' + v + '</b></div>'; }

  $('#preview3d').addEventListener('click', function () { App.toast('Демо: 3D-модель ' + current.id + ' в SolidWorks'); });
  $('#similarBtn').addEventListener('click', function () { App.toast('Создан новый техпроцесс по образцу ' + current.id); });

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
