/* ============================================================
   3DMP Service · apps/tkp — реестр ТКП
   Данные: 0057. Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, tkps = [], customers = [], q = '', filter = '';

  var ST = { actual: 'Актуальное', expired: 'Истёк срок', contracted: 'Заключён договор', closed: 'Закрыто' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return v == null ? '—' : num(v).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_tkp_list', { p_token: token, p_q: null }),
      rpc('app_customer_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      tkps = r[0] || []; customers = r[1] || [];
      $('#fCust').innerHTML = '<option value="">— выберите —</option>' + customers.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + '</option>'; }).join('');
      renderKpi(); render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    var c = { actual: 0, expired: 0, contracted: 0, closed: 0 };
    tkps.forEach(function (t) { if (c[t.status] != null) c[t.status]++; });
    $('#kpis').innerHTML = cell('Всего', tkps.length) + cell('Актуальные', c.actual) + cell('Истёк срок', c.expired, c.expired ? '#b91c1c' : '') +
      cell('Договор', c.contracted, '#15803d') + cell('Закрытые', c.closed);
    function cell(l, v, col) { return '<div class="kpi"><small>' + l + '</small><b' + (col ? ' style="color:' + col + '"' : '') + '>' + v + '</b></div>'; }
  }
  function render() {
    var s = q.toLowerCase();
    var list = tkps.filter(function (t) {
      if (filter && t.status !== filter) return false;
      if (!s) return true;
      return [t.number, t.subject, t.counterparty, t.customer].join(' ').toLowerCase().indexOf(s) >= 0;
    });
    $('#list').innerHTML = '<table class="table" style="width:100%;border-collapse:collapse"><thead><tr><th>Номер</th><th>Дата</th><th>Заказчик</th><th>Предмет</th><th>Срок</th><th>Цена</th><th>Статус</th></tr></thead><tbody>' +
      (list.length ? list.map(function (t) {
        return '<tr style="border-bottom:1px solid var(--border)"><td><b>' + esc(t.number) + '</b></td><td>' + fmt(t.tkp_date) + '</td>' +
          '<td>' + esc(t.customer || t.counterparty || '—') + '</td><td>' + esc(t.subject) + '</td>' +
          '<td>' + fmt(t.valid_until) + (t.expired ? ' <span class="badge cancelled">просрочено</span>' : '') + '</td><td>' + money(t.price) + '</td>' +
          '<td><select data-st="' + t.id + '" style="padding:5px;border:1px solid var(--border);border-radius:7px;font-size:.76rem;">' +
          Object.keys(ST).map(function (k) { return '<option value="' + k + '"' + (t.status === k ? ' selected' : '') + '>' + ST[k] + '</option>'; }).join('') +
          '</select></td></tr>';
      }).join('') : '<tr><td colspan="7"><span class="note">ТКП нет.</span></td></tr>') + '</tbody></table>';
    $$('#list [data-st]').forEach(function (sel) {
      sel.addEventListener('change', function () {
        rpc('app_tkp_set_status', { p_token: token, p_id: sel.dataset.st, p_status: sel.value })
          .then(function (d) { var r = d && d[0]; if (r && !r.ok) { ui.toast(r.message); return; } window.Auth.log('ТКП статус', sel.value); load(); })
          .catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
      });
    });
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    filter = b.dataset.f; render();
  });
  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fAdd').addEventListener('click', function () {
    var subj = $('#fSubject').value.trim(); if (!subj) { msg('#fMsg', 'Укажите предмет ТКП.', 'err'); return; }
    var price = parseFloat(($('#fPrice').value || '').replace(',', '.'));
    rpc('app_tkp_save', { p_token: token, p_id: null, p_customer_id: $('#fCust').value || null, p_counterparty: $('#fCounter').value.trim(),
      p_subject: subj, p_valid_until: $('#fValid').value || null, p_price: isNaN(price) ? null : price, p_order_id: null, p_document_id: null, p_note: null })
      .then(function (d) { var r = d && d[0]; msg('#fMsg', (r && r.message) || '', r && r.ok !== false ? 'ok' : 'err'); if (r && r.id) { window.Auth.log('ТКП', r.number); ['#fSubject', '#fCounter', '#fValid', '#fPrice'].forEach(function (s) { $(s).value = ''; }); load(); } })
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
