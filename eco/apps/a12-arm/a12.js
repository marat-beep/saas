/* ============================================================
   A12 · Автоматизированные рабочие места (АРМ)
   назначение → параметры → расчёт → заявка
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var PURPOSES = {
    assembly: { icon: '🔧', title: 'Сборочное место', desc: 'Верстак, освещение, оснастка', base: 85000 },
    qc: { icon: '📐', title: 'Контрольное место', desc: 'Измерительный стол, КИМ-зона', base: 120000 },
    cncop: { icon: '🪚', title: 'Место оператора ЧПУ', desc: 'Пульт, стойка, СОЖ', base: 95000 },
    packing: { icon: '📦', title: 'Упаковка и маркировка', desc: 'Стол, принтер, сканер', base: 70000 },
    warehouse: { icon: '🏭', title: 'Складское место', desc: 'Терминал, весы, стеллаж', base: 65000 }
  };

  var FIELDS = [
    { id: 'cnc', type: 'segmented', label: 'Интеграция с ЧПУ', options: [['Нет', 1], ['Да', 1.35]] },
    { id: 'software', type: 'select', label: 'ПО', options: [['Базовое', 1], ['С CAD/CAM', 1.25], ['С MES-интеграцией', 1.5]] },
    { id: 'ergonomics', type: 'segmented', label: 'Оснащение', options: [['Стандарт', 1], ['Промышленное', 1.2], ['Премиум', 1.45]] },
    { id: 'seats', type: 'number', label: 'Количество мест', def: 1, min: 1 },
    { id: 'urgency', type: 'segmented', label: 'Срочность', options: [['Стандарт', 1], ['Срочно', 1.3]] }
  ];

  var state = { purpose: null, values: {} };
  var calcResult = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#purposeOptions').innerHTML = Object.keys(PURPOSES).map(function (id) {
    var p = PURPOSES[id];
    return '<div class="option" data-id="' + id + '"><span class="opt-icon">' + p.icon + '</span><span class="opt-title">' + p.title + '</span><span class="opt-desc">' + p.desc + '</span></div>';
  }).join('');
  $('#purposeOptions').addEventListener('click', function (e) {
    var el = e.target.closest('.option'); if (!el) return;
    $$('.option', this).forEach(function (o) { o.classList.toggle('selected', o === el); });
    state.purpose = el.dataset.id; $('#toS2').disabled = false;
  });

  function fieldHtml(f) {
    var v = state.values[f.id];
    if (f.type === 'number') return '<div class="field"><label>' + f.label + '</label><input type="number" min="' + (f.min || 0) + '" data-fld="' + f.id + '" value="' + (v == null ? '' : v) + '"></div>';
    if (f.type === 'select') return '<div class="field"><label>' + f.label + '</label><select data-fld="' + f.id + '">' + f.options.map(function (o) { return '<option value="' + o[1] + '"' + (v === o[1] ? ' selected' : '') + '>' + o[0] + '</option>'; }).join('') + '</select></div>';
    if (f.type === 'segmented') return '<div class="field"><label>' + f.label + '</label><div class="segmented" data-fld="' + f.id + '">' + f.options.map(function (o, i) { return '<button data-val="' + o[1] + '"' + ((v === o[1] || (i === 0 && v == null)) ? ' class="active"' : '') + '>' + o[0] + '</button>'; }).join('') + '</div></div>';
    return '';
  }
  function renderFields() {
    $('#armTitle').textContent = 'Параметры · ' + PURPOSES[state.purpose].title;
    $('#armFields').innerHTML = FIELDS.map(fieldHtml).join('');
  }
  function initValues() {
    state.values = {};
    FIELDS.forEach(function (f) {
      if (f.type === 'select') state.values[f.id] = parseFloat(f.options[0][1]);
      else if (f.type === 'number') state.values[f.id] = f.def;
      else state.values[f.id] = f.options[0][1];
    });
  }
  $('#armFields').addEventListener('input', function (e) {
    var el = e.target.closest('[data-fld]'); if (!el) return;
    state.values[el.dataset.fld] = el.type === 'number' ? (parseFloat(el.value) || 0) : parseFloat(el.value);
  });
  $('#armFields').addEventListener('change', function (e) {
    var el = e.target.closest('select[data-fld]'); if (!el) return;
    state.values[el.dataset.fld] = parseFloat(el.value);
  });
  $('#armFields').addEventListener('click', function (e) {
    var b = e.target.closest('.segmented button'); if (!b) return;
    var grp = b.closest('.segmented');
    $$('button', grp).forEach(function (x) { x.classList.toggle('active', x === b); });
    state.values[grp.dataset.fld] = parseFloat(b.dataset.val);
  });

  function row(k, v) { return '<div class="row between" style="padding:7px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;">' + v + '</b></div>'; }
  function label(f, v) { if (f.type === 'segmented') { var o = f.options.find(function (x) { return x[1] === v; }); return o ? o[0] : v; } if (f.type === 'select') { var o2 = f.options.find(function (x) { return x[1] === v; }); return o2 ? o2[0] : v; } return v; }

  function calculate() {
    var p = PURPOSES[state.purpose], v = state.values;
    var perSeat = p.base * v.cnc * v.software * v.ergonomics;
    var mid = perSeat * v.seats * v.urgency;
    calcResult = { mid: mid, lo: mid * 0.85, hi: mid * 1.2, perSeat: perSeat };
    $('#priceRange').textContent = money(calcResult.lo) + ' — ' + money(calcResult.hi);
    $('#priceHint').textContent = '≈ ' + money(perSeat) + ' за место · срок 4–10 недель';
    $('#armEstimate').innerHTML =
      row('Место (' + p.title + ')', money(p.base)) + row('Интеграция с ЧПУ', label(FIELDS[0], v.cnc)) + row('ПО', label(FIELDS[1], v.software)) + row('Оснащение', label(FIELDS[2], v.ergonomics)) +
      '<div class="row between" style="padding-top:10px;margin-top:6px;border-top:1px solid var(--border-2);"><b>Итого (вилка)</b><b style="color:var(--accent-700);">' + money(calcResult.lo) + ' — ' + money(calcResult.hi) + '</b></div>';
    $('#armSummary').innerHTML = FIELDS.map(function (f) { return row(f.label, f.type === 'number' ? state.values[f.id] : label(f, state.values[f.id])); }).join('');
    screens.go('s3');
  }
  $('#calcBtn').addEventListener('click', calculate);

  $('#submitBtn').addEventListener('click', function () {
    var ticket = App.randomTicket('ARM');
    App.Store.set('armRequests', (App.Store.get('armRequests', [])).concat([{ ticket: ticket, purpose: PURPOSES[state.purpose].title, seats: state.values.seats, mid: Math.round(calcResult.mid), created: App.today() }]));
    if (window.AppData) AppData.requests.add({ source: 'A12', title: 'АРМ: ' + PURPOSES[state.purpose].title + ' × ' + state.values.seats, amount: Math.round(calcResult.mid), ref: ticket });
    $('#ticketNum').textContent = ticket;
    $('#resCard').innerHTML = row('Назначение', PURPOSES[state.purpose].title) + row('Мест', state.values.seats) + row('Цена за место', money(calcResult.perSeat)) + row('Вилка', money(calcResult.lo) + ' — ' + money(calcResult.hi));
    screens.go('s4');
    App.toast('Заявка ' + ticket + ' создана');
  });

  $('#toS2').addEventListener('click', function () { initValues(); renderFields(); screens.go('s2'); });
  $('#editBtn').addEventListener('click', function () { screens.go('s2'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#newBtn').addEventListener('click', function () { location.reload(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
