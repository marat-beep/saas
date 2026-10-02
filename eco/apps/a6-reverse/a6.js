/* ============================================================
   A6 · Реверс-инжиниринг
   образец → методы обмера → план работ → заявка
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var METHODS = [
    { id: 'scan3d', icon: '🛰', title: '3D-сканирование / КИМ', desc: 'Точная цифровая копия геометрии', cost: 18000, days: 2, base: true },
    { id: 'measure', icon: '📏', title: 'Ручной обмер', desc: 'Штангенциркуль, микрометр, нутромер', cost: 4000, days: 1, base: true },
    { id: 'profile', icon: '🌊', title: 'Профилометрия', desc: 'Шероховатость и микрорельеф', cost: 5000, days: 1 },
    { id: 'defect', icon: '🩻', title: 'Дефектоскопия', desc: 'Рентген / УЗК: внутренние дефекты', cost: 9000, days: 2 },
    { id: 'cad', icon: '💻', title: 'CAD-моделирование', desc: 'Построение 3D-модели и чертежей', cost: 22000, days: 3, base: true }
  ];

  var draft = { samples: [], name: '', mat: '', methods: ['scan3d', 'measure', 'cad'] };
  var plan = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Образец ---------- */
  $('#sampleZone').addEventListener('click', function () {
    draft.samples.push('sample_' + Math.floor(100 + Math.random() * 900) + (Math.random() > .5 ? '.jpg' : '.stl'));
    renderSamples();
  });
  function renderSamples() {
    $('#sampleList').innerHTML = draft.samples.map(function (s, i) {
      return '<div class="row between" style="background:var(--surface);border:1px solid var(--border);border-radius:var(--r-sm);padding:8px 12px;margin-bottom:6px;"><span>📦 ' + s + '</span><button class="btn btn-ghost btn-sm" data-rm="' + i + '">Убрать</button></div>';
    }).join('');
    $$('#sampleList [data-rm]').forEach(function (b) { b.addEventListener('click', function () { draft.samples.splice(parseInt(b.dataset.rm, 10), 1); renderSamples(); }); });
  }
  $('#partName').addEventListener('input', function () { draft.name = this.value; });
  $('#partMat').addEventListener('input', function () { draft.mat = this.value; });

  /* ---------- Методы ---------- */
  renderMethods();
  function renderMethods() {
    $('#methods').innerHTML = METHODS.map(function (m) {
      var sel = draft.methods.indexOf(m.id) >= 0;
      return '<div class="method' + (sel ? ' selected' : '') + '" data-id="' + m.id + '"><div class="m-check">' + (sel ? '✓' : '') + '</div><div class="grow"><div class="opt-title">' + m.icon + ' ' + m.title + '</div><div class="opt-desc">' + m.desc + ' · от ' + money(m.cost) + '</div></div></div>';
    }).join('');
  }
  $('#methods').addEventListener('click', function (e) {
    var el = e.target.closest('.method'); if (!el) return;
    var id = el.dataset.id; var i = draft.methods.indexOf(id);
    if (i >= 0) draft.methods.splice(i, 1); else draft.methods.push(id);
    renderMethods();
  });

  /* ---------- План ---------- */
  function buildPlan() {
    // если выбран CAD или 3D-скан — добавляем моделирование/верификацию
    var steps = [
      { n: 1, t: 'Приём и визуальный осмотр образца', d: '1 день', c: 0 },
      { n: 2, t: 'Обмер и оцифровка геометрии', d: '1–3 дня', c: 0 },
      { n: 3, t: 'Построение CAD-модели и чертежей', d: '2–4 дня', c: 0 },
      { n: 4, t: 'Согласование модели с заказчиком', d: '1 день', c: 0 },
      { n: 5, t: 'Изготовление и контроль образца', d: '3–7 дней', c: 0 }
    ];
    var cost = 0, days = 0;
    draft.methods.forEach(function (id) {
      var m = METHODS.find(function (x) { return x.id === id; });
      if (m) { cost += m.cost; days += m.days; }
    });
    if (!draft.methods.length) { cost = 6000; days = 2; }
    plan = { steps: steps, cost: cost, days: Math.max(days, 4) };
    return plan;
  }

  function renderPlan() {
    if (!plan) buildPlan();
    $('#planCard').innerHTML = plan.steps.map(function (s) {
      return '<div class="step-plan"><div class="n">' + s.n + '</div><div class="grow"><div style="font-weight:600;font-size:.84rem;">' + s.t + '</div><div class="faint" style="font-size:.7rem;">' + s.d + '</div></div></div>';
    }).join('');
    var chosen = draft.methods.map(function (id) { return METHODS.find(function (x) { return x.id === id; }); }).filter(Boolean);
    $('#costCard').innerHTML = chosen.map(function (m) {
      return '<div class="row between" style="padding:6px 0;font-size:.8rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + m.icon + ' ' + m.title + '</span><b>' + money(m.cost) + '</b></div>';
    }).join('') +
      '<div class="row between mt-8"><span class="muted">Общий срок</span><b>' + plan.days + ' раб. дней</b></div>' +
      '<div class="row between mt-8" style="padding-top:10px;border-top:1px solid var(--border-2);"><b>Стоимость работ</b><b style="color:var(--accent-700);">от ' + money(plan.cost) + '</b></div>';
  }

  $('#toS3').addEventListener('click', function () {
    if (!draft.methods.length) { App.toast('Выберите хотя бы один метод'); return; }
    buildPlan(); renderPlan(); screens.go('s3');
  });

  /* ---------- Отправка ---------- */
  $('#submitBtn').addEventListener('click', function () {
    var ticket = App.randomTicket('REV');
    App.Store.set('reverseRequests', (App.Store.get('reverseRequests', [])).concat([{ ticket: ticket, name: draft.name, cost: plan.cost, created: App.today() }]));
    if (window.AppData) AppData.requests.add({ source: 'A6', title: 'Реверс: ' + (draft.name || 'по образцу'), amount: plan.cost, ref: ticket });
    $('#ticketNum').textContent = ticket;
    $('#resCard').innerHTML =
      '<div class="row between"><span class="muted">Деталь</span><b>' + (draft.name || 'по образцу') + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Методов обмера</span><b>' + draft.methods.length + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Срок</span><b>' + plan.days + ' раб. дней</b></div>' +
      '<div class="row between mt-8"><span class="muted">Стоимость</span><b style="color:var(--accent-700);">от ' + money(plan.cost) + '</b></div>';
    screens.go('s4');
    App.toast('Заявка ' + ticket + ' создана');
  });

  /* ---------- Навигация ---------- */
  $('#toS2').addEventListener('click', function () { screens.go('s2'); });
  $('#editBtn').addEventListener('click', function () { screens.go('s2'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#newBtn').addEventListener('click', function () { location.reload(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
