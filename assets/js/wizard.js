/* ============================================================
   3DMP Service · wizard.js — движок пошаговых мастеров (W32).
   window.AppWizard.open(cfg): шаги, валидация, прогресс, черновик
   (localStorage), Назад/Далее/Готово. Черновик можно продолжить.
   cfg = {
     id, title, icon, submitText, doneText,
     steps: [{ title, hint, html(draft), onShow(box,draft), validate(draft)->string|null }],
     onSubmit(draft) -> Promise<string|null>   // строка = ошибка, null = успех
     onDone()
   }
   ============================================================ */
(function (g) {
  'use strict';
  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }
  function toast(t) { if (g.AppUI && g.AppUI.toast) g.AppUI.toast(t); else alert(t); }

  function ensureStyle() {
    if (document.getElementById('wzStyle')) return;
    var st = document.createElement('style'); st.id = 'wzStyle';
    st.textContent =
      '.wz-overlay{position:fixed;inset:0;background:rgba(15,23,42,.5);z-index:1200;display:flex;align-items:center;justify-content:center;padding:16px}' +
      '.wz-modal{background:var(--surface,#fff);border:1px solid var(--border);border-radius:14px;box-shadow:0 24px 60px rgba(15,23,42,.28);width:min(620px,100%);max-height:92vh;display:flex;flex-direction:column;overflow:hidden}' +
      '.wz-head{display:flex;align-items:center;gap:10px;padding:14px 16px;border-bottom:1px solid var(--border)}' +
      '.wz-head b{flex:1;font-size:1rem}' +
      '.wz-x{border:0;background:transparent;color:var(--muted);font-size:1.05rem;cursor:pointer;line-height:1;padding:4px 6px;border-radius:8px}' +
      '.wz-x:hover{color:var(--danger);background:rgba(15,23,42,.05)}' +
      '.wz-progress{display:flex;align-items:center;gap:6px;padding:10px 16px 0}' +
      '.wz-dot{width:22px;height:5px;border-radius:999px;background:var(--border,#e2e8f0);border:0;padding:0;cursor:pointer;transition:background .15s}' +
      '.wz-dot[disabled]{cursor:default;opacity:.65}' +
      '.wz-dot.cur{background:var(--accent,#10b981)}.wz-dot.done{background:var(--accent-700,#059669)}' +
      '.wz-dot:not([disabled]):hover{background:var(--accent-700,#059669)}' +
      '.wz-count{margin-left:auto;font-size:.72rem;color:var(--muted)}' +
      '.wz-body{padding:14px 16px;overflow:auto}' +
      '.wz-step-t{font-weight:800;margin-bottom:4px}' +
      '.wz-fields{display:grid;gap:10px;margin-top:10px}' +
      '.wz-fields label{display:block;font-size:.8rem;font-weight:600;margin-bottom:3px}' +
      '.wz-fields input,.wz-fields select,.wz-fields textarea{width:100%;padding:9px 11px;border:1px solid var(--border);border-radius:9px;font:inherit;font-size:.88rem;background:#fff}' +
      '.wz-fields input[type=checkbox]{width:auto;flex:0 0 auto;padding:0;border-radius:4px}' +
      '.wz-fields label{display:block}' +
      '.wz-fields label input[type=checkbox]{margin-right:6px}' +
      '.wz-fields .ac{position:relative}' +
      '.wz-fields .ac-panel{position:absolute;left:0;right:0;top:calc(100% + 4px);z-index:60;background:#fff;border:1px solid var(--border);border-radius:10px;box-shadow:0 10px 26px rgba(15,23,42,.16);max-height:220px;overflow:auto}' +
      '.wz-fields .ac-panel[hidden]{display:none}' +
      '.wz-fields .ac-item{padding:8px 12px;cursor:pointer;display:flex;justify-content:space-between;gap:10px;align-items:baseline;font-size:.84rem}' +
      '.wz-fields .ac-item b{font-weight:600;font-size:.84rem}' +
      '.wz-fields .ac-item .g{color:var(--muted);font-size:.72rem;white-space:nowrap}' +
      '.wz-fields .ac-item:hover{background:#f0fdf4}' +
      '.wz-pv{overflow:auto;max-height:300px}' +
      '.wz-req{color:var(--danger)}' +
      '.wz-msg{margin:0 16px;font-size:.82rem;padding:8px 10px;border-radius:9px}' +
      '.wz-msg.err{background:#fef2f2;color:#b91c1c;border:1px solid #fecaca}' +
      '.wz-msg.info{background:var(--accent-100,#e8f5ee);color:var(--accent-700);border:1px solid var(--border)}' +
      '.wz-foot{display:flex;gap:8px;align-items:center;padding:12px 16px;border-top:1px solid var(--border)}' +
      '.wz-foot .btn[disabled]{opacity:.6;cursor:default}' +
      '@media(max-width:560px){.wz-foot{flex-wrap:wrap}}';
    document.head.appendChild(st);
  }

  function open(cfg) {
    ensureStyle();
    var key = '3dmp:wiz:' + cfg.id, draft = {}, restored = false, startStep = 0;
    try {
      var s = localStorage.getItem(key);
      if (s) {
        draft = JSON.parse(s) || {};
        restored = Object.keys(draft).some(function (k) { return k !== '__step' && draft[k] !== '' && draft[k] != null && draft[k] !== false; });
        if (typeof draft.__step === 'number') startStep = draft.__step;
      }
    } catch (e) {}
    var steps = cfg.steps || [];
    var i = (startStep >= 0 && startStep < steps.length) ? startStep : 0;   // W5: помним шаг черновика
    var maxReached = i;
    var overlay = document.createElement('div'); overlay.className = 'wz-overlay';
    overlay.innerHTML =
      '<div class="wz-modal" role="dialog" aria-modal="true" aria-label="' + esc(cfg.title || 'Мастер') + '">' +
      '<div class="wz-head"><span class="wz-ic">' + (cfg.icon || '🧩') + '</span><b>' + esc(cfg.title || 'Мастер') + '</b>' +
      '<button class="wz-x" type="button" aria-label="Закрыть">✕</button></div>' +
      '<div class="wz-progress"></div>' +
      '<div class="wz-body"></div>' +
      '<div class="wz-msg" style="display:none;"></div>' +
      '<div class="wz-foot"><button class="btn secondary" type="button" data-wz="draft">Сохранить черновик</button>' +
      '<div style="flex:1"></div>' +
      '<button class="btn secondary" type="button" data-wz="back">← Назад</button>' +
      '<button class="btn" type="button" data-wz="next">Далее →</button></div></div>';
    document.body.appendChild(overlay);

    var $ = function (s) { return overlay.querySelector(s); };
    var body = $('.wz-body');
    function setMsg(t, isErr) {
      var m = $('.wz-msg'); if (!t) { m.style.display = 'none'; m.textContent = ''; return; }
      m.style.display = ''; m.className = 'wz-msg ' + (isErr ? 'err' : 'info'); m.textContent = t;
    }
    function capture() {
      Array.prototype.forEach.call(body.querySelectorAll('[name]'), function (el) {
        draft[el.name] = (el.type === 'checkbox') ? el.checked : el.value;
      });
    }
    function saveDraft() { try { localStorage.setItem(key, JSON.stringify(draft)); } catch (e) {} }
    function clearDraft() { try { localStorage.removeItem(key); } catch (e) {} }
    function hasData() { return Object.keys(draft).some(function (k) { return k !== '__step' && draft[k] !== '' && draft[k] != null && draft[k] !== false; }); }
    function progress() {
      $('.wz-progress').innerHTML = steps.map(function (s, idx) {
        return '<button class="wz-dot' + (idx < i ? ' done' : (idx === i ? ' cur' : '')) + '" type="button" data-step="' + idx + '"' +
          (idx > maxReached ? ' disabled' : '') + ' title="Шаг ' + (idx + 1) + '"></button>';
      }).join('') + '<span class="wz-count">Шаг ' + (i + 1) + ' из ' + steps.length + '</span>';
      Array.prototype.forEach.call($('.wz-progress').querySelectorAll('.wz-dot'), function (d) {
        d.addEventListener('click', function () {
          var idx = Number(d.getAttribute('data-step'));
          if (idx > maxReached || idx === i) return;
          capture(); i = idx; render();
        });
      });
    }
    function render() {
      var st = steps[i] || {};
      body.innerHTML = '<div class="wz-step-t">' + esc(st.title || ('Шаг ' + (i + 1))) + '</div>' +
        (st.hint ? '<p class="note">' + esc(st.hint) + '</p>' : '') +
        '<div class="wz-fields">' + (st.html ? st.html(draft) : '') + '</div>';
      if (st.onShow) { try { st.onShow(body, draft); } catch (e) {} }
      $('[data-wz="back"]').style.display = i > 0 ? '' : 'none';
      $('[data-wz="next"]').textContent = (i === steps.length - 1) ? (cfg.submitText || 'Готово') : 'Далее →';
      progress(); setMsg('');
      /* W5: автофокус первого поля */
      var f = body.querySelector('input:not([type=checkbox]):not([type=hidden]):not([type=file]), select, textarea');
      if (f && !f.disabled) { try { f.focus(); } catch (e) {} }
    }
    function liveValidate() {
      var st = steps[i] || {}; if (!st.validate) return;
      capture(); if (!st.validate(draft)) setMsg('');
    }
    function close(force) {
      if (!force && hasData() && !window.confirm('Закрыть мастер? Черновик сохранён — можно продолжить позже.')) return;
      if (!force) { capture(); draft.__step = i; saveDraft(); }
      overlay.remove(); document.removeEventListener('keydown', onKey);
    }
    function onKey(e) { if (e.key === 'Escape') close(); }
    function next() {
      var st = steps[i] || {}; capture();
      if (st.validate) { var e = st.validate(draft); if (e) { setMsg(e, true); return; } }
      if (i < steps.length - 1) { i++; if (i > maxReached) maxReached = i; draft.__step = i; saveDraft(); render(); return; }
      var btn = $('[data-wz="next"]'); btn.disabled = true;
      Promise.resolve().then(function () { return cfg.onSubmit ? cfg.onSubmit(draft) : null; }).then(function (res) {
        btn.disabled = false;
        if (res) { setMsg(res, true); return; }
        clearDraft(); close(true); toast(cfg.doneText || 'Готово');
        if (cfg.onDone) { try { cfg.onDone(); } catch (e) {} }
      }).catch(function (e) { btn.disabled = false; setMsg((e && e.message) || String(e), true); });
    }

    $('.wz-x').addEventListener('click', close);
    $('[data-wz="back"]').addEventListener('click', function () { if (i > 0) { capture(); i--; draft.__step = i; saveDraft(); render(); } });
    $('[data-wz="next"]').addEventListener('click', next);
    $('[data-wz="draft"]').addEventListener('click', function () { capture(); draft.__step = i; saveDraft(); toast('Черновик сохранён'); });
    /* W5: Enter → Далее; инлайновая валидация по вводу */
    body.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' && e.target && e.target.tagName !== 'TEXTAREA' && e.target.type !== 'checkbox' && e.target.type !== 'button') {
        e.preventDefault(); next();
      }
    });
    body.addEventListener('input', liveValidate);
    body.addEventListener('change', liveValidate);
    document.addEventListener('keydown', onKey);
    render();
    if (restored) setMsg('Черновик восстановлен (шаг ' + (i + 1) + ') — можно продолжить или изменить.', false);
    return { close: close };
  }

  g.AppWizard = { open: open };
})(window);
