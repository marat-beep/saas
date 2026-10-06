/* ============================================================
   3DMP Service · apps/teo — ТЭО (статьи и итог). Данные: 0064.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], orders = [], cur = null, lines = [], q = '';

  var KIND = { metal: 'Металл', consumables: 'Расходники', labor: 'Работы', service: 'Услуги', other: 'Прочее' };
  var ST = { draft: ['Черновик', 'normal'], approved: ['Утверждено', 'done'], rejected: ['Отклонено', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function money(v) { return (v == null ? 0 : Number(v)).toLocaleString('ru-RU') + ' ₽'; }

  function load() {
    return Promise.all([
      rpc('app_teo_list', { p_token: token, p_q: null }),
      rpc('app_teo_kpi', { p_token: token }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; orders = r[2] || [];
      $('#fOrder').innerHTML = '<option value="">— не выбрана —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('Черновиков', k.drafts || 0) + cell('Утверждено', k.approved || 0) + cell('Сумма', money(k.amount_sum));
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (t) { return !s || [(t.number || ''), (t.title || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (t) {
      var st = ST[t.status] || [t.status, ''];
      return '<div class="ocard" data-open="' + t.id + '"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + esc(t.number) + '</span><span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(t.title) + '</b>' +
        (t.order_number ? '<span class="note">заявка ' + esc(t.order_number) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + money(t.total) + ' · статей ' + (t.lines || 0) + '</span></div>' +
        '<div class="toolbar mt"><button class="btn secondary" data-edit="' + t.id + '" style="width:auto;padding:7px 12px;">Реквизиты</button>' +
        '<button class="btn" data-lines="' + t.id + '" style="width:auto;padding:7px 12px;">Статьи и итог</button></div></div>';
    }).join('') : '<span class="note">ТЭО нет.</span>';
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function (e) { e.stopPropagation(); edit(b.dataset.edit); }); });
    $$('#list [data-lines]').forEach(function (b) { b.addEventListener('click', function (e) { e.stopPropagation(); openLines(b.dataset.lines); }); });
  }

  function edit(id) {
    cur = list.filter(function (t) { return t.id === id; })[0]; if (!cur) return;
    $('#fTitle').value = cur.title || ''; $('#fNote').value = ''; window.scrollTo(0, 0);
  }

  function openLines(id) {
    cur = list.filter(function (t) { return t.id === id; })[0]; if (!cur) return;
    $('#linesCard').style.display = 'block'; $('#curTitle').textContent = '· ' + (cur.number || '') + ' ' + (cur.title || '');
    rpc('app_teo_lines_list', { p_token: token, p_teo_id: id }).then(function (r) { lines = r || []; renderLines(); });
  }

  function renderLines() {
    var total = lines.reduce(function (s, l) { return s + (Number(l.amount) || 0); }, 0);
    $('#lines').innerHTML = '<table class="mini"><thead><tr><th>Вид</th><th>Наименование</th><th class="num">Кол-во</th><th class="num">Цена</th><th class="num">Сумма</th><th></th></tr></thead><tbody>' +
      (lines.length ? lines.map(function (l) {
        return '<tr><td>' + esc(KIND[l.kind] || l.kind) + '</td><td>' + esc(l.name) + '</td><td class="num">' + (l.qty || 0) + '</td><td class="num">' + money(l.price) + '</td><td class="num">' + money(l.amount) + '</td>' +
          '<td><button class="btn secondary" data-dl="' + l.id + '" style="width:auto;padding:3px 8px;font-size:.72rem;">×</button></td></tr>';
      }).join('') : '<tr><td colspan="6" class="note">Статей нет.</td></tr>') +
      '</tbody><tfoot><tr><th colspan="4">ИТОГО</th><th class="num">' + money(total) + '</th><th></th></tr></tfoot></table>';
    $$('#lines [data-dl]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_teo_line_delete', { p_token: token, p_id: b.dataset.dl }).then(function () { openLines(cur.id); });
    }); });
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fSave').addEventListener('click', function () {
    var title = $('#fTitle').value.trim(); if (!title) { msg('#fMsg', 'Укажите название.', 'err'); return; }
    rpc('app_teo_save', { p_token: token, p_id: cur ? cur.id : null, p_order_id: $('#fOrder').value || null, p_title: title, p_note: $('#fNote').value })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? (x.message + ': ' + x.number) : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('ТЭО', x.number); cur = null; load(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#fFromOrder').addEventListener('click', function () {
    var oid = $('#fOrder').value; if (!oid) { msg('#fMsg', 'Выберите заявку.', 'err'); return; }
    rpc('app_teo_from_order', { p_token: token, p_order_id: oid }).then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); load(); });
  });
  $('#lAdd').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_teo_line_save', { p_token: token, p_id: null, p_teo_id: cur.id, p_kind: $('#lKind').value,
      p_name: $('#lName').value, p_qty: parseFloat($('#lQty').value) || 1, p_price: parseFloat($('#lPrice').value) || 0 })
      .then(function (r) { var x = r && r[0]; msg('#lMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); $('#lName').value = ''; openLines(cur.id); });
  });
  $('#teoApprove').addEventListener('click', function () { if (cur) setStatus('approved'); });
  $('#teoReject').addEventListener('click', function () { if (cur) setStatus('rejected'); });
  function setStatus(st) { rpc('app_teo_set_status', { p_token: token, p_id: cur.id, p_status: st }).then(function () { load(); openLines(cur.id); }).catch(function (e) { msg('#lMsg', e.message, 'err'); }); }
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
