/* ============================================================
   3DMP Service · apps/warehouse — склад материалов
   Данные: app_material_*, app_stock_* (0010_warehouse.sql). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, mats = [], cur = null, editId = null;

  function esc(v) { return ui.esc(v); }
  function num(v) { return (Number(v) || 0); }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return rpc('app_material_list', { p_token: token }).then(function (d) { mats = d || []; render(); })
      .catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function render() {
    if (!mats.length) { $('#list').innerHTML = '<span class="note">Материалов нет.</span>'; return; }
    $('#list').innerHTML = mats.map(function (m) {
      return '<div class="mcard' + (m.low ? ' low' : '') + '" data-id="' + m.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;">' +
        '<b style="font-size:.94rem;">' + esc(m.name) + '</b>' +
        '<span class="b ' + (m.low ? 'low' : 'ok') + '" style="margin-left:auto;">' + (m.low ? 'ниже минимума' : 'норма') + '</span></div>' +
        '<div style="font-size:.78rem;color:var(--muted);margin-top:5px;">' +
        (m.code ? esc(m.code) + ' · ' : '') + 'остаток: ' + num(m.qty) + ' ' + esc(m.unit || '') +
        ' · мин: ' + num(m.min_qty) + ' · ' + num(m.price) + ' ₽</div></div>';
    }).join('');
    $$('#list .mcard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function openItem(id) {
    cur = mats.filter(function (m) { return m.id === id; })[0]; if (!cur) return;
    $('#material').innerHTML =
      '<div style="display:flex;gap:8px;align-items:center;">' +
      '<b style="font-size:.94rem;">' + esc(cur.name) + '</b>' +
      (cur.low ? '<span class="b low" style="margin-left:auto;">ниже минимума</span>' : '<span class="b ok" style="margin-left:auto;">норма</span>') + '</div>' +
      kv('Код', cur.code) + kv('Остаток', num(cur.qty) + ' ' + (cur.unit || '')) +
      kv('Минимум', num(cur.min_qty) + ' ' + (cur.unit || '')) + kv('Цена', num(cur.price) + ' ₽');
    $('#mvKind').value = 'in'; $('#mvQty').value = ''; $('#mvNote').value = '';
    clearMsg('#mvMsg');
    loadMoves();
    screens.go('s-item');
  }
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }

  function loadMoves() {
    rpc('app_stock_moves_list', { p_token: token, p_material_id: cur.id, p_limit: 30 }).then(function (list) {
      list = list || [];
      if (!list.length) { $('#moves').innerHTML = '<span class="note">Движений нет.</span>'; return; }
      $('#moves').innerHTML = list.map(function (v) {
        return '<div class="kvr"><span class="b ' + v.kind + '">' + (v.kind === 'in' ? 'приход' : 'расход') + '</span>' +
          '<b>' + num(v.qty) + ' ' + esc(cur.unit || '') + '</b>' +
          '<span class="note" style="margin-left:auto;">' + fmt(v.created_at) + ' · ' + esc(v.by_login || '') + (v.note ? ' · ' + esc(v.note) : '') + '</span></div>';
      }).join('');
    });
  }

  $('#toForm').addEventListener('click', function () { editId = null; $('#formTitle').textContent = 'Новый материал'; ['#mName', '#mCode', '#mUnit', '#mPrice', '#mMin'].forEach(function (s) { $(s).value = ''; }); clearMsg('#fMsg'); screens.go('s-form'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  $('#saveMat').addEventListener('click', function () {
    var name = $('#mName').value.trim();
    if (!name) { msg('#fMsg', 'Укажите наименование.', 'err'); return; }
    var price = parseFloat($('#mPrice').value.replace(',', '.'));
    var minq = parseFloat($('#mMin').value.replace(',', '.'));
    rpc('app_material_save', { p_token: token, p_id: editId, p_code: $('#mCode').value.trim(), p_name: name,
      p_unit: $('#mUnit').value.trim(), p_price: isNaN(price) ? 0 : price, p_min_qty: isNaN(minq) ? 0 : minq })
      .then(function (d) { var r = d && d[0]; if (!r || !r.ok) { msg('#fMsg', (r && r.message) || 'Ошибка', 'err'); return; }
        window.Auth.log('Материал', name); ui.toast('Сохранено'); load().then(function () { screens.go('s-list'); }); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#mvBtn').addEventListener('click', function () {
    if (!cur) return;
    var q = parseFloat($('#mvQty').value.replace(',', '.'));
    if (!q || q <= 0) { msg('#mvMsg', 'Укажите количество > 0.', 'err'); return; }
    rpc('app_stock_move', { p_token: token, p_material_id: cur.id, p_kind: $('#mvKind').value, p_qty: q, p_price: 0, p_note: $('#mvNote').value.trim(), p_source: 'manual' })
      .then(function (d) { var r = d && d[0]; if (!r || !r.ok) { msg('#mvMsg', (r && r.message) || 'Ошибка', 'err'); return; }
        window.Auth.log('Движение склада', cur.name + ' ' + $('#mvKind').value + ' ' + q);
        if (window.AppNotify) window.AppNotify.refresh(true);
        ui.toast('Движение проведено'); $('#mvQty').value = '';
        load().then(function () { openItem(cur.id); }); })
      .catch(function (e) { msg('#mvMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (['admin', 'owner', 'manager'].indexOf(s.role) < 0) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
