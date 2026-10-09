/* ============================================================
   3DMP Service · apps/tasks — задачи/проекты + inbox (W16, 0164).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, projects = [], tasks = [], prj = null;
  var COLS = [{ s: 'todo', t: 'К выполнению' }, { s: 'in_progress', t: 'В работе' }, { s: 'done', t: 'Готово' }];
  var PRI = { low: 'низкий', normal: 'обычный', high: 'высокий' };
  var IB = { new: 'Новое', assigned: 'Назначено', closed: 'Закрыто' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dd(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'prj') loadProjects();
    if (scr === 'board') loadProjects().then(function () { if (projects[0]) { $('#prjSel').value = prj ? prj.id : projects[0].id; loadBoard(); } });
    if (scr === 'my') loadMy();
    if (scr === 'inbox') loadInbox();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_collab_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Проектов', k.projects || 0) + cell('Открытых задач', k.tasks_open || 0) + cell('Выполнено', k.tasks_done || 0) + cell('Просрочено', k.overdue || 0) + cell('Часов учтено', k.logged_hours || 0) + cell('Обращений', k.inbox_open || 0);
    });
  }

  /* ---------- Проекты ---------- */
  function loadProjects() {
    return rpc('app_projects_list', { p_token: token, p_q: $('#pq').value || null }).then(function (r) {
      projects = r || [];
      $('#projects').innerHTML = projects.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Проект</th><th>Код</th><th>Статус</th><th class="num">Задач</th><th class="num">Готово</th><th></th></tr></thead><tbody>' +
        projects.map(function (p) {
          return '<tr><td><b>' + esc(p.name) + '</b></td><td>' + esc(p.code || '') + '</td><td>' + esc(p.status) + '</td><td class="num">' + p.tasks + '</td><td class="num">' + p.done + '</td>' +
            '<td style="white-space:nowrap;"><button class="act" data-open="' + p.id + '">Доска</button><button class="act" data-edit="' + p.id + '">Изменить</button><button class="act danger" data-del="' + p.id + '">Удалить</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Проектов нет.</span>';
      $('#prjSel').innerHTML = projects.map(function (p) { return '<option value="' + p.id + '">' + esc(p.name) + '</option>'; }).join('') || '<option value="">—</option>';
      $$('#projects [data-open]').forEach(function (b) { b.addEventListener('click', function () { prj = projects.filter(function (x) { return x.id === b.dataset.open; })[0]; showTab('board'); }); });
      $$('#projects [data-edit]').forEach(function (b) { b.addEventListener('click', function () { prjForm(projects.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
      $$('#projects [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить проект?')) return; rpc('app_project_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadProjects(); loadKpi(); }); }); });
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function prjForm(p) {
    p = p || {};
    ui.formDialog({ title: p.id ? 'Проект' : 'Новый проект', okText: 'Сохранить', fields: [
      { name: 'name', label: 'Название', type: 'text', required: true }, { name: 'code', label: 'Код', type: 'text' },
      { name: 'status', label: 'Статус', type: 'select', options: [{ value: 'active', label: 'Активен' }, { value: 'done', label: 'Завершён' }, { value: 'archived', label: 'Архив' }] },
      { name: 'owner', label: 'Ответственный (логин)', type: 'text' }, { name: 'due', label: 'Срок', type: 'date' }
    ], values: { name: p.name || '', code: p.code || '', status: p.status || 'active', owner: p.owner_login || '', due: p.due_date || '' } }).then(function (v) {
      if (!v) return;
      rpc('app_project_save', { p_token: token, p_id: p.id || null, p_name: v.name, p_code: v.code || null, p_status: v.status, p_owner: v.owner || null, p_start: null, p_due: v.due || null, p_note: null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadProjects(); loadKpi(); });
    });
  }

  /* ---------- Доска ---------- */
  function loadBoard() {
    var id = $('#prjSel').value; prj = projects.filter(function (p) { return p.id === id; })[0] || prj;
    if (!id) { $('#board').innerHTML = '<span class="note">Нет проектов.</span>'; return; }
    return rpc('app_tasks_list', { p_token: token, p_project_id: id, p_status: null, p_assignee: null }).then(function (r) {
      tasks = r || [];
      $('#board').innerHTML = COLS.map(function (c) {
        var list = tasks.filter(function (t) { return t.status === c.s; });
        return '<div class="kcol"><h4>' + c.t + ' (' + list.length + ')</h4>' + (list.length ? list.map(function (t) {
          return '<div class="kcard"><div class="k-t">' + esc(t.title) + '</div>' +
            '<div class="note">' + esc(t.assignee_login || '—') + (t.due_date ? ' · до ' + dd(t.due_date) : '') + (t.fact_hours ? ' · ' + t.fact_hours + 'ч' : '') + '</div>' +
            '<div style="margin-top:4px;display:flex;gap:4px;flex-wrap:wrap;"><button class="act" data-open="' + t.id + '">Открыть</button>' +
            (c.s !== 'done' ? '<button class="act" data-next="' + t.id + '">→</button>' : '') + '</div></div>';
        }).join('') : '<div class="note" style="padding:6px;">—</div>') + '</div>';
      }).join('');
      $$('#board [data-open]').forEach(function (b) { b.addEventListener('click', function () { openTask(tasks.filter(function (t) { return t.id === b.dataset.open; })[0]); }); });
      $$('#board [data-next]').forEach(function (b) { b.addEventListener('click', function () {
        var t = tasks.filter(function (x) { return x.id === b.dataset.next; })[0];
        var next = t.status === 'todo' ? 'in_progress' : 'done';
        rpc('app_task_set_status', { p_token: token, p_id: t.id, p_status: next }).then(function () { loadBoard(); loadKpi(); });
      }); });
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function taskForm() {
    var pid = $('#prjSel').value;
    ui.formDialog({ title: 'Новая задача', okText: 'Создать', fields: [
      { name: 'title', label: 'Задача', type: 'text', required: true },
      { name: 'assignee', label: 'Исполнитель (логин)', type: 'text' },
      { name: 'priority', label: 'Приоритет', type: 'select', options: Object.keys(PRI).map(function (k) { return { value: k, label: PRI[k] }; }) },
      { name: 'due', label: 'Срок', type: 'date' }, { name: 'est', label: 'Оценка, ч', type: 'number' },
      { name: 'desc', label: 'Описание', type: 'textarea', rows: 2 }
    ], values: { priority: 'normal' } }).then(function (v) {
      if (!v) return;
      rpc('app_task_save', { p_token: token, p_id: null, p_project_id: pid || null, p_title: v.title, p_description: v.desc || null, p_status: 'todo', p_priority: v.priority, p_assignee: v.assignee || null, p_due: v.due || null, p_est: v.est ? Number(v.est) : null, p_pos: 0, p_entity_type: null, p_entity_id: null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadBoard(); loadKpi(); });
    });
  }
  function openTask(t) {
    if (!t) return;
    Promise.all([
      rpc('app_task_time_list', { p_token: token, p_task_id: t.id }).catch(function () { return []; }),
      rpc('app_messages_list', { p_token: token, p_entity_type: 'task', p_entity_id: t.id }).catch(function () { return []; })
    ]).then(function (r) {
      var tm = r[0] || [], cm = r[1] || [];
      var html = '<div class="note"><b>' + esc(t.title) + '</b> · ' + esc(t.assignee_login || '—') + ' · ' + esc(PRI[t.priority] || '') + (t.due_date ? ' · до ' + dd(t.due_date) : '') + ' · факт ' + (t.fact_hours || 0) + 'ч</div>' +
        '<div class="form-grid mt"><div class="field"><label>Часы</label><input type="number" id="ttH" step="0.5"></div><div class="field"><label>Дата</label><input type="date" id="ttD"></div><div class="field" style="display:flex;align-items:flex-end;"><button class="btn" id="ttAdd" style="width:auto;padding:6px 10px;">Учесть время</button></div></div>' +
        '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Дата</th><th>Кто</th><th class="num">Часы</th></tr></thead><tbody>' +
        (tm.length ? tm.map(function (x) { return '<tr><td>' + dd(x.work_date) + '</td><td>' + esc(x.user_login || '') + '</td><td class="num">' + x.hours + '</td></tr>'; }).join('') : '<tr><td colspan="3" class="note">Нет записей</td></tr>') + '</tbody></table></div>' +
        '<h4 class="mt">Обсуждение</h4>' +
        '<div id="msgList">' + (cm.length ? cm.map(function (x) { return '<div class="ocard"><div class="note">' + esc(x.author_login || '') + ' · ' + (x.created_at ? new Date(x.created_at).toLocaleString('ru-RU') : '') + '</div><div>' + esc(x.body) + '</div></div>'; }).join('') : '<span class="note">Сообщений нет.</span>') + '</div>' +
        '<div class="field mt"><input id="msgText" placeholder="Сообщение (@логин для упоминания)"></div>';
      ui.dialog({ title: 'Задача', body: html, html: true, okText: 'Написать', cancelText: 'Закрыть', onOpen: function (back) {
        back.querySelector('#ttAdd').addEventListener('click', function () { var h = back.querySelector('#ttH').value; if (!h) return; rpc('app_task_time_add', { p_token: token, p_task_id: t.id, p_hours: Number(h), p_work_date: back.querySelector('#ttD').value || null, p_note: null }).then(function () { back.querySelector('[data-ok]').click(); }); });
      } }).then(function (ok) {
        if (!ok) { loadBoard(); loadKpi(); return; }
        var el = $('#msgText'); var body = el ? el.value.trim() : '';
        if (body) rpc('app_message_add', { p_token: token, p_entity_type: 'task', p_entity_id: t.id, p_body: body }).then(function () { openTask(t); });
        else { loadBoard(); loadKpi(); }
      });
    });
  }

  /* ---------- Мои задачи ---------- */
  function loadMy() {
    return rpc('app_my_tasks', { p_token: token }).then(function (r) {
      var list = r || [];
      $('#my').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Проект</th><th>Задача</th><th>Статус</th><th>Приоритет</th><th>Срок</th><th></th></tr></thead><tbody>' +
        list.map(function (t) { return '<tr><td>' + esc(t.project || '') + '</td><td><b>' + esc(t.title) + '</b></td><td>' + esc(t.status) + '</td><td>' + esc(PRI[t.priority] || '') + '</td><td>' + dd(t.due_date) + '</td>' +
          '<td><button class="act" data-done="' + t.id + '">Готово</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Мои задачи пусты.</span>';
      $$('#my [data-done]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_task_set_status', { p_token: token, p_id: b.dataset.done, p_status: 'done' }).then(function () { loadMy(); loadKpi(); }); }); });
    });
  }

  /* ---------- Inbox ---------- */
  function loadInbox() {
    var st = $('#ibStatus').value || null;
    return rpc('app_inbox_list', { p_token: token, p_status: st }).then(function (r) {
      var list = r || [];
      $('#inbox').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Канал</th><th>Контрагент</th><th>Тема</th><th>Статус</th><th>Исполнитель</th><th>Действия</th></tr></thead><tbody>' +
        list.map(function (i) {
          var acts = '';
          if (i.status !== 'closed') acts += '<button class="act" data-assign="' + i.id + '">Назначить</button><button class="act" data-close="' + i.id + '">Закрыть</button>';
          return '<tr><td>' + esc(i.channel) + '</td><td>' + esc(i.counterparty || '') + '</td><td>' + esc(i.subject) + '</td><td>' + esc(IB[i.status] || i.status) + '</td><td class="muted">' + esc(i.assignee_login || '') + '</td><td style="white-space:nowrap;">' + acts + '</td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Обращений нет.</span>';
      $$('#inbox [data-assign]').forEach(function (b) { b.addEventListener('click', function () { var who = prompt('Исполнитель (логин):', ''); rpc('app_inbox_set_status', { p_token: token, p_id: b.dataset.assign, p_status: 'assigned', p_assignee: who }).then(function () { loadInbox(); loadKpi(); }); }); });
      $$('#inbox [data-close]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_inbox_set_status', { p_token: token, p_id: b.dataset.close, p_status: 'closed', p_assignee: null }).then(function () { loadInbox(); loadKpi(); }); }); });
    });
  }
  function ibForm() {
    ui.formDialog({ title: 'Новое обращение', okText: 'Создать', fields: [
      { name: 'channel', label: 'Канал', type: 'select', options: [{ value: 'email', label: 'E-mail' }, { value: 'chat', label: 'Чат' }, { value: 'sms', label: 'SMS' }, { value: 'call', label: 'Звонок' }, { value: 'other', label: 'Прочее' }] },
      { name: 'counterparty', label: 'Контрагент', type: 'text', required: true }, { name: 'subject', label: 'Тема', type: 'text', required: true },
      { name: 'assignee', label: 'Исполнитель (логин)', type: 'text' }
    ], values: { channel: 'email' } }).then(function (v) {
      if (!v) return;
      rpc('app_inbox_save', { p_token: token, p_id: null, p_channel: v.channel, p_counterparty: v.counterparty, p_subject: v.subject, p_body: null, p_assignee: v.assignee || null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadInbox(); loadKpi(); });
    });
  }

  $('#addPrj').addEventListener('click', function () { prjForm(null); });
  $('#pq').addEventListener('input', loadProjects);
  $('#prjSel').addEventListener('change', loadBoard);
  $('#addTask').addEventListener('click', taskForm);
  $('#myBtn').addEventListener('click', loadMy);
  $('#ibStatus').addEventListener('change', loadInbox);
  $('#addIb').addEventListener('click', ibForm);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadKpi(); loadProjects();
  });
})();
