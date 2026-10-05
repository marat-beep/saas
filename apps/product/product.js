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
    var back = document.createElement('div');
    back.className = 'modal-backdrop';
    back.innerHTML =
      '<div class="modal" role="dialog" aria-modal="true">' +
        '<div class="modal-head">Запросить демо' + (plan ? ' · ' + esc(plan) : '') + '</div>' +
        '<div class="modal-body">' +
          '<div class="field"><label>Организация</label><input type="text" id="dOrg" placeholder="ООО «Мой завод»"></div>' +
          '<div class="field"><label>Контактное лицо</label><input type="text" id="dName" placeholder="Иванов И.И."></div>' +
          '<div class="grid2c">' +
            '<div class="field"><label>Телефон</label><input type="text" id="dPhone" placeholder="+7 …"></div>' +
            '<div class="field"><label>E-mail</label><input type="text" id="dEmail" placeholder="mail@…"></div>' +
          '</div>' +
          '<div class="field"><label>Комментарий</label><input type="text" id="dNote" placeholder="что интересует"></div>' +
          '<div class="msg" id="dMsg"></div>' +
        '</div>' +
        '<div class="modal-foot">' +
          '<button class="btn secondary" data-cancel>Отмена</button>' +
          '<button class="btn" data-send>Отправить</button>' +
        '</div>' +
      '</div>';
    document.body.appendChild(back);
    requestAnimationFrame(function () { back.classList.add('show'); });
    function close() { back.classList.remove('show'); setTimeout(function () { back.remove(); }, 160); }
    back.addEventListener('click', function (e) {
      if (e.target === back || e.target.closest('[data-cancel]')) { close(); return; }
      if (e.target.closest('[data-send]')) {
        var org = back.querySelector('#dOrg').value.trim();
        var nm = back.querySelector('#dName').value.trim();
        var msg = back.querySelector('#dMsg');
        if (!org || !nm) { msg.className = 'msg show err'; msg.textContent = 'Укажите организацию и контактное лицо.'; return; }
        // В след. волнах: запись в app_orders (source='product'). Сейчас — подтверждение.
        msg.className = 'msg show ok'; msg.textContent = 'Спасибо! Заявка принята — мы свяжемся с вами.';
        setTimeout(function () { close(); ui.toast('Заявка на демо отправлена', 'ok'); }, 900);
      }
    });
  }

  $('#demoBtn').addEventListener('click', function () { openDemo(''); });
  renderContours();
  renderPlans();
})();
