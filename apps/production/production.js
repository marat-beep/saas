/* ============================================================
   3DMP Service · apps/production — Производство (наряды и операции)
   План/факт, маршрут и заявка, приоритет/сроки, операции из справочника.
   Данные: 0007+0026+0033. Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, naryads = [], wcs = [], orders = [], ops = [], curOps = [], cur = null, filter = '', q = '';

  var ST = { open: 'Открыт', in_progress: 'В работе', closed: 'Закрыт' };
  var PR = { high: 'Высокий', normal: 'Обычный', low: 'Низкий' };

  /* ---------- Роли (data-cap) ---------- */
  var ALL = { edit: 1, reports: 1 };
  var CAPS = { admin: ALL, owner: ALL, director: ALL, manager: ALL, chief: ALL, master: { edit: 1 }, technologist: { edit: 1 }, operator: { edit: 1 }, default: { reports: 1 } };
  function can(c) { return !!(me && (CAPS[me.role] || CAPS['default'])[c]); }
  function applyCaps() { $$('[data-cap]').forEach(function (el) { var n = (el.dataset.cap || '').split('|'); if (!n.some(can)) el.style.display = 'none'; }); }
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
      renderKpi(); renderList(); renderRisks();
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
  function kcell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }
  function renderRisks() {
    var host = $('#risks'); if (!host) return;
    var today = Date.now(), rows = [];
    naryads.forEach(function (n) {
      if (n.status === 'closed') return;
      var flags = [];
      if (num(n.plan_hours) > 0 && num(n.fact_hours) > num(n.plan_hours)) flags.push('перерасход ' + (Math.round((num(n.fact_hours) - num(n.plan_hours)) * 10) / 10) + ' ч');
      if (n.due_date) { var dd = new Date(n.due_date).getTime(); if (dd < today) flags.push('просрочен'); else if (dd - today < 3 * 86400000) flags.push('срок ≤3 дн'); }
      if (flags.length) rows.push({ n: n, flags: flags });
    });
    host.innerHTML = rows.length ? '<div class="card"><h2>Узкие места и риски <span class="note">' + rows.length + '</span></h2><div class="tbl-wrap"><table class="tbl"><thead><tr><th>Наряд</th><th>РЦ</th><th class="num">План/факт, ч</th><th>Сигналы</th></tr></thead><tbody>' +
      rows.map(function (x) { return '<tr data-rid="' + x.n.id + '" style="cursor:pointer;"><td><b>' + esc(x.n.number) + '</b> · ' + esc(x.n.title) + '</td><td>' + esc(x.n.wc_name || '—') + '</td><td class="num">' + num(x.n.plan_hours) + ' / ' + num(x.n.fact_hours) + '</td><td>' + x.flags.map(function (f) { return '<span class="badge">' + esc(f) + '</span>'; }).join(' ') + '</td></tr>'; }).join('') + '</tbody></table></div></div>' : '';
    $$('#risks [data-rid]').forEach(function (tr) { tr.addEventListener('click', function () { openDetail(tr.dataset.rid); }); });
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
      curOps = r[1] || [];
      var tot = curOps.length, doneN = curOps.filter(function (o) { return o.done; }).length;
      var fh = curOps.reduce(function (s, o) { return s + num(o.fact_hours); }, 0);
      var ph = curOps.reduce(function (s, o) { return s + num(o.plan_hours); }, 0);
      var prog = tot ? Math.round(doneN / tot * 100) : 0, dev = Math.round((fh - ph) * 10) / 10;
      var slaTxt = '—', slaC = '';
      if (n.due_date) { var dd = Math.ceil((new Date(n.due_date).getTime() - Date.now()) / 86400000); if (dd < 0) { slaTxt = 'просрочен на ' + (-dd) + ' дн'; slaC = '#b91c1c'; } else if (dd <= 3) { slaTxt = 'срок через ' + dd + ' дн'; slaC = '#b45309'; } else slaTxt = 'до срока ' + dd + ' дн'; }
      $('#detail').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' + stBadge(n.status) +
        '<span class="badge ' + (n.priority || 'normal') + '">' + (PR[n.priority] || n.priority || '') + '</span>' +
        '<b style="margin-left:auto;">' + esc(n.number) + '</b></div>' +
        '<h1 style="font-size:1.15rem;margin:10px 0;">' + esc(n.title) + '</h1>' +
        '<div class="kpi-row">' + kcell('Прогресс', prog + '%') + kcell('Операций', doneN + '/' + tot) +
        kcell('План, ч', Math.round(ph * 10) / 10) + kcell('Факт, ч', Math.round(fh * 10) / 10) +
        kcell('Отклонение, ч', dev, dev > 0 ? '#b91c1c' : (dev < 0 ? '#15803d' : '')) +
        kcell('Срок', slaTxt, slaC) + '</div>' +
        kv('Рабочий центр', n.wc_name) + kv('Исполнитель', n.assignee) + kv('Заявка', n.order_number) + kv('Маршрут', n.route_number) +
        kv('План-старт', fmt(n.start_date)) + kv('Срок', fmt(n.due_date)) + kv('План / факт', num(n.plan_hours) + ' / ' + num(n.fact_hours) + ' ч') +
        kv('Автор', n.created_login) + kv('Создан', fmt(n.created_at));
      $('#uAssignee').value = n.assignee || ''; $('#uPriority').value = n.priority || 'normal';
      $('#uWc').value = n.wc_id || ''; $('#uStart').value = (n.start_date || '').slice ? (n.start_date || '').slice(0, 10) : '';
      $('#uDue').value = (n.due_date || '').slice ? (n.due_date || '').slice(0, 10) : ''; $('#uNote').value = n.note || '';
      $('#closeBtn').disabled = n.status === 'closed';
      clearMsg('#opMsg'); clearMsg('#uMsg');
      renderOps(curOps);
      renderDefects(id);
      screens.go('s-detail');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderOps(ops) {
    if (!ops.length) { $('#ops').innerHTML = '<span class="note">Операций нет.</span>'; return; }
    $('#ops').innerHTML = ops.map(function (o) {
      var running = o.started_at && !o.finished_at;
      return '<div class="opline" data-op="' + o.id + '">' +
        '<div class="n">' + o.seq + '</div>' +
        '<div>' + esc(o.operation) + (o.route_step_id ? ' <span class="badge">из маршрута</span>' : '') + (o.done ? ' <span class="badge done">готово</span>' : '') + (running ? ' <span class="badge in_progress">▶ таймер</span>' : '') + '</div>' +
        '<div>' + num(o.plan_hours) + '</div>' +
        '<input type="text" data-fact="' + o.id + '" inputmode="decimal" value="' + num(o.fact_hours) + '">' +
        '<div style="white-space:nowrap;"><button class="chip" data-start="' + o.id + '" title="Запустить таймер">▶</button><button class="chip" data-stop="' + o.id + '" title="Остановить таймер">⏸</button><button class="chip" data-done="' + o.id + '" title="Отметить выполненной">✓</button></div>' +
        '</div>';
    }).join('');
    $$('#ops [data-start]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_op_start', { p_token: token, p_op_id: b.dataset.start })
          .then(function (r) { var x = r && r[0]; msg('#opMsg', (x && x.message) || '', x && x.ok ? 'ok' : 'err'); openDetail(cur.id); })
          .catch(function (e) { msg('#opMsg', 'Ошибка: ' + e.message, 'err'); });
      });
    });
    $$('#ops [data-stop]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_op_stop', { p_token: token, p_op_id: b.dataset.stop })
          .then(function (r) { var x = r && r[0]; msg('#opMsg', (x && x.message) || '', x && x.ok ? 'ok' : 'err'); openDetail(cur.id); })
          .catch(function (e) { msg('#opMsg', 'Ошибка: ' + e.message, 'err'); });
      });
    });
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

  /* ---------- Брак и переделки ---------- */
  var SEV = { minor: 'Незначительный', major: 'Значительный', critical: 'Критический' };
  function renderDefects(id) {
    return rpc('app_prod_defect_list', { p_token: token, p_naryad_id: id }).then(function (list) {
      list = list || [];
      $('#defects').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Операция</th><th>Причина</th><th class="num">Кол-во</th><th>Виновник</th><th class="num">Стоимость</th><th>Крит.</th></tr></thead><tbody>' +
        list.map(function (d) { return '<tr><td>' + esc(d.operation || '') + '</td><td>' + esc(d.cause || d.title || '') + '</td><td class="num">' + num(d.qty) + '</td><td>' + esc(d.culprit_login || '') + '</td><td class="num">' + (d.cost != null ? num(d.cost).toLocaleString('ru-RU') + ' ₽' : '—') + '</td><td>' + esc(SEV[d.severity] || d.severity) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Брака нет.</span>';
    }).catch(function () { $('#defects').innerHTML = '<span class="note">—</span>'; });
  }
  function defectForm() {
    if (!curOps.length) { ui.toast('Нет операций'); return; }
    ui.formDialog({ title: 'Фиксация брака/переделки', okText: 'Зафиксировать', fields: [
      { name: 'op_id', label: 'Операция', type: 'select', required: true, options: curOps.map(function (o) { return { value: o.id, label: o.seq + '. ' + o.operation }; }) },
      { name: 'qty', label: 'Количество', type: 'number', value: 1 },
      { name: 'cause', label: 'Причина', type: 'text', required: true, placeholder: 'Например: отклонение размера' },
      { name: 'culprit', label: 'Виновник (логин)', type: 'text' },
      { name: 'cost', label: 'Стоимость, ₽', type: 'number' },
      { name: 'severity', label: 'Критичность', type: 'select', options: [{ value: 'minor', label: 'Незначительный' }, { value: 'major', label: 'Значительный' }, { value: 'critical', label: 'Критический' }] }
    ] }).then(function (v) {
      if (!v) return;
      rpc('app_prod_defect_save', { p_token: token, p_id: null, p_naryad_op_id: v.op_id, p_qty: v.qty ? num(v.qty) : 1, p_cause: v.cause, p_culprit: v.culprit, p_cost: v.cost ? num(v.cost) : null, p_severity: v.severity, p_note: null })
        .then(function (r) { var x = r && r[0]; ui.toast((x && x.message) || '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) renderDefects(cur.id); });
    });
  }
  function defectKpi() {
    rpc('app_prod_defect_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      ui.dialog({ title: 'Брак и переделки — KPI', body: '<div class="kpi-row"><div class="kpi"><small>Записей</small><b>' + num(k.total) + '</b></div><div class="kpi"><small>Кол-во</small><b>' + num(k.qty) + '</b></div><div class="kpi"><small>Стоимость</small><b>' + num(k.cost).toLocaleString('ru-RU') + ' ₽</b></div><div class="kpi"><small>Критичных</small><b>' + num(k.critical) + '</b></div><div class="kpi"><small>Открытых</small><b>' + num(k.open_count) + '</b></div></div>', html: true, cancelText: 'Закрыть' });
    });
  }
  function routeCard() {
    if (!cur) { ui.toast('Откройте наряд'); return; }
    rpc('app_route_card', { p_token: token, p_naryad_id: cur.id }).then(function (rows) {
      rows = rows || [];
      var body = 'МАРШРУТНАЯ КАРТА · ' + esc(cur.number) + ' · ' + esc(cur.title) + '\n\n' +
        rows.map(function (o) { return o.seq + '. ' + o.operation + ' — план ' + num(o.plan_hours) + ' ч, факт ' + num(o.fact_hours) + ' ч' + (o.done ? ' (готово)' : ''); }).join('\n');
      var w = window.open('', '_blank');
      if (!w) { ui.toast('Разрешите всплывающие окна'); return; }
      w.document.write('<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>Маршрутная карта</title></head><body style="font:14px/1.6 system-ui,Segoe UI,Arial;white-space:pre-wrap;padding:24px;">' + body + '</body></html>');
      w.document.close(); w.focus(); w.print();
    });
  }
  function sszDialog() {
    ui.formDialog({ title: 'Сменно-суточное задание', okText: 'Сформировать', fields: [
      { name: 'date', label: 'Дата', type: 'date', value: new Date().toISOString().slice(0, 10) }
    ] }).then(function (v) {
      if (!v) return;
      rpc('app_daily_job_build', { p_token: token, p_date: v.date }).then(function (r) {
        var x = r && r[0]; ui.toast((x && x.message) || '', x && x.ok ? 'ok' : 'err');
        return rpc('app_daily_job_list', { p_token: token, p_date: v.date });
      }).then(function (list) {
        list = list || [];
        var html = '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Наряд</th><th>Операция</th><th class="num">План, ч</th><th>Исполнитель</th><th>Статус</th></tr></thead><tbody>' +
          (list.length ? list.map(function (j) { return '<tr><td>' + esc(j.naryad_number || '') + '</td><td>' + esc(j.operation || '') + '</td><td class="num">' + num(j.plan_hours) + '</td><td>' + esc(j.assignee || '') + '</td><td>' + esc(j.status) + '</td></tr>'; }).join('') : '<tr><td colspan="5" class="note">Пусто</td></tr>') + '</tbody></table></div>';
        ui.dialog({ title: 'ССЗ на ' + v.date, body: html, html: true, cancelText: 'Закрыть' });
      });
    });
  }

  /* ---------- Отчёт (производство) ---------- */
  function reportPdf() {
    if (!window.AppExport) { ui.toast('Экспорт недоступен'); return; }
    var plan = naryads.reduce(function (s, n) { return s + num(n.plan_hours); }, 0);
    var fact = naryads.reduce(function (s, n) { return s + num(n.fact_hours); }, 0);
    var cols = [
      { key: 'number', label: 'Наряд' }, { key: 'title', label: 'Название' },
      { key: 'status', label: 'Статус', value: function (n) { return ST[n.status] || n.status; } },
      { key: 'priority', label: 'Приоритет', value: function (n) { return PR[n.priority] || n.priority; } },
      { key: 'wc_name', label: 'Центр' }, { key: 'assignee', label: 'Исполнитель' },
      { key: 'plan_hours', label: 'План,ч', num: true }, { key: 'fact_hours', label: 'Факт,ч', num: true },
      { key: 'ops_done', label: 'Опер. вып./всего', num: true, value: function (n) { return num(n.ops_done) + '/' + num(n.ops_total); } },
      { key: 'due_date', label: 'Срок', value: function (n) { return n.due_date ? String(n.due_date).slice(0, 10) : ''; } }
    ];
    AppExport.exportPdf('Производство — отчёт', AppExport.reportDocument({
      brand: '3DMP Service', title: 'Отчёт по производству (наряды)', subtitle: new Date().toLocaleDateString('ru-RU'),
      kpis: [{ label: 'Нарядов', value: naryads.length }, { label: 'План, ч', value: Math.round(plan * 10) / 10 }, { label: 'Факт, ч', value: Math.round(fact * 10) / 10 }],
      sections: [{ title: 'Наряды', columns: cols, rows: naryads }],
      sign: ['Начальник производства', 'Главный инженер'], footer: '3DMP Service · производство'
    }));
  }
  $('#repBtn').addEventListener('click', reportPdf);
  $('#rcBtn').addEventListener('click', routeCard);
  $('#defectKpiBtn').addEventListener('click', defectKpi);
  $('#sszBtn').addEventListener('click', sszDialog);
  $('#addDefect').addEventListener('click', defectForm);

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
    me = s; token = s.token; applyCaps();
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    loadAll();
  });
})();
