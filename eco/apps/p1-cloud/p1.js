/* ============================================================
   P1 · 3DMP Cloud — SaaS-платформа экосистемы
   лендинг → консоль платформы → кабинет тенанта → биллинг
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var MODULES = [
    { id: 'A1', icon: '🧮', name: 'Калькулятор заказа', price: 3900 },
    { id: 'A2', icon: '🧭', name: 'Мастер подбора', price: 2900 },
    { id: 'A3', icon: '🖥', name: 'Кабинет заказчика', price: 5900 },
    { id: 'A4', icon: '🛠', name: 'Заявка на сервис', price: 3900 },
    { id: 'A5', icon: '📊', name: 'Аудит зрелости', price: 2900 },
    { id: 'A6', icon: '🔍', name: 'Реверс-инжиниринг', price: 4900 },
    { id: 'A7', icon: '📦', name: 'Портал закупок', price: 5900 },
    { id: 'B1', icon: '📋', name: 'Канбан-доска', price: 6900 },
    { id: 'B2', icon: '📐', name: 'Библиотека техпроцессов', price: 4900 },
    { id: 'B3', icon: '📱', name: 'Мобильный ОТК', price: 5900 },
    { id: 'B4', icon: '📚', name: 'База знаний', price: 3900 },
    { id: 'B5', icon: '💼', name: 'Вакансии и онбординг', price: 2900 },
    { id: 'C1', icon: '🚚', name: 'Портал поставщика', price: 5900 },
    { id: 'C2', icon: '🤝', name: 'Партнёрский кабинет', price: 4900 },
    { id: 'A8', icon: '🛠', name: 'Конфигуратор спец-технологий', price: 4900 },
    { id: 'A9', icon: '📐', name: 'Заказ документации', price: 4900 },
    { id: 'B6', icon: '🧾', name: 'Цифровой паспорт изделия', price: 6900 },
    { id: 'B7', icon: '♻️', name: 'Бережливое производство', price: 3900 },
    { id: 'C3', icon: '🏆', name: 'Клуб поставщиков', price: 4900 },
    { id: 'A10', icon: '📏', name: 'Измерения как услуга', price: 4900 },
    { id: 'A11', icon: '🏗', name: 'Поставки оборудования', price: 5900 },
    { id: 'B8', icon: '⏱', name: 'Нормирование операций', price: 6900 },
    { id: 'B9', icon: '📋', name: 'Спецификации и BOM', price: 5900 },
    { id: 'B10', icon: '🗓', name: 'Планирование и Гант', price: 7900 },
    { id: 'B11', icon: '🧾', name: 'Наряды', price: 4900 },
    { id: 'B12', icon: '🎯', name: 'CRM и воронка', price: 7900 },
    { id: 'B13', icon: '🧰', name: 'Инструмент и NC-программы', price: 5900 },
    { id: 'B14', icon: '📦', name: 'Склад материалов и закупки', price: 5900 },
    { id: 'B15', icon: '🔧', name: 'ТОиР и простои', price: 4900 },
    { id: 'A12', icon: '🖥', name: 'Автоматизированные рабочие места', price: 5900 },
    { id: 'B16', icon: '📨', name: 'Диспетчер обращений', price: 3900 },
    { id: 'B17', icon: '📟', name: 'Монитор станков (OEE)', price: 8900 },
    { id: 'B18', icon: '💻', name: 'УП и постпроцессоры (DNC)', price: 8900 },
    { id: 'B19', icon: '🧷', name: 'Инструмент и стойкость', price: 6900 },
    { id: 'B20', icon: '🧲', name: 'Наладка и оснастка', price: 5900 },
    { id: 'B21', icon: '📈', name: 'Режимы резания', price: 4900 },
    { id: 'B22', icon: '📱', name: 'Мобильный пульт оператора', price: 4900 },
    { id: 'A13', icon: '🏭', name: 'Отраслевые решения', price: 3900 },
    { id: 'B23', icon: '📈', name: 'Дашборд руководителя', price: 7900 },
    { id: 'B24', icon: '🚨', name: 'Эскалация и проблемы', price: 5900 },
    { id: 'B25', icon: '📏', name: 'Допуски и посадки', price: 4900 },
    { id: 'B26', icon: '📈', name: 'Режимы резания PRO', price: 5900 },
    { id: 'B27', icon: '📜', name: 'База УП и G-код', price: 6900 },
    { id: 'B28', icon: '💰', name: 'Стоимость нормочаса ЧПУ', price: 6900 },
    { id: 'B29', icon: '🧰', name: 'Рабочее место сервисного инженера', price: 5900 },
    { id: 'B30', icon: '📐', name: 'КД и изменения', price: 7900 },
    { id: 'B31', icon: '📊', name: 'Экономика заказа', price: 7900 },
    { id: 'B32', icon: '🏷', name: 'Маркировка (децимальные номера, QR)', price: 4900 },
    { id: 'B33', icon: '📄', name: 'Конструктор документов', price: 5900 },
    { id: 'B34', icon: '📦', name: 'Калькулятор металлопроката', price: 3900 },
    { id: 'B35', icon: '📚', name: 'Справочники', price: 3900 },
    { id: 'B36', icon: '🛡', name: 'ИТ-инфраструктура предприятия', price: 4900 },
    { id: 'B37', icon: '👔', name: 'Кадры: личные дела', price: 4900 },
    { id: 'B38', icon: '📅', name: 'Производственный календарь', price: 2900 },
    { id: 'B39', icon: '📉', name: 'Прогноз загрузки', price: 5900 },
    { id: 'A14', icon: '👥', name: 'CRM клиента и доступы', price: 4900 }
  ];

  var PLANS = [
    { id: 'start', name: 'Старт', base: 9900, hot: false, features: ['До 5 модулей', '1 завод', 'Базовая поддержка', 'Обновления'] },
    { id: 'business', name: 'Бизнес', base: 19900, hot: true, features: ['До 10 модулей', 'White-label', 'Роли и права', 'Поддержка 8×5'] },
    { id: 'corp', name: 'Корпоративный', base: 39900, hot: false, features: ['Все 56 модулей', 'Неогр. пользователи', 'SLA 99,9%', 'Персональный менеджер'] }
  ];

  var TENANTS = [
    { name: 'ООО «Пресс-Технологии»', plan: 'Бизнес', status: 'active', modules: 10, mrr: 48900 },
    { name: 'АО «Урал-Штамп»', plan: 'Корпоративный', status: 'active', modules: 14, mrr: 91500 },
    { name: 'ООО «Точмаш-Сервис»', plan: 'Бизнес', status: 'active', modules: 8, mrr: 42100 },
    { name: 'ИП Ковалёв А.В.', plan: 'Старт', status: 'trial', modules: 4, mrr: 0 },
    { name: 'ООО «ЛазерПро-Юг»', plan: 'Старт', status: 'active', modules: 5, mrr: 25400 },
    { name: 'ООО «Металлист-2»', plan: 'Бизнес', status: 'risk', modules: 9, mrr: 44600 },
    { name: 'ЗАО «Термообработка+»', plan: 'Бизнес', status: 'active', modules: 7, mrr: 38900 },
    { name: 'ООО «Гальваник»', plan: 'Старт', status: 'trial', modules: 3, mrr: 0 }
  ];

  var tenantPlan = PLANS[1];
  var selected = MODULES.map(function (m) { return m.id; });
  var tFilter = 'all';

  var screens = AppRouter.create({
    onShow: function (s) {
      $$('#nav button').forEach(function (b) { b.classList.toggle('active', b.dataset.s === s.id); });
      window.scrollTo(0, 0);
    },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#nav').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    screens.go(b.dataset.s);
  });
  $('#tryBtn').addEventListener('click', function () { screens.go('s-console'); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  /* ---------- Лендинг ---------- */
  var GROUPED = [
    { t: '👥 Для клиентов', items: ['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9', 'A10', 'A11', 'A12', 'A13', 'A14'] },
    { t: '🏭 Для сотрудников', items: ['B1', 'B2', 'B3', 'B4', 'B5', 'B6', 'B7', 'B8', 'B9', 'B10', 'B11', 'B12', 'B13', 'B14', 'B15', 'B16', 'B17', 'B18', 'B19', 'B20', 'B21', 'B22', 'B23', 'B24', 'B25', 'B26', 'B27', 'B28', 'B29', 'B30', 'B31', 'B32', 'B33', 'B34', 'B35', 'B36', 'B37', 'B38', 'B39'] },
    { t: '🤝 Для партнёров', items: ['C1', 'C2', 'C3'] }
  ];
  $('#landingModules').innerHTML = GROUPED.map(function (g) {
    return '<div class="card"><h4 class="mb-8">' + g.t + '</h4>' + g.items.map(function (id) {
      var m = MODULES.find(function (x) { return x.id === id; });
      return '<div class="row between" style="padding:5px 0;font-size:.8rem;"><span>' + m.icon + ' ' + m.name + '</span><b class="faint">' + money(m.price) + '/мес</b></div>';
    }).join('') + '</div>';
  }).join('');

  $('#landingPlans').innerHTML = PLANS.map(function (p) {
    return '<div class="plan' + (p.hot ? ' hot' : '') + '">' + (p.hot ? '<span class="badge accent" style="position:absolute;top:-10px;right:14px;">Популярный</span>' : '') +
      '<h4>' + p.name + '</h4><div class="price">' + money(p.base) + '<span class="faint" style="font-size:.8rem;font-weight:600;">/мес</span></div>' +
      '<ul>' + p.features.map(function (f) { return '<li>✓ ' + f + '</li>'; }).join('') + '</ul>' +
      '<button class="btn btn-' + (p.hot ? 'primary' : 'secondary') + ' mt-12" data-plan="' + p.id + '">Выбрать</button></div>';
  }).join('');
  $$('#landingPlans [data-plan]').forEach(function (b) {
    b.addEventListener('click', function () {
      tenantPlan = PLANS.find(function (p) { return p.id === b.dataset.plan; });
      applyPlan(); screens.go('s-tenant'); App.toast('Тариф «' + tenantPlan.name + '» выбран');
    });
  });

  /* ---------- Консоль ---------- */
  function renderTenants() {
    var list = TENANTS.filter(function (t) {
      if (tFilter === 'active') return t.status === 'active';
      if (tFilter === 'trial') return t.status === 'trial';
      if (tFilter === 'risk') return t.status === 'risk';
      return true;
    });
    $('#tCount').textContent = list.length + ' из ' + TENANTS.length;
    $('#tenantList').innerHTML = list.map(function (t) {
      var badge = t.status === 'active' ? 'success' : t.status === 'trial' ? 'info' : 'danger';
      var label = t.status === 'active' ? 'Активен' : t.status === 'trial' ? 'Пробный' : 'Риск оттока';
      return '<div class="trow"><div class="tlogo">' + t.name.replace(/[^A-Za-zА-Яа-я]/g, '').slice(0, 2).toUpperCase() + '</div>' +
        '<div class="grow"><div style="font-weight:700;font-size:.86rem;">' + t.name + '</div><div class="faint" style="font-size:.7rem;">' + t.plan + ' · ' + t.modules + ' модулей</div></div>' +
        '<div class="text-center" style="min-width:90px;"><b style="font-size:.84rem;">' + (t.mrr ? money(t.mrr) : '—') + '</b><div class="faint" style="font-size:.66rem;">MRR</div></div>' +
        '<span class="badge ' + badge + '">' + label + '</span></div>';
    }).join('');
  }
  $('#tFilters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    tFilter = c.dataset.f; renderTenants();
  });

  /* ---------- Кабинет тенанта ---------- */
  function renderModules() {
    $('#moduleGrid').innerHTML = MODULES.map(function (m) {
      var on = selected.indexOf(m.id) >= 0;
      return '<div class="mod' + (on ? ' on' : '') + '" data-id="' + m.id + '"><span class="tick">' + (on ? '✓' : '') + '</span>' + m.icon + ' ' + m.name + '</div>';
    }).join('');
    $('#modCount').textContent = selected.length + ' из ' + MODULES.length;
  }
  $('#moduleGrid').addEventListener('click', function (e) {
    var el = e.target.closest('.mod'); if (!el) return;
    var id = el.dataset.id, i = selected.indexOf(id);
    if (i >= 0) selected.splice(i, 1); else selected.push(id);
    renderModules(); recalcBill();
  });

  function applyPlan() {
    $('#tenantPlan').textContent = tenantPlan.name;
    if (tenantPlan.id === 'start') selected = selected.slice(0, 5);
    if (tenantPlan.id === 'business') selected = MODULES.slice(0, 10).map(function (m) { return m.id; });
    if (tenantPlan.id === 'corp') selected = MODULES.map(function (m) { return m.id; });
    renderModules(); recalcBill();
  }
  $('#saveTenant').addEventListener('click', function () { App.toast('Конфигурация завода сохранена'); });

  /* ---------- Биллинг ---------- */
  function billTotal() {
    var mods = selected.reduce(function (s, id) {
      var m = MODULES.find(function (x) { return x.id === id; });
      return s + (m ? m.price : 0);
    }, 0);
    return tenantPlan.base + mods;
  }
  function recalcBill() {
    var total = billTotal();
    $('#billTotal').textContent = money(total);
    $('#billHint').textContent = 'Тариф «' + tenantPlan.name + '» ' + money(tenantPlan.base) + ' + ' + selected.length + ' модулей';
  }
  function renderInvoices() {
    var total = billTotal();
    var months = ['Сентябрь 2025', 'Август 2025', 'Июль 2025'];
    $('#invoiceList').innerHTML = months.map(function (m, i) {
      var paid = i > 0;
      return '<div class="row between" style="padding:10px 0;border-bottom:1px solid var(--border-2);"><div><div style="font-weight:600;font-size:.84rem;">' + m + '</div><div class="faint" style="font-size:.7rem;">Подписка 3DMP Cloud</div></div>' +
        '<div class="text-center"><b>' + money(total) + '</b></div><span class="badge ' + (paid ? 'success' : 'warning') + '">' + (paid ? 'Оплачен' : 'К оплате') + '</span></div>';
    }).join('');
  }
  $('#payBtn').addEventListener('click', function () { App.toast('Демо: оплата счёта прошла'); });

  /* ---------- Init ---------- */
  renderTenants();
  renderModules();
  applyPlan();
  renderInvoices();
})();
