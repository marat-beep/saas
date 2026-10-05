/* ============================================================
   3DMP Service · apps/passport — паспорт изделия + QR
   Данные: app_passport_* (0012_quality.sql). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, items = [], orders = [], qcs = [], cur = null;

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
      rpc('app_qc_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      items = r[0] || []; orders = r[1] || []; qcs = r[2] || [];
      $('#pOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      $('#pQc').innerHTML = '<option value="">— нет —</option>' + qcs.map(function (q) { return '<option value="' + q.id + '">' + esc(q.number) + ' · ' + esc(q.product || '') + '</option>'; }).join('');
      render();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function render() {
    if (!items.length) { $('#list').innerHTML = '<span class="note">Паспортов нет.</span>'; return; }
    $('#list').innerHTML = items.map(function (p) {
      return '<div class="pcard" data-id="' + p.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;"><b style="font-size:.94rem;">' + esc(p.product) + '</b>' +
        '<span class="note" style="margin-left:auto;">' + esc(p.number) + '</span></div>' +
        '<div style="font-size:.78rem;color:var(--muted);margin-top:5px;">' + (p.order_number ? '📥 ' + esc(p.order_number) + ' · ' : '') + fmt(p.created_at) + '</div></div>';
    }).join('');
    $$('#list .pcard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function openItem(id) {
    rpc('app_passport_get', { p_token: token, p_id: id }).then(function (r) {
      var p = r && r[0]; if (!p) { ui.toast('Паспорт не найден'); return; }
      cur = p;
      var data = p.data || {};
      $('#passport').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;"><b style="font-size:.94rem;">' + esc(p.product) + '</b>' +
        '<span class="note" style="margin-left:auto;">' + esc(p.number) + '</span></div>' +
        kv('Заявка', p.order_number) + kv('Материал', data.material) + kv('Примечание', data.note) +
        kv('Оформил', p.created_login) + kv('Создан', fmt(p.created_at));
      var link = location.origin + location.pathname + '?id=' + p.id;
      $('#qrText').textContent = p.number + ' · ' + link;
      var box = $('#qr'); box.innerHTML = '';
      try {
        if (window.QRCode) { new QRCode(box, { text: link, width: 160, height: 160 }); }
        else { box.innerHTML = '<span class="note">QR-библиотека не загрузилась</span>'; }
      } catch (e) { box.innerHTML = '<span class="note">QR недоступен</span>'; }
      screens.go('s-item');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }

  $('#toNew').addEventListener('click', function () { clearMsg('#nMsg'); screens.go('s-new'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  $('#createBtn').addEventListener('click', function () {
    var product = $('#pProduct').value.trim();
    if (!product) { msg('#nMsg', 'Укажите изделие.', 'err'); return; }
    var data = { material: $('#pMaterial').value.trim(), note: $('#pNote').value.trim() };
    rpc('app_passport_create', { p_token: token, p_order_id: $('#pOrder').value || null, p_product: product, p_qc_check_id: $('#pQc').value || null, p_data: data })
      .then(function (d) { var row = d && d[0]; if (!row) { msg('#nMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('Паспорт', row.number); ui.toast('Паспорт ' + row.number + ' создан');
        ['#pProduct', '#pMaterial', '#pNote'].forEach(function (s) { $(s).value = ''; });
        load().then(function () { openItem(row.id); }); })
      .catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  // открыть по ссылке ?id=
  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load().then(function () {
      var q = new URLSearchParams(location.search).get('id');
      if (q) openItem(q);
    });
  });
})();
