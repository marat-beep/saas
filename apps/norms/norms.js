/* ============================================================
   3DMP Service · apps/norms — «Нормирование PRO» (P14). Данные: 0073.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, ops = [], kfactors = [], serial = [], analogs = [], tab = 'calc', curOp = null, lastCalc = null;

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  var TABS = [['calc', 'Калькулятор'], ['ops', 'Операции и ставки'], ['k', 'K-коэффициенты'], ['ser', 'Серийность'], ['an', 'Аналоги'], ['h', 'История']];
  function renderTabs() {
    $('#tabs').innerHTML = TABS.map(function (t) { return '<button class="tab' + (t[0] === tab ? ' active' : '') + '" data-t="' + t[0] + '">' + t[1] + '</button>'; }).join('');
    $$('#tabs .tab').forEach(function (b) { b.addEventListener('click', function () { tab = b.dataset.t; renderTabs(); showTab(); }); });
  }
  function showTab() {
    TABS.forEach(function (t) { var el = $('#sec-' + t[0]); if (el) el.style.display = (t[0] === tab ? 'block' : 'none'); });
  }

  function loadKpis() {
    return rpc('app_norms_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Операций', k.operations || 0) + cell('Ставок', k.rates || 0) + cell('K-коэф.', k.kfactors || 0) + cell('Аналогов', k.analogs || 0) + cell('Серийность', k.serial_ranges || 0);
    });
  }

  function loadOps() {
    return rpc('app_norms_ops_list', { p_token: token, p_q: null }).then(function (r) {
      ops = r || [];
      $('#cOp').innerHTML = ops.map(function (o) { return '<option value="' + o.id + '">' + esc(o.code) + ' · ' + esc(o.name) + '</option>'; }).join('');
      renderOps();
    });
  }

  function renderOps() {
    $('#oList').innerHTML = ops.length ? '<div class="olist">' + ops.map(function (o) {
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + esc(o.code) + '</span><b>' + esc(o.name) + '</b>' +
        '<span class="note">' + esc(o.category || '') + ' · ' + esc(o.unit || '') + ' · ставок ' + (o.rates || 0) + '</span></div>' +
        '<div class="toolbar mt"><button class="btn secondary" data-oedit="' + o.id + '" style="width:auto;padding:6px 11px;">Править</button>' +
        '<button class="btn secondary" data-rates="' + o.id + '" style="width:auto;padding:6px 11px;">Ставки</button></div>' +
        '<div id="rates_' + o.id + '"></div></div>';
    }).join('') + '</div>' : '<span class="note">Операций нет.</span>';
    $$('#oList [data-oedit]').forEach(function (b) { b.addEventListener('click', function () { editOp(b.dataset.oedit); }); });
    $$('#oList [data-rates]').forEach(function (b) { b.addEventListener('click', function () { toggleRates(b.dataset.rates); }); });
  }

  function editOp(id) { curOp = ops.filter(function (o) { return o.id === id; })[0]; if (!curOp) return; $('#oCode').value = curOp.code; $('#oName').value = curOp.name; $('#oCat').value = curOp.category || ''; $('#oMt').value = curOp.machine_type || ''; window.scrollTo(0, 0); }

  function toggleRates(opId) {
    var host = $('#rates_' + opId);
    if (host.innerHTML) { host.innerHTML = ''; return; }
    rpc('app_norms_rates_list', { p_token: token, p_operation_id: opId }).then(function (rs) {
      host.innerHTML = '<table class="mini mt"><thead><tr><th>Сложность</th><th class="num">Мин</th><th class="num">Макс</th><th class="num">cost ratio</th><th></th></tr></thead><tbody>' +
        (rs || []).map(function (r) { return '<tr><td>' + esc(r.complexity) + '</td><td class="num">' + r.sale_min + '</td><td class="num">' + r.sale_max + '</td><td class="num">' + r.cost_ratio + '</td><td><button class="btn secondary" data-rdel="' + r.id + '" style="width:auto;padding:3px 8px;font-size:.72rem;">×</button></td></tr>'; }).join('') +
        '</tbody></table><button class="btn secondary mt" data-radd="' + opId + '" style="width:auto;padding:6px 11px;">+ Ставка</button>';
      $$('#rates_' + opId + ' [data-rdel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_norms_rate_delete', { p_token: token, p_id: b.dataset.rdel }).then(function () { host.innerHTML = ''; toggleRates(opId); }); }); });
      $$('#rates_' + opId + ' [data-radd]').forEach(function (b) { b.addEventListener('click', function () { addRate(opId); }); });
    });
  }

  function addRate(opId) {
    var cx = prompt('Сложность (simple/mid/hard):', 'mid'); if (!cx) return;
    var mn = parseFloat(prompt('Ставка мин, ₽:', '5000')) || 0;
    var mx = parseFloat(prompt('Ставка макс, ₽:', '8000')) || 0;
    var cr = parseFloat(prompt('cost ratio (0–1):', '0.7')) || 0.7;
    rpc('app_norms_rate_save', { p_token: token, p_id: null, p_operation_id: opId, p_complexity: cx, p_sale_min: mn, p_sale_max: mx, p_cost_ratio: cr })
      .then(function () { $('#rates_' + opId).innerHTML = ''; toggleRates(opId); msg('#oMsg', 'Ставка сохранена', 'ok'); })
      .catch(function (e) { msg('#oMsg', e.message, 'err'); });
  }

  function fillKSelects() {
    function opts(cat, def) {
      var list = kfactors.filter(function (k) { return k.category === cat; });
      return list.map(function (k) { return '<option value="' + k.value + '"' + (k.value === def ? ' selected' : '') + '>' + esc(k.name) + ' ×' + k.value + '</option>'; }).join('');
    }
    $('#cKm').innerHTML = opts('material', 1);
    $('#cKa').innerHTML = opts('accuracy', 1);
    $('#cKg').innerHTML = opts('geometry', 1);
    $('#cKf').innerHTML = opts('fixture', 1);
  }

  function loadK() {
    return rpc('app_norms_k_list', { p_token: token, p_category: null }).then(function (r) {
      kfactors = r || []; fillKSelects();
      var byCat = { material: 'Материал', accuracy: 'Точность', geometry: 'Геометрия', fixture: 'Оснастка' };
      $('#kList').innerHTML = '<table class="mini"><thead><tr><th>Категория</th><th>Название</th><th class="num">K</th><th></th></tr></thead><tbody>' +
        kfactors.map(function (k) { return '<tr><td>' + esc(byCat[k.category] || k.category) + '</td><td>' + esc(k.name) + '</td><td class="num">' + k.value + '</td><td><button class="btn secondary" data-kdel="' + k.id + '" style="width:auto;padding:3px 8px;font-size:.72rem;">×</button></td></tr>'; }).join('') + '</tbody></table>';
      $$('#kList [data-kdel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_norms_k_delete', { p_token: token, p_id: b.dataset.kdel }).then(function () { loadK(); }); }); });
    });
  }

  function loadSerial() {
    return rpc('app_norms_serial_list', { p_token: token }).then(function (r) {
      serial = r || [];
      $('#sList').innerHTML = '<table class="mini"><thead><tr><th>Название</th><th class="num">от</th><th class="num">до</th><th class="num">K</th></tr></thead><tbody>' +
        serial.map(function (s) { return '<tr><td>' + esc(s.label || '') + '</td><td class="num">' + s.qty_min + '</td><td class="num">' + (s.qty_max == null ? '∞' : s.qty_max) + '</td><td class="num">' + s.factor + '</td></tr>'; }).join('') + '</tbody></table>';
    });
  }

  function loadAnalogs(q) {
    return rpc('app_analogs_list', { p_token: token, p_q: q || null }).then(function (r) {
      analogs = r || [];
      $('#aList').innerHTML = analogs.length ? '<table class="mini"><thead><tr><th>Название</th><th>Материал</th><th>Операция</th><th class="num">Масса</th><th class="num">Норма</th><th></th></tr></thead><tbody>' +
        analogs.map(function (a) { return '<tr><td>' + esc(a.name) + '</td><td>' + esc(a.material || '') + '</td><td>' + esc(a.operation || '') + '</td><td class="num">' + (a.weight == null ? '' : a.weight) + '</td><td class="num">' + (a.norm_base == null ? '' : a.norm_base) + '</td><td><button class="btn secondary" data-adel="' + a.id + '" style="width:auto;padding:3px 8px;font-size:.72rem;">×</button></td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Аналогов нет.</span>';
      $$('#aList [data-adel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_analog_delete', { p_token: token, p_id: b.dataset.adel }).then(function () { loadAnalogs($('#aQ').value); }); }); });
    });
  }

  function loadHistory() {
    return rpc('app_calc_list', { p_token: token, p_kind: 'norm', p_q: null }).then(function (r) {
      var rows = r || [];
      $('#hList').innerHTML = rows.length ? rows.map(function (c) {
        var rs = c.result || {};
        return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;"><b>' + esc(c.title || 'Расчёт') + '</b>' +
          '<span class="note" style="margin-left:auto;">норма ' + (rs.norm_sale != null ? rs.norm_sale + ' ₽/н·ч' : '') + '</span></div>' +
          '<div class="note mt">' + new Date(c.created_at).toLocaleString('ru-RU') + '</div></div>';
      }).join('') : '<span class="note">История пуста.</span>';
    });
  }

  // Калькулятор
  $('#cCalc').addEventListener('click', function () {
    var args = { p_token: token, p_operation_id: $('#cOp').value, p_complexity: $('#cCx').value, p_qty: parseFloat($('#cQty').value) || 1,
      p_kmaterial: parseFloat($('#cKm').value) || 1, p_kaccuracy: parseFloat($('#cKa').value) || 1,
      p_kgeometry: parseFloat($('#cKg').value) || 1, p_kfixture: parseFloat($('#cKf').value) || 1,
      p_base_override: $('#cBase').value ? parseFloat($('#cBase').value) : null };
    rpc('app_norm_calc', args).then(function (r) {
      var x = (r && r[0]) || {}; lastCalc = x; window.__lastNormArgs = args;
      $('#cRes').innerHTML = '<div class="resbox">' +
        '<div class="resline"><span>Норма, ₽/н·ч</span><b>' + x.norm_sale + '</b></div>' +
        '<div class="resline"><span>Себестоимость, ₽/н·ч</span><b>' + x.norm_cost + '</b></div>' +
        '<div class="resline"><span>K-произведение</span><b>' + x.k_product + '</b></div>' +
        '<div class="resline"><span>Серийность</span><b>' + x.serial_factor + '</b></div>' +
        '<div class="resline"><span>Количество</span><b>' + x.qty + '</b></div>' +
        '<div class="resline"><span>Итого (норма × кол-во)</span><b>' + x.total_sale + ' ₽</b></div>' +
        '<div class="note mt">' + esc(x.formula || '') + '</div></div>';
      $('#cSaveRow').style.display = 'flex';
      $('#cTitle').value = (x.operation || 'Норма') + ' (' + x.complexity + ', ' + x.qty + ' шт)';
      msg('#cMsg', 'Расчёт выполнен', 'ok');
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#cSave').addEventListener('click', function () {
    if (!lastCalc) return;
    rpc('app_calc_save', { p_token: token, p_kind: 'norm', p_title: $('#cTitle').value || 'Расчёт нормы',
      p_input: window.__lastNormArgs, p_result: lastCalc, p_ref: null, p_order_id: null })
      .then(function () { msg('#cMsg', 'Сохранено в историю', 'ok'); loadHistory(); loadKpis(); })
      .catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  // Операции
  $('#oClear').addEventListener('click', function () { curOp = null; $('#oCode').value = ''; $('#oName').value = ''; $('#oCat').value = ''; $('#oMt').value = ''; });
  $('#oSave').addEventListener('click', function () {
    rpc('app_norms_op_save', { p_token: token, p_id: curOp ? curOp.id : null, p_code: $('#oCode').value, p_name: $('#oName').value,
      p_category: $('#oCat').value, p_machine_type: $('#oMt').value, p_note: null, p_active: true })
      .then(function (r) { var x = r && r[0]; msg('#oMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); curOp = null; return loadOps().then(loadKpis); })
      .catch(function (e) { msg('#oMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  // K
  $('#kSave').addEventListener('click', function () {
    rpc('app_norms_k_save', { p_token: token, p_id: null, p_category: $('#kCat').value, p_name: $('#kName').value, p_value: parseFloat($('#kVal').value) || 1, p_note: null })
      .then(function () { msg('#kMsg', 'Сохранено', 'ok'); $('#kName').value = ''; return loadK().then(loadKpis); })
      .catch(function (e) { msg('#kMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  // Серийность
  $('#sSave').addEventListener('click', function () {
    var max = $('#sMax').value ? parseInt($('#sMax').value, 10) : null;
    rpc('app_norms_serial_save', { p_token: token, p_id: null, p_label: $('#sLabel').value, p_qty_min: parseInt($('#sMin').value, 10) || 1, p_qty_max: max, p_factor: parseFloat($('#sFactor').value) || 1 })
      .then(function () { msg('#sMsg', 'Сохранено', 'ok'); return loadSerial().then(loadKpis); })
      .catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  // Аналоги
  $('#aSave').addEventListener('click', function () {
    rpc('app_analog_save', { p_token: token, p_id: null, p_name: $('#aName').value, p_material: $('#aMat').value, p_operation: $('#aOp').value,
      p_weight: $('#aW').value ? parseFloat($('#aW').value) : null, p_dims: $('#aDims').value, p_norm_base: $('#aNorm').value ? parseFloat($('#aNorm').value) : null,
      p_tags: $('#aTags').value, p_note: null })
      .then(function () { msg('#aMsg', 'Аналог добавлен', 'ok'); $('#aName').value = ''; return loadAnalogs($('#aQ').value).then(loadKpis); })
      .catch(function (e) { msg('#aMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#aFind').addEventListener('click', function () {
    rpc('app_analog_find', { p_token: token, p_material: $('#aFMat').value, p_operation: $('#aFOp').value, p_weight: $('#aFW').value ? parseFloat($('#aFW').value) : null })
      .then(function (r) {
        var rows = r || [];
        $('#aFindRes').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Аналог</th><th>Материал</th><th>Операция</th><th class="num">Масса</th><th class="num">Норма</th><th class="num">Совпадение</th></tr></thead><tbody>' +
          rows.map(function (a) { return '<tr><td>' + esc(a.name) + '</td><td>' + esc(a.material || '') + '</td><td>' + esc(a.operation || '') + '</td><td class="num">' + (a.weight == null ? '' : a.weight) + '</td><td class="num">' + (a.norm_base == null ? '' : a.norm_base) + '</td><td class="num">' + a.score + '</td></tr>'; }).join('') + '</tbody></table>'
          : '<span class="note">Аналоги не найдены.</span>';
      }).catch(function (e) { msg('#aMsg', e.message, 'err'); });
  });
  $('#aQ').addEventListener('input', function () { loadAnalogs(this.value); });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#cMsg', 'Supabase не подключён.', 'err'); return; }
    renderTabs(); showTab();
    Promise.all([loadKpis(), loadOps(), loadK(), loadSerial(), loadAnalogs(null), loadHistory()]);
  });
})();
