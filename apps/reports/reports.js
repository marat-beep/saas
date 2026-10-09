/* ============================================================
   3DMP Service · apps/reports — отчёты, экспорт и конструктор (W8).
   Движок: assets/js/export.js (AppExport). Конструктор: 0153 (app_report_defs).
   Роли: admin/owner/manager (staff).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB, EX = window.AppExport;
  var token = null, me = null, cur = null, rows = [], cols = [];
  var defs = [], lastRun = null;
  function esc(v) { return ui.esc(v); }
  function day(v) { return v ? String(v).slice(0, 10) : ''; }
  function msg(t, k) { var e = $('#msg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function defMsg(t, k) { var e = $('#defMsg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg() { $('#msg').className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  var DATASETS = {
    orders: {
      name: 'Заявки', load: function () { return rpc('app_order_list', { p_token: token }); },
      cols: [{ key: 'number', label: 'Номер' }, { key: 'title', label: 'Тема' }, { key: 'customer', label: 'Заказчик' },
             { key: 'source', label: 'Источник' }, { key: 'status', label: 'Статус' }, { key: 'priority', label: 'Приоритет' },
             { key: 'amount', label: 'Сумма', num: true },
             { key: 'created_at', label: 'Создана', value: function (r) { return day(r.created_at); } }]
    },
    naryads: {
      name: 'Наряды', load: function () { return rpc('app_naryad_list', { p_token: token }); },
      cols: [{ key: 'number', label: 'Наряд' }, { key: 'title', label: 'Название' }, { key: 'wc_name', label: 'Центр' },
             { key: 'assignee', label: 'Исполнитель' }, { key: 'status', label: 'Статус' },
             { key: 'plan_hours', label: 'План, ч', num: true }, { key: 'fact_hours', label: 'Факт, ч', num: true }]
    },
    tenders: {
      name: 'Закупки', load: function () { return rpc('app_tender_list_full', { p_token: token }); },
      cols: [{ key: 'title', label: 'Закупка' }, { key: 'category', label: 'Категория' }, { key: 'customer', label: 'Заказчик' },
             { key: 'deadline', label: 'Срок', value: function (r) { return day(r.deadline); } },
             { key: 'status', label: 'Статус' }, { key: 'bids_count', label: 'КП', num: true }]
    },
    materials: {
      name: 'Склад', load: function () { return rpc('app_material_list', { p_token: token }); },
      cols: [{ key: 'code', label: 'Код' }, { key: 'name', label: 'Материал' }, { key: 'unit', label: 'Ед.' },
             { key: 'qty', label: 'Остаток', num: true }, { key: 'min_qty', label: 'Минимум', num: true },
             { key: 'price', label: 'Цена, ₽', num: true }]
    },
    passports: {
      name: 'Паспорта', load: function () { return rpc('app_passport_list', { p_token: token }); },
      cols: [{ key: 'number', label: 'Номер' }, { key: 'product', label: 'Изделие' }, { key: 'order_number', label: 'Заявка' },
             { key: 'created_at', label: 'Создан', value: function (r) { return day(r.created_at); } }]
    },
    invoices: {
      name: 'Счета', load: function () { return rpc('app_invoice_list', { p_token: token }); },
      cols: [{ key: 'number', label: 'Счёт' }, { key: 'customer_name', label: 'Заказчик' }, { key: 'order_number', label: 'Заявка' },
             { key: 'amount', label: 'Сумма', num: true }, { key: 'paid', label: 'Оплачено', num: true },
             { key: 'balance', label: 'Остаток', num: true }, { key: 'status', label: 'Статус' },
             { key: 'due_date', label: 'Срок', value: function (r) { return day(r.due_date); } }]
    },
    economics: {
      name: 'Экономика заявок', load: function () { return rpc('app_economics_orders', { p_token: token }); },
      cols: [{ key: 'number', label: 'Заявка' }, { key: 'title', label: 'Тема' }, { key: 'amount', label: 'Сумма', num: true },
             { key: 'work_cost', label: 'Работы', num: true }, { key: 'material_cost', label: 'Материалы', num: true },
             { key: 'total', label: 'Себестоимость', num: true }, { key: 'margin', label: 'Маржа', num: true },
             { key: 'margin_pct', label: 'Маржа %', num: true }]
    },
    qc: {
      name: 'ОТК', load: function () { return rpc('app_qc_list', { p_token: token }); },
      cols: [{ key: 'number', label: 'Чек-лист' }, { key: 'product', label: 'Изделие' }, { key: 'status', label: 'Итог' },
             { key: 'qty_good', label: 'Годных', num: true }, { key: 'qty_total', label: 'Всего', num: true },
             { key: 'defects_count', label: 'Дефектов', num: true }, { key: 'inspector', label: 'Контролёр' }]
    },
    routes: {
      name: 'Маршруты', load: function () { return rpc('app_route_list', { p_token: token }); },
      cols: [{ key: 'number', label: 'Маршрут' }, { key: 'name', label: 'Название' }, { key: 'template_name', label: 'Техпроцесс' },
             { key: 'order_number', label: 'Заявка' }, { key: 'total_min', label: 'Мин', num: true },
             { key: 'total_cost', label: 'Себестоимость', num: true }, { key: 'status', label: 'Статус' }]
    },
    /* ---------- W34: наборы по модулям волн v2/v3 (через app_module_report) ---------- */
    tooling: {
      name: 'Инструмент (экземпляры)', load: function () { return mr('tooling'); },
      cols: [{ key: 'serial', label: 'Серийный №' }, { key: 'status', label: 'Статус' }, { key: 'machine', label: 'Станок' },
             { key: 'used_min', label: 'Наработка, мин', num: true }, { key: 'resource_min', label: 'Ресурс, мин', num: true },
             { key: 'holder_login', label: 'У кого' }]
    },
    mdm: {
      name: 'НСИ (позиции)', load: function () { return mr('mdm'); },
      cols: [{ key: 'code', label: 'Код' }, { key: 'name', label: 'Наименование' }, { key: 'item_type', label: 'Тип' },
             { key: 'unit', label: 'Ед.' }, { key: 'grp', label: 'Группа' }, { key: 'status', label: 'Статус' }, { key: 'source', label: 'Источник' }]
    },
    plm: {
      name: 'Изделия (PLM)', load: function () { return mr('plm'); },
      cols: [{ key: 'code', label: 'Код' }, { key: 'name', label: 'Изделие' }, { key: 'version', label: 'Версия' }, { key: 'state', label: 'Состояние' }]
    },
    edo: {
      name: 'Документы (ЭДО)', load: function () { return mr('edo'); },
      cols: [{ key: 'reg_number', label: 'Рег. №' }, { key: 'kind', label: 'Вид' }, { key: 'doc_type', label: 'Тип' },
             { key: 'title', label: 'Тема' }, { key: 'correspondent', label: 'Корреспондент' }, { key: 'status', label: 'Статус' },
             { key: 'responsible_login', label: 'Ответственный' }, { key: 'due_date', label: 'Срок' }]
    },
    kedo: {
      name: 'Кадровые документы (КЭДО)', load: function () { return mr('kedo'); },
      cols: [{ key: 'number', label: 'Номер' }, { key: 'doc_type', label: 'Тип' }, { key: 'title', label: 'Название' },
             { key: 'employee_login', label: 'Сотрудник' }, { key: 'status', label: 'Статус' }, { key: 'signed_at', label: 'Подписано' }]
    },
    eam: {
      name: 'Вибрация (EAM)', load: function () { return mr('eam'); },
      cols: [{ key: 'equipment', label: 'Оборудование' }, { key: 'value', label: 'Значение', num: true }, { key: 'unit', label: 'Ед.' },
             { key: 'result', label: 'Результат' }, { key: 'ts', label: 'Время' }]
    },
    safety: {
      name: 'Инциденты (EHS)', load: function () { return mr('safety'); },
      cols: [{ key: 'kind', label: 'Тип' }, { key: 'event_date', label: 'Дата' }, { key: 'location', label: 'Место' },
             { key: 'severity', label: 'Критичность' }, { key: 'status', label: 'Статус' }]
    },
    holding: {
      name: 'Площадки (Холдинг)', load: function () { return mr('holding'); },
      cols: [{ key: 'name', label: 'Площадка' }, { key: 'code', label: 'Код' }, { key: 'region', label: 'Регион' },
             { key: 'share', label: 'Доля', num: true }, { key: 'active', label: 'Активна' }]
    },
    projbudget: {
      name: 'Сметы проектов', load: function () { return mr('projbudget'); },
      cols: [{ key: 'name', label: 'Смета' }, { key: 'version', label: 'Версия' }, { key: 'currency', label: 'Валюта' }, { key: 'status', label: 'Статус' }]
    },
    pmo: {
      name: 'Вехи (PMO)', load: function () { return mr('pmo'); },
      cols: [{ key: 'name', label: 'Веха' }, { key: 'due_date', label: 'Срок' }, { key: 'status', label: 'Статус' }, { key: 'weight', label: 'Вес', num: true }]
    },
    logistics: {
      name: 'Рейсы (TMS)', load: function () { return mr('logistics'); },
      cols: [{ key: 'number', label: 'Рейс' }, { key: 'direction', label: 'Направление' }, { key: 'counterparty', label: 'Контрагент' },
             { key: 'cargo', label: 'Груз' }, { key: 'from_loc', label: 'Откуда' }, { key: 'to_loc', label: 'Куда' },
             { key: 'cost', label: 'Стоимость', num: true }, { key: 'status', label: 'Статус' }]
    },
    itsm: {
      name: 'Заявки ИТ (ITSM)', load: function () { return mr('itsm'); },
      cols: [{ key: 'number', label: 'Номер' }, { key: 'title', label: 'Тема' }, { key: 'priority', label: 'Приоритет' },
             { key: 'status', label: 'Статус' }, { key: 'assignee_login', label: 'Исполнитель' }, { key: 'due_at', label: 'SLA-срок' }]
    },
    elearning: {
      name: 'Курсы (e-Learning)', load: function () { return mr('elearning'); },
      cols: [{ key: 'code', label: 'Код' }, { key: 'name', label: 'Курс' }, { key: 'category', label: 'Категория' },
             { key: 'hours', label: 'Часов', num: true }, { key: 'active', label: 'Активен' }]
    },
    accounting: {
      name: 'Проводки (Бухгалтерия)', load: function () { return mr('accounting'); },
      cols: [{ key: 'number', label: 'Номер' }, { key: 'period_date', label: 'Период' }, { key: 'debit_code', label: 'Дт' },
             { key: 'credit_code', label: 'Кт' }, { key: 'amount', label: 'Сумма', num: true }, { key: 'memo', label: 'Примечание' }]
    },
    tasks: {
      name: 'Задачи', load: function () { return mr('tasks'); },
      cols: [{ key: 'title', label: 'Задача' }, { key: 'status', label: 'Статус' }, { key: 'priority', label: 'Приоритет' },
             { key: 'assignee_login', label: 'Исполнитель' }, { key: 'due_date', label: 'Срок' },
             { key: 'est_hours', label: 'План, ч', num: true }, { key: 'fact_hours', label: 'Факт, ч', num: true }]
    },
    crm_reminders: {
      name: 'CRM-напоминания', load: function () { return mr('crm_reminders'); },
      cols: [{ key: 'title', label: 'Напоминание' }, { key: 'due_at', label: 'Срок' }, { key: 'channel', label: 'Канал' },
             { key: 'status', label: 'Статус' }, { key: 'owner_login', label: 'Ответственный' }]
    }
  };
  /* Загрузка через универсальный отчёт по модулю (ветки W34 в app_module_report) */
  function mr(mod) {
    return rpc('app_module_report', { p_token: token, p_module: mod, p_from: null, p_to: null })
      .then(function (d) { return (d && d[0] && d[0].rows) || []; });
  }
  var NEW_DATASETS = ['tooling', 'mdm', 'plm', 'edo', 'kedo', 'eam', 'safety', 'holding', 'projbudget',
    'pmo', 'logistics', 'itsm', 'elearning', 'accounting', 'tasks', 'crm_reminders'];

  /* ---------------- Базовый отчёт ---------------- */
  function fillDs() {
    $('#ds').innerHTML = Object.keys(DATASETS).map(function (k) { return '<option value="' + k + '">' + DATASETS[k].name + '</option>'; }).join('');
  }
  function reportHtml() {
    return EX.reportDocument({
      brand: (me && me.tenant_name) || '3DMP Service',
      title: $('#title').value.trim() || (cur && cur.name) || 'Отчёт',
      subtitle: me && me.tenant_name ? me.tenant_name : '',
      meta: [{ k: 'Организация', v: (me && me.tenant_name) || '—' }, { k: 'Период', v: $('#period').value.trim() || '—' },
             { k: 'Дата', v: day(new Date().toISOString()) }, { k: 'Строк', v: rows.length }],
      sections: [{ title: (cur && cur.name) || 'Данные', columns: cols, rows: rows }],
      footer: 'Сформировано в 3DMP Service · ' + new Date().toLocaleString('ru-RU')
    });
  }
  function refreshPreview() { $('#preview').innerHTML = reportHtml(); }

  function loadCurrent() {
    clearMsg(); $('#preview').innerHTML = '<span class="note">Загрузка…</span>';
    cur = DATASETS[$('#ds').value]; cols = cur.cols;
    return cur.load().then(function (d) {
      rows = d || [];
      $('#info').textContent = 'Записей: ' + rows.length;
      refreshPreview();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); $('#preview').innerHTML = ''; });
  }

  $('#ds').addEventListener('change', loadCurrent);
  $('#title').addEventListener('input', refreshPreview);
  $('#period').addEventListener('input', refreshPreview);

  $$('[data-fmt]').forEach(function (b) {
    b.addEventListener('click', function () {
      if (!cur || !rows.length) { msg('Нет данных для выгрузки.', 'err'); return; }
      var base = (($('#title').value.trim() || cur.name) + '_' + day(new Date().toISOString())).replace(/[^\wа-яА-ЯёЁ\-]+/g, '_').slice(0, 50);
      var fmt = b.dataset.fmt, ok = true;
      if (fmt === 'csv') ok = EX.exportCsv(base, cols, rows);
      else if (fmt === 'xls') ok = EX.exportXls(base, cols, rows, $('#title').value.trim() || cur.name);
      else if (fmt === 'json') ok = EX.exportJson(base, rows);
      else if (fmt === 'doc') ok = EX.exportDoc(base, $('#title').value.trim() || cur.name, reportHtml());
      else if (fmt === 'pdf') ok = EX.exportPdf($('#title').value.trim() || cur.name, reportHtml());
      if (ok) { window.Auth.log('Экспорт ' + fmt.toUpperCase(), cur.name); ui.toast('Выгрузка ' + fmt.toUpperCase() + ' сформирована'); }
    });
  });

  function kpiReport() {
    return rpc('app_economics', { p_token: token }).then(function (r) {
      var e = (r && r[0]) || {};
      var M = function (v) { return (Number(v) || 0).toLocaleString('ru-RU'); };
      return Promise.all([
        rpc('app_order_list', { p_token: token }).catch(function () { return []; }),
        rpc('app_naryad_list', { p_token: token }).catch(function () { return []; })
      ]).then(function (rr) {
        return EX.reportDocument({
          brand: (me && me.tenant_name) || '3DMP Service',
          title: 'Сводный отчёт', subtitle: (me && me.tenant_name) || '',
          meta: [{ k: 'Дата', v: day(new Date().toISOString()) }],
          kpis: [{ label: 'Заявок', value: M(e.orders_total) }, { label: 'В работе', value: M(e.orders_open) },
                 { label: 'Брак (открыто)', value: M(e.defects_open) }, { label: 'План-часов', value: M(e.plan_hours) },
                 { label: 'Факт-часов', value: M(e.fact_hours) }, { label: 'Ниже минимума', value: M(e.low_stock) }],
          sections: [
            { title: 'Заявки', columns: [{ key: 'number', label: 'Номер' }, { key: 'title', label: 'Тема' }, { key: 'status', label: 'Статус' }], rows: rr[0] || [] },
            { title: 'Наряды', columns: [{ key: 'number', label: 'Наряд' }, { key: 'title', label: 'Название' }, { key: 'status', label: 'Статус' }, { key: 'plan_hours', label: 'План, ч', num: true }, { key: 'fact_hours', label: 'Факт, ч', num: true }], rows: rr[1] || [] }
          ],
          footer: 'Сформировано в 3DMP Service · ' + new Date().toLocaleString('ru-RU')
        });
      });
    });
  }
  $$('[data-kpi]').forEach(function (b) {
    b.addEventListener('click', function () {
      kpiReport().then(function (html) {
        var ok = (b.dataset.kpi === 'doc') ? EX.exportDoc('svodny_otchet_' + day(new Date().toISOString()), 'Сводный отчёт', html) : EX.exportPdf('Сводный отчёт', html);
        if (ok) window.Auth.log('Сводный отчёт', b.dataset.kpi.toUpperCase());
      }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
    });
  });

  /* ---------------- Конструктор отчётов ---------------- */
  function colLabel(ds, key) {
    var c = (DATASETS[ds] && DATASETS[ds].cols || []).filter(function (x) { return x.key === key; })[0];
    return c ? c.label : key;
  }
  function numCols(ds) { return (DATASETS[ds] && DATASETS[ds].cols || []).filter(function (c) { return c.num; }); }

  function loadDefs() {
    return rpc('app_report_defs_list', { p_token: token }).then(function (r) {
      defs = r || []; renderDefs();
    }).catch(function (e) { defMsg('Ошибка: ' + e.message, 'err'); });
  }
  function renderDefs() {
    $('#defsCnt').textContent = '(' + defs.length + ')';
    if (!defs.length) { $('#defs').innerHTML = '<span class="note">Сохранённых отчётов нет. Создайте первый — «＋ Новый отчёт».</span>'; return; }
    $('#defs').innerHTML = '<div class="tbl-wrap"><table class="tbl"><thead><tr>' +
      '<th>Название</th><th>Набор</th><th>Группировка</th><th>График</th><th>Автор</th><th>Действия</th></tr></thead><tbody>' +
      defs.map(function (d) {
        var dsName = (DATASETS[d.dataset] && DATASETS[d.dataset].name) || d.dataset;
        var colsArr = Array.isArray(d.columns) ? d.columns : [];
        var grp = d.group_by ? (colLabel(d.dataset, d.group_by) + ' · ' + (d.agg || 'count')) : '—';
        var shared = d.shared ? ' <span class="note">общий</span>' : '';
        return '<tr><td><b>' + esc(d.name) + '</b>' + shared + '<div class="note">Колонок: ' + colsArr.length + '</div></td>' +
          '<td>' + esc(dsName) + '</td><td class="muted">' + esc(grp) + '</td><td>' + esc(d.chart || 'table') + '</td>' +
          '<td class="muted">' + esc(d.created_login || '—') + '</td>' +
          '<td style="white-space:nowrap;"><button class="act" data-run="' + d.id + '">Запустить</button>' +
          '<button class="act" data-edit="' + d.id + '">Изменить</button><button class="act danger" data-del="' + d.id + '">Удалить</button></td></tr>';
      }).join('') + '</tbody></table></div>';
    $$('#defs [data-run]').forEach(function (b) { b.addEventListener('click', function () { runDef(defs.filter(function (x) { return x.id === b.dataset.run; })[0]); }); });
    $$('#defs [data-edit]').forEach(function (b) { b.addEventListener('click', function () { openDef(defs.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
    $$('#defs [data-del]').forEach(function (b) {
      b.addEventListener('click', function () {
        ui.confirmDialog('Удалить отчёт?', 'Удаление').then(function (ok) {
          if (!ok) return;
          rpc('app_report_def_delete', { p_token: token, p_id: b.dataset.del })
            .then(function (r) { var x = r && r[0]; defMsg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadDefs(); });
        });
      });
    });
  }

  function openDef(d) {
    d = d || {};
    var ds = d.dataset || 'orders';
    var f = d.filters || {};
    function colChecks() {
      return DATASETS[ds].cols.map(function (c) {
        var on = !d.columns && (c.key === 'number' || c.key === 'title' || c.key === 'status');
        if (d.columns) on = d.columns.indexOf(c.key) >= 0;
        return '<label style="display:block;font-size:.82rem;"><input type="checkbox" data-col="' + c.key + '"' + (on ? ' checked' : '') + '> ' + esc(c.label) + '</label>';
      }).join('');
    }
    function options(sel, list, cur2) { return list.map(function (o) { return '<option value="' + o.value + '"' + (String(cur2) === String(o.value) ? ' selected' : '') + '>' + esc(o.label) + '</option>'; }).join(''); }
    function numOpts() { return [{ value: '', label: '—' }].concat(numCols(ds).map(function (c) { return { value: c.key, label: c.label }; })); }
    var html =
      '<div class="form-grid">' +
        '<div class="field"><label>Название <span class="req">*</span></label><input id="rd_name" value="' + esc(d.name || '') + '"></div>' +
        '<div class="field"><label>Набор данных</label><select id="rd_ds">' + options('', Object.keys(DATASETS).map(function (k) { return { value: k, label: DATASETS[k].name }; }), ds) + '</select></div>' +
      '</div>' +
      '<div class="field"><label>Колонки</label><div id="rd_cols" style="max-height:180px;overflow:auto;border:1px solid var(--border);border-radius:10px;padding:8px 10px;">' + colChecks() + '</div></div>' +
      '<div class="form-grid">' +
        '<div class="field"><label>Группировка</label><select id="rd_group">' + options('', [{ value: '', label: '— без группировки —' }].concat(DATASETS[ds].cols.map(function (c) { return { value: c.key, label: c.label }; })), d.group_by || '') + '</select></div>' +
        '<div class="field"><label>Агрегация</label><select id="rd_agg">' + options('', [{ value: 'count', label: 'Количество' }, { value: 'sum', label: 'Сумма' }, { value: 'avg', label: 'Среднее' }], d.agg || 'count') + '</select></div>' +
        '<div class="field"><label>Показатель (для суммы/среднего)</label><select id="rd_measure">' + options('', numOpts(), (f.measure || '')) + '</select></div>' +
        '<div class="field"><label>График</label><select id="rd_chart">' + options('', [{ value: 'table', label: 'Таблица' }, { value: 'bar', label: 'Столбцы' }, { value: 'line', label: 'Линия' }], d.chart || 'table') + '</select></div>' +
      '</div>' +
      '<div class="form-grid">' +
        '<div class="field"><label>Фильтр: статус</label><input id="rd_status" value="' + esc(f.status || '') + '" placeholder="напр. open"></div>' +
        '<div class="field"><label>Поиск (любое поле)</label><input id="rd_q" value="' + esc(f.q || '') + '"></div>' +
        '<div class="field"><label>Дата с</label><input type="date" id="rd_from" value="' + esc(f.date_from || '') + '"></div>' +
        '<div class="field"><label>Дата по</label><input type="date" id="rd_to" value="' + esc(f.date_to || '') + '"></div>' +
      '</div>' +
      '<label class="note"><input type="checkbox" id="rd_shared"' + (d.shared ? ' checked' : '') + '> Общий отчёт организации</label>';

    ui.dialog({ title: d.id ? 'Отчёт: ' + (d.name || '') : 'Новый отчёт', body: html, html: true, okText: 'Сохранить', onOpen: function (back) {
      var dsSel = back.querySelector('#rd_ds');
      dsSel.addEventListener('change', function () {
        var nd = dsSel.value;
        back.querySelector('#rd_cols').innerHTML = DATASETS[nd].cols.map(function (c) {
          return '<label style="display:block;font-size:.82rem;"><input type="checkbox" data-col="' + c.key + '"' + (c.key === 'number' || c.key === 'title' || c.key === 'status' ? ' checked' : '') + '> ' + esc(c.label) + '</label>';
        }).join('');
        back.querySelector('#rd_group').innerHTML = options('', [{ value: '', label: '— без группировки —' }].concat(DATASETS[nd].cols.map(function (c) { return { value: c.key, label: c.label }; })), '');
        back.querySelector('#rd_measure').innerHTML = options('', [{ value: '', label: '—' }].concat(numCols(nd).map(function (c) { return { value: c.key, label: c.label }; })), '');
      });
    } }).then(function (ok) {
      if (!ok) return;
      var back = null;
      var nameEl = document.getElementById('rd_name');
      if (!nameEl) return;
      var payload = {
        p_token: token, p_id: d.id || null,
        p_name: nameEl.value,
        p_dataset: document.getElementById('rd_ds').value,
        p_columns: $$('#rd_cols [data-col]').filter(function (c) { return c.checked; }).map(function (c) { return c.dataset.col; }),
        p_filters: {
          status: document.getElementById('rd_status').value || null,
          q: document.getElementById('rd_q').value || null,
          date_from: document.getElementById('rd_from').value || null,
          date_to: document.getElementById('rd_to').value || null,
          measure: document.getElementById('rd_measure').value || null
        },
        p_group_by: document.getElementById('rd_group').value || null,
        p_agg: document.getElementById('rd_agg').value || 'count',
        p_chart: document.getElementById('rd_chart').value || 'table',
        p_shared: !!(document.getElementById('rd_shared') && document.getElementById('rd_shared').checked)
      };
      rpc('app_report_def_save', payload).then(function (r) {
        var x = r && r[0];
        if (!x || !x.ok) { defMsg(x ? x.message : 'Ошибка', 'err'); return; }
        window.Auth.log(d.id ? 'Отчёт изменён' : 'Отчёт создан', nameEl.value);
        defMsg(x.message, 'ok'); loadDefs();
      }).catch(function (e) { defMsg('Ошибка: ' + e.message, 'err'); });
    });
  }

  function rowDate(r) { return r.created_at || r.due_date || r.deadline || r.work_date || null; }
  function applyFilters(list, f) {
    f = f || {};
    return list.filter(function (r) {
      if (f.status && String(r.status || '').toLowerCase().indexOf(String(f.status).toLowerCase()) < 0) return false;
      if (f.q) { var s = JSON.stringify(r).toLowerCase(); if (s.indexOf(String(f.q).toLowerCase()) < 0) return false; }
      var dt = rowDate(r);
      if (f.date_from && (!dt || day(dt) < f.date_from)) return false;
      if (f.date_to && (!dt || day(dt) > f.date_to)) return false;
      return true;
    });
  }
  function aggregate(list, def) {
    if (!def.group_by) return { grouped: false, rows: list };
    var f = def.filters || {}, agg = def.agg || 'count', measure = f.measure;
    var acc = {};
    list.forEach(function (r) {
      var k = r[def.group_by] == null ? '—' : String(r[def.group_by]);
      if (!acc[k]) acc[k] = { n: 0, s: 0 };
      acc[k].n++; acc[k].s += measure ? (Number(r[measure]) || 0) : 0;
    });
    var out = Object.keys(acc).map(function (k) {
      var v = agg === 'count' ? acc[k].n : (agg === 'avg' ? (acc[k].n ? acc[k].s / acc[k].n : 0) : acc[k].s);
      return { group: k, value: Math.round(v * 100) / 100 };
    }).sort(function (a, b) { return b.value - a.value; });
    return { grouped: true, rows: out };
  }

  function runDef(d) {
    if (!d) return;
    var ds = DATASETS[d.dataset];
    if (!ds) { defMsg('Набор данных недоступен', 'err'); return; }
    d.filters = d.filters || {};
    defMsg('Запуск…', 'info');
    ds.load().then(function (list) {
      var filtered = applyFilters(list || [], d.filters);
      var res = aggregate(filtered, d);
      lastRun = { def: d, ds: ds, res: res };
      renderRun();
      defMsg('Отчёт «' + d.name + '»: строк ' + res.rows.length, 'ok');
    }).catch(function (e) { defMsg('Ошибка: ' + e.message, 'err'); });
  }

  function runHtml() {
    if (!lastRun) return '';
    var d = lastRun.def, res = lastRun.res;
    var dsName = (DATASETS[d.dataset] && DATASETS[d.dataset].name) || d.dataset;
    var cols, rows;
    if (res.grouped) {
      cols = [{ key: 'group', label: (colLabel(d.dataset, d.group_by)) }, { key: 'value', label: 'Значение (' + (d.agg || 'count') + ')', num: true }];
      rows = res.rows;
    } else {
      var keys = Array.isArray(d.columns) && d.columns.length ? d.columns : (DATASETS[d.dataset].cols || []).map(function (c) { return c.key; });
      cols = DATASETS[d.dataset].cols.filter(function (c) { return keys.indexOf(c.key) >= 0; });
      rows = res.rows;
    }
    var html = EX.reportDocument({
      brand: (me && me.tenant_name) || '3DMP Service',
      title: d.name, subtitle: dsName,
      meta: [{ k: 'Организация', v: (me && me.tenant_name) || '—' }, { k: 'Дата', v: day(new Date().toISOString()) }, { k: 'Строк', v: rows.length }],
      sections: [{ title: d.name, columns: cols, rows: rows }],
      footer: 'Конструктор отчётов · 3DMP Service · ' + new Date().toLocaleString('ru-RU')
    });
    return html;
  }

  function renderRun() {
    if (!lastRun) { $('#runCard').style.display = 'none'; return; }
    $('#runCard').style.display = '';
    $('#runTitle').textContent = 'Результат: ' + lastRun.def.name;
    var res = lastRun.res, d = lastRun.def;
    var chart = '';
    if (res.grouped && (d.chart === 'bar' || d.chart === 'line') && res.rows.length) {
      var maxV = Math.max.apply(null, res.rows.map(function (r) { return r.value; })) || 1;
      if (d.chart === 'line') chart = svgLine(res.rows.map(function (r) { return r.value; }), res.rows.map(function (r) { return r.group; }));
      else chart = '<div style="margin:10px 0;">' + res.rows.slice(0, 12).map(function (r) {
        return '<div style="display:flex;align-items:center;gap:8px;margin:4px 0;"><span style="min-width:160px;font-size:.82rem;">' + esc(r.group) + '</span>' +
          '<div class="bar" style="flex:1;"><i style="width:' + Math.round(r.value / maxV * 100) + '%"></i></div><b style="min-width:60px;text-align:right;">' + r.value + '</b></div>';
      }).join('') + '</div>';
    }
    $('#runPreview').innerHTML = chart + runHtml();
  }

  function svgLine(vals, labels) {
    if (!vals.length) return '';
    var w = 640, h = 180, pad = 30;
    var max = Math.max.apply(null, vals) || 1, min = 0;
    var step = vals.length > 1 ? (w - pad * 2) / (vals.length - 1) : 0;
    var pts = vals.map(function (v, i) { return [pad + i * step, h - pad - (v - min) / (max - min || 1) * (h - pad * 2)]; });
    var poly = pts.map(function (p) { return p[0].toFixed(1) + ',' + p[1].toFixed(1); }).join(' ');
    return '<svg viewBox="0 0 ' + w + ' ' + h + '" style="width:100%;max-width:640px;height:auto;">' +
      '<polyline fill="none" stroke="#10b981" stroke-width="2.5" points="' + poly + '"/>' +
      pts.map(function (p, i) { return '<circle cx="' + p[0].toFixed(1) + '" cy="' + p[1].toFixed(1) + '" r="3" fill="#10b981"><title>' + esc(labels[i]) + ': ' + vals[i] + '</title></circle>'; }).join('') +
      '</svg>';
  }

  $('#newDef').addEventListener('click', function () { openDef(null); });
  $$('[data-runfmt]').forEach(function (b) {
    b.addEventListener('click', function () {
      if (!lastRun) return;
      var base = ('report_' + lastRun.def.name + '_' + day(new Date().toISOString())).replace(/[^\wа-яА-ЯёЁ\-]+/g, '_').slice(0, 50);
      var ok = b.dataset.runfmt === 'csv' ? EX.exportCsv(base, runCsvCols(), runCsvRows()) : EX.exportPdf(lastRun.def.name, runHtml());
      if (ok) window.Auth.log('Отчёт ' + b.dataset.runfmt.toUpperCase(), lastRun.def.name);
    });
  });
  function runCsvCols() {
    var d = lastRun.def, res = lastRun.res;
    if (res.grouped) return [{ key: 'group', label: (colLabel(d.dataset, d.group_by)) }, { key: 'value', label: 'Значение', num: true }];
    var keys = Array.isArray(d.columns) && d.columns.length ? d.columns : DATASETS[d.dataset].cols.map(function (c) { return c.key; });
    return DATASETS[d.dataset].cols.filter(function (c) { return keys.indexOf(c.key) >= 0; });
  }
  function runCsvRows() { return lastRun.res.rows; }

  /* ---------- W34: дашборд по новым модулям ---------- */
  function renderDash() {
    var el = $('#dash'); if (!el) return;
    el.innerHTML = '<span class="note">Загрузка…</span>';
    Promise.all(NEW_DATASETS.map(function (k) {
      return mr(k).then(function (rows) { return { k: k, n: (rows || []).length }; }).catch(function () { return { k: k, n: 0 }; });
    })).then(function (list) {
      var max = Math.max.apply(null, list.map(function (x) { return x.n; })) || 1;
      var shown = list.filter(function (x) { return x.n > 0; }).sort(function (a, b) { return b.n - a.n; });
      el.innerHTML = shown.length ? shown.map(function (x) {
        return '<div style="display:flex;align-items:center;gap:8px;margin:4px 0;"><span style="min-width:220px;font-size:.82rem;">' + esc(DATASETS[x.k].name) + '</span>' +
          '<div class="bar" style="flex:1;"><i style="width:' + Math.round(x.n / max * 100) + '%"></i></div><b style="min-width:50px;text-align:right;">' + x.n + '</b></div>';
      }).join('') : '<span class="note">Данных по новым модулям нет.</span>';
    });
  }
  var dashBtn = $('#dashBtn'); if (dashBtn) dashBtn.addEventListener('click', renderDash);

  /* ---------- W41: дашборд по контурам + расписание рассылки ---------- */
  function loadKpis() {
    var el = $('#kpiContours'); if (!el) return; el.innerHTML = '<span class="note">Загрузка…</span>';
    rpc('app_dashboard_kpis', { p_token: token }).then(function (list) {
      var by = {}; (list || []).forEach(function (x) { (by[x.contour] = by[x.contour] || []).push(x); });
      var keys = Object.keys(by);
      el.innerHTML = keys.length ? keys.map(function (c) {
        return '<div style="margin:6px 0;"><b style="font-size:.82rem;">' + esc(c) + '</b> ' +
          '<span style="display:inline-flex;gap:6px;flex-wrap:wrap;margin-left:6px;">' +
          by[c].map(function (x) { return '<span class="badge" style="background:var(--accent-100);color:var(--accent-700);">' + esc(x.metric) + ': <b>' + esc(x.value) + '</b></span>'; }).join('') + '</span></div>';
      }).join('') : '<span class="note">Нет данных.</span>';
    }).catch(function (e) { el.innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
  }
  function scMsg(t, k) { var e = $('#scMsg'); if (e) { e.className = 'msg show ' + (k || 'info'); e.textContent = t; } }
  function loadSched() {
    var el = $('#schedList'); if (!el) return;
    rpc('app_report_schedules_list', { p_token: token }).then(function (list) {
      el.innerHTML = (list && list.length) ? '<table class="tbl"><thead><tr><th>Название</th><th>Модуль</th><th>Формат</th><th>Период</th><th>Канал</th><th>Следующий</th><th></th></tr></thead><tbody>' +
        list.map(function (s) {
          return '<tr><td>' + esc(s.name) + '</td><td>' + esc(s.module) + '</td><td>' + esc(s.format) + '</td><td>' + esc(s.period) + '</td><td>' + esc(s.channel) + '</td>' +
            '<td class="note">' + esc(String(s.next_run_at || '').substring(0, 16).replace('T', ' ')) + '</td>' +
            '<td><button class="act" data-sc-run="' + s.id + '">▶</button> <button class="act danger" data-sc-del="' + s.id + '">✕</button></td></tr>';
        }).join('') + '</tbody></table>' : '<span class="note">Расписаний нет.</span>';
      $$('#schedList [data-sc-run]').forEach(function (b) { b.addEventListener('click', function () { runSched(b.dataset.scRun); }); });
      $$('#schedList [data-sc-del]').forEach(function (b) { b.addEventListener('click', function () { delSched(b.dataset.scDel); }); });
    }).catch(function (e) { el.innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
  }
  function saveSched() {
    var name = $('#scName').value.trim(), mod = $('#scModule').value.trim();
    if (!name || !mod) { scMsg('Укажите название и модуль', 'err'); return; }
    rpc('app_report_schedule_save', {
      p_token: token, p_id: null, p_name: name, p_module: mod,
      p_format: $('#scFormat').value, p_period: $('#scPeriod').value, p_channel: $('#scChannel').value,
      p_target: $('#scTarget').value.trim() || null, p_enabled: true
    }).then(function (r) { var x = r && r[0]; scMsg((x && x.message) || 'Готово', x && x.ok === false ? 'err' : 'ok'); if (x && x.ok) { $('#scName').value = ''; loadSched(); } });
  }
  function runSched(id) { rpc('app_report_schedule_run', { p_token: token, p_id: id }).then(function (r) { var x = r && r[0]; scMsg((x && x.message) || 'Готово', x && x.ok === false ? 'err' : 'ok'); loadSched(); }); }
  function delSched(id) { rpc('app_report_schedule_delete', { p_token: token, p_id: id }).then(function () { scMsg('Расписание удалено', 'ok'); loadSched(); }); }
  function runDue() { rpc('app_report_run_due', { p_token: token }).then(function (r) { var x = r && r[0]; scMsg((x && x.message) || 'Готово', x && x.ok === false ? 'err' : 'ok'); loadSched(); }); }
  var kb = $('#kpiBtn'); if (kb) kb.addEventListener('click', loadKpis);
  var ss = $('#scSave'); if (ss) ss.addEventListener('click', saveSched);
  var sd = $('#scRunDue'); if (sd) sd.addEventListener('click', runDue);

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    fillDs(); loadCurrent(); loadDefs();
    if ($('#dash')) renderDash();
    if ($('#kpiContours')) loadKpis();
    if ($('#schedList')) loadSched();
  });
})();
