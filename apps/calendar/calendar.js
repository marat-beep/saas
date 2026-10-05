/* ============================================================
   3DMP Service · apps/calendar — производственный календарь (B38)
   Данные: 0061. Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, list = [];

  var KIND = { holiday: 'Праздник', short: 'Сокращённый', work: 'Рабочий (перенос)', shift: 'Смена' };
  function esc(v) { return ui.esc(v); }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU', { weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric' }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    var from = $('#from').value || null, to = $('#to').value || null;
    return rpc('app_calendar_list', { p_token: token, p_from: from, p_to: to }).then(function (r) {
      list = r || [];
      var h = list.filter(function (x) { return x.kind === 'holiday'; }).length;
      var s = list.filter(function (x) { return x.kind === 'short'; }).length;
      $('#kpis').innerHTML = cell('Записей', list.length) + cell('Праздников', h) + cell('Сокращённых', s) +
        cell('Рабочих (переносов)', list.filter(function (x) { return x.kind === 'work'; }).length);
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function render() {
    $('#cnt').textContent = '(' + list.length + ')';
    $('#list').innerHTML = list.length ? '<table class="table" style="width:100%;border-collapse:collapse"><thead><tr><th>Дата</th><th>Тип</th><th>Название</th><th></th></tr></thead><tbody>' +
      list.map(function (c) {
        return '<tr style="border-bottom:1px solid var(--border)"><td><b>' + fmt(c.cal_date) + '</b></td>' +
          '<td><span class="badge ' + (c.kind === 'holiday' ? 'cancelled' : c.kind === 'short' ? 'in_progress' : 'done') + '">' + (KIND[c.kind] || c.kind) + '</span></td>' +
          '<td>' + esc(c.name || '') + '</td><td><button class="chip" data-del="' + c.id + '">✕</button></td></tr>';
      }).join('') + '</tbody></table>' : '<span class="note">Записей нет.</span>';
    $$('#list [data-del]').forEach(function (b) {
      b.addEventListener('click', function () { rpc('app_calendar_delete', { p_token: token, p_id: b.dataset.del }).then(function () { window.Auth.log('Календарь удалён', b.dataset.del); load(); }); });
    });
  }

  $('#fAdd').addEventListener('click', function () {
    if (!$('#fDate').value) { msg('#fMsg', 'Укажите дату.', 'err'); return; }
    rpc('app_calendar_save', { p_token: token, p_date: $('#fDate').value, p_kind: $('#fKind').value, p_name: $('#fName').value.trim() })
      .then(function (d) { var r = d && d[0]; msg('#fMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { $('#fName').value = ''; load(); } })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#reload').addEventListener('click', function () { load(); });
  $('#cBtn').addEventListener('click', function () {
    if (!$('#cStart').value) { msg('#cMsg', 'Укажите начало.', 'err'); return; }
    var n = parseInt($('#cDays').value || '', 10);
    rpc('app_calendar_add_days', { p_token: token, p_start: $('#cStart').value, p_days: isNaN(n) ? 0 : n }).then(function (r) {
      var d = r && r[0] && r[0].result;
      msg('#cMsg', 'Результат: ' + fmt(d), 'ok');
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
