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
      renderKpi(); render(); loadBoardSummary();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function loadBoardSummary() {
    return rpc('app_mes_board', { p_token: token, p_wc_id: wcFilter || null }).then(function (rows) {
      rows = rows || [];
      var el = $('#wcSummary'); if (!el) return;
      el.innerHTML = rows.length ? 'Очереди по РЦ: ' + rows.map(function (r) {
        return '<b>' + esc(r.wc_name) + '</b> (' + (r.queue || 0) + 'оч/' + (r.work || 0) + 'раб/' + (r.paused || 0) + 'пауза/' + (r.done || 0) + 'вып)';
      }).join(' · ') : '';
    }).catch(function () {});
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
    $$('.acts [data-reassign]').forEach(function (b) { b.addEventListener('click', function () { reassign(b.dataset.reassign); }); });
    $$('.acts [data-alert]').forEach(function (b) { b.addEventListener('click', function () { alertRaise(b.dataset.alert); }); });
    bindDnd();
  }
  function card(o) {
    var acts = '';
    if (o.mes_status === 'queue') acts = btn('work', o.op_id, '▶ Запустить');
    else if (o.mes_status === 'work') acts = btn('paused', o.op_id, '⏸ Пауза') + btn('done', o.op_id, '✓ Готово');
    else if (o.mes_status === 'paused') acts = btn('work', o.op_id, '▶ Продолжить') + btn('done', o.op_id, '✓ Готово');
    else acts = btn('queue', o.op_id, '↩ В очередь');
    acts += '<button data-reassign="' + o.op_id + '" title="РЦ / приоритет">→ РЦ</button>' +
            '<button data-alert="' + o.op_id + '" title="Аварийный сигнал">⚠</button>';
    return '<div class="card2" draggable="true" data-op="' + o.op_id + '">' +
      '<div style="display:flex;gap:6px;align-items:center;"><span class="badge ' + (o.priority || 'normal') + '">' + (PR[o.priority] || o.priority) + '</span>' +
      '<span class="mini" style="margin-left:auto;">' + esc(o.naryad_number) + '</span></div>' +
      '<div style="font-weight:600;font-size:.85rem;margin-top:5px;">' + o.seq + '. ' + esc(o.operation) + '</div>' +
      '<div class="mini">' + esc(o.naryad_title) + '</div>' +
      '<div class="mini">' + (o.wc_name ? '🏭 ' + esc(o.wc_name) : '') + (o.worker ? ' · 👤 ' + esc(o.worker) : '') +
      ' · план ' + num(o.plan_hours) + '/факт ' + num(o.fact_hours) + ' ч' + (o.due_date ? ' · до ' + fmt(o.due_date) : '') + '</div>' +
      '<div class="acts">' + acts + '</div></div>';
  }
  function btn(st, id, label) { return '<button data-st="' + st + '" data-id="' + id + '">' + label + '</button>'; }

  /* ---------- Drag&drop между колонками ========== */
  var COL_ST = { cQueued: 'queue', cRunning: 'work', cPaused: 'paused', cDone: 'done' };
  function bindDnd() {
    $$('.board .card2').forEach(function (c) {
      c.addEventListener('dragstart', function (e) { e.dataTransfer.setData('text/plain', c.dataset.op); e.dataTransfer.effectAllowed = 'move'; });
    });
    Object.keys(COL_ST).forEach(function (id) {
      var el = $('#' + id); if (!el) return;
      el.addEventListener('dragover', function (e) { e.preventDefault(); e.dataTransfer.dropEffect = 'move'; });
      el.addEventListener('drop', function (e) { e.preventDefault(); var opId = e.dataTransfer.getData('text/plain'); if (opId) setStatus(opId, COL_ST[id]); });
    });
  }
  function reassign(opId) {
    var o = ops.filter(function (x) { return x.op_id === opId; })[0] || {};
    var wcOpts = [{ value: '', label: '— не менять —' }].concat(wcs.map(function (w) { return { value: w.id, label: w.name }; }));
    ui.formDialog({ title: 'Переназначить задание', okText: 'Сохранить', fields: [
      { name: 'wc_id', label: 'Рабочий центр', type: 'select', options: wcOpts, value: o.wc_id || '' },
      { name: 'priority', label: 'Приоритет', type: 'select', options: [{ value: 'high', label: 'Высокий' }, { value: 'normal', label: 'Обычный' }, { value: 'low', label: 'Низкий' }], value: o.priority || 'normal' }
    ] }).then(function (v) {
      if (!v) return;
      rpc('app_op_reassign', { p_token: token, p_op_id: opId, p_wc_id: v.wc_id || null, p_priority: v.priority })
        .then(function (r) { var x = r && r[0]; msg((x && x.message) || '', x && x.ok ? 'ok' : 'err'); load(); });
    });
  }
  function alertRaise(opId) {
    ui.formDialog({ title: 'Аварийный сигнал', okText: 'Отправить', fields: [
      { name: 'kind', label: 'Тип', type: 'select', options: [{ value: 'сбой', label: 'Сбой оборудования' }, { value: 'нет материала', label: 'Нет материала' }, { value: 'брак', label: 'Брак' }, { value: 'инцидент', label: 'Инцидент/ОТ' }] },
      { name: 'text', label: 'Описание', type: 'textarea', rows: 2 }
    ] }).then(function (v) {
      if (!v) return;
      rpc('app_alert_raise', { p_token: token, p_op_id: opId, p_kind: v.kind, p_text: v.text || null })
        .then(function (r) { var x = r && r[0]; ui.toast((x && x.message) || '', x && x.ok ? 'ok' : 'err'); if (window.AppNotify) window.AppNotify.refresh(true); });
    });
  }
  /* ---------- Realtime: живая доска ---------- */
  var rtTimer = null;
  function scheduleReload() { clearTimeout(rtTimer); rtTimer = setTimeout(load, 500); }
  function subscribe() {
    if (!SB || !SB.channel) return;
    try {
      SB.channel('mes-board').on('postgres_changes', { event: '*', schema: 'public', table: 'app_naryad_ops' }, scheduleReload)
        .on('postgres_changes', { event: '*', schema: 'public', table: 'app_naryads' }, scheduleReload).subscribe();
    } catch (e) { /* realtime недоступен — остаётся ручное обновление */ }
  }
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
    subscribe();
  });
})();
