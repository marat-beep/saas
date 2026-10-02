/* ============================================================
   A10 · Измерения как услуга
   услуга → параметры → расчёт → заявка
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var SVC = {
    cim: { icon: '📐', title: 'КИМ-контроль', desc: 'Измерения на координатной машине', base: 8000, per: 1500, unit: 'точка', lead: '2–4 дня', works: [['Подготовка программы', 0.25], ['Измерения на КИМ', 0.5], ['Протокол и анализ', 0.25]] },
    batch: { icon: '🔎', title: 'ОТК партии', desc: 'Выборочный/полный контроль', base: 6000, per: 400, unit: 'деталь', lead: '1–3 дня', works: [['Настройка средств контроля', 0.3], ['Контроль партии', 0.5], ['Оформление протокола', 0.2]] },
    calib: { icon: '⚖️', title: 'Калибровка СИ', desc: 'Поверка средств измерений', base: 4000, per: 900, unit: 'прибор', lead: '3–5 дней', works: [['Подготовка эталонов', 0.3], ['Калибровка', 0.5], ['Сертификат', 0.2]] },
    scan3d: { icon: '🛰', title: '3D-сканирование', desc: 'Цифровая копия и сравнение с моделью', base: 12000, per: 2500, unit: 'деталь', lead: '2–5 дней', works: [['Сканирование', 0.5], ['Обработка облака точек', 0.3], ['Отчёт сравнения', 0.2]] },
    drawing: { icon: '📋', title: 'Контроль по чертежу', desc: 'Проверка соответствия КД', base: 7000, per: 1200, unit: 'размер', lead: '2–4 дня', works: [['Анализ чертежа', 0.3], ['Измерения', 0.5], ['Заключение', 0.2]] }
  };

  var FIELDS = [
    { id: 'object', type: 'text', label: 'Объект / деталь', ph: 'Корпус редуктора' },
    { id: 'count', type: 'number', label: 'Объём (точек/деталей/приборов)', def: 10, min: 1 },
    { id: 'tolerance', type: 'segmented', label: 'Требуемая точность', options: [['Обычная ±0,1', 1], ['Точная ±0,02', 1.3], ['Высокая ±0,005', 1.7]] },
    { id: 'protocol', type: 'select', label: 'Протокол', options: [['Стандартный'], ['По форме заказчика'], ['С аккредитацией']] },
    { id: 'urgency', type: 'segmented', label: 'Срочность', options: [['Стандарт', 1], ['Срочно', 1.4]] }
  ];

  var state = { svc: null, values: {} };
  var calcResult = null, files = [];

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#svcOptions').innerHTML = Object.keys(SVC).map(function (id) {
    var s = SVC[id];
    return '<div class="option" data-id="' + id + '"><span class="opt-icon">' + s.icon + '</span><span class="opt-title">' + s.title + '</span><span class="opt-desc">' + s.desc + '</span></div>';
  }).join('');
  $('#svcOptions').addEventListener('click', function (e) {
    var el = e.target.closest('.option'); if (!el) return;
    $$('.option', this).forEach(function (o) { o.classList.toggle('selected', o === el); });
    state.svc = el.dataset.id; $('#toS2').disabled = false;
  });

  function fieldHtml(f) {
    var v = state.values[f.id];
    if (f.type === 'text') return '<div class="field"><label>' + f.label + '</label><input type="text" data-fld="' + f.id + '" placeholder="' + (f.ph || '') + '" value="' + (v || '') + '"></div>';
    if (f.type === 'number') return '<div class="field"><label>' + f.label + '</label><input type="number" min="' + (f.min || 0) + '" data-fld="' + f.id + '" value="' + (v == null ? '' : v) + '"></div>';
    if (f.type === 'select') return '<div class="field"><label>' + f.label + '</label><select data-fld="' + f.id + '">' + f.options.map(function (o) { return '<option' + (v === o[0] ? ' selected' : '') + '>' + o[0] + '</option>'; }).join('') + '</select></div>';
    if (f.type === 'segmented') return '<div class="field"><label>' + f.label + '</label><div class="segmented" data-fld="' + f.id + '">' + f.options.map(function (o, i) { return '<button data-val="' + o[1] + '"' + ((v === o[1] || (i === 0 && v == null)) ? ' class="active"' : '') + '>' + o[0] + '</button>'; }).join('') + '</div></div>';
    return '';
  }
  function renderFields() {
    $('#svcTitle').textContent = 'Параметры · ' + SVC[state.svc].title;
    $('#svcFields').innerHTML = FIELDS.map(fieldHtml).join('');
  }
  function initValues() {
    state.values = {};
    FIELDS.forEach(function (f) {
      if (f.type === 'select') state.values[f.id] = f.options[0][0];
      else if (f.type === 'number') state.values[f.id] = f.def;
      else if (f.type === 'segmented') state.values[f.id] = f.options[0][1];
      else state.values[f.id] = '';
    });
  }
  $('#svcFields').addEventListener('input', function (e) {
    var el = e.target.closest('[data-fld]'); if (!el) return;
    state.values[el.dataset.fld] = el.type === 'number' ? (parseFloat(el.value) || 0) : el.value;
  });
  $('#svcFields').addEventListener('change', function (e) {
    var el = e.target.closest('select[data-fld]'); if (!el) return;
    state.values[el.dataset.fld] = el.value;
  });
  $('#svcFields').addEventListener('click', function (e) {
    var b = e.target.closest('.segmented button'); if (!b) return;
    var grp = b.closest('.segmented');
    $$('button', grp).forEach(function (x) { x.classList.toggle('active', x === b); });
    state.values[grp.dataset.fld] = parseFloat(b.dataset.val);
  });

  $('#fileZone').addEventListener('click', function () {
    files.push('meas_' + Math.floor(1000 + Math.random() * 9000) + (Math.random() > .5 ? '.pdf' : '.step'));
    $('#fileList').innerHTML = files.map(function (f) { return '<span class="tag">📄 ' + f + '</span>'; }).join(' ');
  });

  function row(k, v) { return '<div class="row between" style="padding:7px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;">' + v + '</b></div>'; }
  function summaryRows() {
    return FIELDS.map(function (f) {
      var v = state.values[f.id];
      if (f.type === 'segmented') { var o = f.options.find(function (x) { return x[1] === v; }); return [f.label, o ? o[0] : '—']; }
      return [f.label, v];
    });
  }

  function calculate() {
    var s = SVC[state.svc], v = state.values;
    var core = s.base + s.per * (v.count || 1);
    var mid = core * v.tolerance * v.urgency;
    calcResult = { mid: mid, lo: mid * 0.85, hi: mid * 1.25, lead: s.lead, works: s.works };
    $('#priceRange').textContent = money(calcResult.lo) + ' — ' + money(calcResult.hi);
    $('#priceHint').textContent = 'Срок: ' + s.lead + ' · Протокол: ' + v.protocol;
    $('#svcEstimate').innerHTML = s.works.map(function (w) { return row(w[0], '≈ ' + money(mid * w[1])); }).join('') +
      '<div class="row between" style="padding-top:10px;margin-top:6px;border-top:1px solid var(--border-2);"><b>Итого (вилка)</b><b style="color:var(--accent-700);">' + money(calcResult.lo) + ' — ' + money(calcResult.hi) + '</b></div>';
    $('#svcSummary').innerHTML = summaryRows().map(function (r) { return row(r[0], r[1] || '—'); }).join('') + row('Файлы', files.length ? files.length + ' шт' : 'не приложены');
    screens.go('s3');
  }
  $('#calcBtn').addEventListener('click', calculate);

  $('#submitBtn').addEventListener('click', function () {
    var ticket = App.randomTicket('MET');
    var s = SVC[state.svc];
    App.Store.set('metrologyRequests', (App.Store.get('metrologyRequests', [])).concat([{ ticket: ticket, svc: s.title, mid: Math.round(calcResult.mid), created: App.today() }]));
    if (window.AppData) AppData.requests.add({ source: 'A10', title: s.title + ' — ' + (state.values.object || 'деталь'), amount: Math.round(calcResult.mid), ref: ticket });
    $('#ticketNum').textContent = ticket;
    $('#resCard').innerHTML = row('Услуга', s.title) + row('Срок', calcResult.lead) + row('Вилка цены', money(calcResult.lo) + ' — ' + money(calcResult.hi)) + row('Протокол', state.values.protocol);
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
