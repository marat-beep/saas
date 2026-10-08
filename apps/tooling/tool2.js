/* ============================================================
   3DMP Service · apps/tooling/tool2.js — Инструментальное хозяйство 2.0 (W13, 0158).
   Экземпляры, каталог, инвентаризация, оснащение по техкартам.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, toolLife = [], places = [], routes = [], steps = [], items = [], catalog = [];

  var ISTAT = { on_stock: 'На складе', issued: 'Выдан', on_machine: 'На станке', worn: 'Изношен', scrapped: 'Списан' };
  var ICLS = { on_stock: 'done', issued: 'in_progress', on_machine: '', worn: '', scrapped: 'cancelled' };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); if (!e) return; e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dt(v) { return v ? new Date(v).toLocaleString('ru-RU') : '—'; }
  function opt(list, v, l) { return list.map(function (x) { return { value: x[v], label: x[l] }; }); }

  function showTab(scr) {
    $$('#t2tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.t2scr').forEach(function (s) { s.classList.toggle('active', s.id === 't2-' + scr); });
    if (scr === 'items') loadItems();
    if (scr === 'catalog') loadCatalog();
    if (scr === 'inv') loadInv();
    if (scr === 'route') loadRoutes();
  }
  $$('#t2tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  /* ---------- Экземпляры ---------- */
  function loadRefs() {
    return Promise.all([
      rpc('app_tool_life_list', { p_token: token, p_q: null }).catch(function () { return []; }),
      rpc('app_wh_address_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) { toolLife = r[0] || []; places = r[1] || []; });
  }
  function loadItems() {
    return Promise.all([
      rpc('app_tool_items_kpi', { p_token: token }).catch(function () { return []; }),
      rpc('app_tool_item_list', { p_token: token, p_status: null, p_q: null }).catch(function () { return []; })
    ]).then(function (r) {
      var k = (r[0] && r[0][0]) || {}; items = r[1] || [];
      $('#t2kpi').innerHTML = cell('Всего экз.', k.total || 0) + cell('На складе', k.on_stock || 0) + cell('Выдано', k.issued || 0) + cell('На станках', k.on_machine || 0) + cell('Изношено', k.worn || 0) + cell('Списано', k.scrapped || 0);
      $('#t2items').innerHTML = items.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Инструмент</th><th>Серийный</th><th>Статус</th><th>Место</th><th>Станок</th><th>Наработка</th><th>Действия</th></tr></thead><tbody>' +
        items.map(function (i) {
          var pct = Number(i.pct) || 0;
          return '<tr><td><b>' + esc(i.tool || '—') + '</b></td><td>' + esc(i.serial || '—') + '</td>' +
            '<td><span class="badge ' + (ICLS[i.status] || '') + '">' + esc(ISTAT[i.status] || i.status) + '</span></td>' +
            '<td class="muted">' + esc(i.location || '—') + '</td><td>' + esc(i.machine || '—') + '</td>' +
            '<td class="num">' + (i.used_min || 0) + (i.resource_min ? ' / ' + i.resource_min : '') + (i.pct != null ? ' (' + pct + '%)' : '') + '</td>' +
            '<td style="white-space:nowrap;">' +
              '<button class="act" data-op="issue" data-id="' + i.id + '">Выдать</button>' +
              '<button class="act" data-op="install" data-id="' + i.id + '">На станок</button>' +
              '<button class="act" data-op="return" data-id="' + i.id + '">Вернуть</button>' +
              '<button class="act" data-hist="' + i.id + '">История</button>' +
              '<button class="act danger" data-op="scrap" data-id="' + i.id + '">Списать</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Экземпляров нет — добавьте.</span>';
      $$('#t2items [data-op]').forEach(function (b) { b.addEventListener('click', function () { op(b.dataset.id, b.dataset.op, b); }); });
      $$('#t2items [data-hist]').forEach(function (b) { b.addEventListener('click', function () { history(b.dataset.hist); }); });
    }).catch(function (e) { msg('#t2m', 'Ошибка: ' + e.message, 'err'); });
  }
  function op(id, kind, btn) {
    function doIt(machine, naryad, used) { rpc('app_tool_event', { p_token: token, p_item_id: id, p_kind: kind, p_machine: machine || null, p_naryad_id: null, p_location_id: null, p_used_min: used || null, p_note: null }).then(function (r) { var x = r && r[0]; msg('#t2m', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadItems(); }); }
    if (kind === 'install') ui.formDialog({ title: 'Установка на станок', okText: 'Установить', fields: [{ name: 'machine', label: 'Станок', type: 'text', required: true }, { name: 'used', label: 'Наработка, мин', type: 'number' }], values: {} }).then(function (v) { if (v) doIt(v.machine, null, v.used ? Number(v.used) : null); });
    else if (kind === 'scrap') { if (confirm('Списать экземпляр?')) doIt(); }
    else doIt();
  }
  function history(id) {
    rpc('app_tool_events_list', { p_token: token, p_item_id: id }).then(function (r) {
      var rows = (r || []).map(function (e) { return '<tr><td>' + dt(e.created_at) + '</td><td>' + esc(e.kind) + '</td><td>' + esc(e.machine || '') + '</td><td>' + esc(e.holder_login || '') + '</td><td class="num">' + (e.used_min != null ? e.used_min : '') + '</td><td class="muted">' + esc(e.note || '') + '</td></tr>'; }).join('');
      ui.dialog({ title: 'История экземпляра', body: '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Когда</th><th>Операция</th><th>Станок</th><th>Ответственный</th><th>Мин</th><th>Примечание</th></tr></thead><tbody>' + (rows || '<tr><td colspan="6" class="note">Нет записей</td></tr>') + '</tbody></table></div>', html: true, cancelText: 'Закрыть' });
    });
  }
  function addItem() {
    ui.formDialog({
      title: 'Новый экземпляр инструмента', okText: 'Создать', fields: [
        { name: 'tool_life_id', label: 'Инструмент', type: 'select', options: toolLife.map(function (t) { return { value: t.id, label: (t.name || '') + ' ' + (t.code || '') }; }), required: true },
        { name: 'serial', label: 'Серийный/метка', type: 'text', required: true },
        { name: 'location_id', label: 'Место хранения', type: 'select', options: [{ value: '', label: '—' }].concat(places.map(function (p) { return { value: p.id, label: p.code }; })) },
        { name: 'resource_min', label: 'Ресурс, мин', type: 'number' }
      ], values: {}
    }).then(function (v) {
      if (!v) return;
      rpc('app_tool_item_save', { p_token: token, p_id: null, p_tool_life_id: v.tool_life_id, p_serial: v.serial, p_location_id: v.location_id || null, p_resource_min: v.resource_min ? Number(v.resource_min) : null, p_note: null })
        .then(function (r) { var x = r && r[0]; msg('#t2m', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadItems(); });
    });
  }

  /* ---------- Каталог ---------- */
  function loadCatalog() {
    return rpc('app_tool_catalog_list', { p_token: token, p_q: null, p_type: null }).then(function (r) {
      catalog = r || [];
      $('#t2cat').innerHTML = catalog.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Производитель</th><th>Код</th><th>Название</th><th>Тип</th><th>Материал</th><th class="num">Ø</th><th>Аналоги</th><th></th></tr></thead><tbody>' +
        catalog.map(function (c) {
          var an = Array.isArray(c.analogs) ? c.analogs.map(function (a) { return (a.vendor || '') + ' ' + (a.code || ''); }).join('; ') : '';
          return '<tr><td>' + esc(c.vendor || '—') + '</td><td>' + esc(c.vendor_code || '') + '</td><td><b>' + esc(c.name) + '</b></td><td>' + esc(c.tool_type || '') + '</td><td>' + esc(c.material || '') + '</td><td class="num">' + (c.diameter != null ? c.diameter : '') + '</td><td class="muted">' + esc(an) + '</td><td><button class="act" data-cedit="' + c.id + '">Изменить</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Каталог пуст.</span>';
      $$('#t2cat [data-cedit]').forEach(function (b) { b.addEventListener('click', function () { catForm(catalog.filter(function (x) { return x.id === b.dataset.cedit; })[0]); }); });
    }).catch(function (e) { msg('#t2m', 'Ошибка: ' + e.message, 'err'); });
  }
  function catForm(c) {
    c = c || {};
    ui.formDialog({
      title: c.id ? 'Позиция каталога' : 'Новая позиция каталога', okText: 'Сохранить', fields: [
        { name: 'vendor', label: 'Производитель', type: 'text' }, { name: 'vendor_code', label: 'Код', type: 'text' },
        { name: 'name', label: 'Название', type: 'text', required: true }, { name: 'tool_type', label: 'Тип', type: 'text' },
        { name: 'material', label: 'Материал', type: 'text' }, { name: 'coating', label: 'Покрытие', type: 'text' },
        { name: 'diameter', label: 'Диаметр', type: 'number' }, { name: 'analogs', label: 'Аналоги (JSON)', type: 'textarea', rows: 2 }
      ],
      values: { vendor: c.vendor || '', vendor_code: c.vendor_code || '', name: c.name || '', tool_type: c.tool_type || '', material: c.material || '', coating: c.coating || '', diameter: c.diameter != null ? c.diameter : '', analogs: JSON.stringify(c.analogs || [], null, 0) }
    }).then(function (v) {
      if (!v) return;
      var an; try { an = JSON.parse(v.analogs || '[]'); } catch (e) { msg('#t2m', 'Некорректный JSON аналогов', 'err'); return; }
      rpc('app_tool_catalog_save', { p_token: token, p_id: c.id || null, p_vendor: v.vendor || null, p_vendor_code: v.vendor_code || null, p_name: v.name, p_tool_type: v.tool_type || null, p_material: v.material || null, p_coating: v.coating || null, p_diameter: v.diameter ? Number(v.diameter) : null, p_geometry: null, p_analogs: an, p_note: null })
        .then(function (r) { var x = r && r[0]; msg('#t2m', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadCatalog(); });
    });
  }

  /* ---------- Инвентаризация ---------- */
  function loadInv() {
    return rpc('app_tool_inventory_list', { p_token: token }).then(function (r) {
      var list = r || [];
      $('#t2inv').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Дата</th><th>Статус</th><th>Автор</th><th class="num">Проверено</th><th class="num">Не найдено</th><th></th></tr></thead><tbody>' +
        list.map(function (s) {
          return '<tr><td>' + dt(s.created_at) + '</td><td>' + (s.status === 'open' ? 'Открыта' : 'Закрыта') + '</td><td class="muted">' + esc(s.created_login || '') + '</td><td class="num">' + s.lines + '</td><td class="num">' + s.not_found + '</td>' +
            '<td><button class="act" data-iopen="' + s.id + '">Открыть</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Инвентаризаций нет.</span>';
      $$('#t2inv [data-iopen]').forEach(function (b) { b.addEventListener('click', function () { invOpen(b.dataset.iopen); }); });
    }).catch(function (e) { msg('#t2m', 'Ошибка: ' + e.message, 'err'); });
  }
  function invStart() { rpc('app_tool_inventory_start', { p_token: token, p_note: null }).then(function (r) { var x = r && r[0]; msg('#t2m', x ? x.message : '', 'ok'); loadInv(); }); }
  function invOpen(sid) {
    $('#t2invPanel').innerHTML = '<div class="toolbar"><input class="search" id="t2scanCode" placeholder="Серийный/метка…" style="flex:1;min-width:180px;"><button class="btn" id="t2scanBtn" style="width:auto;padding:8px 14px;">Отметить</button><button class="btn secondary" id="t2closeBtn" style="width:auto;padding:8px 14px;">Закрыть сессию</button></div><div class="msg" id="t2scanMsg"></div><div id="t2scanList" class="mt"></div>';
    function refresh() { rpc('app_tool_inventory_report', { p_token: token, p_session_id: sid }).then(function (r) { var rows = r || []; $('#t2scanList').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Инструмент</th><th>Серийный</th><th>Было</th><th>Стало</th><th>Результат</th><th>Когда</th></tr></thead><tbody>' + rows.map(function (l) { return '<tr><td>' + esc(l.item || '—') + '</td><td>' + esc(l.serial || '') + '</td><td>' + esc(l.expected_status || '') + '</td><td>' + esc(l.found_status || '') + '</td><td>' + esc(l.result) + '</td><td class="muted">' + dt(l.checked_at) + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Отметок нет.</span>'; }); }
    refresh();
    $('#t2scanBtn').addEventListener('click', function () { var code = $('#t2scanCode').value; if (!code) return; rpc('app_tool_inventory_scan', { p_token: token, p_session_id: sid, p_code: code, p_location_id: null, p_status: null }).then(function (r) { var x = r && r[0]; msg('#t2scanMsg', x ? x.message : '', x && x.result === 'not_found' ? 'err' : 'ok'); $('#t2scanCode').value = ''; refresh(); }); });
    $('#t2closeBtn').addEventListener('click', function () { rpc('app_tool_inventory_close', { p_token: token, p_session_id: sid }).then(function (r) { var x = r && r[0]; msg('#t2m', x ? x.message : '', 'ok'); $('#t2invPanel').innerHTML = ''; loadInv(); }); });
  }

  /* ---------- Оснащение по техкартам ---------- */
  function loadRoutes() {
    return rpc('app_route_list', { p_token: token }).then(function (r) { routes = r || []; $('#t2routeSel').innerHTML = routes.map(function (x) { return '<option value="' + x.id + '">' + esc((x.number || '') + ' ' + (x.name || '')) + '</option>'; }).join('') || '<option value="">— нет маршрутов —</option>'; if (routes[0]) loadSteps(routes[0].id); })
      .catch(function (e) { msg('#t2m', 'Ошибка: ' + e.message, 'err'); });
  }
  function loadSteps(rid) {
    return rpc('app_route_steps_list', { p_token: token, p_id: rid }).then(function (r) {
      steps = r || [];
      $('#t2stepSel').innerHTML = steps.map(function (s) { return '<option value="' + s.id + '">' + esc('№' + (s.seq != null ? s.seq : '') + ' ' + (s.operation || '')) + '</option>'; }).join('') || '<option value="">— нет операций —</option>';
      if (steps[0]) loadRouteTools(steps[0].id); else $('#t2rtools').innerHTML = '<span class="note">Выберите операцию.</span>';
    });
  }
  function loadRouteTools(stepId) {
    return rpc('app_route_tool_list', { p_token: token, p_route_step_id: stepId }).then(function (r) {
      var list = r || [];
      $('#t2rtools').innerHTML = list.length ? '<table class="mini"><thead><tr><th>Инструмент</th><th class="num">Кол-во</th><th class="num">На складе</th><th>Примечание</th><th></th></tr></thead><tbody>' +
        list.map(function (x) { return '<tr><td><b>' + esc(x.tool || '—') + '</b></td><td class="num">' + x.qty + '</td><td class="num">' + x.on_stock + '</td><td class="muted">' + esc(x.note || '') + '</td><td><button class="act danger" data-rdel="' + x.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Оснащение не задано.</span>';
      $$('#t2rtools [data-rdel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_route_tool_delete', { p_token: token, p_id: b.dataset.rdel }).then(function () { loadRouteTools(stepId); }); }); });
    });
  }
  function addRouteTool() {
    var stepId = $('#t2stepSel').value; if (!stepId) { msg('#t2m', 'Выберите операцию.', 'err'); return; }
    ui.formDialog({ title: 'Оснащение операции', okText: 'Добавить', fields: [
      { name: 'tool_life_id', label: 'Инструмент', type: 'select', options: toolLife.map(function (t) { return { value: t.id, label: (t.name || '') + ' ' + (t.code || '') }; }), required: true },
      { name: 'qty', label: 'Кол-во', type: 'number' }, { name: 'note', label: 'Примечание', type: 'text' }
    ], values: { qty: 1 } }).then(function (v) {
      if (!v) return;
      rpc('app_route_tool_save', { p_token: token, p_id: null, p_route_step_id: stepId, p_tool_life_id: v.tool_life_id, p_qty: v.qty ? Number(v.qty) : 1, p_note: v.note || null }).then(function (r) { var x = r && r[0]; msg('#t2m', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadRouteTools(stepId); });
    });
  }

  /* ---------- init ---------- */
  $('#t2add').addEventListener('click', addItem);
  $('#t2addCat').addEventListener('click', function () { catForm(null); });
  $('#t2invStart').addEventListener('click', invStart);
  $('#t2routeSel').addEventListener('change', function () { loadSteps(this.value); });
  $('#t2stepSel').addEventListener('change', function () { loadRouteTools(this.value); });
  $('#t2addRt').addEventListener('click', addRouteTool);

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    token = s.token;
    if (!SB) { msg('#t2m', 'Supabase не подключён.', 'err'); return; }
    loadRefs().then(function () { showTab('items'); });
  });
})();
