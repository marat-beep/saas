/* ============================================================
   3DMP Service · apps/equipment — A11 каталог оборудования. Данные: 0083.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], cur = null, q = '', cat = '';

  var CAT = { cnc: 'ЧПУ', lathe: 'Токарные', edm: 'ЭЭО', grinding: 'Шлифование', press: 'Прессы', measuring: 'Измерения', other: 'Прочее' };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function money(v) { return (v == null ? 0 : Number(v)).toLocaleString('ru-RU') + ' ₽'; }

  function load() {
    return Promise.all([
      rpc('app_equipment_catalog_list', { p_token: token, p_category: cat || null, p_q: null }),
      rpc('app_equipment_kpi', { p_token: token })
    ]).then(function (r) {
      list = r[0] || [];
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Позиций', k.total || 0) + cell('Активных', k.active || 0) + cell('Типов', k.categories || 0) + cell('Цена от', money(k.price_min)) + cell('Цена до', money(k.price_max));
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (e) { return !s || [(e.name || ''), (e.brand || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (e) {
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + esc(CAT[e.category] || e.category || '—') + '</span><b>' + esc(e.name) + '</b>' +
        '<span class="note">' + esc(e.brand || '') + (e.axes ? ' · ' + e.axes + ' ос.' : '') + (e.accuracy ? ' · ' + esc(e.accuracy) : '') + '</span>' +
        '<span class="note" style="margin-left:auto;">' + money(e.price) + '</span></div>' +
        (e.description ? '<div class="note mt">' + esc(e.description) + '</div>' : '') +
        '<div class="toolbar mt"><button class="btn secondary" data-edit="' + e.id + '" style="width:auto;padding:7px 12px;">Править</button>' +
        '<button class="btn secondary" data-del="' + e.id + '" style="width:auto;padding:7px 12px;">Удалить</button></div></div>';
    }).join('') : '<span class="note">Позиций нет.</span>';
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { edit(b.dataset.edit); }); });
    $$('#list [data-del]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_equipment_delete', { p_token: token, p_id: b.dataset.del }).then(load); }); });
  }

  function edit(id) {
    cur = list.filter(function (x) { return x.id === id; })[0]; if (!cur) return;
    $('#fName').value = cur.name || ''; $('#fBrand').value = cur.brand || ''; $('#fCat').value = cur.category || 'cnc';
    $('#fAxes').value = cur.axes || 0; $('#fAcc').value = cur.accuracy || ''; $('#fPrice').value = cur.price || 0; $('#fDescr').value = cur.description || '';
    window.scrollTo(0, 0);
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#qCat').addEventListener('change', function () { cat = this.value; load(); });
  $('#fClear').addEventListener('click', function () { cur = null; ['fName', 'fBrand', 'fAcc', 'fDescr'].forEach(function (i) { $('#' + i).value = ''; }); msg('#fMsg', ''); });
  $('#fSave').addEventListener('click', function () {
    rpc('app_equipment_catalog_save', { p_token: token, p_id: cur ? cur.id : null, p_name: $('#fName').value, p_brand: $('#fBrand').value,
      p_category: $('#fCat').value, p_axes: parseInt($('#fAxes').value, 10) || null, p_accuracy: $('#fAcc').value,
      p_price: parseFloat($('#fPrice').value) || 0, p_description: $('#fDescr').value, p_active: true })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('Оборудование', $('#fName').value); cur = null; load(); })
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
