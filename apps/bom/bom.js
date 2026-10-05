/* ============================================================
   3DMP Service · apps/bom — Спецификации (BOM) + себестоимость
   Данные: 0010+0039. Создание из техпроцесса. Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, boms = [], mats = [], oprs = [], orders = [], tpls = [], lines = [], cur = null, qstr = '';

  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return num(v).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return Promise.all([
      rpc('app_bom_list', { p_token: token }),
      rpc('app_material_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_operations_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_process_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      boms = r[0] || []; mats = r[1] || []; oprs = r[2] || []; orders = r[3] || []; tpls = r[4] || [];
      $('#bOrder').innerHTML = '<option value="">— без заявки —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      $('#bTemplate').innerHTML = '<option value="">— выбрать шаблон —</option>' + tpls.map(function (t) { return '<option value="' + t.id + '">' + esc(t.code ? t.code + ' · ' : '') + esc(t.name) + '</option>'; }).join('');
      renderKpi(); renderList();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    var withTpl = boms.filter(function (b) { return b.source_template_id; }).length;
    $('#kpis').innerHTML = cell('Спецификаций', boms.length) + cell('Из техпроцесса', withTpl) +
      cell('С позициями', boms.filter(function (b) { return num(b.lines_count) > 0; }).length);
    function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  }
  function filtered() {
    var s = qstr.toLowerCase();
    return boms.filter(function (b) { return !s || [b.product, b.product_code, b.order_number].join(' ').toLowerCase().indexOf(s) >= 0; });
  }
  function renderList() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Спецификаций нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (b) {
      return '<div class="ocard" data-id="' + b.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;"><b style="font-size:.94rem;">' + esc(b.product) + '</b>' +
        (b.product_code ? '<span class="badge">' + esc(b.product_code) + '</span>' : '') +
        (b.source_template_id ? '<span class="badge done">из техпроцесса</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + num(b.lines_count) + ' поз. · ' + num(b.norm_hours_sum) + ' н/ч</span></div>' +
        '<div style="font-size:.78rem;color:var(--muted);margin-top:5px;">вер. ' + esc(b.version || '1') +
        (b.order_number ? ' · 📥 ' + esc(b.order_number) : '') + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function openItem(id) {
    cur = boms.filter(function (b) { return b.id === id; })[0]; if (!cur) return;
    $('#bomView').innerHTML =
      '<b style="font-size:1rem;">' + esc(cur.product) + '</b>' +
      kv('Код', cur.product_code) + kv('Версия', cur.version || '1') + kv('Заявка', cur.order_number) +
      kv('Количество', cur.qty != null ? String(cur.qty) : '') + kv('Позиций', String(cur.lines_count)) + kv('Нормо-часы', String(cur.norm_hours_sum)) +
      '<div class="toolbar mt"><button class="btn secondary" id="bomNar" style="width:auto;padding:9px 16px;">Создать наряд</button>' +
      '<button class="btn secondary" id="bomWo" style="width:auto;padding:9px 16px;">Списать материалы</button></div>';
    var nb = $('#bomNar'), wb = $('#bomWo');
    if (nb) nb.addEventListener('click', function () {
      rpc('app_naryad_from_bom', { p_token: token, p_bom_id: cur.id, p_wc_id: null, p_assignee: null, p_due_date: null })
        .then(function (d) { var r = d && d[0]; if (!r) { ui.toast('Ошибка'); return; } window.Auth.log('Наряд из BOM', r.number); ui.toast(r.message + ': ' + r.number); if (window.AppNotify) window.AppNotify.refresh(true); })
        .catch(function (e) { ui.toast('Ошибка: ' + e.message); });
    });
    if (wb) wb.addEventListener('click', function () {
      rpc('app_bom_writeoff', { p_token: token, p_bom_id: cur.id, p_order_id: cur.order_id || null, p_qty: cur.qty || 1 })
        .then(function (d) { var r = d && d[0]; if (!r || !r.ok) { ui.toast((r && r.message) || 'Ошибка'); return; } window.Auth.log('Списание по BOM', cur.product); ui.toast(r.message); if (window.AppNotify) window.AppNotify.refresh(true); })
        .catch(function (e) { ui.toast('Ошибка: ' + e.message); });
    });
    rpc('app_bom_lines_list', { p_token: token, p_bom_id: id }).then(function (ls) {
      ls = ls || [];
      $('#bomLines').innerHTML = ls.length ? ls.map(function (l) {
        return '<div class="kvr"><span class="badge">' + (l.item_type === 'material' ? '🧱' : '⚙️') + '</span><b>' + esc(l.name) + '</b>' +
          '<span class="note">' + num(l.qty) + ' ' + esc(l.unit || '') + (l.norm_hours ? ' · ' + num(l.norm_hours) + ' н/ч' : '') + '</span>' +
          '<span class="note" style="margin-left:auto;">' + money(l.cost) + '</span></div>';
      }).join('') : '<span class="note">Позиций нет.</span>';
    });
    rpc('app_bom_cost', { p_token: token, p_bom_id: id, p_qty: cur.qty || 1 }).then(function (r) {
      var c = (r && r[0]) || { materials_cost: 0, work_cost: 0, total: 0 };
      $('#bomCost').innerHTML = '<div class="sum">' +
        '<div class="cell"><small>Материалы</small><b>' + money(c.materials_cost) + '</b></div>' +
        '<div class="cell"><small>Работы</small><b>' + money(c.work_cost) + '</b></div>' +
        '<div class="cell"><small>Итого (+15%)</small><b>' + money(c.total) + '</b></div></div>';
    }).catch(function () { $('#bomCost').innerHTML = '<span class="note">Расчёт недоступен.</span>'; });
    screens.go('s-item');
  }

  function renderLines() {
    $('#lineCount').textContent = lines.length + ' поз.';
    $('#lines').innerHTML = lines.map(function (l, i) {
      var mid;
      if (l.item_type === 'material') {
        mid = '<select data-i="' + i + '" data-k="material_id"><option value="">— материал —</option>' +
          mats.map(function (m) { return '<option value="' + m.id + '"' + (l.material_id === m.id ? ' selected' : '') + '>' + esc(m.name) + '</option>'; }).join('') + '</select>';
      } else {
        mid = '<select data-i="' + i + '" data-k="operation_id"><option value="">— операция —</option>' +
          oprs.map(function (o) { return '<option value="' + o.id + '"' + (l.operation_id === o.id ? ' selected' : '') + '>' + esc(o.name) + '</option>'; }).join('') + '</select>';
      }
      return '<div class="line">' +
        '<select data-i="' + i + '" data-k="item_type"><option value="material"' + (l.item_type === 'material' ? ' selected' : '') + '>Материал</option><option value="operation"' + (l.item_type === 'operation' ? ' selected' : '') + '>Операция</option></select>' +
        mid +
        '<input type="text" data-i="' + i + '" data-k="qty" inputmode="decimal" value="' + num(l.qty) + '">' +
        '<input type="text" data-i="' + i + '" data-k="unit" value="' + esc(l.unit || '') + '" placeholder="ед.">' +
        '<input type="text" data-i="' + i + '" data-k="norm_hours" inputmode="decimal" value="' + num(l.norm_hours) + '">' +
        '<button class="rm" data-rm="' + i + '">✕</button></div>';
    }).join('');
    $$('#lines [data-k]').forEach(function (el) {
      el.addEventListener('change', function () {
        var i = parseInt(el.dataset.i, 10), k = el.dataset.k;
        if (k === 'item_type') { lines[i] = { item_type: el.value, material_id: null, operation_id: null, name: '', qty: 1, unit: '', norm_hours: 0 }; renderLines(); return; }
        if (k === 'material_id') { lines[i].material_id = el.value || null; var m = mats.filter(function (x) { return x.id === el.value; })[0]; if (m) { lines[i].name = m.name; lines[i].unit = m.unit || lines[i].unit; } return; }
        if (k === 'operation_id') { lines[i].operation_id = el.value || null; var o = oprs.filter(function (x) { return x.id === el.value; })[0]; if (o) { lines[i].name = o.name; lines[i].unit = 'н/ч'; } return; }
        if (k === 'qty' || k === 'norm_hours') lines[i][k] = parseFloat(String(el.value).replace(',', '.')) || 0;
        else lines[i][k] = el.value;
      });
    });
    $$('#lines .rm').forEach(function (b) { b.addEventListener('click', function () { lines.splice(parseInt(b.dataset.rm, 10), 1); renderLines(); }); });
  }

  $('#toForm').addEventListener('click', function () {
    lines = [{ item_type: 'material', material_id: null, name: '', qty: 1, unit: '', norm_hours: 0 }];
    ['#bProduct', '#bCode', '#bQty'].forEach(function (s) { $(s).value = ''; });
    $('#bVersion').value = '1'; $('#bOrder').value = ''; $('#bTemplate').value = '';
    renderLines(); clearMsg('#fMsg'); screens.go('s-form');
  });
  $('#addLine').addEventListener('click', function () { lines.push({ item_type: 'material', material_id: null, operation_id: null, name: '', qty: 1, unit: '', norm_hours: 0 }); renderLines(); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  $('#q').addEventListener('input', function () { qstr = this.value; renderList(); });

  $('#fromTplBtn').addEventListener('click', function () {
    var tid = $('#bTemplate').value;
    if (!tid) { msg('#fMsg', 'Выберите техпроцесс.', 'err'); return; }
    var qty = parseFloat(($('#bQty').value || '').replace(',', '.'));
    rpc('app_bom_from_template', { p_token: token, p_template_id: tid, p_order_id: $('#bOrder').value || null,
      p_product: $('#bProduct').value.trim(), p_qty: isNaN(qty) ? 1 : qty })
      .then(function (d) { var r = d && d[0]; if (!r) { msg('#fMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('BOM из техпроцесса', tid); ui.toast('Спецификация создана из техпроцесса');
        load().then(function () { openItem(r.id); }); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#saveBom').addEventListener('click', function () {
    var product = $('#bProduct').value.trim();
    if (!product) { msg('#fMsg', 'Укажите изделие.', 'err'); return; }
    var qty = parseFloat(($('#bQty').value || '').replace(',', '.'));
    var payload = lines.filter(function (l) { return (l.item_type === 'material' && l.material_id) || (l.item_type === 'operation' && l.operation_id) || (l.name || '').trim(); })
      .map(function (l) { return { item_type: l.item_type, material_id: l.material_id || null, operation_id: l.operation_id || null, name: l.name || '', qty: num(l.qty), unit: l.unit || '', norm_hours: num(l.norm_hours) }; });
    rpc('app_bom_save', { p_token: token, p_id: null, p_order_id: $('#bOrder').value || null, p_product: product,
      p_version: $('#bVersion').value.trim(), p_lines: payload, p_product_code: $('#bCode').value.trim(), p_qty: isNaN(qty) ? null : qty })
      .then(function (d) { var r = d && d[0]; if (!r) { msg('#fMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('Спецификация', product); ui.toast('Спецификация сохранена');
        load().then(function () { openItem(r.id); }); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
