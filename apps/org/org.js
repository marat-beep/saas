/* ============================================================
   3DMP Service · apps/org — организация (тенант)
   Тариф, пользователи, feature flags. Данные: app_tenant_*, app_plans_* (0014).
   Роли: admin/owner (изменение), manager (просмотр).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, users = [], plans = [], info = null, flags = {};

  var MODULES = [
    ['orders', 'Заявки'], ['production', 'Производство'], ['procurement', 'Закупки'], ['supplier', 'Портал поставщика'],
    ['warehouse', 'Склад'], ['bom', 'Спецификации'], ['planning', 'Планирование'], ['qc', 'ОТК'],
    ['passport', 'Паспорта'], ['economics', 'Экономика'], ['reports', 'Отчёты']
  ];
  var ROLES = [['admin', 'Администратор'], ['owner', 'Владелец'], ['manager', 'Менеджер'], ['supplier', 'Поставщик']];

  function esc(v) { return ui.esc(v); }
  function fmt(ts) { if (!ts) return '—'; var d = new Date(ts); return isNaN(d.getTime()) ? '—' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function isOwner() { return me && (me.role === 'owner' || me.role === 'admin'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_tenant_info', { p_token: token }),
      rpc('app_tenant_users', { p_token: token }),
      rpc('app_plans_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_tenant_flags', { p_token: token }).catch(function () { return {}; })
    ]).then(function (r) {
      info = (r[0] && r[0][0]) || {}; users = r[1] || []; plans = r[2] || []; flags = r[3] || {};
      renderKpi(); renderUsers(); renderPlans(); renderFlags();
    }).catch(function (e) { msg('#lMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    var lim = info.max_users ? info.max_users : '∞';
    $('#kpis').innerHTML =
      kpi(esc(info.name || '—'), 'Организация') + kpi(esc(info.plan_name || info.plan || '—'), 'Тариф') +
      kpi(info.users_count + ' / ' + lim, 'Пользователи') + kpi(plans.length ? (plans.filter(function (p) { return p.code === info.plan; })[0] || {}).price : '—', 'Стоимость, ₽/мес');
  }
  function kpi(v, l) { return '<div class="kpi"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>'; }

  function renderUsers() {
    $('#uCount').textContent = '(' + users.length + ')';
    var rows = users.map(function (u) {
      var isMe = me && u.id === me.user_id;
      var opts = ROLES.map(function (r) { return '<option value="' + r[0] + '"' + (u.role === r[0] ? ' selected' : '') + '>' + r[1] + '</option>'; }).join('');
      return '<tr><td><b>' + esc(u.login) + '</b>' + (isMe ? ' <span class="note">(вы)</span>' : '') + '</td>' +
        '<td>' + esc(u.full_name || '—') + '</td>' +
        '<td><select data-role="' + u.id + '"' + (isOwner() ? '' : ' disabled') + '>' + opts + '</select></td>' +
        '<td>' + (u.active ? '<span class="note">активен</span>' : '<span class="note">выключен</span>') + '</td>' +
        '<td>' + fmt(u.last_login_at) + '</td>' +
        '<td style="white-space:nowrap;">' +
        '<button class="act" data-pass="' + u.id + '" data-login="' + esc(u.login) + '">Пароль</button>' +
        (isMe ? '' : '<button class="act ' + (u.active ? 'danger' : '') + '" data-toggle="' + u.id + '" data-active="' + (!u.active) + '">' + (u.active ? 'Выключить' : 'Включить') + '</button>') +
        '</td></tr>';
    }).join('');
    $('#users').innerHTML = '<thead><tr><th>Логин</th><th>Имя</th><th>Роль</th><th>Статус</th><th>Вход</th><th>Действия</th></tr></thead><tbody>' + rows + '</tbody>';
  }
  function renderPlans() {
    $('#planSel').innerHTML = plans.map(function (p) {
      return '<option value="' + p.code + '"' + (info.plan === p.code ? ' selected' : '') + '>' + esc(p.name) + ' · ' + (Number(p.price) || 0).toLocaleString('ru-RU') + ' ₽/мес' + (p.max_users ? ' · до ' + p.max_users + ' польз.' : '') + '</option>';
    }).join('');
    $('#planSel').disabled = !isOwner();
  }
  function renderFlags() {
    $('#flags').innerHTML = MODULES.map(function (m) {
      var on = flags[m[0]] !== false;
      return '<label class="flag"><input type="checkbox" data-flag="' + m[0] + '"' + (on ? ' checked' : '') + (isOwner() ? '' : ' disabled') + '> ' + m[1] + '</label>';
    }).join('');
  }

  $('#uCreate').addEventListener('click', function () {
    var login = $('#uLogin').value.trim();
    if (!login) { msg('#cMsg', 'Укажите логин.', 'err'); return; }
    rpc('app_tenant_user_create', { p_token: token, p_login: login, p_password: $('#uPass').value, p_full_name: $('#uName').value.trim(), p_role: $('#uRole').value })
      .then(function (d) { var r = d && d[0]; if (!r || !r.ok) { msg('#cMsg', (r && r.message) || 'Ошибка', 'err'); return; }
        window.Auth.log('Добавлен пользователь', login); msg('#cMsg', r.message, 'ok');
        $('#uLogin').value = ''; $('#uPass').value = ''; $('#uName').value = ''; load(); })
      .catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#users').addEventListener('change', function (e) {
    var sel = e.target.closest('[data-role]'); if (!sel || !isOwner()) return;
    rpc('app_tenant_user_update', { p_token: token, p_user_id: sel.dataset.role, p_role: sel.value, p_active: null, p_full_name: null })
      .then(function () { window.Auth.log('Роль пользователя', sel.value); msg('#lMsg', 'Сохранено', 'ok'); })
      .catch(function (e2) { msg('#lMsg', 'Ошибка: ' + e2.message, 'err'); });
  });
  $('#users').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    if (b.dataset.toggle) {
      rpc('app_tenant_user_update', { p_token: token, p_user_id: b.dataset.toggle, p_role: null, p_active: b.dataset.active === 'true', p_full_name: null })
        .then(function (d) { var r = d && d[0]; msg('#lMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); load(); })
        .catch(function (e2) { msg('#lMsg', 'Ошибка: ' + e2.message, 'err'); });
    } else if (b.dataset.pass) {
      var np = window.prompt('Новый пароль для «' + b.dataset.login + '»:', '');
      if (np == null) return;
      rpc('app_tenant_user_reset', { p_token: token, p_user_id: b.dataset.pass, p_password: np })
        .then(function (d) { var r = d && d[0]; msg('#lMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); });
    }
  });

  $('#planSave').addEventListener('click', function () {
    rpc('app_tenant_set_plan', { p_token: token, p_plan: $('#planSel').value })
      .then(function (d) { var r = d && d[0]; msg('#pMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); window.Auth.log('Смена тарифа', $('#planSel').value); load(); })
      .catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#flagSave').addEventListener('click', function () {
    if (!isOwner()) { msg('#fMsg', 'Только владелец может менять модули.', 'err'); return; }
    var cbs = $$('#flags [data-flag]');
    var seq = Promise.resolve();
    cbs.forEach(function (cb) {
      seq = seq.then(function () { return rpc('app_tenant_set_flag', { p_token: token, p_module: cb.dataset.flag, p_enabled: cb.checked }); });
    });
    seq.then(function () { msg('#fMsg', 'Модули сохранены.', 'ok'); window.Auth.log('Модули организации', ''); window.AppNotify.refresh(true); })
       .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (['admin', 'owner', 'manager'].indexOf(s.role) < 0) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#lMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
