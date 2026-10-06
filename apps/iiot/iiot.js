/* ============================================================
   3DMP Service · apps/iiot — IIoT-телеметрия и DNC. Данные: 0092.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, jobs = [], q = '';

  var MET = { state: 'Состояние', count: 'Счётчик', speed: 'Обороты', power: 'Мощность', temp: 'Температура', vibration: 'Вибрация', other: 'Прочее' };
  var DS = { queued: ['В очереди', 'normal'], sent: ['Отправлено', 'new'], running: ['Выполняется', 'in_progress'], done: ['Готово', 'done'], failed: ['Ошибка', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_iiot_kpi', { p_token: token }),
      rpc('app_iiot_readings_list', { p_token: token, p_machine: q || null, p_limit: 50 }),
      rpc('app_dnc_list', { p_token: token, p_q: null })
    ]).then(function (r) {
      var k = (r[0] && r[0][0]) || {};
      $('#kpis').innerHTML = cell('Показаний сегодня', k.readings_today || 0) + cell('Станков', k.machines || 0) + cell('DNC-заданий', (r[2] || []).length);
      $('#readings').innerHTML = (r[1] && r[1].length) ? '<table class="mini"><thead><tr><th>Время</th><th>Станок</th><th>Метрика</th><th class="num">Значение</th><th>Источник</th></tr></thead><tbody>' +
        r[1].map(function (x) { return '<tr><td>' + new Date(x.ts).toLocaleString('ru-RU') + '</td><td>' + esc(x.machine) + '</td><td>' + esc(MET[x.metric] || x.metric) + '</td><td class="num">' + x.value + '</td><td>' + esc(x.source || '') + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Нет показаний.</span>';
      jobs = r[2] || []; renderDnc();
    }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderDnc() {
    $('#dCnt').textContent = '(' + jobs.length + ')';
    $('#dnc').innerHTML = jobs.length ? jobs.map(function (d) {
      var st = DS[d.status] || [d.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(d.program_name) + '</b>' +
        '<span class="note">' + esc(d.machine) + '</span></div>' +
        '<div class="toolbar mt">' +
        (d.status === 'queued' ? '<button class="btn secondary" data-st="sent" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">Отправлено</button>' : '') +
        (d.status === 'sent' ? '<button class="btn secondary" data-st="running" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">Выполняется</button>' : '') +
        (d.status !== 'done' ? '<button class="btn" data-st="done" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">Готово</button>' : '') +
        (d.status !== 'failed' && d.status !== 'done' ? '<button class="btn secondary" data-st="failed" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">Ошибка</button>' : '') +
        '</div></div>';
    }).join('') : '<span class="note">Очередь пуста.</span>';
    $$('#dnc [data-st]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_dnc_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.st }).then(load).catch(function (e) { msg('#dMsg', e.message, 'err'); }); }); });
  }

  $('#iSave').addEventListener('click', function () {
    rpc('app_iiot_ingest', { p_token: token, p_machine: $('#iMachine').value, p_metric: $('#iMetric').value, p_value: parseFloat($('#iValue').value) || 0 })
      .then(function (r) { var x = r && r[0]; msg('#iMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); load(); })
      .catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#dSave').addEventListener('click', function () {
    rpc('app_dnc_save', { p_token: token, p_id: null, p_machine: $('#dMachine').value, p_program_name: $('#dProgram').value, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#dMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); load(); })
      .catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#q').addEventListener('input', function () { q = this.value; load(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#iMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
