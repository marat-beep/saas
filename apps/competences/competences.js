/* ============================================================
   3DMP Service · apps/competences — компетенции и обучение (Партия J).
   Данные: 0110 (app_skills_list/app_skill_save/app_skill_delete/
   app_competence_matrix/app_staff_skill_set/app_training_plan_*).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null, skills = [], matrix = [];

  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function maxOf(code) { var s = skills.filter(function (x) { return x.code === code; })[0]; return s ? (s.max_level || 5) : 5; }

  function loadSkills() {
    return rpc('app_skills_list', { p_token: token, p_q: null }).then(function (r) {
      skills = r || [];
      $('#skList').innerHTML = skills.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Код</th><th>Навык</th><th>Категория</th><th class="num">Макс.</th><th class="num">Сотрудников</th><th></th></tr></thead><tbody>' +
        skills.map(function (s) {
          return '<tr><td>' + esc(s.code) + '</td><td>' + esc(s.name) + '</td><td class="muted">' + esc(s.category || '') + '</td>' +
            '<td class="num">' + s.max_level + '</td><td class="num">' + s.staff + '</td>' +
            '<td><button class="btn secondary" data-del="' + s.id + '" style="width:auto;padding:5px 10px;">Удалить</button></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Навыков нет.</span>';
      ui.qsa('#skList [data-del]').forEach(function (b) {
        b.addEventListener('click', function () {
          rpc('app_skill_delete', { p_token: token, p_id: b.dataset.del }).then(function (r) { var x = r && r[0]; msg('#skMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadSkills().then(loadMatrix); }).catch(function (e) { msg('#skMsg', 'Ошибка: ' + e.message, 'err'); });
        });
      });
      $('#tpSkill').innerHTML = '<option value="">— навык —</option>' + skills.map(function (s) { return '<option value="' + s.id + '">' + esc(s.name) + '</option>'; }).join('');
    });
  }

  function loadMatrix() {
    return rpc('app_competence_matrix', { p_token: token }).then(function (r) {
      matrix = r || [];
      if (!matrix.length) { $('#mxList').innerHTML = '<span class="note">Сотрудников нет.</span>'; return; }
      var head = '<tr><th>Сотрудник</th><th>Подразделение</th>' + skills.map(function (s) { return '<th title="' + esc(s.name) + '">' + esc(s.code) + '</th>'; }).join('') + '</tr>';
      var rows = matrix.map(function (e) {
        return '<tr><td>' + esc(e.full_name || '') + '</td><td class="muted">' + esc(e.dept || '') + '</td>' +
          skills.map(function (s) {
            var lv = (e.levels && e.levels[s.code]) || 0, mx = s.max_level || 5, opts = '';
            for (var i = 0; i <= mx; i++) opts += '<option value="' + i + '"' + (i === lv ? ' selected' : '') + '>' + i + '</option>';
            return '<td><select data-emp="' + e.employee_id + '" data-skill="' + s.id + '" style="padding:4px 6px;border:1px solid var(--border);border-radius:8px;">' + opts + '</select></td>';
          }).join('') + '</tr>';
      }).join('');
      $('#mxList').innerHTML = '<div class="tbl-wrap"><table class="tbl"><thead>' + head + '</thead><tbody>' + rows + '</tbody></table></div>';
      ui.qsa('#mxList select').forEach(function (sel) {
        sel.addEventListener('change', function () {
          rpc('app_staff_skill_set', { p_token: token, p_employee_id: sel.dataset.emp, p_skill_id: sel.dataset.skill, p_level: parseInt(sel.value, 10) })
            .then(function (r) { var x = r && r[0]; msg('#mxMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); })
            .catch(function (e) { msg('#mxMsg', 'Ошибка: ' + e.message, 'err'); });
        });
      });
      $('#tpEmp').innerHTML = '<option value="">— сотрудник —</option>' + matrix.map(function (e) { return '<option value="' + e.employee_id + '">' + esc(e.full_name || '') + (e.dept ? ' · ' + esc(e.dept) : '') + '</option>'; }).join('');
      var filled = 0, levels = 0;
      matrix.forEach(function (e) { var n = Object.keys(e.levels || {}).length; if (n) filled++; levels += n; });
      $('#kpis').innerHTML = cell('Навыков', skills.length) + cell('Сотрудников', matrix.length) + cell('С уровнями', filled) + cell('Оценок', levels);
    });
  }

  function loadPlan() {
    return rpc('app_training_plan_list', { p_token: token }).then(function (r) {
      var a = r || [];
      var st = { planned: 'Запланировано', in_progress: 'В работе', done: 'Выполнено' };
      $('#tpList').innerHTML = a.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Сотрудник</th><th>Навык</th><th class="num">Цель</th><th>Статус</th><th>Срок</th><th>Примечание</th></tr></thead><tbody>' +
        a.map(function (t) {
          return '<tr><td>' + esc(t.employee || '') + '</td><td>' + esc(t.skill || '') + '</td><td class="num">' + (t.target_level != null ? t.target_level : '—') + '</td>' +
            '<td><span class="badge">' + esc(st[t.status] || t.status) + '</span></td><td class="muted">' + (t.due_date || '—') + '</td><td class="muted">' + esc(t.note || '') + '</td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">План обучения пуст.</span>';
    });
  }

  /* ---------- события ---------- */
  $('#skSave').addEventListener('click', function () {
    rpc('app_skill_save', { p_token: token, p_id: null, p_code: $('#skCode').value, p_name: $('#skName').value, p_category: $('#skCat').value, p_max_level: parseInt($('#skMax').value, 10) || 5, p_active: true })
      .then(function (r) { var x = r && r[0]; msg('#skMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) { $('#skCode').value = ''; $('#skName').value = ''; $('#skCat').value = ''; loadSkills().then(loadMatrix); } })
      .catch(function (e) { msg('#skMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#tpSave').addEventListener('click', function () {
    if (!$('#tpEmp').value) { msg('#tpMsg', 'Выберите сотрудника', 'err'); return; }
    rpc('app_training_plan_save', { p_token: token, p_id: null, p_employee_id: $('#tpEmp').value, p_skill_id: $('#tpSkill').value || null, p_target_level: parseInt($('#tpLevel').value, 10) || null, p_status: $('#tpStatus').value, p_due_date: $('#tpDue').value || null, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#tpMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) { window.Auth.log('План обучения', $('#tpEmp').value); loadPlan(); } })
      .catch(function (e) { msg('#tpMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#skMsg', 'Supabase не подключён.', 'err'); return; }
    loadSkills().then(loadMatrix).then(loadPlan);
  });
  function _esc(v){ return ui.esc(v); }
  $('#profBtn').addEventListener('click', function () {
    rpc('app_job_profile_list', { p_token: token }).then(function (rows) {
      rows = rows || [];
      var html = '<div class="toolbar"><button class="btn" id="pNew" style="width:auto;padding:8px 14px;">＋ Профиль должности</button></div><div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Должность</th><th>Требования</th></tr></thead><tbody>' +
        (rows.length ? rows.map(function (p) { return '<tr><td><b>' + _esc(p.title) + '</b></td><td>' + (p.requirements || []).map(function (r) { return _esc(r.code) + ':' + r.level; }).join(', ') + '</td></tr>'; }).join('') : '<tr><td colspan="2" class="note">Нет профилей</td></tr>') + '</tbody></table></div>';
      ui.dialog({ title: 'Профили должностей', body: html, html: true, cancelText: 'Закрыть', onOpen: function (back) {
        back.querySelector('#pNew').addEventListener('click', function () {
          ui.formDialog({ title: 'Профиль должности', okText: 'Сохранить', fields: [
            { name: 'title', label: 'Должность', type: 'text', required: true },
            { name: 'dept', label: 'Подразделение', type: 'text' },
            { name: 'reqs', label: 'Требования JSON [{code,level}]', type: 'textarea', rows: 2, value: '[{"code":"cnc","level":4}]' }
          ] }).then(function (v) { if (!v) return; var req; try { req = JSON.parse(v.reqs || '[]'); } catch (e) { ui.toast('Некорректный JSON'); return; }
            rpc('app_job_profile_save', { p_token: token, p_id: null, p_title: v.title, p_dept: v.dept, p_role: null, p_requirements: req }).then(function (r) { var x = r && r[0]; ui.toast((x && x.message) || '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) back.querySelector('[data-cancel]').click(); }); });
        });
      } });
    });
  });
  $('#gapBtn').addEventListener('click', function () {
    rpc('app_skill_gap_scan', { p_token: token }).then(function (rows) {
      rows = rows || [];
      var html = '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Сотрудник</th><th>Профиль</th><th>Навык</th><th class="num">Треб.</th><th class="num">Факт</th><th class="num">Дефицит</th></tr></thead><tbody>' +
        (rows.length ? rows.map(function (g) { return '<tr><td>' + _esc(g.full_name) + '</td><td>' + _esc(g.profile_title) + '</td><td>' + _esc(g.skill_name) + '</td><td class="num">' + g.required + '</td><td class="num">' + g.actual + '</td><td class="num"><b>' + g.gap + '</b></td></tr>'; }).join('') : '<tr><td colspan="6" class="note">Дефицита нет</td></tr>') + '</tbody></table></div>';
      ui.dialog({ title: 'Дефицит навыков', body: html, html: true, cancelText: 'Закрыть' });
    });
  });
  $('#certBtn').addEventListener('click', function () {
    rpc('app_cert_list', { p_token: token, p_employee_id: null }).then(function (rows) {
      rows = rows || [];
      var html = '<div class="toolbar"><button class="btn secondary" id="cScan" style="width:auto;padding:8px 14px;">🔔 Проверить сроки</button></div><div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Сотрудник</th><th>Сертификат</th><th>Действует до</th><th class="num">Дней</th></tr></thead><tbody>' +
        (rows.length ? rows.map(function (c) { return '<tr><td>' + _esc(c.employee || '') + '</td><td>' + _esc(c.name) + '</td><td>' + (c.expires_at || '') + '</td><td class="num">' + (c.days_left == null ? '—' : c.days_left) + '</td></tr>'; }).join('') : '<tr><td colspan="4" class="note">Нет сертификатов</td></tr>') + '</tbody></table></div>';
      ui.dialog({ title: 'Сертификаты', body: html, html: true, cancelText: 'Закрыть', onOpen: function (back) {
        var s = back.querySelector('#cScan'); if (s) s.addEventListener('click', function () { rpc('app_cert_scan', { p_token: token, p_days: 30 }).then(function (r) { var x = r && r[0]; ui.toast((x && x.message) || '', 'ok'); }); });
      } });
    });
  });
})();