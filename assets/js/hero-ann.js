/* ============================================================
   3DMP Service · hero-ann.js — баннер объявлений на главной (W1).
   Читает app_announcements_active (0116), показывает активные объявления
   (critical/pinned — первыми), фиксирует прочтение. Требует auth.js/SB.
   ============================================================ */
(function (g) {
  'use strict';

  function ready(fn) { if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn); else fn(); }
  function esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }

  var KIND = {
    info: { l: '📣 Объявление', c: '#0f766e' },
    release: { l: '🚀 Релиз', c: '#1d4ed8' },
    maintenance: { l: '🛠 Плановые тех.работы', c: '#b45309' },
    critical: { l: '⚠ Важно', c: '#b91c1c' }
  };

  function init() {
    var body = document.getElementById('annBody');
    if (!body) return;
    if (!g.SB || !g.Auth || !g.Auth.token()) return;

    var token = g.Auth.token();
    g.SB.rpc('app_announcements_active', { p_token: token }).then(function (r) {
      if (r.error) return;
      var list = r.data || [];
      if (!list.length) { body.innerHTML = '<span class="note">Пока объявлений нет.</span>'; return; }

      var i = 0, timer = null;
      var tag = document.querySelector('#annZone .ann-tag');

      function markRead(id) { g.SB.rpc('app_announcement_read', { p_token: token, p_id: id }).catch(function () {}); }

      function show(k) {
        var a = list[k]; if (!a) return;
        var kk = KIND[a.kind] || KIND.info;
        if (tag) { tag.textContent = kk.l; tag.style.color = kk.c; }
        var link = a.url ? '<a href="' + esc(a.url) + '">подробнее ›</a>' : '';
        var nav = list.length > 1
          ? '<div style="display:flex;gap:6px;align-items:center;white-space:nowrap;">' +
              '<button type="button" class="cardbtn" data-prev title="Предыдущее">‹</button>' +
              '<span class="note">' + (k + 1) + ' / ' + list.length + '</span>' +
              '<button type="button" class="cardbtn" data-next title="Следующее">›</button></div>'
          : '';
        body.innerHTML =
          '<div style="display:flex;gap:10px;align-items:flex-start;">' +
            '<div style="flex:1;min-width:0;">' +
              '<div style="font-weight:700;">' + esc(a.title) + (a.pinned ? ' 📌' : '') + '</div>' +
              (a.body ? '<div class="note" style="margin:2px 0 0;">' + esc(a.body) + '</div>' : '') +
              (link ? '<div style="margin-top:4px;font-size:.78rem;">' + link + '</div>' : '') +
            '</div>' + nav +
          '</div>';
        var p = body.querySelector('[data-prev]'), n = body.querySelector('[data-next]');
        if (p) p.addEventListener('click', function () { go(k - 1); });
        if (n) n.addEventListener('click', function () { go(k + 1); });
        markRead(a.id);
      }

      function go(k) { i = (k + list.length) % list.length; show(i); restart(); }
      function restart() { if (timer) clearInterval(timer); if (list.length > 1) timer = setInterval(function () { go(i + 1); }, 8000); }

      show(0); restart();
    }).catch(function () {});
  }

  ready(function () { setTimeout(init, 350); });
})(window);
