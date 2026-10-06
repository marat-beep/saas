/* ============================================================
   3DMP Service · apps/setup — B20 наладка. Данные: 0077.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], naryads = [], cur = null, q = '';

  var T = { setup: 'Наладка', changeover: 'Переналадка', trial: 'Пробный пуск', adjust: 'Подналадка' };
  var ST = { planned: ['Запланирована', 'normal'], in_progress: ['В работе', 'in_progress'], done: ['Выполнена', 'done'], cancelled: ['Отменена', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_setups_list', { p_token: token, p_q: null }),
      rpc('app_setups_kpi', { p_token: token }),
      rpc('app_naryad_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; naryads = r[2] || [];
      $('#fNaryad').innerHTML = '<option value="">— не выбран —</option>' + naryads.map(function (n) { return '<option value="' + n.id + '">' + esc(n.number) + ' · ' + esc(n.title) + '</option>'; }).join('');
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('Запланировано', k.planned || 0) + cell('В работе', k.in_progress || 0) + cell('Выполнено', k.done || 0) + cell('Часы план/факт', (k.hours_planned || 0) + ' / ' + (k.hours_fact || 0));
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (x) { return !s || [(x.equipment || ''), (x.assignee || ''), (x.naryad_number || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (x) {
      var st = ST[x.status] || [x.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(x.equipment || '—') + '</b>' +
        '<span class="badge">' + esc(T[x.setup_type] || x.setup_type) + '</span>' +
        (x.naryad_number ? '<span class="note">наряд ' + esc(x.naryad_number) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + (x.planned_hours || 0) + ' / ' + (x.fact_hours || 0) + ' ч</span></div>' +
        (x.assignee ? '<div class="note mt">Исполнитель: ' + esc(x.assignee) + '</div>' : '') +
        '<div class="toolbar mt"><button class="btn secondary" data-edit="' + x.id + '" style="width:auto;padding:7px 12px;">Править</button>' +
        (x.status !== 'in_progress' && x.status !== 'done' ? '<button class="btn" data-st="in_progress" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">В работу</button>' : '') +
        (x.status !== 'done' ? '<button class="btn" data-st="done" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">Выполнено</button>' : '') +
        '<button class="btn secondary" data-del="' + x.id + '" style="width:auto;padding:7px 12px;">Удалить</button></div></div>';
    }).join('') : '<span class="note">Наладок нет.</span>';
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { edit(b.dataset.edit); }); });
    $$('#list [data-st]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_setup_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.st, p_fact_hours: null }).then(load).catch(function (e) { msg('#mMsg', e.message, 'err'); }); }); });
    $$('#list [data-del]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_setup_delete', { p_token: token, p_id: b.dataset.del }).then(load); }); });
  }

  function loadDict() {
    return rpc('app_dict_items_by_code', { p_token: token, p_code: 'setup_type' }).then(function (r) {
      if (!r || !r.length) return;
      var map = {}; r.forEach(function (x) { map[x.value] = x.label; });
      T = map;
      $('#fType').innerHTML = r.map(function (x) { return '<option value="' + esc(x.value) + '">' + esc(x.label) + '</option>'; }).join('');
      render();
    }).catch(function () {});
  }

  function edit(id) {
    cur = list.filter(function (x) { return x.id === id; })[0]; if (!cur) return;
    $('#fNaryad').value = cur.naryad_id || ''; $('#fEquip').value = cur.equipment || ''; $('#fType').value = cur.setup_type || 'setup';
    $('#fHours').value = cur.planned_hours || 0; $('#fAssignee').value = cur.assignee || ''; window.scrollTo(0, 0);
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fClear').addEventListener('click', function () { cur = null; ['fEquip', 'fAssignee', 'fNote'].forEach(function (i) { $('#' + i).value = ''; }); msg('#fMsg', ''); });
  $('#fSave').addEventListener('click', function () {
    rpc('app_setup_save', { p_token: token, p_id: cur ? cur.id : null, p_naryad_id: $('#fNaryad').value || null, p_equipment: $('#fEquip').value,
      p_setup_type: $('#fType').value, p_planned_hours: parseFloat($('#fHours').value) || 0, p_assignee: $('#fAssignee').value, p_note: $('#fNote').value })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('Наладка', $('#fEquip').value); cur = null; load(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load().then(loadDict);
  });
})();
