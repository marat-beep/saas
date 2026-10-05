/* ============================================================
   3DMP Service · apps/registry — справочники (master data)
   Оборудование, материалы, операции, техпроцессы (0024) и маршруты (0025).
   Маршрут: шаблон техпроцесса → нормирование → себестоимость.
   Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, eq = [], mats = [], ops = [], tps = [], routes = [], orders = [], wcs = [], refs = [];
  var curTp = null, curRoute = null, refGroup = '', refQ = '';

  var KIND = { frezerny: 'Фрезерный', tokarny: 'Токарный', lazer: 'Лазер', sverlilny: 'Сверлильный', shlifovalny: 'Шлифовальный', edm: 'Электроэрозия', sborka: 'Сборка' };
  var GRP = { steel: 'Констр. сталь', tool_steel: 'Инстр. сталь', stainless: 'Нержавеющая', bearing: 'Подшипниковая', aluminum: 'Алюминий', bronze: 'Бронза', brass: 'Латунь', copper: 'Медь', cast_iron: 'Чугун', plastic: 'Пластик', titanium: 'Титан' };
  function kLabel(k) { return KIND[k] || k; }
  function esc(v) { return ui.esc(v); }
  function num(v) { return v == null ? '' : (Number(v) || 0); }
  function fmt(v) { return (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 2 }); }
  function opt(label, val) { return '<option value="' + val + '">' + esc(label) + '</option>'; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function numInput(id) { var v = parseFloat(($(id).value || '').replace(',', '.')); return isNaN(v) ? 0 : v; }

  function load() {
    return Promise.all([
      rpc('app_equipment_list', { p_token: token }),
      rpc('app_materials_reg', { p_token: token }).catch(function () { return []; }),
      rpc('app_operations_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_process_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_route_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_wc_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_ref_material_list', { p_token: token, p_group: null, p_q: null }).catch(function () { return []; })
    ]).then(function (r) {
      eq = r[0] || []; mats = r[1] || []; ops = r[2] || []; tps = r[3] || []; routes = r[4] || []; orders = r[5] || []; wcs = r[6] || []; refs = r[7] || [];
      renderEq(); renderMat(); renderOp(); renderTp(); renderRt(); renderRef();
      $('#tpMat').innerHTML = opt('— нет —', '') + mats.map(function (m) { return opt(m.name, m.id); }).join('');
      $('#stOp').innerHTML = ops.map(function (o) { return opt(o.name + ' (' + kLabel(o.kind) + ')', o.id); }).join('');
      $('#stEq').innerHTML = opt('— не выбрано —', '') + eq.map(function (e) { return opt(e.name + ' (' + kLabel(e.kind) + ')', e.id); }).join('');
      $('#rtTpl').innerHTML = opt('— выберите —', '') + tps.map(function (t) { return opt((t.code ? t.code + ' · ' : '') + t.name + (t.material_name ? ' [' + t.material_name + ']' : ''), t.id); }).join('');
      $('#rtMatSel').innerHTML = opt('— из техпроцесса —', '') + mats.map(function (m) { return opt(m.name + (m.price ? ' · ' + fmt(m.price) + ' ₽' : ''), m.id); }).join('');
      $('#rtOrder').innerHTML = opt('— без заказа —', '') + orders.map(function (o) { return opt(o.number + ' · ' + o.title, o.id); }).join('');
      $('#rtWc').innerHTML = opt('— из маршрута —', '') + wcs.map(function (w) { return opt(w.name, w.id); }).join('');
    }).catch(function (e) { msg('#eqMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderEq() {
    $('#eqCnt').textContent = '(' + eq.length + ')';
    $('#eqList').innerHTML = '<thead><tr><th>Код</th><th>Название</th><th>Модель</th><th>Тип</th><th>Габариты</th><th>Точн.</th><th>₽/ч</th><th>Опер.</th><th>Статус</th></tr></thead><tbody>' +
      eq.map(function (e) {
        return '<tr><td>' + esc(e.code || '—') + '</td><td><b>' + esc(e.name) + '</b></td><td>' + esc(e.model || '—') + '</td>' +
          '<td><span class="b">' + kLabel(e.kind) + '</span></td>' +
          '<td>' + (e.max_x ? num(e.max_x) + '×' + num(e.max_y) + '×' + num(e.max_z) : '—') + '</td>' +
          '<td>' + (e.accuracy != null ? '±' + num(e.accuracy) : '—') + '</td><td>' + fmt(e.cost_hour) + '</td>' +
          '<td>' + e.ops_count + '</td><td>' + (e.status === 'active' ? 'работает' : e.status) + '</td></tr>';
      }).join('') + '</tbody>';
  }
  function renderMat() {
    $('#matCnt').textContent = '(' + mats.length + ')';
    $('#matList').innerHTML = '<thead><tr><th>Код</th><th>Материал</th><th>Группа</th><th>Марка</th><th>Стандарт</th><th>Плотн.</th><th>Ед.</th><th>Цена</th><th>Остаток</th></tr></thead><tbody>' +
      mats.map(function (m) {
        return '<tr><td>' + esc(m.code || '—') + '</td><td><b>' + esc(m.name) + '</b></td><td>' + esc(m.material_group || '—') + '</td>' +
          '<td>' + esc(m.grade || '—') + '</td><td>' + esc(m.standard || '—') + '</td><td>' + (m.density != null ? num(m.density) : '—') + '</td>' +
          '<td>' + esc(m.unit || '') + '</td><td>' + fmt(m.price) + '</td><td>' + num(m.qty) + '</td></tr>';
      }).join('') + '</tbody>';
  }
  function renderOp() {
    $('#opCnt').textContent = '(' + ops.length + ')';
    $('#opList').innerHTML = '<thead><tr><th>Код</th><th>Операция</th><th>Тип оборудования</th><th>Подг., мин</th><th>На ед., мин</th><th>₽/ч</th><th>Оборудования</th></tr></thead><tbody>' +
      ops.map(function (o) {
        return '<tr><td>' + esc(o.code || '—') + '</td><td><b>' + esc(o.name) + '</b></td><td><span class="b">' + kLabel(o.kind) + '</span></td>' +
          '<td>' + num(o.setup_min) + '</td><td>' + num(o.unit_min) + '</td><td>' + fmt(o.base_rate) + '</td><td>' + o.equipment_count + '</td></tr>';
      }).join('') + '</tbody>';
  }
  function renderTp() {
    $('#tpCnt').textContent = '(' + tps.length + ')';
    $('#tpList').innerHTML = '<thead><tr><th>Код</th><th>Техпроцесс</th><th>Тип изделия</th><th>Материал</th><th>Шагов</th><th></th></tr></thead><tbody>' +
      tps.map(function (t) {
        return '<tr><td>' + esc(t.code || '—') + '</td><td><b>' + esc(t.name) + '</b></td><td>' + esc(t.product_type || '—') + '</td>' +
          '<td>' + esc(t.material_name || '—') + '</td><td>' + t.steps_count + '</td>' +
          '<td><button class="act" data-open="' + t.id + '">Шаги</button></td></tr>';
      }).join('') + '</tbody>';
    $$('#tpList [data-open]').forEach(function (b) { b.addEventListener('click', function () { openTp(b.dataset.open); }); });
  }
  var RT_STATUS = { draft: 'черновик', active: 'в работе', done: 'завершён' };
  function renderRt() {
    $('#rtCnt').textContent = '(' + routes.length + ')';
    $('#rtList').innerHTML = '<thead><tr><th>№</th><th>Маршрут</th><th>Техпроцесс</th><th>Заказ</th><th>Кол-во</th><th>Шагов</th><th>Трудоёмк., мин</th><th>Себестоим., ₽</th><th>Статус</th><th></th></tr></thead><tbody>' +
      (routes.length ? routes.map(function (r) {
        return '<tr><td>' + esc(r.number || '—') + '</td><td><b>' + esc(r.name) + '</b></td><td>' + esc(r.template_name || '—') + '</td>' +
          '<td>' + esc(r.order_number || '—') + '</td><td>' + num(r.qty) + '</td><td>' + r.step_count + '</td>' +
          '<td>' + fmt(r.total_min) + '</td><td>' + fmt(r.total_cost) + '</td>' +
          '<td><span class="b">' + (RT_STATUS[r.status] || r.status) + '</span></td>' +
          '<td><button class="act" data-rt="' + r.id + '">Состав</button></td></tr>';
      }).join('') : '<tr><td colspan="10"><span class="note">Маршрутов пока нет — рассчитайте и создайте из техпроцесса.</span></td></tr>') + '</tbody>';
    $$('#rtList [data-rt]').forEach(function (b) { b.addEventListener('click', function () { openRoute(b.dataset.rt); }); });
  }

  function renderRef() {
    var list = refs.filter(function (g) {
      if (refGroup && g.group_code !== refGroup) return false;
      if (refQ) { var s = refQ.toLowerCase(); return [g.grade, g.standard, g.note].join(' ').toLowerCase().indexOf(s) >= 0; }
      return true;
    });
    $('#refCnt').textContent = '(' + list.length + ')';
    $('#refList').innerHTML = '<table class="tab"><thead><tr><th>Марка</th><th>Группа</th><th>ГОСТ</th><th>ρ, г/см³</th><th>σв, МПа</th><th>HB/HRC</th><th>₽/кг</th><th>Применение</th></tr></thead><tbody>' +
      (list.length ? list.map(function (g) {
        return '<tr><td><b>' + esc(g.grade) + '</b></td><td><span class="b">' + esc(GRP[g.group_code] || g.group_code) + '</span></td>' +
          '<td>' + esc(g.standard || '—') + '</td><td>' + num(g.density) + '</td><td>' + num(g.tensile) + '</td>' +
          '<td>' + num(g.hardness) + '</td><td>' + fmt(g.price) + '</td><td>' + esc(g.note || '') + '</td></tr>';
      }).join('') : '<tr><td colspan="8"><span class="note">Ничего не найдено.</span></td></tr>') + '</tbody></table>';
  }

  function openTp(id) {
    curTp = tps.filter(function (t) { return t.id === id; })[0] || null;
    if (!curTp) return;
    $('#tpDetail').style.display = '';
    $('#tpTitle').textContent = curTp.name;
    loadSteps();
    window.scrollTo(0, document.body.scrollHeight);
  }
  function loadSteps() {
    rpc('app_process_steps_list', { p_token: token, p_id: curTp.id }).then(function (st) {
      st = st || [];
      $('#steps').innerHTML = st.length ? st.map(function (s) {
        return '<div class="step"><div>' + s.seq + '</div><div><b>' + esc(s.operation || '—') + '</b></div><div>' + esc(s.equipment || '—') + '</div><div>' + num(s.plan_min) + ' мин</div></div>';
      }).join('') : '<span class="note">Шагов нет.</span>';
    });
  }

  /* ---------- Маршруты: расчёт и создание ---------- */
  function rtParams() {
    return {
      tpl: $('#rtTpl').value || null,
      order: $('#rtOrder').value || null,
      qty: numInput('#rtQty') || 1,
      mat: $('#rtMatSel').value || null,
      matQty: numInput('#rtMatQty'),
      name: $('#rtName').value.trim()
    };
  }
  function renderPreview(steps, cost) {
    var c = (cost && cost[0]) || { step_count: 0, total_min: 0, work_cost: 0, material_cost: 0, overhead: 0, total: 0 };
    var sum = '<div class="sum">' +
      '<div class="cell"><small>Шагов</small><b>' + c.step_count + '</b></div>' +
      '<div class="cell"><small>Трудоёмкость</small><b>' + fmt(c.total_min) + ' мин</b></div>' +
      '<div class="cell"><small>Работы</small><b>' + fmt(c.work_cost) + ' ₽</b></div>' +
      '<div class="cell"><small>Материал</small><b>' + fmt(c.material_cost) + ' ₽</b></div>' +
      '<div class="cell"><small>Итого (+15%)</small><b>' + fmt(c.total) + ' ₽</b></div>' +
      '</div>';
    var rows = (steps || []).length ? '<div class="step5" style="font-weight:600;color:var(--muted)"><div>#</div><div>Операция</div><div>Оборудование</div><div>Норма</div><div>План, мин</div><div>Стоимость, ₽</div></div>' +
      steps.map(function (s) {
        return '<div class="step5"><div>' + s.seq + '</div><div><b>' + esc(s.operation || '—') + '</b></div><div>' + esc(s.equipment || '—') + '</div>' +
          '<div><span class="b">' + esc(s.norm_source) + '</span></div><div>' + fmt(s.plan_min) + '</div><div>' + fmt(s.cost) + '</div></div>';
      }).join('') : '<div class="note">В техпроцессе нет шагов.</div>';
    $('#rtPreview').innerHTML = sum + '<div class="mt">' + rows + '</div>';
  }
  $('#rtCalc').addEventListener('click', function () {
    var p = rtParams();
    if (!p.tpl) { msg('#rtMsg', 'Выберите техпроцесс.', 'err'); return; }
    Promise.all([
      rpc('app_route_calc', { p_token: token, p_id: p.tpl, p_qty: p.qty }),
      rpc('app_route_cost', { p_token: token, p_id: p.tpl, p_qty: p.qty, p_material_id: p.mat, p_mat_qty: p.matQty })
    ]).then(function (r) { renderPreview(r[0], r[1]); msg('#rtMsg', 'Расчёт выполнен.', 'ok'); })
      .catch(function (e) { msg('#rtMsg', 'Ошибка расчёта: ' + e.message, 'err'); });
  });
  $('#rtCreate').addEventListener('click', function () {
    var p = rtParams();
    if (!p.tpl) { msg('#rtMsg', 'Выберите техпроцесс.', 'err'); return; }
    rpc('app_route_from_tpl', {
      p_token: token, p_id: p.tpl, p_order_id: p.order, p_qty: p.qty,
      p_material_id: p.mat, p_mat_qty: p.matQty, p_name: p.name || null, p_note: null
    }).then(function (d) {
      var r = d && d[0]; if (!r) { msg('#rtMsg', 'Ошибка', 'err'); return; }
      msg('#rtMsg', r.message + ': ' + r.number, 'ok');
      $('#rtName').value = '';
      load().then(function () { openRoute(r.id); });
    }).catch(function (e) { msg('#rtMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  function openRoute(id) {
    curRoute = routes.filter(function (r) { return r.id === id; })[0] || null;
    Promise.all([
      rpc('app_route_get', { p_token: token, p_id: id }),
      rpc('app_route_steps_list', { p_token: token, p_id: id }),
      rpc('app_route_naryads', { p_token: token, p_route_id: id }).catch(function () { return []; })
    ]).then(function (r) {
      var h = (r[0] && r[0][0]) || null, steps = r[1] || [], nr = r[2] || [];
      if (!h) return;
      curRoute = h;
      $('#rtDetail').style.display = '';
      $('#rtTitle').textContent = (h.number || '') + ' · ' + h.name;
      $('#rtSummary').innerHTML =
        '<div class="cell"><small>Тип</small><b>' + esc(h.template_name || '—') + '</b></div>' +
        '<div class="cell"><small>Заказ</small><b>' + esc(h.order_number || '—') + '</b></div>' +
        '<div class="cell"><small>Кол-во</small><b>' + num(h.qty) + ' шт</b></div>' +
        '<div class="cell"><small>Материал</small><b>' + esc(h.material_name || '—') + '</b></div>' +
        '<div class="cell"><small>Трудоёмкость</small><b>' + fmt(h.total_min) + ' мин</b></div>' +
        '<div class="cell"><small>Работы</small><b>' + fmt(h.work_cost) + ' ₽</b></div>' +
        '<div class="cell"><small>Материал</small><b>' + fmt(h.material_cost) + ' ₽</b></div>' +
        '<div class="cell"><small>Накладные</small><b>' + fmt(h.overhead) + ' ₽</b></div>' +
        '<div class="cell"><small>Итого</small><b>' + fmt(h.total_cost) + ' ₽</b></div>' +
        '<div class="cell"><small>Статус</small><b>' + (RT_STATUS[h.status] || h.status) + '</b></div>';
      $('#rtSteps').innerHTML = steps.length ? steps.map(function (s) {
        return '<div class="step5"><div>' + s.seq + '</div><div><b>' + esc(s.operation || '—') + '</b></div><div>' + esc(s.equipment || '—') + '</div>' +
          '<div><span class="b">' + esc(s.norm_source) + '</span></div><div>' + fmt(s.plan_min) + ' мин</div><div>' + fmt(s.cost) + ' ₽</div></div>';
      }).join('') : '<span class="note">Шагов нет.</span>';
      $('#rtNaryads').innerHTML = nr.length ? nr.map(function (n) {
        return '<div class="step"><div>' + (RT_STATUS[n.status] || n.status) + '</div><div><b>' + esc(n.number) + '</b></div>' +
          '<div>' + esc(n.assignee || '—') + '</div><div>' + fmt(n.plan_hours) + ' ч</div></div>';
      }).join('') : '<span class="note">Нарядов по маршруту нет.</span>';
      window.scrollTo(0, document.body.scrollHeight);
    }).catch(function (e) { msg('#rtDetMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  $('#rtMakeNaryad').addEventListener('click', function () {
    if (!curRoute) return;
    var wc = $('#rtWc').value || null, asg = $('#rtAssignee').value.trim();
    rpc('app_naryad_from_route', { p_token: token, p_route_id: curRoute.id, p_wc_id: wc, p_assignee: asg, p_due_date: null })
      .then(function (d) {
        var r = d && d[0]; if (!r) { msg('#rtDetMsg', 'Ошибка', 'err'); return; }
        msg('#rtDetMsg', r.message + ': ' + r.number, 'ok');
        if (window.AppNotify) window.AppNotify.refresh(true);
        load().then(function () { openRoute(curRoute.id); });
      }).catch(function (e) { msg('#rtDetMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  function setStatus(st) {
    if (!curRoute) return;
    rpc('app_route_set_status', { p_token: token, p_id: curRoute.id, p_status: st }).then(function (d) {
      var r = d && d[0];
      if (!r || !r.ok) { msg('#rtDetMsg', (r && r.message) || 'Ошибка', 'err'); return; }
      msg('#rtDetMsg', r.message, 'ok');
      load().then(function () { openRoute(curRoute.id); });
    }).catch(function (e) { msg('#rtDetMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  $('#rtToActive').addEventListener('click', function () { setStatus('active'); });
  $('#rtToDone').addEventListener('click', function () { setStatus('done'); });

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    ['eq', 'mat', 'op', 'tp', 'rt', 'ref'].forEach(function (t) { $('#p-' + t).style.display = (b.dataset.t === t) ? '' : 'none'; });
  });

  $('#eqAdd').addEventListener('click', function () {
    var name = $('#eqName').value.trim(); if (!name) { msg('#eqMsg', 'Укажите название.', 'err'); return; }
    var c = parseFloat($('#eqCost').value.replace(',', '.'));
    rpc('app_equipment_save', { p_token: token, p_id: null, p_code: $('#eqCode').value.trim(), p_name: name, p_model: '', p_kind: $('#eqKind').value, p_axis: null, p_max_x: null, p_max_y: null, p_max_z: null, p_accuracy: null, p_cost_hour: isNaN(c) ? 0 : c, p_dept: '', p_status: 'active' })
      .then(function (d) { var r = d && d[0]; msg('#eqMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { ['#eqCode', '#eqName', '#eqCost'].forEach(function (s) { $(s).value = ''; }); load(); } });
  });
  $('#opAdd').addEventListener('click', function () {
    var name = $('#opName').value.trim(); if (!name) { msg('#opMsg', 'Укажите название.', 'err'); return; }
    var rate = parseFloat($('#opRate').value.replace(',', '.'));
    rpc('app_operation_save', { p_token: token, p_id: null, p_code: $('#opCode').value.trim(), p_name: name, p_kind: $('#opKind').value, p_setup: 0, p_unit_min: 0, p_rate: isNaN(rate) ? 0 : rate, p_unit: 'шт' })
      .then(function (d) { var r = d && d[0]; msg('#opMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { ['#opCode', '#opName', '#opRate'].forEach(function (s) { $(s).value = ''; }); load(); } });
  });
  $('#tpAdd').addEventListener('click', function () {
    var name = $('#tpName').value.trim(); if (!name) { msg('#tpMsg', 'Укажите название.', 'err'); return; }
    rpc('app_process_create', { p_token: token, p_code: $('#tpCode').value.trim(), p_name: name, p_product_type: '', p_material_id: $('#tpMat').value || null, p_note: '' })
      .then(function (d) { var r = d && d[0]; if (!r) { msg('#tpMsg', 'Ошибка', 'err'); return; } msg('#tpMsg', r.message, 'ok'); $('#tpCode').value = ''; $('#tpName').value = ''; load().then(function () { openTp(r.id); }); });
  });
  $('#stAdd').addEventListener('click', function () {
    if (!curTp) return;
    var m = parseFloat($('#stMin').value.replace(',', '.'));
    rpc('app_process_add_step', { p_token: token, p_id: curTp.id, p_operation_id: $('#stOp').value || null, p_equipment_id: $('#stEq').value || null, p_material_id: null, p_plan_min: isNaN(m) ? 0 : m, p_note: '' })
      .then(function (d) { var r = d && d[0]; msg('#stMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { $('#stMin').value = ''; loadSteps(); } });
  });
  $('#refQ').addEventListener('input', function () { refQ = this.value; renderRef(); });
  $('#refGroup').addEventListener('change', function () { refGroup = this.value; renderRef(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#eqMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
