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

  // Модальное окно: opts = { title, body(HTML|text), okText, cancelText, danger, hideCancel }
  // Возвращает Promise<boolean> (true — подтверждено).
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
        '<div class="modal" role="dialog" aria-modal="true">' +
          (opts.title ? '<div class="modal-head">' + esc(opts.title) + '</div>' : '') +
          '<div class="modal-body">' + (opts.html ? opts.body : esc(opts.body || '')) + '</div>' +
          '<div class="modal-foot">' + foot + '</div>' +
        '</div>';
      document.body.appendChild(back);
      requestAnimationFrame(function () { back.classList.add('show'); });
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
        if (e.target.closest('[data-ok]')) close(true);
        if (e.target.closest('[data-cancel]')) close(false);
      });
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

  g.AppUI = { qs: qs, qsa: qsa, esc: esc, toast: toast, fmtDate: fmtDate, dialog: dialog, confirmDialog: confirmDialog };
})(window);
