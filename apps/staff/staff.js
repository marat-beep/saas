/* ============================================================
   3DMP Service · apps/staff — B12 CRM сотрудников. Данные: 0084.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], cur = null, q = '';

  var ST = { active: ['Работает', 'done'], leave: ['Отпуск', 'in_progress'], fired: ['Уволен', 'cancelled'] };
  var EK = { note: 'Заметка', one_on_one: '1-на-1', review: 'Аттестация', promotion: 'Повышение', warning: 'Замечание' };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function d(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }

  function load() {
    return Promise.all([
      rpc('app_staff_list', { p_token: token, p_q: null }),
      rpc('app_staff_kpi', { p_token: token })
    ]).then(function (r) {
      list = r[0] || [];
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('Работают', k.active || 0) + cell('В отпуске', k.on_leave || 0) + cell('Уволены', k.fired || 0) + cell('Ср. рейтинг', k.avg_rating || 0);
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (x) { return !s || [(x.name || ''), (x.pos || ''), (x.department || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (x) {
      var st = ST[x.status] || [x.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(x.name) + '</b>' +
        '<span class="note">' + esc(x.pos || '') + ' · ' + esc(x.department || '') + '</span>' +
        '<span class="note" style="margin-left:auto;">рейтинг ' + (x.rating || 0) + ' · записей ' + (x.events || 0) + '</span></div>' +
        (x.manager ? '<div class="note mt">Руководитель: ' + esc(x.manager) + '</div>' : '') +
        '<div class="toolbar mt"><button class="btn secondary" data-edit="' + x.id + '" style="width:auto;padding:7px 12px;">Править</button>' +
        '<button class="btn" data-ev="' + x.id + '" style="width:auto;padding:7px 12px;">История</button></div></div>';
    }).join('') : '<span class="note">Сотрудников нет.</span>';
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { edit(b.dataset.edit); }); });
    $$('#list [data-ev]').forEach(function (b) { b.addEventListener('click', function () { openEvents(b.dataset.ev); }); });
  }

  function edit(id) {
    cur = list.filter(function (x) { return x.id === id; })[0]; if (!cur) return;
    $('#fName').value = cur.name || ''; $('#fPos').value = cur.pos || ''; $('#fDept').value = cur.department || '';
    $('#fMgr').value = cur.manager || ''; $('#fStatus').value = cur.status || 'active'; $('#fHired').value = cur.hired_at || ''; $('#fRating').value = cur.rating || 0;
    window.scrollTo(0, 0);
  }

  function openEvents(id) {
    cur = list.filter(function (x) { return x.id === id; })[0]; if (!cur) return;
    $('#evCard').style.display = 'block'; $('#evTitle').textContent = '· ' + (cur.name || '');
    rpc('app_staff_events_list', { p_token: token, p_staff_id: id }).then(function (r) {
      var rows = r || [];
      $('#events').innerHTML = rows.length ? rows.map(function (e) {
        return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;"><span class="badge">' + esc(EK[e.kind] || e.kind) + '</span><span>' + esc(e.note || '') + '</span>' +
          '<span class="note" style="margin-left:auto;">' + new Date(e.created_at).toLocaleString('ru-RU') + (e.author ? ' · ' + esc(e.author) : '') + '</span></div></div>';
      }).join('') : '<span class="note">Записей нет.</span>';
    });
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fClear').addEventListener('click', function () { cur = null; ['fName', 'fPos', 'fDept', 'fMgr'].forEach(function (i) { $('#' + i).value = ''; }); msg('#fMsg', ''); });
  $('#fSave').addEventListener('click', function () {
    rpc('app_staff_save', { p_token: token, p_id: cur ? cur.id : null, p_name: $('#fName').value, p_position: $('#fPos').value,
      p_department: $('#fDept').value, p_manager: $('#fMgr').value, p_status: $('#fStatus').value,
      p_hired_at: $('#fHired').value || null, p_rating: parseFloat($('#fRating').value) || 0, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('Сотрудник', $('#fName').value); cur = null; load(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#evAdd').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_staff_event_add', { p_token: token, p_staff_id: cur.id, p_kind: $('#evKind').value, p_note: $('#evNote').value })
      .then(function () { msg('#evMsg', 'Запись добавлена', 'ok'); $('#evNote').value = ''; openEvents(cur.id); load(); })
      .catch(function (e) { msg('#evMsg', 'Ошибка: ' + e.message, 'err'); });
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
