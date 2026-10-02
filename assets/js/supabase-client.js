/* ============================================================
   3DMP Service · клиент Supabase
   Создаёт единый экземпляр window.SB, если конфиг заполнен.
   ============================================================ */
(function (global) {
  'use strict';

  var cfg = global.APP_CONFIG || {};

  if (!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) {
    global.SB = null;
    global.SB_ERROR = 'Не заполнены SUPABASE_URL / SUPABASE_ANON_KEY в assets/js/config.js';
    return;
  }
  if (!global.supabase || typeof global.supabase.createClient !== 'function') {
    global.SB = null;
    global.SB_ERROR = 'Библиотека supabase-js не загрузилась (CDN)';
    return;
  }

  try {
    global.SB = global.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
      auth: { persistSession: false }   // вход в сервисе — собственный (login/пароль)
    });
    global.SB_ERROR = null;
  } catch (e) {
    global.SB = null;
    global.SB_ERROR = e && e.message ? e.message : String(e);
  }
})(window);
