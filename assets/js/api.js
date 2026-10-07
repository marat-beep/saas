/* ============================================================
   3DMP Service · единый API-слой (window.AppAPI)
   Обёртка над Supabase RPC: единая обработка ошибок/результата.
   Использование: AppAPI.call('app_order_list', { p_token })
                  AppAPI.callSafe('app_kpi', { p_token }, {})
   ============================================================ */
(function (g) {
  'use strict';

  function ensure() {
    if (!g.SB) throw new Error(g.SB_ERROR || 'Supabase не подключён');
    return g.SB;
  }

  // Вызов RPC; при ошибке бросает Error с текстом. Возвращает data (массив/объект).
  function call(name, args) {
    return ensure().rpc(name, args || {}).then(function (r) {
      if (r.error) throw new Error(r.error.message || 'Ошибка RPC');
      return r.data;
    });
  }

  // Безопасный вызов: при ошибке возвращает fallback (по умолчанию []).
  function callSafe(name, args, fallback) {
    return call(name, args).catch(function () { return fallback === undefined ? [] : fallback; });
  }

  // Первая строка результата (для RPC, возвращающих одну запись) или null.
  function first(name, args) {
    return call(name, args).then(function (d) { return (d && d[0]) || null; });
  }

  g.AppAPI = { call: call, callSafe: callSafe, first: first };
})(window);
