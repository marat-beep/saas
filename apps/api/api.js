/* ============================================================
   3DMP Service · apps/api — API-ключи и вебхуки
   Данные: app_api_key_*, app_webhook_* (0018_api.sql). Роли: owner/manager/admin.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, keys = [], hooks = [];
  var BASE = 'https://zfkbzzmtbrueaksfaqbf.supabase.co';

  function esc(v) { return ui.esc(v); }
  function fmt(ts) { if (!ts) return '—'; var d = new Date(ts); return isNaN(d.getTime()) ? '—' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function isOwner() { return me && (me.role === 'owner' || me.role === 'admin'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_api_key_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_webhook_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) { keys = r[0] || []; hooks = r[1] || []; renderKeys(); renderHooks(); renderSample(); })
      .catch(function (e) { msg('#kMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderKeys() {
    if (!keys.length) { $('#keys').innerHTML = '<tr><td class="note">Ключей нет.</td></tr>'; return; }
    $('#keys').innerHTML = '<thead><tr><th>Название</th><th>Ключ</th><th>Статус</th><th>Использован</th><th></th></tr></thead><tbody>' +
      keys.map(function (k) {
        return '<tr><td>' + esc(k.name) + '</td><td><code>' + esc(k.api_key) + '</code></td>' +
          '<td>' + (k.active ? '<span class="note">активен</span>' : '<span class="note">отозван</span>') + '</td>' +
          '<td>' + fmt(k.last_used_at) + '</td>' +
          '<td style="white-space:nowrap;"><button class="act" data-copy="' + esc(k.api_key) + '">Копировать</button>' +
          (k.active && isOwner() ? '<button class="act danger" data-rev="' + k.id + '">Отозвать</button>' : '') + '</td></tr>';
      }).join('') + '</tbody>';
  }
  function renderHooks() {
    if (!hooks.length) { $('#hooks').innerHTML = '<tr><td class="note">Вебхуков нет.</td></tr>'; return; }
    $('#hooks').innerHTML = '<thead><tr><th>URL</th><th>Событие</th><th>Статус</th><th></th></tr></thead><tbody>' +
      hooks.map(function (h) {
        return '<tr><td><code>' + esc(h.url) + '</code></td><td>' + esc(h.event) + '</td>' +
          '<td>' + (h.active ? '<span class="note">вкл</span>' : '<span class="note">выкл</span>') + '</td>' +
          '<td style="white-space:nowrap;">' +
          (isOwner() ? '<button class="act" data-tg="' + h.id + '" data-active="' + (!h.active) + '">' + (h.active ? 'Выкл' : 'Вкл') + '</button>' +
            '<button class="act danger" data-del="' + h.id + '">Удалить</button>' : '') + '</td></tr>';
      }).join('') + '</tbody>';
  }
  function renderSample() {
    var k = (keys.filter(function (x) { return x.active; })[0] || {}).api_key || 'ВАШ-КЛЮЧ';
    $('#sample').textContent =
      'curl -X POST "' + BASE + '/rest/v1/rpc/api_orders" \\\n' +
      '  -H "apikey: <publishable-ключ>" -H "Content-Type: application/json" \\\n' +
      '  -d \'{"p_key":"' + k + '"}\'\n\n' +
      '# Доступные функции: api_orders, api_tenders, api_stock';
  }

  $('#keys').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    if (b.dataset.copy) { try { navigator.clipboard.writeText(b.dataset.copy); ui.toast('Ключ скопирован'); } catch (err) {} }
    else if (b.dataset.rev) {
      rpc('app_api_key_revoke', { p_token: token, p_id: b.dataset.rev }).then(function () { ui.toast('Ключ отозван'); load(); });
    }
  });
  $('#hooks').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    if (b.dataset.tg) { rpc('app_webhook_toggle', { p_token: token, p_id: b.dataset.tg, p_active: b.dataset.active === 'true' }).then(function () { load(); }); }
    else if (b.dataset.del) { rpc('app_webhook_delete', { p_token: token, p_id: b.dataset.del }).then(function () { ui.toast('Удалено'); load(); }); }
  });

  $('#kCreate').addEventListener('click', function () {
    rpc('app_api_key_create', { p_token: token, p_name: $('#kName').value.trim() })
      .then(function (d) { var r = d && d[0]; if (!r) { msg('#kMsg', 'Ошибка', 'err'); return; }
        msg('#kMsg', 'Ключ создан. Скопируйте его — он нужен для внешних систем.', 'ok');
        window.Auth.log('Создан API-ключ', r.api_key); $('#kName').value = ''; load(); });
  });
  $('#wAdd').addEventListener('click', function () {
    rpc('app_webhook_add', { p_token: token, p_url: $('#wUrl').value.trim(), p_event: $('#wEvent').value })
      .then(function (d) { var r = d && d[0]; msg('#wMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { $('#wUrl').value = ''; load(); } });
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#kMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
