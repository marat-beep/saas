/* ============================================================
   3DMP Service · apps/passport — Паспорт изделия + QR + трассируемость
   Данные: 0012+0038. Трассируемость — app_qc_trace (по чек-листу ОТК).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, items = [], orders = [], naryads = [], qcs = [], cur = null, qstr = '';

  function esc(v) { return ui.esc(v); }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return Promise.all([
      rpc('app_passport_list', { p_token: token }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_naryad_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_qc_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      items = r[0] || []; orders = r[1] || []; naryads = r[2] || []; qcs = r[3] || [];
      $('#pOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      $('#pNaryad').innerHTML = '<option value="">— нет —</option>' + naryads.map(function (n) { return '<option value="' + n.id + '">' + esc(n.number) + ' · ' + esc(n.title) + '</option>'; }).join('');
      $('#pQc').innerHTML = '<option value="">— нет —</option>' + qcs.map(function (q) { return '<option value="' + q.id + '">' + esc(q.number) + ' · ' + esc(q.product || '') + '</option>'; }).join('');
      renderKpi(); render();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    $('#kpis').innerHTML = cell('Паспортов', items.length) +
      cell('С серийным №', items.filter(function (p) { return p.serial; }).length) +
      cell('С ОТК', items.filter(function (p) { return p.qc_check_id; }).length);
    function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  }
  function filtered() {
    var s = qstr.toLowerCase();
    return items.filter(function (p) {
      if (!s) return true;
      return [p.number, p.product, p.serial, p.order_number, p.naryad_number, p.qc_number].join(' ').toLowerCase().indexOf(s) >= 0;
    });
  }
  function render() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Паспортов нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (p) {
      return '<div class="ocard" data-id="' + p.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;"><b style="font-size:.94rem;">' + esc(p.product) + '</b>' +
        (p.serial ? '<span class="badge">SN ' + esc(p.serial) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + esc(p.number) + '</span></div>' +
        '<div style="font-size:.78rem;color:var(--muted);margin-top:5px;">' +
        (p.order_number ? '📥 ' + esc(p.order_number) + ' · ' : '') + (p.naryad_number ? '🏭 ' + esc(p.naryad_number) + ' · ' : '') +
        (p.qc_number ? '✅ ' + esc(p.qc_number) + ' · ' : '') + fmt(p.created_at) + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function openItem(id) {
    rpc('app_passport_get', { p_token: token, p_id: id }).then(function (r) {
      var p = r && r[0]; if (!p) { ui.toast('Паспорт не найден'); return; }
      cur = p; var data = p.data || {};
      $('#passport').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;"><b style="font-size:.94rem;">' + esc(p.product) + '</b>' +
        '<span class="badge done" style="margin-left:auto;">' + esc(p.number) + '</span></div>' +
        (p.serial ? kv('Серийный номер', p.serial) : '') + (p.qty != null ? kv('Количество', String(p.qty)) : '') +
        kv('Заявка', p.order_number) + kv('Наряд', p.naryad_number) + kv('Чек-лист ОТК', p.qc_number) +
        kv('Материал', data.material) + kv('Примечание', data.note) +
        kv('Оформил', p.created_login) + kv('Создан', fmt(p.created_at));
      var link = location.origin + location.pathname + '?id=' + p.id;
      $('#qrText').textContent = p.number + ' · ' + link;
      var box = $('#qr'); box.innerHTML = '';
      try { if (window.QRCode) new QRCode(box, { text: link, width: 160, height: 160 }); else box.innerHTML = '<span class="note">QR-библиотека не загрузилась</span>'; }
      catch (e) { box.innerHTML = '<span class="note">QR недоступен</span>'; }
      loadTrace(p.qc_check_id);
      if (window.AppFiles) window.AppFiles.mount({ token: token, entityType: 'passport', entityId: p.id, el: '#filesBox' });
      screens.go('s-item');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function loadTrace(qcId) {
    if (!qcId) { $('#trace').innerHTML = '<span class="note">Нет чек-листа ОТК — трассируемость недоступна.</span>'; return; }
    rpc('app_qc_trace', { p_token: token, p_check_id: qcId }).then(function (rows) {
      rows = rows || [];
      $('#trace').innerHTML = rows.length ? rows.map(function (r) {
        return '<div class="kvr"><span class="badge">' + esc(r.kind) + '</span><b>' + esc(r.title || '') + '</b>' +
          (r.detail ? '<span class="note">' + esc(r.detail) + '</span>' : '') + '<span class="note" style="margin-left:auto;">' + fmt(r.ts) + '</span></div>';
      }).join('') : '<span class="note">Связей не найдено.</span>';
    }).catch(function () { $('#trace').innerHTML = '<span class="note">Трассируемость недоступна.</span>'; });
  }

  $('#toNew').addEventListener('click', function () { clearMsg('#nMsg'); screens.go('s-new'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  $('#q').addEventListener('input', function () { qstr = this.value; render(); });

  $('#createBtn').addEventListener('click', function () {
    var product = $('#pProduct').value.trim();
    if (!product) { msg('#nMsg', 'Укажите изделие.', 'err'); return; }
    var data = { material: $('#pMaterial').value.trim(), note: $('#pNote').value.trim() };
    var qty = parseFloat(($('#pQty').value || '').replace(',', '.'));
    rpc('app_passport_create', { p_token: token, p_order_id: $('#pOrder').value || null, p_product: product,
      p_qc_check_id: $('#pQc').value || null, p_data: data, p_naryad_id: $('#pNaryad').value || null,
      p_serial: $('#pSerial').value.trim(), p_qty: isNaN(qty) ? null : qty })
      .then(function (d) { var row = d && d[0]; if (!row) { msg('#nMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('Паспорт', row.number); ui.toast('Паспорт ' + row.number + ' создан');
        if (window.AppNotify) window.AppNotify.refresh(true);
        ['#pProduct', '#pMaterial', '#pNote', '#pSerial', '#pQty'].forEach(function (s) { $(s).value = ''; });
        load().then(function () { openItem(row.id); }); })
      .catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load().then(function () { var q = new URLSearchParams(location.search).get('id'); if (q) openItem(q); });
  });
})();
