/* ============================================================
   B27 · База УП и G-код
   шаблоны управляющих программ для Siemens / Fanuc / Heidenhain
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var TPL = [
    { id: 'GC-01', ctrl: 'Fanuc', cat: 'setup', title: 'Fanuc: начало программы и привязка', note: 'Базовый блок безопасности: сброс коррекций, выбор рабочей системы координат, вызов инструмента, включение шпинделя.',
      code: '%\nO0100 (SETUP FANUC)\nG21 G40 G49 G80 G17 G90\nG54 G0 X0 Y0\nT1 M6 (FREZA D12)\nS3000 M3\nG43 H1 Z50 M8\n(--- обработка ---)\nG0 Z100 M9\nG91 G28 Z0\nM30\n%' },
    { id: 'GC-02', ctrl: 'Fanuc', cat: 'drill', title: 'Fanuc: цикл сверления G81 / G83', note: 'G81 — обычное сверление, G83 — с выводом стружки. Укажите R (плоскость возврата), Q (шаг), F (подача).',
      code: '%\nO0200 (DRILL FANUC)\nG21 G90 G54\nT3 M6 (SVERLO D5)\nS2500 M3\nG43 H3 Z50\nG98 G83 X20 Y20 Z-25 R2 Q5 F120\nX60\nX100\nG80\nG0 Z100\nM30\n%' },
    { id: 'GC-03', ctrl: 'Fanuc', cat: 'contour', title: 'Fanuc: контур с коррекцией G41/G42', note: 'Коррекция на радиус инструмента влево (G41) / вправо (G42). D — номер корректора.',
      code: '%\nO0300 (CONTOUR FANUC)\nG21 G90 G54\nT1 M6 (FREZA D8)\nS4000 M3\nG43 H1 Z50\nG0 X-10 Y-10\nG1 Z-5 F200\nG41 D1 X0 Y0 F600\nG1 X80\nG1 Y60\nG2 X100 Y80 R20\nG1 X0\nG1 Y0\nG40 G1 X-10 Y-10\nG0 Z100\nM30\n%' },
    { id: 'GC-04', ctrl: 'Fanuc', cat: 'thread', title: 'Fanuc: резьба метчиком G84 / G76', note: 'G84 — нарезание метчиком, G76 — резцовая резьба. P — пауза, F = шаг × обороты (для G84).',
      code: '%\nO0400 (TAP FANUC)\nG21 G90 G54\nT5 M6 (METCHIK M6)\nS400 M3\nG43 H5 Z50\nM29 S400\nG98 G84 X30 Y30 Z-18 R3 F1.0\nG80\nG0 Z100\nM30\n%' },
    { id: 'GC-05', ctrl: 'Siemens', cat: 'setup', title: 'Siemens: начало программы (Sinumerik)', note: 'Установите активную систему G54, вызовите инструмент по имени, задайте обороты и рабочую подачу.',
      code: 'N10 G90 G54 G0 X0 Y0 ; SETUP SIEMENS\nN20 T="MILL12" M6\nN30 S3000 M3 M8\nN40 G0 Z50\nN50 ; --- obrabotka ---\nN60 G0 Z100 M9\nN70 M30' },
    { id: 'GC-06', ctrl: 'Siemens', cat: 'drill', title: 'Siemens: цикл CYCLE81 / CYCLE83', note: 'CYCLE81 — сверление, CYCLE83 — сверление с выводом стружки. Параметры: плоскость возврата, глубина, подача.',
      code: 'N10 G90 G54\nN20 T="DRILL5" M6\nN30 S2200 M3\nN40 G0 X20 Y20 Z50\nN50 CYCLE81(5, 0, 2, -25, 0)\nN60 G0 X60 Y20\nN70 CYCLE81(5, 0, 2, -25, 0)\nN80 G0 Z100\nN90 M30' },
    { id: 'GC-07', ctrl: 'Siemens', cat: 'contour', title: 'Siemens: карман CYCLE76 / POCKET', note: 'Обработка прямоугольного/круглого кармана циклом. Укажите размеры кармана, припуск и подачу.',
      code: 'N10 G90 G54\nN20 T="MILL8" M6\nN30 S3800 M3\nN40 G0 X0 Y0 Z50\nN50 CYCLE76(5, 0, 1, 1, 0, 1, 80, 60, -6, 0, 0, 0, 0, 1, 0, 600)\nN60 G0 Z100\nN70 M30' },
    { id: 'GC-08', ctrl: 'Siemens', cat: 'thread', title: 'Siemens: резьба CYCLE97', note: 'Нарезание резьбы резцом. Укажите шаг, глубину, конус и подачу врезания.',
      code: 'N10 G90 G54\nN20 T="THREAD" M6\nN30 S500 M3\nN40 G0 X40 Y0 Z10\nN50 CYCLE97(1.5, 0, 0, 30, 30, 1.2, 1.2, 1, 0.1, 0, 0, 0, 0, 0)\nN60 G0 Z100\nN70 M30' },
    { id: 'GC-09', ctrl: 'Heidenhain', cat: 'setup', title: 'Heidenhain: начало программы (Klartext)', note: 'Определение заготовки BLK FORM, вызов инструмента с номером оси шпинделя, подвод с FMAX.',
      code: 'BEGIN PGM SETUP MM\nQ1 = 0 ; ------------------------------------------------------------------\nBLK FORM 0.1 Z X+0 Y+0 Z-40\nBLK FORM 0.2 X+150 Y+100 Z+0\nTOOL CALL 1 Z S3000\nL X+0 Y+0 R0 FMAX M3\nL Z+50 R0 FMAX\n; ------------------------------------------------------------------\nL Z+100 R0 FMAX M30\nEND PGM SETUP MM' },
    { id: 'GC-10', ctrl: 'Heidenhain', cat: 'drill', title: 'Heidenhain: сверление циклом 200/203', note: 'Циклы сверления (200) и сверления с выводом стружки (203). Указываются глубина, шаг и подача.',
      code: 'BEGIN PGM DRILL MM\nBLK FORM 0.1 Z X+0 Y+0 Z-40\nBLK FORM 0.2 X+150 Y+100 Z+0\nTOOL CALL 3 Z S2200\nL X+20 Y+20 R0 FMAX M3\nCYCL DEF 200 SVERLEN ~\n  Q200=+2 ; BEZOP. RASST. ~\n  Q201=-25 ; GLUBINA ~\n  Q206=+120 ; PODACHA ~\n  Q203=+0 ; POVERHNOST ~\n  Q204=+50 ; 2-Y BEZOP.\nCYCL CALL\nL Z+100 R0 FMAX M30\nEND PGM DRILL MM' },
    { id: 'GC-11', ctrl: 'Heidenhain', cat: 'contour', title: 'Heidenhain: контур со скруглением RL/RR', note: 'Коррекция радиуса инструмента RL (влево) / RR (вправо). RND — скругление угла.',
      code: 'BEGIN PGM CONTOUR MM\nBLK FORM 0.1 Z X+0 Y+0 Z-20\nBLK FORM 0.2 X+120 Y+80 Z+0\nTOOL CALL 1 Z S4000\nL X-10 Y-10 R0 FMAX M3\nL Z-5 R0 F600\nAPPR LT X+0 Y+0 LEN10 RL\nL X+80 Y+0 RL\nL Y+60 RL\nRND R20 RL\nL X+0 Y+60 RL\nL X+0 Y+0 RL\nDEP LT LEN10\nL Z+100 R0 FMAX M30\nEND PGM CONTOUR MM' }
  ];

  var ctrlF = 'all', catF = 'all', query = '', current = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function hl(code) {
    return code.split('\n').map(function (line) {
      return line
        .replace(/(\(.*?\))/g, '<span class="cm">$1</span>')
        .replace(/\b(N\d+)/g, '<span class="n">$1</span>')
        .replace(/\b([GM])(\d+\.?\d*)/g, '<span class="$1">$2</span>')
        .replace(/\b([XYZ])([+-]?\d+\.?\d*)/g, '<span class="ax">$1$2</span>')
        .replace(/\b([FS])(\d+\.?\d*)/g, '<span class="fs">$1$2</span>');
    }).join('\n');
  }

  function renderList() {
    var list = TPL.filter(function (t) {
      if (ctrlF !== 'all' && t.ctrl !== ctrlF) return false;
      if (catF !== 'all' && t.cat !== catF) return false;
      if (query && (t.title + ' ' + t.ctrl + ' ' + t.code).toLowerCase().indexOf(query) < 0) return false;
      return true;
    });
    $('#gCount').textContent = list.length + ' шаблонов';
    $('#gList').innerHTML = list.length ? list.map(function (t) {
      return '<div class="g-row" data-id="' + t.id + '"><div><div style="font-weight:600;font-size:.82rem;">' + t.title + '</div><div class="faint" style="font-size:.66rem;">' + t.id + ' · ' + t.ctrl + '</div></div><span class="badge accent">' + t.ctrl + '</span></div>';
    }).join('') : '<div class="callout info"><span class="ci">🔍</span><div>Шаблоны не найдены.</div></div>';
    $$('#gList .g-row').forEach(function (r) { r.addEventListener('click', function () { openT(r.dataset.id); }); });
  }
  $('#ctrlF').addEventListener('click', function (e) { var c = e.target.closest('.chip'); if (!c) return; $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); }); ctrlF = c.dataset.f; renderList(); });
  $('#catF').addEventListener('click', function (e) { var c = e.target.closest('.chip'); if (!c) return; $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); }); catF = c.dataset.f; renderList(); });
  $('#search').addEventListener('input', function () { query = this.value.trim().toLowerCase(); renderList(); });

  function openT(id) {
    current = TPL.filter(function (t) { return t.id === id; })[0];
    $('#dId').textContent = current.id;
    $('#dCtrl').textContent = current.ctrl;
    $('#dTitle').textContent = current.title;
    $('#dTags').innerHTML = '<span class="tag">' + catName(current.cat) + '</span><span class="tag">' + current.ctrl + '</span>';
    $('#dCode').innerHTML = hl(current.code);
    $('#dNote').textContent = current.note;
    screens.go('s2');
  }
  function catName(c) { return { setup: 'Наладка', contour: 'Контур', drill: 'Сверление', thread: 'Резьба' }[c] || c; }

  $('#copyBtn').addEventListener('click', function () {
    if (navigator.clipboard) navigator.clipboard.writeText(current.code).catch(function () {});
    done('Шаблон скопирован', 'Код помещён в буфер обмена (демо).', current.id);
  });
  $('#saveBtn').addEventListener('click', function () {
    App.Store.set('ncTemplates', (App.Store.get('ncTemplates', [])).concat([{ id: current.id, title: current.title, ctrl: current.ctrl, created: App.today() }]));
    done('Сохранено в мои УП', current.title + ' добавлен в библиотеку (B18).', current.id);
  });
  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }

  $('#toList').addEventListener('click', function () { screens.replace('s1'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
