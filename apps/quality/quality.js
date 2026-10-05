/* ============================================================
   3DMP Service · apps/quality — СМК (СИ/поверка, трассируемость)
   Данные: 0022+0044. Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, tools = [], trace = [], orders = [], q = '';

  var STAT = { ok: 'в норме', due: 'истекает', expired: 'просрочено', none: 'нет даты' };
  var BADGE = { ok: 'done', due: 'in_progress', expired: 'cancelled', none: '' };
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
      $('#kpis').innerHTML = cell('СИ всего', k.tools || 0) + cell('Просрочено', k.expired || 0, (k.expired ? '#b91c1c' : '')) +
        cell('Истекает (30 дн.)', k.due || 0, (k.due ? '#92400e' : '')) + cell('Записей трассируемости', k.trace_records || 0);
      $('#vTool').innerHTML = '<option value="">— выберите СИ —</option>' + tools.map(function (t) { return '<option value="' + t.id + '">' + esc(t.name) + (t.serial ? ' (' + esc(t.serial) + ')' : '') + '</option>'; }).join('');
      $('#rOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      renderTools(); renderTrace();
    }).catch(function (e) { msg('#tMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function renderTools() {
    var list = tools.filter(function (t) { if (!q) return true; var s = q.toLowerCase(); return [t.name, t.serial, t.tool_type, t.location].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#tools').innerHTML = list.length ? list.map(function (t) {
      return '<div class="kvr"><span class="badge ' + (BADGE[t.status] || '') + '">' + (STAT[t.status] || t.status) + '</span>' +
        '<b>' + esc(t.name) + '</b><span class="note">' + (t.serial ? esc(t.serial) + ' · ' : '') + (t.tool_type ? esc(t.tool_type) + ' · ' : '') + (t.location ? esc(t.location) : '') + '</span>' +
        '<span class="note" style="margin-left:auto;">поверка: ' + fmt(t.next_verified) + (t.days_left != null ? ' (' + (t.days_left < 0 ? 'просрочено ' + (-t.days_left) + ' дн.' : 'через ' + t.days_left + ' дн.') + ')' : '') + '</span>' +
        '<button class="chip" data-vs="' + t.id + '">Поверка</button>' +
        '<button class="chip" data-del="' + t.id + '">✕</button></div>';
    }).join('') : '<span class="note">СИ нет.</span>';
    $$('#tools [data-del]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_tool_delete', { p_token: token, p_id: b.dataset.del }).then(function () { window.Auth.log('Удалено СИ', b.dataset.del); ui.toast('Удалено'); load(); }); }); });
    $$('#tools [data-vs]').forEach(function (b) { b.addEventListener('click', function () { $('#vTool').value = b.dataset.vs; $('#vMsg').className = 'msg'; window.scrollTo(0, 0); }); });
  }
  function renderTrace() {
    $('#trace').innerHTML = trace.length ? trace.map(function (t) {
      return '<div class="kvr"><b>' + esc(t.item) + '</b>' +
        '<span class="note">' + (t.serial ? esc(t.serial) + ' · ' : '') + (t.material ? esc(t.material) + ' · ' : '') +
        (t.order_number ? '📥 ' + esc(t.order_number) + ' · ' : '') + (t.passport_number ? '🪪 ' + esc(t.passport_number) + ' · ' : '') +
        (t.operator ? '👤 ' + esc(t.operator) : '') + '</span>' +
        '<span class="note" style="margin-left:auto;">' + fmt(t.created_at) + ' · ' + esc(t.by_login || '') + '</span></div>';
    }).join('') : '<span class="note">Записей нет.</span>';
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    $('#t-tools').style.display = (b.dataset.t === 'tools') ? '' : 'none';
    $('#t-trace').style.display = (b.dataset.t === 'trace') ? '' : 'none';
  });
  $('#q').addEventListener('input', function () { q = this.value; renderTools(); });

  $('#gAdd').addEventListener('click', function () {
    var name = $('#gName').value.trim(); if (!name) { msg('#tMsg', 'Укажите наименование.', 'err'); return; }
    rpc('app_tool_save', { p_token: token, p_id: null, p_name: name, p_serial: $('#gSerial').value.trim(), p_tool_type: $('#gType').value.trim(), p_location: $('#gLoc').value.trim(), p_last: $('#gLast').value || null, p_next: $('#gNext').value || null })
      .then(function (d) { var r = d && d[0]; msg('#tMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { ['#gName', '#gSerial', '#gType', '#gLoc', '#gLast', '#gNext'].forEach(function (s) { $(s).value = ''; }); load(); } });
  });
  $('#vBtn').addEventListener('click', function () {
    var id = $('#vTool').value; if (!id) { msg('#vMsg', 'Выберите СИ.', 'err'); return; }
    rpc('app_tool_verify', { p_token: token, p_id: id, p_date: $('#vLast').value || null, p_next: $('#vNext').value || null })
      .then(function (d) { var r = d && d[0]; msg('#vMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('Поверка СИ', id); if (window.AppNotify) window.AppNotify.refresh(true); $('#vLast').value = ''; $('#vNext').value = ''; load(); } });
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
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#tMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
