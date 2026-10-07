/* ============================================================
   3DMP Service · apps/tooling — Инструмент и стойкость
   Ресурс/наработка, заточки, износ. Данные: 0053.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, tools = [], eq = [], q = '';

  var STAT = { ok: 'в работе', worn: 'изношен', scrapped: 'списан' };

  /* ---------- Роли (data-cap) ---------- */
  var ALL = { edit: 1, reports: 1 };
  var CAPS = { admin: ALL, owner: ALL, director: ALL, manager: ALL, chief: ALL, master: { edit: 1 }, technologist: { edit: 1 }, operator: { edit: 1 }, default: { reports: 1 } };
  function can(c) { return !!(me && (CAPS[me.role] || CAPS['default'])[c]); }
  function applyCaps() { $$('[data-cap]').forEach(function (el) { var n = (el.dataset.cap || '').split('|'); if (!n.some(can)) el.style.display = 'none'; }); }

  /* ---------- Отчёт (инструмент) ---------- */
  function reportPdf() {
    if (!window.AppExport) { ui.toast('Экспорт недоступен'); return; }
    var cols = [
      { key: 'name', label: 'Инструмент' }, { key: 'code', label: 'Код' }, { key: 'tool_type', label: 'Тип' },
      { key: 'diameter', label: 'Ø', num: true }, { key: 'equipment', label: 'Станок' },
      { key: 'status', label: 'Статус', value: function (t) { return STAT[t.status] || t.status; } },
      { key: 'used_min', label: 'Наработка, мин', num: true }, { key: 'resource_min', label: 'Ресурс, мин', num: true },
      { key: 'life_pct', label: 'Износ, %', num: true }, { key: 'wears', label: 'Заточек (факт/макс)', num: true, value: function (t) { return num(t.wears) + '/' + num(t.max_wears); } }
    ];
    AppExport.exportPdf('Инструмент — отчёт', AppExport.reportDocument({
      brand: '3DMP Service', title: 'Отчёт по инструменту и стойкости', subtitle: new Date().toLocaleDateString('ru-RU'),
      kpis: [{ label: 'Инструмента', value: tools.length }],
      sections: [{ title: 'Инструмент', columns: cols, rows: tools }],
      sign: ['Инженер-технолог', 'Начальник цеха'], footer: '3DMP Service · инструмент'
    }));
  }
  $('#repBtn').addEventListener('click', reportPdf);
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_tool_life_list', { p_token: token, p_q: null }),
      rpc('app_tool_kpi', { p_token: token }),
      rpc('app_equipment_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      tools = r[0] || []; var k = (r[1] && r[1][0]) || {}; eq = r[2] || [];
      $('#gEq').innerHTML = '<option value="">— не выбрано —</option>' + eq.map(function (e) { return '<option value="' + e.id + '">' + esc(e.name) + '</option>'; }).join('');
      $('#kpis').innerHTML = cell('Инструмента', num(k.tools_total)) + cell('Изношено', num(k.worn), k.worn ? '#92400e' : '') +
        cell('Списано', num(k.scrapped), k.scrapped ? '#b91c1c' : '') + cell('Средний износ', num(k.avg_life) + '%');
      render();
    }).catch(function (e) { msg('#tMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function render() {
    var list = tools.filter(function (t) { if (!q) return true; var s = q.toLowerCase(); return [t.name, t.code, t.tool_type, t.equipment, t.location].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + list.length + ')';
    $('#list').innerHTML = list.length ? list.map(function (t) {
      var pct = Math.max(0, Math.min(100, num(t.life_pct)));
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + (t.status === 'ok' ? 'done' : t.status === 'worn' ? 'in_progress' : 'cancelled') + '">' + (STAT[t.status] || t.status) + '</span>' +
        '<b>' + esc(t.name) + '</b>' +
        '<span class="note">' + (t.code ? esc(t.code) + ' · ' : '') + (t.tool_type ? esc(t.tool_type) + ' · ' : '') + (t.diameter ? 'Ø' + num(t.diameter) + ' · ' : '') + (t.equipment ? '🏭 ' + esc(t.equipment) : '') + '</span>' +
        '<span class="note" style="margin-left:auto;">наработка ' + num(t.used_min) + ' / ' + num(t.resource_min) + ' мин · заточек ' + t.wears + '/' + t.max_wears + '</span></div>' +
        '<div class="life ' + t.status + '"><i style="width:' + pct + '%"></i></div>' +
        '<div class="toolbar mt">' +
        '<button class="btn secondary" data-use="' + t.id + '" data-name="' + esc(t.name) + '" style="width:auto;padding:8px 14px;">Учесть наработку</button>' +
        '<button class="btn secondary" data-resh="' + t.id + '" style="width:auto;padding:8px 14px;">Заточка</button>' +
        '</div></div>';
    }).join('') : '<span class="note">Инструмента нет.</span>';
    $$('#list [data-use]').forEach(function (b) {
      b.addEventListener('click', function () {
        var m = window.prompt('Наработка инструмента «' + b.dataset.name + '», минут:', '30');
        if (m == null) return;
        var mv = parseFloat(String(m).replace(',', '.'));
        if (isNaN(mv) || mv <= 0) return;
        rpc('app_tool_life_use', { p_token: token, p_id: b.dataset.use, p_minutes: mv, p_note: null })
          .then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Учтено'); window.Auth.log('Наработка инструмента', b.dataset.name); if (window.AppNotify) window.AppNotify.refresh(true); load(); })
          .catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
      });
    });
    $$('#list [data-resh]').forEach(function (b) {
      b.addEventListener('click', function () {
        if (!window.confirm('Зарегистрировать заточку? Наработка обнулится.')) return;
        rpc('app_tool_life_resharpen', { p_token: token, p_id: b.dataset.resh, p_note: null })
          .then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово'); window.Auth.log('Заточка инструмента', ''); load(); })
          .catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
      });
    });
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#gAdd').addEventListener('click', function () {
    var name = $('#gName').value.trim(); if (!name) { msg('#tMsg', 'Укажите наименование.', 'err'); return; }
    var dia = parseFloat(($('#gDia').value || '').replace(',', '.'));
    var res = parseFloat(($('#gRes').value || '').replace(',', '.'));
    var wr = parseInt($('#gWears').value || '', 10);
    rpc('app_tool_life_save', { p_token: token, p_id: null, p_code: $('#gCode').value.trim(), p_name: name, p_tool_type: $('#gType').value.trim(),
      p_material: $('#gMat').value.trim(), p_coating: $('#gCoat').value.trim(), p_diameter: isNaN(dia) ? null : dia,
      p_equipment_id: $('#gEq').value || null, p_resource_min: isNaN(res) ? 0 : res, p_max_wears: isNaN(wr) ? 3 : wr,
      p_location: $('#gLoc').value.trim(), p_note: null })
      .then(function (d) { var r = d && d[0]; msg('#tMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('Инструмент', name); ['#gCode', '#gName', '#gType', '#gMat', '#gCoat', '#gDia', '#gRes', '#gWears', '#gLoc'].forEach(function (s) { $(s).value = ''; }); load(); } })
      .catch(function (e) { msg('#tMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token; applyCaps();
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#tMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
