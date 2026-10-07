/* ============================================================
   3DMP Service · apps/service — Сервис и ремонт ЧПУ (S1, миграция 0122)
   Заявки SRV v2: приоритет/SLA, гарантия, история, выезды, KPI, IIoT-автотикеты.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, list = [], customers = [], eq = [], cur = null, filter = '', q = '';
  var lastK = {}, lastKe = {};

  var KIND = { service: 'Сервис', repair: 'Ремонт', warranty: 'Гарантия' };
  var ST = { new: 'Новая', scheduled: 'Запланирована', in_progress: 'В работе', done: 'Выполнена', cancelled: 'Отменена' };
  var PRIO = { low: 'Низкий', normal: 'Обычный', high: 'Высокий', critical: 'Критичный' };
  var CHAN = { manual: 'вручную', phone: 'телефон', email: 'e-mail', portal: 'портал', dealer: 'дилер', iiot: 'IIoT' };
  var VST = { assigned: 'Назначен', on_way: 'В пути', in_work: 'В работе', done: 'Завершён', cancelled: 'Отменён' };
  var SLA = { ok: 'SLA в норме', warn: 'SLA истекает', overdue: 'SLA просрочен', closed: 'закрыта' };

  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return v == null ? '—' : num(v).toLocaleString('ru-RU', { maximumFractionDigits: 0 }) + ' ₽'; }
  function pad(n) { return ('0' + n).slice(-2); }
  function fmtTs(ts) { if (!ts) return '—'; var d = new Date(ts); return isNaN(d.getTime()) ? String(ts) : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function toLocalInput(iso) { if (!iso) return ''; var d = new Date(iso); if (isNaN(d.getTime())) return ''; return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes()); }
  function fromLocalInput(v) { if (!v) return null; var d = new Date(v); return isNaN(d.getTime()) ? null : d.toISOString(); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  /* ---------- Роли: доступные функции (оргструктура службы) ---------- */
  var ALL = { dash:1, list:1, visits:1, refs:1, reports:1, access:1, new:1, edit:1, assign:1, supply:1, act:1, passport:1, parts:1, rules:1, iiot:1 };
  var CAPS = {
    admin: ALL, owner: ALL, director: ALL,
    manager: { dash:1, list:1, visits:1, refs:1, reports:1, access:1, new:1, edit:1, assign:1, supply:1, act:1, passport:1, parts:1, iiot:1, rules:1 },
    chief:   { dash:1, list:1, visits:1, refs:1, reports:1, access:1, new:1, edit:1, assign:1, supply:1, act:1, passport:1, parts:1, iiot:1, rules:1 },
    support: { list:1, new:1, edit:1, assign:1, act:1, visits:1, passport:1 },
    master:  { list:1, visits:1, edit:1, act:1, passport:1, parts:1 },
    qc:      { list:1, visits:1, edit:1, act:1, passport:1 },
    default: { list:1, visits:1, act:1, passport:1 }
  };
  function capsFor(role) { return CAPS[role] || CAPS['default']; }
  function can(c) { return !!(me && capsFor(me.role)[c]); }
  function applyCaps() {
    $$('[data-cap]').forEach(function (el) {
      var need = (el.dataset.cap || '').split('|');
      var ok = need.some(function (n) { return can(n); });
      if (!ok) { el.style.display = 'none'; el.classList.remove('active'); }
    });
  }
  function setActiveTab(id) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.go === id); });
  }
  function go(id) { setActiveTab(id); screens.go(id); if (id === 's-visits') loadMyVisits(); if (id === 's-refs') { loadRefs(); loadRules(); loadEngineerLoad(); loadTemplates(); } if (id === 's-reports') loadReports(); if (id === 's-dash') renderDash(); if (id === 's-access') renderAccess(); if (id === 's-proc') renderProcess(); }

  function load() {
    return Promise.all([
      rpc('app_service_list', { p_token: token, p_q: null }),
      rpc('app_service_kpi', { p_token: token }),
      rpc('app_customer_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_equipment_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_service_kpi_ext', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; var k = (r[1] && r[1][0]) || {}; customers = r[2] || []; eq = r[3] || []; var ke = (r[4] && r[4][0]) || {};
      $('#kpis').innerHTML = cell('Открытых', num(k.open), num(k.open) ? '#92400e' : '') +
        cell('Критичных', num(k.critical), num(k.critical) ? '#b91c1c' : '') +
        cell('Просрочено SLA', num(k.overdue_sla), num(k.overdue_sla) ? '#b91c1c' : '') +
        cell('MTTR, ч', k.mttr_hours != null ? num(k.mttr_hours) : '—') +
        cell('MTBF, ч', ke.mtbf_hours != null ? num(ke.mtbf_hours) : '—') +
        cell('FTFR, %', k.ftfr_pct != null ? num(k.ftfr_pct) : '—') +
        cell('Активных выездов', num(ke.active_visits)) +
        cell('Затраты', money(k.cost_sum));
      lastK = k; lastKe = ke;
      render(); renderDash();
      if (cur) loadDetail(cur.id);
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
    function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }
  }
  function filtered() {
    var s = q.toLowerCase();
    return list.filter(function (r) {
      if (filter === 'open' && (r.status === 'done' || r.status === 'cancelled')) return false;
      if (filter === 'critical' && r.priority !== 'critical') return false;
      if (filter === 'warranty' && !r.is_warranty) return false;
      if (filter === 'overdue' && r.sla_state !== 'overdue') return false;
      if (!s) return true;
      return [r.number, r.title, r.customer, r.engineer, r.assigned_login].join(' ').toLowerCase().indexOf(s) >= 0;
    });
  }
  function prioBadge(p) { return '<span class="badge p-' + (p || 'normal') + '">' + (PRIO[p] || p) + '</span>'; }
  function slaBadge(s) { return s && s !== 'closed' ? '<span class="badge sla-' + s + '">' + (SLA[s] || s) + '</span>' : ''; }
  function render() {
    var rows = filtered();
    $('#list').innerHTML = rows.length ? rows.map(function (r) {
      return '<div class="ocard" data-id="' + r.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' + prioBadge(r.priority) +
        '<span class="badge">' + (KIND[r.kind] || r.kind) + '</span>' + (r.is_warranty ? '<span class="badge">гарантия</span>' : '') +
        slaBadge(r.sla_state) + (r.source === 'iiot' ? '<span class="badge">IIoT</span>' : '') +
        '<b style="margin-left:auto;">' + esc(r.number) + '</b></div>' +
        '<h3 style="font-size:.94rem;margin:8px 0 4px;">' + esc(r.title || '') + '</h3>' +
        '<div style="font-size:.76rem;color:var(--muted);">' +
        (r.customer ? '🏢 ' + esc(r.customer) + ' · ' : '') + (r.equipment ? '🏭 ' + esc(r.equipment) + ' · ' : '') +
        '👤 ' + esc(r.assigned_login || r.engineer || '—') + ' · ' + (ST[r.status] || r.status) +
        ' · до ' + fmtTs(r.resolve_due) + '</div></div>';
    }).join('') : '<span class="note">Заявок нет.</span>';
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function kpi(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }
  function openItem(id) { cur = { id: id }; screens.go('s-item'); loadDetail(id); }
  function loadDetail(id) {
    Promise.all([
      rpc('app_service_get', { p_token: token, p_id: id }),
      rpc('app_service_history_list', { p_token: token, p_id: id }).catch(function () { return []; }),
      rpc('app_service_visit_list', { p_token: token, p_id: id }).catch(function () { return []; })
    ]).then(function (r) {
      var d = (r[0] || [])[0]; var hist = r[1] || []; var visits = r[2] || [];
      if (!d) { msg('#iMsg', 'Заявка не найдена', 'err'); return; }
      cur = d;
      $('#detail').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' + prioBadge(d.priority) +
        '<span class="badge">' + (KIND[d.kind] || d.kind) + '</span>' + (d.is_warranty ? '<span class="badge">гарантия</span>' : '') +
        slaBadge(d.sla_state) + '<b style="margin-left:auto;">' + esc(d.number) + '</b></div>' +
        '<h1 style="font-size:1.1rem;margin:10px 0;">' + esc(d.title || '') + '</h1>' +
        kv('Заказчик', d.customer) + kv('Оборудование', d.equipment) + kv('Канал', CHAN[d.channel] || d.channel) +
        kv('Контакт', d.contact) + kv('Место', d.location) + kv('Код ошибки', d.fault_code) +
        kv('Инженер', d.assigned_login || d.engineer) +
        kv('Создана', fmtTs(d.reported_at || d.created_at)) + kv('Реакция до', fmtTs(d.response_due)) + kv('Решение до', fmtTs(d.resolve_due)) +
        kv('Решена', fmtTs(d.resolved_at)) + kv('Источник', d.source === 'iiot' ? 'IIoT' : d.source === 'ppr' ? 'ППР (ТОиР)' : (CHAN[d.channel] || 'вручную')) +
        kv('Гарантия', d.warranty_number) + kv('Контракт', d.contract_number) + kv('План ТОиР', d.plan_id ? 'связан' : null) +
        kv('Затраты (работы)', money(d.cost)) + kv('Стоимость запчастей', d.parts_cost ? money(d.parts_cost) : null) +
        kv('Работы', d.works) + kv('Примечание', d.note);
      $('#stSel').value = d.status;
      $('#visits').innerHTML = visits.length ? visits.map(function (v) {
        return '<div class="kvr"><span class="badge">' + (VST[v.status] || v.status) + '</span><b>' + esc(v.engineer || '—') + '</b>' +
          (v.place ? '<span class="note">📍 ' + esc(v.place) + '</span>' : '') +
          '<span class="note">план ' + fmtTs(v.planned_at) + (v.finished_at ? ' · факт ' + fmtTs(v.finished_at) : '') + '</span>' +
          (v.work_report ? '<span class="note">' + esc(v.work_report) + '</span>' : '') +
          '<span style="margin-left:auto;white-space:nowrap;">' +
          (v.status !== 'in_work' && v.status !== 'done' ? '<button class="act" data-vst="in_work" data-vid="' + v.id + '">В работе</button>' : '') +
          (v.status !== 'done' ? '<button class="act" data-vst="done" data-vid="' + v.id + '">Завершить</button>' : '') + '</span></div>';
      }).join('') : '<span class="note">Выездов нет.</span>';
      $('#history').innerHTML = hist.length ? hist.map(function (h) {
        return '<div class="tl-item"><div class="note">' + fmtTs(h.created_at) + ' · ' + esc(h.by_login || '') + '</div><div>' + esc(h.text || h.kind) + '</div></div>';
      }).join('') : '<span class="note">История пуста.</span>';
      bindVisits(); loadParts(id);
    }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function bindVisits() {
    $$('#visits [data-vst]').forEach(function (b) {
      b.addEventListener('click', function () {
        callOffline('app_service_visit_status', { p_token: token, p_visit_id: b.dataset.vid, p_status: b.dataset.vst, p_report: null }, 'выезд ' + b.dataset.vst, function () {
          window.Auth.log('Сервис выезд', b.dataset.vst); if (window.AppNotify) window.AppNotify.refresh(true); load();
        });
      });
    });
  }

  function openForm() {
    if (!customers.length && !eq.length) { /* допустимо */ }
    ui.formDialog({
      title: 'Новая заявка', okText: 'Создать', size: 'lg',
      fields: [
        { name: 'title', label: 'Тема *', type: 'text', required: true, placeholder: 'Аварийный ремонт шпинделя' },
        { name: 'kind', label: 'Вид', type: 'select', options: [{ value: 'service', label: 'Сервис' }, { value: 'repair', label: 'Ремонт' }, { value: 'warranty', label: 'Гарантия' }] },
        { name: 'priority', label: 'Приоритет', type: 'select', options: [{ value: 'low', label: 'Низкий' }, { value: 'normal', label: 'Обычный' }, { value: 'high', label: 'Высокий' }, { value: 'critical', label: 'Критичный' }] },
        { name: 'channel', label: 'Канал', type: 'select', options: [{ value: 'manual', label: 'Вручную' }, { value: 'phone', label: 'Телефон' }, { value: 'email', label: 'E-mail' }, { value: 'portal', label: 'Портал' }, { value: 'dealer', label: 'Дилер' }] },
        { name: 'customer_id', label: 'Заказчик', type: 'select', options: [{ value: '', label: '— нет —' }].concat(customers.map(function (c) { return { value: c.id, label: c.name }; })) },
        { name: 'equipment_id', label: 'Оборудование', type: 'select', options: [{ value: '', label: '— нет —' }].concat(eq.map(function (e) { return { value: e.id, label: e.name }; })) },
        { name: 'is_warranty', label: 'Гарантийный', type: 'checkbox' },
        { name: 'contact', label: 'Контакт', type: 'text' },
        { name: 'location', label: 'Место', type: 'text', placeholder: 'Цех 1, уч. 3' },
        { name: 'scheduled_date', label: 'Плановая дата', type: 'date' },
        { name: 'assigned_login', label: 'Инженер (логин)', type: 'text' },
        { name: 'cost', label: 'Стоимость, ₽', type: 'text' },
        { name: 'works', label: 'Работы', type: 'text' },
        { name: 'note', label: 'Примечание', type: 'textarea', rows: 2 }
      ],
      values: { kind: 'service', priority: 'normal', channel: 'manual', scheduled_date: new Date().toISOString().slice(0, 10) }
    }).then(function (v) {
      if (!v) return;
      var cost = parseFloat(String(v.cost || '').replace(',', '.'));
      rpc('app_service_save', {
        p_token: token, p_id: null, p_customer_id: v.customer_id || null, p_equipment_id: v.equipment_id || null,
        p_title: v.title, p_kind: v.kind, p_scheduled_date: v.scheduled_date || null, p_engineer: v.assigned_login || null,
        p_works: v.works || null, p_cost: isNaN(cost) ? null : cost, p_note: v.note || null,
        p_priority: v.priority, p_channel: v.channel, p_is_warranty: !!v.is_warranty,
        p_contact: v.contact || null, p_location: v.location || null, p_assigned_login: v.assigned_login || null
      }).then(function (d) { var r = d && d[0]; if (!r) { msg('#listMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('Сервис', r.number); msg('#listMsg', r.message + ' ' + r.number, 'ok'); load(); })
        .catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
    });
  }

  $('#newBtn').addEventListener('click', openForm);
  $('#iiotBtn').addEventListener('click', function () {
    rpc('app_service_iiot_auto', { p_token: token, p_hours: 24 }).then(function (d) { var r = d && d[0]; msg('#listMsg', r ? r.message : '', r && r.created > 0 ? 'ok' : 'info'); if (r && r.created > 0) load(); })
      .catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; render();
  });
  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#stBtn').addEventListener('click', function () {
    if (!cur) return;
    callOffline('app_service_set_status', { p_token: token, p_id: cur.id, p_status: $('#stSel').value, p_note: $('#stNote').value.trim() }, 'статус ' + $('#stSel').value, function (d) {
      var r = d && d[0]; msg('#iMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('Сервис статус', $('#stSel').value); if (window.AppNotify) window.AppNotify.refresh(true); load(); }
    });
  });
  $('#assignBtn').addEventListener('click', function () {
    if (!cur) return;
    ui.formDialog({ title: 'Назначить выезд', okText: 'Назначить', fields: [
      { name: 'engineer', label: 'Инженер (логин)', type: 'text', required: true },
      { name: 'planned_at', label: 'Дата/время', type: 'datetime-local' },
      { name: 'place', label: 'Место', type: 'text' }
    ], values: { planned_at: toLocalInput(new Date().toISOString()) } }).then(function (v) {
      if (!v) return;
      rpc('app_service_assign', { p_token: token, p_id: cur.id, p_engineer: v.engineer, p_planned_at: fromLocalInput(v.planned_at), p_place: v.place || null })
        .then(function (d) { var r = d && d[0]; msg('#iMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('Сервис назначение', v.engineer); load(); } })
        .catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
    });
  });
  $('#commentBtn').addEventListener('click', function () {
    if (!cur) return;
    ui.formDialog({ title: 'Комментарий', okText: 'Добавить', fields: [{ name: 'text', label: 'Текст', type: 'textarea', rows: 2, required: true }] })
      .then(function (v) { if (!v) return;
        rpc('app_service_history_add', { p_token: token, p_id: cur.id, p_text: v.text, p_kind: 'comment' })
          .then(function () { loadDetail(cur.id); }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); }); });
  });
  /* ---------- Офлайн-обёртка для действий ---------- */
  function callOffline(name, args, label, onOk) {
    if (!navigator.onLine || !SB) { queueOp(name, args, label); return; }
    rpc(name, args).then(function (d) { if (onOk) onOk(d); }).catch(function () { queueOp(name, args, label); });
  }
  function queueOp(name, args, label) {
    if (!window.AppOffline) { msg('#iMsg', 'Нет сети, очередь недоступна.', 'err'); return; }
    window.AppOffline.add({ rpc: name, args: args, label: label }).then(function () { msg('#iMsg', 'Офлайн — сохранено, синхронизируется автоматически.', 'info'); });
  }

  /* ---------- Запчасти по заявке ---------- */
  var spareParts = [];
  function loadParts(id) {
    rpc('app_service_parts_list', { p_token: token, p_id: id }).then(function (r) {
      r = r || [];
      $('#parts').innerHTML = r.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Запчасть</th><th class="num">Кол-во</th><th class="num">Цена</th><th class="num">Стоимость</th><th>Статус</th><th></th></tr></thead><tbody>' +
        r.map(function (x) { return '<tr><td>' + esc(x.part || '') + '</td><td class="num">' + num(x.qty) + ' ' + esc(x.unit || '') + '</td><td class="num">' + money(x.price) + '</td><td class="num">' + money(x.cost) + '</td>' +
          '<td><span class="badge">' + (x.status === 'reserved' ? 'резерв' : esc(x.status)) + '</span></td>' +
          '<td><button class="act danger" data-prem="' + x.id + '">Вернуть</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Запчастей нет.</span>';
      $$('#parts [data-prem]').forEach(function (b) {
        b.addEventListener('click', function () {
          rpc('app_service_part_remove', { p_token: token, p_id: b.dataset.prem }).then(function (d) { var r2 = d && d[0]; msg('#iMsg', r2 ? r2.message : '', r2 && r2.ok ? 'ok' : 'err'); loadParts(cur.id); load(); });
        });
      });
    }).catch(function () { $('#parts').innerHTML = '<span class="note">Недоступно.</span>'; });
  }
  function partForm() {
    if (!cur) return;
    var go = function () {
      ui.formDialog({ title: 'Запчасть по заявке', okText: 'Зарезервировать', fields: [
        { name: 'part', label: 'Запчасть', type: 'select', options: spareParts.map(function (p) { return { value: p.id, label: p.name + ' (' + num(p.qty) + ' ' + (p.unit || '') + ')' }; }) },
        { name: 'qty', label: 'Количество', type: 'text', required: true, value: '1' }
      ] }).then(function (v) { if (!v) return; var q = parseFloat(String(v.qty).replace(',', '.'));
        if (isNaN(q) || q <= 0) { msg('#iMsg', 'Некорректное количество', 'err'); return; }
        rpc('app_service_part_add', { p_token: token, p_id: cur.id, p_part_id: v.part, p_qty: q })
          .then(function (d) { var r = d && d[0]; msg('#iMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('Сервис запчасть', ''); loadParts(cur.id); load(); } });
      });
    };
    if (spareParts.length) { go(); return; }
    rpc('app_spare_parts_list', { p_token: token }).then(function (r) { spareParts = r || []; if (!spareParts.length) { msg('#iMsg', 'Нет запчастей на складе', 'err'); return; } go(); });
  }

  /* ---------- Выезды службы (обезличенно) ---------- */
  var visitBoard = [], vq = '';
  function loadMyVisits() {
    rpc('app_service_visit_board', { p_token: token, p_days: 30 }).then(function (r) {
      visitBoard = r || []; renderVisits();
    }).catch(function () { $('#myList').innerHTML = '<span class="note">Недоступно.</span>'; });
  }
  function renderVisits() {
    var s = vq.toLowerCase();
    var rows = visitBoard.filter(function (v) { return !s || [v.number, v.title, v.equipment, v.engineer, v.place].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#myList').innerHTML = rows.length ? rows.map(function (v) {
      return '<div class="ocard" data-open="' + v.request_id + '" style="cursor:pointer;">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' + prioBadge(v.priority) +
        (v.sla_state === 'overdue' ? '<span class="badge sla-overdue">SLA просрочен</span>' : v.sla_state === 'warn' ? '<span class="badge sla-warn">SLA истекает</span>' : '') +
        '<span class="badge">' + (VST[v.status] || v.status) + '</span>' +
        '<b style="margin-left:auto;">' + esc(v.number) + '</b></div>' +
        '<div style="font-size:.84rem;margin-top:4px;">' + esc(v.title || '') + '</div>' +
        '<div class="note">' + (v.equipment ? '🏭 ' + esc(v.equipment) + ' · ' : '') + (v.place ? '📍 ' + esc(v.place) + ' · ' : '') +
        (v.fault_code ? '⚠ ' + esc(v.fault_code) + ' · ' : '') + 'инженер: ' + esc(v.engineer || '—') + ' · план ' + fmtTs(v.planned_at) + '</div>' +
        '<div class="toolbar mt"><button class="act" data-mv="on_way" data-vid="' + v.visit_id + '">В пути</button>' +
        '<button class="act" data-mv="in_work" data-vid="' + v.visit_id + '">В работе</button>' +
        '<button class="act" data-mv="done" data-vid="' + v.visit_id + '">Завершить выезд</button></div></div>';
    }).join('') : '<span class="note">Выездов нет.</span>';
    $$('#myList [data-open]').forEach(function (c) {
      c.addEventListener('click', function (e) { if (e.target.closest('[data-mv]')) return; openItem(c.dataset.open); });
    });
    $$('#myList [data-mv]').forEach(function (b) {
      b.addEventListener('click', function (e) {
        e.stopPropagation();
        callOffline('app_service_visit_status', { p_token: token, p_visit_id: b.dataset.vid, p_status: b.dataset.mv, p_report: null }, 'выезд ' + b.dataset.mv, function () {
          window.Auth.log('Сервис выезд', b.dataset.mv); loadMyVisits();
        });
      });
    });
  }

  /* ---------- Гарантии и контракты ---------- */
  var warranties = [], contracts = [];
  function loadRefs() {
    Promise.all([
      rpc('app_warranty_list', { p_token: token }),
      rpc('app_service_contract_list', { p_token: token })
    ]).then(function (r) {
      warranties = r[0] || []; contracts = r[1] || []; renderWarr(); renderCon();
    }).catch(function (e) { msg('#refMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  var WST = { active: 'активна', expired: 'истекла', planned: 'запланирована', off: 'выключена' };
  function renderWarr() {
    $('#warrList').innerHTML = warranties.length ? '<table class="tbl"><thead><tr><th>Оборудование</th><th>Заказчик</th><th>№</th><th>Поставщик</th><th>Период</th><th>Статус</th><th></th></tr></thead><tbody>' +
      warranties.map(function (w) { return '<tr><td><b>' + esc(w.equipment || '—') + '</b></td><td class="muted">' + esc(w.customer || '') + '</td><td>' + esc(w.number || '') + '</td>' +
        '<td>' + esc(w.provider) + '</td><td class="muted">' + (w.start_date || '') + ' — ' + (w.end_date || '∞') + (w.days_left != null ? ' (' + w.days_left + ' дн)' : '') + '</td>' +
        '<td><span class="badge ' + (w.status === 'active' ? 'done' : 'cancelled') + '">' + (WST[w.status] || w.status) + '</span></td>' +
        '<td style="white-space:nowrap;"><button class="act" data-wedit="' + w.id + '">Изменить</button><button class="act danger" data-wdel="' + w.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Гарантий нет.</span>';
    $$('#warrList [data-wedit]').forEach(function (b) { b.addEventListener('click', function () { warrForm(warranties.filter(function (x) { return x.id === b.dataset.wedit; })[0]); }); });
    $$('#warrList [data-wdel]').forEach(function (b) { b.addEventListener('click', function () { if (!window.confirm('Удалить гарантию?')) return; rpc('app_warranty_delete', { p_token: token, p_id: b.dataset.wdel }).then(function (d) { var r = d && d[0]; msg('#refMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); loadRefs(); }); }); });
  }
  function renderCon() {
    $('#conList').innerHTML = contracts.length ? '<table class="tbl"><thead><tr><th>Заказчик</th><th>№</th><th>Тип</th><th>Период</th><th class="num">Реакция, мин</th><th class="num">Решение, мин</th><th>Статус</th><th></th></tr></thead><tbody>' +
      contracts.map(function (k) { return '<tr><td><b>' + esc(k.customer || '—') + '</b></td><td>' + esc(k.number || '') + '</td><td>' + esc(k.kind) + '</td>' +
        '<td class="muted">' + (k.start_date || '') + ' — ' + (k.end_date || '∞') + '</td><td class="num">' + (k.response_sla_min || '—') + '</td><td class="num">' + (k.resolve_sla_min || '—') + '</td>' +
        '<td><span class="badge ' + (k.status === 'active' ? 'done' : 'cancelled') + '">' + (WST[k.status] || k.status) + '</span></td>' +
        '<td style="white-space:nowrap;"><button class="act" data-kedit="' + k.id + '">Изменить</button><button class="act danger" data-kdel="' + k.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Контрактов нет.</span>';
    $$('#conList [data-kedit]').forEach(function (b) { b.addEventListener('click', function () { conForm(contracts.filter(function (x) { return x.id === b.dataset.kedit; })[0]); }); });
    $$('#conList [data-kdel]').forEach(function (b) { b.addEventListener('click', function () { if (!window.confirm('Удалить контракт?')) return; rpc('app_service_contract_delete', { p_token: token, p_id: b.dataset.kdel }).then(function (d) { var r = d && d[0]; msg('#refMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); loadRefs(); }); }); });
  }
  function warrForm(w) {
    w = w || {};
    ui.formDialog({ title: w.id ? 'Гарантия' : 'Новая гарантия', okText: 'Сохранить', size: 'lg', fields: [
      { name: 'equipment_id', label: 'Оборудование *', type: 'select', options: eq.map(function (e) { return { value: e.id, label: e.name }; }) },
      { name: 'customer_id', label: 'Заказчик', type: 'select', options: [{ value: '', label: '— нет —' }].concat(customers.map(function (c) { return { value: c.id, label: c.name }; })) },
      { name: 'number', label: 'Номер', type: 'text' },
      { name: 'provider', label: 'Поставщик', type: 'select', options: [{ value: 'manufacturer', label: 'Производитель' }, { value: 'dealer', label: 'Дилер' }, { value: 'internal', label: 'Внутренняя' }] },
      { name: 'start_date', label: 'Начало', type: 'date' },
      { name: 'end_date', label: 'Окончание', type: 'date' },
      { name: 'coverage', label: 'Покрытие', type: 'text' },
      { name: 'terms', label: 'Условия', type: 'textarea', rows: 2 },
      { name: 'active', label: 'Активна', type: 'checkbox' }
    ], values: { equipment_id: w.equipment_id || '', customer_id: w.customer_id || '', number: w.number || '', provider: w.provider || 'manufacturer', start_date: w.start_date ? String(w.start_date).slice(0, 10) : new Date().toISOString().slice(0, 10), end_date: w.end_date ? String(w.end_date).slice(0, 10) : '', coverage: w.coverage || '', terms: w.terms || '', active: (w.id ? w.active : true) ? 'да' : '' } })
      .then(function (v) { if (!v) return;
        rpc('app_warranty_save', { p_token: token, p_id: w.id || null, p_equipment_id: v.equipment_id || null, p_customer_id: v.customer_id || null, p_number: v.number, p_provider: v.provider, p_start_date: v.start_date || null, p_end_date: v.end_date || null, p_coverage: v.coverage, p_terms: v.terms, p_active: !!v.active })
          .then(function (d) { var r = d && d[0]; msg('#refMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) loadRefs(); });
      });
  }
  function conForm(k) {
    k = k || {};
    ui.formDialog({ title: k.id ? 'Контракт' : 'Новый контракт', okText: 'Сохранить', size: 'lg', fields: [
      { name: 'customer_id', label: 'Заказчик *', type: 'select', options: customers.map(function (c) { return { value: c.id, label: c.name }; }) },
      { name: 'number', label: 'Номер', type: 'text' },
      { name: 'kind', label: 'Тип', type: 'select', options: [{ value: 'sla', label: 'SLA' }, { value: 'service', label: 'Сервис' }, { value: 'extended_warranty', label: 'Расширенная гарантия' }] },
      { name: 'start_date', label: 'Начало', type: 'date' },
      { name: 'end_date', label: 'Окончание', type: 'date' },
      { name: 'response_sla_min', label: 'Реакция, мин', type: 'text' },
      { name: 'resolve_sla_min', label: 'Решение, мин', type: 'text' },
      { name: 'cost', label: 'Стоимость, ₽', type: 'text' },
      { name: 'terms', label: 'Условия', type: 'textarea', rows: 2 },
      { name: 'active', label: 'Активен', type: 'checkbox' }
    ], values: { customer_id: k.customer_id || '', number: k.number || '', kind: k.kind || 'sla', start_date: k.start_date ? String(k.start_date).slice(0, 10) : new Date().toISOString().slice(0, 10), end_date: k.end_date ? String(k.end_date).slice(0, 10) : '', response_sla_min: k.response_sla_min != null ? String(k.response_sla_min) : '', resolve_sla_min: k.resolve_sla_min != null ? String(k.resolve_sla_min) : '', cost: k.cost != null ? String(k.cost) : '', terms: k.terms || '', active: (k.id ? k.active : true) ? 'да' : '' } })
      .then(function (v) { if (!v) return;
        var rmin = parseInt(v.response_sla_min, 10), smin = parseInt(v.resolve_sla_min, 10), cst = parseFloat(String(v.cost || '').replace(',', '.'));
        rpc('app_service_contract_save', { p_token: token, p_id: k.id || null, p_customer_id: v.customer_id || null, p_number: v.number, p_kind: v.kind, p_start_date: v.start_date || null, p_end_date: v.end_date || null, p_response_sla_min: isNaN(rmin) ? null : rmin, p_resolve_sla_min: isNaN(smin) ? null : smin, p_cost: isNaN(cst) ? null : cst, p_terms: v.terms, p_active: !!v.active })
          .then(function (d) { var r = d && d[0]; msg('#refMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) loadRefs(); });
      });
  }

  /* ---------- Правила IIoT и загрузка инженеров ---------- */
  var iotRules = [];
  function loadRules() {
    rpc('app_service_iot_rules_list', { p_token: token }).then(function (r) {
      iotRules = r || [];
      $('#ruleList').innerHTML = iotRules.length ? '<table class="tbl"><thead><tr><th>Метрика</th><th>Условие</th><th>Приоритет</th><th>Вид</th><th>Статус</th><th></th></tr></thead><tbody>' +
        iotRules.map(function (x) { return '<tr><td><b>' + esc(x.metric) + '</b></td><td>' + esc(x.op) + ' ' + num(x.threshold) + '</td><td>' + (PRIO[x.priority] || x.priority) + '</td>' +
          '<td>' + (KIND[x.kind] || x.kind) + '</td><td><span class="badge ' + (x.active ? 'done' : 'cancelled') + '">' + (x.active ? 'активно' : 'выкл') + '</span></td>' +
          '<td style="white-space:nowrap;"><button class="act" data-redit="' + x.id + '">Изменить</button><button class="act danger" data-rdel="' + x.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Правил нет.</span>';
      $$('#ruleList [data-redit]').forEach(function (b) { b.addEventListener('click', function () { ruleForm(iotRules.filter(function (x) { return x.id === b.dataset.redit; })[0]); }); });
      $$('#ruleList [data-rdel]').forEach(function (b) { b.addEventListener('click', function () { if (!window.confirm('Удалить правило?')) return; rpc('app_service_iot_rule_delete', { p_token: token, p_id: b.dataset.rdel }).then(function (d) { var r2 = d && d[0]; msg('#refMsg', r2 ? r2.message : '', r2 && r2.ok ? 'ok' : 'err'); loadRules(); }); }); });
    }).catch(function () { $('#ruleList').innerHTML = '<span class="note">Недоступно.</span>'; });
  }
  function ruleForm(x) {
    x = x || {};
    ui.formDialog({ title: x.id ? 'Правило IIoT' : 'Новое правило IIoT', okText: 'Сохранить', fields: [
      { name: 'metric', label: 'Метрика', type: 'text', required: true, placeholder: 'temperature' },
      { name: 'op', label: 'Оператор', type: 'select', options: [{ value: '>=', label: '>=' }, { value: '>', label: '>' }] },
      { name: 'threshold', label: 'Порог', type: 'text', required: true, value: '1' },
      { name: 'priority', label: 'Приоритет', type: 'select', options: [{ value: 'low', label: 'Низкий' }, { value: 'normal', label: 'Обычный' }, { value: 'high', label: 'Высокий' }, { value: 'critical', label: 'Критичный' }] },
      { name: 'kind', label: 'Вид заявки', type: 'select', options: [{ value: 'repair', label: 'Ремонт' }, { value: 'service', label: 'Сервис' }] },
      { name: 'active', label: 'Активно', type: 'checkbox' }
    ], values: { metric: x.metric || '', op: x.op || '>=', threshold: x.threshold != null ? String(x.threshold) : '1', priority: x.priority || 'critical', kind: x.kind || 'repair', active: (x.id ? x.active : true) ? 'да' : '' } })
      .then(function (v) { if (!v) return; var th = parseFloat(String(v.threshold).replace(',', '.'));
        rpc('app_service_iot_rule_save', { p_token: token, p_id: x.id || null, p_metric: v.metric, p_op: v.op, p_threshold: isNaN(th) ? 1 : th, p_priority: v.priority, p_kind: v.kind, p_active: !!v.active })
          .then(function (d) { var r = d && d[0]; msg('#refMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) loadRules(); });
      });
  }
  function loadEngineerLoad(sel) {
    sel = sel || '#loadList';
    rpc('app_service_engineer_load', { p_token: token }).then(function (r) {
      r = r || [];
      $(sel).innerHTML = r.length ? '<table class="tbl"><thead><tr><th>Инженер</th><th class="num">Выездов</th><th class="num">Заявок</th></tr></thead><tbody>' +
        r.map(function (x) { return '<tr><td>' + esc(x.engineer) + '</td><td class="num">' + num(x.open_visits) + '</td><td class="num">' + num(x.open_requests) + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Активных выездов нет.</span>';
    }).catch(function () { $(sel).innerHTML = '<span class="note">Недоступно.</span>'; });
  }

  /* ---------- Акт (печать) ---------- */
  function openAct() {
    if (!cur) return;
    rpc('app_service_act', { p_token: token, p_id: cur.id }).then(function (r) {
      var a = (r || [])[0]; if (!a) { msg('#iMsg', 'Нет данных акта', 'err'); return; }
      var w = window.open('', '_blank');
      if (!w) { msg('#iMsg', 'Разрешите всплывающие окна', 'err'); return; }
      var rows = [
        ['Номер', a.number], ['Заказчик', a.customer || '—'], ['Оборудование', a.equipment || '—'],
        ['Тема', a.title || ''], ['Инженер', a.engineer || '—'],
        ['Создана', fmtTs(a.reported_at)], ['Выполнена', fmtTs(a.resolved_at)],
        ['Работы', a.works || ''], ['Решение', a.solution || ''], ['Запчасти', a.parts || '—'],
        ['Стоимость работ', money(a.cost)], ['Стоимость запчастей', money(a.parts_cost)]
      ];
      w.document.write('<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>Акт ' + esc(a.number) + '</title>' +
        '<style>body{font-family:Segoe UI,Roboto,sans-serif;padding:28px;color:#0f172a}h1{font-size:18px}table{width:100%;border-collapse:collapse;margin-top:14px}td{padding:8px;border:1px solid #cbd5e1;font-size:14px}td:first-child{width:180px;color:#475569;background:#f8fafc}.sig{margin-top:36px;display:flex;justify-content:space-between}.sig div{border-top:1px solid #94a3b8;padding-top:6px;width:45%}</style></head><body>' +
        '<h1>Акт выполненных работ — ' + esc(a.number) + '</h1><table>' +
        rows.map(function (row) { return '<tr><td>' + esc(row[0]) + '</td><td>' + esc(row[1] == null ? '—' : String(row[1])) + '</td></tr>'; }).join('') +
        '</table><div class="sig"><div>Исполнитель</div><div>Заказчик</div></div>' +
        '<p style="margin-top:20px;color:#64748b;font-size:12px">3DMP Service · сервис и ремонт · сформировано ' + new Date().toLocaleString('ru-RU') + '</p>' +
        '<script>window.print()</' + 'script></body></html>');
      w.document.close();
    }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  $('#myBtn').addEventListener('click', function () { go('s-visits'); });
  $('#refBtn').addEventListener('click', function () { go('s-refs'); });
  $('#ruleAdd').addEventListener('click', function () { ruleForm(null); });
  $('#actBtn').addEventListener('click', openAct);

  /* ---------- Отчёт PDF ---------- */
  function reportPdf() {
    if (!window.AppExport) { msg('#listMsg', 'Экспорт недоступен', 'err'); return; }
    rpc('app_service_report', { p_token: token, p_from: null, p_to: null }).then(function (rows) {
      rows = rows || [];
      var total = rows.length, open = rows.filter(function (r) { return r.status !== 'done' && r.status !== 'cancelled'; }).length;
      var done = rows.filter(function (r) { return r.status === 'done'; }).length;
      var sum = rows.reduce(function (s, r) { return s + num(r.total); }, 0);
      var cols = [
        { key: 'number', label: 'Номер' }, { key: 'reported_at', label: 'Создана', value: function (r) { return fmtTs(r.reported_at); } },
        { key: 'customer', label: 'Заказчик' }, { key: 'equipment', label: 'Оборудование' }, { key: 'title', label: 'Тема' },
        { key: 'priority', label: 'Приоритет', value: function (r) { return PRIO[r.priority] || r.priority; } },
        { key: 'status', label: 'Статус', value: function (r) { return ST[r.status] || r.status; } },
        { key: 'resolved_at', label: 'Выполнена', value: function (r) { return fmtTs(r.resolved_at); } },
        { key: 'total', label: 'Сумма, ₽', num: true, value: function (r) { return money(r.total); } }
      ];
      var html = AppExport.reportDocument({
        brand: '3DMP Service', title: 'Отчёт по сервису и ремонту', subtitle: 'за последние 90 дней',
        meta: [{ k: 'Сформирован', v: new Date().toLocaleString('ru-RU') }],
        kpis: [{ label: 'Заявок', value: total }, { label: 'Открытых', value: open }, { label: 'Выполнено', value: done }, { label: 'Сумма', value: money(sum) }],
        sections: [{ title: 'Заявки', columns: cols, rows: rows }],
        sign: ['Руководитель сервиса', 'Главный инженер'], footer: '3DMP Service · сервис и ремонт'
      });
      AppExport.exportPdf('Сервис — отчёт', html);
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Заявка на снабжение ---------- */
  function supplyForm() {
    if (!cur) return;
    ui.formDialog({ title: 'Заявка на снабжение (ремонт)', okText: 'Создать', fields: [
      { name: 'material', label: 'Материал/запчасть', type: 'text', required: true, placeholder: 'Подшипник 6205' },
      { name: 'qty', label: 'Количество', type: 'text', value: '1' },
      { name: 'note', label: 'Примечание', type: 'text' }
    ] }).then(function (v) { if (!v) return; var q = parseFloat(String(v.qty).replace(',', '.'));
      rpc('app_service_supply_request', { p_token: token, p_id: cur.id, p_material: v.material, p_qty: isNaN(q) ? 1 : q, p_note: v.note || null })
        .then(function (d) { var r = d && d[0]; msg('#iMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('Снабжение', v.material); loadDetail(cur.id); } });
    });
  }

  /* ---------- Завершение работы и проблемы (инженер) ---------- */
  function pnum(v) { var n = parseFloat(String(v == null ? '' : v).replace(',', '.')); return isNaN(n) ? null : n; }
  function completeForm() {
    if (!cur) return;
    ui.formDialog({ title: 'Завершить работу', okText: 'Завершить и закрыть', size: 'lg', fields: [
      { name: 'works', label: 'Работы', type: 'text', value: cur.works || '' },
      { name: 'solution', label: 'Решение / результат *', type: 'textarea', rows: 3, required: true },
      { name: 'labor_hours', label: 'Трудозатраты, ч', type: 'text' },
      { name: 'downtime_hours', label: 'Простой, ч', type: 'text' },
      { name: 'cost', label: 'Стоимость работ, ₽', type: 'text', value: cur.cost != null ? String(cur.cost) : '' }
    ] }).then(function (v) { if (!v) return;
      rpc('app_service_complete', { p_token: token, p_id: cur.id, p_works: v.works, p_solution: v.solution, p_labor_hours: pnum(v.labor_hours), p_downtime_hours: pnum(v.downtime_hours), p_cost: pnum(v.cost) })
        .then(function (d) { var r = d && d[0]; msg('#iMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('Сервис завершение', cur.number); if (window.AppNotify) window.AppNotify.refresh(true); load().then(function () { openItem(cur.id); }); } });
    });
  }
  function escalateForm() {
    if (!cur) return;
    ui.formDialog({ title: 'Эскалация в проблему', okText: 'Создать проблему', fields: [{ name: 'note', label: 'Описание проблемы', type: 'textarea', rows: 3, required: true }] })
      .then(function (v) { if (!v) return;
        rpc('app_service_escalate', { p_token: token, p_id: cur.id, p_note: v.note })
          .then(function (d) { var r = d && d[0]; msg('#iMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('Сервис проблема', cur.number); loadDetail(cur.id); } });
      });
  }
  /* ---------- Процессный подход ---------- */
  var PROCESS = [
    { t: 'План ТО/ППР', role: 'Главный инженер / ТОиР', text: 'Планы ТО по периодичности и норме наработки; при просрочке — автозаявка.', where: 'apps/maintenance · apps/service → «🛠 ППР → заявки»' },
    { t: 'Обнаружение', role: 'Оператор / рабочий', text: 'Станок загудел (шпиндель), ошибка ALM 401. Оператор фиксирует останов.', where: 'apps/terminal · apps/iiot (показания, авто-тикет)' },
    { t: 'Заявка', role: 'Оператор / Диспетчер', text: 'Создаётся заявка SRV- или авто-тикет IIoT по правилу порога (приоритет, SLA).', where: 'apps/service → «＋ Заявка» / «⚙ IIoT → заявки»' },
    { t: 'Диспетчеризация', role: 'Диспетчер (manager)', text: 'Проверка гарантии (WR-) и контракта (SC-, SLA), назначение инженера и выезда.', where: 'apps/service → «Назначить выезд»' },
    { t: 'Выезд и диагностика', role: 'Сервисный инженер (master)', text: 'Открывает карточку: заказчик, станок, место, контакт, код ошибки; диагностика.', where: 'apps/service → «Выезды» → карточка' },
    { t: 'Запчасти', role: 'Инженер + Склад', text: 'Резерв запчастей под заявку; при нехватке — заявка на снабжение.', where: 'apps/service → «Запчасти», «📦 Снабжение» → apps/procurement' },
    { t: 'Закупка', role: 'Снабжение (supply)', text: 'Тендер/закупка запчастей, контроль срока и поставки.', where: 'apps/procurement · apps/warehouse' },
    { t: 'Ремонт', role: 'Сервисный инженер', text: 'Работы, замена, калибровка; фиксация трудозатрат и простоя.', where: 'apps/service → «✅ Завершить с отчётом»' },
    { t: 'Отчёт и акт', role: 'Инженер / Руководитель сервиса', text: 'Решение, акт выполненных работ, паспорт станка, событие в ERP.', where: 'apps/service → «Акт», «Паспорт станка»; apps/integrations' },
    { t: 'Гарантия и оплата', role: 'Гарантийный отдел / Финансы', text: 'Сопоставление с гарантией или контрактом; счёт/затраты.', where: 'apps/service → «Гарантии/контракты»; apps/economics' },
    { t: 'Контроль SLA', role: 'Система / Руководство', text: 'Просрочка SLA → событие, уведомление директору/руководителю; для критичных — проблема.', where: 'apps/service → «🔔 Проверить SLA»; apps/issues' },
    { t: 'Контроль KPI', role: 'Руководитель предприятия / Главный инженер', text: 'SLA, MTTR, MTBF, FTFR, CSAT, затраты; отчёты PDF.', where: 'apps/service → «KPI и отчёты»; apps/bi' }
  ];
  function renderProcess() {
    $('#procFlow').innerHTML = PROCESS.map(function (s, i) {
      return '<div class="card" style="margin:8px 0;border-left:4px solid var(--accent,#10b981);">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;"><span class="badge">' + (i + 1) + '</span><b>' + esc(s.t) + '</b>' +
        '<span class="badge" style="margin-left:auto;">' + esc(s.role) + '</span></div>' +
        '<div style="font-size:.84rem;margin-top:6px;">' + esc(s.text) + '</div>' +
        '<div class="note" style="margin-top:4px;">📍 ' + esc(s.where) + '</div></div>';
    }).join('');
  }
  function processPdf() {
    if (!window.AppExport) return;
    var rows = PROCESS.map(function (s, i) { return { n: i + 1, t: s.t, role: s.role, what: s.text, where: s.where }; });
    AppExport.exportPdf('Сервис — процесс', AppExport.reportDocument({
      brand: '3DMP Service', title: 'Процессный подход: сервис и ремонт ЧПУ', subtitle: 'сквозной процесс от рабочего до директора',
      sections: [{ title: 'Цепочка процесса', columns: [{ key: 'n', label: '№' }, { key: 't', label: 'Этап' }, { key: 'role', label: 'Роль' }, { key: 'what', label: 'Действие' }, { key: 'where', label: 'Где в системе' }], rows: rows }],
      footer: '3DMP Service · процесс сервиса'
    }));
  }

  /* ---------- Печать заявки ---------- */
  function printRequest() {
    if (!cur || !window.AppExport) return;
    Promise.all([
      rpc('app_service_get', { p_token: token, p_id: cur.id }),
      rpc('app_service_history_list', { p_token: token, p_id: cur.id }).catch(function () { return []; }),
      rpc('app_service_visit_list', { p_token: token, p_id: cur.id }).catch(function () { return []; }),
      rpc('app_service_parts_list', { p_token: token, p_id: cur.id }).catch(function () { return []; })
    ]).then(function (r) {
      var d = (r[0] || [])[0]; if (!d) return;
      var hist = r[1] || [], visits = r[2] || [], parts = r[3] || [];
      var info = [
        ['Номер', d.number], ['Статус', ST[d.status] || d.status], ['Приоритет', PRIO[d.priority] || d.priority],
        ['Заказчик', d.customer || '—'], ['Оборудование', d.equipment || '—'], ['Место', d.location || '—'], ['Контакт', d.contact || '—'],
        ['Код ошибки', d.fault_code || '—'], ['Гарантия', d.warranty_number || 'нет'], ['Контракт', d.contract_number || '—'],
        ['Инженер', d.assigned_login || d.engineer || '—'], ['Создана', fmtTs(d.reported_at || d.created_at)],
        ['Реакция до', fmtTs(d.response_due)], ['Решение до', fmtTs(d.resolve_due)], ['Решена', fmtTs(d.resolved_at)],
        ['Работы', d.works || '—'], ['Решение', d.solution || '—'],
        ['Стоимость работ', money(d.cost)], ['Стоимость запчастей', money(d.parts_cost)]
      ].map(function (x) { return { k: x[0], v: x[1] == null || x[1] === '' ? '—' : String(x[1]) }; });
      AppExport.exportPdf('Заявка ' + d.number, AppExport.reportDocument({
        brand: '3DMP Service', title: 'Сервисная заявка ' + d.number, subtitle: d.title || '',
        meta: [{ k: 'Сформирована', v: new Date().toLocaleString('ru-RU') }],
        sections: [
          { title: 'Сведения', columns: [{ key: 'k', label: 'Параметр' }, { key: 'v', label: 'Значение' }], rows: info },
          { title: 'Выезды', columns: [{ key: 'e', label: 'Инженер' }, { key: 's', label: 'Статус', value: function (v) { return VST[v.status] || v.status; } }, { key: 'p', label: 'План', value: function (v) { return fmtTs(v.planned_at); } }, { key: 'r', label: 'Отчёт' }], rows: visits.map(function (v) { return { e: v.engineer || '—', s: v.status, p: v.planned_at, r: v.work_report || '' }; }) },
          { title: 'Запчасти', columns: [{ key: 'part', label: 'Запчасть' }, { key: 'qty', label: 'Кол-во', num: true }, { key: 'price', label: 'Цена', num: true }], rows: parts },
          { title: 'История', columns: [{ key: 'ts', label: 'Время', value: function (h) { return fmtTs(h.created_at); } }, { key: 'by', label: 'Кто' }, { key: 't', label: 'Событие' }], rows: hist.map(function (h) { return { ts: h.created_at, by: h.by_login || '', t: h.text || h.kind }; }) }
        ],
        sign: ['Исполнитель', 'Заказчик'], footer: '3DMP Service · сервисная заявка'
      }));
    });
  }

  /* ---------- Спецификация ---------- */
  function specPdf() {
    if (!cur || !window.AppExport) return;
    rpc('app_service_spec', { p_token: token, p_id: cur.id }).then(function (rows) {
      rows = rows || [];
      var total = rows.reduce(function (s, r) { return s + num(r.cost); }, 0);
      AppExport.exportPdf('Спецификация ' + (cur.number || ''), AppExport.reportDocument({
        brand: '3DMP Service', title: 'Спецификация к заявке ' + (cur.number || ''), subtitle: cur.title || '',
        kpis: [{ label: 'Позиций', value: rows.length }, { label: 'Итого', value: money(total) }],
        sections: [{ title: 'Состав', columns: [
          { key: 'kind', label: 'Тип', value: function (r) { return r.kind === 'part' ? 'Запчасть' : 'Работа'; } },
          { key: 'name', label: 'Наименование' }, { key: 'qty', label: 'Кол-во', num: true },
          { key: 'price', label: 'Цена', num: true, value: function (r) { return r.price != null ? money(r.price) : '—'; } },
          { key: 'cost', label: 'Стоимость', num: true, value: function (r) { return money(r.cost); } }
        ], rows: rows }],
        sign: ['Исполнитель', 'Заказчик'], footer: '3DMP Service · спецификация'
      }));
    }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Паспорт нового станка с выезда ---------- */
  function newEqForm() {
    if (!cur) return;
    ui.formDialog({ title: 'Новый станок — цифровой паспорт', okText: 'Создать и привязать', size: 'lg', fields: [
      { name: 'name', label: 'Название станка *', type: 'text', required: true, placeholder: 'DMG MORI NHX 5000' },
      { name: 'code', label: 'Инв. номер', type: 'text' },
      { name: 'kind', label: 'Тип', type: 'select', options: [{ value: 'frezerny', label: 'Фрезерный' }, { value: 'tokarny', label: 'Токарный' }, { value: 'lazer', label: 'Лазерный' }, { value: 'sverlilny', label: 'Сверлильный' }, { value: 'shlifovalny', label: 'Шлифовальный' }, { value: 'edm', label: 'Электроэрозионный' }, { value: 'sborka', label: 'Сборка' }] },
      { name: 'model', label: 'Модель', type: 'text' },
      { name: 'dept', label: 'Подразделение/цех', type: 'text' },
      { name: 'warranty_number', label: 'Гарантия №', type: 'text' },
      { name: 'warranty_end', label: 'Гарантия до', type: 'date' }
    ] }).then(function (v) { if (!v) return;
      rpc('app_service_equipment_create', { p_token: token, p_name: v.name, p_code: v.code, p_kind: v.kind, p_model: v.model, p_dept: v.dept, p_customer_id: cur.customer_id || null, p_warranty_number: v.warranty_number, p_warranty_end: v.warranty_end || null })
        .then(function (d) { var r = d && d[0]; if (!r || !r.ok) { msg('#iMsg', r ? r.message : 'Ошибка', 'err'); return; }
          rpc('app_service_equipment_link', { p_token: token, p_id: cur.id, p_equipment_id: r.equipment_id })
            .then(function () { window.Auth.log('Паспорт станка', v.name); msg('#iMsg', 'Паспорт станка создан и привязан', 'ok'); load().then(function () { openItem(cur.id); }); });
        }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
    });
  }

  /* ---------- Шаблоны ---------- */
  var templates = [];
  function loadTemplates() {
    rpc('app_service_templates_list', { p_token: token }).then(function (r) { templates = r || []; renderTpl(); }).catch(function () { $('#tplList').innerHTML = '<span class="note">Недоступно.</span>'; });
  }
  var TKIND = { checklist: 'Чек-лист', works: 'Работы', act: 'Акт', note: 'Заметка' };
  function renderTpl() {
    $('#tplList').innerHTML = templates.length ? '<table class="tbl"><thead><tr><th>Тип</th><th>Название</th><th></th></tr></thead><tbody>' +
      templates.map(function (t) { return '<tr><td><span class="badge">' + (TKIND[t.kind] || t.kind) + '</span></td><td><b>' + esc(t.title) + '</b><div class="note">' + esc(String(t.body || '').replace(/\n/g, ' · ').slice(0, 100)) + '</div></td>' +
        '<td><button class="act danger" data-tdel="' + t.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Шаблонов нет.</span>';
    $$('#tplList [data-tdel]').forEach(function (b) { b.addEventListener('click', function () { if (!window.confirm('Удалить шаблон?')) return; rpc('app_service_template_delete', { p_token: token, p_id: b.dataset.tdel }).then(function (d) { var r = d && d[0]; msg('#refMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); loadTemplates(); }); }); });
  }
  function tplForm() {
    ui.formDialog({ title: 'Новый шаблон', okText: 'Сохранить', size: 'lg', fields: [
      { name: 'kind', label: 'Тип', type: 'select', options: [{ value: 'checklist', label: 'Чек-лист' }, { value: 'works', label: 'Работы' }, { value: 'act', label: 'Акт' }, { value: 'note', label: 'Заметка' }] },
      { name: 'title', label: 'Название', type: 'text', required: true },
      { name: 'body', label: 'Содержание (по строке на пункт)', type: 'textarea', rows: 5 }
    ] }).then(function (v) { if (!v) return;
      rpc('app_service_template_save', { p_token: token, p_id: null, p_kind: v.kind, p_title: v.title, p_body: v.body, p_active: true })
        .then(function (d) { var r = d && d[0]; msg('#refMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) loadTemplates(); });
    });
  }
  function templateApply() {
    if (!cur) return;
    var go2 = function () {
      if (!templates.length) { msg('#iMsg', 'Нет шаблонов', 'err'); return; }
      ui.formDialog({ title: 'Применить шаблон', okText: 'Добавить в историю', size: 'lg', fields: [
        { name: 'tpl', label: 'Шаблон', type: 'select', options: templates.map(function (t) { return { value: t.id, label: '(' + (TKIND[t.kind] || t.kind) + ') ' + t.title }; }) }
      ] }).then(function (v) { if (!v) return;
        var t = templates.filter(function (x) { return x.id === v.tpl; })[0]; if (!t) return;
        rpc('app_service_history_add', { p_token: token, p_id: cur.id, p_text: '[' + (TKIND[t.kind] || t.kind) + '] ' + t.title + '\n' + (t.body || ''), p_kind: 'comment' })
          .then(function () { window.Auth.log('Шаблон', t.title); msg('#iMsg', 'Шаблон применён', 'ok'); loadDetail(cur.id); });
      });
    };
    if (templates.length) go2(); else rpc('app_service_templates_list', { p_token: token }).then(function (r) { templates = r || []; go2(); });
  }

  function renderAccess() {
    var roles = [['admin', 'Администратор'], ['owner', 'Владелец'], ['director', 'Руководитель предприятия'], ['chief', 'Главный инженер'], ['manager', 'Диспетчер (manager)'], ['support', 'Поддержка'], ['master', 'Сервисный инженер'], ['qc', 'ОТК (qc)']];
    var cols = [['dash', 'Дашборд'], ['list', 'Заявки'], ['visits', 'Выезды'], ['refs', 'Гарантии/контракты'], ['reports', 'KPI и отчёты'], ['access', 'Матрица'], ['new', 'Создать заявку'], ['edit', 'Статус/отчёт'], ['assign', 'Назначить выезд'], ['supply', 'Снабжение'], ['rules', 'Правила IIoT'], ['act', 'Акт'], ['passport', 'Паспорт станка']];
    var h = '<table class="tbl"><thead><tr><th>Роль</th>' + cols.map(function (c) { return '<th>' + c[1] + '</th>'; }).join('') + '</tr></thead><tbody>';
    roles.forEach(function (rw) {
      var caps = capsFor(rw[0]);
      h += '<tr><td><b>' + rw[1] + '</b><br><span class="note">' + rw[0] + '</span></td>' + cols.map(function (c) { return '<td style="text-align:center;">' + (caps[c[0]] ? '✅' : '—') + '</td>'; }).join('') + '</tr>';
    });
    $('#accessMatrix').innerHTML = h + '</tbody></table>';
  }

  /* ---------- Цифровой паспорт станка ---------- */
  var passportData = null;
  function openPassport() {
    if (!cur || !cur.equipment_id) { msg('#iMsg', 'У заявки не указано оборудование', 'err'); return; }
    rpc('app_equipment_passport', { p_token: token, p_equipment_id: cur.equipment_id }).then(function (r) {
      var p = (r || [])[0]; if (!p) { msg('#iMsg', 'Паспорт не найден', 'err'); return; }
      passportData = p;
      $('#passport').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;"><span class="badge">' + esc(p.kind) + '</span>' +
        '<span class="badge ' + (p.status === 'active' ? 'done' : 'cancelled') + '">' + esc(p.status) + '</span>' +
        '<b style="margin-left:auto;">' + esc(p.code || '') + '</b></div>' +
        '<h1 style="font-size:1.15rem;margin:10px 0;">🪪 ' + esc(p.name) + '</h1>' + kv('Модель', p.model) + kv('Подразделение', p.dept) + kv('Стоимость часа', p.cost_hour != null ? money(p.cost_hour) : null) +
        '<div class="stat-div"></div>' +
        '<div class="kpi-row">' + cell('Заявок', num(p.requests_total)) + cell('Открытых', num(p.requests_open), num(p.requests_open) ? '#b45309' : '') + cell('Выполнено', num(p.requests_done)) + cell('MTBF, ч', p.mtbf_hours != null ? num(p.mtbf_hours) : '—') + cell('MTTR, ч', p.mttr_hours != null ? num(p.mttr_hours) : '—') + '</div>' +
        kv('Гарантия', p.warranty_number ? p.warranty_number + ' до ' + (p.warranty_end || '—') : null) +
        kv('Последний ремонт', fmtTs(p.last_repair)) +
        kv('Планов ТОиР', p.plans != null ? String(p.plans) : null) + kv('Последнее ТО', p.last_plan_kind ? (p.last_plan_kind + ' · ' + (p.last_plan_date || '')) : null) +
        kv('Телеметрия', p.iiot_last_metric ? (p.iiot_last_metric + ' = ' + num(p.iiot_last_value) + ' · ' + fmtTs(p.iiot_last_ts)) : 'нет данных');
      screens.go('s-eq');
    }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
    function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }
  }
  function passportPdf() {
    if (!passportData || !window.AppExport) { msg('#iMsg', 'Нет данных', 'err'); return; }
    var p = passportData;
    var html = AppExport.reportDocument({
      brand: '3DMP Service', title: 'Цифровой паспорт станка', subtitle: p.name,
      meta: [{ k: 'Код', v: p.code || '—' }, { k: 'Модель', v: p.model || '—' }, { k: 'Подразделение', v: p.dept || '—' }, { k: 'Сформирован', v: new Date().toLocaleString('ru-RU') }],
      kpis: [{ label: 'Заявок', value: num(p.requests_total) }, { label: 'Открытых', value: num(p.requests_open) }, { label: 'Выполнено', value: num(p.requests_done) }, { label: 'MTBF, ч', value: p.mtbf_hours != null ? num(p.mtbf_hours) : '—' }, { label: 'MTTR, ч', value: p.mttr_hours != null ? num(p.mttr_hours) : '—' }],
      sections: [{ title: 'Сведения', columns: [{ key: 'k', label: 'Параметр' }, { key: 'v', label: 'Значение' }], rows: [
        { k: 'Гарантия', v: p.warranty_number ? p.warranty_number + ' до ' + (p.warranty_end || '—') : '—' },
        { k: 'Последний ремонт', v: fmtTs(p.last_repair) },
        { k: 'Планов ТОиР', v: p.plans != null ? String(p.plans) : '—' },
        { k: 'Последнее ТО', v: p.last_plan_kind ? (p.last_plan_kind + ' · ' + (p.last_plan_date || '')) : '—' },
        { k: 'Телеметрия', v: p.iiot_last_metric ? (p.iiot_last_metric + ' = ' + num(p.iiot_last_value) + ' · ' + fmtTs(p.iiot_last_ts)) : 'нет данных' }
      ] }],
      sign: ['Главный инженер', 'Начальник цеха'], footer: '3DMP Service · цифровой паспорт станка'
    });
    AppExport.exportPdf('Паспорт станка', html);
  }

  $('#reportBtn').addEventListener('click', reportPdf);
  $('#supplyBtn').addEventListener('click', supplyForm);
  $('#completeBtn').addEventListener('click', completeForm);
  $('#issueBtn').addEventListener('click', escalateForm);
  $('#printBtn').addEventListener('click', printRequest);
  $('#procPdf').addEventListener('click', processPdf);
  $('#specBtn').addEventListener('click', specPdf);
  $('#newEqBtn').addEventListener('click', newEqForm);
  $('#tplBtn').addEventListener('click', templateApply);
  $('#tplAdd').addEventListener('click', tplForm);
  function runScan(sel, name) {
    rpc(name, { p_token: token }).then(function (d) {
      var r = d && d[0];
      msg(sel, r ? r.message : 'Готово', 'ok');
      if (r && (num(r.created) > 0 || num(r.escalated) > 0)) { if (window.AppNotify) window.AppNotify.refresh(true); load(); }
    }).catch(function (e) { msg(sel, 'Ошибка: ' + e.message, 'err'); });
  }
  $('#slaBtn').addEventListener('click', function () { runScan('#dashMsg', 'app_service_sla_scan'); });
  $('#pprBtn').addEventListener('click', function () { runScan('#dashMsg', 'app_service_ppr_scan'); });
  $('#pprBtn2').addEventListener('click', function () { runScan('#listMsg', 'app_service_ppr_scan'); });
  $('#vq').addEventListener('input', function () { vq = this.value; renderVisits(); });
  $('#passportBtn').addEventListener('click', openPassport);
  $('#passportPdf').addEventListener('click', passportPdf);
  $('#backE').addEventListener('click', function () { if (cur) screens.go('s-item'); else go('s-list'); });
  $('#warrAdd').addEventListener('click', function () { warrForm(null); });
  $('#conAdd').addEventListener('click', function () { conForm(null); });
  $('#partAdd').addEventListener('click', partForm);

  $('#backBtn').addEventListener('click', function () { cur = null; load(); go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  window.addEventListener('online', function () { setTimeout(load, 1200); });

  /* ---------- Дашборд ---------- */
  function renderDash() {
    var k = lastK, ke = lastKe;
    var open = list.filter(function (r) { return r.status !== 'done' && r.status !== 'cancelled'; });
    $('#dashKpis').innerHTML = kpi('Открытых', open.length, open.length ? '#92400e' : '') +
      kpi('Критичных', num(k.critical), num(k.critical) ? '#b91c1c' : '') +
      kpi('Просрочено SLA', num(k.overdue_sla), num(k.overdue_sla) ? '#b91c1c' : '') +
      kpi('MTTR, ч', k.mttr_hours != null ? num(k.mttr_hours) : '—') +
      kpi('MTBF, ч', ke.mtbf_hours != null ? num(ke.mtbf_hours) : '—') +
      kpi('FTFR, %', k.ftfr_pct != null ? num(k.ftfr_pct) : '—') +
      kpi('Активных выездов', num(ke.active_visits)) + kpi('Затраты', money(k.cost_sum));
    var act = open.slice().sort(function (a, b) {
      var pa = a.priority === 'critical' ? 0 : a.priority === 'high' ? 1 : 2, pb = b.priority === 'critical' ? 0 : b.priority === 'high' ? 1 : 2;
      return pa - pb;
    }).slice(0, 6);
    $('#dashActive').innerHTML = act.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>№</th><th>Станок</th><th>Тема</th><th>Приоритет</th><th>Статус</th><th>Инженер</th><th>SLA</th></tr></thead><tbody>' +
      act.map(function (r) { return '<tr data-id="' + r.id + '" style="cursor:pointer;"><td><b>' + esc(r.number) + '</b></td><td>' + esc(r.equipment || '—') + '</td><td>' + esc(r.title || '') + '</td>' +
        '<td>' + prioBadge(r.priority) + '</td><td>' + (ST[r.status] || r.status) + '</td><td>' + esc(r.assigned_login || r.engineer || '—') + '</td>' +
        '<td>' + (r.sla_state === 'overdue' ? '<span class="badge sla-overdue">просрочен</span>' : r.sla_state === 'warn' ? '<span class="badge sla-warn">истекает</span>' : '<span class="badge sla-ok">норма</span>') + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Открытых заявок нет.</span>';
    $$('#dashActive tr[data-id]').forEach(function (tr) { tr.addEventListener('click', function () { openItem(tr.dataset.id); }); });
    loadEngineerLoad('#dashLoad');
    rpc('app_spare_parts_list', { p_token: token }).then(function (ps) {
      var low = (ps || []).filter(function (p) { return p.low; });
      $('#dashParts').innerHTML = low.length ? low.map(function (p) { return '<div class="kvr"><b>' + esc(p.name) + '</b><span class="note" style="margin-left:auto;">' + num(p.qty) + ' / мин ' + num(p.min_qty) + '</span></div>'; }).join('') : '<span class="note">Все позиции в норме.</span>';
    }).catch(function () { $('#dashParts').innerHTML = '<span class="note">—</span>'; });
    $('#dashHistory').innerHTML = list.slice(0, 6).map(function (r) {
      return '<div class="tl-item"><div class="note">' + fmtTs(r.reported_at || r.created_at) + ' · ' + esc(r.number) + '</div><div>' + esc(r.title || '') + ' — ' + (ST[r.status] || r.status) + '</div></div>';
    }).join('') || '<span class="note">Событий нет.</span>';
  }

  /* ---------- KPI и отчёты ---------- */
  var reportRows = [];
  function repCols() {
    return [
      { key: 'number', label: 'Номер' }, { key: 'reported_at', label: 'Создана', value: function (r) { return fmtTs(r.reported_at); } },
      { key: 'customer', label: 'Заказчик' }, { key: 'equipment', label: 'Оборудование' }, { key: 'title', label: 'Тема' },
      { key: 'priority', label: 'Приоритет', value: function (r) { return PRIO[r.priority] || r.priority; } },
      { key: 'status', label: 'Статус', value: function (r) { return ST[r.status] || r.status; } },
      { key: 'resolved_at', label: 'Выполнена', value: function (r) { return fmtTs(r.resolved_at); } },
      { key: 'total', label: 'Сумма, ₽', num: true, value: function (r) { return money(r.total); } }
    ];
  }
  function reportHtml() {
    var rows = reportRows;
    var total = rows.length, open = rows.filter(function (r) { return r.status !== 'done' && r.status !== 'cancelled'; }).length;
    var done = rows.filter(function (r) { return r.status === 'done'; }).length;
    var sum = rows.reduce(function (s, r) { return s + num(r.total); }, 0);
    return AppExport.reportDocument({
      brand: '3DMP Service', title: 'Отчёт по сервису и ремонту', subtitle: ($('#repFrom').value || '—') + ' — ' + ($('#repTo').value || '—'),
      meta: [{ k: 'Сформирован', v: new Date().toLocaleString('ru-RU') }],
      kpis: [{ label: 'Заявок', value: total }, { label: 'Открытых', value: open }, { label: 'Выполнено', value: done }, { label: 'Сумма', value: money(sum) }],
      sections: [{ title: 'Заявки', columns: repCols(), rows: rows }],
      sign: ['Руководитель сервиса', 'Главный инженер'], footer: '3DMP Service · сервис и ремонт'
    });
  }
  function loadReports() {
    if (!$('#repFrom').value) $('#repFrom').value = new Date(Date.now() - 90 * 864e5).toISOString().slice(0, 10);
    if (!$('#repTo').value) $('#repTo').value = new Date().toISOString().slice(0, 10);
    rpc('app_service_report', { p_token: token, p_from: $('#repFrom').value || null, p_to: $('#repTo').value || null }).then(function (rows) {
      reportRows = rows || [];
      var total = reportRows.length, open = reportRows.filter(function (r) { return r.status !== 'done' && r.status !== 'cancelled'; }).length;
      var done = reportRows.filter(function (r) { return r.status === 'done'; }).length;
      var sum = reportRows.reduce(function (s, r) { return s + num(r.total); }, 0);
      $('#repKpis').innerHTML = kpi('Заявок', total) + kpi('Открытых', open) + kpi('Выполнено', done) + kpi('Сумма', money(sum));
      $('#repTable').innerHTML = reportRows.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Номер</th><th>Создана</th><th>Заказчик</th><th>Оборудование</th><th>Тема</th><th>Приоритет</th><th>Статус</th><th class="num">Сумма</th></tr></thead><tbody>' +
        reportRows.map(function (r) { return '<tr><td><b>' + esc(r.number) + '</b></td><td class="muted">' + fmtTs(r.reported_at) + '</td><td>' + esc(r.customer || '') + '</td><td>' + esc(r.equipment || '') + '</td>' +
          '<td>' + esc(r.title || '') + '</td><td>' + prioBadge(r.priority) + '</td><td>' + (ST[r.status] || r.status) + '</td><td class="num">' + money(r.total) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Нет заявок за период.</span>';
    }).catch(function (e) { msg('#repMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b || !b.dataset.go) return; go(b.dataset.go);
  });
  $('#repFrom').addEventListener('change', loadReports);
  $('#repTo').addEventListener('change', loadReports);
  $('#repPdf').addEventListener('click', function () { if (window.AppExport) AppExport.exportPdf('Сервис — отчёт', reportHtml()); });
  $('#repDoc').addEventListener('click', function () { if (window.AppExport) AppExport.exportDoc('Сервис — отчёт', 'Отчёт по сервису и ремонту', reportHtml()); });
  $('#repCsv').addEventListener('click', function () { if (window.AppExport) AppExport.exportCsv('service-report', repCols(), reportRows); });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    applyCaps();
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
    var land = can('dash') ? 's-dash' : (can('list') ? 's-list' : (can('visits') ? 's-visits' : 's-dash'));
    setActiveTab(land); screens.go(land);
  });
})();
