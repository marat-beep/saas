/* ============================================================
   3DMP Service · apps/registry — справочники (master data)
   Оборудование, материалы, операции, шаблоны техпроцессов (0024). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, eq = [], mats = [], ops = [], tps = [], curTp = null;

  var KIND = { frezerny: 'Фрезерный', tokarny: 'Токарный', lazer: 'Лазер', sverlilny: 'Сверлильный', shlifovalny: 'Шлифовальный', edm: 'Электроэрозия', sborka: 'Сборка' };
  function kLabel(k) { return KIND[k] || k; }
  function esc(v) { return ui.esc(v); }
  function num(v) { return v == null ? '' : (Number(v) || 0); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_equipment_list', { p_token: token }),
      rpc('app_materials_reg', { p_token: token }).catch(function () { return []; }),
      rpc('app_operations_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_process_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      eq = r[0] || []; mats = r[1] || []; ops = r[2] || []; tps = r[3] || [];
      renderEq(); renderMat(); renderOp(); renderTp();
      $('#tpMat').innerHTML = '<option value="">— нет —</option>' + mats.map(function (m) { return '<option value="' + m.id + '">' + esc(m.name) + '</option>'; }).join('');
      $('#stOp').innerHTML = ops.map(function (o) { return '<option value="' + o.id + '">' + esc(o.name) + ' (' + kLabel(o.kind) + ')</option>'; }).join('');
      $('#stEq').innerHTML = '<option value="">— не выбрано —</option>' + eq.map(function (e) { return '<option value="' + e.id + '">' + esc(e.name) + ' (' + kLabel(e.kind) + ')</option>'; }).join('');
    }).catch(function (e) { msg('#eqMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderEq() {
    $('#eqCnt').textContent = '(' + eq.length + ')';
    $('#eqList').innerHTML = '<thead><tr><th>Код</th><th>Название</th><th>Модель</th><th>Тип</th><th>Габариты</th><th>Точн.</th><th>₽/ч</th><th>Опер.</th><th>Статус</th></tr></thead><tbody>' +
      eq.map(function (e) {
        return '<tr><td>' + esc(e.code || '—') + '</td><td><b>' + esc(e.name) + '</b></td><td>' + esc(e.model || '—') + '</td>' +
          '<td><span class="b">' + kLabel(e.kind) + '</span></td>' +
          '<td>' + (e.max_x ? num(e.max_x) + '×' + num(e.max_y) + '×' + num(e.max_z) : '—') + '</td>' +
          '<td>' + (e.accuracy != null ? '±' + num(e.accuracy) : '—') + '</td><td>' + num(e.cost_hour) + '</td>' +
          '<td>' + e.ops_count + '</td><td>' + (e.status === 'active' ? 'работает' : e.status) + '</td></tr>';
      }).join('') + '</tbody>';
  }
  function renderMat() {
    $('#matCnt').textContent = '(' + mats.length + ')';
    $('#matList').innerHTML = '<thead><tr><th>Код</th><th>Материал</th><th>Группа</th><th>Марка</th><th>Стандарт</th><th>Плотн.</th><th>Ед.</th><th>Цена</th><th>Остаток</th></tr></thead><tbody>' +
      mats.map(function (m) {
        return '<tr><td>' + esc(m.code || '—') + '</td><td><b>' + esc(m.name) + '</b></td><td>' + esc(m.material_group || '—') + '</td>' +
          '<td>' + esc(m.grade || '—') + '</td><td>' + esc(m.standard || '—') + '</td><td>' + (m.density != null ? num(m.density) : '—') + '</td>' +
          '<td>' + esc(m.unit || '') + '</td><td>' + num(m.price) + '</td><td>' + num(m.qty) + '</td></tr>';
      }).join('') + '</tbody>';
  }
  function renderOp() {
    $('#opCnt').textContent = '(' + ops.length + ')';
    $('#opList').innerHTML = '<thead><tr><th>Код</th><th>Операция</th><th>Тип оборудования</th><th>Подг., мин</th><th>На ед., мин</th><th>₽/ч</th><th>Оборудования</th></tr></thead><tbody>' +
      ops.map(function (o) {
        return '<tr><td>' + esc(o.code || '—') + '</td><td><b>' + esc(o.name) + '</b></td><td><span class="b">' + kLabel(o.kind) + '</span></td>' +
          '<td>' + num(o.setup_min) + '</td><td>' + num(o.unit_min) + '</td><td>' + num(o.base_rate) + '</td><td>' + o.equipment_count + '</td></tr>';
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

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    ['eq', 'mat', 'op', 'tp'].forEach(function (t) { $('#p-' + t).style.display = (b.dataset.t === t) ? '' : 'none'; });
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
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (['admin', 'owner', 'manager'].indexOf(s.role) < 0) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#eqMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
