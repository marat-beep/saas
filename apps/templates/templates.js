/* ============================================================
   3DMP Service · apps/templates — шаблоны документов (B33)
   Данные: 0062. Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, list = [], orders = [], cur = null, q = '';

  var T = { kp: 'КП', contract: 'Договор', act: 'Акт', techcard: 'Техкарта', other: 'Другое' };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_doc_templates_list', { p_token: token, p_doc_type: null, p_q: null }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; orders = r[1] || [];
      $('#fOrder').innerHTML = '<option value="">— заявка для создания —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      $('#kpis').innerHTML = cell('Шаблонов', list.length) +
        '<div class="kpi"><small>Типы</small><b>' + ['kp', 'contract', 'act', 'techcard'].filter(function (k) { return list.some(function (t) { return t.doc_type === k; }); }).length + '</b></div>';
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (t) { return !s || t.name.toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (t) {
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + (T[t.doc_type] || t.doc_type) + '</span><b>' + esc(t.name) + '</b>' +
        '<span class="note" style="margin-left:auto;">' + (t.body ? esc(t.body.slice(0, 60)) + '…' : '') + '</span></div>' +
        '<div class="toolbar mt">' +
        '<button class="btn secondary" data-edit="' + t.id + '" style="width:auto;padding:8px 14px;">Редактировать</button>' +
        '<button class="btn" data-make="' + t.id + '" style="width:auto;padding:8px 14px;">Создать документ из шаблона</button>' +
        '</div></div>';
    }).join('') : '<span class="note">Шаблонов нет.</span>';
    $$('#list [data-edit]').forEach(function (b) {
      b.addEventListener('click', function () {
        cur = list.filter(function (t) { return t.id === b.dataset.edit; })[0];
        if (!cur) return;
        $('#fType').value = cur.doc_type; $('#fName').value = cur.name; $('#fBody').value = cur.body || '';
        window.scrollTo(0, 0);
      });
    });
    $$('#list [data-make]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_doc_from_template', { p_token: token, p_template_id: b.dataset.make, p_order_id: $('#fOrder').value || null })
          .then(function (d) { var r = d && d[0]; if (!r) { msg('#mMsg', 'Ошибка', 'err'); return; } msg('#mMsg', r.message + ': ' + r.number, 'ok'); window.Auth.log('Документ из шаблона', r.number); })
          .catch(function (e) { msg('#mMsg', 'Ошибка: ' + e.message, 'err'); });
      });
    });
  }
  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fSave').addEventListener('click', function () {
    var name = $('#fName').value.trim(); if (!name) { msg('#fMsg', 'Укажите название.', 'err'); return; }
    rpc('app_doc_template_save', { p_token: token, p_id: cur ? cur.id : null, p_doc_type: $('#fType').value, p_name: name, p_body: $('#fBody').value, p_active: true })
      .then(function (d) { var r = d && d[0]; if (!r) { msg('#fMsg', 'Ошибка', 'err'); return; } msg('#fMsg', r.message, 'ok'); cur = null; load(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#fClear').addEventListener('click', function () { cur = null; $('#fName').value = ''; $('#fBody').value = ''; msg('#fMsg', '', 'info'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
