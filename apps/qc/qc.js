/* ============================================================
   3DMP Service · apps/qc — ОТК и качество
   Данные: app_qc_*, app_defect_* (0012_quality.sql). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, checks = [], defects = [], naryads = [], cur = null;

  var ST = { draft: 'Черновик', passed: 'Годен', failed: 'Брак' };
  var SEV = { minor: 'Незнач.', major: 'Значит.', critical: 'Критич.' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return (Number(v) || 0); }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleDateString('ru-RU'); }
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
      $('#cNaryad').innerHTML = '<option value="">— нет —</option>' + naryads.map(function (n) {
        return '<option value="' + n.id + '">' + esc(n.number) + ' · ' + esc(n.title) + '</option>';
      }).join('');
      render(); renderDefects();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function render() {
    if (!checks.length) { $('#list').innerHTML = '<span class="note">Чек-листов нет.</span>'; return; }
    $('#list').innerHTML = checks.map(function (c) {
      return '<div class="qcard" data-id="' + c.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;"><span class="b ' + c.status + '">' + (ST[c.status] || c.status) + '</span>' +
        '<span class="note" style="margin-left:auto;">' + esc(c.number) + '</span></div>' +
        '<h3 style="font-size:.94rem;margin:8px 0 4px;">' + esc(c.product || 'Контроль') + '</h3>' +
        '<div style="font-size:.76rem;color:var(--muted);">' + (c.inspector ? '👤 ' + esc(c.inspector) + ' · ' : '') +
        c.lines_count + ' поз. · дефектов: ' + c.defects_count + ' · ' + fmt(c.created_at) + '</div></div>';
    }).join('');
    $$('#list .qcard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }
  function renderDefects() {
    if (!defects.length) { $('#defects').innerHTML = '<span class="note">Дефектов нет.</span>'; return; }
    $('#defects').innerHTML = defects.map(function (d) {
      return '<div class="kvr"><span class="b ' + d.severity + '">' + (SEV[d.severity] || d.severity) + '</span>' +
        '<b>' + esc(d.title) + '</b> <span class="note">×' + num(d.qty) + '</span>' +
        '<span class="b ' + (d.status === 'resolved' ? 'resolved' : 'failed') + '" style="margin-left:8px;">' + (d.status === 'resolved' ? 'закрыт' : 'открыт') + '</span>' +
        (d.status !== 'resolved' ? '<button class="act" data-res="' + d.id + '" style="margin-left:auto;background:none;border:1px solid var(--border);border-radius:8px;padding:5px 9px;cursor:pointer;font-size:.74rem;">Закрыть</button>' : '') +
        '</div>';
    }).join('');
    $$('#defects [data-res]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_defect_resolve', { p_token: token, p_id: b.dataset.res, p_note: '' })
          .then(function () { window.Auth.log('Дефект закрыт', b.dataset.res); ui.toast('Дефект закрыт'); load(); });
      });
    });
  }

  function openItem(id) {
    cur = checks.filter(function (c) { return c.id === id; })[0]; if (!cur) return;
    $('#check').innerHTML =
      '<div style="display:flex;gap:8px;align-items:center;"><span class="b ' + cur.status + '">' + (ST[cur.status] || cur.status) + '</span>' +
      '<b style="margin-left:auto;">' + esc(cur.number) + '</b></div>' +
      '<h1 style="font-size:1.1rem;margin:10px 0;">' + esc(cur.product || 'Контроль') + '</h1>' +
      kv('Контролёр', cur.inspector) + kv('Наряд', cur.naryad_number) + kv('Создан', fmt(cur.created_at));
    loadLines();
    clearMsg('#iMsg'); $('#dTitle').value = ''; $('#dQty').value = ''; $('#lName').value = ''; $('#lNorm').value = ''; $('#lValue').value = '';
    screens.go('s-item');
  }
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function loadLines() {
    rpc('app_qc_lines_list', { p_token: token, p_check_id: cur.id }).then(function (ls) {
      ls = ls || [];
      $('#lines').innerHTML = ls.length ? ls.map(function (l) {
        return '<div class="line"><div>' + esc(l.name) + '</div><div>' + esc(l.norm || '—') + '</div><div>' + esc(l.value || '—') + '</div>' +
          '<div><span class="b ' + (l.result === 'ok' ? 'passed' : 'failed') + '">' + (l.result === 'ok' ? 'годен' : 'брак') + '</span></div></div>';
      }).join('') : '<span class="note">Позиций нет.</span>';
    });
  }

  $('#toNew').addEventListener('click', function () { clearMsg('#nMsg'); screens.go('s-new'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  $('#createBtn').addEventListener('click', function () {
    rpc('app_qc_create', { p_token: token, p_naryad_id: $('#cNaryad').value || null, p_order_id: null, p_product: $('#cProduct').value.trim(), p_inspector: $('#cInspector').value.trim() })
      .then(function (d) { var row = d && d[0]; if (!row) { msg('#nMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('Чек-лист ОТК', row.number); $('#cProduct').value = '';
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
      .then(function (d) { var r = d && d[0]; msg('#iMsg', (r && r.message) || 'Готово', 'ok'); window.Auth.log('ОТК', cur.number + ' → ' + st); load().then(function () { openItem(cur.id); }); });
  }
  $('#addDefect').addEventListener('click', function () {
    if (!cur) return;
    var t = $('#dTitle').value.trim(); if (!t) { msg('#iMsg', 'Опишите дефект.', 'err'); return; }
    var q = parseFloat($('#dQty').value.replace(',', '.'));
    rpc('app_defect_add', { p_token: token, p_check_id: cur.id, p_title: t, p_qty: isNaN(q) ? 1 : q, p_severity: $('#dSev').value, p_note: '' })
      .then(function () { window.Auth.log('Дефект', t); ui.toast('Дефект зарегистрирован'); load().then(function () { openItem(cur.id); }); });
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
