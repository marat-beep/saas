/* ============================================================
   3DMP · Центр экспорта — единый движок выгрузок
   Форматы: PDF (печать) / DOC / CSV / JSON / ICS + конструктор отчётов.
   Без внешних зависимостей, работает офлайн. Доступ: window.AppExport
   ============================================================ */
(function (global) {
  'use strict';

  function pad(n, l) { n = String(n); l = l || 2; while (n.length < l) n = '0' + n; return n; }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  /* ---------- CSV ---------- */
  function csvCell(v) {
    v = v == null ? '' : String(v);
    if (/[";\n\r]/.test(v)) return '"' + v.replace(/"/g, '""') + '"';
    return v;
  }
  function csv(columns, rows) {
    var cols = columns || [];
    var head = cols.map(function (c) { return csvCell(c.label); }).join(';');
    var body = (rows || []).map(function (r) {
      return cols.map(function (c) { return csvCell(typeof c.value === 'function' ? c.value(r) : r[c.key]); }).join(';');
    }).join('\r\n');
    return '\ufeff' + head + '\r\n' + body;
  }

  /* ---------- JSON ---------- */
  function json(obj) { return JSON.stringify(obj, null, 2); }

  /* ---------- ICS (календарь iCalendar) ---------- */
  function icsDate(d) {
    if (d instanceof Date) return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate());
    var s = String(d || '');
    var m = s.match(/(\d{4})-(\d{2})-(\d{2})/);
    if (m) return m[1] + m[2] + m[3];
    var ru = s.match(/(\d{2})\.(\d{2})\.(\d{4})/);
    if (ru) return ru[3] + ru[2] + ru[1];
    var n = new Date(); return n.getFullYear() + pad(n.getMonth() + 1) + pad(n.getDate());
  }
  function icsStamp() {
    var d = new Date();
    return d.getUTCFullYear() + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate()) + 'T' +
      pad(d.getUTCHours()) + pad(d.getUTCMinutes()) + pad(d.getUTCSeconds()) + 'Z';
  }
  function icsEsc(s) { return String(s == null ? '' : s).replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n'); }
  function ics(events, calName) {
    var lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//3DMP//Export Center//RU', 'CALSCALE:GREGORIAN'];
    if (calName) lines.push('X-WR-CALNAME:' + icsEsc(calName));
    (events || []).forEach(function (e, i) {
      lines.push('BEGIN:VEVENT');
      lines.push('UID:3dmp-' + Date.now() + '-' + i + '@3dmp.local');
      lines.push('DTSTAMP:' + icsStamp());
      lines.push('DTSTART;VALUE=DATE:' + icsDate(e.date));
      if (e.end) lines.push('DTEND;VALUE=DATE:' + icsDate(e.end));
      if (e.title) lines.push('SUMMARY:' + icsEsc(e.title));
      if (e.desc) lines.push('DESCRIPTION:' + icsEsc(e.desc));
      if (e.location) lines.push('LOCATION:' + icsEsc(e.location));
      lines.push('END:VEVENT');
    });
    lines.push('END:VCALENDAR');
    return lines.join('\r\n');
  }

  /* ---------- HTML-таблица ---------- */
  function tableHtml(columns, rows) {
    var cols = columns || [];
    return '<table><thead><tr>' + cols.map(function (c) { return '<th>' + esc(c.label) + '</th>'; }).join('') + '</tr></thead><tbody>' +
      (rows || []).map(function (r) {
        return '<tr>' + cols.map(function (c) {
          var v = typeof c.value === 'function' ? c.value(r) : r[c.key];
          return '<td' + (c.num ? ' class="num"' : '') + '>' + esc(v) + '</td>';
        }).join('') + '</tr>';
      }).join('') + '</tbody></table>';
  }

  /* ---------- Базовые стили документов ---------- */
  function baseCss() {
    return 'body{font-family:Arial,Helvetica,sans-serif;color:#0f172a;font-size:12px;line-height:1.5;padding:22px;}' +
      'h1{font-size:16px;text-align:center;margin:0;}' +
      '.rpt-sub{text-align:center;color:#475569;font-size:11px;margin:4px 0 14px;}' +
      '.rpt-meta{display:flex;flex-wrap:wrap;gap:6px 18px;margin:0 0 14px;font-size:11px;}' +
      '.rpt-meta span{color:#64748b;} .rpt-meta b{color:#0f172a;}' +
      '.rpt-kpis{display:flex;flex-wrap:wrap;gap:10px;margin:0 0 16px;}' +
      '.rpt-kpi{border:1px solid #cbd5e1;border-radius:8px;padding:8px 12px;min-width:120px;}' +
      '.rpt-kpi b{display:block;font-size:15px;} .rpt-kpi span{font-size:10px;color:#64748b;text-transform:uppercase;letter-spacing:.4px;}' +
      '.rpt-sec{margin:14px 0;}' +
      '.rpt-sec h2{font-size:12px;margin:0 0 6px;border-bottom:2px solid #0f172a;padding-bottom:3px;}' +
      '.rpt-sec p{margin:0 0 8px;}' +
      'table{width:100%;border-collapse:collapse;margin:6px 0 10px;}' +
      'th,td{border:1px solid #cbd5e1;padding:5px 7px;text-align:left;font-size:11px;}' +
      'th{background:#f1f5f9;} td.num,th.num{text-align:right;}' +
      '.rpt-note{color:#64748b;font-size:10px;margin-top:4px;}' +
      '.rpt-sign{margin-top:22px;display:flex;justify-content:space-between;font-size:11px;}' +
      '.rpt-foot{margin-top:24px;border-top:1px solid #e2e8f0;padding-top:8px;color:#94a3b8;font-size:10px;text-align:center;}';
  }

  /* ---------- Документ (Word) ---------- */
  function docBody(title, bodyHtml, opts) {
    opts = opts || {};
    return '<html xmlns:o="urn:schemas-microsoft-com:office:office" ' +
      'xmlns:w="urn:schemas-microsoft-com:office:word" xmlns="http://www.w3.org/TR/REC-html40">' +
      '<head><meta charset="utf-8"><title>' + esc(title || 'Документ') + '</title>' +
      '<style>' + baseCss() + '</style></head><body>' + (opts.header || '') + (bodyHtml || '') + (opts.footer || '') + '</body></html>';
  }

  /* ---------- PDF через печать ---------- */
  function printDoc(title, bodyHtml, opts) {
    opts = opts || {};
    var w = global.open ? global.open('', '_blank') : null;
    if (!w) { if (global.App && App.toast) App.toast('Разрешите всплывающие окна'); return false; }
    w.document.write(docBody(title, bodyHtml, opts));
    w.document.close(); w.focus();
    setTimeout(function () { try { w.print(); } catch (e) {} }, 300);
    return true;
  }

  /* ---------- Скачивание файла ---------- */
  function download(filename, content, mime) {
    try {
      var blob = new Blob([content], { type: mime || 'text/plain;charset=utf-8' });
      var url = URL.createObjectURL(blob);
      var a = document.createElement('a');
      a.href = url; a.download = filename;
      document.body.appendChild(a); a.click();
      setTimeout(function () { if (a.parentNode) a.parentNode.removeChild(a); URL.revokeObjectURL(url); }, 400);
      return true;
    } catch (e) {
      if (global.App && App.toast) App.toast('Не удалось сохранить файл');
      return false;
    }
  }

  /* ---------- Конструктор отчёта → HTML ---------- */
  // opts: {brand, title, subtitle, meta:[{k,v}], kpis:[{label,value}], sections:[{title, text, columns, rows}], note, sign, footer}
  function reportDocument(opts) {
    opts = opts || {};
    var h = '';
    if (opts.brand) h += '<h1>' + esc(opts.brand) + '</h1>';
    if (opts.title) h += '<div class="rpt-sub"><b>' + esc(opts.title) + '</b>' + (opts.subtitle ? ' · ' + esc(opts.subtitle) : '') + '</div>';
    if (opts.meta && opts.meta.length) {
      h += '<div class="rpt-meta">' + opts.meta.map(function (m) {
        return '<span>' + esc(m.k) + ': <b>' + esc(m.v) + '</b></span>';
      }).join('') + '</div>';
    }
    if (opts.kpis && opts.kpis.length) {
      h += '<div class="rpt-kpis">' + opts.kpis.map(function (k) {
        return '<div class="rpt-kpi"><b>' + esc(k.value) + '</b><span>' + esc(k.label) + '</span></div>';
      }).join('') + '</div>';
    }
    (opts.sections || []).forEach(function (s) {
      h += '<div class="rpt-sec">';
      if (s.title) h += '<h2>' + esc(s.title) + '</h2>';
      if (s.text) h += '<p>' + esc(s.text) + '</p>';
      if (s.columns && s.rows) h += tableHtml(s.columns, s.rows);
      h += '</div>';
    });
    if (opts.note) h += '<div class="rpt-note">' + esc(opts.note) + '</div>';
    if (opts.sign) h += '<div class="rpt-sign"><span>' + esc(opts.sign[0] || '') + ' ____________</span><span>' + esc(opts.sign[1] || '') + ' ____________</span></div>';
    if (opts.footer) h += '<div class="rpt-foot">' + esc(opts.footer) + '</div>';
    return h;
  }

  var AppExport = {
    // низкоуровневые преобразования
    csv: csv, json: json, ics: ics, tableHtml: tableHtml,
    docBody: docBody, baseCss: baseCss, reportDocument: reportDocument,
    // сохранение
    download: download,
    exportCsv: function (filename, columns, rows) {
      return download(filename + '.csv', csv(columns, rows), 'text/csv;charset=utf-8');
    },
    exportJson: function (filename, data) {
      return download(filename + '.json', json(data), 'application/json;charset=utf-8');
    },
    exportIcs: function (filename, events, calName) {
      return download(filename + '.ics', ics(events, calName), 'text/calendar;charset=utf-8');
    },
    exportDoc: function (filename, title, bodyHtml, opts) {
      return download(filename + '.doc', docBody(title, bodyHtml, opts), 'application/msword');
    },
    exportPdf: function (title, bodyHtml, opts) {
      return printDoc(title, bodyHtml, opts);
    }
  };

  global.AppExport = AppExport;
})(window);
