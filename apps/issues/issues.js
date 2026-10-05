/* ============================================================
   3DMP Service · apps/issues — проблемы и эскалация (B24)
   Данные: 0060. Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, list = [], eq = [], orders = [], q = '';

  var PR = { low: 'Низкий', normal: 'Обычный', high: 'Высокий', critical: 'Критический' };
  var ST = { open: 'Открыта', in_progress: 'В работе', resolved: 'Решена', closed: 'Закрыта' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_issue_list', { p_token: token, p_q: null }),
      rpc('app_issue_kpi', { p_token: token }),
      rpc('app_equipment_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; var k = (r[1] && r[1][0]) || {}; eq = r[2] || []; orders = r[3] || [];
      $('#fEq').innerHTML = '<option value="">— нет —</option>' + eq.map(function (e) { return '<option value="' + e.id + '">' + esc(e.name) + '</option>'; }).join('');
      $('#fOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + '</option>'; }).join('');
      $('#kpis').innerHTML = cell('Открытых', num(k.issues_open)) + cell('Критических', num(k.critical), num(k.critical) ? '#b91c1c' : '') +
        cell('Эскалировано', num(k.escalated), num(k.escalated) ? '#b91c1c' : '') + cell('Просрочено', num(k.overdue), num(k.overdue) ? '#b91c1c' : '');
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (i) { if (!s) return true; return [i.title, i.assignee].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (i) {
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + (i.priority === 'critical' ? 'cancelled' : i.priority === 'high' ? 'in_progress' : '') + '">' + (PR[i.priority] || i.priority) + '</span>' +
        (i.escalated ? '<span class="badge cancelled">эскалация</span>' : '') + '<b>' + esc(i.title) + '</b>' +
        (i.overdue ? '<span class="badge overdue">просрочено</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + (i.assignee ? '👤 ' + esc(i.assignee) + ' · ' : '') + 'срок ' + fmt(i.due_date) + '</span></div>' +
        '<div style="font-size:.76rem;color:var(--muted);margin-top:4px;">' + (i.equipment ? '🏭 ' + esc(i.equipment) + ' · ' : '') + (i.order_number ? '📥 ' + esc(i.order_number) : '') + '</div>' +
        '<div class="toolbar mt">' +
        '<select data-st="' + i.id + '" style="padding:7px;border:1px solid var(--border);border-radius:8px;font-size:.78rem;">' +
        Object.keys(ST).map(function (k) { return '<option value="' + k + '"' + (i.status === k ? ' selected' : '') + '>' + ST[k] + '</option>'; }).join('') + '</select>' +
        (i.status !== 'resolved' && i.status !== 'closed' && !i.escalated ? '<button class="btn secondary" data-esc="' + i.id + '" style="width:auto;padding:8px 14px;">Эскалировать</button>' : '') +
        '</div></div>';
    }).join('') : '<span class="note">Проблем нет.</span>';
    $$('#list [data-st]').forEach(function (sel) {
      sel.addEventListener('change', function () { rpc('app_issue_set_status', { p_token: token, p_id: sel.dataset.st, p_status: sel.value }).then(function (d) { var r = d && d[0]; if (r && !r.ok) { ui.toast(r.message); return; } window.Auth.log('Проблема статус', sel.value); load(); }); });
    });
    $$('#list [data-esc]').forEach(function (b) {
      b.addEventListener('click', function () {
        if (!window.confirm('Эскалировать проблему руководству (критический приоритет)?')) return;
        rpc('app_issue_escalate', { p_token: token, p_id: b.dataset.esc, p_note: null }).then(function (d) { var r = d && d[0]; ui.toast((r && r.message) || 'Готово'); window.Auth.log('Эскалация', b.dataset.esc); if (window.AppNotify) window.AppNotify.refresh(true); load(); });
      });
    });
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fAdd').addEventListener('click', function () {
    var t = $('#fTitle').value.trim(); if (!t) { msg('#fMsg', 'Укажите тему.', 'err'); return; }
    rpc('app_issue_save', { p_token: token, p_id: null, p_title: t, p_description: $('#fDescr').value.trim(), p_priority: $('#fPriority').value,
      p_assignee: $('#fAsg').value.trim(), p_due_date: $('#fDue').value || null, p_order_id: $('#fOrder').value || null, p_equipment_id: $('#fEq').value || null, p_source: null })
      .then(function (d) { var r = d && d[0]; msg('#fMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('Проблема', t); ['#fTitle', '#fAsg', '#fDue', '#fDescr'].forEach(function (s) { $(s).value = ''; }); if (window.AppNotify) window.AppNotify.refresh(true); load(); } })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
