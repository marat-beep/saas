/* ============================================================
   3DMP Service · apps/quality — СМК (СИ/поверка, трассируемость)
   Данные: app_tool_*, app_trace_*, app_quality_kpi (0022). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, tools = [], trace = [], orders = [];

  var STAT = { ok: 'в норме', due: 'истекает', expired: 'просрочено', none: 'нет даты' };
  function esc(v) { return ui.esc(v); }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? '—' : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_tools_list', { p_token: token }),
      rpc('app_trace_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_quality_kpi', { p_token: token }).catch(function () { return []; }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      tools = r[0] || []; trace = r[1] || []; var k = (r[2] && r[2][0]) || {}; orders = r[3] || [];
      $('#kpis').innerHTML = kpi(k.tools || 0, 'СИ всего') + kpi(k.expired || 0, 'Просрочено') + kpi(k.due || 0, 'Истекает (30 дн.)') + kpi(k.trace_records || 0, 'Записей трассируемости');
      $('#rOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      renderTools(); renderTrace();
    }).catch(function (e) { msg('#tMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function kpi(v, l) { return '<div class="kpi"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>'; }

  function renderTools() {
    $('#tools').innerHTML = tools.length ? tools.map(function (t) {
      return '<div class="row"><span class="b ' + t.status + '">' + (STAT[t.status] || t.status) + '</span>' +
        '<b>' + esc(t.name) + '</b><span class="note">' + (t.serial ? esc(t.serial) + ' · ' : '') + (t.tool_type ? esc(t.tool_type) + ' · ' : '') + (t.location ? esc(t.location) : '') + '</span>' +
        '<span class="note" style="margin-left:auto;">поверка: ' + fmt(t.next_verified) + '</span>' +
        '<button class="act danger" data-del="' + t.id + '">✕</button></div>';
    }).join('') : '<span class="note">СИ нет.</span>';
    $$('#tools [data-del]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_tool_delete', { p_token: token, p_id: b.dataset.del }).then(function () { ui.toast('Удалено'); load(); }); }); });
  }
  function renderTrace() {
    $('#trace').innerHTML = trace.length ? trace.map(function (t) {
      return '<div class="row"><b>' + esc(t.item) + '</b><span class="note">' + (t.serial ? esc(t.serial) + ' · ' : '') + (t.material ? esc(t.material) + ' · ' : '') + (t.order_number ? '📥 ' + esc(t.order_number) + ' · ' : '') + (t.by_login ? esc(t.by_login) : '') + '</span>' +
        '<span class="note" style="margin-left:auto;">' + fmt(t.created_at) + '</span></div>';
    }).join('') : '<span class="note">Записей нет.</span>';
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    $('#t-tools').style.display = (b.dataset.t === 'tools') ? '' : 'none';
    $('#t-trace').style.display = (b.dataset.t === 'trace') ? '' : 'none';
  });

  $('#gAdd').addEventListener('click', function () {
    var name = $('#gName').value.trim(); if (!name) { msg('#tMsg', 'Укажите наименование.', 'err'); return; }
    rpc('app_tool_save', { p_token: token, p_id: null, p_name: name, p_serial: $('#gSerial').value.trim(), p_tool_type: $('#gType').value.trim(), p_location: $('#gLoc').value.trim(), p_last: $('#gLast').value || null, p_next: $('#gNext').value || null })
      .then(function (d) { var r = d && d[0]; msg('#tMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { ['#gName', '#gSerial', '#gType', '#gLoc'].forEach(function (s) { $(s).value = ''; }); load(); } });
  });
  $('#rAdd').addEventListener('click', function () {
    var item = $('#rItem').value.trim(); if (!item) { msg('#rMsg', 'Укажите изделие.', 'err'); return; }
    rpc('app_trace_add', { p_token: token, p_item: item, p_serial: $('#rSerial').value.trim(), p_order_id: $('#rOrder').value || null, p_passport_id: null, p_material: $('#rMat').value.trim(), p_operator: $('#rOp').value.trim(), p_note: '' })
      .then(function (d) { var r = d && d[0]; msg('#rMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { ['#rItem', '#rSerial', '#rMat', '#rOp'].forEach(function (s) { $(s).value = ''; }); load(); } });
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#tMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
