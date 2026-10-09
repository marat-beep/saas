/* ============================================================
   3DMP Service · apps/accounting — бухучёт задел (W27, 0175).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, accounts = [];
  var KI = { asset: 'Актив', liability: 'Пассив', income: 'Доход', expense: 'Расход', equity: 'Капитал' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function money(v) { return v == null ? '—' : (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 2 }); }
  function dd(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }
  function tbl(head, rows) { return '<div class="tbl-wrap"><table class="tbl"><thead><tr>' + head + '</tr></thead><tbody>' + rows + '</tbody></table></div>'; }

  function showTab(scr) { $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); }); $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); }); if (scr === 'ac') loadAc(); if (scr === 'po') loadPo(); if (scr === 'osv') loadOsv(); }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() { return rpc('app_accounting_kpi', { p_token: token }).then(function (r) { var k = (r && r[0]) || {}; $('#kpis').innerHTML = cell('Счетов', k.accounts || 0) + cell('Проводок', k.postings || 0) + cell('Оборот', money(k.turnover)); }); }
  function loadAc() {
    return rpc('app_accounts_list', { p_token: token }).then(function (r) {
      accounts = r || [];
      $('#ac').innerHTML = accounts.length ? tbl('<th>Счёт</th><th>Название</th><th>Тип</th><th></th>', accounts.map(function (a) { return '<tr><td><b>' + esc(a.code) + '</b></td><td>' + esc(a.name) + '</td><td>' + esc(KI[a.kind] || a.kind) + '</td><td><button class="act danger" data-del="' + a.id + '">Удалить</button></td></tr>'; }).join('')) : '<span class="note">Счетов нет.</span>';
      $$('#ac [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить счёт?')) return; rpc('app_account_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadAc(); loadKpi(); }); }); });
    });
  }
  function acForm() { ui.formDialog({ title: 'Счёт', okText: 'Сохранить', fields: [{ name: 'code', label: 'Код', type: 'text', required: true }, { name: 'name', label: 'Название', type: 'text', required: true }, { name: 'kind', label: 'Тип', type: 'select', options: Object.keys(KI).map(function (k) { return { value: k, label: KI[k] }; }) }], values: { kind: 'asset' } }).then(function (v) { if (!v) return; rpc('app_account_save', { p_token: token, p_id: null, p_code: v.code, p_name: v.name, p_kind: v.kind }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadAc(); loadKpi(); }); }); }
  function loadPo() {
    return rpc('app_postings_list', { p_token: token, p_limit: 200 }).then(function (r) {
      var list = r || [];
      $('#po').innerHTML = list.length ? tbl('<th>№</th><th>Дата</th><th>Дт</th><th>Кт</th><th class="num">Сумма</th><th>Примечание</th><th></th>', list.map(function (p) { return '<tr><td>' + esc(p.number || '') + '</td><td>' + dd(p.period_date) + '</td><td>' + esc(p.debit_code) + '</td><td>' + esc(p.credit_code) + '</td><td class="num">' + money(p.amount) + '</td><td class="muted">' + esc(p.memo || '') + '</td><td><button class="act danger" data-del="' + p.id + '">Удалить</button></td></tr>'; }).join('')) : '<span class="note">Проводок нет.</span>';
      $$('#po [data-del]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_posting_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadPo(); loadKpi(); }); }); });
    });
  }
  function poForm() { ui.formDialog({ title: 'Проводка', okText: 'Добавить', fields: [{ name: 'period', label: 'Дата', type: 'date' }, { name: 'debit', label: 'Дт (счёт)', type: 'text', required: true }, { name: 'credit', label: 'Кт (счёт)', type: 'text', required: true }, { name: 'amount', label: 'Сумма', type: 'number', required: true }, { name: 'memo', label: 'Примечание', type: 'text' }], values: { period: new Date().toISOString().slice(0, 10) } }).then(function (v) { if (!v) return; rpc('app_posting_save', { p_token: token, p_id: null, p_period: v.period || null, p_debit: v.debit, p_credit: v.credit, p_amount: v.amount ? Number(v.amount) : 0, p_memo: v.memo || null, p_source: 'manual', p_entity_type: null, p_entity_id: null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadPo(); loadKpi(); }); }); }
  function loadOsv() {
    return rpc('app_trial_balance', { p_token: token, p_from: $('#d1').value || null, p_to: $('#d2').value || null }).then(function (r) {
      var list = r || [];
      $('#osv').innerHTML = list.length ? tbl('<th>Счёт</th><th>Название</th><th class="num">Дебет</th><th class="num">Кредит</th><th class="num">Сальдо</th>', list.map(function (x) { return '<tr><td><b>' + esc(x.code) + '</b></td><td>' + esc(x.name) + '</td><td class="num">' + money(x.debit) + '</td><td class="num">' + money(x.credit) + '</td><td class="num">' + money(x.balance) + '</td></tr>'; }).join('')) : '<span class="note">Нет данных.</span>';
    });
  }

  $('#addAc').addEventListener('click', acForm);
  $('#addPo').addEventListener('click', poForm);
  $('#osvBtn').addEventListener('click', loadOsv);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadKpi(); loadAc();
  });
})();
