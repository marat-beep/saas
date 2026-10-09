/* ============================================================
   3DMP Service · wizards.js — пилотные мастера (W32).
   Требует wizard.js (AppWizard), supabase-client.js, auth.js.
   Кнопка «＋ … (мастер)» подставляется автоматически на страницах
   модулей mdm/tooling/warehouse/workflow/kedo/logistics.
   ============================================================ */
(function (g) {
  'use strict';
  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }
  function tok() { return g.Auth && g.Auth.token ? g.Auth.token() : null; }
  function rpc(n, a) { return g.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function call(n, a) {
    return rpc(n, a).then(function (d) {
      var row = Array.isArray(d) ? d[0] : d;
      if (row && row.ok === false) return row.message || 'Не удалось сохранить';
      return null;
    });
  }
  function num(v) { return (v === '' || v == null) ? null : Number(v); }
  function sel(opts, cur) {
    return opts.map(function (o) { return '<option value="' + o[0] + '"' + (String(cur) === String(o[0]) ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('');
  }
  function fi(label, name, d, attrs) { return '<label>' + label + '<input name="' + name + '" value="' + esc(d[name] == null ? '' : d[name]) + '" ' + (attrs || '') + '></label>'; }
  function fsel(label, name, d, options) { return '<label>' + label + '<select name="' + name + '">' + options + '</select></label>'; }
  function loadSel(box, name, loadFn, valFn, labFn, cur) {
    var s = box.querySelector('[name="' + name + '"]'); if (!s) return;
    loadFn().then(function (list) {
      var opts = '<option value="">— выберите —</option>' + (list || []).map(function (x) {
        return '<option value="' + valFn(x) + '">' + esc(labFn(x)) + '</option>';
      }).join('');
      s.innerHTML = opts;
      if (cur) s.value = cur;
    }).catch(function (e) {
      s.innerHTML = '<option value="">Ошибка загрузки</option>';
      if (g.AppUI && g.AppUI.toast) g.AppUI.toast('Список недоступен: ' + e.message);
    });
  }

  var SPECS = {
    mdm: {
      icon: '🌐', title: 'Мастер: новая позиция НСИ', startLabel: '＋ Позиция НСИ (мастер)', submitText: 'Создать', doneText: 'Позиция НСИ создана',
      steps: [
        { title: 'Основное', hint: 'Код и наименование обязательны.',
          html: function (d) {
            return fi('Код <span class="wz-req">*</span>', 'code', d) + fi('Наименование <span class="wz-req">*</span>', 'name', d) +
              fsel('Тип', 'item_type', d, sel([['material', 'Материал'], ['product', 'Изделие'], ['service', 'Услуга'], ['equipment', 'Оборудование'], ['tool', 'Инструмент']], d.item_type || 'material')) +
              fi('Единица', 'unit', d);
          },
          validate: function (d) { if (!d.code) return 'Укажите код'; if (!d.name) return 'Укажите наименование'; } },
        { title: 'Классификация',
          html: function (d) {
            return fi('Группа', 'grp', d) +
              fsel('Статус', 'status', d, sel([['active', 'Активна'], ['draft', 'Черновик'], ['archived', 'Архив']], d.status || 'active')) +
              fi('Примечание', 'note', d);
          } }
      ],
      onSubmit: function (d) { return call('app_master_item_save', { p_token: tok(), p_id: null, p_code: d.code, p_name: d.name, p_item_type: d.item_type || 'material', p_unit: d.unit || null, p_group: d.grp || null, p_attrs: null, p_status: d.status || 'active', p_note: d.note || null }); }
    },
    tooling: {
      icon: '🪚', title: 'Мастер: экземпляр инструмента', startLabel: '＋ Экземпляр инструмента (мастер)', submitText: 'Добавить', doneText: 'Экземпляр добавлен',
      steps: [
        { title: 'Инструмент', hint: 'Позиция из ресурсного справочника инструмента.',
          html: function (d) { return fsel('Инструмент (ресурс) <span class="wz-req">*</span>', 'tool_life_id', d, '<option value="">загрузка…</option>') + fi('Серийный №', 'serial', d); },
          onShow: function (box, d) { loadSel(box, 'tool_life_id', function () { return rpc('app_tool_life_list', { p_token: tok() }); }, function (x) { return x.id; }, function (x) { return (x.code ? x.code + ' · ' : '') + (x.name || ''); }, d.tool_life_id); },
          validate: function (d) { if (!d.tool_life_id) return 'Выберите инструмент'; } },
        { title: 'Размещение',
          html: function (d) { return fsel('Адрес хранения', 'location_id', d, '<option value="">загрузка…</option>') + fi('Ресурс, мин', 'resource_min', d, 'type="number" min="0" step="any"') + fi('Примечание', 'note', d); },
          onShow: function (box, d) { loadSel(box, 'location_id', function () { return rpc('app_wh_address_list', { p_token: tok() }); }, function (x) { return x.id; }, function (x) { return x.code || ((x.zone || '') + '/' + (x.cell || '')); }, d.location_id); } }
      ],
      onSubmit: function (d) { return call('app_tool_item_save', { p_token: tok(), p_id: null, p_tool_life_id: d.tool_life_id || null, p_serial: d.serial || null, p_location_id: d.location_id || null, p_resource_min: num(d.resource_min), p_note: d.note || null }); }
    },
    warehouse: {
      icon: '📦', title: 'Мастер: приёмка на склад', startLabel: '＋ Приёмка (мастер)', submitText: 'Разместить', doneText: 'Материал размещён',
      steps: [
        { title: 'Материал',
          html: function (d) { return fsel('Материал <span class="wz-req">*</span>', 'material_id', d, '<option value="">загрузка…</option>') + fi('Партия (номер)', 'lot', d); },
          onShow: function (box, d) { loadSel(box, 'material_id', function () { return rpc('app_material_list', { p_token: tok() }); }, function (x) { return x.id; }, function (x) { return (x.code ? x.code + ' · ' : '') + (x.name || ''); }, d.material_id); },
          validate: function (d) { if (!d.material_id) return 'Выберите материал'; } },
        { title: 'Размещение',
          html: function (d) {
            return fsel('Адрес <span class="wz-req">*</span>', 'location_id', d, '<option value="">загрузка…</option>') +
              fi('Количество <span class="wz-req">*</span>', 'qty', d, 'type="number" min="0" step="any"') +
              fi('Цена', 'price', d, 'type="number" min="0" step="any"') + fi('Поставщик', 'supplier', d);
          },
          onShow: function (box, d) { loadSel(box, 'location_id', function () { return rpc('app_wh_address_list', { p_token: tok() }); }, function (x) { return x.id; }, function (x) { return x.code || ((x.zone || '') + '/' + (x.cell || '')); }, d.location_id); },
          validate: function (d) { if (!d.location_id) return 'Выберите адрес'; if (!(Number(d.qty) > 0)) return 'Укажите количество > 0'; } }
      ],
      onSubmit: function (d) { return call('app_wh_place', { p_token: tok(), p_material_id: d.material_id, p_location_id: d.location_id, p_lot: d.lot || null, p_qty: num(d.qty), p_price: num(d.price) || 0, p_supplier: d.supplier || null }); }
    },
    workflow: {
      icon: '⚙️', title: 'Мастер: запуск процесса', startLabel: '＋ Запустить процесс (мастер)', submitText: 'Запустить', doneText: 'Процесс запущен',
      steps: [
        { title: 'Процесс',
          html: function (d) { return fsel('Процесс <span class="wz-req">*</span>', 'def_id', d, '<option value="">загрузка…</option>'); },
          onShow: function (box, d) { loadSel(box, 'def_id', function () { return rpc('app_process_defs_list', { p_token: tok() }); }, function (x) { return x.id; }, function (x) { return (x.name || '') + (x.code ? ' (' + x.code + ')' : ''); }, d.def_id); },
          validate: function (d) { if (!d.def_id) return 'Выберите процесс'; } },
        { title: 'Предмет', html: function (d) { return fi('Название / предмет', 'entity_title', d) + fi('Комментарий', 'note', d); } }
      ],
      onSubmit: function (d) { return call('app_process_start', { p_token: tok(), p_def_id: d.def_id, p_entity_type: null, p_entity_id: null, p_entity_title: d.entity_title || null, p_data: null }); }
    },
    kedo: {
      icon: '🧑‍💼', title: 'Мастер: кадровый документ', startLabel: '＋ Кадровый документ (мастер)', submitText: 'Создать', doneText: 'Кадровый документ создан',
      steps: [
        { title: 'Документ',
          html: function (d) {
            return fsel('Тип', 'doc_type', d, sel([['order', 'Приказ'], ['hire', 'Приём'], ['transfer', 'Перевод'], ['dismiss', 'Увольнение'], ['vacation', 'Отпуск'], ['sick', 'Больничный'], ['ack', 'Ознакомление']], d.doc_type || 'order')) +
              fi('Сотрудник (логин) <span class="wz-req">*</span>', 'employee', d) + fi('Название <span class="wz-req">*</span>', 'title', d);
          },
          validate: function (d) { if (!d.employee) return 'Укажите сотрудника'; if (!d.title) return 'Укажите название'; } },
        { title: 'Проверка', hint: 'Документ будет создан черновиком.',
          html: function (d) { return '<div class="note">Сотрудник: <b>' + esc(d.employee || '') + '</b><br>Тип: ' + esc(d.doc_type || '') + '<br>Название: ' + esc(d.title || '') + '</div>'; } }
      ],
      onSubmit: function (d) { return call('app_hr_doc_save', { p_token: tok(), p_id: null, p_employee: d.employee, p_doc_type: d.doc_type || 'order', p_title: d.title, p_payload: null }); }
    },
    logistics: {
      icon: '🚚', title: 'Мастер: заявка на перевозку', startLabel: '＋ Заявка на перевозку (мастер)', submitText: 'Создать', doneText: 'Заявка на перевозку создана',
      steps: [
        { title: 'Направление и груз',
          html: function (d) {
            return fsel('Направление', 'direction', d, sel([['out', 'Отгрузка'], ['in', 'Доставка']], d.direction || 'out')) +
              fi('Контрагент', 'counterparty', d) + fi('Груз <span class="wz-req">*</span>', 'cargo', d) + fi('Вес, кг', 'weight', d, 'type="number" min="0" step="any"');
          },
          validate: function (d) { if (!d.cargo) return 'Укажите груз'; } },
        { title: 'Маршрут',
          html: function (d) { return fi('Откуда', 'from_loc', d) + fi('Куда <span class="wz-req">*</span>', 'to_loc', d) + fi('Погрузка', 'pickup', d, 'type="date"') + fi('Выгрузка', 'deliver', d, 'type="date"'); },
          validate: function (d) { if (!d.to_loc) return 'Укажите пункт назначения'; } },
        { title: 'Транспорт и стоимость', html: function (d) { return fi('ТС', 'vehicle', d) + fi('Водитель', 'driver', d) + fi('Стоимость', 'cost', d, 'type="number" min="0" step="any"') + fi('Примечание', 'note', d); } }
      ],
      onSubmit: function (d) { return call('app_transport_save', { p_token: tok(), p_id: null, p_number: null, p_direction: d.direction || 'out', p_counterparty: d.counterparty || null, p_cargo: d.cargo, p_weight: num(d.weight), p_from: d.from_loc || null, p_to: d.to_loc, p_pickup: d.pickup || null, p_deliver: d.deliver || null, p_carrier_id: null, p_vehicle: d.vehicle || null, p_driver: d.driver || null, p_cost: num(d.cost), p_note: d.note || null }); }
    }
  };

  function moduleId() { return (location.pathname.match(/\/apps\/([\w-]+)\//) || [])[1]; }

  function inject() {
    var m = moduleId(), spec = SPECS[m];
    if (!spec || document.querySelector('[data-wizard]')) return;
    var main = document.querySelector('main.wrap') || document.querySelector('main');
    if (!main) return;
    var bar = document.createElement('div'); bar.className = 'sv-actions'; bar.style.cssText = 'margin:0 0 12px;';
    var b = document.createElement('button');
    b.className = 'btn'; b.type = 'button'; b.setAttribute('data-wizard', m);
    b.textContent = spec.startLabel || ('＋ ' + spec.title);
    bar.appendChild(b); main.insertBefore(bar, main.firstChild);
  }

  function open(mod) {
    var spec = SPECS[mod]; if (!spec || !g.AppWizard) return;
    g.AppWizard.open({
      id: mod, icon: spec.icon, title: spec.title, submitText: spec.submitText, doneText: spec.doneText,
      steps: spec.steps, onSubmit: spec.onSubmit,
      onDone: function () { setTimeout(function () { location.reload(); }, 500); }
    });
  }

  function bind() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-wizard]'), function (b) {
      if (b.__wzBound) return; b.__wzBound = true;
      b.addEventListener('click', function () { open(b.getAttribute('data-wizard')); });
    });
  }
  function start() { inject(); bind(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
  g.AppWizards = { specs: SPECS, open: open, bind: bind };
})(window);
