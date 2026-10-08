/* ============================================================
   3DMP Service · apps/finance/finance2.js — финансы/управленческий учёт (W18a, 0160).
   Бюджеты/ЦФО и план-факт, платёжный календарь, KPI.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, budgets = [], lines = [], cur = null;
  var STB = { draft: 'Черновик', approved: 'Утверждён', closed: 'Закрыт' };
  var MSC = ['', 'Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
  function esc(v) { return ui.esc(v); }
  function money(v) { return v == null ? '—' : (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 0 }) + ' ₽'; }
  function msg(id, t, k) { var e = $(id); if (!e) return; e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dd(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }

  function showTab(scr) {
    $$('#f2tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.f2scr').forEach(function (s) { s.classList.toggle('active', s.id === 'f2-' + scr); });
    if (scr === 'bud') loadBudgets();
    if (scr === 'cash') loadCash();
  }
  $$('#f2tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_cash_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#f2kpi').innerHTML = cell('Дебиторка', money(k.receivable)) + cell('Кредиторка', money(k.payable)) + cell('Просрочено (вход)', money(k.overdue_in)) + cell('Просрочено (исход)', money(k.overdue_out)) + cell('Касса (30 дн.)', money(k.cash_plan_30));
    }).catch(function (e) { msg('#f2m', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Бюджеты ---------- */
  function loadBudgets() {
    return rpc('app_budgets_list', { p_token: token }).then(function (r) {
      budgets = r || [];
      $('#f2bud').innerHTML = budgets.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Название</th><th>Год</th><th>ЦФО</th><th>Статус</th><th class="num">План</th><th class="num">Факт</th><th class="num">Вып.</th><th></th></tr></thead><tbody>' +
        budgets.map(function (b) {
          var pct = Number(b.plan_total) > 0 ? Math.round(Number(b.fact_total) / Number(b.plan_total) * 100) : 0;
          return '<tr><td><b>' + esc(b.name) + '</b></td><td>' + b.year + '</td><td>' + esc(b.cfo || '—') + '</td><td>' + esc(STB[b.status] || b.status) + '</td>' +
            '<td class="num">' + money(b.plan_total) + '</td><td class="num">' + money(b.fact_total) + '</td><td class="num">' + pct + '%</td>' +
            '<td style="white-space:nowrap;"><button class="act" data-open="' + b.id + '">Открыть</button><button class="act" data-edit="' + b.id + '">Изменить</button><button class="act danger" data-del="' + b.id + '">Удалить</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Бюджетов нет.</span>';
      $$('#f2bud [data-open]').forEach(function (x) { x.addEventListener('click', function () { openBudget(budgets.filter(function (b) { return b.id === x.dataset.open; })[0]); }); });
      $$('#f2bud [data-edit]').forEach(function (x) { x.addEventListener('click', function () { budForm(budgets.filter(function (b) { return b.id === x.dataset.edit; })[0]); }); });
      $$('#f2bud [data-del]').forEach(function (x) { x.addEventListener('click', function () { if (!confirm('Удалить бюджет?')) return; rpc('app_budget_delete', { p_token: token, p_id: x.dataset.del }).then(function () { loadBudgets(); }); }); });
    }).catch(function (e) { msg('#f2m', 'Ошибка: ' + e.message, 'err'); });
  }
  function budForm(b) {
    b = b || {};
    ui.formDialog({ title: b.id ? 'Бюджет' : 'Новый бюджет', okText: 'Сохранить', fields: [
      { name: 'name', label: 'Название', type: 'text', required: true },
      { name: 'year', label: 'Год', type: 'number' }, { name: 'cfo', label: 'ЦФО', type: 'text' },
      { name: 'status', label: 'Статус', type: 'select', options: [{ value: 'draft', label: 'Черновик' }, { value: 'approved', label: 'Утверждён' }, { value: 'closed', label: 'Закрыт' }] }
    ], values: { name: b.name || '', year: b.year || new Date().getFullYear(), cfo: b.cfo || '', status: b.status || 'draft' } }).then(function (v) {
      if (!v) return;
      rpc('app_budget_save', { p_token: token, p_id: b.id || null, p_name: v.name, p_year: v.year ? parseInt(v.year, 10) : null, p_cfo: v.cfo || null, p_status: v.status, p_note: null })
        .then(function (r) { var x = r && r[0]; msg('#f2m', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadBudgets(); });
    });
  }
  function openBudget(b) {
    if (!b) return;
    cur = b;
    return Promise.all([
      rpc('app_budget_lines_list', { p_token: token, p_budget_id: b.id }),
      rpc('app_budget_plan_fact', { p_token: token, p_budget_id: b.id }),
      rpc('app_budget_kpi', { p_token: token, p_budget_id: b.id })
    ]).then(function (r) {
      lines = r[0] || []; var pf = r[1] || []; var k = (r[2] && r[2][0]) || {};
      $('#f2budPanel').innerHTML =
        '<h3>' + esc(b.name) + ' <span class="note">план ' + money(k.plan_total) + ' · факт ' + money(k.fact_total) + ' · ' + (k.pct != null ? k.pct + '%' : '—') + '</span>' +
        ' <button class="btn" id="f2fromInv" style="width:auto;padding:6px 10px;">Факт «Продажи» из счетов</button></h3>' +
        '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Статья</th><th class="num">План</th><th class="num">Факт</th><th class="num">Δ</th><th class="num">%</th></tr></thead><tbody>' +
        (pf.length ? pf.map(function (p) { return '<tr><td>' + esc(p.category) + '</td><td class="num">' + money(p.amount_plan) + '</td><td class="num">' + money(p.amount_fact) + '</td><td class="num">' + money(p.delta) + '</td><td class="num">' + (p.pct != null ? p.pct + '%' : '—') + '</td></tr>'; }).join('') : '<tr><td colspan="5" class="note">Нет строк</td></tr>') +
        '</tbody></table></div>' +
        '<div class="toolbar mt"><button class="btn" id="f2addLine" style="width:auto;padding:7px 12px;">＋ Строка</button></div>' +
        '<div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Статья</th><th>Позиция</th><th>Мес.</th><th class="num">План</th><th class="num">Факт</th><th></th></tr></thead><tbody>' +
        (lines.length ? lines.map(function (l) { return '<tr><td>' + esc(l.category) + '</td><td>' + esc(l.item || '') + '</td><td>' + (MSC[l.month] || l.month) + '</td><td class="num">' + money(l.amount_plan) + '</td><td class="num">' + money(l.amount_fact) + '</td><td><button class="act danger" data-ldel="' + l.id + '">Удалить</button></td></tr>'; }).join('') : '<tr><td colspan="6" class="note">Нет строк</td></tr>') +
        '</tbody></table></div>';
      $$('#f2budPanel [data-ldel]').forEach(function (x) { x.addEventListener('click', function () { rpc('app_budget_line_delete', { p_token: token, p_id: x.dataset.ldel }).then(function () { openBudget(b); loadBudgets(); }); }); });
      $('#f2addLine').addEventListener('click', function () { lineForm(b.id); });
      $('#f2fromInv').addEventListener('click', function () {
        var m = new Date().getMonth() + 1;
        rpc('app_budget_from_invoices', { p_token: token, p_budget_id: b.id, p_year: new Date().getFullYear(), p_month: m }).then(function (x) { var q = x && x[0]; msg('#f2m', q ? q.message : '', 'ok'); openBudget(b); loadBudgets(); });
      });
    });
  }
  function lineForm(bid) {
    ui.formDialog({ title: 'Строка бюджета', okText: 'Добавить', fields: [
      { name: 'category', label: 'Статья', type: 'text', required: true, placeholder: 'Материалы' },
      { name: 'item', label: 'Позиция', type: 'text' }, { name: 'month', label: 'Месяц (1..12)', type: 'number' },
      { name: 'plan', label: 'План, ₽', type: 'number' }, { name: 'fact', label: 'Факт, ₽', type: 'number' }
    ], values: { month: new Date().getMonth() + 1 } }).then(function (v) {
      if (!v) return;
      rpc('app_budget_line_save', { p_token: token, p_id: null, p_budget_id: bid, p_category: v.category, p_item: v.item || null, p_month: v.month ? parseInt(v.month, 10) : 1, p_plan: v.plan ? Number(v.plan) : 0, p_fact: v.fact ? Number(v.fact) : 0, p_note: null })
        .then(function (x) { var q = x && x[0]; msg('#f2m', q ? q.message : '', q && q.ok ? 'ok' : 'err'); openBudget(cur); loadBudgets(); });
    });
  }

  /* ---------- Платёжный календарь ---------- */
  function loadCash() {
    var days = parseInt($('#f2days').value, 10) || 30;
    return Promise.all([
      rpc('app_cash_calendar', { p_token: token, p_days: days }).catch(function () { return []; }),
      rpc('app_cash_list', { p_token: token, p_kind: null, p_status: null }).catch(function () { return []; })
    ]).then(function (r) {
      var cal = r[0] || [], manual = r[1] || [];
      $('#f2cal').innerHTML = cal.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Дата</th><th>Тип</th><th>Контрагент</th><th>Источник</th><th class="num">Сумма</th><th class="num">Дней</th></tr></thead><tbody>' +
        cal.map(function (c) { return '<tr><td>' + dd(c.at) + '</td><td>' + (c.kind === 'in' ? '↑ приход' : '↓ расход') + '</td><td>' + esc(c.counterparty || '') + '</td><td class="muted">' + esc(c.source || '') + '</td><td class="num">' + money(c.amount) + '</td><td class="num">' + c.days_left + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Платежей нет.</span>';
      $('#f2pay').innerHTML = manual.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Дата</th><th>Тип</th><th>Контрагент</th><th class="num">Сумма</th><th>Статус</th><th></th></tr></thead><tbody>' +
        manual.map(function (p) { return '<tr><td>' + dd(p.due_date) + '</td><td>' + (p.kind === 'in' ? 'приход' : 'расход') + '</td><td>' + esc(p.counterparty || '') + '</td><td class="num">' + money(p.amount) + '</td><td>' + esc(p.status) + '</td>' +
          '<td style="white-space:nowrap;">' + (p.status !== 'paid' ? '<button class="act" data-paid="' + p.id + '">Оплачен</button>' : '') + '<button class="act danger" data-del="' + p.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Ручных платежей нет.</span>';
      $$('#f2pay [data-paid]').forEach(function (x) { x.addEventListener('click', function () { rpc('app_cash_set_status', { p_token: token, p_id: x.dataset.paid, p_status: 'paid' }).then(function () { loadCash(); loadKpi(); }); }); });
      $$('#f2pay [data-del]').forEach(function (x) { x.addEventListener('click', function () { rpc('app_cash_delete', { p_token: token, p_id: x.dataset.del }).then(function () { loadCash(); loadKpi(); }); }); });
    }).catch(function (e) { msg('#f2m', 'Ошибка: ' + e.message, 'err'); });
  }
  function cashForm() {
    ui.formDialog({ title: 'Новый платёж', okText: 'Создать', fields: [
      { name: 'kind', label: 'Тип', type: 'select', options: [{ value: 'out', label: 'Расход' }, { value: 'in', label: 'Приход' }] },
      { name: 'counterparty', label: 'Контрагент', type: 'text', required: true },
      { name: 'amount', label: 'Сумма, ₽', type: 'number', required: true },
      { name: 'due_date', label: 'Срок', type: 'date' }, { name: 'doc', label: 'Документ', type: 'text' }
    ], values: { kind: 'out' } }).then(function (v) {
      if (!v) return;
      rpc('app_cash_save', { p_token: token, p_id: null, p_kind: v.kind, p_counterparty: v.counterparty, p_amount: v.amount ? Number(v.amount) : 0, p_due_date: v.due_date || null, p_status: 'planned', p_doc: v.doc || null, p_note: null })
        .then(function (x) { var q = x && x[0]; msg('#f2m', q ? q.message : '', q && q.ok ? 'ok' : 'err'); loadCash(); loadKpi(); });
    });
  }

  $('#f2newBud').addEventListener('click', function () { budForm(null); });
  $('#f2newPay').addEventListener('click', cashForm);
  $('#f2days').addEventListener('change', loadCash);

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    if (!SB) return;
    loadKpi(); showTab('bud');
  });
})();
