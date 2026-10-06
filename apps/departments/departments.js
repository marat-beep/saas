/* ============================================================
   3DMP Service · apps/departments — P13 иерархия. Данные: 0069.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], cur = null;

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_departments_list', { p_token: token, p_q: null }),
      rpc('app_department_kpi', { p_token: token })
    ]).then(function (r) {
      list = r[0] || [];
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Подразделений', k.total || 0) + cell('Корневых', k.root || 0) + cell('С руководителем', k.with_head || 0) + cell('Глубина', k.max_depth || 0);
      renderParentOptions(); renderTree();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderParentOptions() {
    var sel = $('#fParent');
    var opts = '<option value="">— корневое —</option>' + list.filter(function (d) { return !cur || d.id !== cur.id; })
      .map(function (d) { return '<option value="' + d.id + '">' + esc(d.name) + '</option>'; }).join('');
    sel.innerHTML = opts;
  }

  function nodeHtml(d, children) {
    var kids = (children[d.id] || []);
    return '<li><div class="node">' +
      '<span>' + (kids.length ? '📁' : '📄') + '</span><b>' + esc(d.name) + '</b>' +
      (d.code ? '<span class="badge">' + esc(d.code) + '</span>' : '') +
      (d.head ? '<span class="note">рук.: ' + esc(d.head) + '</span>' : '<span class="note">без руководителя</span>') +
      '<span class="note">сотрудников: ' + (d.employees || 0) + '</span>' +
      '<span style="margin-left:auto;display:flex;gap:6px;">' +
      '<button class="btn secondary" data-edit="' + d.id + '" style="width:auto;padding:4px 10px;font-size:.72rem;">Править</button>' +
      '<button class="btn secondary" data-del="' + d.id + '" style="width:auto;padding:4px 10px;font-size:.72rem;">Удалить</button></span>' +
      '</div>' + (kids.length ? '<ul>' + kids.map(function (c) { return nodeHtml(c, children); }).join('') + '</ul>' : '') + '</li>';
  }

  function renderTree() {
    var children = {};
    list.forEach(function (d) { var p = d.parent_id || 'root'; (children[p] = children[p] || []).push(d); });
    var roots = children['root'] || [];
    $('#cnt').textContent = '(' + list.length + ')';
    $('#tree').innerHTML = roots.length ? '<ul class="tree">' + roots.map(function (d) { return nodeHtml(d, children); }).join('') + '</ul>' : '<span class="note">Структура пуста.</span>';
    $$('#tree [data-edit]').forEach(function (b) { b.addEventListener('click', function () { edit(b.dataset.edit); }); });
    $$('#tree [data-del]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_department_delete', { p_token: token, p_id: b.dataset.del })
        .then(function (r) { var x = r && r[0]; if (x && !x.ok) msg('#mMsg', x.message, 'err'); else { cur = null; load(); } });
    }); });
  }

  function edit(id) {
    cur = list.filter(function (d) { return d.id === id; })[0]; if (!cur) return;
    renderParentOptions();
    $('#fParent').value = cur.parent_id || ''; $('#fName').value = cur.name || ''; $('#fCode').value = cur.code || '';
    $('#fHead').value = cur.head || ''; window.scrollTo(0, 0);
  }

  $('#fClear').addEventListener('click', function () { cur = null; ['fName', 'fCode', 'fHead', 'fNote'].forEach(function (i) { $('#' + i).value = ''; }); renderParentOptions(); msg('#fMsg', ''); });
  $('#fSave').addEventListener('click', function () {
    var name = $('#fName').value.trim(); if (!name) { msg('#fMsg', 'Укажите название.', 'err'); return; }
    rpc('app_department_save', { p_token: token, p_id: cur ? cur.id : null, p_parent_id: $('#fParent').value || null,
      p_name: name, p_code: $('#fCode').value, p_head: $('#fHead').value, p_note: $('#fNote').value, p_active: true })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); cur = null; load(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
