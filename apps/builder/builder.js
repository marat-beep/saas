/* ============================================================
   3DMP Service · apps/builder — P2 App Builder. Данные: 0066.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, entities = [], fields = [], records = [], cur = null, q = '';

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function loadEntities() {
    return rpc('app_entity_list', { p_token: token, p_q: null }).then(function (r) { entities = r || []; renderEntities(); });
  }

  function renderEntities() {
    var s = q.toLowerCase();
    var rows = entities.filter(function (e) { return !s || (e.name + ' ' + (e.code || '')).toLowerCase().indexOf(s) >= 0; });
    $('#eList').innerHTML = rows.length ? rows.map(function (e) {
      return '<div class="ocard" data-e="' + e.id + '"><div style="display:flex;gap:8px;align-items:center;">' +
        '<span>' + esc(e.icon || '🧩') + '</span><b>' + esc(e.name) + '</b>' +
        '<span class="note" style="margin-left:auto;">' + e.fields_count + ' пол. · ' + e.records_count + ' зап.</span></div></div>';
    }).join('') : '<span class="note">Сущностей нет.</span>';
    $$('#eList [data-e]').forEach(function (b) { b.addEventListener('click', function () { open(b.dataset.e); }); });
  }

  function open(id) {
    cur = entities.filter(function (e) { return e.id === id; })[0]; if (!cur) return;
    $('#detailCard').style.display = 'block'; $('#emptyCard').style.display = 'none';
    $('#eTitle').textContent = (cur.icon || '🧩') + ' ' + cur.name;
    $('#eDesc').textContent = cur.description || '';
    Promise.all([
      rpc('app_entity_fields_list', { p_token: token, p_entity_id: id }),
      rpc('app_entity_records_list', { p_token: token, p_entity_id: id, p_q: null })
    ]).then(function (r) { fields = r[0] || []; records = r[1] || []; renderFields(); renderRecordForm(); renderRecords(); });
  }

  function renderFields() {
    $('#fields').innerHTML = fields.length ? '<table class="mini"><thead><tr><th>Название</th><th>Код</th><th>Тип</th><th></th></tr></thead><tbody>' +
      fields.map(function (f) {
        return '<tr><td>' + esc(f.name) + (f.required ? ' *' : '') + '</td><td>' + esc(f.code) + '</td><td>' + esc(f.field_type) + (f.options ? ' (' + esc(f.options) + ')' : '') + '</td>' +
          '<td><button class="btn secondary" data-fd="' + f.id + '" style="width:auto;padding:3px 8px;font-size:.72rem;">×</button></td></tr>';
      }).join('') + '</tbody></table>' : '<span class="note">Полей нет — добавьте первое поле.</span>';
    $$('#fields [data-fd]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_entity_field_delete', { p_token: token, p_id: b.dataset.fd }).then(function () { open(cur.id); });
    }); });
  }

  function renderRecordForm() {
    $('#recForm').innerHTML = fields.map(function (f) {
      var inp;
      if (f.field_type === 'select') {
        inp = '<select id="rf_' + f.code + '"><option value=""></option>' + (f.options || '').split(',').map(function (o) { return '<option value="' + esc(o.trim()) + '">' + esc(o.trim()) + '</option>'; }).join('') + '</select>';
      } else if (f.field_type === 'bool') {
        inp = '<input type="checkbox" id="rf_' + f.code + '">';
      } else if (f.field_type === 'number') {
        inp = '<input type="number" step="any" id="rf_' + f.code + '">';
      } else if (f.field_type === 'date') {
        inp = '<input type="date" id="rf_' + f.code + '">';
      } else if (f.field_type === 'textarea') {
        inp = '<textarea id="rf_' + f.code + '" rows="2" style="width:100%;padding:9px;border:1px solid var(--border);border-radius:9px;"></textarea>';
      } else {
        inp = '<input type="text" id="rf_' + f.code + '">';
      }
      return '<div class="field"><label>' + esc(f.name) + (f.required ? ' *' : '') + '</label>' + inp + '</div>';
    }).join('');
  }

  function renderRecords() {
    $('#rCnt').textContent = '(' + records.length + ')';
    if (!fields.length) { $('#records').innerHTML = '<span class="note">Добавьте поля, затем записи.</span>'; return; }
    $('#records').innerHTML = records.length ? '<table class="mini"><thead><tr>' +
      fields.map(function (f) { return '<th>' + esc(f.name) + '</th>'; }).join('') + '<th></th></tr></thead><tbody>' +
      records.map(function (r) {
        return '<tr>' + fields.map(function (f) {
          var v = r.data ? r.data[f.code] : '';
          if (typeof v === 'boolean') v = v ? '✓' : '';
          return '<td>' + esc(v == null ? '' : v) + '</td>';
        }).join('') + '<td><button class="btn secondary" data-rd="' + r.id + '" style="width:auto;padding:3px 8px;font-size:.72rem;">×</button></td></tr>';
      }).join('') + '</tbody></table>' : '<span class="note">Записей нет.</span>';
    $$('#records [data-rd]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_entity_record_delete', { p_token: token, p_id: b.dataset.rd }).then(function () { open(cur.id); });
    }); });
  }

  $('#q').addEventListener('input', function () { q = this.value; renderEntities(); });
  $('#eSave').addEventListener('click', function () {
    var name = $('#eName').value.trim(); if (!name) { msg('#eMsg', 'Укажите название.', 'err'); return; }
    rpc('app_entity_save', { p_token: token, p_id: null, p_name: name, p_code: $('#eCode').value, p_icon: null, p_description: null, p_active: true })
      .then(function (r) { var x = r && r[0]; msg('#eMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); $('#eName').value = ''; $('#eCode').value = ''; loadEntities(); })
      .catch(function (e) { msg('#eMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#eClear').addEventListener('click', function () { $('#eName').value = ''; $('#eCode').value = ''; msg('#eMsg', ''); });
  $('#fAdd').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_entity_field_save', { p_token: token, p_id: null, p_entity_id: cur.id, p_name: $('#fName').value,
      p_code: $('#fCode').value, p_field_type: $('#fType').value, p_options: $('#fOptions').value, p_required: false, p_sort: fields.length * 10 + 10 })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); $('#fName').value = ''; $('#fCode').value = ''; $('#fOptions').value = ''; open(cur.id); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#rSave').addEventListener('click', function () {
    if (!cur) return;
    var data = {};
    fields.forEach(function (f) {
      var el = $('#rf_' + f.code); if (!el) return;
      if (f.field_type === 'bool') data[f.code] = el.checked;
      else if (f.field_type === 'number') { var n = parseFloat(el.value); data[f.code] = isNaN(n) ? null : n; }
      else data[f.code] = el.value;
    });
    rpc('app_entity_record_save', { p_token: token, p_id: null, p_entity_id: cur.id, p_data: data })
      .then(function (r) { var x = r && r[0]; msg('#rMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); open(cur.id); })
      .catch(function (e) { msg('#rMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#rReset').addEventListener('click', function () { if (cur) renderRecordForm(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#eMsg', 'Supabase не подключён.', 'err'); return; }
    loadEntities();
  });
})();
