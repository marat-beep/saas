/* ============================================================
   3DMP Service · apps/oee — OEE-монитор (эффективность оборудования)
   Доступность × качество по сменам, простои. Данные: 0054.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, rows = [], byEq = [], eq = [], q = '';

  var SHIFTS = { '1': '1-я', '2': '2-я', night: 'Ночная' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function oeeClass(v) { return v >= 75 ? 'good' : v >= 50 ? 'mid' : 'bad'; }

  function load() {
    return Promise.all([
      rpc('app_oee_log_list', { p_token: token, p_q: null }),
      rpc('app_oee_kpi', { p_token: token }),
      rpc('app_oee_by_equipment', { p_token: token }),
      rpc('app_equipment_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      rows = r[0] || []; var k = (r[1] && r[1][0]) || {}; byEq = r[2] || []; eq = r[3] || [];
      $('#fEq').innerHTML = '<option value="">— выберите —</option>' + eq.map(function (e) { return '<option value="' + e.id + '">' + esc(e.name) + '</option>'; }).join('');
      $('#kpis').innerHTML = cell('Средний OEE', num(k.avg_oee) + '%', k.avg_oee >= 75 ? '#15803d' : (k.avg_oee < 50 ? '#b91c1c' : '#92400e')) +
        cell('Доступность', num(k.avg_availability) + '%') + cell('Качество', num(k.avg_quality) + '%') +
        cell('Смен учтено', num(k.records)) + cell('Простои, мин', num(k.downtime_total), k.downtime_total ? '#b91c1c' : '');
      render(); renderByEq();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function render() {
    var list = rows.filter(function (r) { if (!q) return true; var s = q.toLowerCase(); return [r.equipment, r.downtime_reason].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + list.length + ')';
    $('#list').innerHTML = list.length ? list.map(function (r) {
      var o = num(r.oee), p = Math.max(0, Math.min(100, o));
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<b>' + esc(r.equipment || '—') + '</b>' +
        '<span class="note">' + fmt(r.shift_date) + ' · ' + (SHIFTS[r.shift] || r.shift || '') + '</span>' +
        '<span class="note" style="margin-left:auto;">OEE <b>' + o + '%</b> · доступн. ' + num(r.availability) + '% · качество ' + num(r.quality) + '%</span></div>' +
        '<div class="life ' + oeeClass(o) + '"><i style="width:' + p + '%"></i></div>' +
        '<div style="font-size:.78rem;color:var(--muted);margin-top:5px;">работа ' + num(r.run_min) + '/' + num(r.planned_min) + ' мин · простой ' + num(r.downtime_min) + ' мин' +
        (r.downtime_reason ? ' (' + esc(r.downtime_reason) + ')' : '') + ' · годных ' + num(r.good_qty) + '/' + num(r.total_qty) + '</div></div>';
    }).join('') : '<span class="note">Записей нет.</span>';
  }
  function renderByEq() {
    $('#byEq').innerHTML = byEq.length ? '<table class="table" style="width:100%;border-collapse:collapse"><thead><tr><th>Оборудование</th><th>Смен</th><th>Средний OEE</th><th>Простои, мин</th></tr></thead><tbody>' +
      byEq.map(function (e) {
        return '<tr style="border-bottom:1px solid var(--border)"><td><b>' + esc(e.equipment) + '</b></td><td>' + num(e.records) + '</td>' +
          '<td>' + num(e.avg_oee) + '%</td><td>' + num(e.downtime_total) + '</td></tr>';
      }).join('') + '</tbody></table>' : '<span class="note">Нет данных.</span>';
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fAdd').addEventListener('click', function () {
    var eid = $('#fEq').value; if (!eid) { msg('#fMsg', 'Выберите оборудование.', 'err'); return; }
    var plan = parseFloat(($('#fPlan').value || '').replace(',', '.'));
    if (isNaN(plan) || plan <= 0) { msg('#fMsg', 'Укажите плановое время > 0.', 'err'); return; }
    var run = parseFloat(($('#fRun').value || '').replace(',', '.')); var down = parseFloat(($('#fDown').value || '').replace(',', '.'));
    var good = parseFloat(($('#fGood').value || '').replace(',', '.')); var total = parseFloat(($('#fTotal').value || '').replace(',', '.'));
    rpc('app_oee_save', { p_token: token, p_id: null, p_equipment_id: eid, p_date: $('#fDate').value || null, p_shift: $('#fShift').value,
      p_planned: plan, p_run: isNaN(run) ? 0 : run, p_downtime: isNaN(down) ? 0 : down, p_reason: $('#fReason').value.trim(),
      p_good: isNaN(good) ? 0 : good, p_total: isNaN(total) ? 0 : total, p_note: null })
      .then(function (d) { var r = d && d[0]; msg('#fMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('OEE смена', ''); ['#fPlan', '#fRun', '#fDown', '#fReason', '#fGood', '#fTotal'].forEach(function (s) { $(s).value = ''; }); load(); } })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    $('#fDate').value = new Date().toISOString().slice(0, 10);
    load();
  });
})();
