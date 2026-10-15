/* ============================================================
   3DMP Service · apps/iiot — IIoT/DNC + W9 (коннекторы, OEE онлайн, износ). Данные: 0092, 0154.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, jobs = [], conns = [], q = '', lastReadings = [], edge = [];

  var MET = { state: 'Состояние', count: 'Счётчик', speed: 'Обороты', power: 'Мощность', temp: 'Температура', vibration: 'Вибрация', runtime_min: 'Наработка, мин', other: 'Прочее' };
  var DS = { queued: ['В очереди', 'normal'], sent: ['Отправлено', 'new'], running: ['Выполняется', 'in_progress'], done: ['Готово', 'done'], failed: ['Ошибка', 'cancelled'] };
  var KIND = { opcua: 'OPC UA', mtconnect: 'MTConnect', modbus: 'Modbus', manual: 'Вручную' };
  var WSTAT = { ok: ['Норма', 'done'], due: ['К заточке', ''], worn: ['Изношен', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function num(v) { return (Number(v) || 0).toLocaleString('ru-RU'); }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'conn' && !conns.length) loadConns();
    if (scr === 'oee') loadOee();
    if (scr === 'wear') loadWear();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

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
      lastReadings = r[1] || [];
      jobs = r[2] || []; renderDnc(); sparkline(lastReadings);
    }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* P19: тренды по метрикам (sparkline) и экспорт показаний CSV */
  function sparkline(rows) {
    var host = document.getElementById('spark'); if (!host) return;
    if (!rows || !rows.length) { host.innerHTML = ''; return; }
    var byM = {};
    rows.forEach(function (x) { if (x.value == null || x.value === '') return; (byM[x.metric] = byM[x.metric] || []).push(Number(x.value)); });
    host.innerHTML = Object.keys(byM).slice(0, 3).map(function (m) {
      var arr = byM[m].slice(0, 40).reverse();
      if (!arr.length) return '';
      var min = Math.min.apply(null, arr), max = Math.max.apply(null, arr), rng = (max - min) || 1, W = 260, H = 40, n = arr.length;
      var pts = arr.map(function (v, i) { return (n > 1 ? i / (n - 1) * W : 0).toFixed(1) + ',' + (H - (v - min) / rng * H).toFixed(1); }).join(' ');
      return '<div class="kvr" style="align-items:center;"><b style="min-width:120px;">' + esc(MET[m] || m) + '</b>' +
        '<svg width="' + W + '" height="' + H + '" style="flex:0 0 auto;"><polyline points="' + pts + '" fill="none" stroke="#10b981" stroke-width="2"/></svg>' +
        '<span class="note" style="margin-left:auto;">мин ' + min + ' · макс ' + max + '</span></div>';
    }).join('');
  }
  function exportCsv() {
    if (!lastReadings.length) { msg('#iMsg', 'Нет показаний для экспорта', 'err'); return; }
    var head = 'Время;Станок;Метрика;Значение;Источник\n';
    var body = lastReadings.map(function (x) { return [new Date(x.ts).toLocaleString('ru-RU'), x.machine || '', (MET[x.metric] || x.metric), x.value, x.source || ''].join(';'); }).join('\n');
    var blob = new Blob(['\ufeff' + head + body], { type: 'text/csv;charset=utf-8' });
    var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'iiot-readings.csv'; a.click(); setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
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

  /* ---------- Коннекторы (0154) ---------- */
  function loadConns() {
    return rpc('app_iiot_connectors_list', { p_token: token }).then(function (r) {
      conns = r || []; renderConns();
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderConns() {
    $('#conns').innerHTML = conns.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Название</th><th>Тип</th><th>Endpoint</th><th>Активен</th><th>Последний запуск</th><th>Статус</th><th>Действия</th></tr></thead><tbody>' +
      conns.map(function (c) {
        return '<tr><td><b>' + esc(c.name) + '</b></td><td>' + esc(KIND[c.kind] || c.kind) + '</td><td class="muted">' + esc(c.endpoint || '—') + '</td>' +
          '<td>' + (c.active ? 'да' : 'нет') + '</td><td class="muted">' + (c.last_run ? new Date(c.last_run).toLocaleString('ru-RU') : '—') + '</td>' +
          '<td>' + esc(c.last_status || '—') + '</td>' +
          '<td style="white-space:nowrap;"><button class="act" data-run="' + c.id + '">Запустить</button>' +
            '<button class="act" data-edit="' + c.id + '">Изменить</button><button class="act danger" data-del="' + c.id + '">Удалить</button></td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Коннекторов нет.</span>';
    $$('#conns [data-run]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_iiot_connector_run', { p_token: token, p_id: b.dataset.run }).then(function (r) { var x = r && r[0]; msg('#cMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadConns(); }); }); });
    $$('#conns [data-edit]').forEach(function (b) { b.addEventListener('click', function () { openConn(conns.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
    $$('#conns [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить коннектор?')) return; rpc('app_iiot_connector_delete', { p_token: token, p_id: b.dataset.del }).then(function (r) { var x = r && r[0]; msg('#cMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadConns(); }); }); });
  }
  function openConn(c) {
    c = c || {};
    ui.formDialog({
      title: c.id ? 'Коннектор' : 'Новый коннектор', okText: 'Сохранить', fields: [
        { name: 'name', label: 'Название', type: 'text', required: true },
        { name: 'kind', label: 'Тип', type: 'select', options: Object.keys(KIND).map(function (k) { return { value: k, label: KIND[k] }; }) },
        { name: 'endpoint', label: 'Endpoint', type: 'text', placeholder: 'opc.tcp://host:4840' },
        { name: 'machine', label: 'Станок (в settings.machine)', type: 'text' },
        { name: 'integration_id', label: 'ID интеграции (необязательно)', type: 'text', hint: 'Для постановки опроса в очередь обмена.' },
        { name: 'active', label: 'Активен', type: 'checkbox' }
      ],
      values: { name: c.name || '', kind: c.kind || 'manual', endpoint: c.endpoint || '', machine: (c.settings && c.settings.machine) || '', integration_id: (c.settings && c.settings.integration_id) || '', active: c.active === false ? '' : 'да' }
    }).then(function (v) {
      if (!v) return;
      rpc('app_iiot_connector_save', {
        p_token: token, p_id: c.id || null, p_name: v.name, p_kind: v.kind, p_endpoint: v.endpoint || null,
        p_settings: { machine: v.machine || null, integration_id: v.integration_id || null },
        p_active: !!v.active
      }).then(function (r) { var x = r && r[0]; msg('#cMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadConns(); });
    });
  }

  /* ---------- OEE онлайн ---------- */
  function loadOee() {
    return rpc('app_oee_online', { p_token: token }).then(function (r) {
      var rows = r || [];
      $('#oee').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Оборудование</th><th>Смена</th><th class="num">План, мин</th><th class="num">Работа, мин</th><th class="num">Простой, мин</th><th class="num">Годных</th><th>Доступность</th><th>Качество</th><th>OEE</th></tr></thead><tbody>' +
        rows.map(function (o) {
          return '<tr><td><b>' + esc(o.equipment) + '</b></td><td>' + (o.shift_date || '—') + '</td><td class="num">' + num(o.planned_min) + '</td>' +
            '<td class="num">' + num(o.run_min) + '</td><td class="num">' + num(o.downtime_min) + '</td><td class="num">' + num(o.good_qty) + '/' + num(o.total_qty) + '</td>' +
            '<td class="num">' + (o.availability != null ? o.availability + '%' : '—') + '</td><td class="num">' + (o.quality != null ? o.quality + '%' : '—') + '</td>' +
            '<td class="num"><b style="color:' + ((Number(o.oee) || 0) >= 85 ? '#047857' : (Number(o.oee) || 0) >= 65 ? '#b45309' : '#b91c1c') + '">' + (o.oee != null ? o.oee + '%' : '—') + '</b></td></tr>';
        }).join('') + '</tbody></table>' : '<span class="note">Нет данных OEE.</span>';
    }).catch(function (e) { msg('#oMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Износ инструмента ---------- */
  function loadWear() {
    return rpc('app_tool_wear_scan', { p_token: token, p_limit: 100 }).then(function (r) {
      var rows = r || [];
      $('#wear').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Код</th><th>Инструмент</th><th>Тип</th><th class="num">Наработка</th><th class="num">Ресурс</th><th>Износ</th><th>Статус</th></tr></thead><tbody>' +
        rows.map(function (t) {
          var st = WSTAT[t.status] || [t.status, ''];
          var pct = Number(t.pct) || 0, cls = pct >= 100 ? 'over' : (pct >= 85 ? 'warn' : '');
          return '<tr><td>' + esc(t.code || '') + '</td><td><b>' + esc(t.name || '') + '</b></td><td>' + esc(t.tool_type || '') + '</td>' +
            '<td class="num">' + num(t.used_min) + '</td><td class="num">' + num(t.resource_min) + '</td>' +
            '<td style="min-width:120px;"><div class="bar"><i class="' + cls + '" style="width:' + Math.min(pct, 100) + '%"></i></div><span class="note">' + (t.pct != null ? t.pct + '%' : '—') + '</span></td>' +
            '<td><span class="badge ' + st[1] + '">' + esc(st[0]) + '</span></td></tr>';
        }).join('') + '</tbody></table>' : '<span class="note">Инструмент не заведён.</span>';
    }).catch(function (e) { msg('#wMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  $('#iSave').addEventListener('click', function () {
    rpc('app_iiot_ingest', { p_token: token, p_machine: $('#iMachine').value, p_metric: $('#iMetric').value, p_value: parseFloat($('#iValue').value) || 0, p_source: $('#iSource').value || null })
      .then(function (r) { var x = r && r[0]; msg('#iMsg', x ? x.message : 'Ошибка', x && x.ok ? 'ok' : 'err'); load(); })
      .catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#dSave').addEventListener('click', function () {
    rpc('app_dnc_save', { p_token: token, p_id: null, p_machine: $('#dMachine').value, p_program_name: $('#dProgram').value, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#dMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); load(); })
      .catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#q').addEventListener('input', function () { q = this.value; load(); });
  if ($('#readCsv')) $('#readCsv').addEventListener('click', exportCsv);
  $('#cNew').addEventListener('click', function () { openConn(null); });
  $('#oeeBtn').addEventListener('click', loadOee);
  $('#wearBtn').addEventListener('click', loadWear);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  /* R4·PROP-27: MQTT/Edge-буфер (store-and-forward) */
  function loadEdge() {
    return rpc('app_iiot_edge_list', { p_token: token, p_undelivered: false }).then(function (r) { edge = r || []; renderEdge(); }).catch(function () {});
  }
  function renderEdge() {
    var host = $('#edge'); if (!host) return;
    var und = edge.filter(function (e) { return !e.delivered; }).length;
    host.innerHTML = '<div class="card"><h2>MQTT/Edge-буфер (store-and-forward)</h2>' +
      '<div class="kpi-row"><div class="kpi"><small>В буфере</small><b' + (und ? ' style="color:#b45309"' : '') + '>' + und + '</b></div><div class="kpi"><small>Всего сообщений</small><b>' + edge.length + '</b></div></div>' +
      '<div class="btn-row"><button class="btn secondary" id="edgeFlush">Сбросить буфер (отметить доставленными)</button><button class="btn secondary" id="edgePush">+ Тест-сообщение</button></div>' +
      (edge.length ? '<div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Время</th><th>Станок</th><th>Метрика</th><th class="num">Значение</th><th>Источник</th><th>Статус</th><th></th></tr></thead><tbody>' +
        edge.slice(0, 100).map(function (e) { return '<tr><td>' + esc(new Date(e.ts).toLocaleString('ru-RU')) + '</td><td>' + esc(e.machine || '—') + '</td><td>' + esc(e.metric || '—') + '</td><td class="num">' + (Number(e.value) || 0) + '</td><td>' + esc(e.source) + '</td><td>' + (e.delivered ? 'доставлено' : 'в буфере') + '</td><td>' + (!e.delivered ? '<button class="act" data-eack="' + e.id + '">доставлено</button>' : '') + '</td></tr>'; }).join('') + '</tbody></table></div>'
        : '<span class="note">Буфер пуст. Реальный приём выполняет edge-воркер (MQTT/Sparkplug B, OPC-UA/MTConnect/Modbus).</span>') + '</div>';
    $('#edgeFlush').addEventListener('click', function () { rpc('app_iiot_edge_flush', { p_token: token }).then(function (r) { var x = r && r[0]; ui.toast((x && x.message ? x.message : 'Готово') + ' ' + (x && x.count ? x.count : '')); loadEdge(); }); });
    $('#edgePush').addEventListener('click', function () { rpc('app_iiot_edge_push', { p_token: token, p_machine: 'Тест', p_metric: 'rpm', p_value: 1000, p_source: 'mqtt', p_payload: null }).then(function () { loadEdge(); }); });
    $$('#edge [data-eack]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_iiot_edge_ack', { p_token: token, p_id: b.dataset.eack }).then(loadEdge); }); });
  }

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    loadEdge();
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#iMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
