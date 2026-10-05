/* ============================================================
   3DMP Service · apps/platform — платформенное управление тенантами
   Данные: app_platform_* (0020). Доступ: только role='admin'.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, tenants = [], plans = [];

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_platform_tenants', { p_token: token }),
      rpc('app_plans_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) { tenants = r[0] || []; plans = r[1] || [];
      $('#tPlan').innerHTML = plans.map(function (p) { return '<option value="' + p.code + '">' + esc(p.name) + '</option>'; }).join('');
      render();
    }).catch(function (e) { msg('#lMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function render() {
    $('#cnt').textContent = '(' + tenants.length + ')';
    var pOpts = function (sel) { return plans.map(function (p) { return '<option value="' + p.code + '"' + (sel === p.code ? ' selected' : '') + '>' + esc(p.name) + '</option>'; }).join(''); };
    var sOpts = function (sel) { return ['active', 'suspended'].map(function (s) { return '<option value="' + s + '"' + (sel === s ? ' selected' : '') + '>' + (s === 'active' ? 'активна' : 'приостановлена') + '</option>'; }).join(''); };
    $('#tenants').innerHTML = '<thead><tr><th>Организация</th><th>Тариф</th><th>Статус</th><th>Польз.</th><th>Заявок</th><th></th></tr></thead><tbody>' +
      tenants.map(function (t) {
        return '<tr data-id="' + t.id + '"><td><b>' + esc(t.name) + '</b></td>' +
          '<td><select data-plan="' + t.id + '">' + pOpts(t.plan) + '</select></td>' +
          '<td><select data-status="' + t.id + '">' + sOpts(t.status) + '</select></td>' +
          '<td>' + t.users_count + '</td><td>' + t.orders_count + '</td>' +
          '<td><button class="act" data-save="' + t.id + '">Сохранить</button></td></tr>';
      }).join('') + '</tbody>';
    $$('#tenants [data-save]').forEach(function (b) {
      b.addEventListener('click', function () {
        var id = b.dataset.save;
        var plan = $('[data-plan="' + id + '"]').value;
        var status = $('[data-status="' + id + '"]').value;
        rpc('app_platform_tenant_update', { p_token: token, p_tenant_id: id, p_plan: plan, p_status: status, p_brand: null })
          .then(function (d) { var r = d && d[0]; msg('#lMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); window.Auth.log('Платформа: тенант', id); load(); });
      });
    });
  }

  $('#tCreate').addEventListener('click', function () {
    var name = $('#tName').value.trim(), login = $('#tLogin').value.trim();
    if (!name || !login) { msg('#cMsg', 'Укажите название и логин владельца.', 'err'); return; }
    rpc('app_platform_tenant_create', { p_token: token, p_name: name, p_plan: $('#tPlan').value, p_owner_login: login, p_owner_password: $('#tPass').value, p_owner_name: $('#tOwner').value.trim() })
      .then(function (d) { var r = d && d[0]; if (!r || !r.ok) { msg('#cMsg', (r && r.message) || 'Ошибка', 'err'); return; }
        msg('#cMsg', r.message, 'ok'); window.Auth.log('Создана организация', name);
        ['#tName', '#tLogin', '#tPass', '#tOwner'].forEach(function (s) { $(s).value = ''; }); load(); })
      .catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (s.role !== 'admin') { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#lMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
