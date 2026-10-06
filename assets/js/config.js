/* ============================================================
   3DMP Service · конфигурация клиента
   Заполнить значениями из Supabase → Settings → API.
   anon key — публичный (защита через RLS). service_role здесь НЕ нужен.
   ============================================================ */
window.APP_CONFIG = {
  APP_NAME: '3DMP Service',
  SUPABASE_URL: 'https://zfkbzzmtbrueaksfaqbf.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_akJbBxWd13audl8KMtdB5Q_0_kT51pa',
  // Backend снимков «/shot» для модуля «Замечания к странице» (см. backend-example/ в основной директории).
  // Пусто → демо/same-origin режим. Можно задать также через <meta name="shot-endpoint"> или window.SHOT_CONFIG.
  shotEndpoint: ''
};
