/* ============================================================
   3DMP Service · apps/docbuilder — конструктор документов (Партия B, L3).
   Данные: 0105 (app_doc_type_schemas / app_doc_create_typed /
   app_doc_fields_save / app_doc_render_text / app_doc_typed_list).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null, role = null, types = [], list = [], editId = null, curId = null;

  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function loadTypes() {
    return rpc('app_doc_type_schemas', { p_token: token }).then(function (r) {
      types = r || [];
      var opts = types.map(function (t) { return '<option value="' + t.schema_id + '" data-code="' + esc(t.code) + '">' + t.icon + ' ' + esc(t.name) + '</option>'; }).join('');
      $('#dType').innerHTML = '<option value="">— тип документа —</option>' + opts;
      $('#fType2').innerHTML = '<option value="">Все типы</option>' + types.map(function (t) { return '<option value="' + esc(t.code) + '">' + t.icon + ' ' + esc(t.name) + '</option>'; }).join('');
    });
  }

  function refOptions(src) {
    if (!src) return Promise.resolve([]);
    var p = src.split(':');
    return rpc('app_ref_options', { p_token: token, p_kind: p[0], p_code: p[1] || null }).catch(function () { return []; });
  }

  function renderForm(fs, values) {
    values = values || {};
    if (!fs.length) { $('#dForm').innerHTML = '<span class="note">У этого типа нет полей.</span>'; return; }
    $('#dForm').innerHTML = fs.map(function (f) {
      var id = 'f_' + f.code, wide = (f.field_type === 'textarea' || f.field_type === 'table');
      var h = '<div class="field" data-code="' + esc(f.code) + '"' + (wide ? ' style="grid-column:1/-1"' : '') + '>';
      h += '<label>' + esc(f.label) + (f.required ? ' <span class="req">*</span>' : '') + '</label>';
      if (f.field_type === 'textarea') h += '<textarea id="' + id + '" rows="3"></textarea>';
      else if (f.field_type === 'select') {
        var o = (f.options || '').split(',').map(function (s) { return s.trim(); }).filter(Boolean);
        h += '<select id="' + id + '"><option value="">— выберите —</option>' + o.map(function (x) { return '<option>' + esc(x) + '</option>'; }).join('') + '</select>';
      } else if (f.field_type === 'bool') h += '<label class="note"><input type="checkbox" id="' + id + '"> да</label>';
      else if (f.field_type === 'ref') h += '<select id="' + id + '"><option value="">Загрузка…</option></select>';
      else { var t = f.field_type === 'number' ? 'number' : (f.field_type === 'date' ? 'date' : 'text'); h += '<input type="' + t + '" id="' + id + '">'; }
      h += '</div>';
      return h;
    }).join('');
    fs.forEach(function (f) {
      var el = $('#f_' + f.code); if (!el) return;
      var v = values[f.code];
      if (f.field_type === 'bool') el.checked = (v === 'да' || v === true);
      else if (v != null && v !== '') el.value = v;
      else if (f.default_value) el.value = f.default_value;
    });
    fs.filter(function (f) { return f.field_type === 'ref'; }).forEach(function (f) {
      refOptions(f.ref_source).then(function (opts) {
        var el = $('#f_' + f.code); if (!el) return;
        el.innerHTML = '<option value="">— выберите —</option>' + opts.map(function (o) { return '<option value="' + esc(o.value) + '">' + esc(o.label) + '</option>'; }).join('');
        if (values[f.code]) el.value = values[f.code];
      });
    });
  }

  function collectFields() {
    var obj = {};
    ui.qsa('#dForm [data-code]').forEach(function (w) {
      var code = w.getAttribute('data-code'), el = w.querySelector('input,select,textarea');
      if (!el) return;
      obj[code] = el.type === 'checkbox' ? (el.checked ? 'да' : '') : el.value;
    });
    return obj;
  }

  function loadFields(schemaId, values) {
    return rpc('app_schema_fields_list', { p_token: token, p_schema_id: schemaId }).then(function (fs) { renderForm(fs || [], values); });
  }

  function loadList() {
    return rpc('app_doc_typed_list', { p_token: token, p_doc_type: $('#fType2').value || null, p_q: $('#q').value || null }).then(function (r) {
      list = r || []; render();
      var byType = {}; list.forEach(function (d) { byType[d.doc_type] = (byType[d.doc_type] || 0) + 1; });
      $('#kpis').innerHTML = cell('Всего', list.length) + cell('Типов', Object.keys(byType).length) + cell('Черновиков', list.filter(function (d) { return d.status === 'draft'; }).length);
    });
  }

  function render() {
    $('#cnt').textContent = '(' + list.length + ')';
    $('#list').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>№</th><th>Тип</th><th>Название</th><th>Статус</th><th class="num">Сумма</th><th>Создан</th></tr></thead><tbody>' +
      list.map(function (d) {
        var t = types.filter(function (x) { return x.code === d.doc_type; })[0] || {};
        return '<tr data-open="' + d.id + '"><td>' + esc(d.number || '') + '</td><td>' + (t.icon || '') + ' ' + esc(t.name || d.doc_type) + '</td><td>' + esc(d.title || '') + '</td>' +
          '<td><span class="badge">' + esc(d.status || '') + '</span></td><td class="num">' + (d.amount != null ? Number(d.amount).toLocaleString('ru-RU') : '—') + '</td>' +
          '<td class="muted">' + new Date(d.created_at).toLocaleDateString('ru-RU') + '</td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Документов нет.</span>';
    ui.qsa('#list [data-open]').forEach(function (tr) { tr.addEventListener('click', function () { preview(tr.dataset.open); }); });
  }

  function preview(id) {
    curId = id;
    rpc('app_doc_render_text', { p_token: token, p_id: id }).then(function (r) {
      var d = r && r[0]; if (!d) return;
      $('#pvTitle').textContent = (d.number || '') + ' · ' + (d.title || '');
      $('#pvText').textContent = d.content || '';
      $('#pvWrap').style.display = 'block';
      $('#pvWrap').scrollIntoView({ behavior: 'smooth' });
    }).catch(function (e) { msg('#mMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function startEdit(id) {
    var row = list.filter(function (d) { return d.id === id; })[0];
    if (!row) return;
    rpc('app_doc_render_text', { p_token: token, p_id: id }).then(function (r) {
      var d = r && r[0]; if (!d) return;
      editId = id;
      $('#dType').value = row.schema_id || '';
      $('#dType').disabled = true;
      $('#dTitle').value = d.title || '';
      loadFields(row.schema_id, d.fields || {});
      $('#dCreate').textContent = 'Сохранить поля';
      $('#dMsg').className = 'msg'; $('#dMsg').textContent = '';
      document.querySelector('main').scrollIntoView({ behavior: 'smooth' });
    });
  }

  function resetForm() {
    editId = null; $('#dType').disabled = false; $('#dType').value = ''; $('#dTitle').value = '';
    $('#dForm').innerHTML = '<span class="note">Выберите тип документа.</span>';
    $('#dCreate').textContent = 'Создать документ';
    $('#dMsg').className = 'msg'; $('#dMsg').textContent = '';
  }

  function loadSources() {
    var p1 = rpc('app_bom_list', { p_token: token }).then(function (r) {
      var a = r || [];
      $('#srcBom').innerHTML = '<option value="">— спецификация —</option>' + a.map(function (b) {
        return '<option value="' + b.id + '">' + esc(b.product || 'BOM') + (b.order_number ? ' · ' + esc(b.order_number) : '') + '</option>';
      }).join('');
    }).catch(function () {});
    var p2 = rpc('app_equipment_price_options', { p_token: token }).then(function (r) {
      var a = r || [];
      $('#srcEquip').innerHTML = a.map(function (e) {
        return '<option value="' + e.id + '">' + esc(e.name) + (e.price != null ? ' — ' + Number(e.price).toLocaleString('ru-RU') + ' ' + esc(e.currency || '') : '') + '</option>';
      }).join('');
    }).catch(function () {});
    var p4 = rpc('app_qc_list', { p_token: token }).then(function (r) {
      var a = r || [];
      $('#srcQc').innerHTML = '<option value="">— проверка ОТК —</option>' + a.map(function (q) {
        return '<option value="' + q.id + '">' + esc(q.number || '') + ' · ' + esc(q.product || '') + (q.status ? ' [' + esc(q.status) + ']' : '') + '</option>';
      }).join('');
    }).catch(function () {});
    var p5 = rpc('app_passport_list', { p_token: token }).then(function (r) {
      var a = r || [];
      $('#srcPass').innerHTML = '<option value="">— паспорт —</option>' + a.map(function (pp) {
        return '<option value="' + pp.id + '">' + esc(pp.number || '') + ' · ' + esc(pp.product || '') + (pp.serial ? ' · ' + esc(pp.serial) : '') + '</option>';
      }).join('');
    }).catch(function () {});
    var p3 = rpc('app_route_list', { p_token: token }).then(function (r) {
      var a = r || [];
      $('#srcRoute').innerHTML = '<option value="">— маршрут —</option>' + a.map(function (rt) {
        return '<option value="' + rt.id + '">' + esc(rt.number || '') + ' · ' + esc(rt.name || '') + (rt.order_number ? ' · ' + esc(rt.order_number) : '') + ' (' + (rt.step_count || 0) + ' шаг.)</option>';
      }).join('');
    }).catch(function () {});
    return Promise.all([p1, p2, p3, p4, p5]);
  }

  /* ---------- события ---------- */
  $('#qFromBom').addEventListener('click', function () {
    var id = $('#srcBom').value; if (!id) { msg('#sMsg', 'Выберите спецификацию', 'err'); return; }
    rpc('app_quote_from_bom', { p_token: token, p_bom_id: id, p_margin_pct: parseFloat($('#bomMargin').value) || 0, p_valid_days: 30 })
      .then(function (r) { var x = r && r[0]; msg('#sMsg', x ? (x.message + ': ' + x.number + ' — ' + Number(x.amount).toLocaleString('ru-RU') + ' ₽') : 'Ошибка', x ? 'ok' : 'err'); if (x) { window.Auth.log('КП из спецификации', x.number); loadList(); preview(x.id); } })
      .catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#rFromBom').addEventListener('click', function () {
    var id = $('#srcBom').value; if (!id) { msg('#sMsg', 'Выберите спецификацию', 'err'); return; }
    rpc('app_route_from_bom', { p_token: token, p_bom_id: id, p_name: null })
      .then(function (r) { var x = r && r[0]; msg('#sMsg', x ? (x.message + ': ' + x.number) : 'Ошибка', x ? 'ok' : 'err'); if (x) { window.Auth.log('Маршрут из BOM', x.number); loadSources(); } })
      .catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#tcFromRoute').addEventListener('click', function () {
    var id = $('#srcRoute').value; if (!id) { msg('#sMsg', 'Выберите маршрут', 'err'); return; }
    rpc('app_doc_from_route', { p_token: token, p_route_id: id })
      .then(function (r) { var x = r && r[0]; msg('#sMsg', x ? (x.message + ': ' + x.number) : 'Ошибка', x ? 'ok' : 'err'); if (x) { window.Auth.log('Техкарта из маршрута', x.number); loadList(); preview(x.id); } })
      .catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#kpFromRoute').addEventListener('click', function () {
    var id = $('#srcRoute').value; if (!id) { msg('#sMsg', 'Выберите маршрут', 'err'); return; }
    rpc('app_quote_from_route', { p_token: token, p_route_id: id, p_margin_pct: parseFloat($('#rtMargin').value) || 0, p_valid_days: 30 })
      .then(function (r) { var x = r && r[0]; msg('#sMsg', x ? (x.message + ': ' + x.number + ' — ' + Number(x.amount).toLocaleString('ru-RU') + ' ₽') : 'Ошибка', x ? 'ok' : 'err'); if (x) { window.Auth.log('КП из маршрута', x.number); loadList(); preview(x.id); } })
      .catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#ncFromRoute').addEventListener('click', function () {
    var id = $('#srcRoute').value; if (!id) { msg('#sMsg', 'Выберите маршрут', 'err'); return; }
    rpc('app_nc_from_route', { p_token: token, p_route_id: id, p_program_no: $('#ncNo').value || null, p_equipment_id: null })
      .then(function (r) { var x = r && r[0]; msg('#sMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('УП из маршрута', id); })
      .catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#protoFromQc').addEventListener('click', function () {
    var id = $('#srcQc').value; if (!id) { msg('#sMsg', 'Выберите проверку ОТК', 'err'); return; }
    rpc('app_doc_from_qc', { p_token: token, p_qc_id: id })
      .then(function (r) { var x = r && r[0]; msg('#sMsg', x ? (x.message + ': ' + x.number) : 'Ошибка', x ? 'ok' : 'err'); if (x) { window.Auth.log('Протокол ОТК', x.number); loadList(); preview(x.id); } })
      .catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#passFromPass').addEventListener('click', function () {
    var id = $('#srcPass').value; if (!id) { msg('#sMsg', 'Выберите паспорт', 'err'); return; }
    rpc('app_doc_from_passport', { p_token: token, p_passport_id: id })
      .then(function (r) { var x = r && r[0]; msg('#sMsg', x ? (x.message + ': ' + x.number) : 'Ошибка', x ? 'ok' : 'err'); if (x) { window.Auth.log('Паспорт-документ', x.number); loadList(); preview(x.id); } })
      .catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#qFromEquip').addEventListener('click', function () {
    var ids = ui.qsa('#srcEquip option:checked').map(function (o) { return o.value; });
    if (!ids.length) { msg('#sMsg', 'Выберите позиции оборудования', 'err'); return; }
    rpc('app_quote_from_equipment', { p_token: token, p_ids: ids, p_margin_pct: parseFloat($('#eqMargin').value) || 0 })
      .then(function (r) { var x = r && r[0]; msg('#sMsg', x ? (x.message + ': ' + x.number + ' — ' + Number(x.amount).toLocaleString('ru-RU') + ' ₽') : 'Ошибка', x ? 'ok' : 'err'); if (x) { window.Auth.log('Прайс оборудования', x.number); loadList(); preview(x.id); } })
      .catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#dType').addEventListener('change', function () {
    if (!this.value) { $('#dForm').innerHTML = '<span class="note">Выберите тип документа.</span>'; return; }
    loadFields(this.value);
  });
  $('#dCreate').addEventListener('click', function () {
    var sid = $('#dType').value; if (!sid) { msg('#dMsg', 'Выберите тип документа', 'err'); return; }
    var fields = collectFields();
    if (editId) {
      rpc('app_doc_fields_save', { p_token: token, p_id: editId, p_fields: fields })
        .then(function (r) { var x = r && r[0]; msg('#dMsg', x ? x.message : 'Сохранено', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { var id = editId; resetForm(); loadList(); preview(id); } })
        .catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
    } else {
      rpc('app_doc_create_typed', { p_token: token, p_schema_id: sid, p_title: $('#dTitle').value, p_fields: fields, p_order_id: null, p_customer_id: null, p_amount: null })
        .then(function (r) { var x = r && r[0]; msg('#dMsg', x ? ('Создан ' + x.number) : 'Ошибка', x ? 'ok' : 'err'); if (x) { window.Auth.log('Документ создан', x.number); resetForm(); loadList(); preview(x.id); } })
        .catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
    }
  });
  $('#dReset').addEventListener('click', resetForm);
  $('#fType2').addEventListener('change', loadList);
  $('#q').addEventListener('input', loadList);
  $('#pvPrint').addEventListener('click', function () { window.print(); });
  $('#pvEdit').addEventListener('click', function () { if (curId) startEdit(curId); });
  $('#pvClose').addEventListener('click', function () { $('#pvWrap').style.display = 'none'; curId = null; });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role) && s.role !== 'client') { location.href = '../dashboard/index.html'; return; }
    token = s.token; role = s.role;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#mMsg', 'Supabase не подключён.', 'err'); return; }
    loadTypes().then(loadList).then(loadSources);
  });
})();
