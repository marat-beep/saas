/* ============================================================
   3DMP Service · apps/qc — ОТК (чек-листы, дефекты, трассируемость)
   Данные: 0012+0037. Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, checks = [], defects = [], naryads = [], cur = null, filter = '', q = '';

  var ST = { draft: 'Черновик', passed: 'Годен', failed: 'Брак' };
  var SEV = { minor: 'Незнач.', major: 'Значит.', critical: 'Критич.' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function fmt(ts) { if (!ts) return ''; var d = new Date(ts); return isNaN(d.getTime()) ? String(ts) : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return Promise.all([
      rpc('app_qc_list', { p_token: token }),
      rpc('app_defect_list', { p_token: token }),
      rpc('app_naryad_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      checks = r[0] || []; defects = r[1] || []; naryads = r[2] || [];
      $('#cNaryad').innerHTML = '<option value="">— нет —</option>' + naryads.map(function (n) { return '<option value="' + n.id + '">' + esc(n.number) + ' · ' + esc(n.title) + '</option>'; }).join('');
      renderKpi(); render(); renderDefects();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    var c = { total: checks.length, draft: 0, passed: 0, failed: 0, openD: 0 };
    checks.forEach(function (x) { if (c[x.status] != null) c[x.status]++; });
    defects.forEach(function (d) { if (d.status !== 'resolved') c.openD++; });
    $('#kpis').innerHTML = cell('Чек-листов', c.total) + cell('Годен', c.passed) + cell('Брак', c.failed, c.failed ? '#b91c1c' : '') +
      cell('Черновики', c.draft) + cell('Открытых дефектов', c.openD, c.openD ? '#b91c1c' : '');
    function cell(l, v, col) { return '<div class="kpi"><small>' + l + '</small><b' + (col ? ' style="color:' + col + '"' : '') + '>' + v + '</b></div>'; }
  }
  function filtered() {
    var s = q.toLowerCase();
    return checks.filter(function (c) {
      if (filter && c.status !== filter) return false;
      if (!s) return true;
      return [c.number, c.product, c.inspector, c.naryad_number, c.order_number].join(' ').toLowerCase().indexOf(s) >= 0;
    });
  }
  function render() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Чек-листов нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (c) {
      return '<div class="ocard" data-id="' + c.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;"><span class="badge ' + c.status + '">' + (ST[c.status] || c.status) + '</span>' +
        (c.open_defects ? '<span class="badge cancelled">открытых дефектов ' + c.open_defects + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + esc(c.number) + '</span></div>' +
        '<h3 style="font-size:.94rem;margin:8px 0 4px;">' + esc(c.product || 'Контроль') + '</h3>' +
        '<div style="font-size:.76rem;color:var(--muted);">' + (c.inspector ? '👤 ' + esc(c.inspector) + ' · ' : '') +
        (c.qty_total != null ? 'кол-во ' + num(c.qty_good) + '/' + num(c.qty_total) + ' · ' : '') +
        c.lines_count + ' поз. · дефектов: ' + c.defects_count +
        (c.naryad_number ? ' · 🏭 ' + esc(c.naryad_number) : '') + (c.order_number ? ' · 📥 ' + esc(c.order_number) : '') + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }
  function renderDefects() {
    if (!defects.length) { $('#defects').innerHTML = '<span class="note">Дефектов нет.</span>'; return; }
    $('#defects').innerHTML = defects.map(function (d) {
      return '<div class="kvr"><span class="badge ' + (d.severity === 'critical' ? 'cancelled' : d.severity === 'major' ? 'in_progress' : '') + '">' + (SEV[d.severity] || d.severity) + '</span>' +
        '<b>' + esc(d.title) + '</b> <span class="note">×' + num(d.qty) + '</span>' +
        '<span class="badge ' + (d.status === 'resolved' ? 'done' : 'cancelled') + '" style="margin-left:8px;">' + (d.status === 'resolved' ? 'закрыт' : 'открыт') + '</span>' +
        (d.status !== 'resolved' ? '<button class="chip" data-res="' + d.id + '" style="margin-left:auto;">Закрыть</button>' : '') + '</div>';
    }).join('');
    $$('#defects [data-res]').forEach(function (b) {
      b.addEventListener('click', function () { rpc('app_defect_resolve', { p_token: token, p_id: b.dataset.res, p_note: '' }).then(function () { window.Auth.log('Дефект закрыт', b.dataset.res); ui.toast('Дефект закрыт'); load(); }); });
    });
  }

  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function openItem(id) {
    rpc('app_qc_list', { p_token: token }).then(function (list) {
      checks = list || [];
      cur = checks.filter(function (c) { return c.id === id; })[0]; if (!cur) return;
      $('#check').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;"><span class="badge ' + cur.status + '">' + (ST[cur.status] || cur.status) + '</span>' +
        '<b style="margin-left:auto;">' + esc(cur.number) + '</b></div>' +
        '<h1 style="font-size:1.1rem;margin:10px 0;">' + esc(cur.product || 'Контроль') + '</h1>' +
        kv('Контролёр', cur.inspector) + kv('Наряд', cur.naryad_number) + kv('Заявка', cur.order_number) +
        kv('Количество', cur.qty_total != null ? (num(cur.qty_good) + ' / ' + num(cur.qty_total)) : '') +
        kv('Проверен', fmt(cur.checked_at)) + kv('Создан', fmt(cur.created_at));
      ['#lName', '#lNorm', '#lValue'].forEach(function (s) { $(s).value = ''; });
      $('#dTitle').value = ''; $('#dQty').value = '';
      clearMsg('#iMsg');
      loadLines(); loadTrace();
      screens.go('s-item');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function loadLines() {
    rpc('app_qc_lines_list', { p_token: token, p_check_id: cur.id }).then(function (ls) {
      ls = ls || [];
      $('#lines').innerHTML = ls.length ? ls.map(function (l) {
        return '<div class="line"><div>' + esc(l.name) + '</div><div>' + esc(l.norm || '—') + '</div><div>' + esc(l.value || '—') + '</div>' +
          '<div><span class="badge ' + (l.result === 'ok' ? 'done' : 'cancelled') + '">' + (l.result === 'ok' ? 'годен' : 'брак') + '</span></div></div>';
      }).join('') : '<span class="note">Позиций нет.</span>';
    });
  }
  function loadTrace() {
    rpc('app_qc_trace', { p_token: token, p_check_id: cur.id }).then(function (rows) {
      rows = rows || [];
      $('#trace').innerHTML = rows.length ? rows.map(function (r) {
        return '<div class="kvr"><span class="badge">' + esc(r.kind) + '</span><b>' + esc(r.title || '') + '</b>' +
          (r.detail ? '<span class="note">' + esc(r.detail) + '</span>' : '') +
          '<span class="note" style="margin-left:auto;">' + fmt(r.ts) + '</span></div>';
      }).join('') : '<span class="note">Связей не найдено (нет наряда/заявки).</span>';
    }).catch(function () { $('#trace').innerHTML = '<span class="note">Трассируемость недоступна.</span>'; });
  }

  $('#toNew').addEventListener('click', function () { clearMsg('#nMsg'); screens.go('s-new'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; render();
  });
  $('#q').addEventListener('input', function () { q = this.value; render(); });

  $('#createBtn').addEventListener('click', function () {
    var qt = parseFloat(($('#cQtyTotal').value || '').replace(',', '.'));
    var qg = parseFloat(($('#cQtyGood').value || '').replace(',', '.'));
    rpc('app_qc_create', { p_token: token, p_naryad_id: $('#cNaryad').value || null, p_order_id: null,
      p_product: $('#cProduct').value.trim(), p_inspector: $('#cInspector').value.trim(),
      p_qty_total: isNaN(qt) ? null : qt, p_qty_good: isNaN(qg) ? null : qg })
      .then(function (d) { var row = d && d[0]; if (!row) { msg('#nMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('Чек-лист ОТК', row.number); ['#cProduct', '#cQtyTotal', '#cQtyGood'].forEach(function (s) { $(s).value = ''; });
        load().then(function () { openItem(row.id); }); })
      .catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#addLine').addEventListener('click', function () {
    if (!cur) return;
    var name = $('#lName').value.trim(); if (!name) { msg('#iMsg', 'Укажите параметр.', 'err'); return; }
    rpc('app_qc_add_line', { p_token: token, p_check_id: cur.id, p_name: name, p_norm: $('#lNorm').value.trim(), p_value: $('#lValue').value.trim(), p_result: $('#lResult').value })
      .then(function () { ['#lName', '#lNorm', '#lValue'].forEach(function (s) { $(s).value = ''; }); openItem(cur.id); });
  });
  $('#passBtn').addEventListener('click', function () { qcStatus('passed'); });
  $('#failBtn').addEventListener('click', function () { qcStatus('failed'); });
  function qcStatus(st) {
    if (!cur) return;
    rpc('app_qc_set_status', { p_token: token, p_check_id: cur.id, p_status: st, p_note: st === 'failed' ? 'Зафиксирован брак' : '' })
      .then(function (d) { var r = d && d[0]; msg('#iMsg', (r && r.message) || 'Готово', 'ok'); window.Auth.log('ОТК', cur.number + ' → ' + st); if (window.AppNotify) window.AppNotify.refresh(true); load().then(function () { openItem(cur.id); }); });
  }
  $('#addDefect').addEventListener('click', function () {
    if (!cur) return;
    var t = $('#dTitle').value.trim(); if (!t) { msg('#iMsg', 'Опишите дефект.', 'err'); return; }
    var qv = parseFloat(($('#dQty').value || '').replace(',', '.'));
    rpc('app_defect_add', { p_token: token, p_check_id: cur.id, p_title: t, p_qty: isNaN(qv) ? 1 : qv, p_severity: $('#dSev').value, p_note: '' })
      .then(function () { window.Auth.log('Дефект', t); ui.toast('Дефект зарегистрирован'); load().then(function () { openItem(cur.id); }); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
