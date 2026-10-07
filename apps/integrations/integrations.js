/* ============================================================
   3DMP Service · apps/integrations — конфигуратор интеграций (W6).
   Данные: 0121 (app_integrations_list/save/delete/enqueue/process/retry,
   app_integration_log_list, app_integrations_kpi).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, items = [], logs = [], q = '';

  var KINDS = { odata: '1С/ERP (OData)', smtp: 'E-mail (SMTP)', telegram: 'Telegram', sms: 'SMS', edo: 'ЭДО', webhook: 'Webhook' };
  var DIRS = { in: 'входящий', out: 'исходящий', both: 'двусторонний' };
  var STAT = { pending: 'в очереди', ok: 'доставлено', error: 'ошибка (повтор)', failed: 'провал' };
  var SBADGE = { pending: 'in_progress', ok: 'done', error: 'cancelled', failed: 'cancelled' };

  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function fmt(ts) { if (!ts) return '—'; var d = new Date(ts); return isNaN(d.getTime()) ? String(ts) : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function msg(t, k) { var e = $('#msg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_integrations_list', { p_token: token }),
      rpc('app_integrations_kpi', { p_token: token }),
      rpc('app_integration_log_list', { p_token: token, p_integration_id: null, p_limit: 100 })
    ]).then(function (r) {
      items = r[0] || []; var k = (r[1] || [])[0] || {}; logs = r[2] || [];
      $('#kpis').innerHTML = cell('Интеграций', k.total) + cell('Активных', k.active) + cell('Доставлено', k.ok_count) +
        cell('Ошибок', k.err_count, k.err_count ? '#b91c1c' : '') + cell('В очереди', k.pending, k.pending ? '#b45309' : '');
      renderList(); renderLog();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
    function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + num(v) + '</b></div>'; }
  }
  function filtered() {
    var s = q.toLowerCase();
    return items.filter(function (i) { return !s || [i.name, KINDS[i.kind], i.endpoint].join(' ').toLowerCase().indexOf(s) >= 0; });
  }
  function renderList() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Интеграций нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (i) {
      return '<div class="ocard int-card' + (i.active ? '' : ' off') + '">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + esc(KINDS[i.kind] || i.kind) + '</span>' +
        '<span class="badge">' + (DIRS[i.direction] || i.direction) + '</span>' +
        '<span class="badge ' + (i.active ? 'done' : 'cancelled') + '">' + (i.active ? 'включена' : 'выключена') + '</span>' +
        (i.last_status ? '<span class="badge ' + (SBADGE[i.last_status] || '') + '">' + (STAT[i.last_status] || i.last_status) + '</span>' : '') +
        '<b style="margin-left:auto;">' + esc(i.name) + '</b></div>' +
        '<div style="font-size:.78rem;color:var(--muted);margin-top:5px;">' + (i.endpoint ? '🔗 ' + esc(i.endpoint) + ' · ' : '') +
        (i.has_token ? '🔑 токен задан · ' : '⚠ токен не задан · ') + 'ретраев до ' + num(i.max_retries) +
        (i.last_run ? ' · последний: ' + fmt(i.last_run) : '') + '</div>' +
        '<div style="font-size:.76rem;margin-top:4px;">обменов: ' + num(i.logs_total) + (i.logs_failed ? ' · <span style="color:#b91c1c;">ошибок ' + num(i.logs_failed) + '</span>' : '') + '</div>' +
        '<div class="toolbar mt"><button class="btn secondary" data-test="' + i.id + '" style="width:auto;padding:7px 12px;">Тест обмена</button>' +
        '<button class="btn secondary" data-log="' + i.id + '" style="width:auto;padding:7px 12px;">Журнал</button>' +
        '<button class="act" data-edit="' + i.id + '">Изменить</button>' +
        '<button class="act" data-toggle="' + i.id + '">' + (i.active ? 'Выключить' : 'Включить') + '</button>' +
        '<button class="act danger" data-del="' + i.id + '">Удалить</button></div></div>';
    }).join('');
    bind();
  }
  function renderLog() {
    var list = logs.slice(0, 60);
    $('#logList').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Время</th><th>Интеграция</th><th>Тип</th><th>Статус</th><th class="num">Повторы</th><th>Сообщение</th><th></th></tr></thead><tbody>' +
      list.map(function (l) {
        return '<tr><td class="muted">' + fmt(l.created_at) + '</td><td>' + esc(l.integration || '—') + '</td><td>' + esc(KINDS[l.kind] || l.kind || '') + '</td>' +
          '<td><span class="badge ' + (SBADGE[l.status] || '') + '">' + (STAT[l.status] || l.status) + '</span></td>' +
          '<td class="num">' + num(l.retry_count) + '/' + num(l.max_retries) + '</td>' +
          '<td class="muted">' + esc(l.message || l.response || '') + '</td>' +
          '<td>' + ((l.status === 'error' || l.status === 'failed') ? '<button class="act" data-retry="' + l.id + '">Повтор</button>' : '') + '</td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Обменов нет.</span>';
    $$('#logList [data-retry]').forEach(function (b) {
      b.addEventListener('click', function () { rpc('app_integration_retry', { p_token: token, p_log_id: b.dataset.retry }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); load(); }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); }); });
    });
  }
  function bind() {
    $$('#list [data-test]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_integration_enqueue', { p_token: token, p_id: b.dataset.test, p_direction: 'out', p_payload: { test: true, ts: new Date().toISOString() } })
          .then(function () { return rpc('app_integration_process', { p_token: token, p_limit: 50 }); })
          .then(function (p) { var x = p && p[0]; msg(x ? x.message : 'Обработано', 'ok'); if (window.Auth) window.Auth.log('Тест интеграции', b.dataset.test); load(); })
          .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
      });
    });
    $$('#list [data-log]').forEach(function (b) { b.addEventListener('click', function () { var i = items.filter(function (x) { return x.id === b.dataset.log; })[0]; msg(i ? 'Журнал по «' + i.name + '» (показаны только его записи).' : '', 'info'); filterLog(b.dataset.log); }); });
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { openForm(items.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
    $$('#list [data-toggle]').forEach(function (b) {
      b.addEventListener('click', function () {
        var i = items.filter(function (x) { return x.id === b.dataset.toggle; })[0]; if (!i) return;
        rpc('app_integration_save', { p_token: token, p_id: i.id, p_name: i.name, p_kind: i.kind, p_direction: i.direction, p_endpoint: i.endpoint || '', p_token_secret: null, p_settings: null, p_active: !i.active, p_max_retries: i.max_retries })
          .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); load(); });
      });
    });
    $$('#list [data-del]').forEach(function (b) {
      b.addEventListener('click', function () { if (!window.confirm('Удалить интеграцию и её журнал?')) return;
        rpc('app_integration_delete', { p_token: token, p_id: b.dataset.del }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); load(); }); });
    });
  }
  var logFilter = null;
  function filterLog(id) { logFilter = id; rpc('app_integration_log_list', { p_token: token, p_integration_id: id, p_limit: 100 }).then(function (r) { logs = r || []; renderLog(); }); }

  function openForm(i) {
    i = i || {};
    ui.formDialog({
      title: i.id ? 'Интеграция' : 'Новая интеграция', okText: 'Сохранить', size: 'lg',
      fields: [
        { name: 'name', label: 'Название', type: 'text', required: true, placeholder: '1С/ERP — обмен заказами' },
        { name: 'kind', label: 'Тип', type: 'select', options: Object.keys(KINDS).map(function (k) { return { value: k, label: KINDS[k] }; }) },
        { name: 'direction', label: 'Направление', type: 'select', options: Object.keys(DIRS).map(function (k) { return { value: k, label: DIRS[k] }; }) },
        { name: 'endpoint', label: 'Endpoint / URL', type: 'text', placeholder: 'https://…' },
        { name: 'token', label: 'Токен / секрет', type: 'text', hint: 'Оставьте пустым, чтобы не менять.' },
        { name: 'max_retries', label: 'Макс. повторов', type: 'text', value: '3' },
        { name: 'settings', label: 'Настройки (JSON)', type: 'textarea', rows: 3, placeholder: '{"chat_id":"..."}' },
        { name: 'active', label: 'Включена', type: 'checkbox', hint: 'Активна' }
      ],
      values: {
        name: i.name || '', kind: i.kind || 'odata', direction: i.direction || 'out', endpoint: i.endpoint || '',
        token: '', max_retries: i.max_retries != null ? String(i.max_retries) : '3', settings: '', active: (i.id ? i.active : true) ? 'да' : ''
      }
    }).then(function (v) {
      if (!v) return;
      var settings = null;
      if (v.settings && String(v.settings).trim()) { try { settings = JSON.parse(v.settings); } catch (e) { msg('Настройки: неверный JSON', 'err'); return; } }
      rpc('app_integration_save', { p_token: token, p_id: i.id || null, p_name: v.name, p_kind: v.kind, p_direction: v.direction, p_endpoint: v.endpoint, p_token_secret: v.token || null, p_settings: settings, p_active: !!v.active, p_max_retries: parseInt(v.max_retries, 10) || 3 })
        .then(function (r) { var x = r && r[0]; if (!x || !x.ok) { msg(x ? x.message : 'Ошибка', 'err'); return; } window.Auth.log(i.id ? 'Изменена интеграция' : 'Создана интеграция', v.name); msg(x.message, 'ok'); load(); })
        .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
    });
  }

  $('#newBtn').addEventListener('click', function () { openForm(null); });
  $('#procBtn').addEventListener('click', function () {
    rpc('app_integration_process', { p_token: token, p_limit: 100 }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', 'ok'); load(); }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  });
  $('#q').addEventListener('input', function () { q = this.value; renderList(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (s.role !== 'admin' && s.role !== 'owner' && s.role !== 'manager' && s.role !== 'director') { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    load();
  });
})();
