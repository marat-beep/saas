/* ============================================================
   3DMP Service · apps/product — витрина «продукт и цены» (гость)
   Контуры/модули — из catalog.js; тарифы — статично; CTA «Запросить демо».
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, C = window.AppCatalog;
  function esc(v) { return ui.esc(v); }

  var PLANS = [
    { name: 'Старт', price: 19900, hot: false, feats: ['До 10 пользователей', 'Заявки, документы, финансы', 'Справочники и маршруты', 'Склад и BOM', 'Поддержка по почте'] },
    { name: 'Бизнес', price: 39900, hot: true, feats: ['До 50 пользователей', 'Всё из «Старт»', 'Производство: наряды, MES, планирование', 'Качество: ОТК, паспорт, СМК', 'Экономика, BI, отчёты', 'Роли и матрица прав'] },
    { name: 'Корпоративный', price: 79900, hot: false, feats: ['Пользователи без ограничений', 'Всё из «Бизнес»', 'Файлы и вложения', 'White-label, бренд', 'API и вебхуки', 'Приоритетная поддержка'] },
    { name: 'Enterprise', price: null, hot: false, feats: ['Интеграции 1С/ERP/IIoT/DNC', 'Мультизавод', 'Индивидуальные модули', 'SLA и выделенная поддержка', 'Обучение и внедрение'] }
  ];

  function renderContours() {
    if (!C || !C.groups) return;
    $('#contours').innerHTML = C.groups.map(function (g) {
      var items = C.apps.filter(function (a) { return a.group === g.id; });
      if (!items.length) return '';
      return '<div class="grp-t">' + g.icon + ' ' + esc(g.title) + '</div>' +
        '<div class="feat">' + items.map(function (a) {
          return '<div class="f"><b>' + a.icon + ' ' + esc(a.title) + '</b><span>' + esc(a.desc) + '</span></div>';
        }).join('') + '</div>';
    }).join('');
  }

  function renderPlans() {
    $('#plans').innerHTML = PLANS.map(function (p) {
      return '<div class="plan' + (p.hot ? ' hot' : '') + '">' +
        '<div class="name">' + esc(p.name) + (p.hot ? ' <span class="tag-hot">популярный</span>' : '') + '</div>' +
        '<div class="price">' + (p.price ? p.price.toLocaleString('ru-RU') + ' ₽' : 'по запросу') + (p.price ? ' <small>/ мес</small>' : '') + '</div>' +
        '<ul>' + p.feats.map(function (f) { return '<li>' + esc(f) + '</li>'; }).join('') + '</ul>' +
        '<button class="btn' + (p.hot ? '' : ' secondary') + '" data-plan="' + esc(p.name) + '">Выбрать</button>' +
      '</div>';
    }).join('');
    ui.qsa('#plans [data-plan]').forEach(function (b) { b.addEventListener('click', function () { openDemo(b.dataset.plan); }); });
  }

  function openDemo(plan) {
    // Модальная форма — общий компонент дизайн-системы AppUI.formDialog
    ui.formDialog({
      title: 'Запросить демо' + (plan ? ' · ' + plan : ''),
      okText: 'Отправить',
      fields: [
        { name: 'org', label: 'Организация', required: true, placeholder: 'ООО «Мой завод»' },
        { name: 'name', label: 'Контактное лицо', required: true, placeholder: 'Иванов И.И.' },
        { name: 'phone', label: 'Телефон', placeholder: '+7 …' },
        { name: 'email', label: 'E-mail', type: 'email', placeholder: 'mail@…' },
        { name: 'note', label: 'Комментарий', placeholder: 'что интересует' }
      ]
    }).then(function (v) {
      if (!v) return;
      // В след. волнах: запись заявки в app_orders (source='product'). Сейчас — подтверждение.
      ui.toast('Заявка на демо отправлена', 'ok');
    });
  }

  $('#demoBtn').addEventListener('click', function () { openDemo(''); });
  renderContours();
  renderPlans();
})();
