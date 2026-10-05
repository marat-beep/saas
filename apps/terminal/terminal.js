/* ============================================================
   3DMP Service · apps/terminal — Пульт оператора (PWA)
   Операции нарядов: запуск/пауза/готово, факт часов. Данные: MES (0034).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, ops = [], wcs = [], onlyMine = true, wcFilter = '';

  var STATUS = { queue: 'В очереди', work: 'В работе', paused: 'Пауза', done: 'Выполнено' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function msg(t, k) { var e = $('#msg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_mes_ops_board', { p_token: token, p_wc_id: wcFilter || null }),
      rpc('app_wc_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      ops = r[0] || []; wcs = r[1] || [];
      var cur = $('#wc').value;
      $('#wc').innerHTML = '<option value="">— все центры —</option>' + wcs.map(function (w) { return '<option value="' + w.id + '">' + esc(w.name) + '</option>'; }).join('');
      $('#wc').value = cur || '';
      render();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function render() {
    var my = (me && me.login || '').toLowerCase();
    var list = ops.filter(function (o) {
      if (onlyMine && my && (o.worker || '').toLowerCase() !== my) return false;
      return true;
    });
    $('#list').innerHTML = list.length ? list.map(card).join('') : '<span class="note">Операций нет. Смените фильтр или центр.</span>';
    $$('#list [data-st]').forEach(function (b) {
      b.addEventListener('click', function () { setStatus(b.dataset.id, b.dataset.st); });
    });
  }
  function card(o) {
    var acts = '';
    if (o.mes_status === 'queue') acts = btn('work', o.op_id, '▶ Запустить', 'b-go');
    else if (o.mes_status === 'work') acts = btn('paused', o.op_id, '⏸ Пауза', 'b-pause') + btn('done', o.op_id, '✓ Готово', 'b-done');
    else if (o.mes_status === 'paused') acts = btn('work', o.op_id, '▶ Продолжить', 'b-go') + btn('done', o.op_id, '✓ Готово', 'b-done');
    else acts = btn('queue', o.op_id, '↩ В очередь', 'b-back');
    return '<div class="op' + (o.mes_status === 'done' ? ' done' : '') + '">' +
      '<div class="t">' + o.seq + '. ' + esc(o.operation) + '</div>' +
      '<div class="m">' + esc(o.naryad_number) + ' · ' + esc(o.naryad_title || '') + '</div>' +
      '<div class="m">' + (o.wc_name ? '🏭 ' + esc(o.wc_name) : '') + (o.worker ? ' · 👤 ' + esc(o.worker) : '') +
      ' · план ' + num(o.plan_hours) + ' ч · факт ' + num(o.fact_hours) + ' ч</div>' +
      '<div class="m"><span class="badge ' + (o.mes_status === 'done' ? 'done' : o.mes_status === 'work' ? 'in_progress' : '') + '">' + (STATUS[o.mes_status] || o.mes_status) + '</span></div>' +
      '<div class="acts">' + acts + '</div></div>';
  }
  function btn(st, id, label, cls) { return '<button data-st="' + st + '" data-id="' + id + '" class="' + cls + '">' + label + '</button>'; }
  function setStatus(id, st) {
    var fact = null;
    if (st === 'done') {
      var m = window.prompt('Факт часов по операции (необязательно):', '');
      if (m != null && String(m).trim() !== '') fact = parseFloat(String(m).replace(',', '.'));
    }
    rpc('app_mes_ops_set_status', { p_token: token, p_op_id: id, p_status: st })
      .then(function (d) {
        var r = d && d[0]; if (r && !r.ok) throw new Error(r.message || 'Ошибка');
        if (st === 'done' && fact != null && !isNaN(fact)) {
          return rpc('app_naryad_op_done', { p_token: token, p_op_id: id, p_fact_hours: fact, p_done: true });
        }
      })
      .then(function () { window.Auth.log('Пульт', st); ui.toast((STATUS[st] || st)); if (window.AppNotify) window.AppNotify.refresh(true); load(); })
      .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }

  $('#wc').addEventListener('change', function () { wcFilter = this.value; load(); });
  $('#onlyMine').addEventListener('change', function () { onlyMine = this.checked; render(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  if ('serviceWorker' in navigator) { navigator.serviceWorker.register('sw.js').catch(function () {}); }

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    load();
  });
})();
