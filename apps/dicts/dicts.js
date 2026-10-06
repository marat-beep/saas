/* ============================================================
   3DMP Service · apps/dicts — настраиваемые справочники. Данные: 0080.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, dicts = [], items = [], cur = null, q = '';

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_dicts_list', { p_token: token, p_q: null }),
      rpc('app_dicts_kpi', { p_token: token })
    ]).then(function (r) {
      dicts = r[0] || [];
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Справочников', k.dicts || 0) + cell('Значений', k.items || 0) + cell('Активных', k.active_items || 0);
      renderDicts();
    }).catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderDicts() {
    var s = q.toLowerCase();
    var rows = dicts.filter(function (d) { return !s || (d.name + ' ' + d.code).toLowerCase().indexOf(s) >= 0; });
    $('#dList').innerHTML = rows.length ? rows.map(function (d) {
      return '<div class="ocard" data-open="' + d.id + '"><div style="display:flex;gap:8px;align-items:center;"><b>' + esc(d.name) + '</b>' +
        '<span class="badge">' + esc(d.code) + '</span><span class="note" style="margin-left:auto;">' + d.items + ' знач.</span></div></div>';
    }).join('') : '<span class="note">Справочников нет.</span>';
    $$('#dList [data-open]').forEach(function (b) { b.addEventListener('click', function () { open(b.dataset.open); }); });
  }

  function open(id) {
    cur = dicts.filter(function (d) { return d.id === id; })[0]; if (!cur) return;
    $('#itemsCard').style.display = 'block'; $('#emptyCard').style.display = 'none';
    $('#dTitle').textContent = cur.name + ' · ' + cur.code;
    rpc('app_dict_items_list', { p_token: token, p_dict_id: id }).then(function (r) { items = r || []; renderItems(); });
  }

  function renderItems() {
    $('#iList').innerHTML = items.length ? '<table class="mini"><thead><tr><th>Значение</th><th>Название</th><th>Порядок</th><th></th></tr></thead><tbody>' +
      items.map(function (i) { return '<tr><td>' + esc(i.value) + '</td><td>' + esc(i.label) + '</td><td>' + i.sort + '</td>' +
        '<td><button class="btn secondary" data-idel="' + i.id + '" style="width:auto;padding:3px 8px;font-size:.72rem;">×</button></td></tr>'; }).join('') + '</tbody></table>'
      : '<span class="note">Значений нет.</span>';
    $$('#iList [data-idel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_dict_item_delete', { p_token: token, p_id: b.dataset.idel }).then(function () { open(cur.id); load(); }); }); });
  }

  $('#q').addEventListener('input', function () { q = this.value; renderDicts(); });
  $('#dSave').addEventListener('click', function () {
    rpc('app_dict_save', { p_token: token, p_id: null, p_code: $('#dCode').value, p_name: $('#dName').value, p_description: null, p_active: true })
      .then(function (r) { var x = r && r[0]; msg('#dMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); $('#dCode').value = ''; $('#dName').value = ''; load(); })
      .catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#dClear').addEventListener('click', function () { $('#dCode').value = ''; $('#dName').value = ''; msg('#dMsg', ''); });
  $('#iSave').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_dict_item_save', { p_token: token, p_id: null, p_dict_id: cur.id, p_value: $('#iValue').value, p_label: $('#iLabel').value, p_sort: parseInt($('#iSort').value, 10) || 100, p_active: true })
      .then(function (r) { var x = r && r[0]; msg('#iMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); $('#iValue').value = ''; $('#iLabel').value = ''; open(cur.id); load(); })
      .catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#iClear').addEventListener('click', function () { $('#iValue').value = ''; $('#iLabel').value = ''; msg('#iMsg', ''); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#dMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
