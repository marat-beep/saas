/* ============================================================
   3DMP Service · apps/production — Производство (наряды и операции)
   План/факт, маршрут и заявка, приоритет/сроки, операции из справочника.
   Данные: 0007+0026+0033. Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, naryads = [], wcs = [], orders = [], ops = [], cur = null, filter = '', q = '';

  var ST = { open: 'Открыт', in_progress: 'В работе', closed: 'Закрыт' };
  var PR = { high: 'Высокий', normal: 'Обычный', low: 'Низкий' };
  function stBadge(s) { return '<span class="badge ' + (s === 'closed' ? 'done' : s) + '">' + (ST[s] || s) + '</span>'; }
  function esc(v) { return ui.esc(v); }
  function fmt(ts) { if (!ts) return ''; var d = new Date(ts); return isNaN(d.getTime()) ? String(ts) : d.toLocaleDateString('ru-RU'); }
  function num(v) { return Number(v) || 0; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function loadAll() {
    return Promise.all([
      rpc('app_naryad_list', { p_token: token }),
      rpc('app_wc_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_operations_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      naryads = r[0] || []; wcs = r[1] || []; orders = r[2] || []; ops = r[3] || [];
      var wcOpts = '<option value="">— не выбрано —</option>' + wcs.map(function (w) { return '<option value="' + w.id + '">' + esc(w.name) + (w.cost_hour ? ' · ' + w.cost_hour + ' ₽/ч' : '') + '</option>'; }).join('');
      $('#fWc').innerHTML = wcOpts; $('#uWc').innerHTML = wcOpts;
      $('#fOrder').innerHTML = '<option value="">— без заявки —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      $('#opSel').innerHTML = '<option value="">— вручную —</option>' + ops.map(function (o) { return '<option value="' + o.id + '">' + esc(o.name) + '</option>'; }).join('');
      renderKpi(); renderList();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    var c = { open: 0, in_progress: 0, closed: 0, plan: 0, fact: 0 };
    naryads.forEach(function (n) { c[n.status] = (c[n.status] || 0) + 1; c.plan += num(n.plan_hours); c.fact += num(n.fact_hours); });
    $('#kpis').innerHTML = cell('Открыто', c.open) + cell('В работе', c.in_progress) + cell('Закрыто', c.closed) +
      cell('План, ч', Math.round(c.plan * 10) / 10) + cell('Факт, ч', Math.round(c.fact * 10) / 10);
    function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  }
  function filtered() {
    var s = q.toLowerCase();
    return naryads.filter(function (n) {
      if (filter && n.status !== filter) return false;
      if (!s) return true;
      return [n.number, n.title, n.wc_name, n.assignee, n.order_number, n.route_number].join(' ').toLowerCase().indexOf(s) >= 0;
    });
  }
  function renderList() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Нарядов нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (n) {
      var prog = n.ops_total ? Math.round((num(n.ops_done) / num(n.ops_total)) * 100) : 0;
      return '<div class="ocard" data-id="' + n.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' + stBadge(n.status) +
        '<span class="badge ' + n.priority + '">' + (PR[n.priority] || n.priority) + '</span>' +
        (n.route_number ? '<span class="badge">🧭 ' + esc(n.route_number) + '</span>' : '') +
        (n.order_number ? '<span class="badge">📥 ' + esc(n.order_number) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + esc(n.number) + '</span></div>' +
        '<h3 style="font-size:.95rem;margin:8px 0 4px;">' + esc(n.title) + '</h3>' +
        '<div style="font-size:.76rem;color:var(--muted);">' +
        (n.wc_name ? '🏭 ' + esc(n.wc_name) + ' · ' : '') + (n.assignee ? '👤 ' + esc(n.assignee) + ' · ' : '') +
        'план ' + num(n.plan_hours) + ' / факт ' + num(n.fact_hours) + ' ч · операции ' + num(n.ops_done) + '/' + num(n.ops_total) + ' (' + prog + '%)' +
        (n.due_date ? ' · до ' + fmt(n.due_date) : '') + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openDetail(c.dataset.id); }); });
  }

  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function openDetail(id) {
    Promise.all([rpc('app_naryad_get', { p_token: token, p_id: id }), rpc('app_naryad_ops', { p_token: token, p_id: id })]).then(function (r) {
      var n = r[0] && r[0][0]; if (!n) { ui.toast('Наряд не найден'); return; }
      cur = n;
      $('#detail').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' + stBadge(n.status) +
        '<span class="badge ' + (n.priority || 'normal') + '">' + (PR[n.priority] || n.priority || '') + '</span>' +
        '<b style="margin-left:auto;">' + esc(n.number) + '</b></div>' +
        '<h1 style="font-size:1.15rem;margin:10px 0;">' + esc(n.title) + '</h1>' +
        kv('Рабочий центр', n.wc_name) + kv('Исполнитель', n.assignee) + kv('Заявка', n.order_number) + kv('Маршрут', n.route_number) +
        kv('План-старт', fmt(n.start_date)) + kv('Срок', fmt(n.due_date)) + kv('План / факт', num(n.plan_hours) + ' / ' + num(n.fact_hours) + ' ч') +
        kv('Автор', n.created_login) + kv('Создан', fmt(n.created_at));
      $('#uAssignee').value = n.assignee || ''; $('#uPriority').value = n.priority || 'normal';
      $('#uWc').value = n.wc_id || ''; $('#uStart').value = (n.start_date || '').slice ? (n.start_date || '').slice(0, 10) : '';
      $('#uDue').value = (n.due_date || '').slice ? (n.due_date || '').slice(0, 10) : ''; $('#uNote').value = n.note || '';
      $('#closeBtn').disabled = n.status === 'closed';
      clearMsg('#opMsg'); clearMsg('#uMsg');
      renderOps(r[1] || []);
      screens.go('s-detail');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderOps(ops) {
    if (!ops.length) { $('#ops').innerHTML = '<span class="note">Операций нет.</span>'; return; }
    $('#ops').innerHTML = ops.map(function (o) {
      return '<div class="opline" data-op="' + o.id + '">' +
        '<div class="n">' + o.seq + '</div>' +
        '<div>' + esc(o.operation) + (o.route_step_id ? ' <span class="badge">из маршрута</span>' : '') + (o.done ? ' <span class="badge done">готово</span>' : '') + '</div>' +
        '<div>' + num(o.plan_hours) + '</div>' +
        '<input type="text" data-fact="' + o.id + '" inputmode="decimal" value="' + num(o.fact_hours) + '">' +
        '<button class="chip" data-done="' + o.id + '" title="Отметить выполненной">✓</button>' +
        '</div>';
    }).join('');
    $$('#ops [data-done]').forEach(function (b) {
      b.addEventListener('click', function () {
        var fid = b.dataset.done, el = $('#ops [data-fact="' + fid + '"]');
        var fv = parseFloat((el && el.value) || '0');
        rpc('app_naryad_op_done', { p_token: token, p_op_id: fid, p_fact_hours: isNaN(fv) ? 0 : fv, p_done: true })
          .then(function () { window.Auth.log('Операция выполнена', cur && cur.number); openDetail(cur.id); })
          .catch(function (e) { msg('#opMsg', 'Ошибка: ' + e.message, 'err'); });
      });
    });
  }

  $('#toCreate').addEventListener('click', function () { clearMsg('#cMsg'); screens.go('s-create'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { loadAll(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });
  $('#q').addEventListener('input', function () { q = this.value; renderList(); });

  $('#createBtn').addEventListener('click', function () {
    var title = $('#fTitle').value.trim();
    if (!title) { msg('#cMsg', 'Укажите название наряда.', 'err'); return; }
    rpc('app_naryad_create', {
      p_token: token, p_order_id: $('#fOrder').value || null, p_title: title,
      p_wc_id: $('#fWc').value || null, p_assignee: $('#fAssignee').value.trim(), p_due_date: $('#fDue').value || null,
      p_priority: $('#fPriority').value, p_start_date: $('#fStart').value || null
    }).then(function (d) {
      var row = d && d[0];
      window.Auth.log('Создан наряд', (row && row.number) || title);
      if (window.AppNotify) window.AppNotify.refresh(true);
      ui.toast('Наряд ' + ((row && row.number) || '') + ' создан');
      ['#fTitle', '#fAssignee', '#fStart', '#fDue'].forEach(function (s) { $(s).value = ''; });
      loadAll().then(function () { screens.go('s-list'); });
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#addOp').addEventListener('click', function () {
    if (!cur) return;
    var name = $('#opName').value.trim();
    var opId = $('#opSel').value || null;
    if (!name && !opId) { msg('#opMsg', 'Выберите операцию или введите название.', 'err'); return; }
    var ph = parseFloat(($('#opPlan').value || '').replace(',', '.'));
    rpc('app_naryad_add_op', { p_token: token, p_naryad_id: cur.id, p_operation: name, p_worker: '', p_plan_hours: isNaN(ph) ? 0 : ph, p_operation_id: opId, p_route_step_id: null })
      .then(function (d) { var r = d && d[0]; if (r && !r.ok) { msg('#opMsg', r.message, 'err'); return; } $('#opName').value = ''; $('#opPlan').value = ''; $('#opSel').value = ''; openDetail(cur.id); })
      .catch(function (e) { msg('#opMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#saveBtn').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_naryad_update', {
      p_token: token, p_id: cur.id, p_assignee: $('#uAssignee').value.trim(), p_priority: $('#uPriority').value,
      p_wc_id: $('#uWc').value || null, p_start_date: $('#uStart').value || null, p_due_date: $('#uDue').value || null, p_note: $('#uNote').value.trim()
    }).then(function (d) { var r = d && d[0]; msg('#uMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) openDetail(cur.id); })
      .catch(function (e) { msg('#uMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#closeBtn').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_naryad_close', { p_token: token, p_id: cur.id }).then(function (d) {
      var row = d && d[0];
      if (!row || !row.ok) { msg('#opMsg', (row && row.message) || 'Не удалось', 'err'); return; }
      window.Auth.log('Закрыт наряд', cur.number); ui.toast('Наряд закрыт'); openDetail(cur.id);
    }).catch(function (e) { msg('#opMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    loadAll();
  });
})();
