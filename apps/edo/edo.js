/* ============================================================
   3DMP Service · apps/edo — ЭДО/СЭД (W19, 0163).
   Реестр документов, регистрация, поручения, связи, номенклатура дел.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, docs = [], noms = [];
  var KIND = { in: 'Входящий', out: 'Исходящий', internal: 'Внутренний', ord: 'ОРД' };
  var ST = { draft: 'Черновик', registered: 'Зарегистрирован', in_work: 'В работе', closed: 'Закрыт', cancelled: 'Отменён' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dd(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'reg') loadList();
    if (scr === 'nom') loadNom();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_edo_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('Входящих', k.incoming || 0) + cell('Исходящих', k.outgoing || 0) + cell('ОРД', k.ord || 0) + cell('В работе', k.in_work || 0) + cell('Просрочено', k.overdue || 0) + cell('Поручений откр.', k.open_resolutions || 0);
    });
  }
  function loadNomsRef() { return rpc('app_doc_nomenclature_list', { p_token: token }).then(function (r) { noms = r || []; }).catch(function () { noms = []; }); }

  function loadList() {
    return rpc('app_doc_list', { p_token: token, p_kind: $('#kind').value || null, p_status: $('#status').value || null, p_q: $('#q').value || null }).then(function (r) {
      docs = r || [];
      $('#list').innerHTML = docs.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Вид</th><th>Тип</th><th>Заголовок</th><th>№</th><th>Корреспондент</th><th>Статус</th><th>Ответств.</th><th>Срок</th><th></th></tr></thead><tbody>' +
        docs.map(function (d) {
          return '<tr><td>' + esc(KIND[d.kind] || d.kind) + '</td><td>' + esc(d.doc_type || '') + '</td><td><b>' + esc(d.title) + '</b></td><td>' + esc(d.reg_number || '—') + '</td>' +
            '<td>' + esc(d.correspondent || '') + '</td><td>' + esc(ST[d.status] || d.status) + '</td><td class="muted">' + esc(d.responsible_login || '') + '</td><td>' + dd(d.due_date) + '</td>' +
            '<td style="white-space:nowrap;"><button class="act" data-open="' + d.id + '">Открыть</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Документов нет.</span>';
      $$('#list [data-open]').forEach(function (b) { b.addEventListener('click', function () { openDoc(docs.filter(function (x) { return x.id === b.dataset.open; })[0]); }); });
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function docForm() {
    ui.formDialog({ title: 'Новый документ', okText: 'Создать', size: 'lg', fields: [
      { name: 'kind', label: 'Вид', type: 'select', options: Object.keys(KIND).map(function (k) { return { value: k, label: KIND[k] }; }) },
      { name: 'doc_type', label: 'Тип', type: 'text', placeholder: 'письмо / приказ / договор' },
      { name: 'title', label: 'Заголовок', type: 'text', required: true },
      { name: 'correspondent', label: 'Корреспондент', type: 'text' },
      { name: 'responsible', label: 'Ответственный (логин)', type: 'text' },
      { name: 'due_date', label: 'Срок', type: 'date' },
      { name: 'summary', label: 'Краткое содержание', type: 'textarea', rows: 2 }
    ], values: { kind: 'in' } }).then(function (v) {
      if (!v) return;
      rpc('app_doc_save', { p_token: token, p_id: null, p_kind: v.kind, p_doc_type: v.doc_type || null, p_title: v.title, p_correspondent: v.correspondent || null, p_summary: v.summary || null, p_responsible: v.responsible || null, p_due_date: v.due_date || null, p_reg_date: null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadList(); loadKpi(); });
    });
  }
  function openDoc(d) {
    if (!d) return;
    Promise.all([
      rpc('app_doc_links_list', { p_token: token, p_doc_id: d.id }).catch(function () { return []; }),
      rpc('app_doc_resolutions_list', { p_token: token, p_doc_id: d.id }).catch(function () { return []; })
    ]).then(function (r) {
      var links = r[0] || [], res = r[1] || [];
      var nOpts = noms.map(function (n) { return '<option value="' + n.id + '">' + esc(n.idx + ' ' + n.title) + '</option>'; }).join('');
      var html =
        '<div class="note"><b>' + esc(KIND[d.kind] || d.kind) + '</b> · ' + esc(d.title) + ' · ' + esc(d.reg_number || 'черновик') + '</div>' +
        '<div class="toolbar mt"><button class="btn" data-act="register" style="width:auto;padding:6px 10px;">Зарегистрировать</button>' +
        '<button class="btn secondary" data-act="in_work" style="width:auto;padding:6px 10px;">В работу</button>' +
        '<button class="btn secondary" data-act="closed" style="width:auto;padding:6px 10px;">Закрыть</button></div>' +
        '<div class="form-grid mt"><div class="field"><label>Связь: тип</label><input id="lType" placeholder="order / invoice / customer"></div>' +
        '<div class="field"><label>Примечание</label><input id="lNote"></div><div class="field" style="display:flex;align-items:flex-end;"><button class="btn" id="lAdd" style="width:auto;padding:6px 10px;">Добавить связь</button></div></div>' +
        '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Тип связи</th><th>Примечание</th><th></th></tr></thead><tbody>' +
        (links.length ? links.map(function (l) { return '<tr><td>' + esc(l.entity_type) + '</td><td class="muted">' + esc(l.note || '') + '</td><td><button class="act danger" data-ldel="' + l.id + '">Удалить</button></td></tr>'; }).join('') : '<tr><td colspan="3" class="note">Связей нет</td></tr>') + '</tbody></table></div>' +
        '<div class="form-grid mt"><div class="field"><label>Поручение</label><input id="rText"></div><div class="field"><label>Исполнитель (логин)</label><input id="rWho"></div>' +
        '<div class="field"><label>Срок</label><input type="date" id="rDue"></div><div class="field" style="display:flex;align-items:flex-end;"><button class="btn" id="rAdd" style="width:auto;padding:6px 10px;">Поручить</button></div></div>' +
        '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Поручение</th><th>Исполнитель</th><th>Статус</th><th></th></tr></thead><tbody>' +
        (res.length ? res.map(function (x) { return '<tr><td>' + esc(x.body) + '</td><td>' + esc(x.assignee_login || '') + '</td><td>' + esc(x.status) + '</td><td>' + (x.status === 'open' ? '<button class="act" data-rdone="' + x.id + '">Выполнено</button>' : '') + '</td></tr>'; }).join('') : '<tr><td colspan="4" class="note">Поручений нет</td></tr>') + '</tbody></table></div>' +
        '<div class="toolbar mt"><label class="note">В дело:</label><select id="arNom">' + (nOpts || '<option value="">— нет дел —</option>') + '</select><button class="act" id="arBtn">В архив</button></div>';

      ui.dialog({ title: 'Документ', body: html, html: true, cancelText: 'Закрыть', onOpen: function (back) {
        back.querySelectorAll('[data-act]').forEach(function (b) { b.addEventListener('click', function () {
          var a = b.dataset.act;
          if (a === 'register') rpc('app_doc_register', { p_token: token, p_id: d.id }).then(function () { back.querySelector('[data-ok]').click(); });
          else rpc('app_doc_set_status', { p_token: token, p_id: d.id, p_status: a, p_comment: null }).then(function () { back.querySelector('[data-ok]').click(); });
        }); });
        back.querySelectorAll('[data-ldel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_doc_link_delete', { p_token: token, p_id: b.dataset.ldel }).then(function () { back.querySelector('[data-ok]').click(); }); }); });
        back.querySelectorAll('[data-rdone]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_doc_resolution_set_status', { p_token: token, p_id: b.dataset.rdone, p_status: 'done' }).then(function () { back.querySelector('[data-ok]').click(); }); }); });
        back.querySelector('#lAdd').addEventListener('click', function () { var t = back.querySelector('#lType').value.trim(); if (!t) return; rpc('app_doc_link_save', { p_token: token, p_id: null, p_doc_id: d.id, p_entity_type: t, p_entity_id: null, p_note: back.querySelector('#lNote').value || null }).then(function () { back.querySelector('[data-ok]').click(); }); });
        back.querySelector('#rAdd').addEventListener('click', function () { var t = back.querySelector('#rText').value.trim(); if (!t) return; rpc('app_doc_resolution_add', { p_token: token, p_doc_id: d.id, p_text: t, p_assignee: back.querySelector('#rWho').value || null, p_due_date: back.querySelector('#rDue').value || null }).then(function () { back.querySelector('[data-ok]').click(); }); });
        back.querySelector('#arBtn').addEventListener('click', function () { var nid = back.querySelector('#arNom').value; if (!nid) return; rpc('app_doc_archive', { p_token: token, p_doc_id: d.id, p_nomenclature_id: nid }).then(function () { back.querySelector('[data-ok]').click(); }); });
      } }).then(function () { loadList(); loadKpi(); });
    });
  }

  /* ---------- Номенклатура ---------- */
  function loadNom() {
    return rpc('app_doc_nomenclature_list', { p_token: token }).then(function (r) {
      noms = r || [];
      $('#nom').innerHTML = noms.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Индекс</th><th>Дело</th><th class="num">Срок, лет</th><th class="num">Документов</th><th></th></tr></thead><tbody>' +
        noms.map(function (n) { return '<tr><td>' + esc(n.idx || '') + '</td><td><b>' + esc(n.title) + '</b></td><td class="num">' + (n.retention_years || 0) + '</td><td class="num">' + n.docs + '</td><td><button class="act danger" data-del="' + n.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Дел нет.</span>';
      $$('#nom [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить дело?')) return; rpc('app_doc_nomenclature_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadNom(); }); }); });
    });
  }
  function nomForm() {
    ui.formDialog({ title: 'Новое дело', okText: 'Создать', fields: [
      { name: 'idx', label: 'Индекс', type: 'text' }, { name: 'title', label: 'Название', type: 'text', required: true }, { name: 'retention', label: 'Срок хранения, лет', type: 'number' }
    ], values: { retention: 5 } }).then(function (v) {
      if (!v) return;
      rpc('app_doc_nomenclature_save', { p_token: token, p_id: null, p_idx: v.idx || null, p_title: v.title, p_retention: v.retention ? parseInt(v.retention, 10) : 5 })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadNom(); loadNomsRef(); });
    });
  }

  $('#add').addEventListener('click', docForm);
  $('#addNom').addEventListener('click', nomForm);
  $('#q').addEventListener('input', loadList);
  $('#kind').addEventListener('change', loadList);
  $('#status').addEventListener('change', loadList);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadKpi(); loadNomsRef(); loadList();
  });
})();
