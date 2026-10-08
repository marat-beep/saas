/* ============================================================
   3DMP Service · apps/plm — PDM/PLM (W18c, 0162).
   Изделия/состав/документы/изменения (ECN).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, products = [], items = [], cur = null;
  var STP = { draft: 'Черновик', released: 'Выпущено', obsolete: 'Снято' };
  var STE = { draft: 'Черновик', pending: 'В работе', approved: 'Утверждено', rejected: 'Отклонено' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'prod') loadProducts();
    if (scr === 'ecn') loadEcn();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_plm_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Изделий', k.products || 0) + cell('Выпущено', k.released || 0) + cell('Черновиков', k.draft || 0) + cell('Строк состава', k.bom_lines || 0) + cell('Документов', k.docs || 0) + cell('ECN в работе', k.ecn_pending || 0);
    });
  }
  function loadItems() { return rpc('app_master_items_list', { p_token: token, p_q: null, p_type: null, p_group: null }).then(function (r) { items = r || []; }).catch(function () { items = []; }); }

  /* ---------- Изделия ---------- */
  function loadProducts() {
    return rpc('app_products_list', { p_token: token, p_q: $('#q').value || null, p_state: $('#state').value || null }).then(function (r) {
      products = r || [];
      $('#list').innerHTML = products.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Код</th><th>Изделие</th><th class="num">Версия</th><th>Состояние</th><th class="num">Состав</th><th class="num">Док.</th><th></th></tr></thead><tbody>' +
        products.map(function (p) {
          return '<tr><td>' + esc(p.code || '—') + '</td><td><b>' + esc(p.name) + '</b></td><td class="num">v' + p.version + '</td><td>' + esc(STP[p.state] || p.state) + '</td><td class="num">' + p.bom + '</td><td class="num">' + p.docs + '</td>' +
            '<td style="white-space:nowrap;"><button class="act" data-open="' + p.id + '">Открыть</button><button class="act" data-edit="' + p.id + '">Изменить</button><button class="act danger" data-del="' + p.id + '">Удалить</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Изделий нет.</span>';
      $$('#list [data-open]').forEach(function (b) { b.addEventListener('click', function () { openProduct(products.filter(function (x) { return x.id === b.dataset.open; })[0]); }); });
      $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { prodForm(products.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
      $$('#list [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить изделие?')) return; rpc('app_product_delete', { p_token: token, p_id: b.dataset.del }).then(function () { $('#detailCard').style.display = 'none'; loadProducts(); loadKpi(); }); }); });
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function prodForm(p) {
    p = p || {};
    ui.formDialog({ title: p.id ? 'Изделие' : 'Новое изделие', okText: 'Сохранить', size: 'lg', fields: [
      { name: 'code', label: 'Код', type: 'text' }, { name: 'name', label: 'Наименование', type: 'text', required: true },
      { name: 'version', label: 'Версия', type: 'number' },
      { name: 'state', label: 'Состояние', type: 'select', options: Object.keys(STP).map(function (k) { return { value: k, label: STP[k] }; }) },
      { name: 'item_id', label: 'Позиция НСИ', type: 'select', options: [{ value: '', label: '—' }].concat(items.map(function (i) { return { value: i.id, label: i.name }; })) },
      { name: 'attrs', label: 'Атрибуты (JSON)', type: 'textarea', rows: 3 }
    ], values: { code: p.code || '', name: p.name || '', version: p.version || 1, state: p.state || 'draft', item_id: '', attrs: '{}' } }).then(function (v) {
      if (!v) return;
      var at; try { at = JSON.parse(v.attrs || '{}'); } catch (e) { msg('Некорректный JSON атрибутов', 'err'); return; }
      rpc('app_product_save', { p_token: token, p_id: p.id || null, p_code: v.code || null, p_name: v.name, p_version: v.version ? parseInt(v.version, 10) : 1, p_state: v.state, p_item_id: v.item_id || null, p_attrs: at, p_note: null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadProducts(); loadKpi(); });
    });
  }
  function openProduct(p) {
    if (!p) return; cur = p;
    return Promise.all([
      rpc('app_product_bom_list', { p_token: token, p_product_id: p.id, p_version: null }).catch(function () { return []; }),
      rpc('app_product_docs_list', { p_token: token, p_product_id: p.id }).catch(function () { return []; })
    ]).then(function (r) {
      var bom = r[0] || [], docs = r[1] || [];
      $('#detailCard').style.display = '';
      $('#detail').innerHTML =
        '<h3>' + esc(p.name) + ' <span class="note">' + esc(p.code || '') + ' · v' + p.version + ' · ' + esc(STP[p.state] || p.state) + '</span></h3>' +
        '<div class="toolbar"><button class="btn" id="addBom" style="width:auto;padding:7px 12px;">＋ Компонент</button><button class="btn secondary" id="addDoc" style="width:auto;padding:7px 12px;">＋ Документ</button></div>' +
        '<h4 class="mt">Состав</h4>' +
        '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Поз.</th><th>Компонент</th><th class="num">Кол-во</th><th>Ед.</th><th></th></tr></thead><tbody>' +
        (bom.length ? bom.map(function (b) { return '<tr><td>' + esc(b.pos || '') + '</td><td>' + esc(b.component) + '</td><td class="num">' + b.qty + '</td><td>' + esc(b.unit || '') + '</td><td><button class="act danger" data-bdel="' + b.id + '">Удалить</button></td></tr>'; }).join('') : '<tr><td colspan="5" class="note">Состав пуст</td></tr>') +
        '</tbody></table></div>' +
        '<h4 class="mt">Документы</h4>' +
        '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Тип</th><th>Название</th><th></th></tr></thead><tbody>' +
        (docs.length ? docs.map(function (d) { return '<tr><td>' + esc(d.doc_type) + '</td><td>' + esc(d.title || '') + '</td><td><button class="act danger" data-ddel="' + d.id + '">Отвязать</button></td></tr>'; }).join('') : '<tr><td colspan="3" class="note">Документов нет</td></tr>') +
        '</tbody></table></div>';
      $('#addBom').addEventListener('click', function () { bomForm(p.id); });
      $('#addDoc').addEventListener('click', function () { docForm(p.id); });
      $$('#detail [data-bdel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_product_bom_delete', { p_token: token, p_id: b.dataset.bdel }).then(function () { openProduct(p); loadProducts(); }); }); });
      $$('#detail [data-ddel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_product_doc_delete', { p_token: token, p_id: b.dataset.ddel }).then(function () { openProduct(p); }); }); });
    });
  }
  function bomForm(pid) {
    ui.formDialog({ title: 'Компонент состава', okText: 'Добавить', fields: [
      { name: 'item_id', label: 'Компонент (НСИ)', type: 'select', options: [{ value: '', label: '—' }].concat(items.map(function (i) { return { value: i.id, label: i.name }; })) },
      { name: 'qty', label: 'Кол-во', type: 'number' }, { name: 'unit', label: 'Ед.', type: 'text' }, { name: 'pos', label: 'Позиция', type: 'text' }
    ], values: { qty: 1 } }).then(function (v) {
      if (!v || !v.item_id) { if (v) msg('Выберите компонент', 'err'); return; }
      rpc('app_product_bom_save', { p_token: token, p_id: null, p_product_id: pid, p_version: cur.version, p_item_id: v.item_id, p_product_comp: null, p_qty: v.qty ? Number(v.qty) : 1, p_unit: v.unit || null, p_position: v.pos || null, p_note: null })
        .then(function (x) { var q = x && x[0]; msg(q ? q.message : '', q && q.ok ? 'ok' : 'err'); openProduct(cur); loadProducts(); });
    });
  }
  function docForm(pid) {
    ui.formDialog({ title: 'Документ изделия', okText: 'Привязать', fields: [
      { name: 'doc_type', label: 'Тип', type: 'select', options: [{ value: 'ЕСКД', label: 'ЕСКД' }, { value: 'ЕСТД', label: 'ЕСТД' }, { value: 'ТУ', label: 'ТУ' }, { value: 'прочее', label: 'Прочее' }] },
      { name: 'title', label: 'Название', type: 'text', required: true }, { name: 'note', label: 'Примечание', type: 'text' }
    ], values: { doc_type: 'ЕСКД' } }).then(function (v) {
      if (!v) return;
      rpc('app_product_doc_save', { p_token: token, p_id: null, p_product_id: pid, p_doc_type: v.doc_type, p_title: v.title, p_doc_id: null, p_note: v.note || null })
        .then(function (x) { var q = x && x[0]; msg(q ? q.message : '', q && q.ok ? 'ok' : 'err'); openProduct(cur); loadProducts(); });
    });
  }

  /* ---------- ECN ---------- */
  function loadEcn() {
    return rpc('app_ecn_list', { p_token: token, p_status: null }).then(function (r) {
      var list = r || [];
      $('#ecn').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Номер</th><th>Изделие</th><th>Суть</th><th>Статус</th><th>Решение</th><th>Действия</th></tr></thead><tbody>' +
        list.map(function (e) {
          var acts = '';
          if (e.status === 'draft' || e.status === 'rejected') acts += '<button class="act" data-st="pending" data-id="' + e.id + '">В работу</button>';
          if (e.status === 'pending') acts += '<button class="act" data-st="approved" data-id="' + e.id + '">Утвердить</button><button class="act danger" data-st="rejected" data-id="' + e.id + '">Отклонить</button>';
          if (e.status === 'draft' || e.status === 'rejected') acts += '<button class="act danger" data-del="' + e.id + '">Удалить</button>';
          return '<tr><td>' + esc(e.number || '—') + '</td><td>' + esc(e.product || '—') + '</td><td>' + esc(e.title) + '</td><td>' + esc(STE[e.status] || e.status) + '</td><td class="muted">' + esc(e.decided_login || '') + '</td><td style="white-space:nowrap;">' + acts + '</td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Изменений нет.</span>';
      $$('#ecn [data-st]').forEach(function (b) { b.addEventListener('click', function () { var st = b.dataset.st; var cm = (st === 'approved' || st === 'rejected') ? prompt('Комментарий решения:', '') : null; rpc('app_ecn_set_status', { p_token: token, p_id: b.dataset.id, p_status: st, p_comment: cm }).then(function (x) { var q = x && x[0]; msg(q ? q.message : '', q && q.ok ? 'ok' : 'err'); loadEcn(); loadKpi(); }); }); });
      $$('#ecn [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить изменение?')) return; rpc('app_ecn_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadEcn(); }); }); });
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function ecnForm() {
    ui.formDialog({ title: 'Новое изменение (ECN)', okText: 'Создать', size: 'lg', fields: [
      { name: 'product_id', label: 'Изделие', type: 'select', options: [{ value: '', label: '—' }].concat(products.map(function (p) { return { value: p.id, label: p.name }; })) },
      { name: 'number', label: 'Номер', type: 'text' }, { name: 'title', label: 'Суть изменения', type: 'text', required: true },
      { name: 'reason', label: 'Причина', type: 'text' },
      { name: 'changes', label: 'Изменения (JSON)', type: 'textarea', rows: 3, hint: '[{"field":"material","old":"Сталь 45","new":"40Х"}]' }
    ], values: { changes: '[]' } }).then(function (v) {
      if (!v) return;
      var ch; try { ch = JSON.parse(v.changes || '[]'); } catch (e) { msg('Некорректный JSON', 'err'); return; }
      rpc('app_ecn_save', { p_token: token, p_id: null, p_product_id: v.product_id || null, p_number: v.number || null, p_title: v.title, p_reason: v.reason || null, p_changes: ch })
        .then(function (x) { var q = x && x[0]; msg(q ? q.message : '', q && q.ok ? 'ok' : 'err'); loadEcn(); loadKpi(); });
    });
  }

  $('#add').addEventListener('click', function () { prodForm(null); });
  $('#newEcn').addEventListener('click', ecnForm);
  $('#q').addEventListener('input', loadProducts);
  $('#state').addEventListener('change', loadProducts);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadItems(); loadKpi(); loadProducts();
  });
})();
