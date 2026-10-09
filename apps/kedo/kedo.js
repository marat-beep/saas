/* ============================================================
   3DMP Service · apps/kedo — КЭДО (W20, 0165).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, docs = [], tpls = [], mchds = [];
  var TP = { hire: 'Приём', transfer: 'Перевод', dismiss: 'Увольнение', vacation: 'Отпуск', sick: 'Больничный', ack: 'Ознакомление', order: 'Приказ', other: 'Прочее' };
  var ST = { draft: 'Черновик', sent: 'Отправлен', signed: 'Подписан', declined: 'Отклонён', archived: 'Архив' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dd(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'docs') loadDocs();
    if (scr === 'me') loadMy();
    if (scr === 'tpl') loadTpl();
    if (scr === 'mchd') loadMchd();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_kedo_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Документов', k.total || 0) + cell('Черновики', k.draft || 0) + cell('На подпись', k.sent || 0) + cell('Подписано', k.signed || 0) + cell('МЧД активных', k.mchd_active || 0) + cell('Шаблонов', k.templates || 0);
    });
  }
  function loadDocs() {
    return rpc('app_hr_docs_list', { p_token: token, p_status: $('#status').value || null, p_type: null, p_employee: $('#q').value || null }).then(function (r) {
      docs = r || [];
      $('#docs').innerHTML = docs.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Сотрудник</th><th>Тип</th><th>Название</th><th>№</th><th>Статус</th><th>Подписан</th><th>Действия</th></tr></thead><tbody>' +
        docs.map(function (d) {
          var acts = '';
          if (d.status === 'draft') acts += '<button class="act" data-a="send" data-id="' + d.id + '">Отправить</button><button class="act danger" data-del="' + d.id + '">Удалить</button>';
          if (d.status === 'sent') acts += '<button class="act" data-a="sign" data-id="' + d.id + '">Подписать</button><button class="act danger" data-a="decline" data-id="' + d.id + '">Отклонить</button>';
          if (d.status === 'signed') acts += '<button class="act" data-a="archive" data-id="' + d.id + '">В архив</button>';
          return '<tr><td>' + esc(d.employee_login || '') + '</td><td>' + esc(TP[d.doc_type] || d.doc_type) + '</td><td><b>' + esc(d.title) + '</b></td><td>' + esc(d.number || '—') + '</td><td>' + esc(ST[d.status] || d.status) + '</td><td class="muted">' + dd(d.signed_at) + (d.sign_method ? ' (' + esc(d.sign_method) + ')' : '') + '</td><td style="white-space:nowrap;">' + acts + '</td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Документов нет.</span>';
      $$('#docs [data-a]').forEach(function (b) { b.addEventListener('click', function () { act(b.dataset.id, b.dataset.a); }); });
      $$('#docs [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить документ?')) return; rpc('app_hr_doc_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadDocs(); loadKpi(); }); }); });
    });
  }
  function act(id, a) {
    var cm = (a === 'sign' || a === 'decline') ? prompt('Комментарий:', '') : null;
    rpc('app_hr_doc_sign', { p_token: token, p_id: id, p_action: a, p_comment: cm }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadDocs(); loadKpi(); });
  }
  function docForm() {
    ui.formDialog({ title: 'Кадровый документ', okText: 'Создать', fields: [
      { name: 'employee', label: 'Сотрудник (логин)', type: 'text', required: true },
      { name: 'doc_type', label: 'Тип', type: 'select', options: Object.keys(TP).map(function (k) { return { value: k, label: TP[k] }; }) },
      { name: 'title', label: 'Название', type: 'text', required: true },
      { name: 'payload', label: 'Данные (JSON)', type: 'textarea', rows: 2 }
    ], values: { doc_type: 'vacation', payload: '{}' } }).then(function (v) {
      if (!v) return;
      var pl; try { pl = JSON.parse(v.payload || '{}'); } catch (e) { msg('Некорректный JSON', 'err'); return; }
      rpc('app_hr_doc_save', { p_token: token, p_id: null, p_employee: v.employee, p_doc_type: v.doc_type, p_title: v.title, p_payload: pl })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadDocs(); loadKpi(); });
    });
  }
  function loadMy() {
    return rpc('app_hr_my_docs', { p_token: token }).then(function (r) {
      var list = r || [];
      $('#my').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Тип</th><th>Название</th><th>Статус</th><th>Действия</th></tr></thead><tbody>' +
        list.map(function (d) { return '<tr><td>' + esc(TP[d.doc_type] || d.doc_type) + '</td><td>' + esc(d.title) + '</td><td>' + esc(ST[d.status] || d.status) + '</td>' +
          '<td style="white-space:nowrap;">' + (d.status === 'sent' ? '<button class="act" data-a="sign" data-id="' + d.id + '">Ознакомлен/подписать</button><button class="act danger" data-a="decline" data-id="' + d.id + '">Отклонить</button>' : '') + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Документов нет.</span>';
      $$('#my [data-a]').forEach(function (b) { b.addEventListener('click', function () { act(b.dataset.id, b.dataset.a); loadMy(); }); });
    });
  }
  function loadTpl() {
    return rpc('app_hr_templates_list', { p_token: token }).then(function (r) {
      tpls = r || [];
      $('#tpl').innerHTML = tpls.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Код</th><th>Название</th><th>Тип</th><th></th></tr></thead><tbody>' +
        tpls.map(function (t) { return '<tr><td>' + esc(t.code || '') + '</td><td><b>' + esc(t.name) + '</b></td><td>' + esc(TP[t.doc_type] || t.doc_type || '') + '</td><td><button class="act" data-edit="' + t.id + '">Изменить</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Шаблонов нет.</span>';
      $$('#tpl [data-edit]').forEach(function (b) { b.addEventListener('click', function () { tplForm(tpls.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
    });
  }
  function tplForm(t) {
    t = t || {};
    ui.formDialog({ title: t.id ? 'Шаблон' : 'Новый шаблон', okText: 'Сохранить', fields: [
      { name: 'code', label: 'Код', type: 'text' }, { name: 'name', label: 'Название', type: 'text', required: true },
      { name: 'doc_type', label: 'Тип', type: 'select', options: Object.keys(TP).map(function (k) { return { value: k, label: TP[k] }; }) },
      { name: 'body', label: 'Текст шаблона', type: 'textarea', rows: 4 }
    ], values: { code: t.code || '', name: t.name || '', doc_type: t.doc_type || 'vacation', body: t.body || '' } }).then(function (v) {
      if (!v) return;
      rpc('app_hr_template_save', { p_token: token, p_id: t.id || null, p_code: v.code || null, p_name: v.name, p_doc_type: v.doc_type, p_body: v.body || null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadTpl(); loadKpi(); });
    });
  }
  function loadMchd() {
    return rpc('app_mchd_list', { p_token: token }).then(function (r) {
      mchds = r || [];
      $('#mchd').innerHTML = mchds.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Номер</th><th>Доверенное лицо</th><th>Полномочия</th><th>Срок</th><th>Статус</th><th></th></tr></thead><tbody>' +
        mchds.map(function (m) { return '<tr><td>' + esc(m.number || '') + '</td><td>' + esc(m.issued_to_login || '') + '</td><td class="muted">' + esc(m.authority || '') + '</td><td>' + dd(m.valid_from) + '—' + dd(m.valid_to) + '</td><td>' + esc(m.status) + '</td>' +
          '<td style="white-space:nowrap;">' + (m.status === 'active' ? '<button class="act danger" data-rev="' + m.id + '">Отозвать</button>' : '') + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">МЧД нет.</span>';
      $$('#mchd [data-rev]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_mchd_set_status', { p_token: token, p_id: b.dataset.rev, p_status: 'revoked' }).then(function () { loadMchd(); loadKpi(); }); }); });
    });
  }
  function mchdForm() {
    ui.formDialog({ title: 'Машиночитаемая доверенность', okText: 'Создать', fields: [
      { name: 'number', label: 'Номер', type: 'text' }, { name: 'to', label: 'Доверенное лицо (логин)', type: 'text', required: true },
      { name: 'authority', label: 'Полномочия', type: 'text' }, { name: 'from', label: 'С', type: 'date' }, { name: 'to_date', label: 'По', type: 'date' }
    ], values: { from: new Date().toISOString().slice(0, 10) } }).then(function (v) {
      if (!v) return;
      rpc('app_mchd_save', { p_token: token, p_id: null, p_number: v.number || null, p_to: v.to, p_authority: v.authority || null, p_from: v.from || null, p_to_date: v.to_date || null, p_status: 'active', p_note: null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadMchd(); loadKpi(); });
    });
  }

  $('#add').addEventListener('click', docForm);
  $('#addTpl').addEventListener('click', function () { tplForm(null); });
  $('#addMchd').addEventListener('click', mchdForm);
  $('#meBtn').addEventListener('click', loadMy);
  $('#q').addEventListener('input', loadDocs);
  $('#status').addEventListener('change', loadDocs);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadKpi(); loadDocs();
  });
})();
