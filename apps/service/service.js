/* ============================================================
   3DMP Service · apps/service — Сервис и ремонт ЧПУ (S1, миграция 0122)
   Заявки SRV v2: приоритет/SLA, гарантия, история, выезды, KPI, IIoT-автотикеты.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, list = [], customers = [], eq = [], cur = null, filter = '', q = '';

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

  function load() {
    return Promise.all([
      rpc('app_service_list', { p_token: token, p_q: null }),
      rpc('app_service_kpi', { p_token: token }),
      rpc('app_customer_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_equipment_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; var k = (r[1] && r[1][0]) || {}; customers = r[2] || []; eq = r[3] || [];
      $('#kpis').innerHTML = cell('Открытых', num(k.open), num(k.open) ? '#92400e' : '') +
        cell('Критичных', num(k.critical), num(k.critical) ? '#b91c1c' : '') +
        cell('Просрочено SLA', num(k.overdue_sla), num(k.overdue_sla) ? '#b91c1c' : '') +
        cell('MTTR, ч', k.mttr_hours != null ? num(k.mttr_hours) : '—') +
        cell('FTFR, %', k.ftfr_pct != null ? num(k.ftfr_pct) : '—') +
        cell('Затраты', money(k.cost_sum));
      render();
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
        kv('Решена', fmtTs(d.resolved_at)) + kv('Затраты', money(d.cost)) + kv('Работы', d.works) + kv('Примечание', d.note);
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
      bindVisits();
    }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function bindVisits() {
    $$('#visits [data-vst]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_service_visit_status', { p_token: token, p_visit_id: b.dataset.vid, p_status: b.dataset.vst, p_report: null })
          .then(function () { window.Auth.log('Сервис выезд', b.dataset.vst); if (window.AppNotify) window.AppNotify.refresh(true); load(); })
          .catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
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
    rpc('app_service_set_status', { p_token: token, p_id: cur.id, p_status: $('#stSel').value, p_note: $('#stNote').value.trim() })
      .then(function (d) { var r = d && d[0]; msg('#iMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('Сервис статус', $('#stSel').value); if (window.AppNotify) window.AppNotify.refresh(true); load(); } })
      .catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
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
  $('#backBtn').addEventListener('click', function () { cur = null; load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  window.addEventListener('online', function () { setTimeout(load, 1200); });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
