/* ============================================================
   3DMP Service · tech-wizard.js (v1) — «Мастер техпроцесса».
   Пошаговый подбор технологии (AppWizard) с автосозданием записей и
   документов через app_tech_wizard_run. Использование:
     window.AppTechWizard.open({ token: '<session-token>', onDone: fn })
   ============================================================ */
(function (g) {
  'use strict';
  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }
  function rpc(n, a) { return g.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function optionsHtml(list, name, sel, emptyLabel) {
    return '<select name="' + name + '"><option value="">' + esc(emptyLabel || '— выберите —') + '</option>' +
      (list || []).map(function (x) {
        return '<option value="' + esc(x.code) + '"' + (sel && String(x.code) === String(sel) ? ' selected' : '') + '>' +
          esc(x.name) + (x.info ? ' · ' + esc(x.info) : '') + '</option>';
      }).join('') + '</select>';
  }

  function open(opts) {
    opts = opts || {};
    var token = opts.token;
    if (!token) { if (g.AppUI) g.AppUI.toast('Нет сессии', 'err'); return; }
    if (!g.AppWizard) { if (g.AppUI) g.AppUI.toast('Движок мастера не подключён', 'err'); return; }
    var parts = [], mats = [], ops = [];
    Promise.all([
      rpc('app_tech_wizard_options', { p_token: token, p_kind: 'part' }).catch(function () { return []; }),
      rpc('app_tech_wizard_options', { p_token: token, p_kind: 'material' }).catch(function () { return []; }),
      rpc('app_tech_wizard_options', { p_token: token, p_kind: 'operation' }).catch(function () { return []; })
    ]).then(function (r) {
      parts = r[0] || []; mats = r[1] || []; ops = r[2] || [];
      if (!parts.length) { if (g.AppUI) g.AppUI.toast('Нет типовых маршрутов — заполните «Справочники → Типовые маршруты»', 'err'); return; }
      g.AppWizard.open({
        id: 'techwiz', title: 'Мастер техпроцесса', icon: '🧭', submitText: 'Создать', doneText: 'Техпроцесс создан',
        steps: [
          {
            title: '1. Тип детали', hint: 'Выберите типовую деталь — под неё подберётся типовой маршрут.',
            html: function (d) { return '<label>Тип детали <span class="wz-req">*</span></label>' + optionsHtml(parts, 'code', d.code); },
            validate: function (d) { return d.code ? null : 'Выберите тип детали'; }
          },
          {
            title: '2. Материал и партия', hint: 'Материал — из справочника; партия учитывается при создании.',
            html: function (d) {
              return '<label>Материал</label>' + optionsHtml(mats, 'material', d.material) +
                '<label>Количество, шт</label><input name="qty" type="number" min="1" step="1" value="' + esc(d.qty || 1) + '">';
            }
          },
          {
            title: '3. Вид обработки (уточнение)', hint: 'Ключевая операция добавится в маршрут, если её нет. Необязательно.',
            html: function (d) { return '<label>Операция</label>' + optionsHtml(ops, 'operation', d.operation, '— без уточнения —'); }
          },
          {
            title: '4. Записи и документы', hint: 'Мастер создаст маршрут, при необходимости — наряд и техкарту.',
            html: function (d) {
              return '<label>Название техпроцесса <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
                '<label>Срок наряда</label><input name="due" type="date" value="' + esc(d.due || '') + '">' +
                '<label style="display:flex;gap:8px;align-items:center;"><input type="checkbox" name="make_naryad" ' + (d.make_naryad !== false ? 'checked' : '') + '> Создать наряд</label>' +
                '<label style="display:flex;gap:8px;align-items:center;"><input type="checkbox" name="make_doc" ' + (d.make_doc !== false ? 'checked' : '') + '> Создать документ (техкарта)</label>';
            },
            validate: function (d) { return d.title ? null : 'Укажите название техпроцесса'; }
          }
        ],
        onSubmit: function (d) {
          return rpc('app_tech_wizard_run', {
            p_token: token, p_code: d.code, p_title: d.title, p_material: d.material || null,
            p_qty: d.qty ? Number(d.qty) : 1, p_due: d.due || null,
            p_make_naryad: d.make_naryad !== false, p_make_doc: d.make_doc !== false,
            p_operation: d.operation || null
          }).then(function (r) {
            var x = r && r[0];
            if (!x || x.ok === false) return (x && x.message) || 'Не удалось создать техпроцесс';
            if (g.AppUI) g.AppUI.toast(x.message || 'Готово', 'ok');
            if (opts.onDone) { try { opts.onDone(x); } catch (e) {} }
            return null;
          });
        }
      });
    }).catch(function (e) { if (g.AppUI) g.AppUI.toast('Ошибка: ' + e.message, 'err'); });
  }

  g.AppTechWizard = { open: open };
})(window);
