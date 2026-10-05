/* ============================================================
   3DMP Service · apps/org — Админ-панель клиента (организация)
   Пользователи/роли, модули (flags), тариф, бренд. Данные: 0014+0020+0041.
   Редактирование: owner/admin. Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB, C = window.AppCatalog;
  var token = null, me = null, users = [], plans = [], info = null, flags = {}, brand = {};

  var ROLE_SETS = [
    ['owner', 'Владелец организации'], ['director', 'Директор'], ['chief', 'Начальник цеха/участка'],
    ['master', 'Мастер/бригадир'], ['technologist', 'Технолог/инженер'], ['operator', 'Оператор ЧПУ'],
    ['supply', 'Снабженец'], ['qc', 'ОТК/метролог'], ['economist', 'Экономист/бухгалтер'],
    ['manager', 'Менеджер'], ['supplier', 'Поставщик'], ['admin', 'Администратор платформы']
  ];
  var SKIP = { auth: 1, panel: 1, dashboard: 1, guide: 1, modules: 1, eco: 1, platform: 1, admin: 1, diagnostics: 1, roles: 1 };

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
      rpc('app_tenant_flags', { p_token: token }).catch(function () { return {}; }),
      rpc('app_tenant_brand', { p_token: token }).catch(function () { return {}; })
    ]).then(function (r) {
      info = (r[0] && r[0][0]) || {}; users = r[1] || []; plans = r[2] || []; flags = r[3] || {}; brand = r[4] || {};
      $('#uRole').innerHTML = ROLE_SETS.map(function (x) { return '<option value="' + x[0] + '">' + x[1] + '</option>'; }).join('');
      renderKpi(); renderUsers(); renderPlans(); renderFlags(); renderBrand();
    }).catch(function (e) { msg('#lMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    var lim = info.max_users ? info.max_users : '∞';
    var plan = plans.filter(function (p) { return p.code === info.plan; })[0] || {};
    $('#kpis').innerHTML = cell('Организация', esc(info.name || '—')) + cell('Тариф', esc(info.plan_name || info.plan || '—')) +
      cell('Пользователи', (users.length) + ' / ' + lim) + cell('Статус', esc(info.status || 'active')) +
      cell('Стоимость', plan.price != null ? Number(plan.price).toLocaleString('ru-RU') + ' ₽' : '—');
    function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  }
  function renderBrand() {
    $('#brName').value = brand.name || info.name || '';
    $('#brColor').value = brand.color || '';
    $('#brLogo').value = brand.logo || '';
    $('#brName').disabled = !isOwner(); $('#brColor').disabled = !isOwner(); $('#brLogo').disabled = !isOwner(); $('#brSave').disabled = !isOwner();
  }
  function renderUsers() {
    $('#uCount').textContent = '(' + users.length + ')';
    var rows = users.map(function (u) {
      var isMe = me && u.id === me.user_id;
      var opts = ROLE_SETS.map(function (r) { return '<option value="' + r[0] + '"' + (u.role === r[0] ? ' selected' : '') + '>' + r[1] + '</option>'; }).join('');
      return '<tr><td><b>' + esc(u.login) + '</b>' + (isMe ? ' <span class="note">(вы)</span>' : '') + '</td>' +
        '<td>' + esc(u.full_name || '—') + '</td>' +
        '<td><select data-role="' + u.id + '"' + (isOwner() ? '' : ' disabled') + '>' + opts + '</select></td>' +
        '<td>' + (u.active ? '<span class="badge done">активен</span>' : '<span class="badge cancelled">выключен</span>') + '</td>' +
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
    $('#planSel').disabled = !isOwner(); $('#planSave').disabled = !isOwner();
  }
  function renderFlags() {
    var mods = (C.apps || []).filter(function (a) { return !SKIP[a.id]; });
    $('#flags').innerHTML = mods.map(function (a) {
      var on = flags[a.id] !== false;
      return '<label><input type="checkbox" data-flag="' + a.id + '"' + (on ? ' checked' : '') + (isOwner() ? '' : ' disabled') + '> ' + a.icon + ' ' + esc(a.title) + '</label>';
    }).join('');
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    ['org', 'users', 'mods', 'plan'].forEach(function (t) { $('#t-' + t).style.display = (b.dataset.t === t) ? '' : 'none'; });
  });

  $('#brSave').addEventListener('click', function () {
    if (!isOwner()) return;
    rpc('app_tenant_set_brand', { p_token: token, p_brand: { name: $('#brName').value.trim(), color: $('#brColor').value.trim(), logo: $('#brLogo').value.trim() } })
      .then(function (d) { var r = d && d[0]; msg('#bMsg', (r && r.message) || 'Сохранено', r && r.ok ? 'ok' : 'err'); window.Auth.log('Бренд организации', ''); })
      .catch(function (e) { msg('#bMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#uCreate').addEventListener('click', function () {
    var login = $('#uLogin').value.trim();
    if (!login) { msg('#cMsg', 'Укажите логин.', 'err'); return; }
    rpc('app_tenant_user_create', { p_token: token, p_login: login, p_password: $('#uPass').value, p_full_name: $('#uName').value.trim(), p_role: $('#uRole').value })
      .then(function (d) { var r = d && d[0]; if (!r || !r.ok) { msg('#cMsg', (r && r.message) || 'Ошибка', 'err'); return; }
        window.Auth.log('Добавлен пользователь', login); msg('#cMsg', r.message, 'ok');
        ['#uLogin', '#uPass', '#uName'].forEach(function (s) { $(s).value = ''; }); load(); })
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
        .then(function (d) { var r = d && d[0]; msg('#lMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); load(); });
    } else if (b.dataset.pass) {
      var np = window.prompt('Новый пароль для «' + b.dataset.login + '»:', '');
      if (np == null) return;
      rpc('app_tenant_user_reset', { p_token: token, p_user_id: b.dataset.pass, p_password: np })
        .then(function (d) { var r = d && d[0]; msg('#lMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); });
    }
  });

  $('#planSave').addEventListener('click', function () {
    rpc('app_tenant_set_plan', { p_token: token, p_plan: $('#planSel').value })
      .then(function (d) { var r = d && d[0]; msg('#pMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); window.Auth.log('Смена тарифа', $('#planSel').value); load(); });
  });
  $('#flagSave').addEventListener('click', function () {
    if (!isOwner()) { msg('#fMsg', 'Только владелец может менять модули.', 'err'); return; }
    var cbs = $$('#flags [data-flag]'); var seq = Promise.resolve();
    cbs.forEach(function (cb) { seq = seq.then(function () { return rpc('app_tenant_set_flag', { p_token: token, p_module: cb.dataset.flag, p_enabled: cb.checked }); }); });
    seq.then(function () { msg('#fMsg', 'Модули сохранены.', 'ok'); window.Auth.log('Модули организации', ''); if (window.AppNotify) window.AppNotify.refresh(true); })
       .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#lMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
