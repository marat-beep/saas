/* ============================================================
   3DMP Service · apps/service — сервис и ремонт (B29)
   Данные: 0060. Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, list = [], customers = [], eq = [], q = '';

  var KIND = { service: 'Сервис', repair: 'Ремонт', warranty: 'Гарантия' };
  var ST = { new: 'Новая', scheduled: 'Запланирована', in_progress: 'В работе', done: 'Выполнена', cancelled: 'Отменена' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return v == null ? '—' : num(v).toLocaleString('ru-RU', { maximumFractionDigits: 0 }) + ' ₽'; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_service_list', { p_token: token, p_q: null }),
      rpc('app_service_kpi', { p_token: token }),
      rpc('app_customer_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_equipment_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; var k = (r[1] && r[1][0]) || {}; customers = r[2] || []; eq = r[3] || [];
      $('#fCust').innerHTML = '<option value="">— нет —</option>' + customers.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + '</option>'; }).join('');
      $('#fEq').innerHTML = '<option value="">— нет —</option>' + eq.map(function (e) { return '<option value="' + e.id + '">' + esc(e.name) + '</option>'; }).join('');
      $('#kpis').innerHTML = cell('Заявок', num(k.requests)) + cell('Открытых', num(k.open), num(k.open) ? '#92400e' : '') +
        cell('Выполнено', num(k.done), '#15803d') + cell('Затраты', money(k.cost_sum));
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (r) { if (!s) return true; return [r.number, r.title, r.customer, r.engineer].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (r) {
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + (KIND[r.kind] || r.kind) + '</span><b>' + esc(r.number) + '</b> · ' + esc(r.title) +
        '<span class="note" style="margin-left:auto;">' + (r.customer ? '🏢 ' + esc(r.customer) + ' · ' : '') + '📅 ' + fmt(r.scheduled_date) + (r.engineer ? ' · 👤 ' + esc(r.engineer) : '') + '</span></div>' +
        '<div class="toolbar mt">' +
        '<select data-st="' + r.id + '" style="padding:7px;border:1px solid var(--border);border-radius:8px;font-size:.78rem;">' +
        Object.keys(ST).map(function (k) { return '<option value="' + k + '"' + (r.status === k ? ' selected' : '') + '>' + ST[k] + '</option>'; }).join('') + '</select>' +
        '<span class="note">' + money(r.cost) + '</span></div></div>';
    }).join('') : '<span class="note">Заявок нет.</span>';
    $$('#list [data-st]').forEach(function (sel) {
      sel.addEventListener('change', function () { rpc('app_service_set_status', { p_token: token, p_id: sel.dataset.st, p_status: sel.value }).then(function (d) { var r = d && d[0]; if (r && !r.ok) { ui.toast(r.message); return; } window.Auth.log('Сервис статус', sel.value); load(); }); });
    });
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fAdd').addEventListener('click', function () {
    var t = $('#fTitle').value.trim(); if (!t) { msg('#fMsg', 'Укажите тему.', 'err'); return; }
    var cost = parseFloat(($('#fCost').value || '').replace(',', '.'));
    rpc('app_service_save', { p_token: token, p_id: null, p_customer_id: $('#fCust').value || null, p_equipment_id: $('#fEq').value || null,
      p_title: t, p_kind: $('#fKind').value, p_scheduled_date: $('#fDate').value || null, p_engineer: $('#fEng').value.trim(),
      p_works: $('#fWorks').value.trim(), p_cost: isNaN(cost) ? null : cost, p_note: null })
      .then(function (d) { var r = d && d[0]; if (!r) { msg('#fMsg', 'Ошибка', 'err'); return; } msg('#fMsg', r.message + ' ' + r.number, 'ok'); window.Auth.log('Сервис', r.number); ['#fTitle', '#fDate', '#fEng', '#fWorks', '#fCost'].forEach(function (s) { $(s).value = ''; }); load(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
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
