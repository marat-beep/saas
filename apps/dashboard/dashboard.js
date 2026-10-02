/* ============================================================
   3DMP Service · apps/dashboard — личный кабинет
   Профиль и организации (memberships → tenants). Требует входа.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI;
  var $ = ui.qs;

  function renderWho(user) {
    $('#who').textContent = user.email || '';
    var out = $('#logout');
    out.style.display = '';
    out.addEventListener('click', function () {
      window.Session.signOut().then(function () { location.href = '../../index.html'; });
    });
  }

  function renderProfile(p, user) {
    var el = $('#profile');
    el.innerHTML =
      row('Email', user.email || '—') +
      row('Имя', (p && p.full_name) || '—') +
      row('ID пользователя', user.id) +
      row('Создан', ui.fmtDate(p && p.created_at));
  }
  function row(k, v) {
    return '<div class="tenant"><span class="note">' + ui.esc(k) + '</span><b style="margin-left:auto;">' + ui.esc(v) + '</b></div>';
  }

  function renderTenants(list) {
    var el = $('#tenants');
    var hint = $('#tenantHint');
    if (!list.length) {
      el.innerHTML = '<span class="note">Организаций нет.</span>';
      hint.innerHTML = '<p class="note">Если таблиц ещё нет — примените миграцию <code>supabase/migrations/0001_init.sql</code> в Supabase → SQL Editor.</p>';
      return;
    }
    el.innerHTML = list.map(function (m) {
      var t = m.tenant || {};
      return '<div class="tenant"><span class="ic">🏢</span><span>' + ui.esc(t.name || '—') +
        '</span><span class="role">' + ui.esc(m.role || 'member') + (t.plan ? ' · ' + ui.esc(t.plan) : '') + '</span></div>';
    }).join('');
  }

  window.Session.guard('../auth/index.html').then(function (user) {
    if (!user) return;
    renderWho(user);
    window.Session.loadProfile().then(function (p) { renderProfile(p, user); });
    window.Session.loadTenants().then(renderTenants);
  });
})();
