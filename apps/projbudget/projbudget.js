/* ============================================================
   3DMP Service · apps/projbudget — Бюджет проектов (W28, 0170).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, budgets = [], projects = [], cur = null;
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function money(v) { return v == null ? '—' : (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 0 }) + ' ₽'; }
  var ST = { draft: 'Черновик', approved: 'Утверждена', closed: 'Закрыта' };

  function loadKpi() {
    return rpc('app_proj_budget_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Смет', k.budgets || 0) + cell('План', money(k.plan_total)) + cell('Факт', money(k.fact_total)) + cell('Резерв, %', k.margin_pct != null ? k.margin_pct : '—');
    }).catch(function () {});
  }
  function loadProjects() { return rpc('app_projects_list', { p_token: token, p_q: null }).then(function (r) { projects = r || []; }).catch(function () { projects = []; }); }
  function loadBudgets() {
    return rpc('app_proj_budgets_list', { p_token: token, p_project_id: null }).then(function (r) {
      budgets = r || [];
      $('#budgets').innerHTML = budgets.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Смета</th><th>Проект</th><th class="num">Версия</th><th>Статус</th><th class="num">План</th><th class="num">Факт</th><th></th></tr></thead><tbody>' +
        budgets.map(function (b) { return '<tr><td><b>' + esc(b.name) + '</b></td><td>' + esc(b.project || '—') + '</td><td class="num">v' + b.version + '</td><td>' + esc(ST[b.status] || b.status) + '</td><td class="num">' + money(b.plan_total) + '</td><td class="num">' + money(b.fact_total) + '</td>' +
          '<td style="white-space:nowrap;"><button class="act" data-open="' + b.id + '">Открыть</button><button class="act danger" data-del="' + b.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Смет нет.</span>';
      $$('#budgets [data-open]').forEach(function (b) { b.addEventListener('click', function () { openBudget(budgets.filter(function (x) { return x.id === b.dataset.open; })[0]); }); });
      $$('#budgets [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить смету?')) return; rpc('app_proj_budget_delete', { p_token: token, p_id: b.dataset.del }).then(function () { $('#detailCard').style.display = 'none'; loadBudgets(); loadKpi(); }); }); });
    });
  }
  function budForm() {
    ui.formDialog({ title: 'Новая смета', okText: 'Создать', fields: [
      { name: 'name', label: 'Название', type: 'text', required: true },
      { name: 'project_id', label: 'Проект', type: 'select', options: [{ value: '', label: '—' }].concat(projects.map(function (p) { return { value: p.id, label: p.name }; })) },
      { name: 'version', label: 'Версия', type: 'number' }, { name: 'status', label: 'Статус', type: 'select', options: Object.keys(ST).map(function (k) { return { value: k, label: ST[k] }; }) }
    ], values: { version: 1, status: 'draft' } }).then(function (v) {
      if (!v) return;
      rpc('app_proj_budget_save', { p_token: token, p_id: null, p_project_id: v.project_id || null, p_name: v.name, p_version: v.version ? parseInt(v.version, 10) : 1, p_status: v.status, p_note: null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadBudgets(); loadKpi(); });
    });
  }
  function openBudget(b) {
    if (!b) return; cur = b;
    return Promise.all([
      rpc('app_proj_budget_lines_list', { p_token: token, p_budget_id: b.id }).catch(function () { return []; }),
      rpc('app_proj_budget_plan_fact', { p_token: token, p_budget_id: b.id }).catch(function () { return []; }),
      rpc('app_proj_budget_evm', { p_token: token, p_budget_id: b.id }).catch(function () { return []; })
    ]).then(function (r) {
      var lines = r[0] || [], pf = r[1] || [], evm = (r[2] && r[2][0]) || {};
      $('#detailCard').style.display = '';
      $('#detail').innerHTML =
        '<h3>' + esc(b.name) + ' <span class="note">' + esc(b.project || '') + ' · v' + b.version + '</span></h3>' +
        '<div class="kpi-row">' + cell('PV (план)', money(evm.pv)) + cell('AC (факт)', money(evm.ac)) + cell('EV (освоено)', money(evm.ev)) + cell('CPI', evm.cpi != null ? evm.cpi + '%' : '—') + cell('SPI', evm.spi != null ? evm.spi + '%' : '—') + cell('EAC (прогноз)', money(evm.eac)) + '</div>' +
        '<div class="toolbar"><button class="btn" id="addLine" style="width:auto;padding:7px 12px;">＋ Строка</button></div>' +
        '<h4>План-факт по статьям</h4>' +
        '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Статья</th><th class="num">План</th><th class="num">Факт</th><th class="num">Δ</th><th class="num">%</th></tr></thead><tbody>' +
        (pf.length ? pf.map(function (p) { return '<tr><td>' + esc(p.category) + '</td><td class="num">' + money(p.amount_plan) + '</td><td class="num">' + money(p.amount_fact) + '</td><td class="num">' + money(p.delta) + '</td><td class="num">' + (p.pct != null ? p.pct + '%' : '—') + '</td></tr>'; }).join('') : '<tr><td colspan="5" class="note">Нет строк</td></tr>') +
        '</tbody></table></div>' +
        '<h4 class="mt">Строки</h4>' +
        '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Статья</th><th>Позиция</th><th class="num">План</th><th class="num">Факт</th><th></th></tr></thead><tbody>' +
        (lines.length ? lines.map(function (l) { return '<tr><td>' + esc(l.category) + '</td><td>' + esc(l.item || '') + '</td><td class="num">' + money(l.amount_plan) + '</td><td class="num">' + money(l.amount_fact) + '</td><td><button class="act danger" data-ldel="' + l.id + '">Удалить</button></td></tr>'; }).join('') : '<tr><td colspan="5" class="note">Нет строк</td></tr>') +
        '</tbody></table></div>';
      $('#addLine').addEventListener('click', lineForm);
      $$('#detail [data-ldel]').forEach(function (x) { x.addEventListener('click', function () { rpc('app_proj_budget_line_delete', { p_token: token, p_id: x.dataset.ldel }).then(function () { openBudget(b); loadBudgets(); loadKpi(); }); }); });
    });
  }
  function lineForm() {
    ui.formDialog({ title: 'Строка сметы', okText: 'Добавить', fields: [
      { name: 'category', label: 'Статья', type: 'text', required: true }, { name: 'item', label: 'Позиция', type: 'text' },
      { name: 'plan', label: 'План, ₽', type: 'number' }, { name: 'fact', label: 'Факт, ₽', type: 'number' }
    ], values: {} }).then(function (v) {
      if (!v) return;
      rpc('app_proj_budget_line_save', { p_token: token, p_id: null, p_budget_id: cur.id, p_category: v.category, p_item: v.item || null, p_plan: v.plan ? Number(v.plan) : 0, p_fact: v.fact ? Number(v.fact) : 0, p_note: null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); openBudget(cur); loadBudgets(); loadKpi(); });
    });
  }

  $('#addBud').addEventListener('click', budForm);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadProjects().then(function () { loadKpi(); loadBudgets(); });
  });
})();
