/* ============================================================
   3DMP Service · apps/support — тикеты поддержки. Данные: 0100.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, role = null, list = [], cur = null, filter = { status: '', scope: '', mine: false };

  var ST = { new: ['Новый', 'high'], open: ['Открыт', 'new'], in_progress: ['В работе', 'in_progress'], waiting: ['Ожидание', 'normal'], resolved: ['Решён', 'done'], closed: ['Закрыт', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function isAgent() { return ['admin', 'owner', 'manager', 'director', 'support'].indexOf(role) >= 0; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function d(v) { return v ? new Date(v).toLocaleString('ru-RU') : '—'; }

  function loadKpi() {
    return rpc('app_support_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('Новые', k.new_cnt || 0) + cell('В работе', k.in_work || 0) + cell('Просрочено', k.overdue || 0) + cell('Решено/30д', k.resolved30 || 0) + cell('CSAT', k.csat_avg || '—');
    });
  }
  function load() {
    return rpc('app_support_ticket_list', { p_token: token, p_status: filter.status || null, p_scope: filter.scope || null, p_mine: filter.mine }).then(function (r) {
      list = r || []; render();
    });
  }
  function render() {
    $('#cnt').textContent = '(' + list.length + ')';
    $('#list').innerHTML = list.length ? '<table class="mini"><thead><tr><th>№</th><th>Тема</th><th>Кат.</th><th>Приоритет</th><th>Статус</th><th>Заявитель</th><th>Исполнитель</th><th>SLA до</th></tr></thead><tbody>' +
      list.map(function (t) {
        var st = ST[t.status] || [t.status, ''];
        var over = t.sla_resolve_due && new Date(t.sla_resolve_due) < new Date() && ['resolved', 'closed'].indexOf(t.status) < 0;
        return '<tr data-open="' + t.id + '" style="cursor:pointer;"><td>' + esc(t.number) + '</td><td>' + esc(t.subject) + '</td><td>' + esc(t.category) + '</td>' +
          '<td>' + esc(t.priority) + '</td><td><span class="badge ' + st[1] + '">' + esc(st[0]) + '</span>' + (t.escalated ? ' ⚠' : '') + '</td>' +
          '<td>' + esc(t.requester_name || '') + '</td><td>' + esc(t.assignee_login || '') + '</td>' +
          '<td' + (over ? ' style="color:#b91c1c;font-weight:700"' : '') + '>' + d(t.sla_resolve_due) + '</td></tr>';
      }).join('') + '</tbody></table>' : '<span class="note">Тикетов нет.</span>';
    $$('#list [data-open]').forEach(function (tr) { tr.addEventListener('click', function () { open(tr.dataset.open); }); });
  }

  function open(id) {
    cur = id;
    Promise.all([
      rpc('app_support_ticket_get', { p_token: token, p_id: id }),
      rpc('app_support_message_list', { p_token: token, p_ticket_id: id })
    ]).then(function (r) {
      var t = (r[0] && r[0][0]) || {};
      $('#card').style.display = 'block';
      $('#cardTitle').textContent = t.number + ' · ' + t.subject;
      $('#cardMeta').textContent = 'Статус: ' + t.status + ' · приоритет: ' + t.priority + ' · scope: ' + t.scope + ' · заявитель: ' + (t.requester_name || '') + ' · исполнитель: ' + (t.assignee_login || '—') + ' · SLA ответа: ' + d(t.sla_response_due) + ' · SLA решения: ' + d(t.sla_resolve_due);
      $('#cStatus').value = ['open', 'in_progress', 'waiting', 'resolved', 'closed'].indexOf(t.status) >= 0 ? t.status : 'open';
      var ms = r[1] || [];
      $('#messages').innerHTML = ms.length ? ms.map(function (m) {
        return '<div class="msg-row ' + (m.is_internal ? 'int' : '') + '"><div class="note">' + esc(m.author_name || m.author_login) + ' · ' + esc(m.author_role) + ' · ' + d(m.created_at) + (m.is_internal ? ' · внутренняя' : '') + '</div><div>' + esc(m.body) + '</div></div>';
      }).join('') : '<span class="note">Сообщений нет.</span>';
      $('#card').scrollIntoView({ behavior: 'smooth' });
    }).catch(function (e) { msg('#mMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  $('#nCreate').addEventListener('click', function () {
    rpc('app_support_ticket_create', { p_token: token, p_subject: $('#nSubject').value, p_description: $('#nDesc').value, p_category: $('#nCategory').value, p_priority: $('#nPriority').value, p_scope: $('#nScope').value, p_module: $('#nModule').value, p_url: location.href, p_related_type: null, p_related_id: null })
      .then(function (r) { var x = r && r[0]; msg('#nMsg', x ? ('Создан ' + x.number) : 'Ошибка', x ? 'ok' : 'err'); if (x) { $('#nSubject').value = ''; $('#nDesc').value = ''; window.Auth.log('Тикет создан', x.number); loadKpi(); load(); } })
      .catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#cReply').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_support_ticket_reply', { p_token: token, p_id: cur, p_body: $('#cBody').value, p_internal: $('#cInternal').checked })
      .then(function (r) { var x = r && r[0]; msg('#cMsg', x ? x.message : 'Ошибка', x && x.ok ? 'ok' : 'err'); $('#cBody').value = ''; window.Auth.log('Ответ по тикету', cur); open(cur); })
      .catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#cSet').addEventListener('click', function () { if (cur) rpc('app_support_ticket_set_status', { p_token: token, p_id: cur, p_status: $('#cStatus').value }).then(function () { load(); open(cur); }); });
  $('#cAssign').addEventListener('click', function () { if (!cur) return; var a = prompt('Логин исполнителя:', ''); if (a == null) return; rpc('app_support_ticket_assign', { p_token: token, p_id: cur, p_assignee_login: a }).then(function () { load(); open(cur); }); });
  $('#cEsc').addEventListener('click', function () { if (cur) rpc('app_support_ticket_escalate', { p_token: token, p_id: cur }).then(function () { load(); open(cur); }); });
  $('#cCsat').addEventListener('click', function () { if (!cur) return; var s = parseInt(prompt('Оценка 1–5:', '5'), 10) || 5; rpc('app_support_ticket_csat', { p_token: token, p_id: cur, p_score: s, p_comment: '' }).then(function () { loadKpi(); }); });
  $('#cClose').addEventListener('click', function () { $('#card').style.display = 'none'; cur = null; });
  $('#scanBtn').addEventListener('click', function () { rpc('app_support_escalate_scan', { p_token: token }).then(function (r) { var n = (r && r[0] && r[0].escalated) || 0; msg('#mMsg', 'Эскалировано: ' + n, n ? 'ok' : 'info'); load(); loadKpi(); }); });
  $('#fStatus').addEventListener('change', function () { filter.status = this.value; load(); });
  $('#fScope').addEventListener('change', function () { filter.scope = this.value; load(); });
  $('#fMine').addEventListener('change', function () { filter.mine = this.checked; load(); });

  function loadKb() {
    return rpc('app_support_kb_list', { p_token: token, p_query: $('#kbQ').value || null }).then(function (r) {
      var rows = r || []; $('#kbCnt').textContent = '(' + rows.length + ')';
      $('#kbList').innerHTML = rows.length ? rows.map(function (k) { return '<div class="ocard"><b>' + esc(k.title) + '</b> ' + (k.published ? '<span class="badge done">опубл.</span>' : '<span class="badge">черновик</span>') + '<div class="note mt">' + esc(k.body || '') + '</div></div>'; }).join('') : '<span class="note">Статей нет.</span>';
    });
  }
  $('#kbSave').addEventListener('click', function () { rpc('app_support_kb_save', { p_token: token, p_id: null, p_title: $('#kbT').value, p_body: $('#kbB').value, p_tags: null, p_published: true }).then(function (r) { var x = r && r[0]; msg('#kbMsg', x ? x.message : 'Ошибка', x && x.ok ? 'ok' : 'err'); $('#kbT').value = ''; $('#kbB').value = ''; loadKb(); }); });
  $('#kbQ').addEventListener('input', loadKb);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    token = s.token; role = s.role;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#mMsg', 'Supabase не подключён.', 'err'); return; }
    loadKpi(); load(); loadKb();
  });
})();
