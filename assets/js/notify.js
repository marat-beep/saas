/* ============================================================
   3DMP Service · уведомления (window.AppNotify)
   Колокольчик в шапке + всплывающие оповещения (toast).
   Опрос app_notif_list/unread; новые показываются всплывашкой.
   Требует auth.js (window.Auth) и supabase-client.js (window.SB).
   ============================================================ */
(function (g) {
  'use strict';

  var seen = {}, first = true, timer = null, open = false;
  var els = {};

  function ready(fn) { if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn); else fn(); }
  function esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function root() {
    var s = (document.currentScript && document.currentScript.src) || '';
    var i = s.indexOf('assets/js/notify.js');
    return i >= 0 ? s.substring(0, i) : '';
  }
  var ROOT = root();

  function buildUI() {
    var bar = document.querySelector('.topbar');
    if (!bar || document.getElementById('ntfBtn')) return;

    var btn = document.createElement('button');
    btn.className = 'tbtn'; btn.id = 'ntfBtn'; btn.type = 'button';
    btn.style.position = 'relative';
    btn.innerHTML = '🔔 <span id="ntfCount" style="display:inline-block;min-width:16px;">0</span>';
    bar.appendChild(btn);

    var drop = document.createElement('div');
    drop.id = 'ntfDrop';
    drop.style.cssText = 'position:fixed;top:56px;right:14px;width:340px;max-width:92vw;max-height:70vh;overflow:auto;' +
      'background:#fff;color:#0f172a;border:1px solid #e2e8f0;border-radius:14px;box-shadow:0 16px 40px rgba(15,23,42,.22);' +
      'padding:8px;display:none;z-index:9500;';
    document.body.appendChild(drop);

    var toastBox = document.createElement('div');
    toastBox.id = 'toastBox';
    toastBox.style.cssText = 'position:fixed;top:16px;right:16px;z-index:9600;display:flex;flex-direction:column;gap:8px;max-width:340px;';
    document.body.appendChild(toastBox);

    els.drop = drop; els.count = btn.querySelector('#ntfCount'); els.toast = toastBox;

    btn.addEventListener('click', function (e) {
      e.stopPropagation(); open = !open; drop.style.display = open ? 'block' : 'none';
      if (open) { refresh(true); }
    });
    document.addEventListener('click', function () { open = false; if (drop) drop.style.display = 'none'; });
    drop.addEventListener('click', function (e) { e.stopPropagation(); });
  }

  function setCount(n) {
    if (!els.count) return;
    els.count.textContent = n;
    els.count.style.color = n > 0 ? '#fca5a5' : '#fff';
  }

  function renderList(items) {
    if (!els.drop) return;
    if (!items.length) { els.drop.innerHTML = '<div style="padding:12px;color:#64748b;font-size:.84rem;">Уведомлений нет.</div>'; return; }
    els.drop.innerHTML = items.map(function (n) {
      return '<a href="' + (ROOT + (n.link || '')) + '" data-nid="' + n.id + '" style="display:block;padding:10px 11px;border-radius:10px;text-decoration:none;color:#0f172a;' +
        (n.read_at ? '' : 'background:#f0fdf4;') + '">' +
        '<div style="font-weight:700;font-size:.84rem;">' + esc(n.title) + '</div>' +
        (n.body ? '<div style="font-size:.76rem;color:#64748b;margin-top:2px;">' + esc(n.body) + '</div>' : '') +
        '<div style="font-size:.7rem;color:#94a3b8;margin-top:3px;">' + fmt(n.created_at) + '</div></a>';
    }).join('');
  }

  function toast(n) {
    if (!els.toast) return;
    var el = document.createElement('a');
    el.href = ROOT + (n.link || '');
    el.textContent = n.title;
    el.style.cssText = 'display:block;background:#0f172a;color:#fff;padding:12px 14px;border-radius:12px;text-decoration:none;' +
      'font-size:.84rem;font-weight:600;box-shadow:0 12px 30px rgba(0,0,0,.3);opacity:0;transform:translateX(20px);transition:.25s;';
    els.toast.appendChild(el);
    requestAnimationFrame(function () { el.style.opacity = '1'; el.style.transform = 'translateX(0)'; });
    setTimeout(function () { el.style.opacity = '0'; el.style.transform = 'translateX(20px)'; setTimeout(function () { el.remove(); }, 260); }, 7000);
  }

  function refresh(noToast) {
    if (!g.SB || !g.Auth || !g.Auth.token()) return;
    var tk = g.Auth.token();
    g.SB.rpc('app_notif_list', { p_token: tk, p_limit: 20 }).then(function (r) {
      var items = (r && !r.error && r.data) || [];
      var unread = 0;
      items.forEach(function (n) {
        if (!n.read_at) unread++;
        if (!seen[n.id]) { seen[n.id] = 1; if (!first && !noToast) toast(n); }
      });
      first = false;
      renderList(items);
      g.SB.rpc('app_notif_unread', { p_token: tk }).then(function (u) {
        setCount((u && u.data != null) ? u.data : unread);
      });
    }).catch(function () {});
  }

  function markAll() {
    if (!g.SB || !g.Auth || !g.Auth.token()) return;
    g.SB.rpc('app_notif_mark_all', { p_token: g.Auth.token() });
    setCount(0);
  }

  function init() {
    if (!document.querySelector('.topbar') || !g.Auth || !g.Auth.token()) return;
    buildUI();
    refresh(false);
    // при открытии панели — помечаем прочитанными
    document.addEventListener('click', function () { if (open) markAll(); });
    if (timer) clearInterval(timer);
    timer = setInterval(function () { refresh(false); }, 15000);
    document.addEventListener('visibilitychange', function () { if (!document.hidden) refresh(false); });
  }

  ready(function () {
    // ждём, пока auth подгрузит сессию (guard вызывается на страницах)
    setTimeout(init, 300);
  });

  g.AppNotify = { refresh: refresh, markAll: markAll, toast: toast };
})(window);
