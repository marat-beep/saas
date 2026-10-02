/* ============================================================
   3DMP Service · apps/admin — администрирование пользователей
   Доступно только role='admin'. Работает через RPC admin_* (0004_admin.sql).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null, me = null, users = [];

  var ROLES = [['admin', 'Администратор'], ['owner', 'Собственник'], ['manager', 'Менеджер'], ['supplier', 'Поставщик']];
  function roleLabel(r) { for (var i = 0; i < ROLES.length; i++) if (ROLES[i][0] === r) return ROLES[i][1]; return r || '—'; }
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }

  function rpc(name, args) {
    return SB.rpc(name, args).then(function (r) {
      if (r.error) throw new Error(r.error.message);
      return r.data;
    });
  }
  function resultMsg(id, data) {
    var row = data && data[0];
    if (!row) { msg(id, 'Нет ответа', 'err'); return false; }
    msg(id, row.message || (row.ok ? 'Готово' : 'Ошибка'), row.ok ? 'ok' : 'err');
    return row.ok;
  }

  function render() {
    $('#count').textContent = '(' + users.length + ')';
    var rows = users.map(function (u) {
      var isMe = me && u.id === me.user_id;
      var opts = ROLES.map(function (r) {
        return '<option value="' + r[0] + '"' + (u.role === r[0] ? ' selected' : '') + '>' + r[1] + '</option>';
      }).join('');
      return '<tr>' +
        '<td><b>' + esc(u.login) + '</b>' + (isMe ? ' <span class="note">(вы)</span>' : '') + '</td>' +
        '<td>' + esc(u.full_name || '—') + '</td>' +
        '<td><select data-role="' + u.id + '">' + opts + '</select></td>' +
        '<td><span class="pill ' + (u.active ? 'on' : 'off') + '">' + (u.active ? 'активен' : 'выключен') + '</span></td>' +
        '<td style="white-space:nowrap;">' +
        '<button class="act" data-toggle="' + u.id + '" data-active="' + (!u.active) + '">' + (u.active ? 'Выключить' : 'Включить') + '</button>' +
        '<button class="act" data-pass="' + u.id + '" data-login="' + esc(u.login) + '">Пароль</button>' +
        (isMe ? '' : '<button class="act danger" data-del="' + u.id + '" data-login="' + esc(u.login) + '">Удалить</button>') +
        '</td></tr>';
    }).join('');
    $('#users').innerHTML = '<thead><tr><th>Логин</th><th>Имя</th><th>Роль</th><th>Статус</th><th>Действия</th></tr></thead><tbody>' + rows + '</tbody>';
  }

  function load() {
    return rpc('admin_list_users', { p_token: token }).then(function (data) {
      users = data || []; render();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- создание ---------- */
  $('#createBtn').addEventListener('click', function () {
    var login = $('#nLogin').value.trim();
    var pass = $('#nPass').value;
    if (!login || !pass) { msg('#createMsg', 'Заполните логин и пароль.', 'err'); return; }
    rpc('admin_create_user', {
      p_token: token, p_login: login, p_password: pass,
      p_full_name: $('#nName').value.trim(), p_role: $('#nRole').value
    }).then(function (data) {
      if (resultMsg('#createMsg', data)) {
        $('#nLogin').value = ''; $('#nPass').value = ''; $('#nName').value = '';
        load();
      }
    }).catch(function (e) { msg('#createMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  /* ---------- действия в таблице ---------- */
  $('#users').addEventListener('change', function (e) {
    var sel = e.target.closest('[data-role]'); if (!sel) return;
    rpc('admin_update_user', { p_token: token, p_user_id: sel.dataset.role, p_role: sel.value, p_active: null, p_full_name: null })
      .then(function (d) { resultMsg('#listMsg', d); load(); })
      .catch(function (err) { msg('#listMsg', 'Ошибка: ' + err.message, 'err'); });
  });
  $('#users').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    if (b.dataset.toggle) {
      rpc('admin_update_user', { p_token: token, p_user_id: b.dataset.toggle, p_role: null, p_active: b.dataset.active === 'true', p_full_name: null })
        .then(function (d) { resultMsg('#listMsg', d); load(); })
        .catch(function (err) { msg('#listMsg', 'Ошибка: ' + err.message, 'err'); });
    } else if (b.dataset.pass) {
      var np = window.prompt('Новый пароль для «' + b.dataset.login + '»:', '');
      if (np == null) return;
      rpc('admin_reset_password', { p_token: token, p_user_id: b.dataset.pass, p_password: np })
        .then(function (d) { resultMsg('#listMsg', d); })
        .catch(function (err) { msg('#listMsg', 'Ошибка: ' + err.message, 'err'); });
    } else if (b.dataset.del) {
      if (!window.confirm('Удалить пользователя «' + b.dataset.login + '»?')) return;
      rpc('admin_delete_user', { p_token: token, p_user_id: b.dataset.del })
        .then(function (d) { resultMsg('#listMsg', d); load(); })
        .catch(function (err) { msg('#listMsg', 'Ошибка: ' + err.message, 'err'); });
    }
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  /* ---------- старт ---------- */
  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (s.role !== 'admin') { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + ' · ' + roleLabel(s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
