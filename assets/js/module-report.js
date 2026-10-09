/* ============================================================
   3DMP Service · module-report.js — универсальный отчёт по модулю.
   Кнопки с атрибутом data-report="<module>" вызывают app_module_report
   и выгружают PDF/CSV (AppExport, подгружается лениво). Требует SB/Auth.
   ============================================================ */
(function (g) {
  'use strict';
  var s = document.currentScript || (function () { var a = document.getElementsByTagName('script'); return a[a.length - 1]; })();
  var src = (s && s.src) || ''; var i = src.indexOf('assets/js/module-report.js'); var ROOT = i >= 0 ? src.slice(0, i) : '';
  var LABELS = {
    name: 'Название', inn: 'ИНН', contact: 'Контакт', phone: 'Телефон', email: 'E-mail', address: 'Адрес',
    category: 'Категория', status: 'Статус', rating: 'Рейтинг', code: 'Код', head: 'Руководитель', active: 'Активен',
    kind: 'Тип', model: 'Модель', dept: 'Подразделение', unit: 'Ед.', qty: 'Кол-во', min_qty: 'Минимум', price: 'Цена',
    question: 'Вопрос', tags: 'Теги', machine: 'Станок', metric: 'Метрика', value: 'Значение', ts: 'Время',
    number: 'Номер', customer: 'Заказчик', title: 'Тема', priority: 'Приоритет', reported_at: 'Создана',
    reg_number: 'Рег. №', doc_type: 'Тип документа', correspondent: 'Корреспондент', responsible_login: 'Ответственный',
    employee_login: 'Сотрудник', item_type: 'Тип', grp: 'Группа', source: 'Источник', version: 'Версия', state: 'Состояние',
    currency: 'Валюта', direction: 'Направление', counterparty: 'Контрагент', cargo: 'Груз', from_loc: 'Откуда', to_loc: 'Куда',
    pickup_date: 'Погрузка', deliver_date: 'Выгрузка', cost: 'Стоимость', weight: 'Вес', debit_code: 'Дт', credit_code: 'Кт',
    amount: 'Сумма', memo: 'Примечание', est_hours: 'План, ч', fact_hours: 'Факт, ч', channel: 'Канал', owner_login: 'Ответственный',
    equipment: 'Оборудование', severity: 'Критичность', location: 'Место', used_min: 'Наработка, мин', resource_min: 'Ресурс, мин',
    holder_login: 'У кого', serial: 'Серийный №', period_date: 'Период', due_date: 'Срок', due_at: 'Срок',
    program_no: 'УП', program_time_min: 'Время, мин', result: 'Результат', share: 'Доля', sign: 'Подпись', signed_at: 'Подписано'
  };
  var order = ['number', 'reg_number', 'code', 'serial', 'name', 'title', 'customer', 'counterparty', 'correspondent',
    'doc_type', 'item_type', 'category', 'kind', 'grp', 'model', 'machine', 'equipment', 'metric', 'value', 'unit', 'qty',
    'min_qty', 'weight', 'price', 'cost', 'amount', 'debit_code', 'credit_code', 'resource_min', 'used_min', 'est_hours',
    'fact_hours', 'hours', 'from_loc', 'to_loc', 'location', 'dept', 'direction', 'channel', 'version', 'state', 'currency',
    'share', 'result', 'status', 'priority', 'severity', 'rating', 'risk', 'active', 'assignee_login', 'responsible_login',
    'employee_login', 'holder_login', 'owner_login', 'reported_at', 'period_date', 'due_date', 'due_at', 'pickup_date',
    'deliver_date', 'signed_at', 'created_at', 'ts', 'memo', 'note', 'description', 'question', 'tags',
    'inn', 'contact', 'phone', 'email', 'address', 'head'];
  function qsa(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
  function toast(t) { if (g.AppUI && g.AppUI.toast) g.AppUI.toast(t); else alert(t); }
  function ensureExport(cb) {
    if (g.AppExport) return cb();
    var sc = document.createElement('script'); sc.src = ROOT + 'assets/js/export.js?v=1';
    sc.onload = cb; sc.onerror = function () { toast('Экспорт недоступен'); };
    document.head.appendChild(sc);
  }
  function cols(rows) {
    var keys = Object.keys(rows[0] || {});
    keys.sort(function (a, b) { var ia = order.indexOf(a), ib = order.indexOf(b); return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib); });
    return keys.map(function (k) { return { key: k, label: LABELS[k] || k }; });
  }
  function run(module, title, fmt) {
    if (!g.SB || !g.Auth || !g.Auth.token()) { toast('Требуется вход'); return; }
    g.SB.rpc('app_module_report', { p_token: g.Auth.token(), p_module: module, p_from: null, p_to: null }).then(function (r) {
      if (r.error) { toast('Ошибка: ' + r.error.message); return; }
      var rows = (r.data && r.data[0] && r.data[0].rows) || [];
      if (!rows.length) { toast('Нет данных'); return; }
      var c = cols(rows);
      if (fmt === 'csv') { ensureExport(function () { g.AppExport.exportCsv('report-' + module, c, rows); }); return; }
      ensureExport(function () {
        var html = g.AppExport.reportDocument({
          brand: '3DMP Service', title: title || ('Отчёт: ' + module), subtitle: new Date().toLocaleDateString('ru-RU'),
          kpis: [{ label: 'Записей', value: rows.length }],
          sections: [{ title: 'Данные', columns: c, rows: rows }],
          footer: '3DMP Service · ' + module
        });
        g.AppExport.exportPdf(title || module, html);
      });
    });
  }
  function bind() {
    qsa('[data-report]').forEach(function (b) {
      if (b.__mrBound) return; b.__mrBound = true;
      b.addEventListener('click', function () { run(b.dataset.report, b.dataset.title, b.dataset.fmt); });
    });
  }
  /* W34: если на странице нет явных кнопок отчёта — добавим их сами
     (модуль определяется по URL apps/<id>/). */
  function autoInject() {
    if (qsa('[data-report]').length) return;
    var m = (location.pathname.match(/\/apps\/([\w-]+)\//) || [])[1];
    if (!m) return;
    var main = document.querySelector('main.wrap') || document.querySelector('main');
    if (!main) return;
    var box = document.createElement('div');
    box.className = 'sv-actions'; box.style.cssText = 'margin:0 0 12px;';
    box.innerHTML = '<button class="btn secondary" type="button" data-report="' + m + '">📄 Отчёт PDF</button>' +
      '<button class="btn secondary" type="button" data-report="' + m + '" data-fmt="csv">📊 CSV</button>';
    main.insertBefore(box, main.firstChild);
  }
  function start() { autoInject(); bind(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
  g.AppModuleReport = { run: run, bind: bind };
})(window);
