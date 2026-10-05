/* ============================================================
   3DMP Service · apps/bom — спецификации изделия (BOM)
   Данные: app_bom_*, app_material_list, app_order_list. Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, boms = [], mats = [], orders = [], lines = [], cur = null;

  function esc(v) { return ui.esc(v); }
  function num(v) { return (Number(v) || 0); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return Promise.all([
      rpc('app_bom_list', { p_token: token }),
      rpc('app_material_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      boms = r[0] || []; mats = r[1] || []; orders = r[2] || [];
      $('#bOrder').innerHTML = '<option value="">— без заявки —</option>' + orders.map(function (o) {
        return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>';
      }).join('');
      renderList();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderList() {
    if (!boms.length) { $('#list').innerHTML = '<span class="note">Спецификаций нет.</span>'; return; }
    $('#list').innerHTML = boms.map(function (b) {
      return '<div class="bcard" data-id="' + b.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;"><b style="font-size:.94rem;">' + esc(b.product) + '</b>' +
        '<span class="note" style="margin-left:auto;">' + b.lines_count + ' поз.</span></div>' +
        '<div style="font-size:.78rem;color:var(--muted);margin-top:5px;">вер. ' + esc(b.version || '1') +
        (b.order_number ? ' · 📥 ' + esc(b.order_number) : '') + '</div></div>';
    }).join('');
    $$('#list .bcard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function openItem(id) {
    cur = boms.filter(function (b) { return b.id === id; })[0]; if (!cur) return;
    $('#bomView').innerHTML =
      '<b style="font-size:1rem;">' + esc(cur.product) + '</b>' +
      kv('Версия', cur.version || '1') + kv('Заявка', cur.order_number);
    rpc('app_bom_lines_list', { p_token: token, p_bom_id: id }).then(function (ls) {
      ls = ls || [];
      $('#bomLines').innerHTML = ls.length ? ls.map(function (l) {
        return '<div class="kvr"><span class="k">' + (l.item_type === 'material' ? '🧱' : '⚙️') + '</span><b>' + esc(l.name) + '</b>' +
          '<span class="note" style="margin-left:auto;">' + num(l.qty) + ' ' + esc(l.unit || '') + (l.norm_hours ? ' · ' + num(l.norm_hours) + ' н/ч' : '') + '</span></div>';
      }).join('') : '<span class="note">Позиций нет.</span>';
      screens.go('s-item');
    });
  }
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }

  function renderLines() {
    $('#lineCount').textContent = lines.length + ' поз.';
    $('#lines').innerHTML = lines.map(function (l, i) {
      var mid = (l.item_type === 'material')
        ? '<select data-i="' + i + '" data-k="material_id">' + '<option value="">— материал —</option>' +
          mats.map(function (m) { return '<option value="' + m.id + '"' + (l.material_id === m.id ? ' selected' : '') + '>' + esc(m.name) + '</option>'; }).join('') + '</select>'
        : '<input type="text" data-i="' + i + '" data-k="name" value="' + esc(l.name || '') + '" placeholder="Операция">';
      return '<div class="line">' +
        '<select data-i="' + i + '" data-k="item_type"><option value="material"' + (l.item_type === 'material' ? ' selected' : '') + '>Материал</option><option value="operation"' + (l.item_type === 'operation' ? ' selected' : '') + '>Операция</option></select>' +
        mid +
        '<input type="text" data-i="' + i + '" data-k="qty" inputmode="decimal" value="' + num(l.qty) + '">' +
        '<input type="text" data-i="' + i + '" data-k="unit" value="' + esc(l.unit || '') + '" placeholder="ед.">' +
        '<input type="text" data-i="' + i + '" data-k="norm_hours" inputmode="decimal" value="' + num(l.norm_hours) + '">' +
        '<button class="rm" data-rm="' + i + '">✕</button></div>';
    }).join('');
    $$('#lines [data-k]').forEach(function (el) {
      el.addEventListener('change', function () {
        var i = parseInt(el.dataset.i, 10), k = el.dataset.k;
        if (k === 'item_type') { lines[i].item_type = el.value; if (el.value === 'material') { lines[i].name = ''; } renderLines(); return; }
        if (k === 'material_id') { lines[i].material_id = el.value || null; var m = mats.filter(function (x) { return x.id === el.value; })[0]; if (m) { lines[i].name = m.name; lines[i].unit = m.unit || lines[i].unit; } return; }
        if (k === 'qty' || k === 'norm_hours') lines[i][k] = parseFloat(String(el.value).replace(',', '.')) || 0;
        else lines[i][k] = el.value;
      });
    });
    $$('#lines .rm').forEach(function (b) { b.addEventListener('click', function () { lines.splice(parseInt(b.dataset.rm, 10), 1); renderLines(); }); });
  }

  $('#toForm').addEventListener('click', function () {
    lines = [{ item_type: 'material', material_id: null, name: '', qty: 1, unit: '', norm_hours: 0 }];
    $('#bProduct').value = ''; $('#bVersion').value = '1'; $('#bOrder').value = '';
    renderLines(); clearMsg('#fMsg'); screens.go('s-form');
  });
  $('#addLine').addEventListener('click', function () { lines.push({ item_type: 'material', material_id: null, name: '', qty: 1, unit: '', norm_hours: 0 }); renderLines(); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  $('#saveBom').addEventListener('click', function () {
    var product = $('#bProduct').value.trim();
    if (!product) { msg('#fMsg', 'Укажите изделие.', 'err'); return; }
    var payload = lines.filter(function (l) { return (l.item_type === 'material' ? l.material_id : (l.name || '').trim()) || (l.name || '').trim(); })
      .map(function (l) { return { item_type: l.item_type, material_id: l.material_id || null, name: l.name || '', qty: num(l.qty), unit: l.unit || '', norm_hours: num(l.norm_hours) }; });
    rpc('app_bom_save', { p_token: token, p_id: null, p_order_id: $('#bOrder').value || null, p_product: product, p_version: $('#bVersion').value.trim(), p_lines: payload })
      .then(function (d) { var r = d && d[0]; if (!r) { msg('#fMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('Спецификация', product); ui.toast('Спецификация сохранена');
        load().then(function () { screens.go('s-list'); }); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
