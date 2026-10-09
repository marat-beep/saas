/* ============================================================
   3DMP Service · apps/mdm — НСИ / Мастер-данные (W18b, 0161).
   Реестр номенклатуры, версии, внешние коды, дубли/слияние, импорт.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB, EX = window.AppExport;
  var token = null, items = [];
  var TP = { material: 'Материал', product: 'Изделие', service: 'Услуга', equipment: 'Оборудование', tool: 'Инструмент', other: 'Прочее' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  /* W43: офлайн-кэш чтения (при отсутствии сети — из кэша) */
  function rpcCached(key, n, a) { return window.AppOfflineCache ? window.AppOfflineCache.cached(key, function () { return rpc(n, a); }) : rpc(n, a); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'reg') loadList();
    if (scr === 'dup') loadDups();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_mdm_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('Активных', k.active || 0) + cell('Материалы', k.materials || 0) + cell('Изделия', k.products || 0) + cell('Услуги', k.services || 0) + cell('С внешними кодами', k.linked || 0) + cell('Дублей', k.duplicates || 0);
    });
  }
  function loadList() {
    return rpcCached('mdm:items', 'app_master_items_list', { p_token: token, p_q: $('#q').value || null, p_type: $('#type').value || null, p_group: null }).then(function (r) {
      items = r || [];
      $('#list').innerHTML = items.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Код</th><th>Наименование</th><th>Тип</th><th>Ед.</th><th>Группа</th><th class="num">Коды</th><th>Статус</th><th>Действия</th></tr></thead><tbody>' +
        items.map(function (i) {
          return '<tr><td>' + esc(i.code || '—') + '</td><td><b>' + esc(i.name) + '</b></td><td>' + esc(TP[i.item_type] || i.item_type) + '</td><td>' + esc(i.unit || '') + '</td><td>' + esc(i.grp || '') + '</td>' +
            '<td class="num">' + (i.links || 0) + '</td><td>' + (i.status === 'active' ? 'активна' : 'архив') + '</td>' +
            '<td style="white-space:nowrap;"><button class="act" data-codes="' + i.id + '">Коды</button><button class="act" data-ver="' + i.id + '">Версии</button><button class="act" data-edit="' + i.id + '">Изменить</button><button class="act danger" data-del="' + i.id + '">Удалить</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Позиций нет.</span>';
      $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { form(items.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
      $$('#list [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить позицию?')) return; rpc('app_master_item_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadList(); loadKpi(); }); }); });
      $$('#list [data-codes]').forEach(function (b) { b.addEventListener('click', function () { codes(items.filter(function (x) { return x.id === b.dataset.codes; })[0]); }); });
      $$('#list [data-ver]').forEach(function (b) { b.addEventListener('click', function () { versions(b.dataset.ver); }); });
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function form(i) {
    i = i || {};
    ui.formDialog({ title: i.id ? 'Позиция НСИ' : 'Новая позиция', okText: 'Сохранить', size: 'lg', fields: [
      { name: 'code', label: 'Код', type: 'text' }, { name: 'name', label: 'Наименование', type: 'text', required: true },
      { name: 'item_type', label: 'Тип', type: 'select', options: Object.keys(TP).map(function (k) { return { value: k, label: TP[k] }; }) },
      { name: 'unit', label: 'Ед. изм.', type: 'text' }, { name: 'grp', label: 'Группа', type: 'text' },
      { name: 'attrs', label: 'Атрибуты (JSON)', type: 'textarea', rows: 3 },
      { name: 'status', label: 'Статус', type: 'select', options: [{ value: 'active', label: 'Активна' }, { value: 'archived', label: 'Архив' }] }
    ], values: { code: i.code || '', name: i.name || '', item_type: i.item_type || 'material', unit: i.unit || '', grp: i.grp || '', attrs: JSON.stringify(i.attrs || {}, null, 0), status: i.status || 'active' } }).then(function (v) {
      if (!v) return;
      var at; try { at = JSON.parse(v.attrs || '{}'); } catch (e) { msg('Некорректный JSON атрибутов', 'err'); return; }
      rpc('app_master_item_save', { p_token: token, p_id: i.id || null, p_code: v.code || null, p_name: v.name, p_item_type: v.item_type, p_unit: v.unit || null, p_group: v.grp || null, p_attrs: at, p_status: v.status, p_note: null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadList(); loadKpi(); });
    });
  }
  function codes(i) {
    rpc('app_mdm_links_list', { p_token: token, p_item_id: i.id }).then(function (r) {
      var rows = (r || []).map(function (l) { return '<tr><td>' + esc(l.system) + '</td><td>' + esc(l.ext_code) + '</td><td><button class="act danger" data-ldel="' + l.id + '">Удалить</button></td></tr>'; }).join('');
      var html = '<div class="note">Позиция: <b>' + esc(i.name) + '</b></div>' +
        '<div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Система</th><th>Код</th><th></th></tr></thead><tbody>' + (rows || '<tr><td colspan="3" class="note">Нет кодов</td></tr>') + '</tbody></table></div>' +
        '<div class="form-grid mt"><div class="field"><label>Система</label><select id="lkSys"><option value="1c">1С</option><option value="plm">PLM</option><option value="erp">ERP</option><option value="other">Прочее</option></select></div>' +
        '<div class="field"><label>Внешний код</label><input id="lkCode"></div></div>';
      ui.dialog({ title: 'Внешние коды', body: html, html: true, okText: 'Добавить', cancelText: 'Закрыть', onOpen: function (back) {
        back.querySelectorAll('[data-ldel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_mdm_link_delete', { p_token: token, p_id: b.dataset.ldel }).then(function () { back.querySelector('[data-ok]').click(); }); }); });
      } }).then(function (ok) {
        if (!ok) return;
        var s = $('#lkSys'), c = $('#lkCode');
        if (!c || !c.value.trim()) return;
        rpc('app_mdm_link_save', { p_token: token, p_id: null, p_item_id: i.id, p_system: s.value, p_ext_code: c.value.trim() }).then(function () { loadList(); loadKpi(); });
      });
    });
  }
  function versions(id) {
    rpc('app_master_item_versions_list', { p_token: token, p_item_id: id }).then(function (r) {
      var rows = (r || []).map(function (v) { return '<tr><td class="num">v' + v.version + '</td><td>' + esc(v.name || '') + '</td><td class="muted">' + esc(JSON.stringify(v.attrs || {})) + '</td><td class="muted">' + (v.created_at ? new Date(v.created_at).toLocaleString('ru-RU') : '') + '</td></tr>'; }).join('');
      ui.dialog({ title: 'Версии позиции', body: '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Версия</th><th>Наименование</th><th>Атрибуты</th><th>Когда</th></tr></thead><tbody>' + (rows || '<tr><td colspan="4" class="note">Нет версий</td></tr>') + '</tbody></table></div>', html: true, cancelText: 'Закрыть' });
    });
  }
  function loadDups() {
    return rpc('app_mdm_duplicates', { p_token: token, p_limit: 50 }).then(function (r) {
      var list = r || [];
      $('#dups').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Наименование</th><th class="num">Кол-во</th><th>Коды</th><th>ID</th><th></th></tr></thead><tbody>' +
        list.map(function (d) { return '<tr><td><b>' + esc(d.name) + '</b></td><td class="num">' + d.cnt + '</td><td class="muted">' + esc(d.codes) + '</td><td class="muted" style="font-size:.72rem;">' + esc(d.ids) + '</td>' +
          '<td><button class="act" data-merge="' + d.ids + '">Слить</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Дублей не найдено.</span>';
      $$('#dups [data-merge]').forEach(function (b) { b.addEventListener('click', function () { mergeDialog(b.dataset.merge); }); });
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function mergeDialog(idsStr) {
    var ids = idsStr.split(',').map(function (s) { return s.trim(); }).filter(Boolean);
    ui.formDialog({ title: 'Слияние дублей', okText: 'Слить', fields: [
      { name: 'keep', label: 'Оставить (ID)', type: 'select', options: ids.map(function (x) { return { value: x, label: x }; }) },
      { name: 'dup', label: 'Объединить и архивировать (ID)', type: 'select', options: ids.map(function (x) { return { value: x, label: x }; }) }
    ], values: { keep: ids[0], dup: ids[1] || ids[0] } }).then(function (v) {
      if (!v) return;
      rpc('app_mdm_merge', { p_token: token, p_keep: v.keep, p_dup: v.dup }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadDups(); loadKpi(); loadList(); });
    });
  }

  $('#add').addEventListener('click', function () { form(null); });
  $('#dupBtn').addEventListener('click', loadDups);
  $('#q').addEventListener('input', loadList);
  $('#type').addEventListener('change', loadList);
  $('#expCsv').addEventListener('click', function () { if (EX) EX.exportCsv('mdm', [{ key: 'code', label: 'Код' }, { key: 'name', label: 'Наименование' }, { key: 'item_type', label: 'Тип' }, { key: 'unit', label: 'Ед.' }, { key: 'grp', label: 'Группа' }, { key: 'status', label: 'Статус' }], items); });
  $('#expPdf').addEventListener('click', function () {
    if (!EX) return;
    var rows = items.map(function (i) { return [i.code, i.name, TP[i.item_type] || i.item_type, i.unit, i.grp, i.status]; });
    EX.exportPdf('НСИ / Мастер-данные (' + new Date().toLocaleDateString('ru-RU') + ')', EX.tableHtml(['Код', 'Наименование', 'Тип', 'Ед.', 'Группа', 'Статус'], rows));
  });
  $('#impBtn').addEventListener('click', function () {
    var it; try { it = JSON.parse($('#imp').value || '[]'); } catch (e) { msg('Некорректный JSON', 'err'); return; }
    rpc('app_mdm_import', { p_token: token, p_items: it }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadList(); loadKpi(); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadKpi(); loadList();
  });
})();
