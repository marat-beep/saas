/* ============================================================
   3DMP · Единый слой данных (сквозные сценарии)
   Профиль, заявки (из всех клиентских приложений), уведомления.
   Работает поверх App.Store (localStorage), backend не требуется.
   Доступ: window.AppData
   ============================================================ */
(function () {
  'use strict';

  function get(k, d) {
    if (window.App && App.Store) return App.Store.get(k, d);
    try { var v = localStorage.getItem('3dmp:' + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; }
  }
  function set(k, v) {
    if (window.App && App.Store) return App.Store.set(k, v);
    try { localStorage.setItem('3dmp:' + k, JSON.stringify(v)); } catch (e) {}
    return v;
  }
  function pad(n, l) { n = String(n); while (n.length < l) n = '0' + n; return n; }
  function iso() { var d = new Date(); return d.getFullYear() + '-' + pad(d.getMonth() + 1, 2) + '-' + pad(d.getDate(), 2); }
  function money(v) {
    if (window.App && App.money) return App.money(v);
    return (Number(v) || 0).toLocaleString('ru-RU') + ' ₽';
  }

  var SOURCE_TITLES = {
    A1: 'Калькулятор', A2: 'Мастер подбора', A4: 'Заявка на сервис', A6: 'Реверс-инжиниринг',
    A8: 'Спец-технологии', A9: 'Документация', A10: 'Измерения', A11: 'Оборудование', A12: 'АРМ'
  };

  var AppData = {
    sourceTitle: function (s) { return SOURCE_TITLES[s] || s; },

    profile: {
      get: function () { return get('profile', null); },
      set: function (p) { return set('profile', p); },
      clear: function () { return set('profile', null); },
      isLogged: function () { return !!get('profile', null); },
      company: function () { var p = get('profile', null); return (p && p.company) || 'Клиент'; }
    },

    requests: {
      all: function () { return get('requests', []); },
      countNew: function () { return get('requests', []).filter(function (r) { return r.status === 'Новая'; }).length; },
      add: function (req) {
        var list = get('requests', []);
        var id = 'REQ-' + new Date().getFullYear() + '-' + pad(list.length + 1, 4);
        var rec = Object.assign({ id: id, status: 'Новая', created: iso(), ts: Date.now() }, req || {});
        if (!rec.customer) rec.customer = AppData.profile.company();
        list.unshift(rec); set('requests', list);
        AppData.notifications.add({ title: 'Новая заявка ' + id, text: (rec.title || ''), source: rec.source });
        return rec;
      },
      update: function (id, patch) {
        var l = get('requests', []); var i = -1;
        for (var k = 0; k < l.length; k++) if (l[k].id === id) { i = k; break; }
        if (i >= 0) { l[i] = Object.assign(l[i], patch); set('requests', l); }
        return l;
      },
      clear: function () { set('requests', []); }
    },

    contacts: {
      all: function () { return get('contacts', []); },
      add: function (c) {
        var l = get('contacts', []);
        l.unshift(Object.assign({ id: 'CT-' + pad(l.length + 1, 3), created: iso() }, c || {}));
        set('contacts', l); return l;
      },
      remove: function (id) { set('contacts', get('contacts', []).filter(function (c) { return c.id !== id; })); }
    },

    team: {
      all: function () { return get('team', []); },
      add: function (m) {
        var l = get('team', []);
        l.unshift(Object.assign({ id: 'TM-' + pad(l.length + 1, 3), role: 'Сотрудник', functions: [] }, m || {}));
        set('team', l); return l;
      },
      update: function (id, patch) {
        var l = get('team', []);
        for (var i = 0; i < l.length; i++) if (l[i].id === id) l[i] = Object.assign(l[i], patch);
        set('team', l); return l;
      },
      remove: function (id) { set('team', get('team', []).filter(function (m) { return m.id !== id; })); }
    },

    log: {
      all: function () { return get('log', []); },
      add: function (entry) {
        var l = get('log', []);
        l.unshift(Object.assign({ ts: Date.now(), date: iso(), who: (get('profile', {}) || {}).company || 'Система' }, entry || {}));
        set('log', l.slice(0, 100));
      },
      clear: function () { set('log', []); }
    },

    settings: {
      get: function (k, d) { var s = get('settings', {}); return s[k] === undefined ? d : s[k]; },
      set: function (k, v) { var s = get('settings', {}); s[k] = v; set('settings', s); return v; }
    },

    departments: {
      all: function () { return get('departments', []); },
      add: function (d) {
        var l = get('departments', []);
        l.unshift(Object.assign({ id: 'DP-' + pad(l.length + 1, 2), type: 'Цех', created: iso() }, d || {}));
        set('departments', l); return l;
      },
      remove: function (id) { set('departments', get('departments', []).filter(function (d) { return d.id !== id; })); }
    },

    staff: {
      all: function () { return get('staff', []); },
      add: function (s) {
        var l = get('staff', []);
        l.unshift(Object.assign({ id: 'ST-' + pad(l.length + 1, 3), level: 'operator', created: iso() }, s || {}));
        set('staff', l); return l;
      },
      update: function (id, patch) {
        var l = get('staff', []);
        for (var i = 0; i < l.length; i++) if (l[i].id === id) l[i] = Object.assign(l[i], patch);
        set('staff', l); return l;
      },
      remove: function (id) { set('staff', get('staff', []).filter(function (s) { return s.id !== id; })); },
      byDept: function (deptId) { return get('staff', []).filter(function (s) { return s.dept === deptId; }); }
    },

    problems: {
      all: function () { return get('problems', []); },
      add: function (p) {
        var l = get('problems', []);
        l.unshift(Object.assign({ id: 'PRB-' + pad(l.length + 1, 3), status: 'Открыта', level: 'Средний', ts: Date.now(), date: iso() }, p || {}));
        set('problems', l);
        return l;
      },
      update: function (id, patch) {
        var l = get('problems', []);
        for (var i = 0; i < l.length; i++) if (l[i].id === id) l[i] = Object.assign(l[i], patch);
        set('problems', l); return l;
      },
      remove: function (id) { set('problems', get('problems', []).filter(function (p) { return p.id !== id; })); },
      open: function () { return get('problems', []).filter(function (p) { return p.status !== 'Решена'; }); },
      critical: function () { return get('problems', []).filter(function (p) { return p.status !== 'Решена' && p.level === 'Критично'; }); },
      seed: function (items) {
        if (get('problems', []).length) return;
        var l = (items || []).map(function (p, i) { return Object.assign({ id: 'PRB-' + pad(i + 1, 3), status: 'Открыта', level: 'Средний', date: iso(), ts: Date.now() }, p); });
        set('problems', l);
      }
    },

    notifications: {
      all: function () { return get('notifications', []); },
      unread: function () { return get('notifications', []).filter(function (n) { return !n.read; }).length; },
      add: function (n) {
        var l = get('notifications', []);
        l.unshift(Object.assign({ read: false, ts: Date.now() }, n || {}));
        set('notifications', l.slice(0, 50));
      },
      markAllRead: function () { var l = get('notifications', []); l.forEach(function (n) { n.read = true; }); set('notifications', l); },
      clear: function () { set('notifications', []); }
    }
  };

  window.AppData = AppData;
})();
