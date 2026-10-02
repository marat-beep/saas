/* ============================================================
   3DMP Service · сессия и данные пользователя (window.Session)
   Требует supabase-client.js (window.SB). Таблицы — из миграции 0001.
   ============================================================ */
(function (g) {
  'use strict';

  var Session = {
    user: null,
    ready: false,

    init: function () {
      var self = this;
      if (!g.SB) { self.ready = true; return Promise.resolve(null); }
      return g.SB.auth.getSession().then(function (res) {
        self.user = (res && res.data && res.data.session && res.data.session.user) || null;
        self.ready = true;
        return self.user;
      }).catch(function () { self.ready = true; return null; });
    },

    onChange: function (cb) {
      if (!g.SB) return;
      g.SB.auth.onAuthStateChange(function (_event, session) {
        Session.user = (session && session.user) || null;
        cb(Session.user);
      });
    },

    guard: function (redirect) {
      var self = this;
      return self.init().then(function (user) {
        if (!user && redirect) { location.href = redirect; return null; }
        return user;
      });
    },

    loadProfile: function () {
      if (!g.SB || !this.user) return Promise.resolve(null);
      return g.SB.from('profiles').select('*').eq('id', this.user.id).maybeSingle()
        .then(function (r) { return r.error ? null : r.data; })
        .catch(function () { return null; });
    },

    loadTenants: function () {
      if (!g.SB || !this.user) return Promise.resolve([]);
      return g.SB.from('memberships')
        .select('role, tenant:tenants ( id, name, plan, status )')
        .eq('user_id', this.user.id)
        .then(function (r) { return r.error ? [] : (r.data || []); })
        .catch(function () { return []; });
    },

    signOut: function () {
      if (!g.SB) return Promise.resolve();
      return g.SB.auth.signOut().catch(function () {});
    }
  };

  g.Session = Session;
})(window);
