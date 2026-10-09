/* ============================================================
   3DMP Service · apps/itsm — ITSM/ITIL (W24, 0173).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, services = [];
  var ST = { new: 'Новая', in_progress: 'В работе', resolved: 'Решена', closed: 'Закрыта' };
  var PR = { low: 'Низкий', normal: 'Обычный', high: 'Высокий' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dt(v) { return v ? new Date(v).toLocaleString('ru-RU') : '—'; }
  function tbl(head, rows) { return '<div class="tbl-wrap"><table class="tbl"><thead><tr>' + head + '</tr></thead><tbody>' + rows + '</tbody></table></div>'; }

  function showTab(scr) { $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); }); $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); }); if (scr === 'tk') loadTk(); else loadSv(); }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() { return rpc('app_itsm_kpi', { p_token: token }).then(function (r) { var k = (r && r[0]) || {}; $('#kpis').innerHTML = cell('Услуг', k.services || 0) + cell('Заявок', k.tickets || 0) + cell('Открытых', k.open_tickets || 0) + cell('В работе', k.in_progress || 0) + cell('Решено', k.resolved || 0) + cell('SLA нарушен', k.sla_breached || 0); }); }
  function loadSvcRef() { return rpc('app_it_services_list', { p_token: token }).then(function (r) { services = r || []; }).catch(function () { services = []; }); }

  function loadTk() {
    return rpc('app_it_tickets_list', { p_token: token, p_status: null }).then(function (r) {
      var list = r || [];
      $('#tk').innerHTML = list.length ? tbl('<th>№</th><th>Услуга</th><th>Тема</th><th>Приоритет</th><th>Статус</th><th>Исполнитель</th><th>SLA</th><th></th>', list.map(function (x) {
        var a = '';
        if (x.status === 'new') a = '<button class="act" data-st="in_progress" data-id="' + x.id + '">В работу</button>';
        else if (x.status === 'in_progress') a = '<button class="act" data-st="resolved" data-id="' + x.id + '">Решена</button>';
        else if (x.status === 'resolved') a = '<button class="act" data-st="closed" data-id="' + x.id + '">Закрыть</button>';
        return '<tr><td>' + esc(x.number || '') + '</td><td>' + esc(x.service || '') + '</td><td><b>' + esc(x.title) + '</b></td><td>' + esc(PR[x.priority] || x.priority) + '</td><td>' + esc(ST[x.status] || x.status) + '</td><td class="muted">' + esc(x.assignee_login || '') + '</td><td class="muted">' + dt(x.due_at) + '</td><td>' + a + '</td></tr>';
      }).join('')) : '<span class="note">Заявок нет.</span>';
      $$('#tk [data-st]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_it_ticket_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.st }).then(function () { loadTk(); loadKpi(); }); }); });
    });
  }
  function svcOpts() { return [{ value: '', label: '—' }].concat(services.map(function (s) { return { value: s.id, label: s.name }; })); }
  function tkForm() {
    ui.formDialog({ title: 'Новая заявка', okText: 'Создать', fields: [
      { name: 'service_id', label: 'Услуга', type: 'select', options: svcOpts() }, { name: 'title', label: 'Тема', type: 'text', required: true },
      { name: 'priority', label: 'Приоритет', type: 'select', options: Object.keys(PR).map(function (k) { return { value: k, label: PR[k] }; }) },
      { name: 'assignee', label: 'Исполнитель (логин)', type: 'text' }, { name: 'description', label: 'Описание', type: 'textarea', rows: 2 }
    ], values: { priority: 'normal' } }).then(function (v) {
      if (!v) return;
      rpc('app_it_ticket_save', { p_token: token, p_id: null, p_service_id: v.service_id || null, p_title: v.title, p_description: v.description || null, p_priority: v.priority, p_assignee: v.assignee || null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadTk(); loadKpi(); });
    });
  }
  function loadSv() {
    return rpc('app_it_services_list', { p_token: token }).then(function (r) {
      services = r || [];
      $('#sv').innerHTML = services.length ? tbl('<th>Услуга</th><th>Категория</th><th>Владелец</th><th class="num">SLA, ч</th><th>Активна</th><th class="num">Заявок</th><th></th>', services.map(function (s) { return '<tr><td><b>' + esc(s.name) + '</b></td><td>' + esc(s.category || '') + '</td><td>' + esc(s.owner_login || '') + '</td><td class="num">' + (s.sla_hours || '') + '</td><td>' + (s.active ? 'да' : 'нет') + '</td><td class="num">' + s.tickets + '</td><td><button class="act danger" data-del="' + s.id + '">Удалить</button></td></tr>'; }).join('')) : '<span class="note">Услуг нет.</span>';
      $$('#sv [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить?')) return; rpc('app_it_service_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadSv(); loadKpi(); }); }); });
    });
  }
  function svForm() { ui.formDialog({ title: 'ИТ-услуга', okText: 'Сохранить', fields: [{ name: 'name', label: 'Название', type: 'text', required: true }, { name: 'category', label: 'Категория', type: 'text' }, { name: 'owner', label: 'Владелец (логин)', type: 'text' }, { name: 'sla', label: 'SLA, часов', type: 'number' }], values: { sla: 8 } }).then(function (v) { if (!v) return; rpc('app_it_service_save', { p_token: token, p_id: null, p_name: v.name, p_category: v.category || null, p_owner: v.owner || null, p_sla: v.sla ? parseInt(v.sla, 10) : 8, p_active: true }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadSv(); loadKpi(); }); }); }

  $('#addTk').addEventListener('click', tkForm);
  $('#addSv').addEventListener('click', svForm);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadSvcRef().then(function () { loadKpi(); loadTk(); });
  });
})();
