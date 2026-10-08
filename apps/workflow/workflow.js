/* ============================================================
   3DMP Service · apps/workflow — Low-code workflow (W15, 0159).
   Процессы, задачи, экземпляры, правила, формы.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, defs = [], rules = [], forms = [];
  var ST = { running: 'В работе', done: 'Завершён', rejected: 'Отклонён', cancelled: 'Отменён' };

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); if (!e) return; e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function dt(v) { return v ? new Date(v).toLocaleString('ru-RU') : '—'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'defs') loadDefs();
    if (scr === 'my') loadMy();
    if (scr === 'inst') loadInst();
    if (scr === 'rules') loadRules();
    if (scr === 'forms') loadForms();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  /* ---------- Процессы ---------- */
  function loadDefs() {
    return rpc('app_process_defs_list', { p_token: token }).then(function (r) {
      defs = r || [];
      $('#defs').innerHTML = defs.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Название</th><th>Код</th><th>Тип</th><th>Этапы</th><th>Активен</th><th>Действия</th></tr></thead><tbody>' +
        defs.map(function (d) {
          var st = (d.steps || []).map(function (s) { return '<span class="chip">' + esc(s.name || s.role || '') + (s.sla_hours ? ' · ' + s.sla_hours + 'ч' : '') + '</span>'; }).join('');
          return '<tr><td><b>' + esc(d.name) + '</b></td><td class="muted">' + esc(d.code || '') + '</td><td>' + esc(d.doc_type || '') + '</td><td>' + (st || '—') + '</td><td>' + (d.active ? 'да' : 'нет') + '</td>' +
            '<td style="white-space:nowrap;"><button class="act" data-start="' + d.id + '">Запустить</button><button class="act" data-edit="' + d.id + '">Изменить</button><button class="act danger" data-del="' + d.id + '">Удалить</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Процессов нет.</span>';
      $$('#defs [data-start]').forEach(function (b) { b.addEventListener('click', function () { start(defs.filter(function (x) { return x.id === b.dataset.start; })[0]); }); });
      $$('#defs [data-edit]').forEach(function (b) { b.addEventListener('click', function () { defForm(defs.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
      $$('#defs [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить процесс?')) return; rpc('app_process_def_delete', { p_token: token, p_id: b.dataset.del }).then(function (r) { var x = r && r[0]; msg('#dMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadDefs(); }); }); });
    }).catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function defForm(d) {
    d = d || {};
    ui.formDialog({
      title: d.id ? 'Процесс' : 'Новый процесс', okText: 'Сохранить', size: 'lg', fields: [
        { name: 'name', label: 'Название', type: 'text', required: true },
        { name: 'code', label: 'Код', type: 'text' },
        { name: 'doc_type', label: 'Тип документа', type: 'text', placeholder: 'order' },
        { name: 'entity_type', label: 'Тип объекта', type: 'text', placeholder: 'order' },
        { name: 'steps', label: 'Этапы (JSON)', type: 'textarea', rows: 5, hint: '[{"ord":1,"name":"Нач. цеха","role":"chief","sla_hours":24},{"ord":2,"name":"Директор","role":"director","sla_hours":48}]' },
        { name: 'active', label: 'Активен', type: 'checkbox' }
      ],
      values: { name: d.name || '', code: d.code || '', doc_type: d.doc_type || '', entity_type: d.entity_type || '', steps: JSON.stringify(d.steps || [{ ord: 1, name: 'Начальник цеха', role: 'chief', sla_hours: 24 }], null, 2), active: d.active === false ? '' : 'да' }
    }).then(function (v) {
      if (!v) return;
      var steps; try { steps = JSON.parse(v.steps || '[]'); } catch (e) { msg('#dMsg', 'Некорректный JSON этапов', 'err'); return; }
      rpc('app_process_def_save', { p_token: token, p_id: d.id || null, p_name: v.name, p_code: v.code || null, p_doc_type: v.doc_type || null, p_entity_type: v.entity_type || null, p_steps: steps, p_active: !!v.active })
        .then(function (r) { var x = r && r[0]; msg('#dMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadDefs(); });
    });
  }
  function start(d) {
    ui.formDialog({ title: 'Запуск: ' + d.name, okText: 'Запустить', fields: [
      { name: 'entity_title', label: 'Название/номер объекта', type: 'text', required: true },
      { name: 'data', label: 'Данные (JSON, необязательно)', type: 'textarea', rows: 3 }
    ], values: {} }).then(function (v) {
      if (!v) return;
      var data; try { data = v.data ? JSON.parse(v.data) : {}; } catch (e) { msg('#dMsg', 'Некорректный JSON данных', 'err'); return; }
      rpc('app_process_start', { p_token: token, p_def_id: d.id, p_entity_type: d.entity_type || null, p_entity_id: null, p_entity_title: v.entity_title, p_data: data })
        .then(function (r) { var x = r && r[0]; msg('#dMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); showTab('my'); });
    });
  }

  /* ---------- Мои задачи ---------- */
  function loadMy() {
    return rpc('app_process_my', { p_token: token }).then(function (r) {
      var list = r || [];
      $('#my').innerHTML = list.length ? list.map(function (t) {
        return '<div class="ocard"><div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;"><b>' + esc(t.entity_title || '') + '</b>' +
          '<span class="note">' + esc(t.def_name || '') + ' · этап ' + t.step_ord + '/' + t.total_steps + ' · ' + esc(t.name || t.role || '') + (t.due_at ? ' · до ' + dt(t.due_at) : '') + '</span></div>' +
          '<div class="toolbar mt"><button class="btn" data-ok="' + t.task_id + '" style="width:auto;padding:7px 12px;">Утвердить</button>' +
          '<button class="btn secondary" data-no="' + t.task_id + '" style="width:auto;padding:7px 12px;">Отклонить</button></div></div>';
      }).join('') : '<span class="note">Задач нет.</span>';
      $$('#my [data-ok]').forEach(function (b) { b.addEventListener('click', function () { act(b.dataset.ok, 'approve'); }); });
      $$('#my [data-no]').forEach(function (b) { b.addEventListener('click', function () { act(b.dataset.no, 'reject'); }); });
    }).catch(function (e) { msg('#mMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function act(taskId, action) {
    ui.formDialog({ title: action === 'approve' ? 'Утвердить этап' : 'Отклонить', okText: 'Подтвердить', fields: [{ name: 'comment', label: 'Комментарий', type: 'text' }], values: {} }).then(function (v) {
      if (v === null) return;
      rpc('app_process_task_act', { p_token: token, p_task_id: taskId, p_action: action, p_comment: (v && v.comment) || null, p_data: null })
        .then(function (r) { var x = r && r[0]; msg('#mMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadMy(); });
    });
  }

  /* ---------- Экземпляры ---------- */
  function loadInst() {
    var st = $('#iStatus').value || null;
    return rpc('app_process_instances_list', { p_token: token, p_status: st }).then(function (r) {
      var list = r || [];
      $('#inst').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Объект</th><th>Процесс</th><th>Этап</th><th>Статус</th><th>Автор</th><th>Создан</th><th></th></tr></thead><tbody>' +
        list.map(function (i) {
          return '<tr><td><b>' + esc(i.entity_title || '') + '</b></td><td>' + esc(i.def_name || '') + '</td><td>' + i.current_step + '/' + i.total_steps + '</td>' +
            '<td>' + esc(ST[i.status] || i.status) + '</td><td class="muted">' + esc(i.requested_login || '') + '</td><td class="muted">' + dt(i.created_at) + '</td>' +
            '<td>' + (i.status === 'running' ? '<button class="act danger" data-cancel="' + i.id + '">Отменить</button>' : '') + '</td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Экземпляров нет.</span>';
      $$('#inst [data-cancel]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Отменить процесс?')) return; rpc('app_process_cancel', { p_token: token, p_instance_id: b.dataset.cancel, p_comment: null }).then(function () { loadInst(); }); }); });
    });
  }

  /* ---------- Правила ---------- */
  function loadRules() {
    return rpc('app_rules_list', { p_token: token }).then(function (r) {
      rules = r || [];
      $('#rules').innerHTML = rules.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Название</th><th>Событие</th><th>Условие</th><th>Действия</th><th class="num">Срабатываний</th><th></th></tr></thead><tbody>' +
        rules.map(function (r) {
          var cond = r.condition && r.condition.field ? (r.condition.field + ' ' + (r.condition.op || '=') + ' ' + (r.condition.value || '')) : '—';
          var acts = (r.actions || []).map(function (a) { return a.type; }).join(', ');
          return '<tr><td><b>' + esc(r.name) + '</b></td><td>' + esc(r.event) + '</td><td class="muted">' + esc(cond) + '</td><td>' + esc(acts) + '</td><td class="num">' + (r.run_count || 0) + '</td>' +
            '<td style="white-space:nowrap;"><button class="act" data-run="' + r.id + '">Проверить</button><button class="act" data-edit="' + r.id + '">Изменить</button><button class="act danger" data-del="' + r.id + '">Удалить</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Правил нет.</span>';
      $$('#rules [data-edit]').forEach(function (b) { b.addEventListener('click', function () { ruleForm(rules.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
      $$('#rules [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить правило?')) return; rpc('app_rule_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadRules(); }); }); });
      $$('#rules [data-run]').forEach(function (b) { b.addEventListener('click', function () { runRule(rules.filter(function (x) { return x.id === b.dataset.run; })[0]); }); });
    }).catch(function (e) { msg('#rMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function ruleForm(r) {
    r = r || {};
    ui.formDialog({
      title: r.id ? 'Правило' : 'Новое правило', okText: 'Сохранить', size: 'lg', fields: [
        { name: 'name', label: 'Название', type: 'text', required: true },
        { name: 'event', label: 'Событие', type: 'text', required: true, placeholder: 'order_created' },
        { name: 'condition', label: 'Условие (JSON)', type: 'textarea', rows: 2, hint: '{"field":"source","op":"contains","value":"снаб"}' },
        { name: 'actions', label: 'Действия (JSON)', type: 'textarea', rows: 4, hint: '[{"type":"notify","params":{"roles":["supply"],"title":"..."}}]' },
        { name: 'active', label: 'Активно', type: 'checkbox' }
      ],
      values: { name: r.name || '', event: r.event || '', condition: JSON.stringify(r.condition || {}, null, 0), actions: JSON.stringify(r.actions || [], null, 0), active: r.active === false ? '' : 'да' }
    }).then(function (v) {
      if (!v) return;
      var cond, acts; try { cond = JSON.parse(v.condition || '{}'); acts = JSON.parse(v.actions || '[]'); } catch (e) { msg('#rMsg', 'Некорректный JSON', 'err'); return; }
      rpc('app_rule_save', { p_token: token, p_id: r.id || null, p_name: v.name, p_event: v.event, p_condition: cond, p_actions: acts, p_active: !!v.active })
        .then(function (x) { var q = x && x[0]; msg('#rMsg', q ? q.message : '', q && q.ok ? 'ok' : 'err'); loadRules(); });
    });
  }
  function runRule(r) {
    ui.formDialog({ title: 'Проверка правила: ' + r.name, okText: 'Запустить', fields: [
      { name: 'event', label: 'Событие', type: 'text' },
      { name: 'context', label: 'Контекст (JSON)', type: 'textarea', rows: 3 }
    ], values: { event: r.event, context: '{"source":"снабжение","entity_title":"проверка"}' } }).then(function (v) {
      if (!v) return;
      var ctx; try { ctx = JSON.parse(v.context || '{}'); } catch (e) { msg('#rMsg', 'Некорректный JSON', 'err'); return; }
      rpc('app_rule_run', { p_token: token, p_event: v.event, p_context: ctx }).then(function (x) { var q = x && x[0]; msg('#rMsg', q ? q.messages : '', q && q.fired > 0 ? 'ok' : 'info'); loadRules(); });
    });
  }

  /* ---------- Формы ---------- */
  function loadForms() {
    return rpc('app_form_defs_list', { p_token: token }).then(function (r) {
      forms = r || [];
      $('#forms').innerHTML = forms.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Название</th><th>Код</th><th>Модуль</th><th>Поля</th><th></th></tr></thead><tbody>' +
        forms.map(function (f) { return '<tr><td><b>' + esc(f.name) + '</b></td><td class="muted">' + esc(f.code || '') + '</td><td>' + esc(f.module || '') + '</td><td class="muted">' + ((f.fields || []).map(function (x) { return x.label; }).join(', ')) + '</td>' +
          '<td style="white-space:nowrap;"><button class="act" data-edit="' + f.id + '">Изменить</button><button class="act danger" data-del="' + f.id + '">Удалить</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Форм нет.</span>';
      $$('#forms [data-edit]').forEach(function (b) { b.addEventListener('click', function () { formForm(forms.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
      $$('#forms [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить форму?')) return; rpc('app_form_def_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadForms(); }); }); });
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function formForm(f) {
    f = f || {};
    ui.formDialog({
      title: f.id ? 'Форма' : 'Новая форма', okText: 'Сохранить', size: 'lg', fields: [
        { name: 'code', label: 'Код', type: 'text' }, { name: 'name', label: 'Название', type: 'text', required: true },
        { name: 'module', label: 'Модуль', type: 'text', placeholder: 'orders' },
        { name: 'fields', label: 'Поля (JSON)', type: 'textarea', rows: 5, hint: '[{"key":"reason","label":"Причина","type":"text","required":true}]' }
      ],
      values: { code: f.code || '', name: f.name || '', module: f.module || '', fields: JSON.stringify(f.fields || [{ key: 'field1', label: 'Поле 1', type: 'text' }], null, 2) }
    }).then(function (v) {
      if (!v) return;
      var flds; try { flds = JSON.parse(v.fields || '[]'); } catch (e) { msg('#fMsg', 'Некорректный JSON полей', 'err'); return; }
      rpc('app_form_def_save', { p_token: token, p_id: f.id || null, p_code: v.code || null, p_name: v.name, p_module: v.module || null, p_fields: flds })
        .then(function (x) { var q = x && x[0]; msg('#fMsg', q ? q.message : '', q && q.ok ? 'ok' : 'err'); loadForms(); });
    });
  }

  $('#newDef').addEventListener('click', function () { defForm(null); });
  $('#myBtn').addEventListener('click', loadMy);
  $('#instBtn').addEventListener('click', loadInst);
  $('#iStatus').addEventListener('change', loadInst);
  $('#newRule').addEventListener('click', function () { ruleForm(null); });
  $('#newForm').addEventListener('click', function () { formForm(null); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#dMsg', 'Supabase не подключён.', 'err'); return; }
    loadDefs();
  });
})();
