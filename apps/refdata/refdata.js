/* ============================================================
   3DMP Service · apps/refdata — отраслевые справочники (ЧПУ, инструмент).
   Данные: 0261 (app_ref_cnc / app_ref_tool). R5·PROP-35.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, cnc = [], tools = [], cq = '', tq = '';

  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_ref_cnc_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_ref_tool_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      cnc = r[0] || []; tools = r[1] || [];
      $('#kpis').innerHTML = cell('Стойки ЧПУ', cnc.length) + cell('Инструмент', tools.length);
      renderCnc(); renderTools();
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderCnc() {
    var s = cq.toLowerCase();
    var rows = cnc.filter(function (c) { return !s || [c.vendor, c.model, c.cnc_system, c.postprocessor].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cList').innerHTML = rows.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Произв.</th><th>Модель</th><th>Система ЧПУ</th><th class="num">Осей</th><th class="num">Об/мин</th><th>Постпроц.</th><th></th></tr></thead><tbody>' +
      rows.map(function (c) {
        return '<tr><td>' + esc(c.vendor || '—') + '</td><td><b>' + esc(c.model) + '</b></td><td>' + esc(c.cnc_system || '—') + '</td>' +
          '<td class="num">' + (c.axes == null ? '—' : c.axes) + '</td><td class="num">' + (c.max_rpm == null ? '—' : c.max_rpm) + '</td>' +
          '<td>' + esc(c.postprocessor || '—') + '</td>' +
          '<td><button class="act danger" data-cdel="' + c.id + '" aria-label="Удалить" title="Удалить">✕</button></td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Стойки/станки не заведены — добавьте в форме выше.</span>';
    $$('#cList [data-cdel]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить запись?')) return; rpc('app_ref_cnc_delete', { p_token: token, p_id: b.dataset.cdel }).then(load); }); });
  }
  function renderTools() {
    var s = tq.toLowerCase();
    var rows = tools.filter(function (t) { return !s || [t.kind, t.name, t.material].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#tList').innerHTML = rows.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Тип</th><th>Название</th><th>Материал</th><th class="num">Ø, мм</th><th class="num">r, мм</th><th class="num">Стойк., мин</th><th class="num">Перет.</th><th></th></tr></thead><tbody>' +
      rows.map(function (t) {
        return '<tr><td>' + esc(t.kind || '—') + '</td><td><b>' + esc(t.name) + '</b></td><td>' + esc(t.material || '—') + '</td>' +
          '<td class="num">' + (t.diameter_mm == null ? '—' : t.diameter_mm) + '</td><td class="num">' + (t.corner_radius_mm == null ? '—' : t.corner_radius_mm) + '</td>' +
          '<td class="num">' + (t.life_min == null ? '—' : t.life_min) + '</td><td class="num">' + (t.resharpen_limit == null ? '—' : t.resharpen_limit) + '</td>' +
          '<td><button class="act danger" data-tdel="' + t.id + '" aria-label="Удалить" title="Удалить">✕</button></td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Инструмент не заведён — добавьте в форме выше.</span>';
    $$('#tList [data-tdel]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить запись?')) return; rpc('app_ref_tool_delete', { p_token: token, p_id: b.dataset.tdel }).then(load); }); });
  }

  $('#cq').addEventListener('input', function () { cq = this.value; renderCnc(); });
  $('#tq').addEventListener('input', function () { tq = this.value; renderTools(); });
  $('#cClear').addEventListener('click', function () { ['cVendor', 'cModel', 'cSys', 'cAxes', 'cRpm', 'cPost', 'cNote'].forEach(function (i) { $('#' + i).value = ''; }); msg('#cMsg', ''); });
  $('#tClear').addEventListener('click', function () { ['tKind', 'tName', 'tMat', 'tD', 'tR', 'tLife', 'tResh', 'tNote'].forEach(function (i) { $('#' + i).value = ''; }); msg('#tMsg', ''); });

  $('#cSave').addEventListener('click', function () {
    if (!$('#cModel').value.trim()) { msg('#cMsg', 'Укажите модель.', 'err'); return; }
    rpc('app_ref_cnc_save', { p_token: token, p_id: null, p_vendor: $('#cVendor').value.trim() || null, p_model: $('#cModel').value.trim(), p_cnc_system: $('#cSys').value.trim() || null, p_axes: parseInt($('#cAxes').value, 10) || null, p_max_rpm: parseInt($('#cRpm').value, 10) || null, p_postprocessor: $('#cPost').value.trim() || null, p_note: $('#cNote').value.trim() || null })
      .then(function (r) { var x = r && r[0]; msg('#cMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { $('#cModel').value = ''; load(); } })
      .catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#tSave').addEventListener('click', function () {
    if (!$('#tName').value.trim()) { msg('#tMsg', 'Укажите название.', 'err'); return; }
    rpc('app_ref_tool_save', { p_token: token, p_id: null, p_kind: $('#tKind').value.trim() || null, p_name: $('#tName').value.trim(), p_material: $('#tMat').value.trim() || null, p_diameter: parseFloat($('#tD').value.replace(',', '.')) || null, p_radius: parseFloat($('#tR').value.replace(',', '.')) || null, p_life: parseInt($('#tLife').value, 10) || null, p_resharpen: parseInt($('#tResh').value, 10) || null, p_note: $('#tNote').value.trim() || null })
      .then(function (r) { var x = r && r[0]; msg('#tMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { $('#tName').value = ''; load(); } })
      .catch(function (e) { msg('#tMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#cMsg', 'Supabase не подключён.', 'err'); return; }
    if (window.AppUI && AppUI.dictSuggest) {
      AppUI.dictSuggest('cSys', 'cnc_systems', token);
      AppUI.dictSuggest('tKind', 'tool_kinds', token);
      AppUI.dictSuggest('tMat', 'tool_materials', token);
      AppUI.dictSuggest('cVendor', 'cnc_models', token);
    }
    load();
  });
})();
