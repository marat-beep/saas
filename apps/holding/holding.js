/* ============================================================
   3DMP Service · apps/holding — Холдинг/CPM (W22, 0169).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, units = [];
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function money(v) { return v == null ? '—' : (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 0 }) + ' ₽'; }
  function dd(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'units') loadUnits(); else loadCons();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_holding_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Площадок', k.units || 0) + cell('Активных', k.units_active || 0) + cell('Выручка', money(k.revenue)) + cell('Себестоимость', money(k.cost)) + cell('Прибыль', money(k.profit)) + cell('Снимков', k.snapshots || 0);
    }).catch(function () {});
  }
  function loadUnits() {
    return rpc('app_holding_units_list', { p_token: token }).then(function (r) {
      units = r || [];
      $('#units').innerHTML = units.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Площадка</th><th>Код</th><th>Регион</th><th class="num">Доля, %</th><th>Активна</th><th></th></tr></thead><tbody>' +
        units.map(function (u) { return '<tr><td><b>' + esc(u.name) + '</b></td><td>' + esc(u.code || '') + '</td><td>' + esc(u.region || '') + '</td><td class="num">' + u.share + '</td><td>' + (u.active ? 'да' : 'нет') + '</td>' +
          '<td style="white-space:nowrap;"><button class="act" data-snap="' + u.id + '">Снимок</button><button class="act danger" data-del="' + u.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Площадок нет.</span>';
      $$('#units [data-snap]').forEach(function (b) { b.addEventListener('click', function () { snapForm(b.dataset.snap); }); });
      $$('#units [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить площадку?')) return; rpc('app_holding_unit_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadUnits(); loadKpi(); }); }); });
    });
  }
  function unitForm() {
    ui.formDialog({ title: 'Площадка', okText: 'Сохранить', fields: [
      { name: 'name', label: 'Название', type: 'text', required: true }, { name: 'code', label: 'Код', type: 'text' },
      { name: 'region', label: 'Регион', type: 'text' }, { name: 'share', label: 'Доля, %', type: 'number' }
    ], values: { share: 100 } }).then(function (v) {
      if (!v) return;
      rpc('app_holding_unit_save', { p_token: token, p_id: null, p_name: v.name, p_code: v.code || null, p_region: v.region || null, p_share: v.share ? Number(v.share) : 100, p_unit_tenant: null, p_active: true })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadUnits(); loadKpi(); });
    });
  }
  function snapForm(uid) {
    ui.formDialog({ title: 'Снимок KPI площадки', okText: 'Добавить', fields: [
      { name: 'period', label: 'Период', type: 'date' }, { name: 'revenue', label: 'Выручка, ₽', type: 'number' }, { name: 'cost', label: 'Себестоимость, ₽', type: 'number' }
    ], values: { period: new Date().toISOString().slice(0, 10) } }).then(function (v) {
      if (!v) return;
      rpc('app_holding_snapshot_save', { p_token: token, p_unit_id: uid, p_period: v.period || null, p_revenue: v.revenue ? Number(v.revenue) : 0, p_cost: v.cost ? Number(v.cost) : 0, p_kpi: {} })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadKpi(); loadCons(); });
    });
  }
  function loadCons() {
    var d = $('#consDate').value || null;
    return rpc('app_holding_consolidate', { p_token: token, p_period: d }).then(function (r) {
      var list = r || [];
      $('#cons').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Площадка</th><th>Регион</th><th class="num">Доля, %</th><th class="num">Выручка</th><th class="num">Себестоимость</th><th class="num">Прибыль</th></tr></thead><tbody>' +
        list.map(function (x) { return '<tr><td>' + esc(x.unit) + '</td><td>' + esc(x.region || '') + '</td><td class="num">' + (x.share != null ? x.share : '') + '</td><td class="num">' + money(x.revenue) + '</td><td class="num">' + money(x.cost) + '</td><td class="num">' + money(x.profit) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Нет данных.</span>';
    });
  }

  $('#addUnit').addEventListener('click', unitForm);
  $('#addSnap').addEventListener('click', function () { if (!units.length) { msg('Сначала добавьте площадку.', 'err'); return; } snapForm(units[0].id); });
  $('#consBtn').addEventListener('click', loadCons);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  /* R4·PROP-29: консолидация группы — элиминации внутригрупповых оборотов */
  var elim = [];
  function elimN(v) { return Number(v) || 0; }
  function elimEsc(v) { return ui.esc(v); }
  function loadElim() {
    return rpc('app_consol_list', { p_token: token }).then(function (r) { elim = r || []; renderElim(); }).catch(function () {});
  }
  function renderElim() {
    var host = $('#elim'); if (!host) return;
    var sum = elim.reduce(function (s, e) { return s + elimN(e.amount); }, 0);
    host.innerHTML = '<div class="card"><h2>Элиминации (консолидация группы)</h2>' +
      '<div class="kpi-row"><div class="kpi"><small>Элиминаций</small><b>' + elim.length + '</b></div><div class="kpi"><small>Сумма элиминаций</small><b>' + sum.toLocaleString('ru-RU') + ' ₽</b></div></div>' +
      '<div class="grid3"><div class="field"><label>Период</label><input type="date" id="elPer"></div><div class="field"><label>Откуда (юрлицо)</label><input type="text" id="elFrom"></div><div class="field"><label>Куда (юрлицо)</label><input type="text" id="elTo"></div></div>' +
      '<div class="grid3"><div class="field"><label>Сумма, ₽</label><input type="text" id="elAmt" inputmode="decimal"></div><div class="field" style="grid-column:span 2;display:flex;align-items:flex-end;"><button class="btn" id="elAdd" style="width:auto;">Добавить элиминацию</button></div></div>' +
      (elim.length ? '<div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Период</th><th>Откуда</th><th>Куда</th><th class="num">Сумма</th><th></th></tr></thead><tbody>' +
        elim.map(function (e) { return '<tr><td>' + elimEsc(e.period) + '</td><td>' + elimEsc(e.from_unit || '—') + '</td><td>' + elimEsc(e.to_unit || '—') + '</td><td class="num"><b>' + elimN(e.amount) + '</b></td><td><button class="act danger" data-eldel="' + e.id + '" aria-label="Удалить" title="Удалить">✕</button></td></tr>'; }).join('') + '</tbody></table></div>'
        : '<span class="note">Элиминаций нет.</span>') +
      '<p class="note" style="margin-top:6px;">Консолидированный результат = сумма площадок − элиминации внутригрупповых оборотов.</p></div>';
    $('#elAdd').addEventListener('click', function () {
      rpc('app_consol_save', { p_token: token, p_id: null, p_period: $('#elPer').value || null, p_from: $('#elFrom').value.trim() || null, p_to: $('#elTo').value.trim() || null, p_amount: parseFloat($('#elAmt').value.replace(',', '.')) || 0, p_note: null })
        .then(function (r) { var x = r && r[0]; ui.toast(x ? x.message : ''); if (x && x.ok) loadElim(); }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
    });
    ui.qsa('#elim [data-eldel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_consol_delete', { p_token: token, p_id: b.dataset.eldel }).then(loadElim); }); });
  }

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    loadElim();
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadKpi(); loadUnits();
  });
})();
