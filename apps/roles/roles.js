/* ============================================================
   3DMP Service · apps/roles — Роли и права (матрица P8)
   Роль × модуль: просмотр/правка. Данные: app_role_permissions (0029).
   Редактирование: admin/owner. Остальные — только просмотр.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB, C = window.AppCatalog;
  var token = null, me = null, roles = [], matrix = {}, sel = null, canEdit = false;

  // сопоставление роли → отображаемое имя
  var LABELS = (window.Auth && window.Auth.ROLE_LABELS) || {};
  function roleLabel(r) { return LABELS[r] || r; }
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#rMsg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  // модули из каталога (кроме служебных ядра, которые не ограничиваются)
  var SKIP = { auth: 1, panel: 1, dashboard: 1, guide: 1, modules: 1, eco: 1 };
  function modules() { return (C.apps || []).filter(function (a) { return !SKIP[a.id]; }); }
  function groupTitle(id) { var g = (C.groups || []).filter(function (x) { return x.id === id; })[0]; return g ? g.icon + ' ' + g.title : id; }

  function load() {
    return Promise.all([
      rpc('app_roles_list', { p_token: token }),
      rpc('app_role_matrix', { p_token: token })
    ]).then(function (r) {
      roles = r[0] || []; matrix = {};
      (r[1] || []).forEach(function (p) {
        matrix[p.role] = matrix[p.role] || {};
        matrix[p.role][p.module_id] = { view: p.can_view, edit: p.can_edit };
      });
      renderRoles();
      sel = sel || (roles[0] && roles[0].role);
      renderPerms();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }

  function renderRoles() {
    $('#roles').innerHTML = roles.map(function (r) {
      return '<div class="rolecard' + (r.role === sel ? ' active' : '') + '" data-role="' + r.role + '">' +
        '<b>' + esc(roleLabel(r.role)) + '</b>' +
        '<small>👤 ' + r.users_count + ' · ✓ ' + r.view_count + ' · ✎ ' + r.edit_count + '</small></div>';
    }).join('');
    ui.qsa('#roles .rolecard').forEach(function (c) {
      c.addEventListener('click', function () { sel = c.dataset.role; renderRoles(); renderPerms(); });
    });
  }

  function renderPerms() {
    $('#roleTitle').textContent = roleLabel(sel);
    var trs = modules().map(function (a) {
      var p = (matrix[sel] && matrix[sel][a.id]) || { view: false, edit: false };
      var dis = canEdit ? '' : ' disabled';
      return '<tr><td>' + a.icon + ' <b>' + esc(a.title) + '</b> <span class="note">· ' + esc(groupTitle(a.group)) + '</span></td>' +
        '<td><input type="checkbox" data-m="' + a.id + '" data-k="view"' + (p.view ? ' checked' : '') + dis + '></td>' +
        '<td><input type="checkbox" data-m="' + a.id + '" data-k="edit"' + (p.edit ? ' checked' : '') + dis + '></td></tr>';
    }).join('');
    $('#perms').innerHTML = '<thead><tr><th>Модуль</th><th>Просмотр</th><th>Правка</th></tr></thead><tbody>' + trs + '</tbody>';
    ui.qsa('#perms input[type=checkbox]').forEach(function (ch) {
      ch.addEventListener('change', function () { save(ch.dataset.m); });
    });
  }

  function save(moduleId) {
    if (!canEdit) return;
    var v = ($('#perms input[data-m="' + moduleId + '"][data-k="view"]') || {}).checked;
    var e = ($('#perms input[data-m="' + moduleId + '"][data-k="edit"]') || {}).checked;
    if (e && !v) { v = true; var vc = $('#perms input[data-m="' + moduleId + '"][data-k="view"]'); if (vc) vc.checked = true; }
    rpc('app_role_perm_set', { p_token: token, p_role: sel, p_module: moduleId, p_view: !!v, p_edit: !!e })
      .then(function (d) {
        var r = d && d[0];
        if (!r || !r.ok) { msg((r && r.message) || 'Ошибка', 'err'); return; }
        matrix[sel] = matrix[sel] || {};
        matrix[sel][moduleId] = { view: !!v, edit: !!e };
        window.Auth.log('Права роли', roleLabel(sel) + ' · ' + moduleId);
        msg('Сохранено: ' + roleLabel(sel) + ' · ' + moduleId, 'ok');
      }).catch(function (err) { msg('Ошибка: ' + err.message, 'err'); });
  }

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token; canEdit = (s.role === 'admin' || s.role === 'owner');
    $('#who').textContent = s.login + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    if (!canEdit) msg('Режим просмотра: изменять матрицу может владелец или администратор.', 'info');
    load();
  });
})();
