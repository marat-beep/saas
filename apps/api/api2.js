/* ============================================================
   3DMP Service · apps/api/api2.js — Экосистема (W17, 0167).
   Лог API, реестр подписей, проверка контрагентов, KPI.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null;
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#e2m'); if (!e) return; e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dt(v) { return v ? new Date(v).toLocaleString('ru-RU') : '—'; }

  function showTab(scr) {
    $$('#e2tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.e2scr').forEach(function (s) { s.classList.toggle('active', s.id === 'e2-' + scr); });
    if (scr === 'log') loadLog();
    if (scr === 'sig') loadSig();
    if (scr === 'cp') loadCp();
  }
  $$('#e2tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_ecosystem_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#e2kpi').innerHTML = cell('API-ключей', k.api_keys || 0) + cell('Активных', k.keys_active || 0) + cell('Webhooks', k.webhooks || 0) + cell('Подписей', k.signatures || 0) + cell('Риск (high)', k.cp_high || 0) + cell('Вызовов API', k.api_calls || 0);
    }).catch(function () {});
  }
  function loadLog() {
    return rpc('app_api_log_list', { p_token: token, p_limit: 100 }).then(function (r) {
      var list = r || [];
      $('#e2log').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Когда</th><th>Метод</th><th>Путь</th><th class="num">Код</th><th>Ключ</th></tr></thead><tbody>' +
        list.map(function (x) { return '<tr><td class="muted">' + dt(x.ts) + '</td><td>' + esc(x.method || '') + '</td><td>' + esc(x.path || '') + '</td><td class="num">' + (x.status || '') + '</td><td class="muted">' + esc(x.key_name || '—') + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Записей нет.</span>';
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function loadSig() {
    return rpc('app_signatures_list', { p_token: token, p_entity_type: null, p_entity_id: null }).then(function (r) {
      var list = r || [];
      $('#e2sig').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Когда</th><th>Объект</th><th>Подписал</th><th>Метод</th><th>Статус</th><th></th></tr></thead><tbody>' +
        list.map(function (x) { return '<tr><td class="muted">' + dt(x.signed_at) + '</td><td>' + esc(x.entity_type) + (x.entity_id ? ' · ' + String(x.entity_id).slice(0, 8) : '') + '</td><td>' + esc(x.signer_login || '') + '</td><td>' + esc(x.method) + '</td><td>' + esc(x.status) + '</td>' +
          '<td>' + (x.status === 'signed' ? '<button class="act danger" data-rev="' + x.id + '">Отозвать</button>' : '') + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Подписей нет.</span>';
      $$('#e2sig [data-rev]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_signature_revoke', { p_token: token, p_id: b.dataset.rev }).then(function () { loadSig(); loadKpi(); }); }); });
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function sigAdd() {
    ui.formDialog({ title: 'Регистрация подписи', okText: 'Подписать', fields: [
      { name: 'entity_type', label: 'Тип объекта', type: 'text', required: true, placeholder: 'doc_flow / hr_doc' },
      { name: 'entity_id', label: 'ID объекта (UUID)', type: 'text' },
      { name: 'method', label: 'Метод', type: 'select', options: [{ value: 'ПЭП', label: 'ПЭП' }, { value: 'УНЭП', label: 'УНЭП' }, { value: 'УКЭП', label: 'УКЭП' }, { value: 'Госключ', label: 'Госключ' }] }
    ], values: { method: 'ПЭП' } }).then(function (v) {
      if (!v) return;
      rpc('app_signature_register', { p_token: token, p_entity_type: v.entity_type, p_entity_id: v.entity_id || null, p_method: v.method, p_note: null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadSig(); loadKpi(); });
    });
  }
  function loadCp() {
    return rpc('app_counterparty_checks_list', { p_token: token, p_limit: 50 }).then(function (r) {
      var list = r || [];
      $('#e2cp').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Когда</th><th>Тип</th><th>Контрагент</th><th>ИНН</th><th class="num">Балл</th><th>Риск</th></tr></thead><tbody>' +
        list.map(function (x) { return '<tr><td class="muted">' + dt(x.checked_at) + '</td><td>' + esc(x.entity_type) + '</td><td>' + esc(x.entity_name || '') + '</td><td>' + esc(x.inn || '') + '</td><td class="num">' + x.risk_score + '</td><td>' + (x.risk_level === 'high' ? '🔴 высокий' : x.risk_level === 'medium' ? '🟡 средний' : '🟢 низкий') + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Проверок нет.</span>';
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function cpAdd() {
    ui.formDialog({ title: 'Проверка контрагента', okText: 'Проверить', fields: [
      { name: 'entity_type', label: 'Тип', type: 'select', options: [{ value: 'customer', label: 'Клиент' }, { value: 'supplier', label: 'Поставщик' }] },
      { name: 'name', label: 'Название', type: 'text', required: true }, { name: 'inn', label: 'ИНН', type: 'text' }
    ], values: { entity_type: 'customer' } }).then(function (v) {
      if (!v) return;
      rpc('app_counterparty_check', { p_token: token, p_entity_type: v.entity_type, p_entity_id: null, p_name: v.name, p_inn: v.inn || null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadCp(); loadKpi(); });
    });
  }

  $('#e2logBtn').addEventListener('click', loadLog);
  $('#e2sigAdd').addEventListener('click', sigAdd);
  $('#e2cpAdd').addEventListener('click', cpAdd);

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    token = s.token;
    if (!SB) return;
    loadKpi(); showTab('log');
  });
})();
