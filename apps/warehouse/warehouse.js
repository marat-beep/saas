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
