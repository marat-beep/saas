/* ============================================================
   3DMP Service · движок выгрузок (window.AppExport)
   PDF (печать) / DOC / CSV / JSON / таблица + конструктор отчёта.
   Без зависимостей. Используется приложением apps/reports/ и другими модулями.
   ============================================================ */
(function (g) {
  'use strict';

  function esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
  function csvCell(v) { v = v == null ? '' : String(v); return /[";\n\r]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; }

  function csv(columns, rows) {
    var head = (columns || []).map(function (c) { return csvCell(c.label); }).join(';');
    var body = (rows || []).map(function (r) { return columns.map(function (c) { return csvCell(typeof c.value === 'function' ? c.value(r) : r[c.key]); }).join(';'); }).join('\r\n');
    return '\ufeff' + head + '\r\n' + body;
  }
  function json(obj) { return JSON.stringify(obj, null, 2); }
  function xls(columns, rows, title) {
    var cols = columns || [];
    return '<html xmlns:x="urn:schemas-microsoft-com:office:excel"><head><meta charset="utf-8">' +
      '<!--[if gte mso 9]><xml><x:ExcelWorkbook><x:ExcelWorksheets><x:ExcelWorksheet><x:Name>Отчёт</x:Name>' +
      '<x:WorksheetOptions><x:DisplayGridlines/></x:WorksheetOptions></x:ExcelWorksheet></x:ExcelWorksheets></x:ExcelWorkbook></xml><![endif]-->' +
      '</head><body>' + (title ? '<table><tr><td colspan="' + Math.max(cols.length, 1) + '"><b>' + esc(title) + '</b></td></tr></table>' : '') +
      tableHtml(columns, rows) + '</body></html>';
  }
  function tableHtml(columns, rows) {
    var cols = columns || [];
    return '<table><thead><tr>' + cols.map(function (c) { return '<th>' + esc(c.label) + '</th>'; }).join('') + '</tr></thead><tbody>' +
      (rows || []).map(function (r) { return '<tr>' + cols.map(function (c) { var v = typeof c.value === 'function' ? c.value(r) : r[c.key]; return '<td' + (c.num ? ' class="num"' : '') + '>' + esc(v) + '</td>'; }).join('') + '</tr>'; }).join('') + '</tbody></table>';
  }

  function baseCss() {
    return 'body{font-family:Arial,sans-serif;color:#0f172a;font-size:12px;line-height:1.5;padding:22px;}h1{font-size:16px;text-align:center;margin:0;}' +
      '.rpt-sub{text-align:center;color:#475569;font-size:11px;margin:4px 0 14px;}.rpt-meta{display:flex;flex-wrap:wrap;gap:6px 18px;margin:0 0 14px;font-size:11px;}' +
      '.rpt-meta span{color:#64748b;}.rpt-meta b{color:#0f172a;}.rpt-kpis{display:flex;flex-wrap:wrap;gap:10px;margin:0 0 16px;}' +
      '.rpt-kpi{border:1px solid #cbd5e1;border-radius:8px;padding:8px 12px;min-width:120px;}.rpt-kpi b{display:block;font-size:15px;}' +
      '.rpt-kpi span{font-size:10px;color:#64748b;text-transform:uppercase;letter-spacing:.4px;}.rpt-sec{margin:14px 0;}' +
      '.rpt-sec h2{font-size:12px;margin:0 0 6px;border-bottom:2px solid #0f172a;padding-bottom:3px;}table{width:100%;border-collapse:collapse;margin:6px 0 10px;}' +
      'th,td{border:1px solid #cbd5e1;padding:5px 7px;text-align:left;font-size:11px;}th{background:#f1f5f9;}td.num,th.num{text-align:right;}' +
      '.rpt-sign{margin-top:22px;display:flex;justify-content:space-between;font-size:11px;}.rpt-foot{margin-top:24px;border-top:1px solid #e2e8f0;padding-top:8px;color:#94a3b8;font-size:10px;text-align:center;}';
  }
  function docBody(title, bodyHtml) {
    return '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns="http://www.w3.org/TR/REC-html40">' +
      '<head><meta charset="utf-8"><title>' + esc(title || 'Документ') + '</title><style>' + baseCss() + '</style></head><body>' + (bodyHtml || '') + '</body></html>';
  }
  function download(filename, content, mime) {
    try {
      var blob = new Blob([content], { type: mime || 'text/plain;charset=utf-8' });
      var url = URL.createObjectURL(blob); var a = document.createElement('a');
      a.href = url; a.download = filename; document.body.appendChild(a); a.click();
      setTimeout(function () { if (a.parentNode) a.parentNode.removeChild(a); URL.revokeObjectURL(url); }, 400);
      return true;
    } catch (e) { if (g.AppUI && AppUI.toast) AppUI.toast('Не удалось сохранить файл'); return false; }
  }
  function printDoc(title, bodyHtml) {
    var w = g.open('', '_blank');
    if (!w) { if (g.AppUI && AppUI.toast) AppUI.toast('Разрешите всплывающие окна'); return false; }
    w.document.write(docBody(title, bodyHtml)); w.document.close(); w.focus();
    setTimeout(function () { try { w.print(); } catch (e) {} }, 300);
    return true;
  }
  // opts: {brand,title,subtitle,meta:[{k,v}],kpis:[{label,value}],sections:[{title,text,columns,rows}],sign:[a,b],footer}
  function reportDocument(opts) {
    opts = opts || {}; var h = '';
    if (opts.brand) h += '<h1>' + esc(opts.brand) + '</h1>';
    if (opts.title) h += '<div class="rpt-sub"><b>' + esc(opts.title) + '</b>' + (opts.subtitle ? ' · ' + esc(opts.subtitle) : '') + '</div>';
    if (opts.meta && opts.meta.length) h += '<div class="rpt-meta">' + opts.meta.map(function (m) { return '<span>' + esc(m.k) + ': <b>' + esc(m.v) + '</b></span>'; }).join('') + '</div>';
    if (opts.kpis && opts.kpis.length) h += '<div class="rpt-kpis">' + opts.kpis.map(function (k) { return '<div class="rpt-kpi"><b>' + esc(k.value) + '</b><span>' + esc(k.label) + '</span></div>'; }).join('') + '</div>';
    (opts.sections || []).forEach(function (s) {
      h += '<div class="rpt-sec">' + (s.title ? '<h2>' + esc(s.title) + '</h2>' : '') + (s.text ? '<p>' + esc(s.text) + '</p>' : '') + (s.columns && s.rows ? tableHtml(s.columns, s.rows) : '') + '</div>';
    });
    if (opts.sign) h += '<div class="rpt-sign"><span>' + esc(opts.sign[0] || '') + ' ____________</span><span>' + esc(opts.sign[1] || '') + ' ____________</span></div>';
    if (opts.footer) h += '<div class="rpt-foot">' + esc(opts.footer) + '</div>';
    return h;
  }

  g.AppExport = {
    csv: csv, json: json, xls: xls, tableHtml: tableHtml, baseCss: baseCss, docBody: docBody, download: download, reportDocument: reportDocument,
    exportCsv: function (f, cols, rows) { return download(f + '.csv', csv(cols, rows), 'text/csv;charset=utf-8'); },
    exportJson: function (f, data) { return download(f + '.json', json(data), 'application/json;charset=utf-8'); },
    exportXls: function (f, cols, rows, title) { return download(f + '.xls', xls(cols, rows, title), 'application/vnd.ms-excel;charset=utf-8'); },
    exportDoc: function (f, title, html) { return download(f + '.doc', docBody(title, html), 'application/msword'); },
    exportPdf: function (title, html) { return printDoc(title, html); }
  };
})(window);
