/* ============================================================
   3DMP Service · UI-утилиты (window.AppUI)
   ============================================================ */
(function (g) {
  'use strict';

  function qs(sel, root) { return (root || document).querySelector(sel); }
  function qsa(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function toastWrap() {
    var w = document.querySelector('.toast-wrap');
    if (!w) { w = document.createElement('div'); w.className = 'toast-wrap'; document.body.appendChild(w); }
    return w;
  }
  // kind: '' | 'ok' | 'err'
  function toast(message, kind) {
    var el = document.createElement('div');
    el.className = 'toast' + (kind ? ' ' + kind : '');
    el.textContent = message;
    toastWrap().appendChild(el);
    requestAnimationFrame(function () { el.classList.add('show'); });
    setTimeout(function () {
      el.classList.remove('show');
      setTimeout(function () { el.remove(); }, 240);
    }, 2600);
  }

  // Модальное окно: opts = { title, body(HTML|text), okText, cancelText, danger, hideCancel, size,
  //                          onOpen(back), validate(back)->boolean }
  // Возвращает Promise<boolean> (true — подтверждено). DOM живёт ещё ~160 мс после resolve.
  function dialog(opts) {
    opts = opts || {};
    return new Promise(function (resolve) {
      var back = document.createElement('div');
      back.className = 'modal-backdrop';
      var foot = opts.hideCancel
        ? '<button class="btn" data-ok>' + esc(opts.okText || 'ОК') + '</button>'
        : '<button class="btn secondary" data-cancel>' + esc(opts.cancelText || 'Отмена') + '</button>' +
          '<button class="btn' + (opts.danger ? '' : '') + '" data-ok>' + esc(opts.okText || 'ОК') + '</button>';
      back.innerHTML =
        '<div class="modal' + (opts.size ? ' ' + esc(opts.size) : '') + '" role="dialog" aria-modal="true">' +
          (opts.title ? '<div class="modal-head">' + esc(opts.title) + '</div>' : '') +
          '<div class="modal-body">' + (opts.html ? opts.body : esc(opts.body || '')) + '</div>' +
          '<div class="modal-foot">' + foot + '</div>' +
        '</div>';
      document.body.appendChild(back);
      requestAnimationFrame(function () { back.classList.add('show'); });
      if (opts.onOpen) opts.onOpen(back);
      function close(val) {
        back.classList.remove('show');
        setTimeout(function () { back.remove(); }, 160);
        document.removeEventListener('keydown', onKey);
        resolve(val);
      }
      function onKey(e) { if (e.key === 'Escape') close(false); }
      document.addEventListener('keydown', onKey);
      back.addEventListener('click', function (e) {
        if (e.target === back) close(false);
        if (e.target.closest('[data-ok]')) { if (opts.validate && !opts.validate(back)) return; close(true); }
        if (e.target.closest('[data-cancel]')) close(false);
      });
    });
  }

  // Модальная форма: opts = { title, fields:[{name,label,type,required,options,placeholder,hint,rows,value}],
  //                          values, okText, cancelText, size, html }
  // Возвращает Promise<object|null> (значения полей или null при отмене).
  function formDialog(opts) {
    opts = opts || {};
    var fields = opts.fields || [], values = opts.values || {};
    var html = '<div class="form-grid">' + fields.map(function (f) {
      var id = 'fd_' + f.name, v = values[f.name] != null ? values[f.name] : (f.value != null ? f.value : '');
      var h = '<div class="field">';
      h += '<label>' + esc(f.label) + (f.required ? ' <span class="req">*</span>' : '') + '</label>';
      if (f.type === 'textarea') h += '<textarea id="' + id + '" rows="' + (f.rows || 3) + '">' + esc(v) + '</textarea>';
      else if (f.type === 'select') h += '<select id="' + id + '">' + (f.options || []).map(function (o) {
        var ov = (o && typeof o === 'object') ? o.value : o, ol = (o && typeof o === 'object') ? o.label : o;
        return '<option value="' + esc(ov) + '"' + (String(v) === String(ov) ? ' selected' : '') + '>' + esc(ol) + '</option>';
      }).join('') + '</select>';
      else if (f.type === 'checkbox') h += '<label class="note"><input type="checkbox" id="' + id + '"' + (v ? ' checked' : '') + '> ' + esc(f.hint || 'да') + '</label>';
      else h += '<input type="' + esc(f.type || 'text') + '" id="' + id + '" value="' + esc(v) + '"' + (f.placeholder ? ' placeholder="' + esc(f.placeholder) + '"' : '') + '>';
      if (f.hint && f.type !== 'checkbox') h += '<span class="hint">' + esc(f.hint) + '</span>';
      return h + '</div>';
    }).join('') + '</div>' + (opts.html || '');
    return dialog({
      title: opts.title, body: html, html: true, okText: opts.okText, cancelText: opts.cancelText, size: opts.size,
      validate: function (back) {
        var miss = null;
        fields.forEach(function (f) {
          if (!f.required) return;
          var el = back.querySelector('#fd_' + f.name);
          var val = el ? (el.type === 'checkbox' ? (el.checked ? '1' : '') : el.value) : '';
          if (!String(val).trim()) miss = f.label;
        });
        var err = back.querySelector('.fd-err');
        if (miss) {
          if (!err) { err = document.createElement('div'); err.className = 'msg err fd-err show'; (back.querySelector('.modal-body') || back).appendChild(err); }
          err.textContent = 'Заполните: ' + miss; return false;
        }
        if (err) err.remove();
        return true;
      }
    }).then(function (ok) {
      if (!ok) return null;
      var out = {};
      fields.forEach(function (f) {
        var el = document.getElementById('fd_' + f.name);
        out[f.name] = el ? (el.type === 'checkbox' ? (el.checked ? 'да' : '') : el.value) : '';
      });
      return out;
    });
  }

  function confirmDialog(text, title) {
    return dialog({ title: title || 'Подтверждение', body: text, okText: 'Подтвердить', danger: true });
  }

  function fmtDate(ts) {
    if (!ts) return '—';
    var d = new Date(ts);
    if (isNaN(d.getTime())) return String(ts);
    return d.toLocaleDateString('ru-RU');
  }

  /* Кнопка «Наверх» (на всех страницах) */
  (function () {
    function init() {
      if (document.querySelector('.to-top')) return;
      var b = document.createElement('button');
      b.className = 'to-top'; b.type = 'button'; b.title = 'Наверх'; b.setAttribute('aria-label', 'Наверх'); b.textContent = '↑';
      b.addEventListener('click', function () { window.scrollTo({ top: 0, behavior: 'smooth' }); });
      document.body.appendChild(b);
      window.addEventListener('scroll', function () { b.classList.toggle('show', window.scrollY > 300); }, { passive: true });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
  })();

  // Универсальный клиентский поиск по списку: скрывает строки/карточки, не содержащие запрос.
  // Использование: AppUI.quickSearch('q', 'list') — input #q фильтрует содержимое #list.
  function quickSearch(input, box, rowSel) {
    var inp = typeof input === 'string' ? document.getElementById(input) : input;
    var host = typeof box === 'string' ? document.getElementById(box) : box;
    if (!inp || !host) return null;
    function rowsOf() {
      if (rowSel) return qsa(rowSel, host);
      var tr = qsa('tbody tr', host); if (tr.length) return tr;
      var oc = qsa('.ocard', host); if (oc.length) return oc;
      var cd = qsa('.card, .row, .item, .mtile', host); if (cd.length) return cd;
      return Array.prototype.filter.call(host.children, function (el) { return el.tagName !== 'SCRIPT' && el.tagName !== 'STYLE'; });
    }
    function apply() {
      var s = (inp.value || '').trim().toLowerCase(), rows = rowsOf(), n = 0;
      rows.forEach(function (r) {
        var hit = !s || (r.textContent || '').toLowerCase().indexOf(s) >= 0;
        r.style.display = hit ? '' : 'none'; if (hit) n++;
      });
      return n;
    }
    inp.addEventListener('input', apply);
    if (window.MutationObserver) { try { new MutationObserver(function () { apply(); }).observe(host, { childList: true, subtree: true }); } catch (e) {} }
    return apply;
  }
  // Автоподключение поиска: любой <input data-search="id1,id2"> фильтрует указанные списки.
  // Достаточно в разметке: <input type="search" class="search" id="q" data-search="cap,orders">.
  function autoSearch(root) {
    qsa('input[data-search]', root || document).forEach(function (inp) {
      if (inp.__qsBound) return; inp.__qsBound = true;
      (inp.getAttribute('data-search') || '').split(',').forEach(function (id) {
        id = id.trim(); if (id) quickSearch(inp, id);
      });
    });
  }
  (function () {
    function init() { try { autoSearch(); } catch (e) {} }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
  })();
  // Поисковый селект (комбо) для форм/мастеров. HTML + инициализация.
  // Использование: container.innerHTML += AppUI.comboHtml('code', [{value,label,info,icon}], sel, 'поиск…'); AppUI.initCombos(container).
  function comboHtml(name, options, selected, placeholder) {
    var sel = (options || []).filter(function (o) { return String(o.value) === String(selected); })[0];
    var list = (options || []).map(function (o) {
      return '<div class="ac-item" data-v="' + esc(o.value) + '"><b>' + (o.icon ? esc(o.icon) + ' ' : '') + esc(o.label) + '</b>' + (o.info ? '<span class="g">' + esc(o.info) + '</span>' : '') + '</div>';
    }).join('');
    return '<div class="ac" data-combo-wrap><input type="text" data-combo autocomplete="off" placeholder="' + esc(placeholder || 'поиск…') + '" value="' + (sel ? esc(sel.label) : '') + '">' +
      '<input type="hidden" name="' + esc(name) + '" value="' + (sel ? esc(sel.value) : '') + '"><div class="ac-panel" hidden>' + list + '</div></div>';
  }
  function initCombos(root) {
    qsa('[data-combo]', root || document).forEach(function (inp) {
      if (inp.__ac) return; inp.__ac = 1;
      var wrap = inp.closest('[data-combo-wrap]'); if (!wrap) return;
      var hid = wrap.querySelector('input[type=hidden]'), panel = wrap.querySelector('.ac-panel');
      var items = qsa('.ac-item', panel);
      function render(f) {
        var q = (f || '').trim().toLowerCase(), n = 0;
        items.forEach(function (it) { var hit = !q || (it.textContent || '').toLowerCase().indexOf(q) >= 0; it.style.display = hit ? '' : 'none'; if (hit) n++; });
        panel.hidden = false; return n;
      }
      inp.addEventListener('focus', function () { render(''); });
      inp.addEventListener('input', function () { hid.value = ''; render(inp.value); });
      inp.addEventListener('keydown', function (e) { if (e.key === 'Escape') panel.hidden = true; });
      inp.addEventListener('blur', function () { setTimeout(function () { panel.hidden = true; }, 160); });
      panel.addEventListener('mousedown', function (e) {
        var it = e.target.closest('.ac-item'); if (!it) return; e.preventDefault();
        hid.value = it.getAttribute('data-v');
        var b = it.querySelector('b'); inp.value = b ? b.textContent.trim() : '';
        panel.hidden = true;
      });
    });
  }
  g.AppUI = { qs: qs, qsa: qsa, esc: esc, toast: toast, fmtDate: fmtDate, dialog: dialog, formDialog: formDialog, confirmDialog: confirmDialog, quickSearch: quickSearch, autoSearch: autoSearch, comboHtml: comboHtml, initCombos: initCombos };
})(window);
