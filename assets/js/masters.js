/* ============================================================
   3DMP Service · masters.js (v1) — «мастера-плитки».
   Отдельные элементы (плитки) для быстрого визуального ввода данных.
   Число мастеров не ограничено; набор зависит от модуля. Монтирование:
   контейнер <div id="masters"></div> + подключение wizard.js и masters.js.
   Открытие: window.AppMasters.open(id, { token }) ; плитки — автоматически.
   ============================================================ */
(function (g) {
  'use strict';
  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }
  function toast(t, k) { if (g.AppUI && g.AppUI.toast) g.AppUI.toast(t, k); }
  function rpc(n, a) { return g.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function moduleId() { var m = location.pathname.match(/\/apps\/([a-z0-9_]+)\//i); return m ? m[1].toLowerCase() : ''; }

  function ensureStyle() {
    if (document.getElementById('mstStyle')) return;
    var st = document.createElement('style'); st.id = 'mstStyle';
    st.textContent =
      '#masters{margin:10px 0 4px}' +
      '.mtiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:14px;align-items:stretch}' +
      '.mtile{text-align:left;border:1px solid var(--border);border-radius:14px;background:#fff;padding:14px 16px;cursor:pointer;transition:.15s;display:flex;flex-direction:column;gap:6px;height:100%;min-height:110px;box-sizing:border-box;font:inherit}' +
      '.mtile:hover{border-color:var(--accent,#10b981);box-shadow:0 8px 22px rgba(16,185,129,.14);transform:translateY(-1px)}' +
      '.mtile .mi{font-size:1.25rem;line-height:1}.mtile b{font-size:.92rem;line-height:1.25}.mtile .md{font-size:.78rem;color:var(--muted,#64748b);line-height:1.3;margin-top:auto}' +
      '.mhead{display:flex;align-items:baseline;gap:10px;margin:0 0 10px}.mhead h2{margin:0;font-size:1.02rem}.mhead .note{margin-left:auto;font-size:.75rem;color:var(--muted)}';
    document.head.appendChild(st);
  }

  function opts(list, name, sel, empty) {
    return '<select name="' + name + '"><option value="">' + esc(empty || '— выберите —') + '</option>' +
      (list || []).map(function (x) { return '<option value="' + esc(x.code) + '"' + (sel && String(x.code) === String(sel) ? ' selected' : '') + '>' + esc(x.name) + (x.info ? ' · ' + esc(x.info) : '') + '</option>'; }).join('') + '</select>';
  }
  function requiresWizard() { if (!g.AppWizard) { toast('Движок мастера не подключён (wizard.js)', 'err'); return true; } return false; }

  /* ---------- Мастер: деталь → техпроцесс → задание/наряд/документ ---------- */
  function openMfg(ctx) {
    if (requiresWizard()) return;
    Promise.all([
      rpc('app_tech_wizard_options', { p_token: ctx.token, p_kind: 'part' }).catch(function () { return []; }),
      rpc('app_tech_wizard_options', { p_token: ctx.token, p_kind: 'material' }).catch(function () { return []; }),
      rpc('app_tech_wizard_options', { p_token: ctx.token, p_kind: 'operation' }).catch(function () { return []; })
    ]).then(function (r) {
      var parts = r[0] || [], mats = r[1] || [], ops = r[2] || [];
      if (!parts.length) { toast('Нет типовых маршрутов — заполните «Справочники → Типовые маршруты»', 'err'); return; }
      g.AppWizard.open({
        id: 'mfg', title: 'Мастер производства: деталь → техпроцесс', icon: '🧭', submitText: 'Создать', doneText: 'Создано',
        steps: [
          { title: '1. Тип детали', hint: 'Типовая деталь → подбирается типовой маршрут.', html: function (d) { return '<label>Тип детали <span class="wz-req">*</span></label>' + opts(parts, 'code', d.code); }, validate: function (d) { return d.code ? null : 'Выберите тип детали'; } },
          { title: '2. Материал, партия и масса', html: function (d) { return '<label>Материал</label>' + opts(mats, 'material', d.material) + '<label>Количество, шт</label><input name="qty" type="number" min="1" value="' + esc(d.qty || 1) + '"><label>Масса, кг</label><input name="weight" type="number" min="0" step="0.1" value="' + esc(d.weight || '') + '">'; } },
          { title: '3. Уточняющая операция', hint: 'Необязательно — добавится в маршрут.', html: function (d) { return '<label>Операция</label>' + opts(ops, 'operation', d.operation, '— без уточнения —'); } },
          { title: '4. Задание, наряд и документ', html: function (d) {
              return '<label>Название <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
                '<label>Срок наряда</label><input name="due" type="date" value="' + esc(d.due || '') + '">' +
                '<label style="display:flex;gap:8px;align-items:center;font-weight:600;"><input type="checkbox" name="make_naryad" style="width:auto;flex:0 0 auto;" ' + (d.make_naryad !== false ? 'checked' : '') + '> Наряд</label>' +
                '<label style="display:flex;gap:8px;align-items:center;font-weight:600;"><input type="checkbox" name="make_tasks" style="width:auto;flex:0 0 auto;" ' + (d.make_tasks !== false ? 'checked' : '') + '> Сменно-суточное задание</label>' +
                '<label style="display:flex;gap:8px;align-items:center;font-weight:600;"><input type="checkbox" name="make_doc" style="width:auto;flex:0 0 auto;" ' + (d.make_doc !== false ? 'checked' : '') + '> Документ-техкарта</label>' +
                '<label style="display:flex;gap:8px;align-items:center;font-weight:600;"><input type="checkbox" name="ex_tooling" style="width:auto;flex:0 0 auto;" ' + (d.ex_tooling ? 'checked' : '') + '> 📐 Нужна оснастка</label>' +
                '<label style="display:flex;gap:8px;align-items:center;font-weight:600;"><input type="checkbox" name="ex_electrodes" style="width:auto;flex:0 0 auto;" ' + (d.ex_electrodes ? 'checked' : '') + '> 🔌 Нужны электроды</label>';
            }, validate: function (d) { return d.title ? null : 'Укажите название'; } }
        ],
        onSubmit: function (d) {
          var extras = [];
          if (d.ex_tooling) extras.push('tooling');
          if (d.ex_electrodes) extras.push('electrodes');
          return rpc('app_master_manufacture', {
            p_token: ctx.token, p_code: d.code, p_title: d.title, p_material: d.material || null,
            p_qty: d.qty ? Number(d.qty) : 1, p_due: d.due || null, p_operation: d.operation || null,
            p_make_naryad: d.make_naryad !== false, p_make_tasks: d.make_tasks !== false, p_make_doc: d.make_doc !== false,
            p_weight: d.weight ? Number(d.weight) : null, p_extras: extras.length ? extras : null
          }).then(function (r) {
            var x = r && r[0];
            if (!x || x.ok === false) return (x && x.message) || 'Не удалось создать';
            toast(x.message || 'Готово', 'ok'); done(x); return null;
          });
        }
      });
    }).catch(function (e) { toast('Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Мастер: быстрый документ ---------- */
  function openDoc(ctx) {
    if (requiresWizard()) return;
    g.AppWizard.open({
      id: 'doc', title: 'Быстрый документ', icon: '📄', submitText: 'Создать', doneText: 'Документ создан',
      steps: [{ title: 'Документ', html: function (d) {
        return '<label>Тип</label><select name="type"><option value="kp">КП</option><option value="contract">Договор</option><option value="techcard">Техкарта</option><option value="act">Акт</option><option value="other">Прочее</option></select>' +
          '<label>Название <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
          '<label>Сумма</label><input name="amount" type="number" value="' + esc(d.amount || '') + '">';
      }, validate: function (d) { return d.title ? null : 'Укажите название'; } }],
      onSubmit: function (d) {
        return rpc('app_doc_create', { p_token: ctx.token, p_doc_type: d.type, p_title: d.title, p_order_id: null, p_counterparty: null, p_amount: d.amount ? Number(d.amount) : null, p_content: null })
          .then(function (r) { var x = r && r[0]; if (!x || !x.number) return 'Не удалось создать'; toast('Создан документ ' + x.number, 'ok'); done(x); return null; });
      }
    });
  }

  /* ---------- Мастер: ёмкость РЦ ---------- */
  function openCap(ctx) {
    if (requiresWizard()) return;
    rpc('app_capacity', { p_token: ctx.token }).then(function (rows) {
      var centers = (rows || []).map(function (c) { return { code: c.wc_id, name: c.wc_name }; });
      if (!centers.length) { toast('Нет рабочих центров', 'err'); return; }
      g.AppWizard.open({
        id: 'cap', title: 'Ёмкость рабочего центра', icon: '⚙', submitText: 'Сохранить', doneText: 'Сохранено',
        steps: [{ title: 'Ёмкость на дату', html: function (d) {
          return '<label>Рабочий центр</label>' + opts(centers, 'wc', d.wc) +
            '<label>Дата</label><input name="date" type="date" value="' + esc(d.date || new Date().toISOString().slice(0, 10)) + '">' +
            '<label>Часов</label><input name="hours" type="number" value="' + esc(d.hours || 8) + '">';
        }, validate: function (d) { return d.wc ? null : 'Выберите центр'; } }],
        onSubmit: function (d) {
          return rpc('app_capacity_set', { p_token: ctx.token, p_wc_id: d.wc, p_date: d.date, p_hours: Number(d.hours) || 8 })
            .then(function (r) { var x = r && r[0]; if (x && x.ok === false) return x.message || 'Ошибка'; toast((x && x.message) || 'Сохранено', 'ok'); done(x); return null; });
        }
      });
    }).catch(function (e) { toast('Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Мастер: наработка инструмента ---------- */
  function openTool(ctx) {
    if (requiresWizard()) return;
    rpc('app_tool_life_list', { p_token: ctx.token, p_q: null }).then(function (rows) {
      var tools = (rows || []).map(function (t) { return { code: t.id, name: t.name + (t.code ? ' (' + t.code + ')' : ''), info: 'наработка ' + (t.used_min || 0) + ' мин' }; });
      if (!tools.length) { toast('Нет инструмента', 'err'); return; }
      g.AppWizard.open({
        id: 'tool', title: 'Наработка инструмента', icon: '🛠', submitText: 'Учесть', doneText: 'Учтено',
        steps: [{ title: 'Списать наработку', html: function (d) {
          return '<label>Инструмент</label>' + opts(tools, 'tool', d.tool) + '<label>Минут</label><input name="minutes" type="number" min="1" value="' + esc(d.minutes || 30) + '">';
        }, validate: function (d) { return d.tool ? null : 'Выберите инструмент'; } }],
        onSubmit: function (d) {
          return rpc('app_tool_life_use', { p_token: ctx.token, p_id: d.tool, p_minutes: Number(d.minutes) || 0, p_note: null })
            .then(function (r) { var x = r && r[0]; toast((x && x.message) || 'Учтено', 'ok'); done(x); return null; });
        }
      });
    }).catch(function (e) { toast('Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Мастер: заказ клиента ---------- */
  function openOrder(ctx) {
    if (requiresWizard()) return;
    g.AppWizard.open({
      id: 'order', title: 'Заказ клиента', icon: '🧾', submitText: 'Создать', doneText: 'Заказ создан',
      steps: [{ title: 'Заказ', html: function (d) {
        return '<label>Тема <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
          '<label>Заказчик</label><input name="customer" value="' + esc(d.customer || '') + '">' +
          '<label>Срок</label><input name="due" type="date" value="' + esc(d.due || '') + '">' +
          '<label>Приоритет</label><select name="priority"><option value="normal">Обычный</option><option value="high">Высокий</option><option value="critical">Критичный</option></select>' +
          '<label>Сумма</label><input name="amount" type="number" value="' + esc(d.amount || '') + '">';
      }, validate: function (d) { return d.title ? null : 'Укажите тему'; } }],
      onSubmit: function (d) {
        return rpc('app_order_create', { p_token: ctx.token, p_title: d.title, p_description: '', p_source: '', p_customer: d.customer || '', p_contact: '', p_priority: d.priority || 'normal', p_customer_id: null, p_due_date: d.due || null, p_assignee: '', p_amount: d.amount ? Number(d.amount) : null, p_order_type: 'single' })
          .then(function (r) { var x = r && r[0]; var id = x && (x.id || x.order_id); if (!id && (!x || x.ok === false)) return (x && x.message) || 'Не удалось создать'; toast('Заказ создан', 'ok'); done(x); return null; });
      }
    });
  }

  /* ---------- Мастер: сервисная заявка ---------- */
  function openSrvc(ctx) {
    if (requiresWizard()) return;
    g.AppWizard.open({
      id: 'srvc', title: 'Сервисная заявка', icon: '🔧', submitText: 'Создать', doneText: 'Заявка создана',
      steps: [{ title: 'Заявка', html: function (d) {
        return '<label>Тема <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
          '<label>Вид</label><select name="kind"><option value="service">Обслуживание</option><option value="repair">Ремонт</option><option value="warranty">Гарантия</option></select>' +
          '<label>Приоритет</label><select name="priority"><option value="normal">Обычный</option><option value="high">Высокий</option><option value="critical">Критичный</option></select>' +
          '<label>Срок</label><input name="due" type="date" value="' + esc(d.due || '') + '">' +
          '<label>Контакт</label><input name="contact" value="' + esc(d.contact || '') + '">' +
          '<label>Объект/адрес</label><input name="location" value="' + esc(d.location || '') + '">';
      }, validate: function (d) { return d.title ? null : 'Укажите тему'; } }],
      onSubmit: function (d) {
        return rpc('app_service_save', { p_token: ctx.token, p_id: null, p_customer_id: null, p_equipment_id: null, p_title: d.title, p_kind: d.kind || 'service', p_scheduled_date: d.due || null, p_engineer: null, p_works: null, p_cost: null, p_note: null, p_priority: d.priority || 'normal', p_channel: 'manual', p_is_warranty: (d.kind === 'warranty') || null, p_contact: d.contact || null, p_location: d.location || null, p_assigned_login: null })
          .then(function (r) { var x = r && r[0]; if (!x || !x.number) return (x && x.message) || 'Не удалось создать'; toast('Создана заявка ' + x.number, 'ok'); done(x); return null; });
      }
    });
  }

  /* ---------- Мастер: паспорт партии ---------- */
  function openPassport(ctx) {
    if (requiresWizard()) return;
    g.AppWizard.open({
      id: 'passport', title: 'Паспорт партии', icon: '📘', submitText: 'Создать', doneText: 'Паспорт создан',
      steps: [{ title: 'Паспорт', html: function (d) {
        return '<label>Изделие/партия <span class="wz-req">*</span></label><input name="product" value="' + esc(d.product || '') + '">' +
          '<label>Серийный номер</label><input name="serial" value="' + esc(d.serial || '') + '">' +
          '<label>Количество</label><input name="qty" type="number" min="1" value="' + esc(d.qty || 1) + '">';
      }, validate: function (d) { return d.product ? null : 'Укажите изделие/партию'; } }],
      onSubmit: function (d) {
        return rpc('app_passport_create', { p_token: ctx.token, p_order_id: null, p_product: d.product, p_qc_check_id: null, p_data: {}, p_naryad_id: null, p_serial: d.serial || null, p_qty: d.qty ? Number(d.qty) : 1 })
          .then(function (r) { var x = r && r[0]; if (!x || (!x.id && !x.number)) return (x && x.message) || 'Не удалось создать'; toast('Паспорт создан', 'ok'); done(x); return null; });
      }
    });
  }

  /* ---------- Мастер: сотрудник ---------- */
  function openEmp(ctx) {
    if (requiresWizard()) return;
    g.AppWizard.open({
      id: 'emp', title: 'Новый сотрудник', icon: '👷', submitText: 'Создать', doneText: 'Сотрудник добавлен',
      steps: [{ title: 'Сотрудник', html: function (d) {
        return '<label>ФИО <span class="wz-req">*</span></label><input name="fio" value="' + esc(d.fio || '') + '">' +
          '<label>Должность</label><input name="position" value="' + esc(d.position || '') + '">' +
          '<label>Подразделение</label><input name="dept" value="' + esc(d.dept || '') + '">' +
          '<label>Телефон</label><input name="phone" value="' + esc(d.phone || '') + '">' +
          '<label>Email</label><input name="email" value="' + esc(d.email || '') + '">' +
          '<label>Дата приёма</label><input name="hired" type="date" value="' + esc(d.hired || '') + '">';
      }, validate: function (d) { return d.fio ? null : 'Укажите ФИО'; } }],
      onSubmit: function (d) {
        return rpc('app_employee_save', { p_token: ctx.token, p_id: null, p_full_name: d.fio, p_position: d.position || '', p_dept: d.dept || '', p_phone: d.phone || '', p_email: d.email || null, p_hired_at: d.hired || null, p_user_login: null })
          .then(function () { toast('Сотрудник добавлен', 'ok'); done(); return null; });
      }
    });
  }

  /* ---------- Мастер: входящий документ ---------- */
  function openEdo(ctx) {
    if (requiresWizard()) return;
    g.AppWizard.open({
      id: 'edo', title: 'Входящий документ', icon: '📥', submitText: 'Создать', doneText: 'Документ создан',
      steps: [{ title: 'Документ', html: function (d) {
        return '<label>Название <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
          '<label>Тип</label><select name="dt"><option value="letter">Письмо</option><option value="order">Приказ</option><option value="contract">Договор</option><option value="invoice">Счёт</option><option value="other">Прочее</option></select>' +
          '<label>Корреспондент</label><input name="corr" value="' + esc(d.corr || '') + '">' +
          '<label>Краткое содержание</label><input name="summary" value="' + esc(d.summary || '') + '">' +
          '<label>Срок</label><input name="due" type="date" value="' + esc(d.due || '') + '">';
      }, validate: function (d) { return d.title ? null : 'Укажите название'; } }],
      onSubmit: function (d) {
        return rpc('app_doc_save', { p_token: ctx.token, p_id: null, p_kind: 'in', p_doc_type: d.dt || 'letter', p_title: d.title, p_correspondent: d.corr || '', p_summary: d.summary || '', p_responsible: '', p_due_date: d.due || null, p_reg_date: null })
          .then(function () { toast('Документ создан', 'ok'); done(); return null; });
      }
    });
  }

  /* ---------- Мастер: заявка на закупку ---------- */
  function openPr(ctx) {
    if (requiresWizard()) return;
    rpc('app_ref_material_list', { p_token: ctx.token, p_group: null, p_q: null }).then(function (rows) {
      var mats = (rows || []).map(function (m) { return { code: m.id, name: m.grade + (m.group_code ? ' (' + m.group_code + ')' : '') }; });
      g.AppWizard.open({
        id: 'pr', title: 'Заявка на закупку', icon: '📦', submitText: 'Создать', doneText: 'Заявка создана',
        steps: [{ title: 'Заявка', html: function (d) {
          return '<label>Название <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
            '<label>Материал (из справочника)</label>' + opts(mats, 'material', d.material, '— без привязки —') +
            '<label>Количество</label><input name="qty" type="number" value="' + esc(d.qty || 1) + '">' +
            '<label>Ед.</label><input name="unit" value="' + esc(d.unit || 'шт') + '">' +
            '<label>Примечание</label><input name="note" value="' + esc(d.note || '') + '">';
        }, validate: function (d) { return d.title ? null : 'Укажите название'; } }],
        onSubmit: function (d) {
          return rpc('app_purchase_request_save', { p_token: ctx.token, p_id: null, p_material_id: d.material || null, p_title: d.title, p_qty: d.qty ? Number(d.qty) : 1, p_unit: d.unit || 'шт', p_note: d.note || null })
            .then(function () { toast('Заявка создана', 'ok'); done(); return null; });
        }
      });
    }).catch(function (e) { toast('Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Мастер: сделка CRM ---------- */
  function openDeal(ctx) {
    if (requiresWizard()) return;
    g.AppWizard.open({
      id: 'deal', title: 'Сделка CRM', icon: '📈', submitText: 'Создать', doneText: 'Сделка создана',
      steps: [{ title: 'Сделка', html: function (d) {
        return '<label>Название <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
          '<label>Стадия</label><select name="stage"><option value="lead">Лид</option><option value="qualified">Квалифицирована</option><option value="proposal">КП</option><option value="negotiation">Переговоры</option><option value="won">Выиграна</option><option value="lost">Проиграна</option></select>' +
          '<label>Сумма</label><input name="amount" type="number" value="' + esc(d.amount || '') + '">' +
          '<label>Вероятность, %</label><input name="prob" type="number" min="0" max="100" value="' + esc(d.prob || 50) + '">' +
          '<label>Следующее действие</label><input name="action" value="' + esc(d.action || '') + '">' +
          '<label>Срок</label><input name="due" type="date" value="' + esc(d.due || '') + '">';
      }, validate: function (d) { return d.title ? null : 'Укажите название'; } }],
      onSubmit: function (d) {
        return rpc('app_deal_save', { p_token: ctx.token, p_id: null, p_customer_id: null, p_title: d.title, p_stage: d.stage || 'lead', p_amount: d.amount ? Number(d.amount) : null, p_probability: d.prob ? Number(d.prob) : null, p_source: '', p_owner: '', p_next_action: d.action || null, p_due_date: d.due || null, p_order_id: null, p_note: null })
          .then(function () { toast('Сделка создана', 'ok'); done(); return null; });
      }
    });
  }

  var DEFS = [
    { id: 'mfg', icon: '🧭', title: 'Деталь → техпроцесс → задание, наряд и документ', desc: 'Пошагово: тип детали, материал, партия, срок → маршрут, ССЗ, наряд, техкарта.', modules: ['registry', 'assistant', 'norms', 'production', 'planning', 'mes', 'docs'], run: openMfg },
    { id: 'doc', icon: '📄', title: 'Быстрый документ', desc: 'Создать КП/договор/акт/техкарту с автоматическим номером.', modules: ['docs', 'docbuilder', 'templates', 'registry', 'tkp'], run: openDoc },
    { id: 'order', icon: '🧾', title: 'Заказ клиента', desc: 'Быстро завести заказ: тема, заказчик, срок, приоритет, сумма.', modules: ['orders', 'crm', 'tkp', 'planning', 'economics'], run: openOrder },
    { id: 'srvc', icon: '🔧', title: 'Сервисная заявка', desc: 'Заявка на ремонт/обслуживание с приоритетом и сроком.', modules: ['service', 'dealer', 'maintenance'], run: openSrvc },
    { id: 'passport', icon: '📘', title: 'Паспорт партии', desc: 'Создать паспорт изделия/партии с серийным номером.', modules: ['qc', 'passport', 'quality', 'production'], run: openPassport },
    { id: 'emp', icon: '👷', title: 'Новый сотрудник', desc: 'Завести сотрудника: ФИО, должность, подразделение, контакты.', modules: ['hr'], run: openEmp },
    { id: 'edo', icon: '📥', title: 'Входящий документ', desc: 'Зарегистрировать входящий документ (письмо/приказ/договор/счёт).', modules: ['edo', 'docs', 'office'], run: openEdo },
    { id: 'pr', icon: '📦', title: 'Заявка на закупку', desc: 'Быстрая заявка на материал с привязкой к справочнику.', modules: ['procurement', 'warehouse', 'supply'], run: openPr },
    { id: 'deal', icon: '📈', title: 'Сделка CRM', desc: 'Новая сделка: стадия, сумма, вероятность, следующее действие.', modules: ['crm', 'tkp', 'orders'], run: openDeal },
    { id: 'cap', icon: '⚙', title: 'Ёмкость РЦ на дату', desc: 'Задать доступные часы рабочего центра.', modules: ['planning', 'slots'], run: openCap },
    { id: 'tool', icon: '🛠', title: 'Наработка инструмента', desc: 'Быстро списать наработку по инструменту.', modules: ['tooling', 'maintenance'], run: openTool }
  ];

  function current() { var mid = moduleId(); return DEFS.filter(function (d) { return !d.modules || d.modules.indexOf(mid) >= 0; }); }

  var g_onDone = null;
  function done(x) { try { if (typeof g_onDone === 'function') g_onDone(x); } catch (e) {} try { window.dispatchEvent(new CustomEvent('masters:done', { detail: x })); } catch (e) {} }

  function render(box, ctx) {
    ensureStyle();
    var list = current();
    if (!list.length) { box.innerHTML = ''; return; }
    box.innerHTML = '<div class="mhead"><h2>Мастера быстрого ввода</h2><span class="note">клик по плитке — пошаговый ввод</span></div>' +
      '<div class="mtiles">' + list.map(function (d) {
        return '<button class="mtile" type="button" data-mst="' + d.id + '"><span class="mi">' + d.icon + '</span><b>' + esc(d.title) + '</b><span class="md">' + esc(d.desc) + '</span></button>';
      }).join('') + '</div>';
    Array.prototype.forEach.call(box.querySelectorAll('[data-mst]'), function (b) {
      b.addEventListener('click', function () { open(b.dataset.mst, ctx); });
    });
  }

  function open(id, ctx) {
    var d = null; for (var i = 0; i < DEFS.length; i++) if (DEFS[i].id === id) d = DEFS[i];
    if (!d) { toast('Мастер не найден', 'err'); return; }
    ctx = ctx || {};
    if (!ctx.token) ctx.token = (g.Auth && g.Auth.token) ? g.Auth.token() : null;
    if (!ctx.token) { toast('Нет сессии', 'err'); return; }
    d.run(ctx);
  }

  function mountAuto() {
    var box = document.getElementById('masters'); if (!box) return;
    var t = (g.Auth && g.Auth.token) ? g.Auth.token() : null;
    if (!t) { setTimeout(mountAuto, 400); return; }
    render(box, { token: t });
  }

  g.AppMasters = {
    list: current,
    open: open,
    render: function (sel, ctx) { var b = typeof sel === 'string' ? document.querySelector(sel) : sel; if (b) { g_onDone = ctx && ctx.onDone; render(b, ctx); } },
    onDone: function (fn) { g_onDone = fn; }
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mountAuto);
  else mountAuto();
})(window);
