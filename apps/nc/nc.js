/* ============================================================
   3DMP Service · apps/nc — реестр УП (управляющие программы)
   Данные: 0059. Файлы — AppFiles (entity 'nc'). Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, list = [], orders = [], eq = [], q = '';

  var ST = { draft: 'Черновик', approved: 'Апробирована', archive: 'Архив' };

  /* ---------- Роли (data-cap) ---------- */
  var ALL = { edit: 1, reports: 1 };
  var CAPS = { admin: ALL, owner: ALL, director: ALL, manager: ALL, chief: ALL, master: { edit: 1 }, technologist: ALL, operator: { edit: 1 }, default: { reports: 1 } };
  function can(c) { return !!(me && (CAPS[me.role] || CAPS['default'])[c]); }
  function applyCaps() { $$('[data-cap]').forEach(function (el) { var n = (el.dataset.cap || '').split('|'); if (!n.some(can)) el.style.display = 'none'; }); }

  /* ---------- Отчёт (УП) ---------- */
  function reportPdf() {
    if (!window.AppExport) { ui.toast('Экспорт недоступен'); return; }
    var totalMin = list.reduce(function (s, n) { return s + num(n.program_time_min); }, 0);
    var cols = [
      { key: 'detail', label: 'Деталь' }, { key: 'program_no', label: '№ УП' }, { key: 'version', label: 'Версия', num: true },
      { key: 'status', label: 'Статус', value: function (n) { return ST[n.status] || n.status; } },
      { key: 'machine', label: 'Станок' }, { key: 'order_number', label: 'Заявка' },
      { key: 'program_time_min', label: 'Время, мин', num: true }
    ];
    AppExport.exportPdf('УП — отчёт', AppExport.reportDocument({
      brand: '3DMP Service', title: 'Реестр управляющих программ (УП)', subtitle: new Date().toLocaleDateString('ru-RU'),
      kpis: [{ label: 'Программ', value: list.length }, { label: 'Суммарное время, мин', value: totalMin }],
      sections: [{ title: 'Программы', columns: cols, rows: list }],
      sign: ['Инженер-технолог', 'Начальник цеха'], footer: '3DMP Service · ЧПУ'
    }));
  }
  $('#repBtn').addEventListener('click', reportPdf);
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_nc_list', { p_token: token, p_q: null }),
      rpc('app_nc_kpi', { p_token: token }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_equipment_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; var k = (r[1] && r[1][0]) || {}; orders = r[2] || []; eq = r[3] || [];
      $('#fOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + '</option>'; }).join('');
      $('#fEq').innerHTML = '<option value="">— нет —</option>' + eq.map(function (e) { return '<option value="' + e.id + '">' + esc(e.name) + '</option>'; }).join('');
      $('#kpis').innerHTML = cell('Программ', num(k.programs)) + cell('Апробировано', num(k.approved), '#15803d') +
        cell('Черновиков', num(k.draft), num(k.draft) ? '#92400e' : '') + cell('Суммарное время, мин', num(k.total_min));
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (n) { if (!s) return true; return [n.detail, n.program_no, n.order_number].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (n) {
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<b>' + esc(n.detail) + '</b>' + (n.program_no ? '<span class="badge">' + esc(n.program_no) + '</span>' : '') +
        '<span class="note">v' + n.version + ' · ' + num(n.program_time_min) + ' мин</span>' +
        '<span class="note" style="margin-left:auto;">' + (n.order_number ? '📥 ' + esc(n.order_number) + ' · ' : '') + (n.equipment ? '🏭 ' + esc(n.equipment) : '') + '</span></div>' +
        '<div class="toolbar mt">' +
        '<select data-st="' + n.id + '" style="padding:7px;border:1px solid var(--border);border-radius:8px;font-size:.78rem;">' +
        Object.keys(ST).map(function (k) { return '<option value="' + k + '"' + (n.status === k ? ' selected' : '') + '>' + ST[k] + '</option>'; }).join('') + '</select>' +
        '<button class="btn secondary" data-files="' + n.id + '" data-name="' + esc(n.detail) + '" style="width:auto;padding:8px 14px;">Файлы УП</button>' +
        '</div></div>';
    }).join('') : '<span class="note">УП нет.</span>';
    $$('#list [data-st]').forEach(function (sel) {
      sel.addEventListener('change', function () {
        rpc('app_nc_set_status', { p_token: token, p_id: sel.dataset.st, p_status: sel.value })
          .then(function (d) { var r = d && d[0]; if (r && !r.ok) { ui.toast(r.message); return; } window.Auth.log('УП статус', sel.value); load(); });
      });
    });
    $$('#list [data-files]').forEach(function (b) {
      b.addEventListener('click', function () {
        $('#filesCard').style.display = ''; $('#fnTitle').textContent = b.dataset.name;
        if (window.AppFiles) window.AppFiles.mount({ token: token, entityType: 'nc', entityId: b.dataset.files, el: '#filesBox' });
        window.scrollTo(0, document.body.scrollHeight);
      });
    });
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fAdd').addEventListener('click', function () {
    var detail = $('#fDetail').value.trim(); if (!detail) { msg('#fMsg', 'Укажите деталь.', 'err'); return; }
    var tm = parseFloat(($('#fTime').value || '').replace(',', '.'));
    rpc('app_nc_save', { p_token: token, p_id: null, p_order_id: $('#fOrder').value || null, p_equipment_id: $('#fEq').value || null,
      p_detail: detail, p_program_no: $('#fNo').value.trim(), p_time: isNaN(tm) ? null : tm, p_note: null })
      .then(function (d) { var r = d && d[0]; msg('#fMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('УП', detail); ['#fDetail', '#fNo', '#fTime'].forEach(function (s) { $(s).value = ''; }); load(); } })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token; applyCaps();
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
