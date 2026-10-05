/* ============================================================
   3DMP Service · apps/mes — диспетчерская (канбан)
   Данные: app_mes_* (0021_mes.sql). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, tasks = [], wcs = [], naryads = [];

  var COLS = [['queued', 'col-queued', 'cQueued'], ['running', 'col-running', 'cRunning'], ['paused', 'col-paused', 'cPaused'], ['done', 'col-done', 'cDone']];
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_mes_board', { p_token: token }),
      rpc('app_wc_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_naryad_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_mes_kpi', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      tasks = r[0] || []; wcs = r[1] || []; naryads = r[2] || []; var k = (r[3] && r[3][0]) || {};
      $('#kpis').innerHTML = kpi(k.queued || 0, 'В очереди') + kpi(k.running || 0, 'В работе') + kpi(k.paused || 0, 'Пауза') + kpi(k.done || 0, 'Выполнено');
      $('#mWc').innerHTML = '<option value="">— центр —</option>' + wcs.map(function (w) { return '<option value="' + w.id + '">' + esc(w.name) + '</option>'; }).join('');
      $('#mNar').innerHTML = '<option value="">— нет —</option>' + naryads.map(function (n) { return '<option value="' + n.id + '">' + esc(n.number) + ' · ' + esc(n.title) + '</option>'; }).join('');
      render();
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function kpi(v, l) { return '<div class="kpi"><div class="v">' + v + '</div><div class="l">' + l + '</div></div>'; }

  function render() {
    COLS.forEach(function (c) {
      var list = tasks.filter(function (t) { return t.status === c[0]; });
      $('#' + c[2]).textContent = '(' + list.length + ')';
      $('#' + c[1]).innerHTML = list.length ? list.map(card).join('') : '<span class="note" style="font-size:.75rem;">—</span>';
    });
    $$('#col-queued [data-st], #col-running [data-st], #col-paused [data-st], #col-done [data-st]').forEach(function (b) {
      b.addEventListener('click', function () { setStatus(b.dataset.id, b.dataset.st); });
    });
    $$('[data-del]').forEach(function (b) { b.addEventListener('click', function () { del(b.dataset.del); }); });
  }
  function card(t) {
    var acts = '';
    if (t.status === 'queued') acts = '<button data-st="running" data-id="' + t.id + '">▶ Запустить</button>';
    else if (t.status === 'running') acts = '<button data-st="paused" data-id="' + t.id + '">⏸ Пауза</button><button data-st="done" data-id="' + t.id + '">✓ Готово</button>';
    else if (t.status === 'paused') acts = '<button data-st="running" data-id="' + t.id + '">▶ Продолжить</button><button data-st="done" data-id="' + t.id + '">✓ Готово</button>';
    else acts = '<button data-del="' + t.id + '">Удалить</button>';
    return '<div class="card2"><div style="display:flex;gap:6px;align-items:center;"><span class="b ' + t.priority + '">' + (t.priority === 'high' ? 'высокий' : t.priority === 'low' ? 'низкий' : 'обычный') + '</span>' +
      '<span class="mini" style="margin-left:auto;">' + esc(t.number) + '</span></div>' +
      '<div style="font-weight:600;font-size:.85rem;margin-top:5px;">' + esc(t.title) + '</div>' +
      '<div class="mini">' + (t.wc_name ? '🏭 ' + esc(t.wc_name) : '') + (t.operator ? ' · 👤 ' + esc(t.operator) : '') + (t.naryad_number ? ' · 📋 ' + esc(t.naryad_number) : '') + '</div>' +
      '<div class="acts">' + acts + '</div></div>';
  }
  function setStatus(id, st) {
    rpc('app_mes_set_status', { p_token: token, p_id: id, p_status: st })
      .then(function () { window.Auth.log('MES', st); if (window.AppNotify) window.AppNotify.refresh(true); load(); })
      .catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function del(id) { rpc('app_mes_delete', { p_token: token, p_id: id }).then(function () { ui.toast('Удалено'); load(); }); }

  $('#mCreate').addEventListener('click', function () {
    var title = $('#mTitle').value.trim(); if (!title) { msg('#cMsg', 'Укажите задание.', 'err'); return; }
    rpc('app_mes_create', { p_token: token, p_wc_id: $('#mWc').value || null, p_naryad_id: $('#mNar').value || null, p_title: title, p_priority: $('#mPriority').value, p_operator: $('#mOperator').value.trim() })
      .then(function (d) { var row = d && d[0]; if (!row) { msg('#cMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('MES задание', row.number); ui.toast('Задание ' + row.number + ' создано');
        $('#mTitle').value = ''; $('#mOperator').value = ''; load(); })
      .catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#cMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
