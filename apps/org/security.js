/* ============================================================
   3DMP Service · apps/org/security.js (W39) — «Безопасность»:
   2FA, смена пароля, мои устройства/сессии, политика, журнал доступа.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null;

  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function msg(id, t, k) { var e = $(id); if (!e) return; e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '—' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function dlg(title, fields) { return ui.formDialog({ title: title, fields: fields, okText: 'Ок' }); }

  function loadSec() {
    if (!token) return;
    Promise.all([
      rpc('app_my_security', { p_token: token }),
      rpc('app_my_sessions', { p_token: token }),
      rpc('app_security_policy_get', { p_token: token })
    ]).then(function (r) {
      var s = (r[0] && r[0][0]) || {}, sess = r[1] || [], pol = (r[2] && r[2][0]) || {};
      var st = $('#secState'); if (st) st.innerHTML = '2FA: <b>' + (s.totp_enabled ? 'включена' : (s.totp_configured ? 'настроена (не включена)' : 'не настроена')) + '</b>' +
        (s.must_change_password ? ' · <span style="color:#b91c1c">требуется смена пароля</span>' : '');
      if ($('#secCnt')) $('#secCnt').textContent = '(' + sess.length + ')';
      $('#secSessions').innerHTML = '<tr><th>Статус</th><th>Устройство</th><th>Клиент</th><th>Активность</th><th>Истекает</th><th></th></tr>' +
        (sess.length ? sess.map(function (x) {
          return '<tr><td>' + (x.current ? '<b>Текущее</b>' : '') + '</td><td>' + esc(x.device || '—') + '</td>' +
            '<td class="note">' + esc(String(x.ua || '').substring(0, 44)) + '</td><td>' + fmt(x.last_seen) + '</td><td>' + fmt(x.expires_at) + '</td>' +
            '<td>' + (x.current ? '' : '<button class="act danger" data-rev="' + x.session_id + '">Завершить</button>') + '</td></tr>';
        }).join('') : '<tr><td colspan="6" class="note">Сессий нет</td></tr>');
      $$('#secSessions [data-rev]').forEach(function (b) { b.addEventListener('click', function () { revoke(b.dataset.rev); }); });

      if ($('#polPwdMin')) $('#polPwdMin').value = pol.pwd_min_len || 8;
      if ($('#polPwdExp')) $('#polPwdExp').value = pol.pwd_expire_days || 0;
      if ($('#polTtl')) $('#polTtl').value = pol.session_ttl_min || 0;
      if ($('#polIp')) $('#polIp').value = pol.ip_allowlist || '';
      if ($('#polRoles')) $('#polRoles').value = (pol.require_2fa_roles || []).join(', ');
    }).catch(function (e) { msg('#secMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function revoke(id) {
    rpc('app_session_revoke', { p_token: token, p_session: id }).then(function (r) {
      var x = r && r[0]; msg('#secMsg', x && x.ok ? 'Сессия завершена' : (x && x.message) || 'Готово', x && x.ok ? 'ok' : 'err'); loadSec();
    }).catch(function (e) { msg('#secMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* 2FA */
  $('#sec2faPrep') && $('#sec2faPrep').addEventListener('click', function () {
    rpc('app_2fa_setup', { p_token: token }).then(function (r) {
      var x = r && r[0]; if (!x) return;
      $('#sec2faSetup').style.display = '';
      $('#sec2faSecret').value = x.secret || '';
      $('#sec2faUri').value = x.uri || '';
      msg('#secMsg', 'Секрет создан. Добавьте его в приложение-аутентификатор и введите код.', 'info');
    }).catch(function (e) { msg('#secMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#sec2faOn') && $('#sec2faOn').addEventListener('click', function () {
    var code = ($('#sec2faCode').value || '').trim();
    rpc('app_2fa_enable', { p_token: token, p_code: code }).then(function (r) {
      var x = r && r[0]; msg('#secMsg', (x && x.message) || 'Готово', x && x.ok ? 'ok' : 'err');
      if (x && x.ok) { $('#sec2faSetup').style.display = 'none'; if (window.Auth) Auth.log('2FA', 'включена'); }
      loadSec();
    }).catch(function (e) { msg('#secMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#sec2faOff') && $('#sec2faOff').addEventListener('click', function () {
    dlg('Отключение 2FA', [{ name: 'code', label: 'Код 2FA', required: true }]).then(function (v) {
      if (!v) return;
      rpc('app_2fa_disable', { p_token: token, p_code: v.code }).then(function (r) {
        var x = r && r[0]; msg('#secMsg', (x && x.message) || 'Готово', x && x.ok ? 'ok' : 'err'); loadSec();
      }).catch(function (e) { msg('#secMsg', 'Ошибка: ' + e.message, 'err'); });
    });
  });

  /* Смена пароля */
  $('#pwdSave') && $('#pwdSave').addEventListener('click', function () {
    var o = ($('#pwdOld').value || ''), n = ($('#pwdNew').value || '');
    if (!o || !n) { msg('#secMsg', 'Укажите текущий и новый пароль', 'err'); return; }
    rpc('app_password_change', { p_token: token, p_old: o, p_new: n }).then(function (r) {
      var x = r && r[0]; msg('#secMsg', (x && x.message) || 'Готово', x && x.ok ? 'ok' : 'err');
      if (x && x.ok) { $('#pwdOld').value = ''; $('#pwdNew').value = ''; if (window.Auth) Auth.log('Пароль', 'изменён'); loadSec(); }
    }).catch(function (e) { msg('#secMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  /* Сессии: завершить прочие */
  $('#secRevokeAll') && $('#secRevokeAll').addEventListener('click', function () {
    rpc('app_session_revoke_all', { p_token: token }).then(function (r) {
      var x = r && r[0]; msg('#secMsg', x && x.ok ? ('Завершено сессий: ' + (x.cnt || 0)) : ((x && x.message) || 'Готово'), x && x.ok ? 'ok' : 'err'); loadSec();
    }).catch(function (e) { msg('#secMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  /* Политика */
  $('#polSave') && $('#polSave').addEventListener('click', function () {
    var roles = ($('#polRoles').value || '').split(',').map(function (x) { return x.trim(); }).filter(Boolean);
    rpc('app_security_policy_set', {
      p_token: token, p_require_2fa_roles: roles,
      p_pwd_min_len: Number($('#polPwdMin').value) || 8,
      p_pwd_expire_days: Number($('#polPwdExp').value) || 0,
      p_session_ttl_min: Number($('#polTtl').value) || 0,
      p_ip_allowlist: ($('#polIp').value || '').trim() || null
    }).then(function (r) {
      var x = r && r[0]; msg('#secMsg', (x && x.message) || 'Готово', x && x.ok ? 'ok' : 'err'); loadSec();
    }).catch(function (e) { msg('#secMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  /* Журнал доступа (admin) */
  $('#logLoad') && $('#logLoad').addEventListener('click', function () {
    rpc('app_access_log_list', { p_token: token, p_limit: 100 }).then(function (list) {
      $('#secLog').innerHTML = '<tr><th>Источник</th><th>Логин</th><th>Действие</th><th>Деталь</th><th>Время</th></tr>' +
        (list || []).map(function (x) {
          return '<tr><td>' + esc(x.src) + '</td><td>' + esc(x.login) + '</td><td>' + esc(x.action) + '</td><td class="note">' + esc(x.detail || '') + '</td><td>' + fmt(x.created_at) + '</td></tr>';
        }).join('');
      msg('#logMsg', 'Загружено записей: ' + (list ? list.length : 0), 'ok');
    }).catch(function (e) { msg('#logMsg', 'Доступно администратору платформы: ' + e.message, 'err'); });
  });

  window.addEventListener('load', function () {
    var s = window.Auth && window.Auth.session && window.Auth.session();
    if (!s) return;
    token = s.token; me = s;
    loadSec();
  });
})();
