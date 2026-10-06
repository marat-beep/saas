/* ============================================================
   3DMP Service · apps/labels — упаковка и маркировка (B37). Данные: 0065.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, packages = [], labels = [], orders = [], curP = null, curL = null, q = '', filter = '';

  var PK = { box: 'Коробка', pallet: 'Паллета', crate: 'Ящик', bag: 'Мешок', other: 'Прочее' };
  var LT = { cargo: 'Грузовая', position: 'Бирка позиции', tag: 'Манипуляц.' };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_package_list', { p_token: token, p_q: null }),
      rpc('app_package_kpi', { p_token: token }),
      rpc('app_label_list', { p_token: token, p_type: filter || null, p_q: null }),
      rpc('app_label_kpi', { p_token: token }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      packages = r[0] || []; labels = r[2] || []; orders = r[4] || [];
      var pk = (r[1] && r[1][0]) || {}, lk = (r[3] && r[3][0]) || {};
      $('#kpis').innerHTML = cell('Мест', pk.packages || 0) + cell('Брутто, кг', pk.gross_sum || 0) + cell('Этикеток', lk.total || 0) + cell('Грузовых', lk.cargo || 0);
      var opts = '<option value="">— не выбрана —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      $('#pOrder').innerHTML = opts; $('#lOrder').innerHTML = opts;
      $('#lPackage').innerHTML = '<option value="">— не выбрано —</option>' + packages.map(function (p) { return '<option value="' + p.id + '">' + (p.order_number || '') + ' · место ' + p.package_no + '</option>'; }).join('');
      renderPackages(); renderLabels();
    }).catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderPackages() {
    $('#pCnt').textContent = '(' + packages.length + ')';
    $('#pList').innerHTML = packages.length ? packages.map(function (p) {
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">№' + p.package_no + '</span><b>' + esc(PK[p.kind] || p.kind) + '</b>' +
        (p.order_number ? '<span class="note">заявка ' + esc(p.order_number) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + esc(p.dims || '') + ' · брутто ' + (p.gross || 0) + ' / нетто ' + (p.net || 0) + ' кг · ' + (p.positions || 0) + ' поз.</span></div>' +
        (p.marks ? '<div class="note mt">Знаки: ' + esc(p.marks) + '</div>' : '') +
        '<div class="toolbar mt"><button class="btn secondary" data-pedit="' + p.id + '" style="width:auto;padding:7px 12px;">Редактировать</button>' +
        '<button class="btn secondary" data-pdel="' + p.id + '" style="width:auto;padding:7px 12px;">Удалить</button></div></div>';
    }).join('') : '<span class="note">Грузовых мест нет.</span>';
    $$('#pList [data-pedit]').forEach(function (b) { b.addEventListener('click', function () { editP(b.dataset.pedit); }); });
    $$('#pList [data-pdel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_package_delete', { p_token: token, p_id: b.dataset.pdel }).then(load); }); });
  }

  function renderLabels() {
    var s = q.toLowerCase();
    var rows = labels.filter(function (l) { return !s || [(l.recipient || ''), (l.item || ''), (l.order_number || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#lCnt').textContent = '(' + rows.length + ')';
    $('#lList').innerHTML = rows.length ? rows.map(function (l) {
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + esc(LT[l.label_type] || l.label_type) + '</span><b>' + esc(l.item || l.recipient || '—') + '</b>' +
        (l.order_number ? '<span class="note">заявка ' + esc(l.order_number) + '</span>' : '') +
        (l.cargo_no ? '<span class="note" style="margin-left:auto;">место ' + l.cargo_no + (l.cargo_total ? '/' + l.cargo_total : '') + '</span>' : '') + '</div>' +
        '<div class="note mt">' + esc(l.recipient || '') + ' · ' + (l.qty || 0) + ' шт · ' + esc(l.dims || '') + ' · брутто ' + (l.gross || 0) + ' / нетто ' + (l.net || 0) + ' кг</div>' +
        '<div class="toolbar mt"><button class="btn secondary" data-ledit="' + l.id + '" style="width:auto;padding:7px 12px;">Редактировать</button>' +
        '<button class="btn" data-lprint="' + l.id + '" style="width:auto;padding:7px 12px;">Печать</button>' +
        '<button class="btn secondary" data-ldel="' + l.id + '" style="width:auto;padding:7px 12px;">Удалить</button></div></div>';
    }).join('') : '<span class="note">Этикеток нет.</span>';
    $$('#lList [data-ledit]').forEach(function (b) { b.addEventListener('click', function () { editL(b.dataset.ledit); }); });
    $$('#lList [data-ldel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_label_delete', { p_token: token, p_id: b.dataset.ldel }).then(load); }); });
    $$('#lList [data-lprint]').forEach(function (b) { b.addEventListener('click', function () { printLabel(labels.filter(function (l) { return l.id === b.dataset.lprint; })[0]); }); });
  }

  function editP(id) {
    curP = packages.filter(function (p) { return p.id === id; })[0]; if (!curP) return;
    $('#pNo').value = curP.package_no || 1; $('#pKind').value = curP.kind || 'box'; $('#pDims').value = curP.dims || '';
    $('#pGross').value = curP.gross || 0; $('#pNet').value = curP.net || 0; $('#pPos').value = curP.positions || 0; $('#pMarks').value = curP.marks || '';
    window.scrollTo(0, 0);
  }
  function editL(id) {
    curL = labels.filter(function (l) { return l.id === id; })[0]; if (!curL) return;
    $('#lType').value = curL.label_type; $('#lRecipient').value = curL.recipient || ''; $('#lSender').value = curL.sender || '';
    $('#lItem').value = curL.item || ''; $('#lQty').value = curL.qty || 0; $('#lDims').value = curL.dims || '';
    $('#lGross').value = curL.gross || 0; $('#lNet').value = curL.net || 0; $('#lPos').value = curL.position_no || '';
    $('#lIdent').value = curL.identifier || ''; $('#lCargoNo').value = curL.cargo_no || ''; $('#lCargoTotal').value = curL.cargo_total || '';
    window.scrollTo(0, 0);
  }

  function printLabel(l) {
    if (!l) return;
    var w = window.open('', '_blank', 'width=520,height=640');
    var html = '<html><head><meta charset="utf-8"><title>Этикетка</title><style>' +
      'body{font-family:Arial,sans-serif;margin:16px;color:#111}h1{font-size:16px;margin:0 0 8px}' +
      '.row{display:flex;justify-content:space-between;border-bottom:1px solid #ccc;padding:5px 0;font-size:13px}' +
      '.b{font-weight:700}.big{font-size:22px;font-weight:800;margin:10px 0}.signs{margin-top:12px;font-size:18px;letter-spacing:6px}' +
      'table{width:100%;border-collapse:collapse;margin-top:8px}td{border:1px solid #999;padding:6px;font-size:13px}' +
      '</style></head><body>' +
      '<h1>' + (LT[l.label_type] || 'Этикетка') + '</h1>' +
      '<div class="row"><span>Получатель</span><span class="b">' + esc(l.recipient || '') + '</span></div>' +
      '<div class="row"><span>Отправитель</span><span>' + esc(l.sender || '') + '</span></div>' +
      '<div class="row"><span>Заявка</span><span class="b">' + esc(l.order_number || '') + '</span></div>' +
      '<div class="row"><span>Товар</span><span>' + esc(l.item || '') + '</span></div>' +
      '<div class="row"><span>Количество</span><span>' + (l.qty || 0) + '</span></div>' +
      '<div class="row"><span>Габариты</span><span>' + esc(l.dims || '') + '</span></div>' +
      '<div class="row"><span>Брутто / Нетто</span><span>' + (l.gross || 0) + ' / ' + (l.net || 0) + ' кг</span></div>' +
      (l.position_no ? '<div class="row"><span>№ позиции</span><span>' + l.position_no + '</span></div>' : '') +
      (l.identifier ? '<div class="row"><span>Идентификатор</span><span>' + esc(l.identifier) + '</span></div>' : '') +
      (l.cargo_no ? '<div class="big">Место ' + l.cargo_no + (l.cargo_total ? ' / ' + l.cargo_total : '') + '</div>' : '') +
      (l.label_type === 'tag' ? '<div class="signs">☂  ⇧  🍷  ❄</div>' : '') +
      '<p style="font-size:11px;color:#666;margin-top:14px">3DMP Service · упаковка и маркировка</p>' +
      '</body></html>';
    w.document.write(html); w.document.close();
    setTimeout(function () { try { w.print(); } catch (e) {} }, 250);
  }

  $('#q').addEventListener('input', function () { q = this.value; renderLabels(); });
  $('#lFilter').addEventListener('change', function () { filter = this.value; rpc('app_label_list', { p_token: token, p_type: filter || null, p_q: null }).then(function (r) { labels = r || []; renderLabels(); }); });

  $('#pSave').addEventListener('click', function () {
    rpc('app_package_save', { p_token: token, p_id: curP ? curP.id : null, p_order_id: $('#pOrder').value || null,
      p_package_no: parseInt($('#pNo').value, 10) || 1, p_kind: $('#pKind').value, p_dims: $('#pDims').value,
      p_gross: parseFloat($('#pGross').value) || 0, p_net: parseFloat($('#pNet').value) || 0,
      p_positions: parseInt($('#pPos').value, 10) || 0, p_marks: $('#pMarks').value, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#pMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); curP = null; load(); })
      .catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#pClear').addEventListener('click', function () { curP = null; msg('#pMsg', ''); });

  $('#lSave').addEventListener('click', function () {
    rpc('app_label_save', { p_token: token, p_id: curL ? curL.id : null, p_order_id: $('#lOrder').value || null,
      p_package_id: $('#lPackage').value || null, p_label_type: $('#lType').value, p_recipient: $('#lRecipient').value,
      p_sender: $('#lSender').value, p_item: $('#lItem').value, p_qty: parseFloat($('#lQty').value) || 0, p_dims: $('#lDims').value,
      p_gross: parseFloat($('#lGross').value) || 0, p_net: parseFloat($('#lNet').value) || 0,
      p_position_no: parseInt($('#lPos').value, 10) || null, p_identifier: $('#lIdent').value,
      p_cargo_no: parseInt($('#lCargoNo').value, 10) || null, p_cargo_total: parseInt($('#lCargoTotal').value, 10) || null, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#lMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); curL = null; load(); })
      .catch(function (e) { msg('#lMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#lClear').addEventListener('click', function () { curL = null; msg('#lMsg', ''); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#pMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
