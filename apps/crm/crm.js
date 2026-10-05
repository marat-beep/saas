/* ============================================================
   3DMP Service · apps/crm — CRM (сделки/воронка, заказчики)
   Данные: 0056 (+ app_customer_list). Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, deals = [], customers = [], q = '';

  var STAGES = [['lead', 'Лид'], ['qualified', 'Квалифицирована'], ['proposal', 'Предложение'], ['negotiation', 'Переговоры'], ['won', 'Выиграна'], ['lost', 'Проиграна']];
  var SNAME = { lead: 'Лид', qualified: 'Квалифицирована', proposal: 'Предложение', negotiation: 'Переговоры', won: 'Выиграна', lost: 'Проиграна' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return num(v).toLocaleString('ru-RU', { maximumFractionDigits: 0 }) + ' ₽'; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_deal_list', { p_token: token, p_q: null }),
      rpc('app_deal_kpi', { p_token: token }),
      rpc('app_customer_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      deals = r[0] || []; var k = (r[1] && r[1][0]) || {}; customers = r[2] || [];
      $('#fCust').innerHTML = '<option value="">— выберите —</option>' + customers.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + '</option>'; }).join('');
      $('#kpis').innerHTML = cell('Сделок', num(k.deals_total)) + cell('Открытых', num(k.open_deals)) +
        cell('Воронка (взвеш.)', money(k.pipeline)) + cell('Выиграно', money(k.won_sum), '#15803d') + cell('Конверсия', num(k.conversion) + '%');
      render(); renderCustomers();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function render() {
    var list = deals.filter(function (d) { if (!q) return true; var s = q.toLowerCase(); return [d.title, d.customer, d.owner_login].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + list.length + ')';
    $('#board').innerHTML = STAGES.map(function (st) {
      var items = list.filter(function (d) { return d.stage === st[0]; });
      return '<div class="col"><h3>' + st[1] + ' (' + items.length + ')</h3>' + (items.length ? items.map(dcard).join('') : '<span class="note" style="font-size:.74rem;">—</span>') + '</div>';
    }).join('');
    $$('#board [data-stage]').forEach(function (sel) {
      sel.addEventListener('change', function () {
        rpc('app_deal_set_stage', { p_token: token, p_id: sel.dataset.stage, p_stage: sel.value })
          .then(function (d) { var r = d && d[0]; if (r && !r.ok) { ui.toast(r.message); return; } window.Auth.log('CRM стадия', sel.value); if (window.AppNotify) window.AppNotify.refresh(true); load(); })
          .catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
      });
    });
  }
  function dcard(d) {
    return '<div class="dcard"><div style="font-weight:600;font-size:.84rem;">' + esc(d.title) + '</div>' +
      '<div style="font-size:.74rem;color:var(--muted);margin-top:3px;">' + (d.customer ? '🏢 ' + esc(d.customer) + ' · ' : '') + (d.owner_login ? '👤 ' + esc(d.owner_login) : '') + '</div>' +
      '<div style="font-size:.8rem;margin-top:4px;">' + money(d.amount) + ' · ' + num(d.probability) + '% → <b>' + money(d.weighted) + '</b></div>' +
      (d.next_action ? '<div class="note" style="margin-top:3px;">→ ' + esc(d.next_action) + (d.due_date ? ' (до ' + esc(d.due_date) + ')' : '') + '</div>' : '') +
      '<select data-stage="' + d.id + '" style="margin-top:6px;width:100%;padding:6px;border:1px solid var(--border);border-radius:8px;font-size:.78rem;">' +
      STAGES.map(function (s) { return '<option value="' + s[0] + '"' + (d.stage === s[0] ? ' selected' : '') + '>' + s[1] + '</option>'; }).join('') + '</select></div>';
  }
  function renderCustomers() {
    $('#customers').innerHTML = customers.length ? customers.map(function (c) {
      return '<div class="kvr"><b>' + esc(c.name) + '</b><span class="note">' + (c.inn ? 'ИНН ' + esc(c.inn) + ' · ' : '') + (c.contact_person ? esc(c.contact_person) + ' · ' : '') + (c.phone || '') + (c.email ? ' · ' + esc(c.email) : '') + '</span></div>';
    }).join('') : '<span class="note">Заказчиков нет.</span>';
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fAdd').addEventListener('click', function () {
    var title = $('#fTitle').value.trim(); if (!title) { msg('#fMsg', 'Укажите название сделки.', 'err'); return; }
    var amt = parseFloat(($('#fAmount').value || '').replace(',', '.')); var pr = parseInt($('#fProb').value || '', 10);
    rpc('app_deal_save', { p_token: token, p_id: null, p_customer_id: $('#fCust').value || null, p_title: title, p_stage: $('#fStage').value,
      p_amount: isNaN(amt) ? null : amt, p_probability: isNaN(pr) ? 10 : pr, p_source: $('#fSource').value.trim(), p_owner: $('#fOwner').value.trim(),
      p_next_action: $('#fNext').value.trim(), p_due_date: $('#fDue').value || null, p_order_id: null, p_note: null })
      .then(function (d) { var r = d && d[0]; msg('#fMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('CRM сделка', title); ['#fTitle', '#fAmount', '#fProb', '#fOwner', '#fSource', '#fNext', '#fDue'].forEach(function (s) { $(s).value = ''; }); load(); } })
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
