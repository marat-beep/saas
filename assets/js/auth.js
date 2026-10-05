/* ============================================================
   3DMP Service · вход по логину/паролю (window.Auth)
   Пароли проверяются на сервере (bcrypt в Postgres) через RPC.
   В браузере хранится только токен сессии (localStorage).
   Требует supabase-client.js (window.SB) и миграцию 0003_app_auth.sql.
   ============================================================ */
(function (g) {
  'use strict';

  var KEY = '3dmp:session';

  function read() {
    try { return JSON.parse(localStorage.getItem(KEY)); } catch (e) { return null; }
  }
  function write(s) { try { localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) {} }
  function clear() { try { localStorage.removeItem(KEY); } catch (e) {} }
  function fail(e) { return e && e.message ? e.message : String(e); }

  var Auth = {
    session: function () { return read(); },
    token: function () { var s = read(); return s && s.token; },
    isLogged: function () { return !!this.token(); },
    user: function () { var s = read(); return s ? { user_id: s.user_id, login: s.login, full_name: s.full_name, role: s.role } : null; },
    role: function () { var s = read(); return s ? s.role : null; },

    // возвращает объект пользователя или null (неверные данные)
    login: function (login, password) {
      if (!g.SB) return Promise.reject(new Error('Supabase не подключён'));
      return g.SB.rpc('app_login', { p_login: login, p_password: password }).then(function (r) {
        if (r.error) throw new Error(fail(r.error));
        var row = r.data && r.data[0];
        if (!row) return null;
        write({ token: row.token, user_id: row.user_id, login: row.login, full_name: row.full_name, role: row.role, ts: Date.now() });
        return row;
      });
    },

    // проверка токена на сервере; при истечении — очищает сессию
    refresh: function () {
      var s = read();
      if (!s || !s.token || !g.SB) return Promise.resolve(null);
      return g.SB.rpc('app_me', { p_token: s.token }).then(function (r) {
        if (r.error) return null; // сеть/ошибка — не разлогиниваем
        var row = r.data && r.data[0];
        if (!row) { clear(); return null; }
        s.login = row.login; s.full_name = row.full_name; s.role = row.role;
        s.last_login_at = row.last_login_at; s.tenant_id = row.tenant_id; s.tenant_name = row.tenant_name;
        write(s);
        return s;
      }).catch(function () { return null; });
    },

    // запись действия в журнал (fire-and-forget)
    log: function (action, detail) {
      var s = read();
      if (g.SB && s && s.token) {
        try { g.SB.rpc('app_log_event', { p_token: s.token, p_action: action, p_detail: detail || '' }); } catch (e) {}
      }
    },

    guard: function (redirect) {
      if (!this.isLogged()) { if (redirect) location.href = redirect; return Promise.resolve(null); }
      return this.refresh().then(function (s) {
        if (!s && redirect) location.href = redirect;
        return s;
      });
    },

    logout: function () {
      var t = this.token();
      if (g.SB && t) {
        try { g.SB.rpc('app_log_event', { p_token: t, p_action: 'Выход', p_detail: '' }); } catch (e) {}
        try { g.SB.rpc('app_logout', { p_token: t }); } catch (e) {}
      }
      clear();
    }
  };

  Auth.KEY = KEY;
  g.Auth = Auth;
})(window);
