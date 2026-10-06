/* ============================================================
   3DMP Service · apps/escrow — P5 эскроу. Данные: 0067.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], orders = [], cur = null, q = '';

  var ST = { created: ['Создана', 'normal'], funded: ['Заморожено', 'new'], in_work: ['В работе', 'in_progress'], released: ['Высвобождено', 'done'], dispute: ['Спор', 'high'], cancelled: ['Отменена', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function money(v) { return (v == null ? 0 : Number(v)).toLocaleString('ru-RU') + ' ₽'; }

  function load() {
    return Promise.all([
      rpc('app_escrow_list', { p_token: token, p_q: null }),
      rpc('app_escrow_kpi', { p_token: token }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; orders = r[2] || [];
      $('#fOrder').innerHTML = '<option value="">— не выбрана —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Сделок', k.total || 0) + cell('Активных', k.active || 0) + cell('Высвобождено', money(k.released_sum)) + cell('Заморожено', money(k.frozen_sum)) + cell('Комиссия', money(k.fee_sum));
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (d) { return !s || [(d.number || ''), (d.buyer || ''), (d.seller || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (d) {
      var st = ST[d.status] || [d.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + esc(d.number) + '</span><span class="badge ' + st[1] + '">' + esc(st[0]) + '</span>' +
        '<b>' + money(d.amount) + '</b>' + (d.order_number ? '<span class="note">заявка ' + esc(d.order_number) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">комиссия ' + money(d.fee) + ' → выплата ' + money(d.payout) + '</span></div>' +
        '<div class="note mt">' + esc(d.buyer || '—') + ' → ' + esc(d.seller || '—') + (d.milestone ? ' · ' + esc(d.milestone) : '') + '</div>' +
        '<div class="toolbar mt">' +
        '<button class="btn secondary" data-edit="' + d.id + '" style="width:auto;padding:7px 12px;">Реквизиты</button>' +
        '<button class="btn secondary" data-ev="' + d.id + '" style="width:auto;padding:7px 12px;">События</button>' +
        (d.status === 'created' ? '<button class="btn" data-st="funded" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">Заморозить</button>' : '') +
        (d.status === 'funded' ? '<button class="btn" data-st="in_work" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">В работу</button>' : '') +
        (d.status !== 'released' && d.status !== 'cancelled' ? '<button class="btn" data-st="released" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">Высвободить</button>' : '') +
        (d.status !== 'dispute' && d.status !== 'released' ? '<button class="btn secondary" data-st="dispute" data-id="' + d.id + '" style="width:auto;padding:7px 12px;">Спор</button>' : '') +
        '</div></div>';
    }).join('') : '<span class="note">Сделок нет.</span>';
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { edit(b.dataset.edit); }); });
    $$('#list [data-ev]').forEach(function (b) { b.addEventListener('click', function () { openEvents(b.dataset.ev); }); });
    $$('#list [data-st]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_escrow_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.st, p_comment: null })
        .then(function () { load(); }).catch(function (e) { msg('#mMsg', e.message, 'err'); });
    }); });
  }

  function edit(id) {
    cur = list.filter(function (d) { return d.id === id; })[0]; if (!cur) return;
    $('#fAmount').value = cur.amount || 0; $('#fFee').value = cur.fee_pct || 2.5; $('#fBuyer').value = cur.buyer || '';
    $('#fSeller').value = cur.seller || ''; $('#fMilestone').value = cur.milestone || ''; window.scrollTo(0, 0);
  }

  function openEvents(id) {
    var d = list.filter(function (x) { return x.id === id; })[0];
    $('#evCard').style.display = 'block'; $('#evTitle').textContent = d ? '· ' + d.number : '';
    rpc('app_escrow_events_list', { p_token: token, p_deal_id: id }).then(function (r) {
      $('#events').innerHTML = (r && r.length) ? '<div class="olist">' + r.map(function (e) {
        return '<div class="ocard"><div style="display:flex;gap:8px;"><span class="badge">' + esc(e.kind) + '</span><span>' + esc(e.comment || '') + '</span><span class="note" style="margin-left:auto;">' + new Date(e.created_at).toLocaleString('ru-RU') + ' · ' + esc(e.by_login || '') + '</span></div></div>';
      }).join('') + '</div>' : '<span class="note">Событий нет.</span>';
    });
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fClear').addEventListener('click', function () { cur = null; ['fBuyer', 'fSeller', 'fMilestone', 'fNote'].forEach(function (i) { $('#' + i).value = ''; }); msg('#fMsg', ''); });
  $('#fSave').addEventListener('click', function () {
    rpc('app_escrow_save', { p_token: token, p_id: cur ? cur.id : null, p_order_id: $('#fOrder').value || null, p_customer_id: null,
      p_buyer: $('#fBuyer').value, p_seller: $('#fSeller').value, p_amount: parseFloat($('#fAmount').value) || 0,
      p_fee_pct: parseFloat($('#fFee').value) || 0, p_milestone: $('#fMilestone').value, p_note: $('#fNote').value })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? (x.message + ' ' + x.number) : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('Эскроу', x.number); cur = null; load(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
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
