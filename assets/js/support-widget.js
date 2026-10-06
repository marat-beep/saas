/* ============================================================
   3DMP · support-widget.js — быстрый доступ к поддержке (🎧 в топбаре).
   Кнопка «Новый тикет» + «Мои тикеты». Данные через RPC 0100.
   Подключается на всех страницах (после notify.js). Префикс .sw-.
   ============================================================ */
(function (g) {
  'use strict';
  if (!g.Auth || !g.SB) return;

  function esc(v) { return String(v == null ? '' : v).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function tok() { return g.Auth.token ? g.Auth.token() : null; }
  function rpc(n, a) { return g.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function ensureStyle() {
    if (document.getElementById('swStyle')) return;
    var st = document.createElement('style'); st.id = 'swStyle';
    st.textContent = '.sw-btn{margin-left:8px;background:#fff;border:1px solid var(--border);border-radius:8px;padding:6px 10px;cursor:pointer}'
      + '.sw-btn:hover{border-color:var(--accent)}'
      + '.sw-modal{position:fixed;inset:0;background:rgba(15,23,42,.5);display:flex;align-items:center;justify-content:center;z-index:9998;padding:16px}'
      + '.sw-dlg{background:var(--surface,#fff);color:var(--text);border-radius:12px;max-width:520px;width:100%;padding:16px;max-height:85vh;overflow:auto;border:1px solid var(--border)}'
      + '.sw-tabs{display:flex;gap:8px;margin-bottom:10px}.sw-tab{padding:6px 12px;border:1px solid var(--border);border-radius:999px;background:#fff;cursor:pointer}'
      + '.sw-tab.on{border-color:var(--accent);color:var(--accent-700)}'
      + '.sw-f{margin:8px 0}.sw-f input,.sw-f select,.sw-f textarea{width:100%;padding:8px 10px;border:1px solid var(--border);border-radius:8px}'
      + '.sw-row{border-bottom:1px solid var(--border);padding:6px 0;font-size:.85rem}';
    document.head.appendChild(st);
  }

  function openModal() {
    ensureStyle();
    var dlg = document.createElement('div'); dlg.className = 'sw-modal';
    dlg.innerHTML = '<div class="sw-dlg" role="dialog" aria-modal="true">'
      + '<div class="sw-tabs"><button class="sw-tab on" data-t="new">Новый тикет</button><button class="sw-tab" data-t="mine">Мои тикеты</button>'
      + '<button class="sw-btn" style="margin-left:auto" data-x="1" aria-label="Закрыть">✕</button></div>'
      + '<div id="swNew">'
      + '<div class="sw-f"><input id="swSub" placeholder="Тема *"></div>'
      + '<div class="sw-f" style="display:flex;gap:8px"><select id="swCat"><option>Техсбой</option><option>Вопрос</option><option>Доработка</option><option>Доступ</option><option>Оплата</option><option>Другое</option></select>'
      + '<select id="swPr"><option value="low">Низкий</option><option value="normal" selected>Обычный</option><option value="high">Высокий</option><option value="critical">Критический</option></select></div>'
      + '<div class="sw-f"><textarea id="swDesc" rows="3" placeholder="Описание"></textarea></div>'
      + '<button class="sw-btn" id="swSend" style="background:var(--accent);color:#fff;border:0">Отправить</button>'
      + '<div class="sw-row" id="swMsg" style="border:0;color:var(--muted)"></div></div>'
      + '<div id="swMine" style="display:none"><div id="swList">Загрузка…</div></div>'
      + '</div>';
    document.body.appendChild(dlg);
    function close() { dlg.remove(); document.removeEventListener('keydown', onEsc); }
    function onEsc(e) { if (e.key === 'Escape') close(); }
    document.addEventListener('keydown', onEsc);
    dlg.querySelector('[data-x]').addEventListener('click', close);
    dlg.addEventListener('click', function (e) { if (e.target === dlg) close(); });
    dlg.querySelectorAll('.sw-tab').forEach(function (b) { b.addEventListener('click', function () {
      dlg.querySelectorAll('.sw-tab').forEach(function (z) { z.classList.toggle('on', z === b); });
      var isNew = b.dataset.t === 'new';
      dlg.querySelector('#swNew').style.display = isNew ? 'block' : 'none';
      dlg.querySelector('#swMine').style.display = isNew ? 'none' : 'block';
      if (!isNew) loadMine(dlg);
    }); });
    dlg.querySelector('#swSend').addEventListener('click', function () {
      var sub = dlg.querySelector('#swSub').value.trim();
      if (!sub) { dlg.querySelector('#swMsg').textContent = 'Укажите тему'; return; }
      rpc('app_support_ticket_create', { p_token: tok(), p_subject: sub, p_description: dlg.querySelector('#swDesc').value, p_category: dlg.querySelector('#swCat').value, p_priority: dlg.querySelector('#swPr').value, p_scope: 'internal', p_module: '', p_url: location.href, p_related_type: null, p_related_id: null })
        .then(function (r) { var x = r && r[0]; dlg.querySelector('#swMsg').textContent = x ? ('Создан ' + x.number) : 'Ошибка'; if (g.Auth.log) g.Auth.log('Тикет создан', x ? x.number : ''); })
        .catch(function (e) { dlg.querySelector('#swMsg').textContent = 'Ошибка: ' + e.message; });
    });
  }

  function loadMine(dlg) {
    var host = dlg.querySelector('#swList');
    rpc('app_support_ticket_list', { p_token: tok(), p_status: null, p_scope: null, p_mine: true }).then(function (rows) {
      rows = rows || [];
      host.innerHTML = rows.length ? rows.map(function (t) { return '<div class="sw-row"><b>' + esc(t.number) + '</b> ' + esc(t.subject) + ' — <span class="note">' + esc(t.status) + '</span></div>'; }).join('') : '<div class="sw-row">Тикетов нет.</div>';
    }).catch(function (e) { host.innerHTML = '<div class="sw-row">Ошибка: ' + esc(e.message) + '</div>'; });
  }

  function addButton() {
    if (!tok() || document.getElementById('swOpen')) return;
    var bar = document.querySelector('.topbar');
    if (!bar) return;
    var b = document.createElement('button');
    b.id = 'swOpen'; b.className = 'sw-btn'; b.type = 'button'; b.title = 'Служба поддержки'; b.setAttribute('aria-label', 'Служба поддержки'); b.textContent = '🎧';
    b.addEventListener('click', openModal);
    var who = bar.querySelector('#who'); if (who && who.parentNode === bar) bar.insertBefore(b, who); else bar.appendChild(b);
  }

  function init() { ensureStyle(); addButton(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
  g.SupportWidget = { open: openModal, refresh: init };
})(window);
