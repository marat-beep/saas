/* ============================================================
   B34 · Калькулятор металлопроката (по образцу «Нормирования»)
   типы: круг / прямоугольник / труба; пресеты, DIN-материалы,
   плотность вручную, НДС, схема, применение к позиции
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var MATS = [
    ['Ст3 / 09Г2С', 'DIN S235JR / S355JR', 7850], ['Сталь 20', 'DIN C22', 7850], ['Сталь 45', 'DIN C45', 7826],
    ['40Х', 'DIN 41Cr4', 7826], ['12Х18Н10Т', 'DIN 1.4301', 7900], ['40Х13', 'DIN 1.4021', 7700],
    ['Х12МФ', 'DIN 1.2379', 7700], ['4Х5МФС', 'DIN 1.2344', 7700], ['Алюминий АМг6', 'DIN 3.2315', 2700],
    ['Алюминий 7075', 'DIN 3.4365', 2810], ['Латунь ЛС59-1', 'DIN CuZn39Pb3', 8500], ['Медь М1', 'DIN 2.0090', 8900],
    ['Титан ВТ6', 'DIN 3.7165', 4500], ['Чугун СЧ20', '—', 7200]
  ];
  var PRESETS = {
    round_D: [20, 25, 30, 40, 50, 60, 70, 80, 100, 120, 150, 200, 250, 300, 400, 500, 600, 800, 1000],
    rect: [10, 20, 30, 40, 50, 60, 80, 100, 120, 150, 200],
    pipe_D: [20, 25, 32, 40, 50, 57, 76, 89, 108, 133, 159, 219],
    pipe_t: [2, 3, 3.5, 4, 5, 6, 8, 10],
    len: [50, 100, 200, 300, 500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 8000, 10000]
  };
  var FIELDS = {
    round: [{ id: 'd', label: 'Диаметр D, мм', def: 20, preset: 'round_D' }],
    rect: [{ id: 'b', label: 'Ширина B, мм', def: 20, preset: 'rect' }, { id: 'h', label: 'Высота H, мм', def: 20, preset: 'rect' }],
    pipe: [{ id: 'd', label: 'Наружный D, мм', def: 57, preset: 'pipe_D' }, { id: 't', label: 'Стенка t, мм', def: 3.5, preset: 'pipe_t' }]
  };

  var type = 'round';
  var vals = {};
  function n(id) { return parseFloat($('#' + id).value) || 0; }

  $('#mat').innerHTML = MATS.map(function (m, i) { return '<option value="' + i + '">' + m[0] + ' — ' + m[1] + ' — ' + m[2] + ' кг/м³</option>'; }).join('');
  $('#lenPresets').innerHTML = PRESETS.len.map(function (v) { return '<button data-len="' + v + '">' + v + '</button>'; }).join('');

  function renderParams() {
    var f = FIELDS[type];
    $('#params').innerHTML = f.map(function (x) {
      return '<div class="field"><label>' + x.label + '</label><input type="number" step="any" id="p_' + x.id + '" value="' + (vals[x.id] != null ? vals[x.id] : x.def) + '"></div>' +
        '<div class="presets" data-preset="' + x.preset + '" data-fid="' + x.id + '">' + PRESETS[x.preset].map(function (v) { return '<button data-v="' + v + '">' + v + '</button>'; }).join('') + '</div>';
    }).join('');
    $$('#params input').forEach(function (inp) { inp.addEventListener('input', function () { vals[inp.id.slice(2)] = parseFloat(inp.value) || 0; calc(); }); });
    $$('#params .presets button').forEach(function (b) {
      b.addEventListener('click', function () {
        var fid = b.closest('.presets').dataset.fid; vals[fid] = parseFloat(b.dataset.v);
        $('#p_' + fid).value = b.dataset.v; calc();
      });
    });
  }

  function rho() { return $('#manualRho').checked ? (parseFloat($('#rho').value) || 7850) : MATS[parseInt($('#mat').value, 10)][2]; }

  function areaMm2() {
    if (type === 'round') { var d = vals.d || 0; return Math.PI / 4 * d * d; }
    if (type === 'rect') { return (vals.b || 0) * (vals.h || 0); }
    var D = vals.d || 0, t = vals.t || 0, dd = D - 2 * t; return Math.PI / 4 * (D * D - dd * dd);
  }
  function areaM2() { return areaMm2() / 1e6; }

  function calc() {
    var len = n('len'), qty = Math.max(1, n('qty')), price = n('price'), vatPct = parseFloat($('#vat').value) || 0;
    var r = rho();
    var mPerM = areaM2() * r;
    var piece = mPerM * len / 1000;
    var batch = piece * qty;
    var base = batch * price, vat = base * vatPct / 100, total = base + vat;

    $('#batchOut').textContent = App.number(batch, 2) + ' кг';
    $('#batchSub').textContent = qty + ' × ' + App.number(piece, 2) + ' кг · ρ ' + r + ' кг/м³';
    $('#resList').innerHTML =
      row('Вес 1 м', App.number(mPerM, 3) + ' кг') +
      row('Вес заготовки', App.number(piece, 2) + ' кг') +
      row('Вес партии', App.number(batch, 2) + ' кг') +
      row('Материал', MATS[parseInt($('#mat').value, 10)][0]) +
      row('Цена без НДС', money(base)) +
      row('НДС ' + vatPct + '%', money(vat)) +
      '<div class="res-row total"><span>С НДС</span><b style="color:var(--accent-700);">' + money(total) + '</b></div>';
    $('#matHint').textContent = 'DIN ' + MATS[parseInt($('#mat').value, 10)][1] + ' · ρ = ' + MATS[parseInt($('#mat').value, 10)][2] + ' кг/м³ · допуск ±5%';
    drawScheme();
  }
  function row(k, v) { return '<div class="res-row"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }

  function drawScheme() {
    var svg = '<svg viewBox="0 0 300 180">';
    svg += '<rect x="0" y="0" width="300" height="180" fill="none"/>';
    if (type === 'round') {
      var d = vals.d || 20, r = Math.min(70, 20 + d / 12);
      svg += '<circle cx="150" cy="90" r="' + r + '" fill="var(--accent-100)" stroke="var(--accent)" stroke-width="2"/>';
      svg += '<line x1="' + (150 - r) + '" y1="90" x2="' + (150 + r) + '" y2="90" stroke="var(--accent-700)" stroke-width="1.5"/>';
      svg += '<text x="150" y="86" text-anchor="middle" font-size="13" fill="var(--accent-700)">Ø' + d + '</text>';
    } else if (type === 'rect') {
      var b = vals.b || 20, h = vals.h || 20, w = Math.min(160, 30 + b), hh = Math.min(120, 30 + h);
      svg += '<rect x="' + (150 - w / 2) + '" y="' + (90 - hh / 2) + '" width="' + w + '" height="' + hh + '" fill="var(--accent-100)" stroke="var(--accent)" stroke-width="2"/>';
      svg += '<text x="150" y="' + (90 - hh / 2 - 6) + '" text-anchor="middle" font-size="12" fill="var(--accent-700)">' + b + '</text>';
      svg += '<text x="' + (150 - w / 2 - 8) + '" y="90" text-anchor="end" font-size="12" fill="var(--accent-700)">' + h + '</text>';
    } else {
      var D = vals.d || 57, t = vals.t || 3.5, R = Math.min(70, 20 + D / 6), ri = Math.max(6, R - Math.max(6, t * 3));
      svg += '<circle cx="150" cy="90" r="' + R + '" fill="var(--accent-100)" stroke="var(--accent)" stroke-width="2"/>';
      svg += '<circle cx="150" cy="90" r="' + ri + '" fill="var(--surface)" stroke="var(--accent)" stroke-width="2"/>';
      svg += '<text x="150" y="18" text-anchor="middle" font-size="12" fill="var(--accent-700)">Ø' + D + ' × ' + t + '</text>';
    }
    svg += '</svg>';
    $('#scheme').innerHTML = svg;
  }

  function initType(t) {
    type = t;
    $$('#typeSeg button').forEach(function (x) { x.classList.toggle('active', x.dataset.t === t); });
    vals = {}; FIELDS[t].forEach(function (f) { vals[f.id] = f.def; });
    renderParams(); calc();
  }

  $('#typeSeg').addEventListener('click', function (e) { var b = e.target.closest('button'); if (!b) return; initType(b.dataset.t); });
  $('#lenPresets').addEventListener('click', function (e) { var b = e.target.closest('button'); if (!b) return; $('#len').value = b.dataset.len; calc(); });
  $('#manualRho').addEventListener('change', function () { $('#rhoWrap').style.display = this.checked ? '' : 'none'; calc(); });
  ['len', 'qty', 'price', 'rho'].forEach(function (id) { $('#' + id).addEventListener('input', calc); });
  $('#mat').addEventListener('change', calc);
  $('#vat').addEventListener('change', calc);

  $('#applyBtn').addEventListener('click', function () {
    var pos = App.Store.get('metalPositions', []);
    pos.push({ type: type, dims: JSON.stringify(vals), len: n('len'), qty: n('qty'), mass: areaM2() * rho() * n('len') / 1000 * Math.max(1, n('qty')), rho: rho(), created: App.today() });
    App.Store.set('metalPositions', pos);
    AppData.log.add({ action: 'Металлопрокат применён к позиции', detail: type + ' · партия ' + pos.length });
    App.toast('Позиция добавлена (масса ' + App.number(areaM2() * rho() * n('len') / 1000 * Math.max(1, n('qty')), 1) + ' кг)');
  });
  $('#clearBtn').addEventListener('click', function () {
    $('#len').value = 1000; $('#qty').value = 1; $('#price').value = 800; $('#manualRho').checked = false; $('#rhoWrap').style.display = 'none';
    initType(type);
  });

  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  initType('round');
})();
