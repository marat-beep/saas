/* ============================================================
   B25 · Допуски и посадки (ISO 286, демо-справочник)
   расчёт предельных размеров, зазоров/натягов и визуализация зон
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  // диапазоны диаметров (мм) и значения IT (мкм) для IT5..IT11
  var RANGES = [
    { max: 6, it: { 5: 5, 6: 8, 7: 12, 8: 18, 9: 30, 10: 48, 11: 75 } },
    { max: 10, it: { 5: 6, 6: 9, 7: 15, 8: 22, 9: 36, 10: 58, 11: 90 } },
    { max: 18, it: { 5: 8, 6: 11, 7: 18, 8: 27, 9: 43, 10: 70, 11: 110 } },
    { max: 30, it: { 5: 9, 6: 13, 7: 21, 8: 33, 9: 52, 10: 84, 11: 130 } },
    { max: 50, it: { 5: 11, 6: 16, 7: 25, 8: 39, 9: 62, 10: 100, 11: 160 } },
    { max: 80, it: { 5: 13, 6: 19, 7: 30, 8: 46, 9: 74, 10: 120, 11: 190 } },
    { max: 120, it: { 5: 15, 6: 22, 7: 35, 8: 54, 9: 87, 10: 140, 11: 220 } }
  ];
  // отклонения валов (мкм) по диапазонам
  var DEV = {
    h: null, // es = 0
    g: [-4, -5, -6, -7, -9, -10, -12],
    f: [-10, -13, -16, -20, -25, -30, -36],
    e: [-20, -25, -32, -40, -50, -60, -72],
    d: [-30, -40, -50, -65, -80, -100, -120],
    k: [1, 1, 2, 2, 3, 3, 4],
    m: [4, 6, 7, 8, 9, 11, 13],
    n: [10, 12, 15, 17, 20, 23, 27],
    p: [12, 15, 18, 22, 26, 32, 37],
    s: [20, 23, 28, 35, 43, 53, 66]
  };

  var FITS = [
    { id: 'H7/h6', hole: 7, shaft: 'h', s: 6, name: 'H7/h6', cat: 'Зазор (точная)' },
    { id: 'H7/g6', hole: 7, shaft: 'g', s: 6, name: 'H7/g6', cat: 'Зазор (скользящая)' },
    { id: 'H7/f7', hole: 7, shaft: 'f', s: 7, name: 'H7/f7', cat: 'Зазор (ходовая)' },
    { id: 'H8/f8', hole: 8, shaft: 'f', s: 8, name: 'H8/f8', cat: 'Зазор (ходовая)' },
    { id: 'H8/e8', hole: 8, shaft: 'e', s: 8, name: 'H8/e8', cat: 'Зазор (легкоходовая)' },
    { id: 'H11/d11', hole: 11, shaft: 'd', s: 11, name: 'H11/d11', cat: 'Зазор (грубая)' },
    { id: 'H7/k6', hole: 7, shaft: 'k', s: 6, name: 'H7/k6', cat: 'Переходная' },
    { id: 'H7/m6', hole: 7, shaft: 'm', s: 6, name: 'H7/m6', cat: 'Переходная' },
    { id: 'H7/n6', hole: 7, shaft: 'n', s: 6, name: 'H7/n6', cat: 'Переходная' },
    { id: 'H7/p6', hole: 7, shaft: 'p', s: 6, name: 'H7/p6', cat: 'Натяг (легкопрессовая)' },
    { id: 'H7/s6', hole: 7, shaft: 's', s: 6, name: 'H7/s6', cat: 'Натяг (прессовая)' },
    { id: 'H8/u8', hole: 8, shaft: 's', s: 8, name: 'H8/s8', cat: 'Натяг (усиленная)' }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#fit').innerHTML = FITS.map(function (f) { return '<option value="' + f.id + '">' + f.name + ' — ' + f.cat + '</option>'; }).join('');

  function rangeIndex(d) {
    for (var i = 0; i < RANGES.length; i++) if (d <= RANGES[i].max) return i;
    return RANGES.length - 1;
  }

  function calc() {
    var D = Math.max(1, parseFloat($('#diam').value) || 1);
    var fi = rangeIndex(D), R = RANGES[fi];
    var fit = FITS.filter(function (f) { return f.id === $('#fit').value; })[0] || FITS[0];

    var holeIT = R.it[fit.hole];
    var shaftIT = R.it[fit.s];
    var EI = 0, ES = holeIT;                 // отверстие H
    var es, ei;
    if (fit.shaft === 'h') { es = 0; ei = -shaftIT; }
    else if (DEV[fit.shaft] && ['g', 'f', 'e', 'd'].indexOf(fit.shaft) >= 0) { es = DEV[fit.shaft][fi]; ei = es - shaftIT; }
    else { ei = DEV[fit.shaft][fi]; es = ei + shaftIT; }

    var Smin = EI - es;   // минимальный зазор (мкм), отрицательный → натяг
    var Smax = ES - ei;   // максимальный зазор
    var type = Smin >= 0 ? 'z' : (Smax <= 0 ? 'n' : 'p');
    var typeName = type === 'z' ? 'Посадка с зазором' : type === 'n' ? 'Посадка с натягом' : 'Переходная посадка';

    current = { D: D, fit: fit, EI: EI, ES: ES, es: es, ei: ei, Smin: Smin, Smax: Smax, type: type, typeName: typeName, holeIT: holeIT, shaftIT: shaftIT };

    // результат
    var box = $('#fitType'); box.className = 'fit-type ' + type + ' mb-12';
    $('#fitName').textContent = fit.name + ' · Ø' + D + ' мм';
    $('#fitDesc').textContent = typeName + ' · ' + fit.cat;
    $('#limits').innerHTML =
      lim('Отверстие ' + 'H' + fit.hole + ' min', (D + EI / 1000).toFixed(3) + ' мм', 'EI = +' + EI + ' мкм') +
      lim('Отверстие max', (D + ES / 1000).toFixed(3) + ' мм', 'ES = +' + ES + ' мкм') +
      lim('Вал ' + fit.shaft + fit.s + ' max', (D + es / 1000).toFixed(3) + ' мм', 'es = ' + fmt(es) + ' мкм') +
      lim('Вал min', (D + ei / 1000).toFixed(3) + ' мм', 'ei = ' + fmt(ei) + ' мкм');
    $('#clearance').innerHTML =
      rowc('Максимальный зазор S<sub>max</sub>', sgn(Smax) + ' мкм', Smax > 0) +
      rowc('Минимальный зазор S<sub>min</sub>', sgn(Smin) + ' мкм', Smin > 0) +
      rowc('Допуск отверстия IT' + fit.hole, holeIT + ' мкм') +
      rowc('Допуск вала IT' + fit.s, shaftIT + ' мкм');

    drawViz();
    screens.go('s2');
  }
  function lim(t, v, sub) { return '<div class="lim"><span>' + t + '</span><b>' + v + '</b><span>' + sub + '</span></div>'; }
  function fmt(v) { return (v > 0 ? '+' : '') + v; }
  function sgn(v) { return (v > 0 ? '+' : '') + v; }
  function rowc(k, v, positive) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b style="' + (positive === false ? 'color:var(--danger);' : positive === true ? 'color:var(--success);' : '') + '">' + v + '</b></div>'; }

  function drawViz() {
    var c = current;
    var lo = Math.min(0, c.ei, c.EI) - 10;
    var hi = Math.max(c.ES, c.es, 0) + 10;
    var span = Math.max(1, hi - lo);
    function x(v) { return 6 + (v - lo) / span * 88; }
    var svg = '';
    // сетка/номинал
    svg += '<line x1="' + x(0) + '" y1="10" x2="' + x(0) + '" y2="140" stroke="#94a3b8" stroke-width="0.4" stroke-dasharray="2 2"/>';
    svg += '<text x="' + x(0) + '" y="9" font-size="5" fill="#94a3b8" text-anchor="middle">номинал</text>';
    // отверстие
    svg += '<rect x="' + x(c.EI) + '" y="36" width="' + (x(c.ES) - x(c.EI)) + '" height="20" fill="#6366f1" opacity="0.8" rx="1"/>';
    svg += '<text x="' + ((x(c.EI) + x(c.ES)) / 2) + '" y="49" font-size="5" fill="#fff" text-anchor="middle">ОТВЕРСТИЕ</text>';
    // вал
    svg += '<rect x="' + x(c.ei) + '" y="80" width="' + (x(c.es) - x(c.ei)) + '" height="20" fill="#f59e0b" opacity="0.85" rx="1"/>';
    svg += '<text x="' + ((x(c.ei) + x(c.es)) / 2) + '" y="93" font-size="5" fill="#fff" text-anchor="middle">ВАЛ</text>';
    // зазор/натяг индикатор
    var ovLo = Math.max(c.EI, c.ei), ovHi = Math.min(c.ES, c.es);
    if (ovHi > ovLo) {
      svg += '<rect x="' + x(ovLo) + '" y="60" width="' + (x(ovHi) - x(ovLo)) + '" height="12" fill="#ef4444" opacity="0.55" rx="1"/>';
      svg += '<text x="' + ((x(ovLo) + x(ovHi)) / 2) + '" y="69" font-size="4.5" fill="#fff" text-anchor="middle">перекрытие</text>';
    }
    $('#viz').innerHTML = svg;
  }

  $('#calcBtn').addEventListener('click', calc);
  $('#editBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#saveBtn').addEventListener('click', function () {
    var num = 'FIT-' + App.pad(Math.floor(1 + Math.random() * 999), 3);
    App.Store.set('fits', (App.Store.get('fits', [])).concat([{ num: num, fit: current.fit.name, d: current.D, smin: current.Smin, smax: current.Smax, created: App.today() }]));
    $('#actNum').textContent = num;
    screens.go('s3'); App.toast('Расчёт ' + num + ' сохранён');
  });
  $('#toList').addEventListener('click', function () { screens.replace('s1'); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#backBtn').addEventListener('click', function () { screens.back(); });

  calc();
})();
