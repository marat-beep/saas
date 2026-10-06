/* ============================================================
   3DMP Service · apps/scale — масштаб/эксплуатация. Данные: 0072.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null, page = 1, size = 10, kind = 'orders';

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function runSmoke() {
    msg('#smMsg', '');
    Promise.all([
      rpc('app_smoke_test', { p_token: token }),
      rpc('app_smoke_test_ext', { p_token: token }).catch(function () { return []; })
    ]).then(function (res) {
      var rows = (res[0] || []).concat(res[1] || []);
      var okc = rows.filter(function (r) { return r.ok; }).length;
      $('#smCnt').textContent = '(' + okc + '/' + rows.length + ')';
      $('#smoke').innerHTML = '<table class="mini"><thead><tr><th>Проверка</th><th>Результат</th><th>Детали</th></tr></thead><tbody>' +
        rows.map(function (r) { return '<tr><td>' + esc(r.name) + '</td><td class="' + (r.ok ? 'ok' : 'bad') + '">' + (r.ok ? 'OK' : 'ОШИБКА') + '</td><td>' + esc(r.detail || '') + '</td></tr>'; }).join('') + '</tbody></table>';
    }).catch(function (e) { msg('#smMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function loadStats() {
    rpc('app_scale_stats', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#statsCard').style.display = 'block';
      $('#stats').innerHTML = '<div class="kpi"><small>Таблиц</small><b>' + (k.tables || 0) + '</b></div>' +
        '<div class="kpi"><small>Функций</small><b>' + (k.functions || 0) + '</b></div>' +
        '<div class="kpi"><small>Пользователей</small><b>' + (k.users || 0) + '</b></div>' +
        '<div class="kpi"><small>Заявок</small><b>' + (k.orders || 0) + '</b></div>' +
        '<div class="kpi"><small>Нарядов</small><b>' + (k.naryads || 0) + '</b></div>' +
        '<div class="kpi"><small>Вложений</small><b>' + (k.attachments || 0) + '</b></div>' +
        '<div class="kpi"><small>Объём вложений</small><b>' + Math.round((k.attachments_bytes || 0) / 1024) + ' КБ</b></div>';
    }).catch(function () {});
  }

  function loadBackups() {
    rpc('app_backup_list', { p_token: token, p_limit: 50 }).then(function (r) {
      $('#backupCard').style.display = 'block';
      var rows = r || [];
      $('#backup').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Дата</th><th>Тип</th><th>Область</th><th>Примечание</th><th>Кто</th></tr></thead><tbody>' +
        rows.map(function (b) { return '<tr><td>' + new Date(b.created_at).toLocaleString('ru-RU') + '</td><td>' + esc(b.kind) + '</td><td>' + esc(b.scope || '') + '</td><td>' + esc(b.note || '') + '</td><td>' + esc(b.by_login || '') + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Записей нет.</span>';
    }).catch(function () {});
  }

  function loadPage() {
    $('#pInfo').textContent = 'стр. ' + page;
    Promise.all([
      rpc('app_page_rows', { p_token: token, p_kind: kind, p_page: page, p_size: size, p_q: $('#pQ').value || null }),
      rpc('app_page_count', { p_token: token, p_kind: kind, p_q: $('#pQ').value || null })
    ]).then(function (r) {
      var rows = r[0] || [], total = r[1] || 0;
      var pages = Math.max(1, Math.ceil(total / size));
      $('#pInfo').textContent = 'стр. ' + page + ' из ' + pages + ' (' + total + ')';
      $('#pList').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Название</th><th>Доп.</th><th>Мета</th><th>Дата</th></tr></thead><tbody>' +
        rows.map(function (x) { return '<tr><td>' + esc(x.title || '') + '</td><td>' + esc(x.subtitle || '') + '</td><td>' + esc(x.meta || '') + '</td><td>' + new Date(x.created_at).toLocaleDateString('ru-RU') + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Нет данных.</span>';
      $('#pNext').disabled = page >= pages;
      $('#pPrev').disabled = page <= 1;
    }).catch(function (e) { msg('#smMsg', 'Ошибка страницы: ' + e.message, 'err'); });
  }

  $('#runSmoke').addEventListener('click', runSmoke);
  $('#pKind').addEventListener('change', function () { kind = this.value; page = 1; loadPage(); });
  $('#pQ').addEventListener('input', function () { page = 1; loadPage(); });
  $('#pPrev').addEventListener('click', function () { if (page > 1) { page--; loadPage(); } });
  $('#pNext').addEventListener('click', function () { page++; loadPage(); });
  $('#bAdd').addEventListener('click', function () {
    rpc('app_backup_note', { p_token: token, p_kind: $('#bKind').value, p_scope: $('#bScope').value, p_note: $('#bNote').value })
      .then(function (r) { var x = r && r[0]; msg('#bMsg', x ? x.message : 'Ошибка', x && x.ok ? 'ok' : 'err'); loadBackups(); })
      .catch(function (e) { msg('#bMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#smMsg', 'Supabase не подключён.', 'err'); return; }
    loadPage(); loadStats(); loadBackups(); runSmoke();
  });
})();
