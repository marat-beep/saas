/* ============================================================
   A3 · Кабинет заказчика
   вход → дашборд заказов → статус-трекер, документы, трекинг
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var STAGES = ['Заявка', 'Расчёт', 'Договор', 'Производство', 'ОТК', 'Доставка', 'Завершён'];

  var orders = [
    { number: '3DMP-2025-0150', title: 'Плита прижимная, 8 шт', stage: 2, amount: 74000, date: '15.09.2025', due: '25.10.2025', tracking: '—', docs: ['КП', 'Договор №150', 'Счёт на оплату'] },
    { number: '3DMP-2025-0147', title: 'Кронштейн датчика, 60 шт', stage: 1, amount: 42000, date: '10.09.2025', due: '22.10.2025', tracking: '—', docs: ['Заявка', 'Чертёж', 'КП'] },
    { number: '3DMP-2025-0145', title: 'Комплект фрезерной оснастки', stage: 0, amount: 118000, date: '08.09.2025', due: '30.10.2025', tracking: '—', docs: ['Заявка'] },
    { number: '3DMP-2025-0142', title: 'Пресс-форма для втулки', stage: 3, amount: 486000, date: '02.09.2025', due: '18.10.2025', tracking: '—', docs: ['Договор №142', 'Спецификация', 'Счёт на оплату'] },
    { number: '3DMP-2025-0141', title: 'Штамп гибочный двухпозиционный', stage: 4, amount: 312000, date: '28.08.2025', due: '12.10.2025', tracking: '—', docs: ['Договор №141', 'Протокол ОТК', 'Счёт'] },
    { number: '3DMP-2025-0138', title: 'Штамп вырубной, серия 50', stage: 5, amount: 214500, date: '21.08.2025', due: '30.09.2025', tracking: 'СДЭК 1098432711', docs: ['Договор №138', 'Акт ОТК', 'УПД', 'Накладная'] },
    { number: '3DMP-2025-0135', title: 'Электроды для ЭЭО, 24 шт', stage: 6, amount: 88000, date: '12.08.2025', due: '05.09.2025', tracking: 'СДЭК 1097990122', docs: ['Договор №135', 'Акт выполненных работ', 'УПД'] },
    { number: '3DMP-2025-0129', title: 'Оснастка для ЧПУ', stage: 6, amount: 96000, date: '05.08.2025', due: '28.08.2025', tracking: 'СДЭК 1097118220', docs: ['Договор №129', 'Акт выполненных работ', 'УПД'] },
    { number: '3DMP-2025-0124', title: 'Корпус редуктора, 12 шт', stage: 6, amount: 158000, date: '19.07.2025', due: '20.08.2025', tracking: 'СДЭК 1096440277', docs: ['Договор №124', 'Протокол ОТК', 'УПД'] },
    { number: '3DMP-2025-0119', title: 'Вал-шестерня, 30 шт', stage: 6, amount: 132000, date: '11.07.2025', due: '05.08.2025', tracking: 'СДЭК 1095772144', docs: ['Договор №119', 'Акт выполненных работ', 'УПД'] }
  ];

  // Заказы, оформленные через A1/др. приложения
  var stored = App.Store.get('orders', []);
  stored.forEach(function (o, i) {
    if (!orders.some(function (x) { return x.number === o.number; })) {
      orders.unshift({ number: o.number, title: o.title, stage: 1, amount: o.amount || 0, date: o.date, due: App.addDays(14), tracking: '—', docs: ['Заявка', 'Чертёж'] });
    }
  });

  var filter = 'all';
  var current = null;

  var screens = AppRouter.create({
    onShow: function (s) {
      $('#backBtn').hidden = (s.id === 's-login' || s.id === 's-dashboard');
      $('#logoutBtn').hidden = (s.id === 's-login');
      $('#content').scrollTop = 0;
    },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Вход ---------- */
  function checkLogin() {
    var u = $('#loginUser').value.trim(), p = $('#loginPass').value.trim();
    $('#loginBtn').disabled = !(u && p);
  }
  $('#loginUser').addEventListener('input', checkLogin);
  $('#loginPass').addEventListener('input', checkLogin);
  $('#loginBtn').addEventListener('click', function () {
    var u = $('#loginUser').value.trim();
    var company = u.indexOf('@') > 0 ? u.split('@')[1] : u;
    if (window.AppData) AppData.profile.set({ company: company, login: u, ts: Date.now() });
    $('#companyName').textContent = company;
    renderDashboard();
    screens.go('s-dashboard');
    App.toast('Добро пожаловать!');
  });
  $('#logoutBtn').addEventListener('click', function () { screens.replace('s-login'); });

  /* ---------- Дашборд ---------- */
  function renderDashboard() {
    var active = orders.filter(function (o) { return o.stage < 6; }).length;
    var done = orders.filter(function (o) { return o.stage === 6; }).length;
    var total = orders.reduce(function (s, o) { return s + o.amount; }, 0);
    $('#stActive').textContent = active;
    $('#stDone').textContent = done;
    $('#stMoney').textContent = money(total).replace(' ₽', '');
    renderRequests();
    renderList();
  }

  function renderRequests() {
    if (!window.AppData) { $('#reqCount').textContent = '0'; $('#reqList').innerHTML = ''; return; }
    var reqs = AppData.requests.all();
    $('#reqCount').textContent = reqs.length + ' шт';
    if (!reqs.length) {
      $('#reqList').innerHTML = '<div class="callout info"><span class="ci">📝</span><div>Заявок нет. Оформите расчёт в приложениях 3DMP (A1, A2, A8…) — заявка появится здесь.</div></div>';
      return;
    }
    $('#reqList').innerHTML = reqs.slice(0, 6).map(function (r) {
      return '<div class="card accent-left mb-8" data-req="' + r.id + '"><div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + r.id + ' · ' + AppData.sourceTitle(r.source) + '</span><span class="badge ' + (r.status === 'Новая' ? 'warning' : 'info') + '">' + r.status + '</span></div><h3 class="mt-8" style="font-size:.88rem;">' + r.title + '</h3><div class="meta-row"><span>📅 ' + r.created + ' · ' + (r.customer || '') + '</span><b>' + (r.amount ? money(r.amount) : '—') + '</b></div></div>';
    }).join('');
  }

  function renderList() {
    var list = orders.filter(function (o) {
      if (filter === 'work') return o.stage < 6;
      if (filter === 'done') return o.stage === 6;
      return true;
    });
    $('#ordersCount').textContent = list.length + ' шт';
    if (!list.length) { $('#ordersList').innerHTML = '<div class="callout info"><span class="ci">📭</span><div>Заказов в этой категории нет.</div></div>'; return; }
    $('#ordersList').innerHTML = list.map(function (o, i) {
      var done = o.stage === 6;
      return '<div class="card clickable accent-left' + (done ? '' : '') + '" data-i="' + orders.indexOf(o) + '">' +
        '<div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + o.number + '</span>' +
        '<span class="badge ' + (done ? 'neutral' : 'accent') + '">' + (done ? 'Выполнен' : STAGES[o.stage]) + '</span></div>' +
        '<h3 class="mt-8">' + o.title + '</h3>' +
        '<div class="meta-row"><span>📅 ' + o.date + '</span><b>' + money(o.amount) + '</b></div></div>';
    }).join('');
    $$('#ordersList .card').forEach(function (c) {
      c.addEventListener('click', function () { openOrder(parseInt(c.dataset.i, 10)); });
    });
  }

  $('#filterChips').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });

  /* ---------- Детали заказа ---------- */
  function openOrder(idx) {
    current = orders[idx];
    var done = current.stage === 6;
    $('#oNum').textContent = current.number;
    $('#oBadge').textContent = done ? 'Выполнен' : STAGES[current.stage];
    $('#oBadge').className = 'badge ' + (done ? 'neutral' : 'accent');
    $('#oTitle').textContent = current.title;
    $('#oTags').innerHTML = '<span class="tag">📅 ' + current.date + '</span><span class="tag">⏱ до ' + current.due + '</span><span class="tag">💰 ' + money(current.amount) + '</span>';

    $('#tracker').innerHTML = STAGES.map(function (name, i) {
      var cls = i < current.stage ? 'done' : i === current.stage ? 'current' : '';
      var date = i <= current.stage ? (i === 0 ? current.date : '—') : '';
      return '<div class="tr-item ' + cls + '"><div class="dot">' + (i < current.stage ? '✓' : '') + '</div>' +
        '<div class="tr-title">' + name + '</div>' + (date ? '<div class="tr-date">' + date + '</div>' : '') + '</div>';
    }).join('');

    $('#oInfo').innerHTML =
      infoRow('Номер заказа', current.number) +
      infoRow('Сумма', money(current.amount)) +
      infoRow('Срок поставки', current.due, true) +
      infoRow('Трек-номер', current.tracking) +
      infoRow('Этап', done ? 'Завершён' : STAGES[current.stage]);

    $('#oDocs').innerHTML = current.docs.map(function (d) {
      return '<div class="doc-item"><div style="width:34px;height:34px;border-radius:8px;background:var(--accent-100);display:flex;align-items:center;justify-content:center;">📄</div><div class="grow"><div style="font-weight:600;font-size:.82rem;">' + d + '</div><div class="faint" style="font-size:.68rem;">PDF · скачать</div></div><span style="color:var(--accent-600);font-weight:700;">↓</span></div>';
    }).join('');
    $$('#oDocs .doc-item').forEach(function (el) {
      el.addEventListener('click', function () { App.toast('Демо: скачивание документа'); });
    });

    screens.go('s-order');
  }

  function infoRow(k, v, accent) {
    return '<div class="row between" style="padding:8px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;' + (accent ? 'color:var(--accent-700);' : '') + '">' + v + '</b></div>';
  }

  /* ---------- Навигация ---------- */
  $('#supportBtn').addEventListener('click', function () { App.toast('Демо: чат с менеджером'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
