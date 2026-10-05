/* ============================================================
   3DMP Service · apps/mes — Диспетчерская (канбан операций нарядов)
   Источник: операции нарядов (app_naryad_ops, 0034). Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, ops = [], wcs = [], wcFilter = '', q = '';

  var COLS = [['queue', 'col-queued', 'cQueued'], ['work', 'col-running', 'cRunning'], ['paused', 'col-paused', 'cPaused'], ['done', 'col-done', 'cDone']];
  var PR = { high: 'высокий', normal: 'обычный', low: 'низкий' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function fmt(d) { if (!d) return ''; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }
  function msg(t, k) { var e = $('#cMsg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_mes_ops_board', { p_token: token, p_wc_id: wcFilter || null }),
      rpc('app_wc_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      ops = r[0] || []; wcs = r[1] || [];
      var cur = $('#mWc').value;
      $('#mWc').innerHTML = '<option value="">— все центры —</option>' + wcs.map(function (w) { return '<option value="' + w.id + '">' + esc(w.name) + '</option>'; }).join('');
      $('#mWc').value = cur || '';
      renderKpi(); render();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function counts() { var c = { queue: 0, work: 0, paused: 0, done: 0 }; ops.forEach(function (o) { c[o.mes_status] = (c[o.mes_status] || 0) + 1; }); return c; }
  function renderKpi() {
    var c = counts(), plan = 0, fact = 0;
    ops.forEach(function (o) { plan += num(o.plan_hours); fact += num(o.fact_hours); });
    $('#kpis').innerHTML = cell('В очереди', c.queue) + cell('В работе', c.work) + cell('Пауза', c.paused) +
      cell('Выполнено', c.done) + cell('План/факт, ч', (Math.round(plan * 10) / 10) + ' / ' + (Math.round(fact * 10) / 10));
    function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  }
  function matches(o) {
    if (!q) return true; var s = q.toLowerCase();
    return [o.naryad_number, o.naryad_title, o.operation, o.worker, o.wc_name].join(' ').toLowerCase().indexOf(s) >= 0;
  }
  function render() {
    COLS.forEach(function (col) {
      var list = ops.filter(function (o) { return o.mes_status === col[0] && matches(o); });
      $('#' + col[2]).textContent = '(' + list.length + ')';
      $('#' + col[1]).innerHTML = list.length ? list.map(card).join('') : '<span class="note" style="font-size:.75rem;">—</span>';
    });
    $$('.acts [data-st]').forEach(function (b) {
      b.addEventListener('click', function () { setStatus(b.dataset.id, b.dataset.st); });
    });
  }
  function card(o) {
    var acts = '';
    if (o.mes_status === 'queue') acts = btn('work', o.op_id, '▶ Запустить');
    else if (o.mes_status === 'work') acts = btn('paused', o.op_id, '⏸ Пауза') + btn('done', o.op_id, '✓ Готово');
    else if (o.mes_status === 'paused') acts = btn('work', o.op_id, '▶ Продолжить') + btn('done', o.op_id, '✓ Готово');
    else acts = btn('queue', o.op_id, '↩ В очередь');
    return '<div class="card2">' +
      '<div style="display:flex;gap:6px;align-items:center;"><span class="badge ' + (o.priority || 'normal') + '">' + (PR[o.priority] || o.priority) + '</span>' +
      '<span class="mini" style="margin-left:auto;">' + esc(o.naryad_number) + '</span></div>' +
      '<div style="font-weight:600;font-size:.85rem;margin-top:5px;">' + o.seq + '. ' + esc(o.operation) + '</div>' +
      '<div class="mini">' + esc(o.naryad_title) + '</div>' +
      '<div class="mini">' + (o.wc_name ? '🏭 ' + esc(o.wc_name) : '') + (o.worker ? ' · 👤 ' + esc(o.worker) : '') +
      ' · план ' + num(o.plan_hours) + '/факт ' + num(o.fact_hours) + ' ч' + (o.due_date ? ' · до ' + fmt(o.due_date) : '') + '</div>' +
      '<div class="acts">' + acts + '</div></div>';
  }
  function btn(st, id, label) { return '<button data-st="' + st + '" data-id="' + id + '">' + label + '</button>'; }
  function setStatus(id, st) {
    rpc('app_mes_ops_set_status', { p_token: token, p_op_id: id, p_status: st })
      .then(function (d) { var r = d && d[0]; if (r && !r.ok) { msg(r.message, 'err'); return; } window.Auth.log('MES', st); if (window.AppNotify) window.AppNotify.refresh(true); load(); })
      .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }

  $('#mWc').addEventListener('change', function () { wcFilter = this.value; load(); });
  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    load();
  });
})();
