/* ============================================================
   A8 · Конфигуратор спец-технологий
   направление → параметры → расчёт → заявка
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var SPECS = {
    vulcanization: {
      icon: '🛞', title: 'Вулканизация', desc: 'Гуммирование, обкладка валов, формование',
      fields: [
        { id: 'item', type: 'text', label: 'Изделие / узел', ph: 'Вал гуммированный' },
        { id: 'rubber', type: 'select', label: 'Материал', options: [['Резина НО-68'], ['Резина СКИ-3'], ['Силикон'], ['Полиуретан']] },
        { id: 'mode', type: 'segmented', label: 'Режим', options: [['Горячая', 1], ['Холодная', 1.3]] },
        { id: 'qty', type: 'number', label: 'Количество, шт', def: 1, min: 1 },
        { id: 'dims', type: 'dims', label: 'Габариты, мм' }
      ],
      calc: function (s) {
        var vol = (s.dimL * s.dimW * s.dimH) / 1e6;
        var core = vol > 0 ? (6000 + 1500 * vol) : 16000;
        var mid = core * s.mode * s.qty;
        return { mid: mid, lead: '5–10 дней', works: [['Подготовка поверхности', 0.2], ['Нанесение / формование', 0.5], ['Вулканизация и контроль', 0.3]] };
      }
    },
    basing: {
      icon: '📐', title: 'Системы базирования', desc: 'Проектирование и изготовление приспособлений',
      fields: [
        { id: 'part', type: 'text', label: 'Деталь / узел', ph: 'Корпус редуктора' },
        { id: 'points', type: 'number', label: 'Точек базирования', def: 4, min: 1 },
        { id: 'precision', type: 'segmented', label: 'Точность', options: [['±0,1 мм', 1], ['±0,05 мм', 1.25], ['±0,01 мм', 1.6]] },
        { id: 'sets', type: 'number', label: 'Комплектов', def: 1, min: 1 }
      ],
      calc: function (s) {
        var mid = (12000 + s.points * 3500) * s.precision * s.sets;
        return { mid: mid, lead: '7–14 дней', works: [['Проектирование схемы базирования', 0.4], ['Изготовление элементов', 0.35], ['Сборка и аттестация', 0.25]] };
      }
    },
    stainless: {
      icon: '🔩', title: 'Инструмент из нержавейки', desc: 'Развёртки, метчики, пуансоны, ножи',
      fields: [
        { id: 'tool', type: 'select', label: 'Тип инструмента', options: [['Развёртка'], ['Метчик'], ['Пуансон'], ['Нож'], ['Оправка']] },
        { id: 'steel', type: 'select', label: 'Марка стали', options: [['12Х18Н10Т'], ['40Х13'], ['08Х18Н10'], ['14Х17Н2']] },
        { id: 'size', type: 'text', label: 'Типоразмер', ph: 'Ø12, L120' },
        { id: 'qty', type: 'number', label: 'Количество, шт', def: 1, min: 1 }
      ],
      calc: function (s) {
        var k = { '40Х13': 1.2, '12Х18Н10Т': 1.4, '08Х18Н10': 1.3, '14Х17Н2': 1.5 }[s.steel] || 1.3;
        var mid = (3200 * k + 800) * s.qty;
        return { mid: mid, lead: '4–9 дней', works: [['Подготовка заготовки', 0.25], ['Механообработка', 0.45], ['Термообработка и заточка', 0.3]] };
      }
    },
    turbine: {
      icon: '✈️', title: 'Лопатки турбин', desc: 'Обработка профиля лопаток ГТД',
      fields: [
        { id: 'blade', type: 'text', label: 'Тип лопатки', ph: 'Рабочая лопатка' },
        { id: 'material', type: 'select', label: 'Материал', options: [['Жаропрочный сплав ЖС'], ['Сплав ВЖ'], ['Титан ВТ6'], ['Сталь']] },
        { id: 'chord', type: 'number', label: 'Хорда, мм', def: 80, min: 1 },
        { id: 'qty', type: 'number', label: 'Количество, шт', def: 1, min: 1 }
      ],
      calc: function (s) {
        var k = { 'Жаропрочный сплав ЖС': 1.6, 'Сплав ВЖ': 1.4, 'Титан ВТ6': 1.2, 'Сталь': 1 }[s.material] || 1;
        var mid = (25000 + 9000 * s.qty) * k;
        return { mid: mid, lead: '10–20 дней', works: [['Контроль геометрии и баз', 0.2], ['Обработка пера и замка', 0.5], ['Контроль профиля на КИМ', 0.3]] };
      }
    }
  };

  var state = { spec: null, values: {} };
  var calcResult = null;
  var files = [];

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Шаг 1 ---------- */
  $('#specOptions').innerHTML = Object.keys(SPECS).map(function (id) {
    var sp = SPECS[id];
    return '<div class="option" data-id="' + id + '"><span class="opt-icon">' + sp.icon + '</span><span class="opt-title">' + sp.title + '</span><span class="opt-desc">' + sp.desc + '</span></div>';
  }).join('');
  $('#specOptions').addEventListener('click', function (e) {
    var el = e.target.closest('.option'); if (!el) return;
    $$('.option', this).forEach(function (o) { o.classList.toggle('selected', o === el); });
    state.spec = el.dataset.id; $('#toS2').disabled = false;
  });

  /* ---------- Шаг 2: динамические поля ---------- */
  function fieldHtml(f) {
    var v = state.values[f.id];
    if (f.type === 'text') return '<div class="field"><label>' + f.label + '</label><input type="text" data-fld="' + f.id + '" placeholder="' + (f.ph || '') + '" value="' + (v || '') + '"></div>';
    if (f.type === 'number') return '<div class="field"><label>' + f.label + '</label><input type="number" min="' + (f.min || 0) + '" data-fld="' + f.id + '" value="' + (v == null ? '' : v) + '"></div>';
    if (f.type === 'select') return '<div class="field"><label>' + f.label + '</label><select data-fld="' + f.id + '">' + f.options.map(function (o) { return '<option' + (v === o[0] ? ' selected' : '') + '>' + o[0] + '</option>'; }).join('') + '</select></div>';
    if (f.type === 'segmented') return '<div class="field"><label>' + f.label + '</label><div class="segmented" data-fld="' + f.id + '">' + f.options.map(function (o, i) { return '<button data-val="' + o[1] + '"' + ((v === o[1] || (i === 0 && v == null)) ? ' class="active"' : '') + '>' + o[0] + '</button>'; }).join('') + '</div></div>';
    if (f.type === 'dims') return '<div class="field"><label>' + f.label + '</label><div class="input-row">' +
      '<div style="flex:1"><input type="number" min="0" data-fld="dimL" placeholder="Длина" value="' + (state.values.dimL || '') + '"></div>' +
      '<div style="flex:1"><input type="number" min="0" data-fld="dimW" placeholder="Ширина" value="' + (state.values.dimW || '') + '"></div>' +
      '<div style="flex:1"><input type="number" min="0" data-fld="dimH" placeholder="Высота" value="' + (state.values.dimH || '') + '"></div></div></div>';
    return '';
  }

  function renderFields() {
    var sp = SPECS[state.spec];
    $('#specTitle').textContent = 'Параметры · ' + sp.title;
    $('#specFields').innerHTML = sp.fields.map(fieldHtml).join('');
  }

  function initValues() {
    var sp = SPECS[state.spec];
    state.values = {};
    sp.fields.forEach(function (f) {
      if (f.type === 'select') state.values[f.id] = f.options[0][0];
      else if (f.type === 'number') state.values[f.id] = f.def;
      else if (f.type === 'segmented') state.values[f.id] = f.options[0][1];
      else if (f.type === 'text') state.values[f.id] = '';
      else if (f.type === 'dims') { state.values.dimL = ''; state.values.dimW = ''; state.values.dimH = ''; }
    });
  }

  $('#specFields').addEventListener('input', function (e) {
    var el = e.target.closest('[data-fld]'); if (!el) return;
    var id = el.dataset.fld;
    state.values[id] = el.type === 'number' ? (parseFloat(el.value) || 0) : el.value;
  });
  $('#specFields').addEventListener('change', function (e) {
    var el = e.target.closest('select[data-fld]'); if (!el) return;
    state.values[el.dataset.fld] = el.value;
  });
  $('#specFields').addEventListener('click', function (e) {
    var b = e.target.closest('.segmented button'); if (!b) return;
    var grp = b.closest('.segmented'), id = grp.dataset.fld;
    $$('button', grp).forEach(function (x) { x.classList.toggle('active', x === b); });
    state.values[id] = parseFloat(b.dataset.val);
  });

  /* ---------- Файлы ---------- */
  $('#fileZone').addEventListener('click', function () {
    files.push('spec_' + Math.floor(1000 + Math.random() * 9000) + (Math.random() > .5 ? '.pdf' : '.dwg'));
    $('#fileList').innerHTML = files.map(function (f) { return '<span class="tag">📄 ' + f + '</span>'; }).join(' ');
  });

  /* ---------- Расчёт ---------- */
  function num(v) { return v === '' || v == null ? 0 : Number(v); }
  function summaryRows() {
    var sp = SPECS[state.spec], rows = [];
    sp.fields.forEach(function (f) {
      if (f.type === 'dims') {
        if (num(state.values.dimL) || num(state.values.dimW) || num(state.values.dimH)) rows.push([f.label, num(state.values.dimL) + '×' + num(state.values.dimW) + '×' + num(state.values.dimH)]);
      } else if (f.type === 'segmented') {
        var opt = f.options.find(function (o) { return o[1] === state.values[f.id]; });
        rows.push([f.label, opt ? opt[0] : '—']);
      } else {
        rows.push([f.label, state.values[f.id]]);
      }
    });
    return rows;
  }
  function row(k, v) { return '<div class="row between" style="padding:7px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;">' + v + '</b></div>'; }

  function calculate() {
    var s = state.values;
    s.dimL = num(s.dimL); s.dimW = num(s.dimW); s.dimH = num(s.dimH);
    var res = SPECS[state.spec].calc(s);
    var lo = res.mid * 0.85, hi = res.mid * 1.25;
    calcResult = { lo: lo, hi: hi, mid: res.mid, lead: res.lead, works: res.works };

    $('#priceRange').textContent = money(lo) + ' — ' + money(hi);
    $('#priceHint').textContent = 'Срок: ' + res.lead;
    $('#specEstimate').innerHTML = res.works.map(function (w) {
      return row(w[0], '≈ ' + money(res.mid * w[1]));
    }).join('') + '<div class="row between" style="padding-top:10px;margin-top:6px;border-top:1px solid var(--border-2);"><b>Итого (вилка)</b><b style="color:var(--accent-700);">' + money(lo) + ' — ' + money(hi) + '</b></div>';

    $('#specSummary').innerHTML = summaryRows().map(function (r) { return row(r[0], r[1] || '—'); }).join('') + row('Файлы', files.length ? files.length + ' шт' : 'не приложены');
    screens.go('s3');
  }

  $('#calcBtn').addEventListener('click', calculate);

  /* ---------- Отправка ---------- */
  $('#submitBtn').addEventListener('click', function () {
    var ticket = App.randomTicket('SPEC');
    var sp = SPECS[state.spec];
    App.Store.set('specialRequests', (App.Store.get('specialRequests', [])).concat([{ ticket: ticket, spec: sp.title, mid: Math.round(calcResult.mid), created: App.today() }]));
    if (window.AppData) AppData.requests.add({ source: 'A8', title: sp.title + ' — ' + (state.values.item || 'спец-работа'), amount: Math.round(calcResult.mid), ref: ticket });
    $('#ticketNum').textContent = ticket;
    $('#resCard').innerHTML =
      row('Направление', sp.title) +
      row('Срок', calcResult.lead) +
      row('Вилка цены', money(calcResult.lo) + ' — ' + money(calcResult.hi)) +
      row('Файлы', files.length ? files.length + ' шт' : 'не приложены');
    screens.go('s4');
    App.toast('Заявка ' + ticket + ' создана');
  });

  /* ---------- Навигация ---------- */
  $('#toS2').addEventListener('click', function () { initValues(); renderFields(); screens.go('s2'); });
  $('#editBtn').addEventListener('click', function () { screens.go('s2'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#newBtn').addEventListener('click', function () { location.reload(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
