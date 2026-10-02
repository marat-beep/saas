/* ============================================================
   B26 · Режимы резания PRO
   фрезерование / точение / сверление / резьба — расчёт S/F,
   MRR, мощности и проверка по станку
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var MATS = { steel: 'Сталь конструкционная', ss: 'Нержавеющая сталь', al: 'Алюминий', ti: 'Титан', cast: 'Чугун' };
  var KC = { steel: 0.032, ss: 0.042, al: 0.012, ti: 0.055, cast: 0.028 };
  var VC = { // Vc м/мин: [hss, carbide] по операциям (упрощённо)
    mill: { steel: [25, 140], ss: [15, 90], al: [90, 320], ti: [10, 55], cast: [30, 160] },
    turn: { steel: [30, 180], ss: [18, 110], al: [120, 400], ti: [12, 70], cast: [40, 200] },
    drill: { steel: [20, 90], ss: [12, 55], al: [60, 200], ti: [8, 35], cast: [25, 100] },
    tap: { steel: [10, 30], ss: [6, 18], al: [25, 60], ti: [5, 12], cast: [12, 35] }
  };

  var TABS = {
    mill: { label: '🪚 Фрезер.', fields: ['mat', 'tool', 'd', 'z', 'ap', 'ae', 'pw'], calc: calcMill },
    turn: { label: '🌀 Точение', fields: ['mat', 'tool', 'd', 'f', 'ap', 'pw'], calc: calcTurn },
    drill: { label: '🕳 Сверление', fields: ['mat', 'tool', 'd', 'f', 'pw'], calc: calcDrill },
    tap: { label: '🔩 Резьба', fields: ['mat', 'tool', 'd', 'pitch', 'pw'], calc: calcTap }
  };
  var FIELD_DEFS = {
    mat: { type: 'select', label: 'Материал', options: Object.keys(MATS).map(function (k) { return [MATS[k], k]; }) },
    tool: { type: 'select', label: 'Инструмент', options: [['Твёрдый сплав', 'carbide'], ['HSS', 'hss']] },
    d: { type: 'number', label: 'Диаметр D, мм', def: 12 },
    z: { type: 'number', label: 'Зубьев Z', def: 4 },
    ap: { type: 'number', label: 'Глубина ap, мм', def: 2, step: '0.1' },
    ae: { type: 'number', label: 'Ширина ae, мм', def: 6, step: '0.1' },
    f: { type: 'number', label: 'Подача f, мм/об', def: 0.2, step: '0.05' },
    pitch: { type: 'number', label: 'Шаг резьбы P, мм', def: 1, step: '0.25' },
    pw: { type: 'number', label: 'Мощность станка, кВт', def: 15 }
  };

  var tab = 'mill', values = {};
  var result = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#tabs').innerHTML = Object.keys(TABS).map(function (k, i) { return '<button data-t="' + k + '"' + (i === 0 ? ' class="active"' : '') + '>' + TABS[k].label + '</button>'; }).join('');

  function initValues() {
    values = {};
    TABS[tab].fields.forEach(function (fid) { var f = FIELD_DEFS[fid]; values[fid] = f.type === 'number' ? f.def : (f.options[0][1]); });
  }
  function renderFields() {
    $('#fields').innerHTML = TABS[tab].fields.map(function (fid) {
      var f = FIELD_DEFS[fid], v = values[fid];
      if (f.type === 'select') return '<div class="field"><label>' + f.label + '</label><select data-f="' + fid + '">' + f.options.map(function (o) { return '<option value="' + o[1] + '"' + (v === o[1] ? ' selected' : '') + '>' + o[0] + '</option>'; }).join('') + '</select></div>';
      return '<div class="field"><label>' + f.label + '</label><input type="number" step="' + (f.step || '1') + '" data-f="' + fid + '" value="' + v + '"></div>';
    }).join('');
  }
  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('button', this).forEach(function (x) { x.classList.toggle('active', x === b); });
    tab = b.dataset.t; initValues(); renderFields();
  });
  $('#fields').addEventListener('input', function (e) {
    var el = e.target.closest('[data-f]'); if (!el) return;
    values[el.dataset.f] = el.type === 'number' ? (parseFloat(el.value) || 0) : el.value;
  });
  $('#fields').addEventListener('change', function (e) {
    var el = e.target.closest('select[data-f]'); if (!el) return; values[el.dataset.f] = el.value;
  });

  function vc(op, mat, tool) { var t = VC[op][mat] || [20, 90]; return tool === 'hss' ? t[0] : t[1]; }
  function kc(mat) { return KC[mat] || 0.03; }
  function verdict(Pc) { return Pc > values.pw ? ['danger', '⚠️', 'Требуемая мощность ' + Pc.toFixed(1) + ' кВт выше станка (' + values.pw + ' кВт). Уменьшите ap/ae/pодачу.'] : ['success', '✅', 'Режимы в пределах мощности (' + values.pw + ' кВт). Загрузка ≈ ' + Math.round(Pc / values.pw * 100) + '%.']; }

  function calcMill() {
    var D = Math.max(1, values.d), Z = Math.max(1, values.z);
    var V = vc('mill', values.mat, values.tool);
    var n = Math.round(V * 1000 / (Math.PI * D));
    var fz = 0.02 + D * 0.004, Vf = Math.round(n * fz * Z);
    var mrr = values.ap * values.ae * Vf / 1000, Pc = mrr * kc(values.mat);
    return { n: n, V: V, cells: [[App.number(Vf) + ' мм/мин', 'Подача Vf'], [fz.toFixed(3) + ' мм', 'fz (на зуб)'], [App.number(mrr, 1) + ' см³/мин', 'MRR'], [Pc.toFixed(1) + ' кВт', 'Мощность']], Pc: Pc };
  }
  function calcTurn() {
    var D = Math.max(1, values.d), V = vc('turn', values.mat, values.tool);
    var n = Math.round(V * 1000 / (Math.PI * D)), Vf = Math.round(n * values.f);
    var mrr = V * values.f * values.ap, Pc = mrr * kc(values.mat);
    return { n: n, V: V, cells: [[App.number(Vf) + ' мм/мин', 'Подача Vf'], [values.f + ' мм/об', 'Подача f'], [App.number(mrr, 1) + ' см³/мин', 'MRR'], [Pc.toFixed(1) + ' кВт', 'Мощность']], Pc: Pc };
  }
  function calcDrill() {
    var D = Math.max(1, values.d), V = vc('drill', values.mat, values.tool);
    var n = Math.round(V * 1000 / (Math.PI * D)), Vf = Math.round(n * values.f);
    var mrr = Math.PI * D * D / 4 * values.f * n / 1000, Pc = mrr * kc(values.mat);
    return { n: n, V: V, cells: [[App.number(Vf) + ' мм/мин', 'Подача Vf'], [values.f + ' мм/об', 'Подача f'], [App.number(mrr, 1) + ' см³/мин', 'MRR'], [Pc.toFixed(1) + ' кВт', 'Мощность']], Pc: Pc };
  }
  function calcTap() {
    var D = Math.max(1, values.d), V = vc('tap', values.mat, values.tool);
    var n = Math.round(V * 1000 / (Math.PI * D)), Vf = Math.round(n * values.pitch);
    var mrr = Math.PI * D * D / 4 * values.pitch * n / 1000, Pc = mrr * kc(values.mat) * 1.4;
    return { n: n, V: V, cells: [[App.number(Vf) + ' мм/мин', 'Скорость врезания'], [values.pitch + ' мм', 'Шаг P'], [App.number(mrr, 1) + ' см³/мин', 'MRR'], [Pc.toFixed(1) + ' кВт', 'Мощность']], Pc: Pc };
  }

  $('#calcBtn').addEventListener('click', function () {
    result = TABS[tab].calc();
    $('#nOut').textContent = App.number(result.n) + ' об/мин';
    $('#vcOut').textContent = 'Vc ' + App.number(result.V) + ' м/мин · ' + MATS[values.mat] + ' / ' + (values.tool === 'carbide' ? 'твёрдый сплав' : 'HSS');
    $('#resGrid').innerHTML = result.cells.map(function (c) { return '<div class="res-cell"><b>' + c[0] + '</b><span>' + c[1] + '</span></div>'; }).join('');
    var vd = verdict(result.Pc);
    $('#verdict').innerHTML = '<div class="callout ' + vd[0] + '"><span class="ci">' + vd[1] + '</span><div>' + vd[2] + '</div></div>';
    screens.go('s2');
  });
  $('#editBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#saveBtn').addEventListener('click', function () {
    var num = 'CUT-' + App.pad(Math.floor(1 + Math.random() * 999), 3);
    App.Store.set('cuttingModes', (App.Store.get('cuttingModes', [])).concat([{ num: num, op: tab, mat: values.mat, n: result.n, created: App.today() }]));
    $('#actNum').textContent = num;
    screens.go('s3'); App.toast('Режимы ' + num + ' сохранены');
  });
  $('#againBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  initValues(); renderFields();
})();
