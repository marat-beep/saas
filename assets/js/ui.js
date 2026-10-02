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

  function toast(message) {
    var el = document.createElement('div');
    el.textContent = message;
    el.style.cssText = 'position:fixed;left:50%;bottom:28px;transform:translateX(-50%) translateY(16px);' +
      'background:#0f172a;color:#fff;padding:10px 16px;border-radius:10px;font-size:.82rem;font-weight:600;' +
      'box-shadow:0 10px 30px rgba(0,0,0,.3);z-index:9999;opacity:0;transition:opacity .2s,transform .2s;max-width:90vw;text-align:center;';
    document.body.appendChild(el);
    requestAnimationFrame(function () { el.style.opacity = '1'; el.style.transform = 'translateX(-50%) translateY(0)'; });
    setTimeout(function () {
      el.style.opacity = '0';
      setTimeout(function () { el.remove(); }, 220);
    }, 2400);
  }

  function fmtDate(ts) {
    if (!ts) return '—';
    var d = new Date(ts);
    if (isNaN(d.getTime())) return String(ts);
    return d.toLocaleDateString('ru-RU');
  }

  g.AppUI = { qs: qs, qsa: qsa, esc: esc, toast: toast, fmtDate: fmtDate };
})(window);
