/* ============================================================
   B6 · Цифровой паспорт изделия
   скан/ввод → паспорт (маршрут, материалы, ОТК, документы) → экспорт
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  // прослеживаемость по программе: заказ → [УП, стойка]
  var PROG = {
    '3DMP-2025-0142': ['KORPUS_142 v3', 'Heidenhain TNC 640'],
    '3DMP-2025-0141': ['STAMP_141 v2', 'Fanuc 0i-MF'],
    '3DMP-2025-0119': ['VAL_119 v4', 'Okuma OSP-P300'],
    '3DMP-2025-0135': ['EDM_FORG_12 v2', 'Sodick LN2W'],
    '3DMP-2025-0150': ['PLITA_150 v1', 'Haas VF-6']
  };

  var PRODUCTS = {
    'PRD-2025-0472': {
      title: 'Пресс-форма втулки', order: '3DMP-2025-0142', customer: 'ООО «АвтоПласт»',
      material: 'Сталь 1.2344', status: 'В производстве',
      ops: [
        { op: 'Проектирование', who: 'М. Соколов', equip: 'SolidWorks', date: '04.09', s: 'done' },
        { op: 'Черновая фрезеровка', who: 'А. Кузнецов', equip: 'DMG Mori NHX', date: '09.09', s: 'done' },
        { op: 'Термообработка', who: 'ЗАО «Термо+»', equip: 'Вакуумная печь', date: '14.09', s: 'done' },
        { op: 'Чистовая обработка / ЭЭО', who: 'В. Петров', equip: 'Sodick AG', date: '19.09', s: 'current' },
        { op: 'Полировка и сборка', who: '—', equip: '—', date: 'план', s: 'planned' }
      ],
      materials: [
        { name: 'Сталь 1.2344', lot: 'L-2291', supplier: 'MetallSnab' },
        { name: 'Направляющие колонки', lot: 'L-1104', supplier: 'SKF' }
      ],
      qc: [
        { param: 'Твёрдость', val: '50 HRC', norm: '48–52 HRC', ok: true },
        { param: 'Диаметр формообразующей', val: '42,01 мм', norm: '42 ±0,02', ok: true },
        { param: 'Шероховатость Ra', val: '0,35', norm: '≤ 0,4', ok: true }
      ],
      docs: ['Договор №142', 'Спецификация', 'Сертификат стали L-2291', 'Протокол ТО']
    },
    'PRD-2025-0468': {
      title: 'Штамп вырубной', order: '3DMP-2025-0141', customer: 'ЗАО «ТехноПарк»',
      material: 'Сталь Х12МФ', status: 'ОТК',
      ops: [
        { op: 'Проектирование', who: 'М. Соколов', equip: 'SolidWorks', date: '28.08', s: 'done' },
        { op: 'Фрезеровка', who: 'А. Кузнецов', equip: 'Haas VF-4', date: '02.09', s: 'done' },
        { op: 'Термообработка', who: 'ЗАО «Термо+»', equip: 'Закалка', date: '07.09', s: 'done' },
        { op: 'Шлифовка', who: 'Д. Орлов', equip: 'Плоскошлиф', date: '10.09', s: 'done' },
        { op: 'Контроль ОТК', who: 'Е. Соколова', equip: 'КИМ Zeiss', date: '12.09', s: 'current' }
      ],
      materials: [{ name: 'Сталь Х12МФ', lot: 'L-2277', supplier: 'MetallSnab' }],
      qc: [
        { param: 'Твёрдость', val: '59 HRC', norm: '58–62 HRC', ok: true },
        { param: 'Зазор штампа', val: '0,04 мм', norm: '0,05 ±0,01', ok: true }
      ],
      docs: ['Договор №141', 'Сертификат стали L-2277', 'Протокол ОТК']
    },
    'PRD-2025-0461': {
      title: 'Вал-шестерня', order: '3DMP-2025-0119', customer: 'ИП Смирнов',
      material: 'Сталь 40Х', status: 'Готово',
      ops: [
        { op: 'Токарная обработка', who: 'В. Петров', equip: 'Okuma LB', date: '15.07', s: 'done' },
        { op: 'Фрезеровка шлицев', who: 'А. Кузнецов', equip: 'Haas VF-4', date: '20.07', s: 'done' },
        { op: 'Термообработка', who: 'ЗАО «Термо+»', equip: 'ТВЧ', date: '25.07', s: 'done' },
        { op: 'Шлифовка шеек', who: 'Д. Орлов', equip: 'Круглошлиф', date: '29.07', s: 'done' },
        { op: 'Контроль и упаковка', who: 'Е. Соколова', equip: 'КИМ', date: '01.08', s: 'done' }
      ],
      materials: [{ name: 'Сталь 40Х', lot: 'L-2205', supplier: 'MetallSnab' }],
      qc: [
        { param: 'Диаметр шейки', val: '30,005 мм', norm: '30 ±0,01', ok: true },
        { param: 'Биение', val: '0,012 мм', norm: '≤ 0,02', ok: true },
        { param: 'Твёрдость зубьев', val: '48 HRC', norm: '48 ±2', ok: true }
      ],
      docs: ['Договор №119', 'Акт выполненных работ', 'Паспорт изделия', 'УПД']
    },
    'PRD-2025-0455': {
      title: 'Электрод ЭЭО', order: '3DMP-2025-0135', customer: 'ООО «Металлист»',
      material: 'Графит МПГ-7', status: 'Готово',
      ops: [
        { op: 'Фрезеровка электрода', who: 'В. Петров', equip: 'ЧПУ 3 оси', date: '14.08', s: 'done' },
        { op: 'Контроль размеров', who: 'Е. Соколова', equip: 'КИМ', date: '16.08', s: 'done' }
      ],
      materials: [{ name: 'Графит МПГ-7', lot: 'L-2310', supplier: 'GraphitPro' }],
      qc: [
        { param: 'Длина', val: '120,02 мм', norm: '120 ±0,1', ok: true },
        { param: 'Ширина', val: '60,03 мм', norm: '60 ±0,1', ok: true }
      ],
      docs: ['Договор №135', 'Паспорт изделия']
    },
    'PRD-2025-0479': {
      title: 'Плита прижимная', order: '3DMP-2025-0150', customer: 'ООО «Привод»',
      material: 'Сталь 20', status: 'В производстве',
      ops: [
        { op: 'Фрезеровка плоскостей', who: 'А. Кузнецов', equip: 'Haas VF-6', date: '18.09', s: 'done' },
        { op: 'Сверление отверстий', who: 'А. Кузнецов', equip: 'Haas VF-6', date: '20.09', s: 'current' },
        { op: 'Шлифовка', who: '—', equip: '—', date: 'план', s: 'planned' }
      ],
      materials: [{ name: 'Сталь 20', lot: 'L-2331', supplier: 'MetallSnab' }],
      qc: [{ param: 'Длина', val: '300,1 мм', norm: '300 ±0,2', ok: true }],
      docs: ['Договор №150', 'Чертёж']
    }
  };

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Список ---------- */
  function renderList() {
    var keys = Object.keys(PRODUCTS);
    $('#prodCount').textContent = keys.length + ' изделий';
    $('#prodList').innerHTML = keys.map(function (k) {
      var p = PRODUCTS[k];
      var badge = p.status === 'Готово' ? 'success' : p.status === 'ОТК' ? 'warning' : 'info';
      return '<div class="card clickable accent-left" data-id="' + k + '"><div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + k + '</span><span class="badge ' + badge + '">' + p.status + '</span></div><h3 class="mt-8" style="font-size:.9rem;">' + p.title + '</h3><div class="meta-row"><span>🏭 ' + p.customer + '</span><span class="muted">' + p.order + '</span></div></div>';
    }).join('');
    $$('#prodList .card').forEach(function (c) { c.addEventListener('click', function () { openProduct(c.dataset.id); }); });
  }

  $('#scanBtn').addEventListener('click', function () {
    var keys = Object.keys(PRODUCTS);
    var k = keys[Math.floor(Math.random() * keys.length)];
    App.toast('QR распознан: ' + k); openProduct(k);
  });
  $('#manualBtn').addEventListener('click', function () {
    var v = $('#manual').value.trim().toUpperCase();
    if (PRODUCTS[v]) openProduct(v); else App.toast('Изделие ' + v + ' не найдено');
  });

  /* ---------- Паспорт ---------- */
  function renderQr(serial) {
    var box = $('#qrBox'), size = 11;
    box.innerHTML = '';
    box.style.gridTemplateColumns = 'repeat(' + size + ',7px)';
    var seed = 0; for (var i = 0; i < serial.length; i++) seed += serial.charCodeAt(i) * (i + 1);
    for (var r = 0; r < size; r++) for (var c = 0; c < size; c++) {
      var finder = (r < 3 && c < 3) || (r < 3 && c >= size - 3) || (r >= size - 3 && c < 3);
      var v = ((seed * (r + 3) * (c + 7)) >> 2) % 5;
      var el = document.createElement('i');
      if (finder || v < 2) el.className = 'on';
      box.appendChild(el);
    }
  }

  function openProduct(id) {
    current = { id: id, data: PRODUCTS[id] };
    var p = current.data;
    $('#pSerial').textContent = id;
    $('#pTitle').textContent = p.title;
    var badge = p.status === 'Готово' ? 'success' : p.status === 'ОТК' ? 'warning' : 'info';
    $('#pTags').innerHTML = '<span class="tag">' + p.order + '</span><span class="badge ' + badge + '">' + p.status + '</span>';
    renderQr(id);

    var prog = PROG[p.order] || ['—', '—'];
    $('#pIdent').innerHTML =
      irow('Изделие', p.title) + irow('Заказ', p.order) + irow('Заказчик', p.customer) + irow('Материал', p.material) +
      irow('Программа (УП)', prog[0]) + irow('Стойка', prog[1]) + irow('Статус', p.status);

    $('#pTimeline').innerHTML = p.ops.map(function (o) {
      var cls = o.s === 'done' ? 'done' : o.s === 'current' ? 'current' : '';
      return '<div class="tl-item ' + cls + '"><div class="dot">' + (o.s === 'done' ? '✓' : '') + '</div><div class="tl-t">' + o.op + '</div><div class="tl-m">' + o.who + ' · ' + o.equip + ' · ' + o.date + '</div></div>';
    }).join('');

    $('#pMaterials').innerHTML = p.materials.map(function (m) {
      return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><div><div style="font-weight:600;">' + m.name + '</div><div class="faint" style="font-size:.68rem;">Партия ' + m.lot + ' · ' + m.supplier + '</div></div><span class="badge success">Сертификат</span></div>';
    }).join('');

    $('#pQc').innerHTML = p.qc.map(function (q) {
      return '<div class="qc-row"><span>' + (q.ok ? '✅' : '❌') + ' ' + q.param + '</span><b>' + q.val + ' <span class="faint" style="font-weight:400;">(норма ' + q.norm + ')</span></b></div>';
    }).join('');

    $('#pDocs').innerHTML = p.docs.map(function (d) {
      return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span>📄 ' + d + '</span><span style="color:var(--accent-600);font-weight:700;">↓</span></div>';
    }).join('');

    screens.go('s2');
  }

  function irow(k, v) { return '<div class="row between" style="padding:7px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;">' + v + '</b></div>'; }

  /* ---------- Экспорт / подпись ---------- */
  function showExport(signed) {
    var p = current.data, id = current.id;
    $('#expTitle').textContent = signed ? 'Паспорт подписан' : 'Паспорт сформирован';
    $('#expText').textContent = signed ? 'Электронная подпись контролёра добавлена, паспорт зафиксирован.' : 'PDF-документ привязан к изделию и доступен в системе.';
    $('#expSerial').textContent = id;
    $('#expCard').innerHTML =
      irow('Изделие', p.title) + irow('Заказ', p.order) + irow('Операций в маршруте', p.ops.length + '') + irow('Материалов', p.materials.length + '') + irow('Записей ОТК', p.qc.length + '');
    screens.go('s3');
  }
  $('#exportBtn').addEventListener('click', function () { showExport(false); App.toast('Паспорт ' + current.id + ' сформирован'); });
  $('#signBtn').addEventListener('click', function () { showExport(true); App.toast('Паспорт подписан'); });

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#backList').addEventListener('click', function () { renderList(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
