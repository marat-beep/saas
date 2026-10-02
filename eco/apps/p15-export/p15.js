/* ============================================================
   P15 · Центр экспорта и отчётов (SaaS)
   Единый движок выгрузок (PDF/DOC/CSV/JSON/ICS) + конструктор
   отчётов. Работает по тенанту, учитывает white-label и flags.
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;
  var EX = window.AppExport;
  var D = window.AppData;

  /* ---------- SaaS-контекст ---------- */
  var TENANTS = ['ООО «Пресс-Технологии»', 'АО «Урал-Штамп»', 'ООО «Точмаш-Сервис»', 'ИП Ковалёв А.В.', 'ООО «ЛазерПро-Юг»'];
  var profile = (D && D.profile.get()) || {};
  var tenant = (D && D.settings.get('exportTenant', null)) || profile.company || TENANTS[0];
  var brand = (D && D.settings.get('exportBrand', null)) || tenant;
  var flags = (D && D.settings.get('flags', {})) || {};
  var moduleOn = flags.P15 !== false;

  function levelLabel(l) { return { director: 'Директор', chief: 'Нач. цеха', master: 'Мастер', operator: 'Оператор', engineer: 'Инженер' }[l] || l || '—'; }
  function typeLabel(t) { return { kp: 'КП', contract: 'Договор', naryad: 'Наряд', techcard: 'Техкарта' }[t] || t || '—'; }
  function num(n) { return (Number(n) || 0).toLocaleString('ru-RU'); }
  function safe(s) { return String(s == null ? '' : s).replace(/[^\wа-яА-ЯёЁ\-]+/g, '_').slice(0, 40); }

  /* ---------- Демо-данные (когда localStorage пуст) ---------- */
  var DEMO = {
    requests: [
      { id: 'REQ-2026-0004', source: 'Калькулятор', title: 'Фрезеровка кронштейна', customer: 'ООО «Привод»', status: 'Новая', created: '2026-10-02' },
      { id: 'REQ-2026-0003', source: 'Спец-технологии', title: 'Вулканизация ролика', customer: 'АО «Урал-Штамп»', status: 'В работе', created: '2026-10-01' },
      { id: 'REQ-2026-0002', source: 'Документация', title: 'Техпроцесс на втулку', customer: 'ООО «Точмаш»', status: 'В работе', created: '2026-09-30' },
      { id: 'REQ-2026-0001', source: 'Измерения', title: 'КИМ-контроль партии', customer: 'ООО «Привод»', status: 'Закрыта', created: '2026-09-29' }
    ],
    problems: [
      { id: 'PRB-007', title: 'Износ шпинделя DMU-50', level: 'Критично', status: 'Открыта', date: '2026-10-01' },
      { id: 'PRB-006', title: 'Срыв срока по заказу 0142', level: 'Средний', status: 'Открыта', date: '2026-09-30' },
      { id: 'PRB-005', title: 'Брак по пазу 12H7', level: 'Высокий', status: 'В работе', date: '2026-09-28' },
      { id: 'PRB-004', title: 'Перегрев гидростанции', level: 'Низкий', status: 'Решена', date: '2026-09-25' }
    ],
    staff: [
      { id: 'ST-001', name: 'Иванов И.И.', level: 'director', dept: 'Дирекция' },
      { id: 'ST-002', name: 'Кузнецов А.П.', level: 'chief', dept: 'Механообработка' },
      { id: 'ST-003', name: 'Орлов Д.В.', level: 'master', dept: 'Механообработка' },
      { id: 'ST-004', name: 'Петров В.С.', level: 'operator', dept: 'Механообработка' },
      { id: 'ST-005', name: 'Смирнова Е.А.', level: 'engineer', dept: 'Техотдел' }
    ],
    documents: [
      { num: 'КП-0142', type: 'kp', sum: 184000, created: '02.10.2026' },
      { num: 'Д-0091', type: 'contract', sum: 512000, created: '30.09.2026' },
      { num: 'НР-0512', type: 'naryad', sum: 0, created: '02.10.2026' }
    ],
    naryads: [
      { id: 'NR-0512', order: '3DMP-2025-0142', date: '2026-10-02', shift: '1-я смена', master: 'А. Кузнецов', status: 'Открыт', hours: 10 },
      { id: 'NR-0511', order: '3DMP-2025-0141', date: '2026-10-02', shift: '1-я смена', master: 'Д. Орлов', status: 'Открыт', hours: 8 },
      { id: 'NR-0510', order: '3DMP-2025-0119', date: '2026-10-01', shift: '2-я смена', master: 'В. Петров', status: 'Закрыт', hours: 10 },
      { id: 'NR-0509', order: '3DMP-2025-0150', date: '2026-10-01', shift: '1-я смена', master: 'А. Кузнецов', status: 'Закрыт', hours: 8 }
    ]
  };

  /* ---------- Наборы данных ---------- */
  function srcRequests() {
    var r = D ? D.requests.all() : [];
    if (!r.length) return DEMO.requests.slice();
    return r.map(function (x) { return { id: x.id, source: D.sourceTitle(x.source), title: x.title || '—', customer: x.customer || '—', status: x.status || '—', created: x.created || '' }; });
  }
  function srcProblems() {
    var r = D ? D.problems.all() : [];
    if (!r.length) return DEMO.problems.slice();
    return r.map(function (x) { return { id: x.id, title: x.title || '—', level: x.level || '—', status: x.status || '—', date: x.date || '' }; });
  }
  function srcStaff() {
    var r = D ? D.staff.all() : [];
    if (!r.length) return DEMO.staff.slice();
    return r.map(function (x) { return { id: x.id, name: x.name || '—', level: levelLabel(x.level), dept: x.dept || '—' }; });
  }
  function srcDocuments() {
    var r = App.Store.get('documents', []);
    if (!r.length) return DEMO.documents.slice();
    return r.map(function (x) { return { num: x.num, type: typeLabel(x.type), sum: Number(x.sum) || 0, created: x.created || '' }; });
  }
  function srcNaryads() {
    return DEMO.naryads.slice();
  }
  function srcKpi() {
    var req = srcRequests(), prb = srcProblems(), nar = srcNaryads();
    var hours = nar.reduce(function (a, n) { return a + (n.hours || 0); }, 0);
    var openNar = nar.filter(function (n) { return n.status === 'Открыт'; }).length;
    return [
      { metric: 'Заявок всего', value: req.length },
      { metric: 'Проблем открыто', value: prb.filter(function (p) { return p.status !== 'Решена'; }).length },
      { metric: 'Нарядов в работе', value: openNar },
      { metric: 'Нормо-часов планово', value: hours },
      { metric: 'Выручка (демо), ₽', value: '12 480 000' },
      { metric: 'Загрузка, %', value: 78 }
    ];
  }

  var DATASETS = [
    { id: 'requests', icon: '📥', name: 'Заявки', desc: 'Сквозные заявки из клиентских сервисов',
      columns: [{ key: 'id', label: 'ID' }, { key: 'source', label: 'Источник' }, { key: 'title', label: 'Тема' }, { key: 'customer', label: 'Заказчик' }, { key: 'status', label: 'Статус' }, { key: 'created', label: 'Дата' }],
      get: srcRequests, event: function (r) { return { title: 'Заявка ' + r.id + ': ' + r.title, date: r.created, desc: r.customer + ' · ' + r.status }; } },
    { id: 'problems', icon: '🚨', name: 'Проблемы', desc: 'Реестр проблем и эскалаций',
      columns: [{ key: 'id', label: 'ID' }, { key: 'title', label: 'Проблема' }, { key: 'level', label: 'Уровень' }, { key: 'status', label: 'Статус' }, { key: 'date', label: 'Дата' }],
      get: srcProblems, event: function (r) { return { title: 'Проблема ' + r.id + ': ' + r.title, date: r.date, desc: r.level + ' · ' + r.status }; } },
    { id: 'staff', icon: '👔', name: 'Персонал', desc: 'Сотрудники, уровни, подразделения',
      columns: [{ key: 'id', label: 'ID' }, { key: 'name', label: 'Сотрудник' }, { key: 'level', label: 'Уровень' }, { key: 'dept', label: 'Подразделение' }], get: srcStaff },
    { id: 'documents', icon: '📄', name: 'Документы', desc: 'КП, договоры, наряды, техкарты (B33)',
      columns: [{ key: 'num', label: 'Номер' }, { key: 'type', label: 'Тип' }, { key: 'sum', label: 'Сумма, ₽', num: true }, { key: 'created', label: 'Дата' }], get: srcDocuments },
    { id: 'naryads', icon: '🧾', name: 'Наряды', desc: 'Сменные задания и нормо-часы',
      columns: [{ key: 'id', label: 'Наряд' }, { key: 'order', label: 'Заказ' }, { key: 'date', label: 'Дата' }, { key: 'shift', label: 'Смена' }, { key: 'master', label: 'Мастер' }, { key: 'status', label: 'Статус' }, { key: 'hours', label: 'Часы', num: true }],
      get: srcNaryads, event: function (r) { return { title: 'Наряд ' + r.id + ' (' + r.order + ')', date: r.date, desc: r.shift + ' · ' + r.master + ' · ' + r.hours + ' ч' }; } },
    { id: 'kpi', icon: '📊', name: 'KPI завода', desc: 'Сводные показатели для отчёта',
      columns: [{ key: 'metric', label: 'Показатель' }, { key: 'value', label: 'Значение', num: true }], get: srcKpi }
  ];
  function dsById(id) { return DATASETS.filter(function (d) { return d.id === id; })[0]; }
  function colLabel(ds, key) { var c = ds.columns.filter(function (x) { return x.key === key; })[0]; return c ? c.label : key; }

  /* ---------- История выгрузок ---------- */
  function histAll() { return App.Store.get('exports', []); }
  function histAdd(rec) {
    var l = histAll();
    l.unshift(Object.assign({ date: App.today(), when: App.nowTime(), ts: Date.now(), tenant: tenant }, rec));
    App.Store.set('exports', l.slice(0, 100));
    if (D) D.log.add({ action: 'Экспорт ' + rec.format, detail: rec.name + ' · ' + tenant });
  }

  /* ---------- Роутер ---------- */
  var screens = AppRouter.create({
    onShow: function (s) { $$('#nav button').forEach(function (b) { b.classList.toggle('active', b.dataset.s === s.id); }); window.scrollTo(0, 0); },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });
  $('#nav').addEventListener('click', function (e) { var b = e.target.closest('button'); if (!b) return; screens.go(b.dataset.s); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  /* ---------- Обзор ---------- */
  function initTenant() {
    var opts = TENANTS.slice();
    if (profile.company && opts.indexOf(profile.company) < 0) opts.unshift(profile.company);
    $('#tenantSel').innerHTML = opts.map(function (t) { return '<option' + (t === tenant ? ' selected' : '') + '>' + t + '</option>'; }).join('');
    $('#brandInput').value = brand;
  }
  function renderKpi() {
    $('#kpi').innerHTML =
      kpi(DATASETS.length, 'источников данных') +
      kpi('5', 'форматов экспорта') +
      kpi(histAll().length, 'выгрузок в журнале') +
      kpi(moduleOn ? 'вкл' : 'выкл', 'модуль P15');
  }
  function kpi(v, l) { return '<div class="stat"><div class="num accent" style="font-size:1.4rem;">' + v + '</div><div class="label">' + l + '</div></div>'; }

  var FORMATS = [
    ['📄', 'DOC (Word)', 'Редактируемый документ: отчёты, КП, реестры'],
    ['🖨', 'PDF / печать', 'Печатная форма через браузер (без сервера)'],
    ['📑', 'CSV (Excel)', 'Табличная выгрузка с кодировкой UTF-8 BOM'],
    ['🧩', 'JSON', 'Машиночитаемый обмен и интеграция (P4)'],
    ['📅', 'ICS (календарь)', 'События/сроки для Outlook и Google Calendar']
  ];
  $('#fmtList').innerHTML = FORMATS.map(function (f) {
    return '<div class="hrow"><span style="font-size:1.1rem;">' + f[0] + '</span><span class="nm"><b>' + f[1] + '</b><div class="faint" style="font-size:.72rem;">' + f[2] + '</div></span></div>';
  }).join('');

  function renderDsOverview() {
    $('#dsOverview').innerHTML = DATASETS.map(function (d) {
      return '<div class="card clickable ds-card" data-open="' + d.id + '"><div style="font-size:1.4rem;">' + d.icon + '</div><h3 style="font-size:.9rem;margin-top:6px;">' + d.name + '</h3><p style="font-size:.76rem;color:var(--muted);margin:4px 0 0;">' + d.desc + '</p></div>';
    }).join('');
    $$('#dsOverview [data-open]').forEach(function (c) {
      c.addEventListener('click', function () { selectDataset(c.dataset.open); screens.go('s-export'); });
    });
  }

  function renderFlagNotice() {
    var box = $('#flagNotice');
    if (!moduleOn) box.innerHTML = '<div class="notice">Модуль «Центр экспорта» отключён для тенанта (feature flags, P1/P9). Экспорт недоступен — включите модуль в P1 Cloud.</div>';
    else box.innerHTML = '<div class="notice" style="border-color:var(--accent);background:var(--accent-100);color:var(--accent-700);">Тенант: ' + tenant + ' · white-label «' + brand + '» · журнал выгрузок ведётся локально (демо).</div>';
  }

  $('#tenantSel').addEventListener('change', function () {
    tenant = this.value; if (D) D.settings.set('exportTenant', tenant);
    brand = tenant; $('#brandInput').value = brand; if (D) D.settings.set('exportBrand', brand);
    renderFlagNotice(); renderKpi(); App.toast('Тенант: ' + tenant);
  });
  $('#brandInput').addEventListener('change', function () {
    brand = this.value.trim() || tenant; if (D) D.settings.set('exportBrand', brand);
    renderFlagNotice(); App.toast('Бренд документов обновлён');
  });

  /* ---------- Экспорт данных ---------- */
  var curDs = DATASETS[0].id;
  var colSel = {}; // datasetId -> [keys]

  function selectDataset(id) {
    curDs = id;
    if (!colSel[id]) colSel[id] = dsById(id).columns.map(function (c) { return c.key; });
    renderDsPicker(); renderCols(); renderTablePreview();
  }
  function selectedCols(id) {
    var ds = dsById(id);
    if (!colSel[id]) colSel[id] = ds.columns.map(function (c) { return c.key; });
    return ds.columns.filter(function (c) { return colSel[id].indexOf(c.key) >= 0; });
  }
  function renderDsPicker() {
    $('#dsPicker').innerHTML = DATASETS.map(function (d) {
      return '<div class="card clickable ds-card' + (d.id === curDs ? ' on' : '') + '" data-ds="' + d.id + '"><div style="font-size:1.3rem;">' + d.icon + '</div><h3 style="font-size:.86rem;margin-top:4px;">' + d.name + '</h3><div class="faint" style="font-size:.7rem;">' + d.get().length + ' строк</div></div>';
    }).join('');
    $$('#dsPicker [data-ds]').forEach(function (c) { c.addEventListener('click', function () { selectDataset(c.dataset.ds); }); });
  }
  function renderCols() {
    var ds = dsById(curDs), sel = colSel[curDs];
    $('#cols').innerHTML = ds.columns.map(function (c) {
      return '<span class="col-chip' + (sel.indexOf(c.key) >= 0 ? ' on' : '') + '" data-col="' + c.key + '">' + (sel.indexOf(c.key) >= 0 ? '✓ ' : '') + c.label + '</span>';
    }).join('');
    $('#colCount').textContent = sel.length + ' из ' + ds.columns.length;
    $$('#cols [data-col]').forEach(function (ch) {
      ch.addEventListener('click', function () {
        var k = ch.dataset.col, i = sel.indexOf(k);
        if (i >= 0) { if (sel.length > 1) sel.splice(i, 1); } else sel.push(k);
        renderCols(); renderTablePreview();
      });
    });
    var icsBtn = $('#exportFmts [data-fmt="ics"]');
    if (icsBtn) icsBtn.disabled = !ds.event;
  }
  function renderTablePreview() {
    var ds = dsById(curDs), data = ds.get(), cols = selectedCols(curDs);
    var show = data.slice(0, 25);
    $('#tablePreview').innerHTML = '<h1>' + brand + '</h1><div class="rpt-sub">Набор: ' + ds.name + ' · ' + tenant + '</div>' +
      '<div class="rpt-meta"><span>Дата: <b>' + App.today() + '</b></span><span>Строк: <b>' + data.length + '</b></span><span>Полей: <b>' + cols.length + '</b></span></div>' +
      EX.tableHtml(cols, show);
    $('#pvInfo').textContent = data.length > 25 ? '(первые 25 из ' + data.length + ')' : '(' + data.length + ')';
  }
  function reportForDataset() {
    var ds = dsById(curDs), data = ds.get(), cols = selectedCols(curDs);
    return EX.reportDocument({
      brand: brand, title: 'Выгрузка: ' + ds.name, subtitle: tenant,
      meta: [{ k: 'Тенант', v: tenant }, { k: 'Дата', v: App.today() }, { k: 'Строк', v: data.length }],
      sections: [{ title: ds.name, columns: cols, rows: data }],
      footer: '3DMP · Центр экспорта · ' + App.today() + ' ' + App.nowTime()
    });
  }
  function exportData(fmt) {
    if (!moduleOn) { App.toast('Модуль экспорта отключён для тенанта'); return; }
    var ds = dsById(curDs), data = ds.get(), cols = selectedCols(curDs);
    var base = safe(tenant + '_' + ds.name + '_' + App.today());
    var ok = true;
    if (fmt === 'csv') ok = EX.exportCsv(base, cols, data);
    else if (fmt === 'json') ok = EX.exportJson(base, data);
    else if (fmt === 'ics') ok = ds.event ? EX.exportIcs(base, data.map(ds.event), '3DMP · ' + ds.name) : false;
    else if (fmt === 'doc') ok = EX.exportDoc(base, ds.name, reportForDataset());
    else if (fmt === 'pdf') ok = EX.exportPdf(ds.name, reportForDataset());
    if (ok) { histAdd({ format: fmt.toUpperCase(), name: 'Набор: ' + ds.name }); renderKpi(); App.toast('Экспорт ' + fmt.toUpperCase() + ' сформирован'); }
  }
  $('#exportFmts').addEventListener('click', function (e) {
    var b = e.target.closest('[data-fmt]'); if (!b || b.disabled) return;
    exportData(b.dataset.fmt);
  });

  /* ---------- Конструктор отчётов ---------- */
  function kpiRequests(r) { return [{ label: 'Всего заявок', value: r.length }, { label: 'Новых', value: r.filter(function (x) { return x.status === 'Новая'; }).length }, { label: 'В работе', value: r.filter(function (x) { return x.status === 'В работе'; }).length }, { label: 'Закрыто', value: r.filter(function (x) { return x.status === 'Закрыта'; }).length }]; }
  function kpiProblems(r) { return [{ label: 'Всего', value: r.length }, { label: 'Критично', value: r.filter(function (x) { return x.level === 'Критично'; }).length }, { label: 'Открыто', value: r.filter(function (x) { return x.status === 'Открыта'; }).length }]; }
  function kpiStaff(r) { return [{ label: 'Сотрудников', value: r.length }, { label: 'Подразделений', value: distinct(r, 'dept').length }]; }
  function kpiNaryads(r) { return [{ label: 'Нарядов', value: r.length }, { label: 'В работе', value: r.filter(function (x) { return x.status === 'Открыт'; }).length }, { label: 'Нормо-часов', value: r.reduce(function (a, x) { return a + (x.hours || 0); }, 0) }]; }
  function distinct(rows, key) { var seen = []; rows.forEach(function (r) { if (seen.indexOf(r[key]) < 0) seen.push(r[key]); }); return seen; }
  function groupBy(rows, key) { return distinct(rows, key).map(function (k) { return { k: k, v: rows.filter(function (r) { return r[key] === k; }).length }; }); }

  var TEMPLATES = [
    { id: 'requests', name: 'Сводка по заявкам', ds: 'requests', kpis: kpiRequests, breakdown: 'status' },
    { id: 'problems', name: 'Проблемы и эскалации', ds: 'problems', kpis: kpiProblems, breakdown: 'level' },
    { id: 'staff', name: 'Структура персонала', ds: 'staff', kpis: kpiStaff, breakdown: 'dept' },
    { id: 'naryads', name: 'Наряды и смены', ds: 'naryads', kpis: kpiNaryads, breakdown: 'shift' },
    { id: 'kpi', name: 'KPI завода (сводка)', ds: 'kpi', kpis: null }
  ];
  function tplById(id) { return TEMPLATES.filter(function (t) { return t.id === id; })[0]; }

  var BLOCKS = [['kpi', 'KPI-плашки'], ['breakdown', 'Разбивка'], ['table', 'Таблица детализации'], ['sign', 'Подписи']];
  var activeBlocks = { kpi: true, breakdown: true, table: true, sign: false };

  function renderBlocks() {
    $('#rptBlocks').innerHTML = BLOCKS.map(function (b) {
      return '<span class="col-chip' + (activeBlocks[b[0]] ? ' on' : '') + '" data-block="' + b[0] + '">' + (activeBlocks[b[0]] ? '✓ ' : '') + b[1] + '</span>';
    }).join('');
    $$('#rptBlocks [data-block]').forEach(function (ch) {
      ch.addEventListener('click', function () { activeBlocks[ch.dataset.block] = !activeBlocks[ch.dataset.block]; renderBlocks(); renderReport(); });
    });
  }

  function renderTplSelect() {
    $('#tplSel').innerHTML = TEMPLATES.map(function (t) { return '<option value="' + t.id + '">' + t.name + '</option>'; }).join('');
  }
  function curTpl() { return tplById($('#tplSel').value) || TEMPLATES[0]; }

  function buildReport() {
    var tpl = curTpl(), ds = dsById(tpl.ds), data = ds.get();
    var title = $('#rptTitle').value.trim() || tpl.name;
    var period = $('#rptPeriod').value.trim() || 'весь период';
    var kpis = (activeBlocks.kpi && tpl.kpis) ? tpl.kpis(data) : [];
    var sections = [];
    if (activeBlocks.breakdown && tpl.breakdown) {
      sections.push({ title: 'Разбивка по полю «' + colLabel(ds, tpl.breakdown) + '»',
        columns: [{ key: 'k', label: colLabel(ds, tpl.breakdown) }, { key: 'v', label: 'Кол-во', num: true }],
        rows: groupBy(data, tpl.breakdown) });
    }
    if (activeBlocks.table) sections.push({ title: 'Детализация', columns: ds.columns, rows: data });
    return EX.reportDocument({
      brand: brand, title: title, subtitle: tenant + ' · ' + period,
      meta: [{ k: 'Тенант', v: tenant }, { k: 'Период', v: period }, { k: 'Дата', v: App.today() }, { k: 'Строк', v: data.length }],
      kpis: kpis, sections: sections,
      sign: activeBlocks.sign ? ['Исполнитель: ' + brand, 'Получатель'] : null,
      footer: 'Сформировано в 3DMP · Центр экспорта и отчётов · ' + App.today() + ' ' + App.nowTime()
    });
  }
  function renderReport() { $('#rptPreview').innerHTML = buildReport(); }

  function exportReport(fmt) {
    if (!moduleOn) { App.toast('Модуль экспорта отключён для тенанта'); return; }
    var tpl = curTpl(), title = $('#rptTitle').value.trim() || tpl.name;
    var base = safe(tenant + '_' + title + '_' + App.today());
    var ok = fmt === 'doc' ? EX.exportDoc(base, title, buildReport()) : EX.exportPdf(title, buildReport());
    if (ok) { histAdd({ format: fmt.toUpperCase(), name: 'Отчёт: ' + title }); renderKpi(); App.toast('Отчёт ' + fmt.toUpperCase() + ' сформирован'); }
  }

  $('#tplSel').addEventListener('change', function () {
    var t = curTpl(); $('#rptTitle').value = t.name; renderReport();
  });
  $('#rptTitle').addEventListener('input', renderReport);
  $('#rptPeriod').addEventListener('input', renderReport);

  function saveTpl() {
    var t = curTpl(), title = $('#rptTitle').value.trim() || t.name;
    var list = savedTpl();
    list.unshift({ name: title, tpl: t.id, title: title, period: $('#rptPeriod').value.trim(), blocks: Object.assign({}, activeBlocks), date: App.today() });
    App.Store.set('reportTemplates', list.slice(0, 20));
    renderSaved(); App.toast('Шаблон сохранён');
  }
  $('#s-reports').addEventListener('click', function (e) {
    var b = e.target.closest('[data-rpt]'); if (!b) return;
    var act = b.dataset.rpt;
    if (act === 'pdf') exportReport('pdf');
    else if (act === 'doc') exportReport('doc');
    else if (act === 'save') saveTpl();
    else renderReport();
  });

  /* ---------- Сохранённые шаблоны ---------- */
  function savedTpl() { return App.Store.get('reportTemplates', []); }
  function renderSaved() {
    var list = savedTpl();
    if (!list.length) { $('#savedTpl').innerHTML = '<div class="faint" style="font-size:.8rem;">Сохранённых шаблонов нет. Настройте отчёт и нажмите «Сохранить шаблон».</div>'; return; }
    $('#savedTpl').innerHTML = list.map(function (t, i) {
      return '<div class="hrow"><span style="font-size:1rem;">📋</span><span class="nm"><b>' + t.name + '</b><div class="faint" style="font-size:.7rem;">' + t.tpl + ' · ' + (t.period || 'весь период') + ' · ' + t.date + '</div></span><button class="btn btn-secondary btn-sm" data-load="' + i + '" style="width:auto;">Открыть</button><button class="btn btn-ghost btn-sm" data-del="' + i + '" style="width:auto;">✕</button></div>';
    }).join('');
    $$('#savedTpl [data-load]').forEach(function (b) { b.addEventListener('click', function () { loadSaved(parseInt(b.dataset.load, 10)); }); });
    $$('#savedTpl [data-del]').forEach(function (b) { b.addEventListener('click', function () { var l = savedTpl(); l.splice(parseInt(b.dataset.del, 10), 1); App.Store.set('reportTemplates', l); renderSaved(); }); });
  }
  function loadSaved(i) {
    var t = savedTpl()[i]; if (!t) return;
    $('#tplSel').value = t.tpl; $('#rptTitle').value = t.title || t.name; $('#rptPeriod').value = t.period || '';
    activeBlocks = Object.assign({ kpi: true, breakdown: true, table: true, sign: false }, t.blocks || {});
    renderBlocks(); renderReport(); screens.go('s-reports'); App.toast('Шаблон загружен');
  }

  /* ---------- История ---------- */
  function renderHistory() {
    var list = histAll();
    if (!list.length) { $('#histList').innerHTML = '<div class="faint" style="font-size:.8rem;">Выгрузок пока нет.</div>'; return; }
    $('#histList').innerHTML = list.map(function (h) {
      return '<div class="hrow"><span class="badge accent">' + h.format + '</span><span class="nm">' + h.name + '<div class="faint" style="font-size:.7rem;">' + h.tenant + '</div></span><span class="faint" style="font-size:.72rem;">' + h.date + ' ' + h.when + '</span></div>';
    }).join('');
  }
  $('#histClear').addEventListener('click', function () { App.Store.set('exports', []); renderHistory(); renderKpi(); App.toast('История выгрузок очищена'); });

  /* ---------- Инициализация ---------- */
  initTenant();
  renderFlagNotice();
  renderKpi();
  renderDsOverview();
  renderTplSelect();
  renderBlocks();
  renderSaved();
  renderHistory();
  selectDataset(curDs);
  $('#rptTitle').value = TEMPLATES[0].name;
  renderReport();
})();
