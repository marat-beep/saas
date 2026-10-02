/* ============================================================
   3DMP Service · старт и health-check
   ============================================================ */
(function () {
  'use strict';

  var cfg = window.APP_CONFIG || {};

  function setStatus(ok, text) {
    var dot = document.querySelector('#status .dot');
    var label = document.getElementById('statusText');
    if (dot) dot.className = 'dot ' + (ok === null ? 'wait' : ok ? 'ok' : 'err');
    if (label) label.textContent = text;
  }

  function row(mark, text, info) {
    return '<li><span class="mark ' + (mark === '✓' ? 'ok' : 'bad') + '">' + mark + '</span>' +
      '<span>' + text + '</span>' + (info ? '<span class="info">' + info + '</span>' : '') + '</li>';
  }

  function renderChecklist(items) {
    var el = document.getElementById('checklist');
    if (el) el.innerHTML = items.join('');
  }

  function start() {
    var items = [];
    var cfgOk = !!(cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY);
    items.push(cfgOk ? row('✓', 'Конфигурация клиента', 'config.js') : row('✕', 'Конфигурация клиента', 'заполнить config.js'));

    var cdnOk = !!(window.supabase && typeof window.supabase.createClient === 'function');
    items.push(cdnOk ? row('✓', 'supabase-js (CDN)', 'загружен') : row('✕', 'supabase-js (CDN)', 'не загружен'));

    if (!cfgOk || !cdnOk) {
      renderChecklist(items);
      setStatus(false, cfgOk ? 'Ошибка загрузки библиотеки' : 'Заполните assets/js/config.js');
      return;
    }
    if (window.SB_ERROR) {
      items.push(row('✕', 'Клиент Supabase', window.SB_ERROR));
      renderChecklist(items);
      setStatus(false, 'Ошибка инициализации клиента');
      return;
    }

    items.push(row('✓', 'Клиент Supabase', 'создан'));
    renderChecklist(items);
    setStatus(null, 'Проверка связи с Supabase…');

    var timeout = new Promise(function (_, reject) { setTimeout(function () { reject(new Error('таймаут')); }, 12000); });
    var check = window.SB.auth.getSession();
    Promise.race([check, timeout]).then(function (res) {
      if (res && res.error) throw res.error;
      items.push(row('✓', 'Связь с Supabase', 'auth endpoint отвечает'));
      renderChecklist(items);
      setStatus(true, 'Подключение к Supabase OK');
      if (window.AppService && typeof window.AppService.init === 'function') window.AppService.init();
    }).catch(function (e) {
      items.push(row('✕', 'Связь с Supabase', (e && e.message) || String(e)));
      renderChecklist(items);
      setStatus(false, 'Нет связи с Supabase (проверьте URL/ключ/сеть)');
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
