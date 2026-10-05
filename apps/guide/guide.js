/* ============================================================
   3DMP Service · apps/guide — гид по системе
   Строит карту модулей из assets/js/catalog.js:
   назначение, функции, связи, вход/результат, аудитория. Гостю доступно.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, C = window.AppCatalog;

  var AUD = {
    guest: 'гость', user: 'пользователь', client_admin: 'админ клиента',
    saas_admin: 'SaaS-админ', developer: 'разработчик'
  };
  function esc(v) { return ui.esc(v); }
  function byId(id) { return (C.apps || []).filter(function (a) { return a.id === id; })[0]; }

  function moduleCard(a) {
    var feats = (a.features || []).map(function (f) { return '<li>' + esc(f) + '</li>'; }).join('');
    var conn = (a.connects || []).map(function (id) {
      var t = byId(id);
      if (!t) return '<span class="chip">↔ ' + esc(id) + '</span>';
      return '<a class="chip" href="../../' + t.href + '">↔ ' + esc(t.title) + '</a>';
    }).join('');
    return '<div class="mod">' +
      '<h3>' + a.icon + ' ' + esc(a.title) +
        '<a class="chip" href="../../' + a.href + '">открыть</a>' +
        '<span class="aud" style="margin-left:auto;">' + (AUD[a.audience] || a.audience || '') + '</span></h3>' +
      '<div class="note">' + esc(a.desc) + '</div>' +
      (a.purpose ? '<div class="purp"><b>Зачем:</b> ' + esc(a.purpose) + '</div>' : '') +
      (feats ? '<ul>' + feats + '</ul>' : '') +
      (conn ? '<div class="chips">' + conn + '</div>' : '') +
      ((a.in_ || a.out) ? '<div class="io">Вход: ' + esc(a.in_ || '—') + ' · Результат: ' + esc(a.out || '—') + '</div>' : '') +
      '</div>';
  }

  // Описание контуров (для «Гида контура»)
  var CONTOURS = {
    core: 'Ядро: вход, личный кабинет, пульт управления, гид и экран модулей. Точка входа и навигация по всей экосистеме.',
    sales: 'Продажи и заказы: приём заявок (CRM), КП/договоры/акты, счета и оплаты, закупки и портал поставщика. Сквозная цепочка «заявка → КП → договор → счёт → оплата» и «потребность → закупка → склад».',
    ktpp: 'Подготовка производства (КТПП): справочники (оборудование, материалы, операции), шаблоны техпроцессов и маршруты, спецификации (BOM) и ИИ-помощник. Основа нормирования и себестоимости.',
    production: 'Производство: наряды и операции, диспетчерская (MES), планирование (Гант/загрузка), склад. Связи «заявка/маршрут → наряд → операции → склад → себестоимость».',
    quality: 'Качество: ОТК (чек-листы, дефекты), паспорт изделия (QR), СМК/метрология (поверка СИ) и трассируемость «заявка → наряд → операции → материалы → дефекты».',
    economics: 'Экономика и финансы: себестоимость по факту, маржа, счета/оплаты, аналитика (BI) и отчёты (PDF/DOC/CSV/JSON).',
    staff: 'Персонал и организация: кадры (сотрудники, смены, обучение), админ-панель клиента (пользователи, роли, модули, бренд), матрица прав.',
    platform: 'Платформа и администрирование: роли и права, организации (SaaS), пользователи, диагностика, API/интеграции.',
    refs: 'Референсы: прототипы экосистемы 3DMP — источник идей, модули строятся по стандарту.'
  };

  function render(filter) {
    var q = (filter || '').trim().toLowerCase();
    var only = new URLSearchParams(location.search).get('c'); // гид контура
    var match = function (a) {
      if (!q) return true;
      var hay = [a.title, a.desc, a.purpose, (a.features || []).join(' '), (a.connects || []).join(' ')].join(' ').toLowerCase();
      return hay.indexOf(q) >= 0;
    };
    var groups = (C.groups || []).filter(function (g) { return !only || g.id === only; });
    var head = '';
    if (only) {
      var g0 = (C.groups || []).filter(function (g) { return g.id === only; })[0];
      head = '<div class="guide-hero">' +
        '<a class="back" href="index.html">← Все контуры</a>' +
        '<h2>' + (g0 ? g0.icon + ' ' + esc(g0.title) : esc(only)) + '</h2>' +
        '<p>' + esc(CONTOURS[only] || '') + '</p>' +
        '<div class="links"><a href="../panel/index.html">🎛 Открыть пульт</a><a href="index.html">📖 Все модули</a><a href="../modules/index.html">🧩 Функции модулей</a></div>' +
        '</div>';
    }
    var html = head + groups.map(function (g) {
      var items = (C.apps || []).filter(function (a) { return a.group === g.id && match(a); });
      if (!items.length) return '';
      return '<div class="guide-grp"><h2>' + g.icon + ' ' + esc(g.title) + '</h2>' + items.map(moduleCard).join('') + '</div>';
    }).join('');
    $('#guide').innerHTML = html || '<div class="card"><span class="note">Ничего не найдено.</span></div>';
  }

  $('#q').addEventListener('input', function () { render(this.value); });

  var s = window.Auth && window.Auth.session ? window.Auth.session() : null;
  if (s) {
    $('#who').textContent = s.login + (s.role ? ' · ' + s.role : '');
    var lo = $('#logout'); lo.style.display = ''; lo.addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  } else {
    $('#who').textContent = 'гость';
  }
  render('');
})();
