/* ============================================================
   B12 · CRM и воронка
   воронка → сделка → продвижение / КП
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var STAGES = [
    { id: 'lead', name: 'Лид', color: '#94a3b8' },
    { id: 'qualified', name: 'Квалификация', color: '#60a5fa' },
    { id: 'quote', name: 'КП', color: '#818cf8' },
    { id: 'negotiation', name: 'Переговоры', color: '#a78bfa' },
    { id: 'contract', name: 'Договор', color: '#c084fc' },
    { id: 'won', name: 'Выиграна', color: '#22c55e' },
    { id: 'lost', name: 'Проиграна', color: '#ef4444' }
  ];

  var DEALS = [
    { id: 'DL-301', client: 'ООО «Привод»', title: 'Корпус редуктора, 12 шт', stage: 'contract', amount: 486000, prob: 85, manager: 'И. Морозов', date: '28.09' },
    { id: 'DL-302', client: 'ЗАО «ТехноПарк»', title: 'Штамп вырубной', stage: 'negotiation', amount: 312000, prob: 65, manager: 'И. Морозов', date: '25.09' },
    { id: 'DL-303', client: 'ООО «АвтоПласт»', title: 'Пресс-форма втулки', stage: 'quote', amount: 540000, prob: 50, manager: 'О. Белова', date: '24.09' },
    { id: 'DL-304', client: 'ИП Смирнов', title: 'Вал-шестерня, 30 шт', stage: 'qualified', amount: 132000, prob: 35, manager: 'О. Белова', date: '22.09' },
    { id: 'DL-305', client: 'ООО «ЛазерПро»', title: 'Оснастка для лазера', stage: 'lead', amount: 96000, prob: 20, manager: 'И. Морозов', date: '20.09' },
    { id: 'DL-306', client: 'ООО «Металлист»', title: 'Электроды ЭЭО', stage: 'won', amount: 88000, prob: 100, manager: 'О. Белова', date: '15.09' },
    { id: 'DL-307', client: 'ООО «Точмаш»', title: 'Плита прижимная', stage: 'lost', amount: 74000, prob: 0, manager: 'И. Морозов', date: '10.09' }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderDashboard() {
    var active = DEALS.filter(function (d) { return d.stage !== 'won' && d.stage !== 'lost'; });
    var pipeline = active.reduce(function (a, d) { return a + d.amount * d.prob / 100; }, 0);
    var won = DEALS.filter(function (d) { return d.stage === 'won'; }).reduce(function (a, d) { return a + d.amount; }, 0);
    var avg = DEALS.length ? Math.round(DEALS.reduce(function (a, d) { return a + d.amount; }, 0) / DEALS.length) : 0;
    $('#cPipeline').textContent = App.number(pipeline / 1000) + ' тыс.';
    $('#cWon').textContent = App.number(won / 1000) + ' тыс.';
    $('#cAvg').textContent = App.number(avg / 1000) + ' тыс.';

    var maxSum = Math.max.apply(null, STAGES.map(function (s) { return DEALS.filter(function (d) { return d.stage === s.id; }).reduce(function (a, d) { return a + d.amount; }, 0); }).concat([1]));
    $('#funnel').innerHTML = STAGES.map(function (s) {
      var list = DEALS.filter(function (d) { return d.stage === s.id; });
      var sum = list.reduce(function (a, d) { return a + d.amount; }, 0);
      return '<div class="funnel-stage" data-stage="' + s.id + '"><div class="fl"><span><b>' + s.name + '</b> <span class="faint">(' + list.length + ')</span></span><span>' + money(sum) + '</span></div><div class="track"><i style="width:' + Math.round(sum / maxSum * 100) + '%;background:' + s.color + ';"></i></div></div>';
    }).join('');
    $$('#funnel .funnel-stage').forEach(function (el) {
      el.addEventListener('click', function () { filter = el.dataset.stage; renderList(); App.toast('Фильтр: ' + STAGES.find(function (s) { return s.id === el.dataset.stage; }).name); });
    });
    renderList();
  }

  var filter = null;
  function renderList() {
    var list = DEALS.filter(function (d) { return !filter || d.stage === filter; });
    $('#dealCount').textContent = list.length + ' сделок';
    $('#dealList').innerHTML = list.map(function (d, i) {
      var s = STAGES.find(function (x) { return x.id === d.stage; });
      return '<div class="card clickable deal" data-id="' + d.id + '"><div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + d.id + ' · ' + d.date + '</span><span class="badge" style="background:' + s.color + '22;color:' + s.color + ';">' + s.name + '</span></div><h3 class="mt-8" style="font-size:.88rem;">' + d.title + '</h3><div class="meta-row"><span>🏭 ' + d.client + ' · 👤 ' + d.manager + '</span><b>' + money(d.amount) + '</b></div></div>';
    }).join('');
    $$('#dealList .deal').forEach(function (c) { c.addEventListener('click', function () { openDeal(c.dataset.id); }); });
  }

  function openDeal(id) {
    current = DEALS.find(function (d) { return d.id === id; });
    renderDeal();
    screens.go('s2');
  }
  function renderDeal() {
    var d = current, s = STAGES.find(function (x) { return x.id === d.stage; });
    $('#dClient').textContent = d.client + ' · ' + d.id;
    var b = $('#dStage'); b.textContent = s.name; b.className = 'badge'; b.style.background = s.color + '22'; b.style.color = s.color;
    $('#dTitle').textContent = d.title;
    $('#dTags').innerHTML = '<span class="tag">👤 ' + d.manager + '</span><span class="tag">📅 ' + d.date + '</span>';
    $('#dInfo').innerHTML =
      irow('Сумма', money(d.amount)) + irow('Вероятность', d.prob + '%') + irow('Взвешенная сумма', money(d.amount * d.prob / 100)) + irow('Стадия', s.name);
    $('#nextBtn').disabled = d.stage === 'won' || d.stage === 'lost';
    $('#kpBtn').disabled = d.stage === 'lead';
  }
  function irow(k, v) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }

  $('#nextBtn').addEventListener('click', function () {
    var idx = STAGES.findIndex(function (x) { return x.id === current.stage; });
    if (idx >= 0 && idx < STAGES.length - 2) { current.stage = STAGES[idx + 1].id; current.prob = Math.min(100, current.prob + 15); }
    renderDeal(); renderDashboard();
    showSuccess('Стадия обновлена', 'Сделка переведена: ' + STAGES.find(function (x) { return x.id === current.stage; }).name + '.', current.id);
  });
  $('#kpBtn').addEventListener('click', function () {
    if (current.stage === 'lead' || current.stage === 'qualified') current.stage = 'quote';
    renderDeal(); renderDashboard();
    var kp = 'КП-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    // сквозной сценарий: КП создаёт связанный счёт для P7 «Финансы»
    var inv = App.Store.get('linkedInvoices', []);
    inv.unshift({ id: 'СЧ-' + kp.replace(/\D/g, ''), client: current.client, contract: kp, amount: current.amount, paid: 0, due: App.addDays(14), status: 'partial', source: 'B12' });
    App.Store.set('linkedInvoices', inv.slice(0, 20));
    showSuccess('КП сформировано', 'Коммерческое предложение отправлено клиенту. Счёт создан в финансах (P7).', kp);
    App.toast('КП ' + kp + ' создано, счёт добавлен в P7');
  });
  function showSuccess(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); }

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderDashboard(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderDashboard();
})();
