/* ============================================================
   3DMP · assets/js/setup-wizard.js — мастер настройки (отдельная процедура).
   window.AppSetupWizard.open(token, opts) / .start(opts).
   - Настройка ВСЕХ включённых модулей (параметры с пояснениями).
   - Быстрое создание справочников в шагах.
   - Scope: opts.module — перенастройка одного модуля.
   - Сохранение в app_tenant_settings; экспорт/импорт — в модуле «Мастер».
   Требует ui.js + wizard.js.
   ============================================================ */
(function (g) {
  'use strict';
  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }
  function toast(t, k) { if (g.AppUI && g.AppUI.toast) g.AppUI.toast(t, k); }
  function rpc(n, a) { return g.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  var SELF = document.currentScript, ROOT = '';
  try { var ss = (SELF && SELF.src) || ''; var ii = ss.indexOf('assets/js/setup-wizard.js'); if (ii >= 0) ROOT = ss.substring(0, ii); } catch (e) {}
  function catApp(id) { var a = (g.AppCatalog && g.AppCatalog.apps) || []; for (var i = 0; i < a.length; i++) { if (a[i].id === id) return a[i]; } return null; }
  /* W8: варианты ролей — из единого справочника Auth.ROLES */
  function roleOpts() {
    if (g.Auth && g.Auth.roleOptions) return g.Auth.roleOptions().map(function (o) { return '<option value="' + esc(o.value) + '">' + esc(o.label) + '</option>'; }).join('');
    return '<option value="manager">Менеджер</option>';
  }
  function ensureCatalog() {
    return new Promise(function (res) {
      if (g.AppCatalog && g.AppCatalog.apps) { res(); return; }
      if (document.getElementById('wzCatLd')) { var t = setInterval(function () { if (g.AppCatalog && g.AppCatalog.apps) { clearInterval(t); res(); } }, 80); return; }
      var s = document.createElement('script'); s.id = 'wzCatLd'; s.src = ROOT + 'assets/js/catalog.js?v=127'; s.onload = function () { res(); }; s.onerror = function () { res(); }; document.head.appendChild(s);
    });
  }

  /* Поля настройки по модулям: key/label/hint/type/options/def */
  var MODULE_FIELDS = {
    orders: { title: 'Заявки', fields: [
      { key: 'sla_days', label: 'Норматив реакции, дн', hint: 'Срок, после которого заявка помечается как просроченная.', type: 'number', def: 3 },
      { key: 'default_priority', label: 'Приоритет по умолчанию', hint: 'Присваивается новым заявкам.', type: 'select', options: ['low', 'normal', 'high'], def: 'normal' },
      { key: 'auto_kp', label: 'Авто-КП', hint: 'Предлагать создать КП при переходе заявки в стадию «КП».', type: 'checkbox', def: false }
    ] },
    production: { title: 'Производство', fields: [
      { key: 'shift_hours', label: 'Длина смены, ч', hint: 'Используется в графиках и нормировании.', type: 'number', def: 8 },
      { key: 'require_defect_cause', label: 'Требовать причину брака', hint: 'Запрещать фиксацию брака без причины.', type: 'checkbox', def: true },
      { key: 'ssz_auto', label: 'Авто-ССЗ', hint: 'Формировать сменно-суточное задание автоматически.', type: 'checkbox', def: false }
    ] },
    hr: { title: 'Кадры', fields: [
      { key: 'work_week_hours', label: 'Норма часов в неделю', hint: 'Нормальная продолжительность рабочей недели.', type: 'number', def: 40 },
      { key: 'vacation_days', label: 'Дней отпуска в год', hint: 'Плановая длительность ежегодного отпуска.', type: 'number', def: 28 }
    ] },
    warehouse: { title: 'Склад', fields: [
      { key: 'default_min_qty', label: 'Минимальный остаток', hint: 'Порог, ниже которого создаётся автозаявка.', type: 'number', def: 10 },
      { key: 'auto_reorder', label: 'Автозаявка на закупку', hint: 'Создавать черновик закупки при остатке ниже минимума.', type: 'checkbox', def: false }
    ] },
    procurement: { title: 'Закупки', fields: [
      { key: 'currency', label: 'Валюта', hint: 'Валюта цен и предложений.', type: 'text', def: 'RUB' },
      { key: 'price_weight', label: 'Вес цены, %', hint: 'Доля цены при авто-ранжировании КП (остальное — срок и рейтинг).', type: 'number', def: 60 }
    ] },
    qc: { title: 'ОТК/Качество', fields: [
      { key: 'spc_enabled', label: 'Контрольные карты (SPC)', hint: 'Вести статистическое управление процессом.', type: 'checkbox', def: true },
      { key: 'require_measure', label: 'Обязательные измерения', hint: 'Требовать измерения в чек-листах.', type: 'checkbox', def: false }
    ] },
    service: { title: 'Сервис', fields: [
      { key: 'sla_response_hours', label: 'Норматив отклика, ч', hint: 'SLA первой реакции на сервисную заявку.', type: 'number', def: 4 },
      { key: 'auto_ppr', label: 'Авто-заявки из ППР', hint: 'Создавать сервисные заявки из планов ТОиР.', type: 'checkbox', def: true }
    ] },
    finance: { title: 'Финансы', fields: [
      { key: 'vat', label: 'НДС, %', hint: 'Ставка НДС для счетов и документов.', type: 'number', def: 20 },
      { key: 'payment_term_days', label: 'Отсрочка платежа, дн', hint: 'Срок оплаты по умолчанию.', type: 'number', def: 14 }
    ] },
    maintenance: { title: 'ТОиР', fields: [
      { key: 'ppr_days', label: 'Периодичность ППР, дн', hint: 'Плановая периодичность обслуживания.', type: 'number', def: 30 },
      { key: 'predictive', label: 'Предиктив (вибрация)', hint: 'Учитывать телеметрию для авто-плана.', type: 'checkbox', def: false }
    ] },
    docs: { title: 'Документы', fields: [
      { key: 'number_prefix', label: 'Префикс нумерации', hint: 'Начало номера документов, напр. DOC-.', type: 'text', def: 'DOC-' },
      { key: 'require_sign', label: 'Требовать подпись', hint: 'Переводить документ в «подписан» только после подписи.', type: 'checkbox', def: false }
    ] },
    planning: { title: 'Планирование', fields: [
      { key: 'horizon_days', label: 'Горизонт, дн', hint: 'Глубина APS-расписания по умолчанию.', type: 'number', def: 14 },
      { key: 'default_capacity', label: 'Ёмкость РЦ, ч/день', hint: 'Ёмкость по умолчанию, если не задана.', type: 'number', def: 8 }
    ] },
    mes: { title: 'MES', fields: [
      { key: 'auto_refresh', label: 'Обновление в реальном времени', hint: 'Доска MES обновляется автоматически.', type: 'checkbox', def: true }
    ] },
    kedo: { title: 'КЭДО', fields: [
      { key: 'sign_method', label: 'Метод подписи', hint: 'По умолчанию: ПЭП/УНЭП/УКЭП/Госключ.', type: 'select', options: ['ПЭП', 'УНЭП', 'УКЭП', 'Госключ'], def: 'ПЭП' },
      { key: 'bulk_ack', label: 'Массовые ознакомления', hint: 'Разрешить рассылку ознакомлений списку.', type: 'checkbox', def: true }
    ] },
    edo: { title: 'ЭДО', fields: [
      { key: 'reg_prefix', label: 'Префикс регистрации', hint: 'Начало регистрационного номера.', type: 'text', def: 'ЭДО' },
      { key: 'operator', label: 'ЭДО-оператор', hint: 'Провайдер обмена (Диадок/СБИС).', type: 'text', def: '' }
    ] },
    crm: { title: 'CRM', fields: [
      { key: 'currency', label: 'Валюта', hint: 'Валюта сумм сделок.', type: 'text', def: 'RUB' },
      { key: 'funnel', label: 'Стадии воронки', hint: 'Через запятую.', type: 'text', def: 'lead,qualified,proposal,negotiation,won' }
    ] },
    safety: { title: 'Охрана труда', fields: [
      { key: 'briefing_days', label: 'Периодичность инструктажа, дн', hint: 'Срок повторного инструктажа.', type: 'number', def: 180 },
      { key: 'ppe_control', label: 'Контроль СИЗ', hint: 'Напоминать об истечении срока СИЗ.', type: 'checkbox', def: true }
    ] },
    competences: { title: 'Компетенции', fields: [
      { key: 'gap_target', label: 'Целевой уровень', hint: 'Целевой уровень навыка в профиле по умолчанию.', type: 'number', def: 4 }
    ] },
    equipment: { title: 'Оборудование', fields: [
      { key: 'verify_days', label: 'Периодичность поверки, дн', hint: 'Срок поверки СИ/оборудования.', type: 'number', def: 365 }
    ] },
    client: { title: 'Кабинет заказчика', fields: [
      { key: 'show_prices', label: 'Показывать цены', hint: 'Отображать суммы в кабинете заказчика.', type: 'checkbox', def: true },
      { key: 'allow_chat', label: 'Чат с менеджером', hint: 'Разрешить переписку клиент ↔ менеджер.', type: 'checkbox', def: true }
    ] },
    tooling: { title: 'Инструмент', fields: [
      { key: 'resharpen_limit', label: 'Предел переточек', hint: 'Число переточек до списания инструмента.', type: 'number', def: 3 }
    ] },
    oee: { title: 'OEE', fields: [
      { key: 'target_oee', label: 'Целевой OEE, %', hint: 'Норматив эффективности оборудования.', type: 'number', def: 85 }
    ] },
    iiot: { title: 'IIoT', fields: [
      { key: 'poll_seconds', label: 'Период опроса, с', hint: 'Частота сбора телеметрии.', type: 'number', def: 60 }
    ] },
    reports: { title: 'Отчёты', fields: [
      { key: 'default_period_days', label: 'Период по умолчанию, дн', hint: 'Глубина отчётов по умолчанию.', type: 'number', def: 30 }
    ] },
    tasks: { title: 'Задачи', fields: [
      { key: 'default_due_days', label: 'Срок задачи по умолчанию, дн', hint: 'Если срок не указан.', type: 'number', def: 3 }
    ] },
    mdm: { title: 'НСИ / Мастер-данные', fields: [
      { key: 'dup_threshold', label: 'Порог дублей, %', hint: 'Схожесть наименований для поиска дублей.', type: 'number', def: 90 }
    ] }
  };

  function fieldHtml(mod, f, val) {
    var name = 'set_' + mod + '__' + f.key;
    var v = (val === undefined || val === null) ? f.def : val;
    var hint = '<div class="note" style="font-size:.75rem;">' + esc(f.hint) + '</div>';
    if (f.type === 'checkbox') return '<div class="field">' + hint + '<label><input type="checkbox" name="' + name + '"' + (v ? ' checked' : '') + '> ' + esc(f.label) + '</label></div>';
    if (f.type === 'select') return '<div class="field"><label>' + esc(f.label) + '</label><select name="' + name + '">' + (f.options || []).map(function (o) { return '<option value="' + esc(o) + '"' + (String(o) === String(v) ? ' selected' : '') + '>' + esc(o) + '</option>'; }).join('') + '</select>' + hint + '</div>';
    return '<div class="field"><label>' + esc(f.label) + '</label><input name="' + name + '" type="' + (f.type === 'number' ? 'number' : 'text') + '" value="' + esc(v == null ? '' : v) + '">' + hint + '</div>';
  }

  function open(token, opts) {
    opts = opts || {};
    if (!g.AppWizard) { toast('Мастер недоступен (нет wizard.js)'); return; }

    ensureCatalog().then(function () { return Promise.all([
      rpc('app_tenant_modules_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_tenant_settings_get', { p_token: token, p_module: null }).catch(function () { return []; })
    ]); }).then(function (r) {
      var mods = r[0] || [], sets = r[1] || [];
      var enabledMap = {}; mods.forEach(function (m) { enabledMap[m.module] = m.enabled !== false; });
      var settingsMap = {}; sets.forEach(function (s) { settingsMap[s.module] = s.settings || {}; });

      var scope = (opts.module || '').toLowerCase();
      var moduleKeys = Object.keys(MODULE_FIELDS).filter(function (m) {
        if (scope) return m === scope;
        return enabledMap[m] !== false;   // включён или не задан → настраиваем
      });

      var steps = [
        { key: 'org', title: '1. Организация', hint: 'Профиль предприятия, реквизиты и тариф.',
          html: function () { return '<a class="btn secondary" href="../org/index.html">Организации ↗</a> <a class="btn secondary" href="../billing/index.html">Тариф ↗</a>'; } },
        { key: 'profile', title: '2. Профиль организации', hint: 'Автонабор модулей под тип предприятия. Применяется сразу (без отключения текущих).',
          html: function () { return '<div id="wzProf"><span class="note">Загрузка…</span></div>'; },
          onShow: function (body) {
            var box = body.querySelector('#wzProf');
            Promise.all([
              rpc('app_org_profiles_list', { p_token: token }).catch(function () { return []; }),
              rpc('app_org_profile_detect', { p_token: token }).catch(function () { return []; })
            ]).then(function (rr) {
              var ps = rr[0] || [], det = (rr[1] && rr[1][0]) || null;
              if (!ps.length) { box.innerHTML = '<span class="note">Профили недоступны.</span>'; return; }
              box.innerHTML = '<div class="field"><label>Профиль</label><select id="wzProfSel">' +
                ps.map(function (p) { return '<option value="' + esc(p.code) + '"' + (det && det.code === p.code ? ' selected' : '') + '>' + esc(p.name) + (det && det.code === p.code ? ' ★ текущий' : '') + '</option>'; }).join('') +
                '</select><div class="note">' + ps.map(function (p) { return esc(p.name) + ': ' + esc(p.description || ''); }).join('<br>') + '</div></div>' +
                '<div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;"><button type="button" class="btn" id="wzProfApply" style="width:auto;padding:8px 14px;">Применить профиль</button><span class="note" id="wzProfMsg">' + (det ? ('Текущий: ' + esc(det.name) + ' (' + det.match_pct + '%)') : '') + '</span></div>';
              box.querySelector('#wzProfApply').addEventListener('click', function () {
                var code = box.querySelector('#wzProfSel').value;
                rpc('app_org_profile_apply', { p_token: token, p_code: code, p_all: null }).then(function (r2) { var x = r2 && r2[0]; toast((x && x.message) || 'Профиль применён', x && x.ok ? 'ok' : 'err'); box.querySelector('#wzProfMsg').textContent = 'Применён: ' + code; }).catch(function (e) { toast('Ошибка: ' + e.message); });
              });
            }).catch(function (e) { box.innerHTML = '<span class="note">' + esc(e.message) + '</span>'; });
          } },
        { key: 'departments', title: '3. Подразделения', hint: 'Структура цехов/отделов — можно создать сразу.',
          html: function (d) { return '<div class="field"><label>Название</label><input name="dep_name" placeholder="Механообработка"></div><div class="field"><label>Код</label><input name="dep_code" placeholder="MECH"></div><div style="display:flex;gap:10px;align-items:center;"><button type="button" class="btn" data-add="dep" style="width:auto;padding:8px 14px;">＋ Добавить</button><span class="note" data-cnt="dep">добавлено: ' + (d._dep || 0) + '</span></div>'; },
          onShow: function (body, draft) { body.querySelector('[data-add="dep"]').addEventListener('click', function () { var n = body.querySelector('[name="dep_name"]').value.trim(); if (!n) { toast('Укажите название'); return; } rpc('app_department_save', { p_token: token, p_id: null, p_parent_id: null, p_name: n, p_code: body.querySelector('[name="dep_code"]').value || null, p_head: null, p_note: null, p_active: true }).then(function () { draft._dep = (draft._dep || 0) + 1; body.querySelector('[data-cnt="dep"]').textContent = 'добавлено: ' + draft._dep; body.querySelector('[name="dep_name"]').value = ''; toast('Подразделение добавлено'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); }); } },
        { key: 'users', title: '4. Пользователи и роли', hint: 'Создайте пользователей и настройте права.',
          html: function (d) { return '<div class="grid2c"><div class="field"><label>Логин</label><input name="u_login" placeholder="ivanov"></div><div class="field"><label>Пароль</label><input name="u_pass" type="text"></div></div><div class="grid2c"><div class="field"><label>ФИО</label><input name="u_name"></div><div class="field"><label>Роль</label><select name="u_role">' + roleOpts() + '</select></div></div><div style="display:flex;gap:10px;align-items:center;"><button type="button" class="btn" data-add="user" style="width:auto;padding:8px 14px;">＋ Создать</button><span class="note" data-cnt="user">создано: ' + (d._user || 0) + '</span> <a class="btn secondary" href="../roles/index.html" style="width:auto;padding:8px 14px;">Матрица ролей ↗</a></div>'; },
          onShow: function (body, draft) { body.querySelector('[data-add="user"]').addEventListener('click', function () { var lg = body.querySelector('[name="u_login"]').value.trim(), pw = body.querySelector('[name="u_pass"]').value; if (!lg || !pw) { toast('Укажите логин и пароль'); return; } rpc('app_tenant_user_create', { p_token: token, p_login: lg, p_password: pw, p_full_name: body.querySelector('[name="u_name"]').value || null, p_role: body.querySelector('[name="u_role"]').value }).then(function (r) { var x = r && r[0]; if (x && x.ok === false) { toast(x.message || 'Ошибка'); return; } draft._user = (draft._user || 0) + 1; body.querySelector('[data-cnt="user"]').textContent = 'создано: ' + draft._user; body.querySelector('[name="u_login"]').value = ''; body.querySelector('[name="u_pass"]').value = ''; toast('Пользователь создан'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); }); } },
        { key: 'refs', title: '5. Справочники', hint: 'Ключевые справочники — можно добавить сразу.',
          html: function (d) { return '<h4 style="margin:6px 0;">Заказчик</h4><div style="display:flex;gap:8px;"><input name="c_name" placeholder="ООО «Ромашка»" style="flex:1;padding:8px;border:1px solid var(--border);border-radius:9px;"><button type="button" class="btn" data-add="cust" style="width:auto;padding:8px 12px;">＋</button></div><h4 style="margin:10px 0 6px;">Поставщик</h4><div style="display:flex;gap:8px;"><input name="s_name" placeholder="ООО «Металл»" style="flex:1;padding:8px;border:1px solid var(--border);border-radius:9px;"><button type="button" class="btn" data-add="sup" style="width:auto;padding:8px 12px;">＋</button></div><h4 style="margin:10px 0 6px;">Материал</h4><div style="display:flex;gap:8px;"><input name="m_code" placeholder="M-001" style="width:110px;padding:8px;border:1px solid var(--border);border-radius:9px;"><input name="m_name" placeholder="Сталь 45" style="flex:1;padding:8px;border:1px solid var(--border);border-radius:9px;"><input name="m_unit" placeholder="кг" style="width:70px;padding:8px;border:1px solid var(--border);border-radius:9px;"><button type="button" class="btn" data-add="mat" style="width:auto;padding:8px 12px;">＋</button></div><h4 style="margin:10px 0 6px;">Оборудование</h4><div style="display:flex;gap:8px;"><input name="e_name" placeholder="Фрезерный ОЦ" style="flex:1;padding:8px;border:1px solid var(--border);border-radius:9px;"><button type="button" class="btn" data-add="eq" style="width:auto;padding:8px 12px;">＋</button></div><div class="note" data-cnt="refs" style="margin-top:8px;">добавлено: ' + (d._refs || 0) + '</div>'; },
          onShow: function (body, draft) { function bump() { draft._refs = (draft._refs || 0) + 1; body.querySelector('[data-cnt="refs"]').textContent = 'добавлено: ' + draft._refs; } body.querySelector('[data-add="cust"]').addEventListener('click', function () { var n = body.querySelector('[name="c_name"]').value.trim(); if (!n) return; rpc('app_customer_save', { p_token: token, p_id: null, p_name: n, p_inn: null, p_contact_person: null, p_phone: null, p_email: null, p_address: null, p_note: null }).then(function () { bump(); body.querySelector('[name="c_name"]').value = ''; toast('Заказчик добавлен'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); }); body.querySelector('[data-add="sup"]').addEventListener('click', function () { var n = body.querySelector('[name="s_name"]').value.trim(); if (!n) return; rpc('app_suppliers_save', { p_token: token, p_id: null, p_name: n, p_inn: null, p_contact: null, p_phone: null, p_email: null, p_category: null, p_rating: null, p_note: null }).then(function () { bump(); body.querySelector('[name="s_name"]').value = ''; toast('Поставщик добавлен'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); }); body.querySelector('[data-add="mat"]').addEventListener('click', function () { var c = body.querySelector('[name="m_code"]').value.trim(), n = body.querySelector('[name="m_name"]').value.trim(); if (!c || !n) { toast('Код и наименование'); return; } rpc('app_material_save', { p_token: token, p_id: null, p_code: c, p_name: n, p_unit: body.querySelector('[name="m_unit"]').value || 'шт', p_price: null, p_min_qty: null }).then(function () { bump(); body.querySelector('[name="m_code"]').value = ''; body.querySelector('[name="m_name"]').value = ''; toast('Материал добавлен'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); }); body.querySelector('[data-add="eq"]').addEventListener('click', function () { var n = body.querySelector('[name="e_name"]').value.trim(); if (!n) return; rpc('app_equipment_save', { p_token: token, p_id: null, p_name: n, p_brand: null, p_category: null, p_axes: null, p_accuracy: null, p_price: null, p_description: null, p_active: true }).then(function () { bump(); body.querySelector('[name="e_name"]').value = ''; toast('Оборудование добавлено'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); }); } }
      ];

      // Шаги по модулям (включённым) — настройки с пояснениями
      moduleKeys.forEach(function (mod) {
        var def = MODULE_FIELDS[mod]; var a = catApp(mod);
        var tt = (a ? a.icon + ' ' + a.title : '⚙ ' + def.title);
        var hh = (a && (a.desc || a.purpose)) ? (a.desc || a.purpose) : 'Параметры модуля. Пояснения — под каждым полем.';
        steps.push({ key: 'mod_' + mod, title: tt, hint: hh,
          html: function () { return def.fields.map(function (f) { return fieldHtml(mod, f, (settingsMap[mod] || {})[f.key]); }).join('') + '<div class="note" style="margin-top:6px;">Сохраняется в настройках организации.</div>'; } });
      });

      steps.push({ key: 'check', title: '✅ Проверка', hint: 'Сводка готовности: что уже заполнено, что осталось дозаполнить.',
        html: function () { return '<div id="wzChk"><span class="note">Проверка…</span></div>'; },
        onShow: function (body) {
          var box = body.querySelector('#wzChk');
          rpc('app_setup_readiness', { p_token: token }).then(function (rows) { rows = rows || []; var ok = rows.filter(function (r) { return r.ready; }).length; var pct = rows.length ? Math.round(100 * ok / rows.length) : 0;
            box.innerHTML = '<div style="font-weight:700;font-size:1.05rem;">Готовность: ' + ok + ' / ' + rows.length + ' (' + pct + '%)</div>' +
              '<div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Пункт</th><th class="num">Заполнено</th><th>Статус</th></tr></thead><tbody>' +
              rows.map(function (r) { return '<tr><td>' + esc(r.label) + ' <span class="note">' + esc(r.module) + '</span></td><td class="num">' + r.cnt + ' / ' + r.target + '</td><td>' + (r.ready ? '<span class="badge done">готово</span>' : '<span class="badge in_progress">дозаполнить</span>') + '</td></tr>'; }).join('') + '</tbody></table></div>'; }).catch(function (e) { box.innerHTML = '<span class="note">' + esc(e.message) + '</span>'; });
        } });
      steps.push({ key: 'modules', title: '🧩 Включение модулей', hint: 'Доступ к отключённым модулям закрывается (навигация и прямой URL).',
        html: function () { return '<div class="field"><label>Поиск модуля</label><input type="text" id="wzModQ" placeholder="Название, назначение или контур…"></div><div id="wzMods"><span class="note">Загрузка…</span></div>'; },
        onShow: function (body) { var box = body.querySelector('#wzMods'); var cat = (g.AppCatalog && g.AppCatalog.apps) ? g.AppCatalog : { apps: [], groups: [] }; rpc('app_tenant_modules_list', { p_token: token }).then(function (rows) { rows = rows || []; var map = {}; rows.forEach(function (m) { map[m.module] = m.enabled !== false; }); var apps = (cat.apps || []).filter(function (a) { return a.href && a.href.indexOf('apps/') === 0; }); var byG = {}; apps.forEach(function (a) { var k = a.group || '_'; (byG[k] = byG[k] || []).push(a); }); var order = (cat.groups || []).map(function (x) { return x.id; }).filter(function (id) { return byG[id]; }); if (byG['_']) order.push('_'); if (!apps.length) { box.innerHTML = '<span class="note">Каталог не загружен.</span>'; return; } box.innerHTML = order.map(function (gid) { var grp = (cat.groups || []).filter(function (x) { return x.id === gid; })[0] || { icon: '🗂', title: 'Прочее' }; var items = byG[gid] || []; return '<div class="note" style="margin:12px 0 2px;font-weight:700;">' + grp.icon + ' ' + esc(grp.title) + '</div>' + items.map(function (a) { var on = map[a.id] !== false; return '<div class="kvr" data-modrow style="align-items:flex-start;"><span style="font-size:1.25rem;">' + a.icon + '</span><div style="flex:1;min-width:0;"><b>' + esc(a.title) + '</b><div class="note" style="font-size:.74rem;">' + esc(a.desc || a.purpose || '') + '</div>' + (a.features && a.features.length ? '<div class="note" style="font-size:.72rem;">✔ ' + esc(a.features.slice(0, 5).join('; ')) + '</div>' : '') + '</div><label class="m"><input type="checkbox" data-mod="' + esc(a.id) + '"' + (on ? ' checked' : '') + '> включён</label></div>'; }).join(''); }).join(''); var qEl = document.getElementById('wzModQ'); if (qEl) qEl.addEventListener('input', function () { var s = qEl.value.trim().toLowerCase(); box.querySelectorAll('[data-modrow]').forEach(function (r) { r.style.display = (!s || (r.textContent || '').toLowerCase().indexOf(s) >= 0) ? '' : 'none'; }); }); box.querySelectorAll('[data-mod]').forEach(function (ch) { ch.addEventListener('change', function () { rpc('app_tenant_module_set', { p_token: token, p_module: ch.dataset.mod, p_enabled: ch.checked }).then(function () { toast('Обновлено'); }).catch(function (e) { toast('Ошибка: ' + e.message); }); }); }); }).catch(function (e) { box.innerHTML = '<span class="note">' + esc(e.message) + '</span>'; }); } });
      steps.push({ key: 'demo', title: 'Демо-данные', hint: 'Демо-строки можно загрузить и удалить отдельно — реальные данные не затрагиваются.',
        html: function (d) { return '<label><input type="checkbox" name="load_demo"' + (d.load_demo ? ' checked' : '') + '> Загрузить демо-данные по всем модулям</label>'; } });

      function collectModuleSettings(draft) {
        var out = [];
        moduleKeys.forEach(function (mod) {
          var obj = {}; var has = false;
          MODULE_FIELDS[mod].fields.forEach(function (f) {
            var name = 'set_' + mod + '__' + f.key; if (draft[name] !== undefined) { obj[f.key] = draft[name]; has = true; }
          });
          if (has) out.push({ module: mod, settings: obj });
        });
        return out;
      }

      g.AppWizard.open({
        id: scope ? ('setup-' + scope) : 'setup', title: scope ? ('Настройка модуля: ' + (MODULE_FIELDS[scope] ? MODULE_FIELDS[scope].title : scope)) : 'Мастер настройки', icon: '🚀', submitText: 'Завершить',
        steps: steps,
        onSubmit: function (draft) {
          var chain = Promise.resolve();
          steps.forEach(function (s) { chain = chain.then(function () { return rpc('app_setup_step_set', { p_token: token, p_key: s.key, p_status: 'done', p_note: null }).catch(function () {}); }); });
          collectModuleSettings(draft).forEach(function (ms) {
            chain = chain.then(function () { return rpc('app_tenant_settings_set', { p_token: token, p_module: ms.module, p_settings: ms.settings }).catch(function () {}); });
          });
          if (draft.load_demo) chain = chain.then(function () { return rpc('app_demo_seed', { p_token: token, p_module: 'all' }).catch(function () {}); });
          return chain.then(function () { toast('Настройки сохранены'); if (opts.onDone) opts.onDone(); }).then(function () { return null; }, function (e) { return 'Ошибка: ' + e.message; });
        }
      });
    }).catch(function (e) { toast('Ошибка загрузки настроек: ' + e.message); });
  }

  function start(opts) { var token = (g.Auth && g.Auth.token) ? g.Auth.token() : null; if (!token) { toast('Требуется вход'); return; } open(token, opts); }

  g.AppSetupWizard = { open: open, start: start, MODULE_FIELDS: MODULE_FIELDS };
})(window);
