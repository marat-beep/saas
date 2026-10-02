/* ============================================================
   3DMP Service · проверка подключения к Supabase (window.AppStatus)
   render(sel) — рисует статус в элемент с id=sel (или '<id>' c точкой/решеткой).
   ============================================================ */
(function (g) {
  'use strict';

  function step(ok, text, info) {
    return { ok: ok, text: text, info: info || '' };
  }

  function check() {
    var cfg = g.APP_CONFIG || {};
    var steps = [];
    var cfgOk = !!(cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY);
    steps.push(step(cfgOk, 'Конфигурация клиента', cfgOk ? 'config.js' : 'заполнить config.js'));

    var cdnOk = !!(g.supabase && typeof g.supabase.createClient === 'function');
    steps.push(step(cdnOk, 'supabase-js (CDN)', cdnOk ? 'загружен' : 'не загружен'));

    if (!cfgOk || !cdnOk || !g.SB) {
      if (g.SB_ERROR) steps.push(step(false, 'Клиент Supabase', g.SB_ERROR));
      return Promise.resolve({ ok: false, steps: steps, message: cfgOk ? 'Ошибка загрузки библиотеки' : 'Заполните assets/js/config.js' });
    }

    steps.push(step(true, 'Клиент Supabase', 'создан'));

    var url = cfg.SUPABASE_URL.replace(/\/+$/, '') + '/auth/v1/health';
    var ctrl = ('AbortController' in g) ? new g.AbortController() : null;
    var timer = setTimeout(function () { if (ctrl) ctrl.abort(); }, 12000);

    return fetch(url, { headers: { apikey: cfg.SUPABASE_ANON_KEY }, signal: ctrl ? ctrl.signal : undefined })
      .then(function (res) {
        clearTimeout(timer);
        if (!res.ok) throw new Error('HTTP ' + res.status);
        steps.push(step(true, 'Связь с Supabase', 'endpoint отвечает'));
        return { ok: true, steps: steps, message: 'Подключение к Supabase OK' };
      })
      .catch(function (e) {
        clearTimeout(timer);
        steps.push(step(false, 'Связь с Supabase', (e && e.message) || String(e)));
        return { ok: false, steps: steps, message: 'Нет связи с Supabase (проверьте URL/ключ/сеть)' };
      });
  }

  function setStatus(sel, state, text) {
    var box = document.querySelector(sel);
    if (!box) return;
    var dot = box.querySelector('.dot');
    var label = box.querySelector('[data-status-text]') || box.querySelector('#statusText') || box.querySelector('.status-text');
    if (dot) dot.className = 'dot ' + state;
    if (label) label.textContent = text;
  }

  function renderStatus(sel, text) {
    var box = document.querySelector(sel);
    if (!box) return;
    box.innerHTML = '<span class="dot wait"></span><span class="status-text">' + (text || 'Проверка…') + '</span>';
  }

  function render(sel) {
    renderStatus(sel, 'Проверка…');
    return check().then(function (r) {
      setStatus(sel, r.ok ? 'ok' : 'err', r.message);
      var list = document.querySelector('[data-checklist]');
      if (list) {
        list.innerHTML = r.steps.map(function (s) {
          return '<li><span class="mark ' + (s.ok ? 'ok' : 'bad') + '">' + (s.ok ? '✓' : '✕') + '</span>' +
            '<span>' + s.text + '</span>' + (s.info ? '<span class="info">' + s.info + '</span>' : '') + '</li>';
        }).join('');
      }
      return r;
    });
  }

  g.AppStatus = { check: check, render: render };
})(window);
