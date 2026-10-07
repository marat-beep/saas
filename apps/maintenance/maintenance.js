/* ============================================================
   3DMP Service · apps/maintenance — ТОиР (обслуживание и ремонт)
   Планы ТО/ППР, регистрация работ, история, KPI. Данные: 0052.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, plans = [], log = [], eq = [], pq = '', rq = '';

  var KINDS = { to1: 'ТО-1', to2: 'ТО-2', to3: 'ТО-3', ppr: 'ППР', repair: 'Ремонт', service: 'Сервис' };
  var STAT = { ok: 'в норме', due: 'истекает', overdue: 'просрочено', none: 'нет даты' };
  var SBADGE = { ok: 'done', due: 'in_progress', overdue: 'cancelled', none: '' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return num(v).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_mnt_plans_list', { p_token: token, p_q: null }),
      rpc('app_mnt_log_list', { p_token: token, p_q: null }),
      rpc('app_mnt_kpi', { p_token: token }),
      rpc('app_equipment_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      plans = r[0] || []; log = r[1] || []; var k = (r[2] && r[2][0]) || {}; eq = r[3] || [];
      var eo = '<option value="">— выберите —</option>' + eq.map(function (e) { return '<option value="' + e.id + '">' + esc(e.name) + '</option>'; }).join('');
      $('#pEq').innerHTML = eo; $('#rEq').innerHTML = eo;
      $('#kpis').innerHTML = cell('Планов', num(k.plans_total)) + cell('Истекает (30 дн.)', num(k.due), k.due ? '#92400e' : '') +
        cell('Просрочено', num(k.overdue), k.overdue ? '#b91c1c' : '') + cell('Выполнено за месяц', num(k.done_month)) +
        cell('Затраты за месяц', money(k.cost_month));
      renderPlans(); renderLog();
    }).catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function renderPlans() {
    var list = plans.filter(function (p) { if (!pq) return true; var s = pq.toLowerCase(); return [p.equipment, p.title, p.responsible].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#plansCnt').textContent = '(' + list.length + ')';
    $('#plans').innerHTML = list.length ? list.map(function (p) {
      var dl = p.days_left;
      var hint = dl == null ? '' : (dl < 0 ? 'просрочено ' + (-dl) + ' дн.' : 'через ' + dl + ' дн.');
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + (SBADGE[p.status] || '') + '">' + (STAT[p.status] || p.status) + '</span>' +
        '<span class="badge">' + (KINDS[p.kind] || p.kind) + '</span>' +
        '<b>' + esc(p.equipment || '—') + '</b>' +
        '<span class="note" style="margin-left:auto;">' + (p.title ? esc(p.title) + ' · ' : '') + 'след.: ' + fmt(p.next_due) + (hint ? ' (' + hint + ')' : '') + '</span></div>' +
        '<div style="font-size:.78rem;color:var(--muted);margin-top:5px;">' +
        (p.period_days ? 'период ' + p.period_days + ' дн. · ' : '') + (p.responsible ? '👤 ' + esc(p.responsible) + ' · ' : '') + 'последнее: ' + fmt(p.last_done) + '</div>' +
        '<div class="toolbar wrap mt" data-cap="edit"><button class="btn secondary" data-reg="' + p.id + '" data-eq="' + (p.equipment_id || '') + '" data-kind="' + (p.kind || '') + '" style="width:auto;padding:8px 14px;">Зарегистрировать работу</button>' +
        '<button class="btn secondary" data-srv="' + p.id + '" style="width:auto;padding:8px 14px;" title="Создать заявку сервиса по этому плану">→ Сервис</button>' +
        '<a class="btn secondary" href="../service/index.html" style="width:auto;padding:8px 14px;">Сервис ↗</a></div></div>';
    }).join('') : '<span class="note">Планов нет.</span>';
    $$('#plans [data-srv]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_mnt_plan_service_request', { p_token: token, p_plan_id: b.dataset.srv }).then(function (d) {
          var r = d && d[0]; msg('#pMsg', r ? r.message : '', r && r.ok ? 'ok' : 'err');
          if (r && r.ok && window.AppNotify) window.AppNotify.refresh(true);
        }).catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
      });
    });
    $$('#plans [data-reg]').forEach(function (b) {
      b.addEventListener('click', function () {
        $('#rEq').value = b.dataset.eq || ''; $('#rKind').value = b.dataset.kind || 'to1';
        $('#rDate').value = new Date().toISOString().slice(0, 10);
        $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x.dataset.t === 'log'); });
        $('#t-plans').style.display = 'none'; $('#t-log').style.display = '';
        window.scrollTo(0, 0);
      });
    });
  }
  function renderLog() {
    var list = log.filter(function (l) { if (!rq) return true; var s = rq.toLowerCase(); return [l.equipment, l.works, l.executor].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#log').innerHTML = '<table class="tab" style="width:100%;border-collapse:collapse"><thead><tr><th>Дата</th><th>Оборудование</th><th>Вид</th><th>Работы</th><th>Заменено</th><th>Исполнитель</th><th>Стоимость</th><th>Запчасти</th></tr></thead><tbody>' +
      (list.length ? list.map(function (l) {
        return '<tr style="border-bottom:1px solid var(--border)"><td>' + fmt(l.work_date) + '</td><td><b>' + esc(l.equipment || '—') + '</b></td>' +
          '<td>' + (KINDS[l.kind] || l.kind || '') + '</td><td>' + esc(l.works || '') + '</td><td>' + esc(l.replaced || '') + '</td>' +
          '<td>' + esc(l.executor || '') + '</td><td>' + money(l.cost) + '</td>' +
          '<td><button class="act" data-parts="' + l.id + '">Запчасти</button></td></tr>';
      }).join('') : '<tr><td colspan="8"><span class="note">Записей нет.</span></td></tr>') + '</tbody></table>';
    $$('#log [data-parts]').forEach(function (b) { b.addEventListener('click', function () { partsDialog(b.dataset.parts); }); });
  }

  /* ---------- Запчасти ТОиР ---------- */
  var spare = [], spq = '';
  function loadSpare() { return rpc('app_spare_parts_list', { p_token: token }).then(function (r) { spare = r || []; renderSpare(); }).catch(function () {}); }
  function renderSpare() {
    var list = spare.filter(function (p) { if (!spq) return true; return [p.name, p.code].join(' ').toLowerCase().indexOf(spq.toLowerCase()) >= 0; });
    $('#spareCnt').textContent = '(' + list.length + ')';
    $('#spareList').innerHTML = list.length ? '<table class="tbl"><thead><tr><th>Название</th><th>Код</th><th class="num">Остаток</th><th class="num">Мин.</th><th class="num">Цена</th><th class="num">Стоимость</th><th></th></tr></thead><tbody>' +
      list.map(function (p) { return '<tr><td><b>' + esc(p.name) + '</b>' + (p.low ? ' <span class="badge cancelled">нехватка</span>' : '') + '</td><td class="muted">' + esc(p.code || '') + '</td>' +
        '<td class="num">' + num(p.qty) + ' ' + esc(p.unit || '') + '</td><td class="num">' + num(p.min_qty) + '</td><td class="num">' + money(p.price) + '</td><td class="num">' + money(p.value) + '</td>' +
        '<td style="white-space:nowrap;"><button class="act" data-mov="' + p.id + '">Движение</button><button class="act danger" data-spdel="' + p.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Запчастей нет.</span>';
    $$('#spareList [data-mov]').forEach(function (b) {
      b.addEventListener('click', function () {
        var p = spare.filter(function (x) { return x.id === b.dataset.mov; })[0]; if (!p) return;
        ui.formDialog({ title: 'Движение запчасти', okText: 'Провести', fields: [
          { name: 'kind', label: 'Тип', type: 'select', options: [{ value: 'in', label: 'Приход' }, { value: 'out', label: 'Расход' }] },
          { name: 'qty', label: 'Количество (остаток ' + num(p.qty) + ')', type: 'text', required: true }
        ] }).then(function (v) { if (!v) return; var q = parseFloat(String(v.qty).replace(',', '.')); if (isNaN(q) || q <= 0) { msg('#spMsg', 'Некорректное количество', 'err'); return; }
          rpc('app_spare_part_move', { p_token: token, p_part_id: p.id, p_kind: v.kind, p_qty: q, p_note: null }).then(function (r) { var x = r && r[0]; msg('#spMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { window.Auth.log('Движение запчасти', p.name); loadSpare(); } }); });
      });
    });
    $$('#spareList [data-spdel]').forEach(function (b) {
      b.addEventListener('click', function () { if (!window.confirm('Удалить запчасть?')) return;
        rpc('app_spare_part_delete', { p_token: token, p_id: b.dataset.spdel }).then(function (r) { var x = r && r[0]; msg('#spMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadSpare(); }); });
    });
  }
  function partsDialog(logId) {
    ui.dialog({
      title: 'Запчасти по работе', okText: 'Закрыть', hideCancel: true, html: true, size: 'lg',
      body: '<div id="mpBox"><span class="note">Загрузка…</span></div>',
      onOpen: function (back) { renderMp(back, logId); }
    });
  }
  function renderMp(back, logId) {
    var box = back.querySelector('#mpBox'); if (!box) return;
    rpc('app_mnt_parts_list', { p_token: token, p_log_id: logId }).then(function (list) {
      list = list || [];
      var opts = spare.map(function (s) { return '<option value="' + s.id + '">' + esc(s.name) + ' (' + num(s.qty) + ' ' + esc(s.unit || '') + ')</option>'; }).join('');
      box.innerHTML = (list.length ? '<table class="tbl"><thead><tr><th>Запчасть</th><th class="num">Кол-во</th><th class="num">Цена</th><th class="num">Стоимость</th><th></th></tr></thead><tbody>' +
        list.map(function (x) { return '<tr><td>' + esc(x.part || '') + '</td><td class="num">' + num(x.qty) + '</td><td class="num">' + money(x.price) + '</td><td class="num">' + money(x.value) + '</td>' +
          '<td><button class="act danger" data-mprem="' + x.id + '">Убрать</button></td></tr>'; }).join('') + '</tbody></table>' : '<div class="note">Запчасти не списаны.</div>') +
        '<div class="form-grid mt"><div class="field"><label>Запчасть</label><select id="mpPart">' + (opts || '<option value="">— нет запчастей —</option>') + '</select></div>' +
        '<div class="field"><label>Количество</label><input type="text" id="mpQty" inputmode="decimal" value="1"></div>' +
        '<div class="field" style="display:flex;align-items:flex-end;"><button class="btn" id="mpAdd">Списать на работу</button></div></div>' +
        '<div class="msg" id="mpMsg"></div>';
      var add = box.querySelector('#mpAdd');
      if (add) add.addEventListener('click', function () {
        var pid = box.querySelector('#mpPart').value; var q = parseFloat((box.querySelector('#mpQty').value || '').replace(',', '.'));
        if (!pid || isNaN(q) || q <= 0) { var m = box.querySelector('#mpMsg'); m.className = 'msg show err'; m.textContent = 'Выберите запчасть и количество'; return; }
        rpc('app_mnt_part_add', { p_token: token, p_log_id: logId, p_part_id: pid, p_qty: q }).then(function (r) { var x = r && r[0]; if (!x || !x.ok) { var m2 = box.querySelector('#mpMsg'); m2.className = 'msg show err'; m2.textContent = x ? x.message : 'Ошибка'; return; }
          window.Auth.log('Списание запчасти', ''); loadSpare(); load(); renderMp(back, logId); });
      });
      $$('#mpBox [data-mprem]').forEach(function (b) {
        b.addEventListener('click', function () { rpc('app_mnt_part_remove', { p_token: token, p_id: b.dataset.mprem }).then(function () { loadSpare(); load(); renderMp(back, logId); }); });
      });
    });
  }
  function loadCost() {
    rpc('app_mnt_cost_by_equipment', { p_token: token }).then(function (list) {
      list = list || [];
      $('#costEq').innerHTML = list.length ? '<table class="tbl"><thead><tr><th>Оборудование</th><th class="num">Планов</th><th class="num">Работ</th><th class="num">Запчасти</th><th class="num">Всего</th></tr></thead><tbody>' +
        list.map(function (r) { return '<tr><td><b>' + esc(r.equipment) + '</b></td><td class="num">' + num(r.plans) + '</td><td class="num">' + num(r.works) + '</td>' +
          '<td class="num">' + money(r.parts_cost) + '</td><td class="num">' + money(r.total_cost) + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Нет затрат/планов.</span>';
    }).catch(function () { $('#costEq').innerHTML = '<span class="note">Недоступно.</span>'; });
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    $('#t-plans').style.display = (b.dataset.t === 'plans') ? '' : 'none';
    $('#t-log').style.display = (b.dataset.t === 'log') ? '' : 'none';
    $('#t-parts').style.display = (b.dataset.t === 'parts') ? '' : 'none';
    $('#t-reports').style.display = (b.dataset.t === 'reports') ? '' : 'none';
    if (b.dataset.t === 'reports') loadReports();
  });

  /* ---------- Роли (data-cap) ---------- */
  var ALL = { edit: 1 };
  var CAPS = { admin: ALL, owner: ALL, director: ALL, manager: ALL, chief: ALL, master: ALL, technologist: { edit: 1 }, qc: { edit: 1 }, default: {} };
  function can(c) { return !!(me && (CAPS[me.role] || CAPS['default'])[c]); }
  function applyCaps() { $$('[data-cap]').forEach(function (el) { var n = (el.dataset.cap || '').split('|'); if (!n.some(can)) el.style.display = 'none'; }); }

  /* ---------- Отчёты ---------- */
  var mrepRows = [];
  function mrepCols() {
    return [
      { key: 'work_date', label: 'Дата' }, { key: 'equipment', label: 'Оборудование' }, { key: 'kind', label: 'Вид', value: function (r) { return (KINDS[r.kind] || r.kind || ''); } },
      { key: 'works', label: 'Работы' }, { key: 'replaced', label: 'Заменено' }, { key: 'executor', label: 'Исполнитель' },
      { key: 'cost', label: 'Стоимость', num: true, value: function (r) { return money(r.cost); } },
      { key: 'part_cost', label: 'Запчасти', num: true, value: function (r) { return money(r.part_cost); } }
    ];
  }
  function loadReports() {
    if (!$('#mrepFrom').value) $('#mrepFrom').value = new Date(Date.now() - 90 * 864e5).toISOString().slice(0, 10);
    if (!$('#mrepTo').value) $('#mrepTo').value = new Date().toISOString().slice(0, 10);
    rpc('app_mnt_report', { p_token: token, p_from: $('#mrepFrom').value || null, p_to: $('#mrepTo').value || null }).then(function (rows) {
      mrepRows = rows || [];
      var sum = mrepRows.reduce(function (s, r) { return s + num(r.cost) + num(r.part_cost); }, 0);
      $('#mrepKinds').innerHTML = cell('Работ', mrepRows.length) + cell('Затраты', money(sum));
      $('#mrepTable').innerHTML = mrepRows.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Дата</th><th>Оборудование</th><th>Вид</th><th>Работы</th><th>Заменено</th><th>Исполнитель</th><th class="num">Стоимость</th><th class="num">Запчасти</th></tr></thead><tbody>' +
        mrepRows.map(function (r) { return '<tr><td class="muted">' + fmt(r.work_date) + '</td><td>' + esc(r.equipment || '') + '</td><td>' + (KINDS[r.kind] || r.kind || '') + '</td><td>' + esc(r.works || '') + '</td><td>' + esc(r.replaced || '') + '</td><td>' + esc(r.executor || '') + '</td><td class="num">' + money(r.cost) + '</td><td class="num">' + money(r.part_cost) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">За период работ нет.</span>';
      rpc('app_mnt_kpi_kinds', { p_token: token }).then(function (ks) {
        ks = ks || [];
        if (!ks.length) return;
        $('#mrepKinds').innerHTML += ks.map(function (k) { return cell((KINDS[k.kind] || k.kind) + '', num(k.cnt)); }).join('');
      }).catch(function () {});
    }).catch(function (e) { msg('#mrepMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function mrepHtml() {
    var sum = mrepRows.reduce(function (s, r) { return s + num(r.cost) + num(r.part_cost); }, 0);
    return AppExport.reportDocument({
      brand: '3DMP Service', title: 'Отчёт по ТОиР', subtitle: ($('#mrepFrom').value || '—') + ' — ' + ($('#mrepTo').value || '—'),
      meta: [{ k: 'Сформирован', v: new Date().toLocaleString('ru-RU') }],
      kpis: [{ label: 'Работ', value: mrepRows.length }, { label: 'Затраты', value: money(sum) }],
      sections: [{ title: 'Работы', columns: mrepCols(), rows: mrepRows }],
      sign: ['Главный инженер', 'Начальник цеха'], footer: '3DMP Service · ТОиР'
    });
  }
  $('#mrepPdf').addEventListener('click', function () { if (window.AppExport) AppExport.exportPdf('ТОиР — отчёт', mrepHtml()); });
  $('#mrepCsv').addEventListener('click', function () { if (window.AppExport) AppExport.exportCsv('toir-report', mrepCols(), mrepRows); });
  $('#mrepFrom').addEventListener('change', loadReports);
  $('#mrepTo').addEventListener('change', loadReports);
  $('#spq').addEventListener('input', function () { spq = this.value; renderSpare(); });
  $('#spAdd').addEventListener('click', function () {
    var name = $('#spName').value.trim(); if (!name) { msg('#spMsg', 'Укажите название.', 'err'); return; }
    var price = parseFloat(($('#spPrice').value || '').replace(',', '.')), qv = parseFloat(($('#spQty').value || '').replace(',', '.')), mn = parseFloat(($('#spMin').value || '').replace(',', '.'));
    rpc('app_spare_part_save', { p_token: token, p_id: null, p_code: $('#spCode').value.trim(), p_name: name, p_unit: $('#spUnit').value.trim() || 'шт', p_qty: isNaN(qv) ? 0 : qv, p_min_qty: isNaN(mn) ? 0 : mn, p_price: isNaN(price) ? 0 : price })
      .then(function (r) { var x = r && r[0]; msg('#spMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { window.Auth.log('Запчасть ТОиР', name); ['#spName', '#spCode', '#spUnit', '#spPrice', '#spQty', '#spMin'].forEach(function (s) { $(s).value = ''; }); loadSpare(); } });
  });
  $('#autoBtn').addEventListener('click', function () {
    rpc('app_mnt_auto_schedule', { p_token: token }).then(function (r) { var x = r && r[0]; msg('#autoMsg', x ? x.message : '', x && x.created > 0 ? 'ok' : 'info'); if (x && x.created > 0) { window.Auth.log('Авто-наряд ППР', 'создано ' + x.created); if (window.AppNotify) window.AppNotify.refresh(true); load(); } });
  });
  $('#pq').addEventListener('input', function () { pq = this.value; renderPlans(); });
  $('#rQ').addEventListener('input', function () { rq = this.value; renderLog(); });

  $('#pAdd').addEventListener('click', function () {
    var eid = $('#pEq').value; if (!eid) { msg('#pMsg', 'Выберите оборудование.', 'err'); return; }
    var per = parseInt(($('#pPeriod').value || '').replace(',', '.'), 10);
    var perH = parseFloat(($('#pPeriodH').value || '').replace(',', '.'));
    rpc('app_mnt_plan_save', { p_token: token, p_id: null, p_equipment_id: eid, p_kind: $('#pKind').value, p_title: $('#pTitle').value.trim(),
      p_period_days: isNaN(per) ? null : per, p_last_done: $('#pLast').value || null, p_next_due: null, p_responsible: $('#pResp').value.trim(), p_note: $('#pNote').value.trim(),
      p_period_hours: isNaN(perH) ? null : perH })
      .then(function (d) { var r = d && d[0]; msg('#pMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('План ТОиР', ''); ['#pTitle', '#pPeriod', '#pPeriodH', '#pLast', '#pResp', '#pNote'].forEach(function (s) { $(s).value = ''; }); load(); } })
      .catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#rAdd').addEventListener('click', function () {
    var eid = $('#rEq').value; if (!eid) { msg('#rMsg', 'Выберите оборудование.', 'err'); return; }
    var cost = parseFloat(($('#rCost').value || '').replace(',', '.'));
    rpc('app_mnt_register', { p_token: token, p_plan_id: null, p_equipment_id: eid, p_kind: $('#rKind').value, p_date: $('#rDate').value || null,
      p_executor: $('#rExec').value.trim(), p_cost: isNaN(cost) ? 0 : cost, p_works: $('#rWorks').value.trim(), p_replaced: $('#rRepl').value.trim(), p_note: null })
      .then(function (d) { var r = d && d[0]; msg('#rMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('ТОиР работа', $('#rWorks').value.trim()); if (window.AppNotify) window.AppNotify.refresh(true); ['#rExec', '#rCost', '#rWorks', '#rRepl'].forEach(function (s) { $(s).value = ''; }); load(); } })
      .catch(function (e) { msg('#rMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    applyCaps();
    if (!SB) { msg('#pMsg', 'Supabase не подключён.', 'err'); return; }
    load(); renderRuntime(); loadSpare(); loadCost();
  });

  function renderRuntime() {
    rpc('app_mnt_runtime_status', { p_token: token }).then(function (list) {
      list = list || [];
      if (!list.length) { $('#runtime').innerHTML = '<span class="note">Планов нет.</span>'; return; }
      var pad = { ok: 'в норме', soon: 'скоро', overdue: 'просрочено' };
      var bdg = { ok: 'done', soon: 'in_progress', overdue: 'cancelled' };
      $('#runtime').innerHTML = '<table class="tab2" style="width:100%;border-collapse:collapse"><thead><tr><th>Оборудование</th><th>Вид</th><th>Период, дн</th><th>Наработка, ч</th><th>Норма, ч</th><th>%</th><th>Следующее ТО</th><th>Статус</th></tr></thead><tbody>' +
        list.map(function (r) {
          return '<tr><td>' + esc(r.equipment) + '</td><td>' + esc(r.kind || '') + '</td><td>' + num(r.period_days) + ' дн' + (r.period_hours ? ' · ' + num(r.period_hours) + ' ч' : '') + '</td>' +
            '<td>' + num(r.run_hours) + '</td><td>' + num(r.due_hours) + '</td><td>' + (r.pct != null ? r.pct + '%' : '—') + '</td>' +
            '<td>' + fmt(r.next_due) + '</td><td><span class="badge ' + (bdg[r.status] || '') + '">' + (pad[r.status] || r.status) + '</span></td></tr>';
        }).join('') + '</tbody></table>';
    }).catch(function () { $('#runtime').innerHTML = '<span class="note">Недоступно.</span>'; });
  }
})();
