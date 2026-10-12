/* ============================================================
   3DMP · assets/js/setup-wizard.js — мастер настройки как ОТДЕЛЬНАЯ процедура.
   window.AppSetupWizard.open(token, opts) / .start() — запуск из любого места.
   Быстрое создание справочников прямо в шагах. Требует ui.js + wizard.js.
   ============================================================ */
(function (g) {
  'use strict';
  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }
  function toast(t, k) { if (g.AppUI && g.AppUI.toast) g.AppUI.toast(t, k); }
  function rpc(n, a) { return g.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function open(token, opts) {
    opts = opts || {};
    if (!g.AppWizard) { toast('Мастер недоступен (нет wizard.js)'); return; }
    var done = [];
    function mark(key) { done.push(key); return rpc('app_setup_step_set', { p_token: token, p_key: key, p_status: 'done', p_note: null }).catch(function () {}); }

    var steps = [
      { key: 'org', title: '1. Организация', hint: 'Проверьте профиль предприятия, реквизиты и тариф.',
        html: function () { return '<a class="btn secondary" href="../org/index.html">Организации ↗</a> <a class="btn secondary" href="../billing/index.html">Тариф ↗</a>'; } },

      { key: 'departments', title: '2. Подразделения', hint: 'Создайте структуру цехов/отделов — можно прямо здесь.',
        html: function (d) { return '<div class="field"><label>Название</label><input name="dep_name" placeholder="Механообработка"></div>' +
          '<div class="field"><label>Код</label><input name="dep_code" placeholder="MECH"></div>' +
          '<div style="display:flex;gap:10px;align-items:center;"><button type="button" class="btn" data-add="dep" style="width:auto;padding:8px 14px;">＋ Добавить</button><span class="note" data-cnt="dep">добавлено: ' + (d._dep || 0) + '</span></div>'; },
        onShow: function (body, draft) {
          body.querySelector('[data-add="dep"]').addEventListener('click', function () {
            var n = body.querySelector('[name="dep_name"]').value.trim(); if (!n) { toast('Укажите название'); return; }
            rpc('app_department_save', { p_token: token, p_id: null, p_parent_id: null, p_name: n, p_code: body.querySelector('[name="dep_code"]').value || null, p_head: null, p_note: null, p_active: true })
              .then(function () { draft._dep = (draft._dep || 0) + 1; body.querySelector('[data-cnt="dep"]').textContent = 'добавлено: ' + draft._dep; body.querySelector('[name="dep_name"]').value = ''; toast('Подразделение добавлено'); })
              .catch(function (e) { toast('Ошибка: ' + e.message); });
          });
        } },

      { key: 'users', title: '3. Пользователи и роли', hint: 'Создайте пользователей и настройте права (матрица ролей).',
        html: function (d) { return '<div class="grid2c"><div class="field"><label>Логин</label><input name="u_login" placeholder="ivanov"></div>' +
          '<div class="field"><label>Пароль</label><input name="u_pass" type="text" placeholder="••••"></div></div>' +
          '<div class="grid2c"><div class="field"><label>ФИО</label><input name="u_name" placeholder="Иванов И.И."></div>' +
          '<div class="field"><label>Роль</label><select name="u_role"><option value="manager">manager</option><option value="owner">owner</option><option value="master">master</option><option value="qc">qc</option><option value="supply">supply</option><option value="supplier">supplier</option><option value="client">client</option><option value="dealer">dealer</option></select></div></div>' +
          '<div style="display:flex;gap:10px;align-items:center;"><button type="button" class="btn" data-add="user" style="width:auto;padding:8px 14px;">＋ Создать пользователя</button><span class="note" data-cnt="user">создано: ' + (d._user || 0) + '</span> <a class="btn secondary" href="../roles/index.html" style="width:auto;padding:8px 14px;">Матрица ролей ↗</a></div>'; },
        onShow: function (body, draft) {
          body.querySelector('[data-add="user"]').addEventListener('click', function () {
            var lg = body.querySelector('[name="u_login"]').value.trim(), pw = body.querySelector('[name="u_pass"]').value;
            if (!lg || !pw) { toast('Укажите логин и пароль'); return; }
            rpc('app_tenant_user_create', { p_token: token, p_login: lg, p_password: pw, p_full_name: body.querySelector('[name="u_name"]').value || null, p_role: body.querySelector('[name="u_role"]').value })
              .then(function (r) { var x = r && r[0]; if (x && x.ok === false) { toast(x.message || 'Ошибка'); return; } draft._user = (draft._user || 0) + 1; body.querySelector('[data-cnt="user"]').textContent = 'создано: ' + draft._user; body.querySelector('[name="u_login"]').value = ''; body.querySelector('[name="u_pass"]').value = ''; toast('Пользователь создан'); })
              .catch(function (e) { toast('Ошибка: ' + e.message); });
          });
        } },

      { key: 'refs', title: '4. Справочники', hint: 'Добавьте ключевые справочники — можно прямо здесь.',
        html: function (d) {
          return '<h4 style="margin:6px 0;">Заказчик</h4><div style="display:flex;gap:8px;"><input name="c_name" placeholder="ООО «Ромашка»" style="flex:1;padding:8px;border:1px solid var(--border);border-radius:9px;"><button type="button" class="btn" data-add="cust" style="width:auto;padding:8px 12px;">＋</button></div>' +
            '<h4 style="margin:10px 0 6px;">Поставщик</h4><div style="display:flex;gap:8px;"><input name="s_name" placeholder="ООО «Металл»" style="flex:1;padding:8px;border:1px solid var(--border);border-radius:9px;"><button type="button" class="btn" data-add="sup" style="width:auto;padding:8px 12px;">＋</button></div>' +
            '<h4 style="margin:10px 0 6px;">Материал</h4><div style="display:flex;gap:8px;"><input name="m_code" placeholder="M-001" style="width:110px;padding:8px;border:1px solid var(--border);border-radius:9px;"><input name="m_name" placeholder="Сталь 45" style="flex:1;padding:8px;border:1px solid var(--border);border-radius:9px;"><input name="m_unit" placeholder="кг" style="width:70px;padding:8px;border:1px solid var(--border);border-radius:9px;"><button type="button" class="btn" data-add="mat" style="width:auto;padding:8px 12px;">＋</button></div>' +
            '<h4 style="margin:10px 0 6px;">Оборудование</h4><div style="display:flex;gap:8px;"><input name="e_name" placeholder="Фрезерный ОЦ" style="flex:1;padding:8px;border:1px solid var(--border);border-radius:9px;"><button type="button" class="btn" data-add="eq" style="width:auto;padding:8px 12px;">＋</button></div>' +
            '<div class="note" data-cnt="refs" style="margin-top:8px;">добавлено: ' + (d._refs || 0) + '</div>'; },
        onShow: function (body, draft) {
          function bump() { draft._refs = (draft._refs || 0) + 1; body.querySelector('[data-cnt="refs"]').textContent = 'добавлено: ' + draft._refs; }
          body.querySelector('[data-add="cust"]').addEventListener('click', function () { var n = body.querySelector('[name="c_name"]').value.trim(); if (!n) return; rpc('app_customer_save', { p_token: token, p_id: null, p_name: n, p_inn: null, p_contact_person: null, p_phone: null, p_email: null, p_address: null, p_note: null }).then(function () { bump(); body.querySelector('[name="c_name"]').value = ''; toast('Заказчик добавлен'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); });
          body.querySelector('[data-add="sup"]').addEventListener('click', function () { var n = body.querySelector('[name="s_name"]').value.trim(); if (!n) return; rpc('app_suppliers_save', { p_token: token, p_id: null, p_name: n, p_inn: null, p_contact: null, p_phone: null, p_email: null, p_category: null, p_rating: null, p_note: null }).then(function () { bump(); body.querySelector('[name="s_name"]').value = ''; toast('Поставщик добавлен'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); });
          body.querySelector('[data-add="mat"]').addEventListener('click', function () { var c = body.querySelector('[name="m_code"]').value.trim(), n = body.querySelector('[name="m_name"]').value.trim(); if (!c || !n) { toast('Код и наименование'); return; } rpc('app_material_save', { p_token: token, p_id: null, p_code: c, p_name: n, p_unit: body.querySelector('[name="m_unit"]').value || 'шт', p_price: null, p_min_qty: null }).then(function () { bump(); body.querySelector('[name="m_code"]').value = ''; body.querySelector('[name="m_name"]').value = ''; toast('Материал добавлен'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); });
          body.querySelector('[data-add="eq"]').addEventListener('click', function () { var n = body.querySelector('[name="e_name"]').value.trim(); if (!n) return; rpc('app_equipment_save', { p_token: token, p_id: null, p_name: n, p_brand: null, p_category: null, p_axes: null, p_accuracy: null, p_price: null, p_description: null, p_active: true }).then(function () { bump(); body.querySelector('[name="e_name"]').value = ''; toast('Оборудование добавлено'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); });
        } },

      { key: 'modules', title: '5. Включение модулей', hint: 'Включите/отключите модули организации.',
        html: function () { return '<div id="wzMods"><span class="note">Загрузка…</span></div>'; },
        onShow: function (body) {
          var box = body.querySelector('#wzMods');
          rpc('app_tenant_modules_list', { p_token: token }).then(function (rows) {
            rows = rows || [];
            if (!rows.length) { box.innerHTML = '<span class="note">Нет данных.</span>'; return; }
            box.innerHTML = rows.map(function (m) { var on = m.enabled !== false; return '<div class="kvr"><b>' + esc(m.module) + '</b><span class="m"><label><input type="checkbox" data-mod="' + esc(m.module) + '"' + (on ? ' checked' : '') + '> включён</label></span></div>'; }).join('');
            box.querySelectorAll('[data-mod]').forEach(function (ch) { ch.addEventListener('change', function () { rpc('app_tenant_module_set', { p_token: token, p_module: ch.dataset.mod, p_enabled: ch.checked }).then(function () { toast('Обновлено'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); }); });
          }).catch(function (e) { box.innerHTML = '<span class="note">' + esc(e.message) + '</span>'; });
        } },

      { key: 'demo', title: '6. Демо-данные', hint: 'При желании загрузите демо-данные (удаляются отдельно, только строки с флагом is_demo).',
        html: function (d) { return '<label><input type="checkbox" name="load_demo"' + (d.load_demo ? ' checked' : '') + '> Загрузить демо-данные по всем модулям</label>'; } }
    ];

    g.AppWizard.open({
      id: 'setup', title: 'Мастер настройки', icon: '🚀', submitText: 'Завершить',
      steps: steps,
      onSubmit: function (draft) {
        var chain = Promise.resolve();
        steps.forEach(function (s) { chain = chain.then(function () { return mark(s.key); }); });
        if (draft.load_demo) chain = chain.then(function () { return rpc('app_demo_seed', { p_token: token, p_module: 'all' }).catch(function () {}); });
        return chain.then(function () { toast('Мастер завершён'); if (opts.onDone) opts.onDone(); })
          .then(function () { return null; }, function (e) { return 'Ошибка: ' + e.message; });
      }
    });
  }

  function start(opts) {
    var token = (g.Auth && g.Auth.token) ? g.Auth.token() : null;
    if (!token) { toast('Требуется вход'); return; }
    open(token, opts);
  }

  g.AppSetupWizard = { open: open, start: start };
})(window);
