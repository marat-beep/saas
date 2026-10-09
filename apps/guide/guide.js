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
    var man = '';
    if (!only && !q) {
      man = '<div class="guide-hero"><h2>📚 Справка и мануалы</h2>' +
        '<p>Руководство пользователя и администратора — в базе знаний (категории «Справка» и «Администрирование»).</p>' +
        '<div class="links"><a href="../assistant/index.html">🔎 Поиск по базе знаний</a>' +
        '<a href="../modules/index.html">🧩 Функции модулей</a>' +
        '<a href="../adoption/index.html">🚀 Карта внедрения</a>' +
        '<a href="../../index.html">🏠 Хаб</a></div></div>';
    }
    var gf = '';
    if (!only && !q) {
      var G = window.AppGuideFields || { generic: { steps: [], tips: [] }, modules: {} };
      var opts = '<option value="__generic">Общие правила заполнения</option>';
      var others = (C.apps || []).slice();
      (C.groups || []).forEach(function (g) {
        var items = others.filter(function (a) { return a.group === g.id; });
        if (!items.length) return;
        opts += '<optgroup label="' + esc(g.title) + '">' + items.map(function (a) {
          var cur = G.modules[a.id];
          return '<option value="' + a.id + '">' + (cur ? '★ ' : '') + esc(a.title) + '</option>';
        }).join('') + '</optgroup>';
      });
      var rest = others.filter(function (a) { return !a.group; });
      if (rest.length) opts += '<optgroup label="Прочее">' + rest.map(function (a) { return '<option value="' + a.id + '">' + esc(a.title) + '</option>'; }).join('') + '</optgroup>';
      gf = '<div class="card" id="gf"><h2>🧭 Инструкции: поля и как работать</h2>' +
        '<p class="note">Выберите модуль. «★» — расширенная инструкция по полям; остальные — назначение и порядок работы из каталога.</p>' +
        '<div class="field" style="max-width:460px;"><label>Модуль</label><select id="gfSel">' + opts + '</select></div>' +
        '<div id="gfBody" class="mt"></div></div>';
    }
    var html = man + gf + head + groups.map(function (g) {
      var items = (C.apps || []).filter(function (a) { return a.group === g.id && match(a); });
      if (!items.length) return '';
      return '<div class="guide-grp"><h2>' + g.icon + ' ' + esc(g.title) + '</h2>' + items.map(moduleCard).join('') + '</div>';
    }).join('');
    $('#guide').innerHTML = html || '<div class="card"><span class="note">Ничего не найдено.</span></div>';
    if ($('#gfSel')) {
      var G = window.AppGuideFields || { generic: { steps: [], tips: [] }, modules: {} };
      var renderGf = function (key) {
        var body = $('#gfBody');
        if (key === '__generic') {
          body.innerHTML = '<h3>Общие правила</h3><ol class="gf-list">' + G.generic.steps.map(function (s) { return '<li>' + esc(s) + '</li>'; }).join('') + '</ol>' +
            '<h4>Полезно</h4><ul class="gf-list">' + G.generic.tips.map(function (s) { return '<li>' + esc(s) + '</li>'; }).join('') + '</ul>';
          return;
        }
        var m = G.modules[key];
        if (m) {
          body.innerHTML = '<h3>' + esc(m.title) + '</h3><p>' + esc(m.intro) + '</p>' +
            '<h4>Порядок работы</h4><ol class="gf-list">' + m.flow.map(function (s) { return '<li>' + esc(s) + '</li>'; }).join('') + '</ol>' +
            '<h4>Поля</h4><div class="tbl-wrap"><table class="tbl gf-tbl"><thead><tr><th>Поле</th><th>Назначение</th><th>Как заполнять</th><th class="c">Обязательное</th></tr></thead><tbody>' +
            m.fields.map(function (f) { return '<tr><td><b>' + esc(f.n) + '</b></td><td>' + esc(f.desc || '') + '</td><td class="note">' + esc(f.hint || '') + '</td><td class="c">' + (f.req ? '<b>да</b>' : '—') + '</td></tr>'; }).join('') +
            '</tbody></table></div>' +
            (m.tips && m.tips.length ? '<h4>Подсказки</h4><ul class="gf-list">' + m.tips.map(function (s) { return '<li>' + esc(s) + '</li>'; }).join('') + '</ul>' : '');
          return;
        }
        // из каталога: назначение, возможности, связи, общий порядок
        var a = (C.apps || []).filter(function (x) { return x.id === key; })[0];
        if (!a) { body.innerHTML = ''; return; }
        var feats = (a.features || []).map(function (f) { return '<li>' + esc(f) + '</li>'; }).join('');
        var conns = (a.connects || []).map(function (id) { var t = byId(id); return '<a class="chip" href="../../' + (t ? t.href : '#') + '">' + esc(t ? t.title : id) + '</a>'; }).join('');
        body.innerHTML = '<h3>' + a.icon + ' ' + esc(a.title) + '</h3>' +
          '<p>' + esc(a.purpose || a.desc || '') + '</p>' +
          '<h4>Что можно делать</h4><ul class="gf-list">' + (feats || '<li>—</li>') + '</ul>' +
          '<h4>Порядок работы</h4><ol class="gf-list">' + G.generic.steps.slice(0, 5).map(function (s) { return '<li>' + esc(s) + '</li>'; }).join('') + '</ol>' +
          (conns ? '<h4>Связи</h4><div class="chips">' + conns + '</div>' : '') +
          '<p class="note mt">Расширенная инструкция по полям для этого модуля появится позже; ниже — открыть модуль.</p>' +
          '<div class="links mt"><a class="chip" href="../../' + a.href + '">Открыть «' + esc(a.title) + '»</a><a class="chip" href="../../assets/js/catalog.js">Каталог</a></div>';
      };
      $('#gfSel').addEventListener('change', function () { renderGf(this.value); });
      renderGf('__generic');
    }
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
