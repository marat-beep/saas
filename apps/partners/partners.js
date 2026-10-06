/* ============================================================
   3DMP Service · apps/partners — C2 партнёрский кабинет. Данные: 0082.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], deals = [], orders = [], cur = null, q = '';

  var ST = { active: ['Активен', 'done'], paused: ['Пауза', 'in_progress'], archived: ['Архив', 'cancelled'] };
  var DS = { new: ['Новая', 'normal'], in_work: ['В работе', 'in_progress'], won: ['Выиграна', 'done'], lost: ['Проиграна', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function money(v) { return (v == null ? 0 : Number(v)).toLocaleString('ru-RU') + ' ₽'; }

  function load() {
    return Promise.all([
      rpc('app_partners_list', { p_token: token, p_q: null }),
      rpc('app_partner_deals_list', { p_token: token, p_q: null }),
      rpc('app_partners_kpi', { p_token: token }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; deals = r[1] || []; orders = r[3] || [];
      var k = (r[2] && r[2][0]) || {};
      $('#kpis').innerHTML = cell('Партнёров', k.partners || 0) + cell('Активных', k.active || 0) + cell('Сделок', k.deals || 0) + cell('Выиграно', money(k.won_amount)) + cell('Комиссия', money(k.commission_sum));
      $('#dPartner').innerHTML = '<option value="">— партнёр —</option>' + list.map(function (p) { return '<option value="' + p.id + '">' + esc(p.name) + '</option>'; }).join('');
      $('#dOrder').innerHTML = '<option value="">— не выбрана —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      renderPartners(); renderDeals();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderPartners() {
    var s = q.toLowerCase();
    var rows = list.filter(function (p) { return !s || [(p.name || ''), (p.contact || ''), (p.region || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (p) {
      var st = ST[p.status] || [p.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(p.name) + '</b>' +
        '<span class="badge">' + esc(p.category || '—') + '</span>' +
        '<span class="note">комиссия ' + (p.commission_pct || 0) + '% · сделок ' + (p.deals || 0) + '</span>' +
        '<span class="note" style="margin-left:auto;">' + esc(p.region || '') + '</span></div>' +
        '<div class="note mt">ИНН ' + esc(p.inn || '—') + ' · ' + esc(p.contact || '') + ' ' + esc(p.phone || '') + ' ' + esc(p.email || '') + '</div>' +
        '<div class="toolbar mt"><button class="btn secondary" data-edit="' + p.id + '" style="width:auto;padding:7px 12px;">Править</button>' +
        (p.status !== 'active' ? '<button class="btn" data-st="active" data-id="' + p.id + '" style="width:auto;padding:7px 12px;">Активировать</button>' : '') +
        (p.status === 'active' ? '<button class="btn secondary" data-st="archived" data-id="' + p.id + '" style="width:auto;padding:7px 12px;">В архив</button>' : '') +
        '</div></div>';
    }).join('') : '<span class="note">Партнёров нет.</span>';
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { edit(b.dataset.edit); }); });
    $$('#list [data-st]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_partner_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.st }).then(load).catch(function (e) { msg('#mMsg', e.message, 'err'); }); }); });
  }

  function renderDeals() {
    $('#dCnt').textContent = '(' + deals.length + ')';
    $('#dList').innerHTML = deals.length ? deals.map(function (d) {
      var st = DS[d.status] || [d.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(d.title) + '</b>' +
        (d.partner_name ? '<span class="note">' + esc(d.partner_name) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + money(d.amount) + ' · комиссия ' + money(d.commission) + '</span></div>' +
        '<div class="toolbar mt">' +
        (d.status !== 'in_work' && d.status !== 'won' ? '<button class="btn secondary" data-dst="in_work" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">В работу</button>' : '') +
        (d.status !== 'won' ? '<button class="btn" data-dst="won" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">Выиграна</button>' : '') +
        (d.status !== 'lost' ? '<button class="btn secondary" data-dst="lost" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">Проиграна</button>' : '') +
        '</div></div>';
    }).join('') : '<span class="note">Сделок нет.</span>';
    $$('#dList [data-dst]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_partner_deal_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.dst }).then(load).catch(function (e) { msg('#dMsg', e.message, 'err'); }); }); });
  }

  function edit(id) {
    cur = list.filter(function (x) { return x.id === id; })[0]; if (!cur) return;
    $('#fName').value = cur.name || ''; $('#fInn').value = cur.inn || ''; $('#fContact').value = cur.contact || '';
    $('#fPhone').value = cur.phone || ''; $('#fEmail').value = cur.email || ''; $('#fRegion').value = cur.region || '';
    $('#fCat').value = cur.category || 'агент'; $('#fCom').value = cur.commission_pct || 5; window.scrollTo(0, 0);
  }

  $('#q').addEventListener('input', function () { q = this.value; renderPartners(); });
  $('#fClear').addEventListener('click', function () { cur = null; ['fName', 'fInn', 'fContact', 'fPhone', 'fEmail', 'fRegion'].forEach(function (i) { $('#' + i).value = ''; }); msg('#fMsg', ''); });
  $('#fSave').addEventListener('click', function () {
    rpc('app_partner_save', { p_token: token, p_id: cur ? cur.id : null, p_name: $('#fName').value, p_inn: $('#fInn').value,
      p_contact: $('#fContact').value, p_phone: $('#fPhone').value, p_email: $('#fEmail').value, p_region: $('#fRegion').value,
      p_category: $('#fCat').value, p_commission_pct: parseFloat($('#fCom').value) || 5, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('Партнёр', $('#fName').value); cur = null; load(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#dSave').addEventListener('click', function () {
    rpc('app_partner_deal_save', { p_token: token, p_id: null, p_partner_id: $('#dPartner').value || null, p_order_id: $('#dOrder').value || null,
      p_title: $('#dTitle').value, p_amount: parseFloat($('#dAmount').value) || 0, p_commission: parseFloat($('#dCom').value) || 0, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#dMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); $('#dTitle').value = ''; load(); })
      .catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
