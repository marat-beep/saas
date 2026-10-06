/* ============================================================
   3DMP Service · apps/panel — Пульт управления (единая точка входа)
   Разделы по ролям: разработчик / SaaS-админ / админ клиента / пользователь.
   Состав разделов — из assets/js/catalog.js (по id модулей).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var C = window.AppCatalog;

  function esc(v) { return ui.esc(v); }
  function byId(id) { return (C.apps || []).filter(function (a) { return a.id === id; })[0]; }

  var SECTIONS = [
    {
      id: 'dev', badge: 'Разработчик', cls: 'dev', roles: ['admin'],
      title: '🧰 Раздел разработчика',
      about: 'Технические инструменты и документация системы.',
      apps: ['diagnostics', 'scale', 'api', 'guide', 'modules', 'eco']
    },
    {
      id: 'saas', badge: 'SaaS-администратор', cls: 'saas', roles: ['admin'],
      title: '🏗 Раздел SaaS-администратора',
      about: 'Организации, тарифы, пользователи и аудит всей платформы.',
      apps: ['platform', 'admin', 'org', 'industry', 'reports']
    },
    {
      id: 'client', badge: 'Администратор клиента', cls: 'client', roles: ['admin', 'owner'],
      title: '🏢 Раздел администратора клиента',
      about: 'Сотрудники и роли организации, доступные модули, тариф и бренд.',
      apps: ['org', 'roles', 'builder', 'whitelabel', 'hr', 'departments', 'finance', 'escrow', 'docs', 'bi']
    },
    {
      id: 'user', badge: 'Пользователь', cls: 'user', roles: ['admin', 'owner', 'manager', 'supplier'],
      title: '👤 Рабочее место пользователя',
      about: 'Ежедневные модули: заявки, производство, качество, экономика.',
      apps: ['dashboard', 'crm', 'orders', 'tkp', 'procurement', 'suppliers', 'supplier', 'production', 'mes', 'planning',
             'warehouse', 'maintenance', 'tooling', 'oee', 'terminal', 'issues', 'service', 'calendar', 'registry', 'bom', 'assistant', 'nc', 'calc', 'norms', 'marketplace', 'qc', 'passport', 'quality',
             'economics', 'teo', 'finance', 'bi', 'reports', 'industry', 'hr', 'docs', 'templates', 'engraving', 'labels']
    }
  ];

  function card(a) {
    return '<a class="app-card" href="../../' + a.href + '">' +
      '<span class="ic">' + a.icon + '</span><h3>' + esc(a.title) + '</h3><p>' + esc(a.desc) + '</p></a>';
  }

  function render(role) {
    var html = SECTIONS.filter(function (s) { return s.roles.indexOf(role) >= 0; }).map(function (s) {
      var items = s.apps.map(byId).filter(Boolean);
      return '<section class="card panel-sec">' +
        '<h2>' + s.title + ' <span class="sec-badge ' + s.cls + '">' + s.badge + '</span></h2>' +
        '<p class="note">' + s.about + '</p>' +
        '<div class="apps-grid">' + items.map(card).join('') + '</div></section>';
    }).join('');
    $('#sections').innerHTML = html || '<div class="card"><span class="note">Для вашей роли разделы не найдены.</span></div>';
  }

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.AppStatus.render('#conn').catch(function () {});
  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + (s.role ? ' · ' + s.role : '');
    render(s.role);
  });
})();
