/* ============================================================
   3DMP · Роли и доступ (демо)
   Роль хранится в едином профиле (AppData). Управляет гейтингом
   групп в хабе и может использоваться приложениями.
   Доступ: window.AppAuth
   ============================================================ */
(function () {
  'use strict';

  var ROLES = [
    { id: 'all', label: 'Все', icon: '🌐', desc: 'Демо-режим: видно всё' },
    { id: 'client', label: 'Клиент', icon: '👤', desc: 'Клиентские сервисы' },
    { id: 'staff', label: 'Сотрудник', icon: '🏭', desc: 'Производство и офис (все модули)' },
    { id: 'director', label: 'Директор', icon: '🎯', desc: 'Высший уровень: всё + дашборды' },
    { id: 'chief', label: 'Нач. цеха', icon: '📊', desc: 'Тактический уровень: цех и планирование' },
    { id: 'master', label: 'Мастер', icon: '🔧', desc: 'Операционный уровень: участок, наладка, ОТК' },
    { id: 'operator', label: 'Оператор', icon: '📱', desc: 'Рабочее место: станок, ОТК, пульт' },
    { id: 'engineer', label: 'Инженер', icon: '📐', desc: 'Технолог/конструктор/экономист' },
    { id: 'partner', label: 'Партнёр', icon: '🤝', desc: 'Партнёрские кабинеты' },
    { id: 'admin', label: 'Админ', icon: '🛡', desc: 'Платформа и всё остальное' }
  ];

  // какие роли имеют доступ к группам каталога
  var GROUP_ROLES = {
    clients: ['client', 'admin'],
    staff: ['staff', 'director', 'chief', 'master', 'operator', 'engineer', 'admin'],
    partners: ['partner', 'admin'],
    platform: ['admin']
  };

  // иерархия сотрудников: какие модули доступны уровню (принцип «не меньше нужного»)
  var ALL = 'all';
  var STAFF_LEVEL_APPS = {
    director: ALL,
    chief: ALL,
    master: ['B1', 'B2', 'B3', 'B4', 'B6', 'B7', 'B10', 'B11', 'B13', 'B14', 'B15', 'B17', 'B19', 'B20', 'B21', 'B22', 'B24', 'B26', 'B27', 'B29', 'B34', 'B35', 'B36'],
    operator: ['B1', 'B3', 'B4', 'B6', 'B7', 'B13', 'B21', 'B22', 'B26', 'B27', 'B35', 'B36'],
    engineer: ['B2', 'B4', 'B7', 'B8', 'B9', 'B18', 'B20', 'B21', 'B24', 'B25', 'B26', 'B27', 'B28', 'B29', 'B30', 'B33', 'B34', 'B35', 'B36']
  };

  // сопоставление клиентских приложений делегируемым функциям (см. A14)
  var APP_FUNCTION = {
    A1: 'calc', A2: 'calc', A3: 'orders', A4: 'service', A5: 'calc', A6: 'reverse',
    A7: 'procure', A8: 'special', A9: 'docs', A10: 'measure', A11: 'procure', A12: 'calc',
    A13: 'calc', A14: 'crm'
  };

  function profile() { return (window.AppData && AppData.profile.get()) || {}; }
  function roleLabel(id) { var r = ROLES.filter(function (x) { return x.id === id; })[0]; return r ? r.label : 'Все'; }

  var Auth = {
    roles: ROLES,
    roleLabel: roleLabel,
    current: function () { return profile().role || 'all'; },
    set: function (role) {
      if (window.AppData) { var p = profile(); p.role = role; AppData.profile.set(p); }
      document.documentElement.setAttribute('data-role', role);
      return role;
    },
    canGroup: function (groupId) {
      var r = this.current();
      if (r === 'all' || r === 'admin') return true;
      return (GROUP_ROLES[groupId] || []).indexOf(r) >= 0;
    },
    canApp: function (groupId) { return this.canGroup(groupId); },

    // активный делегированный сотрудник клиента (хранится в AppData.settings)
    activeMember: function () {
      if (!window.AppData) return null;
      var id = AppData.settings.get('activeTeam', null);
      if (!id) return null;
      return AppData.team.all().filter(function (m) { return m.id === id; })[0] || null;
    },
    setActiveMember: function (id) { if (window.AppData) AppData.settings.set('activeTeam', id || null); },

    // иерархия сотрудников: может ли уровень открыть приложение
    canStaffApp: function (appId) {
      var r = this.current();
      if (r === 'all' || r === 'admin' || r === 'staff') return true;
      var map = STAFF_LEVEL_APPS[r];
      if (!map) return true; // роль не из иерархии сотрудников
      return map === ALL || map.indexOf(appId) >= 0;
    },
    staffLevels: function () { return ['director', 'chief', 'master', 'operator', 'engineer']; },
    appsForLevel: function (level) { var m = STAFF_LEVEL_APPS[level]; return m === ALL ? 'all' : (m || []); },

    // может ли текущий пользователь открыть клиентское приложение
    canClientApp: function (appId) {
      if (this.current() !== 'client') return true;
      var m = this.activeMember();
      if (!m) return true;                 // владелец компании — доступно всё
      if (appId === 'A14') return true;    // CRM компании доступна всегда
      var fn = APP_FUNCTION[appId];
      if (!fn) return true;
      return (m.functions || []).indexOf(fn) >= 0;
    },

    apply: function () { document.documentElement.setAttribute('data-role', this.current()); }
  };

  Auth.apply();
  window.AppAuth = Auth;
})();
