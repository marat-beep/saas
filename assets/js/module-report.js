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
    number: 'Номер', customer: 'Заказчик', title: 'Тема', priority: 'Приоритет', reported_at: 'Создана'
  };
  var order = ['name', 'number', 'title', 'customer', 'category', 'kind', 'model', 'code', 'machine', 'metric', 'value', 'unit', 'qty', 'min_qty', 'price', 'inn', 'contact', 'phone', 'email', 'address', 'head', 'dept', 'status', 'priority', 'rating', 'active', 'reported_at', 'ts', 'question', 'tags'];
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
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bind); else bind();
  g.AppModuleReport = { run: run, bind: bind };
})(window);
