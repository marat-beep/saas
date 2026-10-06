/* ============================================================
   3DMP Service · apps/calc — инженерные калькуляторы (B34/A1)
   Данные: 0063. Стандарт модуля: RPC + сохранение + привязка к заявке.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, tab = 'mass', lastInput = null, lastRows = null, saved = [], orders = [], q = '';

  var KINDS = {
    mass: 'Масса проката', cutting: 'Режимы резания', iso: 'ISO 286 (посадки)', cnc: 'Нормочас ЧПУ',
    cost: 'Себестоимость детали', decimal: 'Децимальные обозначения', convert: 'Конвертеры', tech: 'Подбор технологии'
  };

  var SPECS = {
    mass: {
      rpc: 'app_calc_mass',
      fields: [
        { k: 'p_profile', t: 'select', l: 'Профиль', opts: [['round', 'Круг'], ['square', 'Квадрат'], ['rect', 'Прямоугольник'], ['pipe', 'Труба'], ['sheet', 'Лист'], ['hex', 'Шестигранник']] },
        { k: 'p_a', t: 'num', l: 'Размер A, мм', d: 40 },
        { k: 'p_b', t: 'num', l: 'Размер B, мм', d: 0 },
        { k: 'p_c', t: 'num', l: 'C (стенка/толщина), мм', d: 0 },
        { k: 'p_len', t: 'num', l: 'Длина, мм', d: 1000 },
        { k: 'p_density', t: 'num', l: 'Плотность, г/см³', d: 7.85 },
        { k: 'p_qty', t: 'num', l: 'Количество, шт', d: 1 }
      ],
      labels: { area_mm2: 'Площадь сечения, мм²', volume_mm3: 'Объём, мм³', mass_kg: 'Масса 1 шт, кг', mass_total_kg: 'Масса всего, кг' }
    },
    cutting: {
      rpc: 'app_calc_cutting',
      fields: [
        { k: 'p_vc', t: 'num', l: 'Vc, м/мин', d: 120 },
        { k: 'p_d', t: 'num', l: 'Диаметр D, мм', d: 16 },
        { k: 'p_fz', t: 'num', l: 'Подача на зуб fz, мм', d: 0.05 },
        { k: 'p_z', t: 'int', l: 'Число зубьев z', d: 4 },
        { k: 'p_ap', t: 'num', l: 'Глубина ap, мм', d: 2 },
        { k: 'p_ae', t: 'num', l: 'Ширина ae, мм', d: 8 },
        { k: 'p_kc', t: 'num', l: 'kc, Н/мм²', d: 2000 }
      ],
      labels: { n_rpm: 'Обороты n, об/мин', feed_rev: 'Подача, мм/об', vf_mm_min: 'Минутная подача, мм/мин', mrr_cm3_min: 'Съём MRR, см³/мин', pc_kw: 'Мощность резания, кВт' }
    },
    iso: {
      rpc: 'app_calc_iso',
      fields: [
        { k: 'p_nominal', t: 'num', l: 'Номинал, мм', d: 25 },
        { k: 'p_hole_es', t: 'num', l: 'Отверстие ES, мм', d: 0.021 },
        { k: 'p_hole_ei', t: 'num', l: 'Отверстие EI, мм', d: 0 },
        { k: 'p_shaft_es', t: 'num', l: 'Вал es, мм', d: 0 },
        { k: 'p_shaft_ei', t: 'num', l: 'Вал ei, мм', d: -0.013 }
      ],
      labels: { hole_max: 'Отверстие max', hole_min: 'Отверстие min', shaft_max: 'Вал max', shaft_min: 'Вал min', clearance_min: 'Зазор min', clearance_max: 'Зазор max', fit: 'Характер посадки' }
    },
    cnc: {
      rpc: 'app_calc_cnc',
      fields: [
        { k: 'p_machine_price', t: 'num', l: 'Стоимость станка, ₽', d: 8000000 },
        { k: 'p_life_years', t: 'num', l: 'Срок службы, лет', d: 7 },
        { k: 'p_hours_year', t: 'num', l: 'Часов в год', d: 2000 },
        { k: 'p_power_kw', t: 'num', l: 'Мощность, кВт', d: 12 },
        { k: 'p_energy_price', t: 'num', l: 'Цена энергии, ₽/кВт·ч', d: 6 },
        { k: 'p_fot_rate', t: 'num', l: 'ФОТ, ₽/ч', d: 500 },
        { k: 'p_tools_rate', t: 'num', l: 'Расходники, ₽/ч', d: 150 },
        { k: 'p_overhead_pct', t: 'num', l: 'Накладные, %', d: 15 }
      ],
      labels: { amort: 'Амортизация, ₽/ч', energy: 'Энергия, ₽/ч', fot: 'ФОТ, ₽/ч', tools: 'Расходники, ₽/ч', direct: 'Прямые, ₽/ч', overhead: 'Накладные, ₽/ч', rate: 'Нормочас, ₽/ч' }
    },
    cost: {
      rpc: 'app_calc_cost',
      fields: [
        { k: 'p_material_cost', t: 'num', l: 'Материал, ₽', d: 3000 },
        { k: 'p_work_hours', t: 'num', l: 'Работы, н/ч', d: 6 },
        { k: 'p_rate', t: 'num', l: 'Ставка, ₽/ч', d: 900 },
        { k: 'p_overhead_pct', t: 'num', l: 'Накладные, %', d: 15 },
        { k: 'p_qty', t: 'num', l: 'Количество, шт', d: 1 }
      ],
      labels: { material: 'Материал, ₽', work: 'Работы, ₽', overhead: 'Накладные, ₽', total: 'Итого, ₽', per_unit: 'На единицу, ₽' }
    },
    decimal: {
      rpc: 'app_calc_decimal',
      fields: [
        { k: 'p_code', t: 'text', l: 'Код организации (ГОСТ 2.201)', d: 'АБВГ' },
        { k: 'p_doc_number', t: 'text', l: 'Номер документа', d: '1234' },
        { k: 'p_litera', t: 'text', l: 'Литера', d: '' }
      ],
      labels: { designation: 'Обозначение' }
    },
    convert: {
      rpc: 'app_calc_convert',
      fields: [
        { k: 'p_kind', t: 'select', l: 'Конвертация', opts: [['mm_in', 'мм → дюйм'], ['in_mm', 'дюйм → мм'], ['hb_sigma', 'HB → σв'], ['sigma_hb', 'σв → HB'], ['kg_lb', 'кг → lb'], ['lb_kg', 'lb → кг'], ['n_kgf', 'Н → кгс'], ['kgf_n', 'кгс → Н'], ['kw_hp', 'кВт → л.с.'], ['hp_kw', 'л.с. → кВт'], ['grad_rad', 'град → рад'], ['rad_grad', 'рад → град']] },
        { k: 'p_value', t: 'num', l: 'Значение', d: 1 }
      ],
      labels: { result: 'Результат', unit: 'Единица', formula: 'Формула' }
    },
    tech: {
      rpc: 'app_calc_tech',
      fields: [
        { k: 'p_material', t: 'text', l: 'Материал', d: 'Сталь 40Х' },
        { k: 'p_feature', t: 'text', l: 'Признак (отверстие/паз/резьба/плоскость)', d: 'отверстие' }
      ],
      multi: true,
      labels: { recommendation: 'Рекомендация', note: 'Примечание', source: 'Источник' }
    }
  };

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function num(v) { if (v === '' || v === null || v === undefined) return null; var x = parseFloat(String(v).replace(',', '.')); return isNaN(x) ? null : x; }

  function renderTabs() {
    $('#tabs').innerHTML = Object.keys(KINDS).map(function (k) {
      return '<button class="tab' + (k === tab ? ' active' : '') + '" data-t="' + k + '">' + KINDS[k] + '</button>';
    }).join('');
    $$('#tabs .tab').forEach(function (b) { b.addEventListener('click', function () { tab = b.dataset.t; renderTabs(); renderForm(); }); });
  }

  function renderForm() {
    var spec = SPECS[tab];
    $('#form').innerHTML = spec.fields.map(function (f) {
      var input;
      if (f.t === 'select') {
        input = '<select id="fld_' + f.k + '">' + f.opts.map(function (o) { return '<option value="' + o[0] + '">' + o[1] + '</option>'; }).join('') + '</select>';
      } else if (f.t === 'num' || f.t === 'int') {
        input = '<input type="number" step="any" id="fld_' + f.k + '" value="' + (f.d != null ? f.d : '') + '">';
      } else {
        input = '<input type="text" id="fld_' + f.k + '" value="' + esc(f.d != null ? f.d : '') + '">';
      }
      return '<div class="field"><label>' + esc(f.l) + '</label>' + input + '</div>';
    }).join('');
    $('#res').innerHTML = ''; $('#saveRow').style.display = 'none'; msg('#fMsg', '');
  }

  function readInput() {
    var spec = SPECS[tab], args = { p_token: token }, raw = {};
    spec.fields.forEach(function (f) {
      var el = $('#fld_' + f.k); var v = el ? el.value : '';
      raw[f.k] = v;
      args[f.k] = (f.t === 'num') ? num(v) : (f.t === 'int' ? (num(v) == null ? null : parseInt(num(v), 10)) : v);
    });
    lastInput = { args: args, raw: raw };
    return args;
  }

  function renderRes(spec, rows) {
    if (!rows || !rows.length) { $('#res').innerHTML = '<div class="resbox"><span class="note">Нет результата.</span></div>'; return; }
    if (spec.multi) {
      $('#res').innerHTML = '<div class="resbox">' + rows.map(function (r) {
        return '<div class="resline"><span>' + esc(r.recommendation || '') + '</span></div>' +
          (r.note ? '<div class="note">' + esc(r.note) + '</div>' : '') +
          (r.source ? '<div class="note">Источник: ' + esc(r.source) + '</div>' : '');
      }).join('') + '</div>';
      return;
    }
    var r = rows[0], lb = spec.labels || {};
    $('#res').innerHTML = '<div class="resbox">' + Object.keys(r).map(function (k) {
      return '<div class="resline"><span>' + esc(lb[k] || k) + '</span><b>' + esc(r[k]) + '</b></div>';
    }).join('') + '</div>';
  }

  function calc() {
    var spec = SPECS[tab], args;
    try { args = readInput(); } catch (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); return; }
    rpc(spec.rpc, args).then(function (rows) {
      lastRows = rows || [];
      renderRes(spec, lastRows);
      $('#saveRow').style.display = 'flex';
      $('#sTitle').value = (KINDS[tab]) + ' — ' + new Date().toLocaleDateString('ru-RU');
      msg('#fMsg', 'Расчёт выполнен.', 'ok');
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function loadOrders() {
    return rpc('app_order_list', { p_token: token }).then(function (r) {
      orders = r || [];
      $('#sOrder').innerHTML = '<option value="">— привязать к заявке —</option>' + orders.map(function (o) {
        return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>';
      }).join('');
    }).catch(function () {});
  }

  function loadSaved() {
    return rpc('app_calc_list', { p_token: token, p_kind: $('#fKind').value || null, p_q: null }).then(function (r) {
      saved = r || []; renderSaved();
    }).catch(function (e) { msg('#mMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function summ(result) {
    if (!result) return '';
    try { var k = Object.keys(result)[0]; return k ? (k + ': ' + result[k]) : ''; } catch (e) { return ''; }
  }

  function renderSaved() {
    var s = q.toLowerCase();
    var rows = saved.filter(function (c) { return !s || (c.title || '').toLowerCase().indexOf(s) >= 0 || (c.ref || '').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (c) {
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + esc(KINDS[c.kind] || c.kind) + '</span><b>' + esc(c.title || 'Расчёт') + '</b>' +
        (c.order_number ? '<span class="note">заявка ' + esc(c.order_number) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + esc(summ(c.result)) + '</span></div>' +
        '<div class="toolbar mt"><span class="note">' + new Date(c.created_at).toLocaleString('ru-RU') + '</span>' +
        '<button class="btn secondary" data-del="' + c.id + '" style="width:auto;padding:7px 12px;margin-left:auto;">Удалить</button></div></div>';
    }).join('') : '<span class="note">Сохранённых расчётов нет.</span>';
    $$('#list [data-del]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_calc_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadSaved(); });
      });
    });
  }

  $('#calcBtn').addEventListener('click', calc);
  $('#clearBtn').addEventListener('click', renderForm);
  $('#saveBtn').addEventListener('click', function () {
    if (!lastRows) return;
    var spec = SPECS[tab];
    var result = spec.multi ? lastRows : lastRows[0];
    rpc('app_calc_save', {
      p_token: token, p_kind: tab, p_title: $('#sTitle').value || KINDS[tab],
      p_input: lastInput.raw, p_result: result, p_ref: null, p_order_id: $('#sOrder').value || null
    }).then(function (d) {
      var r = d && d[0]; msg('#mMsg', r ? r.message : 'Ошибка', r ? 'ok' : 'err');
      window.Auth.log('Расчёт сохранён', KINDS[tab]); loadSaved();
    }).catch(function (e) { msg('#mMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#q').addEventListener('input', function () { q = this.value; renderSaved(); });
  $('#fKind').addEventListener('change', loadSaved);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    var kinds = $('#fKind');
    Object.keys(KINDS).forEach(function (k) { var o = document.createElement('option'); o.value = k; o.textContent = KINDS[k]; kinds.appendChild(o); });
    renderTabs(); renderForm(); loadOrders(); loadSaved();
  });
})();
