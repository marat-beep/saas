/* ============================================================
   A1 · Калькулятор заказа
   5 экранов: тип → параметры → чертёж → вилка цены → успех
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  /* ---------- Справочники ---------- */
  var TYPES = [
    { id: 'mill',   icon: '🪚', title: 'Фрезеровка ЧПУ',   desc: 'Плоскостная и объёмная 3–5 осей', base: 3500, rate: 900 },
    { id: 'turn',   icon: '🌀', title: 'Токарная обработка', desc: 'Тела вращения, валы, втулки',    base: 2800, rate: 800 },
    { id: 'laser',  icon: '🔦', title: 'Лазерная резка',    desc: 'Листовой раскрой, контур',        base: 1500, rate: 600 },
    { id: 'engrave',icon: '✒️', title: 'Гравировка',        desc: 'Маркировка, шильды, серийники',   base: 1200, rate: 400 },
    { id: 'print3d',icon: '🧊', title: '3D-печать',         desc: 'FDM/SLA прототипы и оснастка',    base: 2000, rate: 1100 }
  ];

  var MATERIALS = [
    { id: 'steel',    name: 'Сталь конструкционная', k: 1.0 },
    { id: 'stainless',name: 'Нержавеющая сталь',     k: 1.35 },
    { id: 'aluminum', name: 'Алюминий',              k: 0.9 },
    { id: 'brass',    name: 'Латунь / бронза',       k: 1.25 },
    { id: 'titanium', name: 'Титан ВТ6',              k: 2.2 },
    { id: 'copper',   name: 'Медь М1',                k: 1.6 },
    { id: 'plastic',  name: 'Пластик / ABS',          k: 0.7 }
  ];

  /* ---------- Состояние ---------- */
  var draft = {
    type: null,
    material: 'steel',
    qty: 1,
    dims: { l: 0, w: 0, h: 0 },
    complexity: 1,
    urgency: 1,
    file: null
  };
  var calc = null;

  var screens = AppRouter.create({
    onShow: function (s) {
      var map = { s1: 'Шаг 1 · Тип', s2: 'Шаг 2 · Параметры', s3: 'Шаг 3 · Чертёж', s4: 'Расчёт', s5: 'Готово' };
      $('#backBtn').hidden = (s.id === 's1' || s.id === 's5');
      $('#content').scrollTop = 0;
    },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Рендер шага 1 ---------- */
  var typeWrap = $('#typeOptions');
  typeWrap.innerHTML = TYPES.map(function (t) {
    return '<div class="option" data-id="' + t.id + '">' +
      '<span class="opt-icon">' + t.icon + '</span>' +
      '<span class="opt-title">' + t.title + '</span>' +
      '<span class="opt-desc">' + t.desc + '</span></div>';
  }).join('');

  typeWrap.addEventListener('click', function (e) {
    var el = e.target.closest('.option');
    if (!el) return;
    $$('.option', typeWrap).forEach(function (o) { o.classList.toggle('selected', o === el); });
    draft.type = el.dataset.id;
    $('#toS2').disabled = false;
  });

  /* ---------- Рендер шага 2 ---------- */
  var matSel = $('#material');
  matSel.innerHTML = MATERIALS.map(function (m) { return '<option value="' + m.id + '">' + m.name + '</option>'; }).join('');
  matSel.addEventListener('change', function () { draft.material = matSel.value; });

  $('#qty').addEventListener('input', function () { draft.qty = Math.max(1, parseInt(this.value, 10) || 1); });
  ['dimL', 'dimW', 'dimH'].forEach(function (id, i) {
    $('#' + id).addEventListener('input', function () {
      var key = ['l', 'w', 'h'][i];
      draft.dims[key] = Math.max(0, parseFloat(this.value) || 0);
    });
  });

  bindSegmented('#complexity', function (v) { draft.complexity = v; });
  bindSegmented('#urgency', function (v) { draft.urgency = v; });

  function bindSegmented(sel, cb) {
    var root = $(sel);
    root.addEventListener('click', function (e) {
      var b = e.target.closest('button'); if (!b) return;
      $$('button', root).forEach(function (x) { x.classList.toggle('active', x === b); });
      cb(parseFloat(b.dataset.v));
    });
  }

  /* ---------- Шаг 3: файл ---------- */
  function attachSim() {
    draft.file = 'detail_' + Math.floor(1000 + Math.random() * 9000) + (Math.random() > .5 ? '.step' : '.pdf');
    var size = (Math.random() * 4 + .3).toFixed(1) + ' МБ';
    $('#fileList').innerHTML =
      '<div class="row between" style="background:var(--surface);border:1px solid var(--border);border-radius:var(--r-sm);padding:10px 12px;">' +
      '<div class="row"><span style="font-size:1.1rem;">📄</span><div><div style="font-weight:600;font-size:.84rem;">' + draft.file + '</div><div class="faint" style="font-size:.68rem;">' + size + ' · загружено</div></div></div>' +
      '<button class="btn btn-ghost btn-sm" id="rmFile">Убрать</button></div>';
    $('#toS4').disabled = false;
    $('#rmFile').addEventListener('click', function () {
      draft.file = null; $('#fileList').innerHTML = ''; $('#toS4').disabled = true;
    });
  }
  $('#dropZone').addEventListener('click', attachSim);
  $('#skipFile').addEventListener('click', function () { draft.file = null; $('#fileList').innerHTML = ''; calculate(); screens.go('s4'); });
  $('#toS4').addEventListener('click', function () { calculate(); screens.go('s4'); });

  /* ---------- Расчёт ---------- */
  function calculate() {
    var type = TYPES.find(function (t) { return t.id === draft.type; }) || TYPES[0];
    var mat = MATERIALS.find(function (m) { return m.id === draft.material; }) || MATERIALS[0];

    var volDm3 = (draft.dims.l * draft.dims.w * draft.dims.h) / 1e6;
    var hasDims = volDm3 > 0;
    var qty = draft.qty;
    var stage = hasDims ? Math.max(type.base, type.rate * volDm3) : type.base;
    var discount = qty >= 200 ? .78 : qty >= 50 ? .85 : qty >= 10 ? .92 : 1;
    var cores = stage * mat.k * draft.complexity * qty * discount;
    var urgencyFee = cores * (draft.urgency - 1);
    var mid = cores + urgencyFee;
    var lo = Math.max(type.base, mid * .85);
    var hi = Math.max(lo * 1.05, mid * 1.25);
    calc = { mid: mid, lo: lo, hi: hi, type: type, mat: mat, hasDims: hasDims, volDm3: volDm3, urgencyFee: urgencyFee, stage: stage, cores: cores, qty: qty };

    $('#priceRange').textContent = money(lo) + ' — ' + money(hi);
    $('#pricePer').textContent = '≈ ' + money(mid / qty) + ' за шт · ' + qty + ' ' + App.plural(qty, 'шт', 'шт', 'шт');

    $('#estimate').innerHTML =
      row('Тип обработки', type.title) +
      row('Материал', mat.name + ' (×' + mat.k + ')') +
      row('Объём партии', hasDims ? App.number(volDm3, 3) + ' дм³' : 'оценочно') +
      row('Сложность', '×' + draft.complexity) +
      row('Обработка', money(cores)) +
      (urgencyFee > 0 ? row('Срочность', money(urgencyFee)) : '') +
      '<div class="row between" style="padding-top:10px;margin-top:6px;border-top:1px solid var(--border-2);"><b>Итого (вилка)</b><b class="accent" style="color:var(--accent-700)">' + money(lo) + ' — ' + money(hi) + '</b></div>';

    var urgencyText = draft.urgency === 1 ? 'Стандарт 5–7 дн' : draft.urgency === 1.35 ? 'Быстро 2–3 дн' : 'Срочно 24 ч';
    $('#summary').innerHTML =
      row('Тип', type.title) + row('Материал', mat.name) +
      row('Количество', qty + ' шт') +
      row('Срок', urgencyText) +
      row('Чертёж', draft.file || 'не приложен');
  }

  function row(k, v) {
    return '<div class="row between" style="padding:7px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;">' + v + '</b></div>';
  }

  /* ---------- Отправка ---------- */
  $('#submitBtn').addEventListener('click', function () {
    var ticket = App.randomTicket('3DMP');
    var saved = {
      ticket: ticket, type: calc.type.id, typeTitle: calc.type.title, material: calc.mat.name,
      qty: calc.qty, complexity: draft.complexity, urgency: draft.urgency,
      file: draft.file, lo: calc.lo, hi: calc.hi, mid: calc.mid, created: App.today()
    };
    App.Draft.set(saved);
    var orders = App.Store.get('orders', []);
    orders.unshift({ number: ticket, title: calc.type.title + ' — ' + calc.qty + ' шт', status: 'Новая', date: App.today(), amount: Math.round(calc.mid) });
    App.Store.set('orders', orders.slice(0, 20));
    if (window.AppData) AppData.requests.add({ source: 'A1', title: calc.type.title + ' — ' + calc.qty + ' шт', amount: Math.round(calc.mid), ref: ticket });

    $('#ticketNum').textContent = ticket;
    $('#resType').textContent = calc.type.title;
    $('#resPrice').textContent = money(calc.lo) + ' — ' + money(calc.hi);
    screens.go('s5');
    App.toast('Заявка ' + ticket + ' создана');
  });

  /* ---------- Навигация ---------- */
  $('#toS2').addEventListener('click', function () { screens.go('s2'); });
  $('#toS3').addEventListener('click', function () { screens.go('s3'); });
  $('#editBtn').addEventListener('click', function () { screens.go('s2'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#newCalc').addEventListener('click', function () { location.reload(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
