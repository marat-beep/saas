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
      '.mtiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:12px}' +
      '.mtile{text-align:left;border:1px solid var(--border);border-radius:14px;background:#fff;padding:14px 16px;cursor:pointer;transition:.15s;display:flex;flex-direction:column;gap:6px}' +
      '.mtile:hover{border-color:var(--accent,#10b981);box-shadow:0 8px 22px rgba(16,185,129,.14);transform:translateY(-1px)}' +
      '.mtile .mi{font-size:1.25rem}.mtile b{font-size:.92rem}.mtile .md{font-size:.78rem;color:var(--muted,#64748b)}' +
      '.mhead{display:flex;align-items:center;gap:8px;margin-bottom:8px}.mhead h2{margin:0;font-size:1.02rem}.mhead .note{margin-left:auto;font-size:.75rem;color:var(--muted)}';
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
          { title: '2. Материал и партия', html: function (d) { return '<label>Материал</label>' + opts(mats, 'material', d.material) + '<label>Количество, шт</label><input name="qty" type="number" min="1" value="' + esc(d.qty || 1) + '">'; } },
          { title: '3. Уточняющая операция', hint: 'Необязательно — добавится в маршрут.', html: function (d) { return '<label>Операция</label>' + opts(ops, 'operation', d.operation, '— без уточнения —'); } },
          { title: '4. Задание, наряд и документ', html: function (d) {
              return '<label>Название <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
                '<label>Срок наряда</label><input name="due" type="date" value="' + esc(d.due || '') + '">' +
                '<label style="display:flex;gap:8px;align-items:center;"><input type="checkbox" name="make_naryad" ' + (d.make_naryad !== false ? 'checked' : '') + '> Наряд</label>' +
                '<label style="display:flex;gap:8px;align-items:center;"><input type="checkbox" name="make_tasks" ' + (d.make_tasks !== false ? 'checked' : '') + '> Сменно-суточное задание</label>' +
                '<label style="display:flex;gap:8px;align-items:center;"><input type="checkbox" name="make_doc" ' + (d.make_doc !== false ? 'checked' : '') + '> Документ-техкарта</label>';
            }, validate: function (d) { return d.title ? null : 'Укажите название'; } }
        ],
        onSubmit: function (d) {
          return rpc('app_master_manufacture', {
            p_token: ctx.token, p_code: d.code, p_title: d.title, p_material: d.material || null,
            p_qty: d.qty ? Number(d.qty) : 1, p_due: d.due || null, p_operation: d.operation || null,
            p_make_naryad: d.make_naryad !== false, p_make_tasks: d.make_tasks !== false, p_make_doc: d.make_doc !== false
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

  var DEFS = [
    { id: 'mfg', icon: '🧭', title: 'Деталь → техпроцесс → задание, наряд и документ', desc: 'Пошагово: тип детали, материал, партия, срок → маршрут, ССЗ, наряд, техкарта.', modules: ['registry', 'assistant', 'norms', 'production', 'planning', 'mes', 'docs'], run: openMfg },
    { id: 'doc', icon: '📄', title: 'Быстрый документ', desc: 'Создать КП/договор/акт/техкарту с автоматическим номером.', modules: ['docs', 'docbuilder', 'templates', 'registry', 'tkp'], run: openDoc },
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
