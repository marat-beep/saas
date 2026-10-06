/* ============================================================
   3DMP Service · apps/admin — администрирование пользователей (платформа)
   Доступно только role='admin'. RPC admin_* (0004) + admin_list_users (0047).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, users = [], q = '';

  function roleLabel(r) { return (window.Auth && window.Auth.roleLabel) ? window.Auth.roleLabel(r) : r; }
  function esc(v) { return ui.esc(v); }
  function fmtDT(ts) { if (!ts) return '—'; var d = new Date(ts); return isNaN(d.getTime()) ? '—' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(name, args) { return SB.rpc(name, args).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function resultMsg(id, data) { var row = data && data[0]; if (!row) { msg(id, 'Нет ответа', 'err'); return false; } msg(id, row.message || (row.ok ? 'Готово' : 'Ошибка'), row.ok ? 'ok' : 'err'); return row.ok; }

  function render() {
    var list = users.filter(function (u) { if (!q) return true; var s = q.toLowerCase(); return [u.login, u.full_name, u.role, u.tenant_name].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#count').textContent = '(' + list.length + ')';
    $('#users').innerHTML = '<thead><tr><th>Логин</th><th>Имя</th><th>Организация</th><th>Роль</th><th>Статус</th><th>Вход</th><th>Действия</th></tr></thead><tbody>' +
      list.map(function (u) {
        var isMe = me && u.id === me.user_id;
        var opt = (window.Auth.ROLE_LABELS ? Object.keys(Auth.ROLE_LABELS) : ['admin','owner','manager','supplier'])
          .map(function (r) { return '<option value="' + r + '"' + (u.role === r ? ' selected' : '') + '>' + esc(roleLabel(r)) + '</option>'; }).join('');
        return '<tr><td><b>' + esc(u.login) + '</b>' + (isMe ? ' <span class="note">(вы)</span>' : '') + '</td>' +
          '<td>' + esc(u.full_name || '—') + '</td>' +
          '<td>' + esc(u.tenant_name || '—') + '</td>' +
          '<td><select data-role="' + u.id + '">' + opt + '</select></td>' +
          '<td><span class="badge ' + (u.active ? 'done' : 'cancelled') + '">' + (u.active ? 'активен' : 'выключен') + '</span></td>' +
          '<td>' + fmtDT(u.last_login_at) + '</td>' +
          '<td style="white-space:nowrap;">' +
          '<button class="act" data-toggle="' + u.id + '" data-active="' + (!u.active) + '">' + (u.active ? 'Выключить' : 'Включить') + '</button>' +
          '<button class="act" data-pass="' + u.id + '" data-login="' + esc(u.login) + '">Пароль</button>' +
          (isMe ? '' : '<button class="act danger" data-del="' + u.id + '" data-login="' + esc(u.login) + '">Удалить</button>') +
          '</td></tr>';
      }).join('') + '</tbody>';
  }
  function renderKpi() {
    var active = users.filter(function (u) { return u.active; }).length;
    var admins = users.filter(function (u) { return u.role === 'admin'; }).length;
    var tenants = {}; users.forEach(function (u) { if (u.tenant_name) tenants[u.tenant_name] = 1; });
    var suppliers = users.filter(function (u) { return u.role === 'supplier'; }).length;
    $('#kpis').innerHTML = cell('Пользователей', users.length) + cell('Активных', active) + cell('Админов', admins) +
      cell('Организаций', Object.keys(tenants).length) + cell('Поставщиков', suppliers);
    function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  }
  function renderEvents() {
    rpc('admin_list_events', { p_token: token, p_limit: 50 }).then(function (list) {
      list = list || [];
      $('#events').innerHTML = list.length ? list.map(function (e) {
        return '<div class="kvr"><b>' + esc(e.login || '—') + '</b><span class="note">' + esc(e.action) + (e.detail ? ' (' + esc(e.detail) + ')' : '') + '</span>' +
          '<span class="note" style="margin-left:auto;">' + fmtDT(e.created_at) + '</span></div>';
      }).join('') : '<span class="note">Событий нет.</span>';
    }).catch(function (e) { msg('#evMsg', 'Ошибка журнала: ' + e.message, 'err'); });
  }
  function load() { return rpc('admin_list_users', { p_token: token }).then(function (d) { users = d || []; renderKpi(); render(); renderEvents(); }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); }); }

  $('#createBtn').addEventListener('click', function () {
    var login = $('#nLogin').value.trim(), pass = $('#nPass').value;
    if (!login || !pass) { msg('#createMsg', 'Заполните логин и пароль.', 'err'); return; }
    rpc('admin_create_user', { p_token: token, p_login: login, p_password: pass, p_full_name: $('#nName').value.trim(), p_role: $('#nRole').value })
      .then(function (data) { if (resultMsg('#createMsg', data)) { window.Auth.log('Создан пользователь', login); ['#nLogin', '#nPass', '#nName'].forEach(function (s) { $(s).value = ''; }); load(); } })
      .catch(function (e) { msg('#createMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#users').addEventListener('change', function (e) {
    var sel = e.target.closest('[data-role]'); if (!sel) return;
    rpc('admin_update_user', { p_token: token, p_user_id: sel.dataset.role, p_role: sel.value, p_active: null, p_full_name: null })
      .then(function (d) { if (d && d[0] && d[0].ok) window.Auth.log('Смена роли', sel.value); resultMsg('#listMsg', d); load(); })
      .catch(function (err) { msg('#listMsg', 'Ошибка: ' + err.message, 'err'); });
  });
  $('#users').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    if (b.dataset.toggle) {
      rpc('admin_update_user', { p_token: token, p_user_id: b.dataset.toggle, p_role: null, p_active: b.dataset.active === 'true', p_full_name: null })
        .then(function (d) { if (d && d[0] && d[0].ok) window.Auth.log('Изменён доступ', b.dataset.active === 'true' ? 'включён' : 'выключен'); resultMsg('#listMsg', d); load(); });
    } else if (b.dataset.pass) {
      var np = window.prompt('Новый пароль для «' + b.dataset.login + '»:', '');
      if (np == null) return;
      rpc('admin_reset_password', { p_token: token, p_user_id: b.dataset.pass, p_password: np }).then(function (d) { if (d && d[0] && d[0].ok) window.Auth.log('Сброс пароля', b.dataset.login); resultMsg('#listMsg', d); });
    } else if (b.dataset.del) {
      if (!window.confirm('Удалить пользователя «' + b.dataset.login + '»?')) return;
      rpc('admin_delete_user', { p_token: token, p_user_id: b.dataset.del }).then(function (d) { if (d && d[0] && d[0].ok) window.Auth.log('Удалён пользователь', b.dataset.login); resultMsg('#listMsg', d); load(); });
    }
  });
  function loadAttempts() {
    return rpc('app_login_attempts_list', { p_token: token, p_limit: 100 }).then(function (a) {
      a = a || [];
      $('#logins').innerHTML = a.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Логин</th><th>Результат</th><th>Время</th></tr></thead><tbody>' +
        a.map(function (x) { return '<tr><td>' + esc(x.login || '—') + '</td><td><span class="badge ' + (x.success ? 'done' : 'cancelled') + '">' + (x.success ? 'успех' : 'отказ') + '</span></td><td class="muted">' + fmtDT(x.created_at) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Записей нет.</span>';
    }).catch(function (e) { msg('#laMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  $('#aq').addEventListener('input', function () { q = this.value; render(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (s.role !== 'admin') { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + ' · ' + roleLabel(s.role);
    $('#nRole').innerHTML = (window.Auth.ROLE_LABELS ? Object.keys(Auth.ROLE_LABELS) : ['admin','owner','manager','supplier'])
      .map(function (r) { return '<option value="' + r + '">' + esc(roleLabel(r)) + '</option>'; }).join('');
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
    loadAttempts();
  });
})();
