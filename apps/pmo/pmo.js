/* ============================================================
   3DMP Service · apps/pmo — PMO (W25, 0171).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, pfs = [], projects = [], curPf = null;
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dd(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }
  function tbl(head, rows) { return '<div class="tbl-wrap"><table class="tbl"><thead><tr>' + head + '</tr></thead><tbody>' + rows + '</tbody></table></div>'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'pf') loadPf(); if (scr === 'ms') loadMs(); if (scr === 'rk') loadRk();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() { return rpc('app_pmo_kpi', { p_token: token }).then(function (r) { var k = (r && r[0]) || {}; $('#kpis').innerHTML = cell('Портфелей', k.portfolios || 0) + cell('Проектов', k.projects || 0) + cell('Вех', k.milestones || 0) + cell('Выполнено вех', k.milestones_done || 0) + cell('Просрочено вех', k.milestones_overdue || 0) + cell('Открытых рисков', k.risks_open || 0) + cell('Высоких рисков', k.risks_high || 0); }); }
  function loadProjects() { return rpc('app_projects_list', { p_token: token, p_q: null }).then(function (r) { projects = r || []; }).catch(function () { projects = []; }); }
  function projOpts() { return [{ value: '', label: '—' }].concat(projects.map(function (p) { return { value: p.id, label: p.name }; })); }

  function loadPf() {
    return rpc('app_pmo_portfolios_list', { p_token: token }).then(function (r) {
      pfs = r || [];
      $('#pf').innerHTML = pfs.length ? tbl('<th>Портфель</th><th>Владелец</th><th>Статус</th><th class="num">Проектов</th><th></th>', pfs.map(function (p) { return '<tr><td><b>' + esc(p.name) + '</b></td><td>' + esc(p.owner_login || '') + '</td><td>' + esc(p.status) + '</td><td class="num">' + p.projects + '</td>' +
        '<td style="white-space:nowrap;"><button class="act" data-op="' + p.id + '">Состав</button><button class="act" data-del="' + p.id + '">Удалить</button></td></tr>'; }).join('')) : '<span class="note">Портфелей нет.</span>';
      $$('#pf [data-op]').forEach(function (b) { b.addEventListener('click', function () { openPf(pfs.filter(function (x) { return x.id === b.dataset.op; })[0]); }); });
      $$('#pf [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить портфель?')) return; rpc('app_pmo_portfolio_delete', { p_token: token, p_id: b.dataset.del }).then(function () { $('#pfItems').innerHTML = ''; loadPf(); loadKpi(); }); }); });
    });
  }
  function openPf(p) {
    if (!p) return; curPf = p;
    return rpc('app_pmo_items_list', { p_token: token, p_portfolio_id: p.id }).then(function (r) {
      var list = r || [];
      $('#pfItems').innerHTML = '<h4>Состав: ' + esc(p.name) + '</h4><div class="toolbar"><button class="btn" id="pfAddItem" style="width:auto;padding:6px 10px;">＋ Проект</button></div>' +
        (list.length ? tbl('<th>Проект</th><th>Приоритет</th><th class="num">Вес</th><th></th>', list.map(function (i) { return '<tr><td>' + esc(i.project || '') + '</td><td>' + esc(i.priority) + '</td><td class="num">' + i.weight + '</td><td><button class="act danger" data-idel="' + i.id + '">Убрать</button></td></tr>'; }).join('')) : '<span class="note">Проектов нет.</span>');
      $('#pfAddItem').addEventListener('click', addItem);
      $$('#pfItems [data-idel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_pmo_item_delete', { p_token: token, p_id: b.dataset.idel }).then(function () { openPf(p); loadPf(); }); }); });
    });
  }
  function pfForm() { ui.formDialog({ title: 'Портфель', okText: 'Создать', fields: [{ name: 'name', label: 'Название', type: 'text', required: true }, { name: 'owner', label: 'Владелец', type: 'text' }], values: {} }).then(function (v) { if (!v) return; rpc('app_pmo_portfolio_save', { p_token: token, p_id: null, p_name: v.name, p_owner: v.owner || null, p_status: 'active', p_note: null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadPf(); loadKpi(); }); }); }
  function addItem() { if (!curPf) return; ui.formDialog({ title: 'Проект в портфель', okText: 'Добавить', fields: [{ name: 'project_id', label: 'Проект', type: 'select', options: projOpts(), required: true }, { name: 'priority', label: 'Приоритет', type: 'text' }, { name: 'weight', label: 'Вес', type: 'number' }], values: { priority: 'normal', weight: 100 } }).then(function (v) { if (!v) return; rpc('app_pmo_item_save', { p_token: token, p_id: null, p_portfolio_id: curPf.id, p_project_id: v.project_id, p_priority: v.priority || null, p_weight: v.weight ? Number(v.weight) : 100 }).then(function () { openPf(curPf); loadPf(); }); }); }

  function loadMs() {
    return rpc('app_pmo_milestones_list', { p_token: token, p_project_id: null }).then(function (r) {
      var list = r || [];
      $('#ms').innerHTML = list.length ? tbl('<th>Проект</th><th>Веха</th><th>Срок</th><th>Статус</th><th></th>', list.map(function (x) { return '<tr><td>' + esc(x.project || '') + '</td><td><b>' + esc(x.name) + '</b></td><td>' + dd(x.due_date) + '</td><td>' + esc(x.status) + '</td>' +
        '<td>' + (x.status === 'pending' ? '<button class="act" data-mst="done" data-id="' + x.id + '">Выполнено</button>' : '') + '</td></tr>'; }).join('')) : '<span class="note">Вех нет.</span>';
      $$('#ms [data-mst]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_pmo_milestone_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.mst }).then(function () { loadMs(); loadKpi(); }); }); });
    });
  }
  function addMs() { ui.formDialog({ title: 'Веха', okText: 'Добавить', fields: [{ name: 'project_id', label: 'Проект', type: 'select', options: projOpts() }, { name: 'name', label: 'Название', type: 'text', required: true }, { name: 'due', label: 'Срок', type: 'date' }], values: {} }).then(function (v) { if (!v) return; rpc('app_pmo_milestone_save', { p_token: token, p_id: null, p_project_id: v.project_id || null, p_name: v.name, p_due: v.due || null, p_status: 'pending', p_weight: 1 }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadMs(); loadKpi(); }); }); }

  function loadRk() {
    return rpc('app_pmo_risks_list', { p_token: token, p_limit: 100 }).then(function (r) {
      var list = r || [];
      $('#rk').innerHTML = list.length ? tbl('<th>Проект</th><th>Риск</th><th class="num">Вер.</th><th class="num">Влияние</th><th class="num">Серьёзн.</th><th>Статус</th><th></th>', list.map(function (x) { return '<tr><td>' + esc(x.project || '') + '</td><td>' + esc(x.title) + '</td><td class="num">' + x.probability + '</td><td class="num">' + x.impact + '</td><td class="num">' + x.severity + '</td><td>' + esc(x.status) + '</td>' +
        '<td style="white-space:nowrap;">' + (x.status === 'open' ? '<button class="act" data-rst="mitigated" data-id="' + x.id + '">Снижен</button><button class="act" data-rst="closed" data-id="' + x.id + '">Закрыть</button>' : '') + '</td></tr>'; }).join('')) : '<span class="note">Рисков нет.</span>';
      $$('#rk [data-rst]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_pmo_risk_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.rst }).then(function () { loadRk(); loadKpi(); }); }); });
    });
  }
  function addRk() { ui.formDialog({ title: 'Риск проекта', okText: 'Добавить', fields: [{ name: 'project_id', label: 'Проект', type: 'select', options: projOpts() }, { name: 'title', label: 'Риск', type: 'text', required: true }, { name: 'prob', label: 'Вероятность (1-5)', type: 'number' }, { name: 'impact', label: 'Влияние (1-5)', type: 'number' }, { name: 'mitigation', label: 'Мероприятия', type: 'text' }], values: { prob: 3, impact: 3 } }).then(function (v) { if (!v) return; rpc('app_pmo_risk_save', { p_token: token, p_id: null, p_project_id: v.project_id || null, p_title: v.title, p_prob: v.prob ? parseInt(v.prob, 10) : 3, p_impact: v.impact ? parseInt(v.impact, 10) : 3, p_status: 'open', p_mitigation: v.mitigation || null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadRk(); loadKpi(); }); }); }

  $('#addPf').addEventListener('click', pfForm);
  $('#addMs').addEventListener('click', addMs);
  $('#addRk').addEventListener('click', addRk);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadProjects().then(function () { loadKpi(); loadPf(); loadWbs(); });
  });
  /* R4·PROP-25: WBS (иерархия работ) и учёт времени (табели) */
  var wbs = [], ts = [], wtProj = '';
  function loadWT() {
    var host = $('#wt'); if (!host) return;
    host.innerHTML = '<div class="card"><h2>WBS и учёт времени</h2>' +
      '<div class="grid3"><div class="field"><label>Проект</label><select id="wtProjSel">' + projOpts().map(function (o) { return '<option value="' + o.value + '"' + (o.value === wtProj ? ' selected' : '') + '>' + esc(o.label) + '</option>'; }).join('') + '</select></div>' +
      '<div class="field"><label>Работа WBS *</label><input type="text" id="wtName" placeholder="Проектирование / Изготовление"></div><div class="field"><label>План, ч</label><input type="number" id="wtPlan" step="0.5"></div></div>' +
      '<div class="btn-row"><button class="btn" id="wtAddWbs">Добавить работу</button></div>' +
      (wbs.length ? tbl('<th>Работа</th><th class="num">План, ч</th><th class="num">Факт, ч</th><th></th>', wbs.map(function (w) { return '<tr><td><b>' + esc(w.name) + '</b></td><td class="num">' + num(w.planned_hours) + '</td><td class="num">' + num(w.fact_hours) + '</td><td><button class="act danger" data-wdel="' + w.id + '" aria-label="Удалить" title="Удалить">✕</button></td></tr>'; }).join('')) : '<span class="note">Работы не заданы.</span>') +
      '<h3 style="margin:12px 0 4px;font-size:.82rem;">Учёт времени</h3>' +
      '<div class="grid3"><div class="field"><label>Работа WBS</label><select id="tsWbs"><option value="">— без привязки —</option>' + wbs.map(function (w) { return '<option value="' + w.id + '">' + esc(w.name) + '</option>'; }).join('') + '</select></div>' +
      '<div class="field"><label>Сотрудник</label><input type="text" id="tsEmp"></div><div class="field"><label>Дата</label><input type="date" id="tsDate"></div></div>' +
      '<div class="grid3"><div class="field"><label>Часы *</label><input type="number" id="tsHours" step="0.5"></div><div class="field" style="grid-column:span 2;"><label>Примечание</label><input type="text" id="tsNote"></div></div>' +
      '<div class="btn-row"><button class="btn" id="tsAdd">Добавить запись времени</button></div>' +
      (ts.length ? tbl('<th>Дата</th><th>Работа</th><th>Сотрудник</th><th class="num">Часы</th><th></th>', ts.map(function (t) { return '<tr><td>' + esc(t.work_date) + '</td><td>' + esc(t.wbs_name || '—') + '</td><td>' + esc(t.employee || '—') + '</td><td class="num">' + num(t.hours) + '</td><td><button class="act danger" data-tdel="' + t.id + '" aria-label="Удалить" title="Удалить">✕</button></td></tr>'; }).join('')) : '<span class="note">Записей нет.</span>') +
      '</div>';
    $('#wtProjSel').addEventListener('change', function () { wtProj = this.value; loadWbs(); });
    var aw = $('#wtAddWbs'); if (aw) aw.addEventListener('click', function () {
      rpc('app_wbs_save', { p_token: token, p_id: null, p_project: wtProj || null, p_parent: null, p_name: $('#wtName').value.trim(), p_ord: 100, p_planned: parseFloat($('#wtPlan').value.replace(',', '.')) || 0 })
        .then(function (r) { var x = r && r[0]; ui.toast(x ? x.message : ''); if (x && x.ok) loadWbs(); }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
    });
    var at = $('#tsAdd'); if (at) at.addEventListener('click', function () {
      rpc('app_timesheet_save', { p_token: token, p_id: null, p_project: wtProj || null, p_wbs: $('#tsWbs').value || null, p_employee: $('#tsEmp').value.trim() || null, p_date: $('#tsDate').value || null, p_hours: parseFloat($('#tsHours').value.replace(',', '.')) || 0, p_note: $('#tsNote').value.trim() || null })
        .then(function (r) { var x = r && r[0]; ui.toast(x ? x.message : ''); if (x && x.ok) loadWbs(); }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
    });
    $$('#wt [data-wdel]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить работу (и её записи времени)?')) return; rpc('app_wbs_delete', { p_token: token, p_id: b.dataset.wdel }).then(loadWbs); }); });
    $$('#wt [data-tdel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_timesheet_delete', { p_token: token, p_id: b.dataset.tdel }).then(loadWbs); }); });
  }
  function loadWbs() {
    return Promise.all([
      rpc('app_wbs_list', { p_token: token, p_project: wtProj || null }),
      rpc('app_timesheet_list', { p_token: token, p_project: wtProj || null })
    ]).then(function (r) { wbs = r[0] || []; ts = r[1] || []; loadWT(); });
  }
})();
