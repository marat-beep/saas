/* ============================================================
   3DMP Service · индикатор состояния Supabase / Realtime
   Показывает плавающий бейдж состояния соединения на любой странице.
   Доступ: window.AppRealtime. Требует supabase-client.js (window.SB).
   ============================================================ */
(function (g) {
  'use strict';

  var COLORS = { ok: '#10b981', err: '#ef4444', wait: '#f59e0b' };
  var el = null;

  function mount() {
    if (el) return el;
    el = document.createElement('div');
    el.id = 'rtBadge';
    el.style.cssText = 'position:fixed;left:14px;bottom:14px;z-index:9000;display:flex;align-items:center;gap:7px;' +
      'background:rgba(15,23,42,.92);color:#fff;padding:7px 12px;border-radius:999px;' +
      'font:600 12px/1 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;' +
      'box-shadow:0 6px 18px rgba(0,0,0,.25);user-select:none;';
    el.innerHTML = '<span id="rtDot" style="width:9px;height:9px;border-radius:50%;background:#f59e0b;display:inline-block;"></span>' +
      '<span id="rtText">Supabase…</span>';
    document.body.appendChild(el);
    return el;
  }

  function set(state, text) {
    var dot = document.getElementById('rtDot');
    var t = document.getElementById('rtText');
    if (!dot || !t) return;
    dot.style.background = COLORS[state] || COLORS.wait;
    t.textContent = text;
  }

  function init() {
    if (!document.body) { document.addEventListener('DOMContentLoaded', init); return; }
    mount();
    if (!g.SB) { set('err', 'Supabase: нет клиента'); return; }

    set('wait', 'Supabase: подключение…');
    try {
      var ch = g.SB.channel('3dmp-status');
      ch.subscribe(function (status) {
        if (status === 'SUBSCRIBED') set('ok', 'Supabase: online');
        else if (status === 'CLOSED') set('err', 'Supabase: offline');
        else if (status === 'CHANNEL_ERROR') set('err', 'Supabase: ошибка связи');
        else if (status === 'TIMED_OUT') set('wait', 'Supabase: таймаут, повтор…');
        else set('wait', 'Supabase: ' + status);
      });
    } catch (e) {
      set('err', 'Realtime: ошибка');
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();

  // Ручной перезапуск: AppRealtime.refresh()
  g.AppRealtime = {
    set: set,
    mount: mount,
    refresh: function () { if (el && el.parentNode) el.parentNode.removeChild(el); el = null; init(); }
  };
})(window);
