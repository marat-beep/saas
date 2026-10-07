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
      renderKpi(); render(); renderDefects(); loadSpcParams();
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
      if (window.AppFiles) window.AppFiles.mount({ token: token, entityType: 'qc', entityId: cur.id, el: '#filesBox' });
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

  /* ---------- SPC: контрольная карта и индексы ---------- */
  var spcParam = '';
  function kpiCell(l, v, col) { return '<div class="kpi"><small>' + l + '</small><b' + (col ? ' style="color:' + col + '"' : '') + '>' + v + '</b></div>'; }
  function loadSpcParams() {
    return rpc('app_qc_params', { p_token: token }).then(function (ps) {
      ps = ps || [];
      var sel = $('#spcParam');
      sel.innerHTML = '<option value="">— параметр —</option>' + ps.map(function (p) { return '<option value="' + esc(p.param) + '">' + esc(p.param) + ' (' + p.n + ')</option>'; }).join('');
      if (!spcParam && ps.length) spcParam = ps[0].param;
      if (spcParam) sel.value = spcParam;
      if (spcParam && ps.length) buildSpc();
    }).catch(function () {});
  }
  function numOrNull(v) { var n = parseFloat(String(v || '').replace(',', '.')); return isNaN(n) ? null : n; }
  function spcSvg(points, st) {
    var W = 760, H = 280, pl = 56, pr = 14, pt = 14, pb = 30;
    var vals = points.map(function (p) { return Number(p.value); });
    var ucl = st.ucl != null ? Number(st.ucl) : null, lcl = st.lcl != null ? Number(st.lcl) : null;
    var cl = st.cl != null ? Number(st.cl) : null;
    var all = vals.slice(); if (ucl != null) all.push(ucl); if (lcl != null) all.push(lcl); if (cl != null) all.push(cl);
    var mn = Math.min.apply(null, all), mx = Math.max.apply(null, all);
    var pad = (mx - mn) * 0.15 || 0.01; mn -= pad; mx += pad;
    var n = points.length;
    function X(i) { return pl + (n <= 1 ? 0 : i * (W - pl - pr) / (n - 1)); }
    function Y(v) { return pt + (mx - v) * (H - pt - pb) / (mx - mn || 1); }
    function line(v, color, dash) { if (v == null) return ''; var y = Y(v).toFixed(1); return '<line x1="' + pl + '" y1="' + y + '" x2="' + (W - pr) + '" y2="' + y + '" stroke="' + color + '" stroke-width="1"' + (dash ? ' stroke-dasharray="5 4"' : '') + '/>'; }
    var poly = points.map(function (p, i) { return X(i).toFixed(1) + ',' + Y(Number(p.value)).toFixed(1); }).join(' ');
    var dots = points.map(function (p, i) {
      var col = p.out_ctl ? '#b91c1c' : '#2563eb';
      return '<circle cx="' + X(i).toFixed(1) + '" cy="' + Y(Number(p.value)).toFixed(1) + '" r="' + (p.out_ctl ? 4 : 3) + '" fill="' + col + '"/>';
    }).join('');
    return '<div style="overflow:auto;"><svg viewBox="0 0 ' + W + ' ' + H + '" width="100%" height="' + H + '" style="max-width:100%;">' +
      '<rect x="0" y="0" width="' + W + '" height="' + H + '" fill="#fff"/>' +
      line(ucl, '#b91c1c', true) + line(cl, '#10b981', false) + line(lcl, '#b91c1c', true) +
      '<polyline points="' + poly + '" fill="none" stroke="#94a3b8" stroke-width="1.4"/>' + dots +
      '<text x="' + (pl - 6) + '" y="' + (Y(mx) + 4) + '" text-anchor="end" font-size="10" fill="#64748b">' + mx.toFixed(3) + '</text>' +
      '<text x="' + (pl - 6) + '" y="' + (Y(mn) + 4) + '" text-anchor="end" font-size="10" fill="#64748b">' + mn.toFixed(3) + '</text>' +
      '</svg></div>' +
      '<div class="note" style="margin-top:4px;">— CL ' + (cl != null ? cl.toFixed(4) : '—') + ' · UCL ' + (ucl != null ? ucl.toFixed(4) : '—') + ' · LCL ' + (lcl != null ? lcl.toFixed(4) : '—') + ' (красные точки — вне границ)</div>';
  }
  function buildSpc() {
    var param = $('#spcParam').value || spcParam; if (!param) { msg('#spcMsg', 'Выберите параметр.', 'err'); return; }
    spcParam = param;
    var st = null;
    rpc('app_qc_spc_stats', { p_token: token, p_param: param, p_lsl: numOrNull($('#spcLsl').value), p_usl: numOrNull($('#spcUsl').value), p_limit: 100 })
      .then(function (rows) {
        st = rows && rows[0]; if (!st) { $('#spcStats').innerHTML = ''; return Promise.resolve([]); }
        $('#spcStats').innerHTML =
          kpiCell('Измерений', st.n) +
          kpiCell('Cp', st.cp != null ? Number(st.cp).toFixed(3) : '—', st.cp != null && st.cp < 1 ? '#b91c1c' : '') +
          kpiCell('Cpk', st.cpk != null ? Number(st.cpk).toFixed(3) : '—', st.cpk != null && st.cpk < 1 ? '#b91c1c' : '') +
          kpiCell('Pp', st.pp != null ? Number(st.pp).toFixed(3) : '—') +
          kpiCell('Ppk', st.ppk != null ? Number(st.ppk).toFixed(3) : '—') +
          kpiCell('Вне границ', st.out_count, st.out_count ? '#b91c1c' : '');
        return rpc('app_qc_spc_points', { p_token: token, p_param: param, p_limit: 100 });
      })
      .then(function (pts) {
        pts = pts || [];
        if (pts.length < 2) { $('#spcChart').innerHTML = '<span class="note">Недостаточно данных (нужно ≥ 2 измерений).</span>'; $('#spcPoints').innerHTML = ''; return; }
        $('#spcChart').innerHTML = spcSvg(pts, st);
        $('#spcPoints').innerHTML = '<div class="tbl-wrap"><table class="tbl"><thead><tr><th class="num">#</th><th>Время</th><th class="num">Значение</th><th class="num">UCL</th><th class="num">LCL</th><th>Контроль</th></tr></thead><tbody>' +
          pts.slice(-12).reverse().map(function (p) {
            return '<tr><td class="num">' + p.seq + '</td><td class="muted">' + fmt(p.ts) + '</td><td class="num">' + Number(p.value).toFixed(4) + '</td>' +
              '<td class="num">' + (p.ucl != null ? Number(p.ucl).toFixed(4) : '—') + '</td><td class="num">' + (p.lcl != null ? Number(p.lcl).toFixed(4) : '—') + '</td>' +
              '<td><span class="badge ' + (p.out_ctl ? 'cancelled' : 'done') + '">' + (p.out_ctl ? 'вне границ' : 'в норме') + '</span></td></tr>';
          }).join('') + '</tbody></table></div>';
      })
      .catch(function (e) { msg('#spcMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  $('#spcBuild').addEventListener('click', buildSpc);
  function offlineAddMeasure(p, v) {
    if (!window.AppOffline) { msg('#spcMsg', 'Нет сети, очередь недоступна.', 'err'); return; }
    window.AppOffline.add({ rpc: 'app_qc_measure_add', args: { p_token: token, p_check_id: null, p_position_id: null, p_param: p, p_value: v }, label: 'SPC ' + p + '=' + v })
      .then(function () { msg('#spcMsg', 'Нет сети — измерение сохранено локально.', 'info'); $('#spcNewValue').value = ''; });
  }
  $('#spcAdd').addEventListener('click', function () {
    var p = $('#spcNewParam').value.trim(), v = numOrNull($('#spcNewValue').value);
    if (!p) { msg('#spcMsg', 'Укажите параметр.', 'err'); return; }
    if (v == null) { msg('#spcMsg', 'Укажите значение.', 'err'); return; }
    if (!navigator.onLine || !SB) { offlineAddMeasure(p, v); return; }
    rpc('app_qc_measure_add', { p_token: token, p_check_id: null, p_position_id: null, p_param: p, p_value: v })
      .then(function (r) { var x = r && r[0]; if (!x || !x.ok) { msg('#spcMsg', x ? x.message : 'Ошибка', 'err'); return; }
        window.Auth.log('SPC измерение', p + ' = ' + v); msg('#spcMsg', x.message, 'ok'); $('#spcNewValue').value = '';
        spcParam = p; $('#spcNewParam').value = ''; loadSpcParams(); })
      .catch(function () { offlineAddMeasure(p, v); });
  });
  window.addEventListener('online', function () { setTimeout(loadSpcParams, 1200); });

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
