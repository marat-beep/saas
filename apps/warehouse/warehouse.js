/* ============================================================
   3DMP Service · apps/warehouse — Склад (остатки/движения/нехватка)
   Данные: 0010+0036. Нехватка → закупка. Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, mats = [], orders = [], low = [], cur = null, editId = null, filter = '', q = '';

  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return num(v).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return Promise.all([
      rpc('app_material_list', { p_token: token }),
      rpc('app_stock_low', { p_token: token }).catch(function () { return []; }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      mats = r[0] || []; low = r[1] || []; orders = r[2] || [];
      $('#mvOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + '</option>'; }).join('');
      renderKpi(); renderLow(); render();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    var val = mats.reduce(function (s, m) { return s + num(m.stock_value); }, 0);
    $('#kpis').innerHTML = cell('Позиций', mats.length) + cell('Ниже минимума', low.length, low.length ? '#b91c1c' : '') + cell('Стоимость запаса', money(val));
    function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }
  }
  function renderLow() {
    if (!low.length) { $('#lowCard').style.display = 'none'; return; }
    $('#lowCard').style.display = '';
    $('#low').innerHTML = low.map(function (m) {
      return '<div class="ocard" data-mk="' + m.id + '"><div style="display:flex;gap:8px;align-items:center;">' +
        '<span class="badge cancelled">нехватка ' + num(m.deficit) + ' ' + esc(m.unit || '') + '</span>' +
        '<b>' + esc(m.name) + '</b><span class="note" style="margin-left:auto;">остаток ' + num(m.qty) + ' / мин ' + num(m.min_qty) + '</span></div>' +
        '<div class="toolbar mt"><button class="btn secondary" data-tender="' + m.id + '" style="width:auto;padding:8px 14px;">Создать закупку</button></div></div>';
    }).join('');
    $$('#low [data-tender]').forEach(function (b) {
      b.addEventListener('click', function (e) { e.stopPropagation(); createTender(b.dataset.tender); });
    });
  }
  function filtered() {
    var s = q.toLowerCase();
    return mats.filter(function (m) {
      if (filter === 'low' && !m.low) return false;
      if (!s) return true;
      return [m.code, m.name].join(' ').toLowerCase().indexOf(s) >= 0;
    });
  }
  function render() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Материалов нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (m) {
      return '<div class="ocard' + (m.low ? ' low' : '') + '" data-id="' + m.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;">' +
        '<b style="font-size:.94rem;">' + esc(m.name) + '</b>' +
        '<span class="badge ' + (m.low ? 'cancelled' : 'done') + '" style="margin-left:auto;">' + (m.low ? 'ниже минимума' : 'норма') + '</span></div>' +
        '<div style="font-size:.78rem;color:var(--muted);margin-top:5px;">' +
        (m.code ? esc(m.code) + ' · ' : '') + 'остаток: ' + num(m.qty) + ' ' + esc(m.unit || '') +
        ' · мин: ' + num(m.min_qty) + ' · ' + money(m.price) + ' · запас ' + money(m.stock_value) + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function openItem(id) {
    cur = mats.filter(function (m) { return m.id === id; })[0]; if (!cur) return;
    $('#material').innerHTML =
      '<div style="display:flex;gap:8px;align-items:center;">' +
      '<b style="font-size:.94rem;">' + esc(cur.name) + '</b>' +
      '<span class="badge ' + (cur.low ? 'cancelled' : 'done') + '" style="margin-left:auto;">' + (cur.low ? 'ниже минимума' : 'норма') + '</span></div>' +
      kv('Код', cur.code) + kv('Остаток', num(cur.qty) + ' ' + (cur.unit || '')) +
      kv('Минимум', num(cur.min_qty) + ' ' + (cur.unit || '')) + kv('Цена', money(cur.price)) + kv('Стоимость запаса', money(cur.stock_value)) +
      (cur.low ? '<div class="toolbar mt"><button class="btn secondary" id="mkTender" style="width:auto;padding:9px 14px;">Создать закупку по нехватке</button></div>' : '');
    var b = $('#mkTender'); if (b) b.addEventListener('click', function () { createTender(cur.id); });
    $('#mvKind').value = 'in'; $('#mvQty').value = ''; $('#mvNote').value = ''; $('#mvOrder').value = '';
    clearMsg('#mvMsg');
    loadMoves();
    screens.go('s-item');
  }
  function loadMoves() {
    rpc('app_stock_moves_list', { p_token: token, p_material_id: cur.id, p_limit: 30 }).then(function (list) {
      list = list || [];
      $('#moves').innerHTML = list.length ? list.map(function (v) {
        return '<div class="kvr"><span class="badge ' + (v.kind === 'in' ? 'done' : 'cancelled') + '">' + (v.kind === 'in' ? 'приход' : 'расход') + '</span>' +
          '<b>' + num(v.qty) + ' ' + esc(cur.unit || '') + '</b>' +
          (v.order_number ? '<span class="note">📥 ' + esc(v.order_number) + '</span>' : '') +
          (v.naryad_number ? '<span class="note">🏭 ' + esc(v.naryad_number) + '</span>' : '') +
          '<span class="note" style="margin-left:auto;">' + fmt(v.created_at) + ' · ' + esc(v.by_login || '') + (v.note ? ' · ' + esc(v.note) : '') + '</span></div>';
      }).join('') : '<span class="note">Движений нет.</span>';
    });
  }
  function createTender(mid) {
    var m = mats.filter(function (x) { return x.id === mid; })[0]; if (!m) return;
    var def = Math.max(num(m.min_qty) - num(m.qty), 0) || 1;
    rpc('app_tender_create', {
      p_token: token, p_title: 'Закупка: ' + m.name, p_description: 'Нехватка по складу (минимум ' + num(m.min_qty) + ' ' + (m.unit || '') + ')',
      p_category: 'Материалы', p_material: m.name, p_qty: def, p_unit: m.unit || '', p_customer: null,
      p_deadline: null, p_order_id: null, p_assignee: null
    }).then(function (d) {
      var r = d && d[0]; if (!r) { msg('#listMsg', 'Ошибка создания закупки', 'err'); return; }
      window.Auth.log('Закупка по нехватке', m.name); ui.toast('Закупка создана: ' + r.message);
      screens.go('s-list'); load();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- WMS: адреса, партии, остатки по адресам ---------- */
  var addrs = [], stock = [];
  function loadWms() {
    return Promise.all([
      rpc('app_wh_address_list', { p_token: token }),
      rpc('app_wh_stock_list', { p_token: token, p_material_id: $('#stMat').value || null, p_location_id: $('#stAddr').value || null }),
      rpc('app_wh_kpi', { p_token: token })
    ]).then(function (r) {
      addrs = r[0] || []; stock = r[1] || []; var k = (r[2] || [])[0] || {};
      var matOpts = '<option value="">— все —</option>' + mats.map(function (m) { return '<option value="' + m.id + '">' + esc(m.name) + '</option>'; }).join('');
      var lv = $('#stMat').value; $('#stMat').innerHTML = matOpts; $('#stMat').value = lv;
      $('#lotMat').innerHTML = '<option value="">— выберите материал —</option>' + mats.map(function (m) { return '<option value="' + m.id + '">' + esc(m.name) + '</option>'; }).join('');
      var addrOpts = '<option value="">— все —</option>' + addrs.map(function (a) { return '<option value="' + a.id + '">' + esc(a.code) + '</option>'; }).join('');
      var av = $('#stAddr').value; $('#stAddr').innerHTML = addrOpts; $('#stAddr').value = av;
      $('#wmsKpis').innerHTML = cell('Адресов', k.addresses || 0) + cell('Партий', k.lots || 0) + cell('Позиций', k.positions || 0) +
        cell('Кол-во', num(k.total_qty)) + cell('Стоимость', money(k.total_value));
      renderAddr(); renderStock();
    }).catch(function (e) { msg('#wmsMsg', 'Ошибка: ' + e.message, 'err'); });
    function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }
  }
  function addrLabel(a) { return a.code + (a.zone || a.rack || a.cell ? ' (' + [a.zone, a.rack, a.cell].filter(Boolean).join('/') + ')' : ''); }
  function renderAddr() {
    $('#addrList').innerHTML = addrs.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Код</th><th>Зона/стеллаж/ячейка</th><th class="num">Позиций</th><th class="num">Кол-во</th><th></th></tr></thead><tbody>' +
      addrs.map(function (a) { return '<tr><td><b>' + esc(a.code) + '</b></td><td class="muted">' + esc([a.zone, a.rack, a.cell].filter(Boolean).join(' / ')) + '</td>' +
        '<td class="num">' + a.positions + '</td><td class="num">' + num(a.qty) + '</td>' +
        '<td><button class="act danger" data-adel="' + a.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Адресов нет.</span>';
    $$('#addrList [data-adel]').forEach(function (b) {
      b.addEventListener('click', function () {
        if (!window.confirm('Удалить адрес?')) return;
        rpc('app_wh_address_delete', { p_token: token, p_id: b.dataset.adel }).then(function (r) { var x = r && r[0]; msg('#wmsMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadWms(); }).catch(function (e) { msg('#wmsMsg', 'Ошибка: ' + e.message, 'err'); });
      });
    });
  }
  function renderStock() {
    $('#stockList').innerHTML = stock.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Адрес</th><th>Материал</th><th>Партия</th><th class="num">Кол-во</th><th class="num">Стоимость</th><th></th></tr></thead><tbody>' +
      stock.map(function (s) { return '<tr><td>' + esc(s.address) + '</td><td>' + esc(s.material) + '</td><td class="muted">' + esc(s.lot || '—') + '</td>' +
        '<td class="num">' + num(s.qty) + ' ' + esc(s.unit || '') + '</td><td class="num">' + money(s.value) + '</td>' +
        '<td style="white-space:nowrap;"><button class="act" data-mv="' + s.id + '">Переместить</button><button class="act danger" data-out="' + s.id + '">Списать</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Остатков на адресах нет.</span>';
    $$('#stockList [data-mv]').forEach(function (b) {
      b.addEventListener('click', function () { moveForm(stock.filter(function (s) { return s.id === b.dataset.mv; })[0]); });
    });
    $$('#stockList [data-out]').forEach(function (b) {
      b.addEventListener('click', function () {
        var s = stock.filter(function (x) { return x.id === b.dataset.out; })[0]; if (!s) return;
        ui.formDialog({ title: 'Списание', okText: 'Списать', fields: [{ name: 'qty', label: 'Количество (до ' + num(s.qty) + ')', type: 'text', required: true, value: String(num(s.qty)) }] })
          .then(function (v) { if (!v) return; var q = parseFloat(String(v.qty).replace(',', '.')); if (isNaN(q) || q <= 0) { msg('#wmsMsg', 'Некорректное количество', 'err'); return; }
            rpc('app_wh_stock_out', { p_token: token, p_stock_id: s.id, p_qty: q }).then(function (r) { var x = r && r[0]; msg('#wmsMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) window.Auth.log('Списание с адреса', s.material + ' ' + q); loadWms(); }); });
      });
    });
  }
  function moveForm(s) {
    if (!s) return;
    var opts = addrs.filter(function (a) { return a.id !== s.location_id; }).map(function (a) { return { value: a.id, label: addrLabel(a) }; });
    if (!opts.length) { msg('#wmsMsg', 'Нет других адресов', 'err'); return; }
    ui.formDialog({
      title: 'Перемещение', okText: 'Переместить',
      fields: [{ name: 'to', label: 'Адрес назначения', type: 'select', options: opts }, { name: 'qty', label: 'Количество (до ' + num(s.qty) + ')', type: 'text', required: true, value: String(num(s.qty)) }]
    }).then(function (v) { if (!v) return; var q = parseFloat(String(v.qty).replace(',', '.')); if (isNaN(q) || q <= 0) { msg('#wmsMsg', 'Некорректное количество', 'err'); return; }
      rpc('app_wh_move', { p_token: token, p_stock_id: s.id, p_to_location_id: v.to, p_qty: q }).then(function (r) { var x = r && r[0]; msg('#wmsMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) window.Auth.log('Перемещение', s.material + ' ' + q); loadWms(); }); });
  }
  function loadLots() {
    var mid = $('#lotMat').value; if (!mid) { $('#lotList').innerHTML = '<span class="note">Выберите материал.</span>'; return; }
    rpc('app_material_lot_list', { p_token: token, p_material_id: mid }).then(function (ls) {
      ls = ls || [];
      $('#lotList').innerHTML = ls.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Партия</th><th>Поставщик</th><th class="num">Принято</th><th class="num">На адресах</th><th class="num">Цена</th><th>Дата</th></tr></thead><tbody>' +
        ls.map(function (l) { return '<tr><td><b>' + esc(l.lot) + '</b></td><td class="muted">' + esc(l.supplier || '—') + '</td><td class="num">' + num(l.qty) + ' ' + esc(l.unit || '') + '</td><td class="num">' + num(l.stock_qty) + '</td><td class="num">' + money(l.price) + '</td><td class="muted">' + fmt(l.created_at) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Партий нет.</span>';
    }).catch(function (e) { msg('#wmsMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  $('#toWms').addEventListener('click', function () { loadWms(); screens.go('s-wms'); });
  $('#addrAdd').addEventListener('click', function () {
    ui.formDialog({ title: 'Новый адрес', okText: 'Сохранить', fields: [
      { name: 'code', label: 'Код', type: 'text', required: true, placeholder: 'A-01-01' },
      { name: 'zone', label: 'Зона', type: 'text', placeholder: 'Зона A' },
      { name: 'rack', label: 'Стеллаж', type: 'text', placeholder: 'Стеллаж 1' },
      { name: 'cell', label: 'Ячейка', type: 'text', placeholder: 'Ячейка 1' }
    ] }).then(function (v) { if (!v) return;
      rpc('app_wh_address_save', { p_token: token, p_id: null, p_code: v.code, p_zone: v.zone, p_rack: v.rack, p_cell: v.cell, p_active: true })
        .then(function (r) { var x = r && r[0]; msg('#wmsMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { window.Auth.log('Адрес склада', v.code); loadWms(); } }); });
  });
  $('#placeBtn').addEventListener('click', function () {
    if (!mats.length) { msg('#wmsMsg', 'Нет материалов', 'err'); return; }
    if (!addrs.length) { msg('#wmsMsg', 'Сначала создайте адрес', 'err'); return; }
    ui.formDialog({ title: 'Размещение на адрес', okText: 'Разместить', size: 'lg', fields: [
      { name: 'material', label: 'Материал', type: 'select', options: mats.map(function (m) { return { value: m.id, label: m.name }; }) },
      { name: 'address', label: 'Адрес', type: 'select', options: addrs.map(function (a) { return { value: a.id, label: addrLabel(a) }; }) },
      { name: 'lot', label: 'Партия', type: 'text', placeholder: 'L-2601', hint: 'Новая или существующая партия.' },
      { name: 'qty', label: 'Количество', type: 'text', required: true },
      { name: 'price', label: 'Цена', type: 'text' },
      { name: 'supplier', label: 'Поставщик', type: 'text' }
    ] }).then(function (v) { if (!v) return; var q = parseFloat(String(v.qty).replace(',', '.')); var pr = parseFloat(String(v.price || '').replace(',', '.'));
      if (isNaN(q) || q <= 0) { msg('#wmsMsg', 'Некорректное количество', 'err'); return; }
      rpc('app_wh_place', { p_token: token, p_material_id: v.material, p_location_id: v.address, p_lot: v.lot, p_qty: q, p_price: isNaN(pr) ? 0 : pr, p_supplier: v.supplier })
        .then(function (r) { var x = r && r[0]; msg('#wmsMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { window.Auth.log('Размещение', v.lot || v.material); loadWms(); } }); });
  });
  $('#stMat').addEventListener('change', loadWms);
  $('#stAddr').addEventListener('change', loadWms);
  $('#lotMat').addEventListener('change', loadLots);
  $('#back3').addEventListener('click', function () { load(); screens.go('s-list'); });

  $('#toForm').addEventListener('click', function () { editId = null; $('#formTitle').textContent = 'Новый материал'; ['#mName', '#mCode', '#mUnit', '#mPrice', '#mMin'].forEach(function (s) { $(s).value = ''; }); clearMsg('#fMsg'); screens.go('s-form'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; render();
  });
  $('#q').addEventListener('input', function () { q = this.value; render(); });

  $('#saveMat').addEventListener('click', function () {
    var name = $('#mName').value.trim();
    if (!name) { msg('#fMsg', 'Укажите наименование.', 'err'); return; }
    var price = parseFloat(($('#mPrice').value || '').replace(',', '.'));
    var minq = parseFloat(($('#mMin').value || '').replace(',', '.'));
    rpc('app_material_save', { p_token: token, p_id: editId, p_code: $('#mCode').value.trim(), p_name: name,
      p_unit: $('#mUnit').value.trim(), p_price: isNaN(price) ? 0 : price, p_min_qty: isNaN(minq) ? 0 : minq })
      .then(function (d) { var r = d && d[0]; if (!r || !r.ok) { msg('#fMsg', (r && r.message) || 'Ошибка', 'err'); return; }
        window.Auth.log('Материал', name); ui.toast('Сохранено'); load().then(function () { screens.go('s-list'); }); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#mvBtn').addEventListener('click', function () {
    if (!cur) return;
    var qv = parseFloat(($('#mvQty').value || '').replace(',', '.'));
    if (!qv || qv <= 0) { msg('#mvMsg', 'Укажите количество > 0.', 'err'); return; }
    rpc('app_stock_move', { p_token: token, p_material_id: cur.id, p_kind: $('#mvKind').value, p_qty: qv, p_price: 0,
      p_note: $('#mvNote').value.trim(), p_source: 'manual', p_order_id: $('#mvOrder').value || null, p_naryad_id: null })
      .then(function (d) { var r = d && d[0]; if (!r || !r.ok) { msg('#mvMsg', (r && r.message) || 'Ошибка', 'err'); return; }
        window.Auth.log('Движение склада', cur.name + ' ' + $('#mvKind').value + ' ' + qv);
        if (window.AppNotify) window.AppNotify.refresh(true);
        ui.toast('Движение проведено'); $('#mvQty').value = '';
        load().then(function () { openItem(cur.id); }); })
      .catch(function (e) { msg('#mvMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
