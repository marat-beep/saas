/* ============================================================
   3DMP Service · apps/eam — CMMS/EAM 2.0 (W14, 0166).
   Вибрация, энергия, простои/дисциплина, версии УП, карта цеха.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, equip = [], reasons = [];
  var RES = { el: 'Электроэнергия', gas: 'Газ', water: 'Вода', air: 'Воздух' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dd(v) { return v ? new Date(v).toLocaleString('ru-RU') : '—'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'vibro') loadVibro();
    if (scr === 'energy') loadEnergy();
    if (scr === 'dt') loadDt();
    if (scr === 'nc') loadNc();
    if (scr === 'map') loadMap();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_eam_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Аварий вибрации', k.vibro_alarms || 0) + cell('Энергия/мес', k.energy_month || 0) + cell('Стоимость/мес', k.energy_cost_month || 0) + cell('Смен открыто', k.shifts_open || 0) + cell('УП расхождений', k.nc_mismatch || 0) + cell('Станков на карте', k.machines || 0);
    });
  }
  function loadEquip() { return rpc('app_equipment_list', { p_token: token }).then(function (r) { equip = r || []; }).catch(function () { equip = []; }); }
  function eqOpts() { return equip.map(function (e) { return { value: e.id, label: e.name }; }); }

  /* ---------- Вибрация ---------- */
  function loadVibro() {
    return rpc('app_vibro_board', { p_token: token }).then(function (r) {
      var list = r || [];
      $('#vboard').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Оборудование</th><th class="num">мм/с</th><th>Оценка</th><th>Когда</th></tr></thead><tbody>' +
        list.map(function (x) { return '<tr><td><b>' + esc(x.equipment) + '</b></td><td class="num">' + x.value + '</td><td>' + (x.result === 'alarm' ? '🔴 авария' : x.result === 'warn' ? '🟡 внимание' : '🟢 норма') + '</td><td class="muted">' + dd(x.ts) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Показаний нет.</span>';
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function vAdd() {
    ui.formDialog({ title: 'Показание вибрации', okText: 'Добавить', fields: [
      { name: 'equipment_id', label: 'Оборудование', type: 'select', options: eqOpts(), required: true },
      { name: 'value', label: 'Значение, мм/с', type: 'number', required: true }, { name: 'unit', label: 'Ед.', type: 'text' }
    ], values: { unit: 'мм/с' } }).then(function (v) {
      if (!v) return;
      rpc('app_vibro_add', { p_token: token, p_equipment_id: v.equipment_id, p_value: v.value ? Number(v.value) : 0, p_unit: v.unit || null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.result === 'alarm' ? 'err' : 'ok'); loadVibro(); loadKpi(); });
    });
  }
  function vLimits() {
    rpc('app_vibro_limits_list', { p_token: token }).then(function (r) {
      var rows = (r || []).map(function (l) { return '<tr><td>' + esc(l.equipment || '—') + '</td><td class="num">' + l.warn + '</td><td class="num">' + l.alarm + '</td></tr>'; }).join('');
      ui.dialog({ title: 'Пороги вибрации', body: '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Оборудование</th><th class="num">Warn</th><th class="num">Alarm</th></tr></thead><tbody>' + (rows || '<tr><td colspan="3" class="note">По умолчанию 4.5 / 7.1</td></tr>') + '</tbody></table></div>', html: true, cancelText: 'Закрыть' });
    });
  }

  /* ---------- Энергия ---------- */
  function loadEnergy() {
    return rpc('app_energy_kpi', { p_token: token, p_from: null, p_to: null }).then(function (r) {
      var list = r || [];
      $('#ekpi').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Ресурс</th><th class="num">Расход</th><th>Ед.</th><th class="num">Стоимость</th></tr></thead><tbody>' +
        list.map(function (x) { return '<tr><td>' + esc(RES[x.resource] || x.resource) + '</td><td class="num">' + x.amount + '</td><td>' + esc(x.unit || '') + '</td><td class="num">' + x.cost + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Нет данных за месяц.</span>';
    });
  }
  function eAdd() {
    ui.formDialog({ title: 'Показание энергии', okText: 'Добавить', fields: [
      { name: 'resource', label: 'Ресурс', type: 'select', options: Object.keys(RES).map(function (k) { return { value: k, label: RES[k] }; }) },
      { name: 'value', label: 'Значение', type: 'number', required: true }, { name: 'unit', label: 'Ед.', type: 'text' },
      { name: 'cost', label: 'Стоимость, ₽', type: 'number' }, { name: 'period', label: 'Дата', type: 'date' }
    ], values: { resource: 'el', period: new Date().toISOString().slice(0, 10) } }).then(function (v) {
      if (!v) return;
      rpc('app_energy_add', { p_token: token, p_resource: v.resource, p_value: v.value ? Number(v.value) : 0, p_unit: v.unit || null, p_cost: v.cost ? Number(v.cost) : 0, p_period: v.period || null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadEnergy(); loadKpi(); });
    });
  }

  /* ---------- Простои ---------- */
  function loadDt() {
    return Promise.all([
      rpc('app_downtime_reasons_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_operator_log_list', { p_token: token, p_login: null, p_limit: 30 }).catch(function () { return []; })
    ]).then(function (r) {
      reasons = r[0] || [];
      $('#reasons').innerHTML = reasons.length ? '<table class="mini"><thead><tr><th>Код</th><th>Причина</th></tr></thead><tbody>' + reasons.map(function (x) { return '<tr><td>' + esc(x.code || '') + '</td><td>' + esc(x.name) + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Причин нет.</span>';
      var log = r[1] || [];
      $('#olog').innerHTML = log.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Когда</th><th>Сотрудник</th><th>Станок</th><th>Событие</th><th>Причина</th></tr></thead><tbody>' +
        log.map(function (x) { return '<tr><td class="muted">' + dd(x.ts) + '</td><td>' + esc(x.login || '') + '</td><td>' + esc(x.machine || '') + '</td><td>' + (x.event === 'in' ? 'вход' : 'выход') + '</td><td class="muted">' + esc(x.reason || '') + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Журнал пуст.</span>';
    });
  }
  function rAdd() {
    ui.formDialog({ title: 'Причина простоя', okText: 'Добавить', fields: [{ name: 'code', label: 'Код', type: 'text' }, { name: 'name', label: 'Название', type: 'text', required: true }], values: {} }).then(function (v) {
      if (!v) return;
      rpc('app_downtime_reason_save', { p_token: token, p_id: null, p_code: v.code || null, p_name: v.name }).then(function () { loadDt(); });
    });
  }
  function oAdd() {
    ui.formDialog({ title: 'Отметка вход/выход', okText: 'Зафиксировать', fields: [
      { name: 'login', label: 'Сотрудник (логин)', type: 'text', required: true },
      { name: 'machine', label: 'Станок', type: 'text' },
      { name: 'event', label: 'Событие', type: 'select', options: [{ value: 'in', label: 'Вход' }, { value: 'out', label: 'Выход' }] }
    ], values: { event: 'in' } }).then(function (v) {
      if (!v) return;
      rpc('app_operator_log_add', { p_token: token, p_login: v.login, p_machine: v.machine || null, p_event: v.event, p_reason_id: null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadDt(); loadKpi(); });
    });
  }

  /* ---------- Версии УП ---------- */
  function loadNc() {
    return rpc('app_nc_versions_compare', { p_token: token }).then(function (r) {
      var list = r || [];
      $('#nc').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Программа</th><th class="num">Эталон</th><th class="num">Факт</th><th>Сверка</th></tr></thead><tbody>' +
        list.map(function (x) { return '<tr><td><b>' + esc(x.program) + '</b></td><td class="num">v' + (x.base_version || '—') + '</td><td class="num">v' + (x.actual_version || '—') + '</td><td>' + (x.match ? '🟢 совпадает' : '🔴 расхождение') + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Версий нет.</span>';
    });
  }
  function ncAdd() {
    ui.formDialog({ title: 'Версия УП', okText: 'Сохранить', fields: [
      { name: 'program', label: 'Программа', type: 'text', required: true }, { name: 'machine', label: 'Станок', type: 'text' },
      { name: 'kind', label: 'Вид', type: 'select', options: [{ value: 'base', label: 'Эталон (base)' }, { value: 'actual', label: 'Факт (actual)' }] },
      { name: 'hash', label: 'Хэш/КС', type: 'text' }
    ], values: { kind: 'base' } }).then(function (v) {
      if (!v) return;
      rpc('app_nc_version_add', { p_token: token, p_program: v.program, p_machine: v.machine || null, p_hash: v.hash || null, p_kind: v.kind, p_note: null }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadNc(); loadKpi(); });
    });
  }

  /* ---------- Карта ---------- */
  function loadMap() {
    return rpc('app_layout_list', { p_token: token }).then(function (r) {
      var list = r || [];
      var html = '<div class="map" id="mapInner">' + list.map(function (m) {
        return '<div class="mnode ' + (m.status === 'alarm' ? 'alarm' : '') + '" style="left:' + (Number(m.x) * 8 + 6) + 'px;top:' + (Number(m.y) * 8 + 6) + 'px;width:' + (Number(m.w) * 8) + 'px;height:' + (Number(m.h) * 8) + 'px;">' + esc(m.machine) + '</div>';
      }).join('') + '</div>';
      $('#map').outerHTML = html;
      $$('#mapAdd');
    });
  }
  function mapAdd() {
    ui.formDialog({ title: 'Станок на карте', okText: 'Сохранить', fields: [
      { name: 'machine', label: 'Станок', type: 'text', required: true }, { name: 'x', label: 'X', type: 'number' },
      { name: 'y', label: 'Y', type: 'number' }, { name: 'w', label: 'Ширина', type: 'number' }, { name: 'h', label: 'Высота', type: 'number' }
    ], values: { x: 0, y: 0, w: 10, h: 8 } }).then(function (v) {
      if (!v) return;
      rpc('app_layout_save', { p_token: token, p_id: null, p_machine: v.machine, p_x: v.x ? Number(v.x) : 0, p_y: v.y ? Number(v.y) : 0, p_w: v.w ? Number(v.w) : 8, p_h: v.h ? Number(v.h) : 6, p_status: 'idle' }).then(function () { loadMap(); loadKpi(); });
    });
  }

  $('#vAdd').addEventListener('click', vAdd);
  $('#vLim').addEventListener('click', vLimits);
  $('#eAdd').addEventListener('click', eAdd);
  $('#rAdd').addEventListener('click', rAdd);
  $('#oAdd').addEventListener('click', oAdd);
  $('#ncAdd').addEventListener('click', ncAdd);
  $('#mapAdd').addEventListener('click', mapAdd);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadEquip().then(function () { loadKpi(); loadVibro(); });
  });
})();
