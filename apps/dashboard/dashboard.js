/* ============================================================
   3DMP Service · apps/dashboard — личный кабинет
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs;

  var ROLE_LABEL = { owner: 'Собственник', manager: 'Менеджер', supplier: 'Поставщик', admin: 'Администратор' };
  function roleLabel(r) { return ROLE_LABEL[r] || r || '—'; }

  function kv(k, v) {
    return '<div class="tenant"><span class="note">' + ui.esc(k) + '</span><b style="margin-left:auto;">' + ui.esc(v) + '</b></div>';
  }

  function renderModules(session) {
    var apps = (window.AppCatalog && window.AppCatalog.apps) || [];
    $('#modules').innerHTML = apps.filter(function (a) {
      if (a.id === 'auth' || a.id === 'dashboard') return false;
      if (a.roles && a.roles.indexOf(session.role) < 0) return false;
      return true;
    }).map(function (a) {
      return '<div class="tenant"><span>' + a.icon + ' <b>' + ui.esc(a.title) + '</b></span>' +
        '<a class="tbtn" style="margin-left:auto;background:var(--accent);border-color:var(--accent);" href="../' + a.id + '/index.html">Открыть</a></div>';
    }).join('') || '<span class="note">Модулей пока нет.</span>';
  }

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    var out = $('#logout');
    out.style.display = '';
    out.addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

    $('#profile').innerHTML =
      kv('Логин', s.login) + kv('Имя', s.full_name || '—') + kv('Роль', roleLabel(s.role));
    renderModules(s);
  });
})();
