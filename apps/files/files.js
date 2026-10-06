/* ============================================================
   3DMP Service · apps/files — вложения (Storage) + сводный журнал. 0075.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, files = [], q = '', ftype = '', BUCKET = 'saas-files';

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function kb(v) { return (v == null ? 0 : (v / 1024).toFixed(0)) + ' КБ'; }

  function loadKpi() {
    return rpc('app_files_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Файлов', k.total || 0) + cell('Объём', kb(k.total_bytes)) + cell('По заявкам', k.orders_files || 0) + cell('Чертежей/PDF', k.drawings || 0);
    });
  }

  function loadFiles() {
    return rpc('app_files_list', { p_token: token, p_entity_type: ftype || null, p_entity_id: null }).then(function (r) {
      files = r || []; renderFiles();
    });
  }

  function renderFiles() {
    var s = q.toLowerCase();
    var rows = files.filter(function (f) { return !s || (f.name || '').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Имя</th><th>Тип</th><th>Размер</th><th>Загрузил</th><th>Дата</th><th></th></tr></thead><tbody>' +
      rows.map(function (f) {
        return '<tr><td>' + esc(f.name) + '</td><td>' + esc(f.entity_type) + '</td><td>' + kb(f.size_bytes) + '</td><td>' + esc(f.uploaded_by || '') + '</td><td>' + new Date(f.created_at).toLocaleDateString('ru-RU') + '</td>' +
          '<td style="white-space:nowrap;"><a class="btn secondary" href="' + esc(f.url) + '" target="_blank" style="width:auto;padding:4px 9px;font-size:.72rem;text-decoration:none;">Открыть</a> ' +
          '<button class="btn secondary" data-del="' + f.id + '" data-path="' + esc(f.path) + '" style="width:auto;padding:4px 9px;font-size:.72rem;">×</button></td></tr>';
      }).join('') + '</tbody></table>' : '<span class="note">Файлов нет.</span>';
    $$('#list [data-del]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_file_delete', { p_token: token, p_id: b.dataset.del }).then(function () {
        try { SB.storage.from(BUCKET).remove([b.dataset.path]); } catch (e) {}
        loadFiles(); loadKpi();
      });
    }); });
  }

  function loadJournal() {
    var lim = parseInt($('#jLimit').value, 10) || 30;
    return rpc('app_journal_list', { p_token: token, p_limit: lim }).then(function (r) {
      var rows = r || [];
      $('#journal').innerHTML = rows.length ? '<div class="olist">' + rows.map(function (j) {
        return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;"><span class="badge">' + esc(j.kind) + '</span><b>' + esc(j.title || '') + '</b>' +
          (j.detail ? '<span class="note">' + esc(j.detail) + '</span>' : '') +
          '<span class="note" style="margin-left:auto;">' + new Date(j.at).toLocaleString('ru-RU') + (j.who ? ' · ' + esc(j.who) : '') + '</span></div></div>';
      }).join('') + '</div>' : '<span class="note">Пусто.</span>';
    });
  }

  function doUpload(file) {
    if (!file) return;
    if (file.size > 10 * 1024 * 1024) { msg('#pMsg', 'Файл больше 10 МБ — отклонён.', 'err'); return; }
    var et = $('#uType').value, eid = $('#uEid').value.trim() || null;
    var safe = file.name.replace(/[^\w.\-]+/g, '_');
    var path = et + '/' + (eid || 'none') + '/' + Date.now() + '_' + safe;
    msg('#pMsg', 'Загрузка…', 'info');
    SB.storage.from(BUCKET).upload(path, file, { upsert: false }).then(function (r) {
      if (r.error) throw new Error(r.error.message);
      return rpc('app_file_register', { p_token: token, p_entity_type: et, p_entity_id: eid, p_name: file.name, p_mime: file.type, p_size: file.size, p_path: path, p_note: $('#uNote').value });
    }).then(function (r) {
      var x = r && r[0];
      msg('#pMsg', x ? x.message : 'Файл загружен', 'ok');
      window.Auth.log('Загружен файл', file.name);
      $('#uNote').value = ''; loadFiles(); loadKpi(); loadJournal();
    }).catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  $('#drop').addEventListener('click', function () { $('#file').click(); });
  $('#file').addEventListener('change', function () { doUpload(this.files[0]); });
  ['dragenter', 'dragover'].forEach(function (ev) { $('#drop').addEventListener(ev, function (e) { e.preventDefault(); this.classList.add('hover'); }); });
  ['dragleave', 'drop'].forEach(function (ev) { $('#drop').addEventListener(ev, function (e) { e.preventDefault(); this.classList.remove('hover'); }); });
  $('#drop').addEventListener('drop', function (e) { doUpload(e.dataTransfer.files[0]); });
  $('#q').addEventListener('input', function () { q = this.value; renderFiles(); });
  $('#fType').addEventListener('change', function () { ftype = this.value; loadFiles(); });
  $('#jRefresh').addEventListener('click', loadJournal);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#uMsg', 'Supabase не подключён.', 'err'); return; }
    loadKpi(); loadFiles(); loadJournal();
  });
})();
