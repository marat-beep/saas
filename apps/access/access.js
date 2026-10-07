/* ============================================================
   3DMP Service · apps/access — Enterprise-права и аудит (W10, 0155).
   Наборы прав, делегирование, маршруты согласований, расширенный аудит.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, isAdmin = false;
  var sets = [], dels = [], routes = [], reqs = [], myAppr = [], pols = [], users = [];
  var ROLES = ['admin', 'owner', 'manager', 'director', 'chief', 'master', 'technologist', 'operator', 'supply', 'qc', 'economist', 'support', 'supplier', 'client'];

  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function msg(id, t, k) { var e = $(id); if (!e) return; e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function dt(v) { return v ? new Date(v).toLocaleString('ru-RU') : '—'; }
  function userOpts(sel) { return users.map(function (u) { return { value: u.id, label: (u.login + (u.full_name ? ' · ' + u.full_name : '') + ' [' + (u.role || '') + ']') }; }).concat(sel ? [] : []); }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'deleg' && !dels.length) loadDels();
    if (scr === 'approve') { loadRoutes(); loadReqs(); loadMy(); }
    if (scr === 'audit') { loadPolicies(); loadAudit(); }
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  /* ---------- Наборы прав ---------- */
  function loadSets() {
    return Promise.all([
      rpc('app_perm_sets_list', { p_token: token }),
      rpc('app_effective_perms', { p_token: token }).catch(function () { return []; }),
      rpc('app_audit_kpi', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      sets = r[0] || []; renderSets();
      var eff = r[1] || []; renderEff(eff);
      var k = (r[2] && r[2][0]) || {};
      $('#kpis').innerHTML = cell('Наборов прав', sets.length) + cell('Эфф. разрешений', eff.length) + cell('Событий аудита', k.events || 0) + cell('Аудитов сегодня', k.today || 0);
    }).catch(function (e) { msg('#sMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderSets() {
    $('#sets').innerHTML = sets.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Название</th><th>Модули</th><th class="num">Назначений</th><th>Действия</th></tr></thead><tbody>' +
      sets.map(function (s) {
        var mods = Object.keys(s.perms || {});
        return '<tr><td><b>' + esc(s.name) + '</b>' + (s.description ? '<div class="note">' + esc(s.description) + '</div>' : '') + '</td>' +
          '<td class="muted">' + (mods.length ? esc(mods.join(', ')) : '—') + '</td><td class="num">' + (s.assign_count || 0) + '</td>' +
          '<td style="white-space:nowrap;"><button class="act" data-assign="' + s.id + '">Назначения</button><button class="act" data-edit="' + s.id + '">Изменить</button><button class="act danger" data-del="' + s.id + '">Удалить</button></td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Наборов нет.</span>';
    $$('#sets [data-edit]').forEach(function (b) { b.addEventListener('click', function () { openSet(sets.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
    $$('#sets [data-assign]').forEach(function (b) { b.addEventListener('click', function () { openAssign(sets.filter(function (x) { return x.id === b.dataset.assign; })[0]); }); });
    $$('#sets [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить набор?')) return; rpc('app_perm_set_delete', { p_token: token, p_id: b.dataset.del }).then(function (r) { var x = r && r[0]; msg('#sMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadSets(); }); }); });
  }
  function renderEff(eff) {
    if (!eff.length) { $('#eff').innerHTML = '<span class="note">Нет данных.</span>'; return; }
    $('#eff').innerHTML = '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Модуль</th><th>Источник</th><th>Просмотр</th><th>Правка</th></tr></thead><tbody>' +
      eff.map(function (p) { return '<tr><td>' + esc(p.module) + '</td><td class="muted">' + esc(p.source) + '</td><td>' + (p.can_view ? '✓' : '—') + '</td><td>' + (p.can_edit ? '✓' : '—') + '</td></tr>'; }).join('') + '</tbody></table></div>';
  }
  function openSet(s) {
    s = s || {};
    ui.formDialog({
      title: s.id ? 'Набор прав' : 'Новый набор', okText: 'Сохранить', size: 'lg', fields: [
        { name: 'name', label: 'Название', type: 'text', required: true },
        { name: 'description', label: 'Описание', type: 'text' },
        { name: 'perms', label: 'Права (JSON)', type: 'textarea', rows: 6, hint: 'Формат: {"orders":{"view":true,"edit":false},"production":{"view":true,"edit":true}}' }
      ],
      values: { name: s.name || '', description: s.description || '', perms: JSON.stringify(s.perms || { orders: { view: true, edit: false } }, null, 2) }
    }).then(function (v) {
      if (!v) return;
      var perms;
      try { perms = JSON.parse(v.perms || '{}'); } catch (e) { msg('#sMsg', 'Некорректный JSON прав', 'err'); return; }
      rpc('app_perm_set_save', { p_token: token, p_id: s.id || null, p_name: v.name, p_description: v.description || null, p_perms: perms })
        .then(function (r) { var x = r && r[0]; msg('#sMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadSets(); });
    });
  }
  function openAssign(s) {
    rpc('app_perm_assign_list', { p_token: token, p_set_id: s.id }).then(function (list) {
      var rows = (list || []).map(function (a) {
        return '<tr><td>' + esc(a.target_type) + '</td><td>' + esc(a.target_name || a.target_ref) + '</td><td>' + (a.active ? 'да' : 'нет') + '</td>' +
          '<td><button class="act danger" data-ad="' + a.id + '">Удалить</button></td></tr>';
      }).join('');
      var html = '<div class="note">Набор: <b>' + esc(s.name) + '</b></div>' +
        '<div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Тип</th><th>Получатель</th><th>Активно</th><th></th></tr></thead><tbody>' + (rows || '<tr><td colspan="4" class="note">Нет назначений</td></tr>') + '</tbody></table></div>' +
        '<div class="form-grid mt">' +
          '<div class="field"><label>Тип</label><select id="as_type"><option value="role">Роль</option><option value="user">Пользователь</option><option value="department">Подразделение</option></select></div>' +
          '<div class="field"><label>Получатель (роль / id пользователя / id подразделения)</label><input id="as_ref" placeholder="operator"></div>' +
        '</div>';
      ui.dialog({
        title: 'Назначения набора', body: html, html: true, okText: 'Добавить', cancelText: 'Закрыть',
        onOpen: function (back) { back.querySelectorAll('[data-ad]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_perm_assign_delete', { p_token: token, p_id: b.dataset.ad }).then(function () { back.querySelector('[data-ok]').click(); }); }); }); }
      }).then(function (ok) {
        if (!ok) return;
        var type = $('#as_type'), ref = $('#as_ref');
        if (!type || !ref || !ref.value.trim()) return;
        rpc('app_perm_assign_save', { p_token: token, p_set_id: s.id, p_target_type: type.value, p_target_ref: ref.value.trim(), p_active: true })
          .then(function (r) { var x = r && r[0]; msg('#sMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadSets(); });
      });
    });
  }

  /* ---------- Делегирование ---------- */
  function loadDels() {
    return rpc('app_delegations_list', { p_token: token }).then(function (r) { dels = r || []; renderDels(); })
      .catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderDels() {
    $('#dels').innerHTML = dels.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>От</th><th>Кому</th><th>Модуль</th><th>Действие</th><th>Период</th><th>Активно</th><th></th></tr></thead><tbody>' +
      dels.map(function (d) {
        return '<tr><td>' + esc(d.from_login || '—') + '</td><td><b>' + esc(d.to_login || '—') + '</b></td><td>' + esc(d.module || '—') + '</td><td>' + esc(d.action || 'любое') + '</td>' +
          '<td class="muted">' + (d.from_date || '—') + ' — ' + (d.to_date || '∞') + '</td><td>' + (d.active ? 'да' : 'нет') + '</td>' +
          '<td style="white-space:nowrap;"><button class="act" data-edit="' + d.id + '">Изменить</button><button class="act danger" data-del="' + d.id + '">Удалить</button></td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Делегирований нет.</span>';
    $$('#dels [data-edit]').forEach(function (b) { b.addEventListener('click', function () { openDel(dels.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
    $$('#dels [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить делегирование?')) return; rpc('app_delegation_delete', { p_token: token, p_id: b.dataset.del }).then(function (r) { var x = r && r[0]; msg('#dMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadDels(); }); }); });
  }
  function openDel(d) {
    d = d || {};
    ui.formDialog({
      title: d.id ? 'Делегирование' : 'Делегировать полномочия', okText: 'Сохранить', fields: [
        { name: 'to_user', label: 'Кому', type: 'select', options: userOpts(), required: true },
        { name: 'module', label: 'Модуль (пусто — все)', type: 'text', placeholder: 'orders' },
        { name: 'action', label: 'Действие', type: 'select', options: [{ value: '', label: 'Любое' }, { value: 'view', label: 'Просмотр' }, { value: 'edit', label: 'Правка' }] },
        { name: 'from_date', label: 'С даты', type: 'date' },
        { name: 'to_date', label: 'По дату', type: 'date' },
        { name: 'active', label: 'Активно', type: 'checkbox' },
        { name: 'note', label: 'Примечание', type: 'text' }
      ],
      values: { to_user: d.to_user_id || '', module: d.module || '', action: d.action || '', from_date: d.from_date || '', to_date: d.to_date || '', active: d.active === false ? '' : 'да', note: d.note || '' }
    }).then(function (v) {
      if (!v) return;
      rpc('app_delegation_save', { p_token: token, p_id: d.id || null, p_to_user: v.to_user, p_module: v.module || null, p_action: v.action || null, p_from_date: v.from_date || null, p_to_date: v.to_date || null, p_active: !!v.active, p_note: v.note || null })
        .then(function (r) { var x = r && r[0]; msg('#dMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadDels(); });
    });
  }

  /* ---------- Согласования ---------- */
  function loadRoutes() { return rpc('app_approval_routes_list', { p_token: token }).then(function (r) { routes = r || []; renderRoutes(); }); }
  function renderRoutes() {
    $('#routes').innerHTML = routes.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Маршрут</th><th>Тип</th><th>Шаги</th><th>Активен</th><th></th></tr></thead><tbody>' +
      routes.map(function (r) {
        var steps = (r.steps || []).map(function (s) { return '<span class="step-chip">' + esc(s.name || s.role || s.user_id || '') + '</span>'; }).join('');
        return '<tr><td><b>' + esc(r.name) + '</b></td><td>' + esc(r.doc_type || '—') + '</td><td>' + (steps || '—') + '</td><td>' + (r.active ? 'да' : 'нет') + '</td>' +
          '<td style="white-space:nowrap;"><button class="act" data-edit="' + r.id + '">Изменить</button><button class="act danger" data-del="' + r.id + '">Удалить</button></td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Маршрутов нет.</span>';
    $$('#routes [data-edit]').forEach(function (b) { b.addEventListener('click', function () { openRoute(routes.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
    $$('#routes [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить маршрут?')) return; rpc('app_approval_route_delete', { p_token: token, p_id: b.dataset.del }).then(function (r) { var x = r && r[0]; msg('#aMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadRoutes(); }); }); });
  }
  function openRoute(r) {
    r = r || {};
    ui.formDialog({
      title: r.id ? 'Маршрут' : 'Новый маршрут', okText: 'Сохранить', size: 'lg', fields: [
        { name: 'name', label: 'Название', type: 'text', required: true },
        { name: 'doc_type', label: 'Тип документа', type: 'select', options: [{ value: '', label: '—' }, { value: 'order', label: 'Заявка' }, { value: 'document', label: 'Документ' }, { value: 'invoice', label: 'Счёт' }, { value: 'tender', label: 'Закупка' }, { value: 'other', label: 'Прочее' }] },
        { name: 'steps', label: 'Шаги (JSON)', type: 'textarea', rows: 5, hint: '[{"ord":1,"role":"chief","name":"Начальник цеха"},{"ord":2,"role":"director","name":"Директор"}]' },
        { name: 'active', label: 'Активен', type: 'checkbox' }
      ],
      values: { name: r.name || '', doc_type: r.doc_type || '', steps: JSON.stringify(r.steps || [{ ord: 1, role: 'chief', name: 'Начальник цеха' }], null, 2), active: r.active === false ? '' : 'да' }
    }).then(function (v) {
      if (!v) return;
      var steps; try { steps = JSON.parse(v.steps || '[]'); } catch (e) { msg('#aMsg', 'Некорректный JSON шагов', 'err'); return; }
      rpc('app_approval_route_save', { p_token: token, p_id: r.id || null, p_name: v.name, p_doc_type: v.doc_type || null, p_steps: steps, p_active: !!v.active })
        .then(function (x) { var q = x && x[0]; msg('#aMsg', q ? q.message : '', q && q.ok ? 'ok' : 'err'); loadRoutes(); });
    });
  }
  function loadReqs() { return rpc('app_approval_requests_list', { p_token: token, p_status: null, p_limit: 100 }).then(function (r) { reqs = r || []; renderReqs(); }); }
  function statusBadge(s) { var m = { pending: ['На согласовании', ''], approved: ['Согласована', 'done'], rejected: ['Отклонена', 'cancelled'], cancelled: ['Отменена', 'cancelled'] }; var x = m[s] || [s, '']; return '<span class="badge ' + x[1] + '">' + esc(x[0]) + '</span>'; }
  function renderReqs() {
    $('#reqs').innerHTML = reqs.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Заявка</th><th>Маршрут</th><th>Шаг</th><th>Статус</th><th>Автор</th><th>Создана</th></tr></thead><tbody>' +
      reqs.map(function (r) { return '<tr><td>' + esc(r.entity_title || '—') + '</td><td>' + esc(r.route_name || '—') + '</td><td>' + r.current_step + '/' + r.total_steps + '</td><td>' + statusBadge(r.status) + '</td><td class="muted">' + esc(r.requested_login || '') + '</td><td class="muted">' + dt(r.created_at) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Заявок нет.</span>';
  }
  function loadMy() {
    return rpc('app_approval_my', { p_token: token }).then(function (r) {
      myAppr = r || [];
      $('#myAppr').innerHTML = myAppr.length ? myAppr.map(function (r) {
        return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;"><b>' + esc(r.entity_title || '—') + '</b>' +
          '<span class="note">шаг ' + r.current_step + '/' + r.total_steps + ' · ' + esc(r.step_name || '') + '</span></div>' +
          '<div class="toolbar mt"><button class="btn" data-ap="' + r.id + '" style="width:auto;padding:7px 12px;">Согласовать</button>' +
          '<button class="btn secondary" data-rj="' + r.id + '" style="width:auto;padding:7px 12px;">Отклонить</button></div></div>';
      }).join('') : '<span class="note">Нет заявок, ожидающих вашего решения.</span>';
      $$('#myAppr [data-ap]').forEach(function (b) { b.addEventListener('click', function () { act(b.dataset.ap, 'approve'); }); });
      $$('#myAppr [data-rj]').forEach(function (b) { b.addEventListener('click', function () { act(b.dataset.rj, 'reject'); }); });
    });
  }
  function act(id, action) {
    ui.formDialog({ title: action === 'approve' ? 'Согласовать' : 'Отклонить', okText: 'Подтвердить', fields: [{ name: 'comment', label: 'Комментарий', type: 'text' }], values: {} }).then(function (v) {
      if (v === null) return;
      rpc('app_approval_act', { p_token: token, p_request_id: id, p_action: action, p_comment: (v && v.comment) || null })
        .then(function (r) { var x = r && r[0]; msg('#aMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadMy(); loadReqs(); });
    });
  }
  function sendRequest() {
    if (!routes.length) { msg('#aMsg', 'Создайте маршрут.', 'err'); return; }
    ui.formDialog({
      title: 'Отправить на согласование', okText: 'Отправить', fields: [
        { name: 'route_id', label: 'Маршрут', type: 'select', options: routes.map(function (r) { return { value: r.id, label: r.name }; }), required: true },
        { name: 'entity_type', label: 'Тип объекта', type: 'text', placeholder: 'order' },
        { name: 'entity_title', label: 'Название/номер', type: 'text', required: true, placeholder: 'REQ-00001' }
      ], values: {}
    }).then(function (v) {
      if (!v) return;
      rpc('app_approval_request_create', { p_token: token, p_route_id: v.route_id, p_entity_type: v.entity_type || null, p_entity_id: null, p_entity_title: v.entity_title })
        .then(function (r) { var x = r && r[0]; msg('#aMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadMy(); loadReqs(); });
    });
  }

  /* ---------- Аудит ---------- */
  function loadPolicies() { return rpc('app_audit_policies_list', { p_token: token }).then(function (r) { pols = r || []; renderPols(); }); }
  function renderPols() {
    $('#pols').innerHTML = pols.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Область</th><th>Модуль</th><th>Действие</th><th>Мин. роль</th><th>Вкл.</th><th></th></tr></thead><tbody>' +
      pols.map(function (p) {
        var scope = p.scope_type === 'department' ? ('Подразделение: ' + (p.scope_name || p.scope_ref || '')) : (p.scope_type === 'module' ? 'Модуль' : 'Все');
        return '<tr><td>' + esc(scope) + '</td><td>' + esc(p.module || '—') + '</td><td>' + esc(p.action || '—') + '</td><td>' + esc(p.min_role || '—') + '</td><td>' + (p.enabled ? 'да' : 'нет') + '</td>' +
          '<td style="white-space:nowrap;"><button class="act" data-edit="' + p.id + '">Изменить</button><button class="act danger" data-del="' + p.id + '">Удалить</button></td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Политик нет.</span>';
    $$('#pols [data-edit]').forEach(function (b) { b.addEventListener('click', function () { openPolicy(pols.filter(function (x) { return x.id === b.dataset.edit; })[0]); }); });
    $$('#pols [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить политику?')) return; rpc('app_audit_policy_delete', { p_token: token, p_id: b.dataset.del }).then(function (r) { var x = r && r[0]; msg('#auMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadPolicies(); }); }); });
  }
  function openPolicy(p) {
    p = p || {};
    ui.formDialog({
      title: p.id ? 'Политика аудита' : 'Новая политика', okText: 'Сохранить', fields: [
        { name: 'scope_type', label: 'Область', type: 'select', options: [{ value: 'all', label: 'Все' }, { value: 'module', label: 'Модуль' }, { value: 'department', label: 'Подразделение' }] },
        { name: 'scope_ref', label: 'Ссылка области (id подразделения)', type: 'text' },
        { name: 'module', label: 'Модуль', type: 'text', placeholder: 'service' },
        { name: 'action', label: 'Действие', type: 'text', placeholder: 'edit' },
        { name: 'min_role', label: 'Мин. роль', type: 'text' },
        { name: 'enabled', label: 'Включена', type: 'checkbox' }
      ],
      values: { scope_type: p.scope_type || 'module', scope_ref: p.scope_ref || '', module: p.module || '', action: p.action || '', min_role: p.min_role || '', enabled: p.enabled === false ? '' : 'да' }
    }).then(function (v) {
      if (!v) return;
      rpc('app_audit_policy_save', { p_token: token, p_id: p.id || null, p_scope_type: v.scope_type, p_scope_ref: v.scope_ref || null, p_module: v.module || null, p_action: v.action || null, p_min_role: v.min_role || null, p_enabled: !!v.enabled })
        .then(function (r) { var x = r && r[0]; msg('#auMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadPolicies(); });
    });
  }
  function loadAudit() {
    return rpc('app_audit_ext_list', { p_token: token, p_module: $('#auQ').value || null, p_limit: 100 }).then(function (r) {
      var list = r || [];
      $('#auditLog').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Когда</th><th>Пользователь</th><th>Роль</th><th>Модуль</th><th>Действие</th><th>Объект</th><th>Детали</th></tr></thead><tbody>' +
        list.map(function (a) { return '<tr><td class="muted">' + dt(a.created_at) + '</td><td>' + esc(a.actor_login || '') + '</td><td>' + esc(a.actor_role || '') + '</td><td>' + esc(a.module || '') + '</td><td>' + esc(a.action || '') + '</td><td>' + esc(a.entity_type || '') + '</td><td class="muted">' + esc(JSON.stringify(a.detail || {})) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Записей нет.</span>';
    }).catch(function (e) { msg('#auMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Действия ---------- */
  $('#newSet').addEventListener('click', function () { openSet(null); });
  $('#newDel').addEventListener('click', function () { if (!users.length) { msg('#dMsg', 'Нет списка пользователей.', 'err'); return; } openDel(null); });
  $('#newRoute').addEventListener('click', function () { openRoute(null); });
  $('#newReq').addEventListener('click', sendRequest);
  $('#newPol').addEventListener('click', function () { openPolicy(null); });
  $('#auQ').addEventListener('input', loadAudit);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (['admin', 'owner', 'manager'].indexOf(s.role) < 0) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token; isAdmin = (s.role === 'admin');
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#sMsg', 'Supabase не подключён.', 'err'); return; }
    rpc('app_tenant_users', { p_token: token }).then(function (u) { users = u || []; }).catch(function () { users = []; }).then(loadSets);
  });
})();
