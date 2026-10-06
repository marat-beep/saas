/* ============================================================
   3DMP Service · apps/slots — слоты по времени и SLA (P14). Данные: 0074.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, cur = null;

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function today() { return new Date().toISOString().slice(0, 10); }
  function plus(d) { var x = new Date(); x.setDate(x.getDate() + d); return x.toISOString().slice(0, 10); }

  function loadKpi() {
    return rpc('app_slots_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Слотов (30 дн)', k.slots || 0) + cell('Мощность, ч', k.hours_capacity || 0) + cell('Занято, ч', k.hours_used || 0) + cell('Загрузка', (k.utilization_pct || 0) + '%');
    });
  }

  function loadSlots() {
    var from = $('#qFrom').value || today(), to = $('#qTo').value || plus(6), center = $('#qCenter').value.trim();
    return rpc('app_slots_list', { p_token: token, p_from: from, p_to: to, p_center: center || null }).then(function (r) {
      var rows = r || [];
      $('#cnt').textContent = '(' + rows.length + ')';
      $('#list').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Дата</th><th>Центр</th><th>Смена</th><th class="num">Мощность</th><th class="num">Занято</th><th>Загрузка</th><th></th></tr></thead><tbody>' +
        rows.map(function (s) {
          var pct = s.capacity_hours > 0 ? Math.round(s.used_hours / s.capacity_hours * 100) : 0;
          return '<tr><td>' + esc(s.slot_date) + '</td><td>' + esc(s.center) + '</td><td>' + esc(s.shift) + '</td>' +
            '<td class="num">' + s.capacity_hours + '</td><td class="num">' + s.used_hours + '</td>' +
            '<td style="min-width:90px;"><div class="bar"><i style="width:' + Math.min(pct, 100) + '%"></i></div><span class="note">' + pct + '% · свободно ' + s.free_hours + '</span></td>' +
            '<td><button class="btn secondary" data-edit="' + s.id + '" style="width:auto;padding:3px 8px;font-size:.72rem;">✎</button> ' +
            '<button class="btn secondary" data-del="' + s.id + '" style="width:auto;padding:3px 8px;font-size:.72rem;">×</button></td></tr>';
        }).join('') + '</tbody></table>' : '<span class="note">Слотов нет.</span>';
      $$('#list [data-del]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_slot_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadSlots(); loadKpi(); }); }); });
      $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () {
        var s = rows.filter(function (x) { return x.id === b.dataset.edit; })[0]; if (!s) return;
        cur = s; $('#fCenter').value = s.center; $('#fDate').value = s.slot_date; $('#fShift').value = s.shift; $('#fCap').value = s.capacity_hours; window.scrollTo(0, 0);
      }); });
    }).catch(function (e) { msg('#mMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function loadSla() {
    return rpc('app_sla_list', { p_token: token }).then(function (r) {
      var rows = r || [];
      $('#sla').innerHTML = '<table class="mini"><thead><tr><th>Приоритет</th><th class="num">Часов</th></tr></thead><tbody>' +
        rows.map(function (s) { return '<tr><td>' + esc(s.priority) + '</td><td class="num">' + s.hours + '</td></tr>'; }).join('') + '</tbody></table>';
    });
  }

  $('#fSave').addEventListener('click', function () {
    rpc('app_slot_save', { p_token: token, p_id: cur ? cur.id : null, p_center: $('#fCenter').value, p_slot_date: $('#fDate').value, p_shift: $('#fShift').value, p_capacity_hours: parseFloat($('#fCap').value) || 8, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); cur = null; loadSlots(); loadKpi(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#fClear').addEventListener('click', function () { cur = null; msg('#fMsg', ''); });
  $('#sSave').addEventListener('click', function () {
    rpc('app_sla_save', { p_token: token, p_id: null, p_priority: $('#sPr').value, p_hours: parseInt($('#sHours').value, 10) || 24 })
      .then(function () { msg('#sMsg', 'SLA сохранён', 'ok'); loadSla(); }).catch(function (e) { msg('#sMsg', e.message, 'err'); });
  });
  $('#scanBtn').addEventListener('click', function () {
    rpc('app_escalation_scan', { p_token: token }).then(function (r) {
      var n = (r && r[0] && r[0].escalated) || 0;
      msg('#sMsg', 'Эскалировано проблем: ' + n, n > 0 ? 'ok' : 'info');
    }).catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#bBook').addEventListener('click', function () {
    rpc('app_slot_book', { p_token: token, p_center: $('#bCenter').value, p_slot_date: $('#bDate').value || today(), p_shift: $('#bShift').value, p_hours: parseFloat($('#bHours').value) || 0 })
      .then(function (r) { var x = r && r[0]; msg('#bMsg', x ? (x.message + ' (занято ' + x.used_hours + '/' + x.capacity_hours + ')') : 'Ошибка', x ? 'ok' : 'err'); loadSlots(); loadKpi(); })
      .catch(function (e) { msg('#bMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#qRefresh').addEventListener('click', function () { loadSlots(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    $('#qFrom').value = today(); $('#qTo').value = plus(6); $('#fDate').value = today(); $('#bDate').value = today();
    loadKpi(); loadSlots(); loadSla();
  });
})();
