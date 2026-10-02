/* ============================================================
   A9 · Заказ конструкторской документации
   тип → параметры → расчёт → заявка
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var TYPES = {
    drawings: { icon: '📐', title: 'Чертёж по ТЗ', desc: 'Рабочие чертежи деталей', base: 8000, per: 3500, lead: '3–7 дней', works: [['Анализ ТЗ', 0.2], ['Построение чертежа', 0.5], ['Нормоконтроль', 0.3]] },
    model3d: { icon: '🧊', title: '3D-модель', desc: 'Твёрдотельная модель детали', base: 9000, per: 5000, lead: '2–5 дней', works: [['Построение 3D-модели', 0.6], ['Проверка геометрии', 0.2], ['Экспорт и оформление', 0.2]] },
    tech: { icon: '⚙️', title: 'Техпроцесс', desc: 'Маршрутная/операционная карта', base: 12000, per: 4000, lead: '4–8 дней', works: [['Анализ детали', 0.25], ['Разработка операций', 0.5], ['Нормирование и согласование', 0.25]] },
    td: { icon: '📚', title: 'Комплект КД/ТД', desc: 'Полный комплект документов', base: 25000, per: 6000, lead: '7–15 дней', works: [['Проектирование', 0.4], ['Оформление по ГОСТ', 0.35], ['Согласование', 0.25]] },
    reverse: { icon: '🔍', title: 'КД по образцу', desc: 'Реверс-документация по детали', base: 15000, per: 7000, lead: '5–12 дней', works: [['Обмер образца', 0.35], ['Построение модели и чертежей', 0.45], ['Согласование', 0.2]] },
    changes: { icon: '✏️', title: 'Изменение КД (ECN)', desc: 'Доработка существующей КД', base: 5000, per: 2500, lead: '1–4 дня', works: [['Анализ изменения', 0.3], ['Правка документации', 0.5], ['Регистрация версии', 0.2]] }
  };

  var state = { type: null, values: {} };
  var calcResult = null, files = [];

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#docOptions').innerHTML = Object.keys(TYPES).map(function (id) {
    var t = TYPES[id];
    return '<div class="option" data-id="' + id + '"><span class="opt-icon">' + t.icon + '</span><span class="opt-title">' + t.title + '</span><span class="opt-desc">' + t.desc + '</span></div>';
  }).join('');
  $('#docOptions').addEventListener('click', function (e) {
    var el = e.target.closest('.option'); if (!el) return;
    $$('.option', this).forEach(function (o) { o.classList.toggle('selected', o === el); });
    state.type = el.dataset.id; $('#toS2').disabled = false;
  });

  var FIELDS = [
    { id: 'object', type: 'text', label: 'Объект / изделие', ph: 'Корпус редуктора' },
    { id: 'cad', type: 'select', label: 'CAD-система', options: [['SolidWorks'], ['КОМПАС-3D'], ['AutoCAD'], ['Не важно']] },
    { id: 'format', type: 'select', label: 'Формат выдачи', options: [['PDF'], ['DWG'], ['STEP'], ['PDF + исходники']] },
    { id: 'count', type: 'number', label: 'Количество деталей / позиций', def: 1, min: 1 },
    { id: 'stage', type: 'segmented', label: 'Стадия', options: [['Эскиз', 0.7], ['Технический проект', 1], ['Рабочая КД', 1.3]] },
    { id: 'urgency', type: 'segmented', label: 'Срочность', options: [['Стандарт', 1], ['Срочно', 1.4], ['Экспресс', 1.9]] }
  ];

  function fieldHtml(f) {
    var v = state.values[f.id];
    if (f.type === 'text') return '<div class="field"><label>' + f.label + '</label><input type="text" data-fld="' + f.id + '" placeholder="' + (f.ph || '') + '" value="' + (v || '') + '"></div>';
    if (f.type === 'number') return '<div class="field"><label>' + f.label + '</label><input type="number" min="' + (f.min || 0) + '" data-fld="' + f.id + '" value="' + (v == null ? '' : v) + '"></div>';
    if (f.type === 'select') return '<div class="field"><label>' + f.label + '</label><select data-fld="' + f.id + '">' + f.options.map(function (o) { return '<option' + (v === o[0] ? ' selected' : '') + '>' + o[0] + '</option>'; }).join('') + '</select></div>';
    if (f.type === 'segmented') return '<div class="field"><label>' + f.label + '</label><div class="segmented" data-fld="' + f.id + '">' + f.options.map(function (o, i) { return '<button data-val="' + o[1] + '"' + ((v === o[1] || (i === 0 && v == null)) ? ' class="active"' : '') + '>' + o[0] + '</button>'; }).join('') + '</div></div>';
    return '';
  }
  function renderFields() {
    $('#docTitle').textContent = 'Параметры · ' + TYPES[state.type].title;
    $('#docFields').innerHTML = FIELDS.map(fieldHtml).join('');
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

  $('#docFields').addEventListener('input', function (e) {
    var el = e.target.closest('[data-fld]'); if (!el) return;
    state.values[el.dataset.fld] = el.type === 'number' ? (parseFloat(el.value) || 0) : el.value;
  });
  $('#docFields').addEventListener('change', function (e) {
    var el = e.target.closest('select[data-fld]'); if (!el) return;
    state.values[el.dataset.fld] = el.value;
  });
  $('#docFields').addEventListener('click', function (e) {
    var b = e.target.closest('.segmented button'); if (!b) return;
    var grp = b.closest('.segmented');
    $$('button', grp).forEach(function (x) { x.classList.toggle('active', x === b); });
    state.values[grp.dataset.fld] = parseFloat(b.dataset.val);
  });

  $('#fileZone').addEventListener('click', function () {
    files.push('src_' + Math.floor(1000 + Math.random() * 9000) + (Math.random() > .5 ? '.pdf' : '.step'));
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
    var t = TYPES[state.type], s = state.values;
    var core = t.base + t.per * (s.count || 1);
    var mid = core * s.stage * s.urgency;
    calcResult = { mid: mid, lo: mid * 0.85, hi: mid * 1.25, lead: t.lead, works: t.works };

    $('#priceRange').textContent = money(calcResult.lo) + ' — ' + money(calcResult.hi);
    $('#priceHint').textContent = 'Срок: ' + t.lead;
    $('#docEstimate').innerHTML = t.works.map(function (w) { return row(w[0], '≈ ' + money(mid * w[1])); }).join('') +
      '<div class="row between" style="padding-top:10px;margin-top:6px;border-top:1px solid var(--border-2);"><b>Итого (вилка)</b><b style="color:var(--accent-700);">' + money(calcResult.lo) + ' — ' + money(calcResult.hi) + '</b></div>';
    $('#docSummary').innerHTML = summaryRows().map(function (r) { return row(r[0], r[1] || '—'); }).join('') + row('Файлы', files.length ? files.length + ' шт' : 'не приложены');
    screens.go('s3');
  }
  $('#calcBtn').addEventListener('click', calculate);

  $('#submitBtn').addEventListener('click', function () {
    var ticket = App.randomTicket('KD');
    var t = TYPES[state.type];
    App.Store.set('docRequests', (App.Store.get('docRequests', [])).concat([{ ticket: ticket, type: t.title, mid: Math.round(calcResult.mid), created: App.today() }]));
    if (window.AppData) AppData.requests.add({ source: 'A9', title: t.title + ' — ' + (state.values.object || 'объект'), amount: Math.round(calcResult.mid), ref: ticket });
    $('#ticketNum').textContent = ticket;
    $('#resCard').innerHTML = row('Тип работ', t.title) + row('Срок', t.lead) + row('Вилка цены', money(calcResult.lo) + ' — ' + money(calcResult.hi)) + row('Исходные данные', files.length ? files.length + ' шт' : 'не приложены');
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
