/* ============================================================
   3DMP Service · tech-wizard.js (v2) — «Мастер техпроцесса».
   Пошаговый подбор технологии (AppWizard) с предпросмотром техпроцесса,
   автосозданием записей/документов (app_tech_wizard_run) и печатью ЕСТД.
     window.AppTechWizard.open({ token, onDone })
   ============================================================ */
(function (g) {
  'use strict';
  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }
  function toast(t, k) { if (g.AppUI && g.AppUI.toast) g.AppUI.toast(t, k); }
  function num(v) { return Number(v) || 0; }
  function rpc(n, a) { return g.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function optionsHtml(list, name, sel, emptyLabel) {
    return '<select name="' + name + '"><option value="">' + esc(emptyLabel || '— выберите —') + '</option>' +
      (list || []).map(function (x) {
        return '<option value="' + esc(x.code) + '"' + (sel && String(x.code) === String(sel) ? ' selected' : '') + '>' +
          esc(x.name) + (x.info ? ' · ' + esc(x.info) : '') + '</option>';
      }).join('') + '</select>';
  }
  function cb(name, label, on) { return '<label style="display:flex;gap:8px;align-items:center;font-weight:600;"><input type="checkbox" name="' + name + '" style="width:auto;flex:0 0 auto;" ' + (on ? 'checked' : '') + '> ' + label + '</label>'; }

  function printEstd(ctx, kind, id) {
    var map = { mk: 'app_route_mk', ok: 'app_route_ok', vo: 'app_route_vo' };
    var head = { mk: 'МАРШРУТНАЯ КАРТА (ГОСТ 3.1118-82)', ok: 'ОПЕРАЦИОННАЯ КАРТА (ОК, ГОСТ 3.1404-86)', vo: 'ВЕДОМОСТЬ ОСНАСТКИ (ВО, ГОСТ 3.1130-93)' };
    rpc(map[kind], { p_token: ctx.token, p_id: id }).then(function (rows) {
      rows = rows || [];
      var body = head[kind] + '\n' + (ctx.lastTitle || '') + (ctx.lastRoute ? ' · ' + ctx.lastRoute : '') + '\n\n' + rows.map(function (s) {
        if (kind === 'vo') return s.seq + '. [' + (s.kind || '') + '] ' + (s.designation || '') + ' — ' + (s.name || '') + (s.standard ? ' (' + s.standard + ')' : '') + ' ×' + num(s.qty);
        if (kind === 'ok') return s.seq + '. ' + s.operation + ' | ' + (s.equipment || '—') + ' | Тпз ' + num(s.setup_min) + ' | Тшт ' + num(s.unit_min) + ' | план ' + num(s.plan_min) + ' мин' + (s.note ? ' | ' + s.note : '');
        return s.seq + '. ' + s.operation + ' | ' + (s.equipment || '—') + ' | ' + num(s.plan_min) + ' мин' + (s.note ? ' | ' + s.note : '');
      }).join('\n');
      var w = window.open('', '_blank'); if (!w) { toast('Разрешите всплывающие окна', 'err'); return; }
      w.document.write('<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>' + esc(kind.toUpperCase()) + '</title></head><body style="font:13px/1.5 Consolas,monospace;white-space:pre-wrap;padding:24px;">' + esc(body) + '</body></html>');
      w.document.close(); w.focus(); w.print();
    }).catch(function (e) { toast('Ошибка печати: ' + e.message, 'err'); });
  }

  function offerPrint(ctx, x) {
    if (!x || !x.route_id) return;
    ctx.lastRoute = x.route_number; ctx.lastTitle = ctx.lastTitleValue || '';
    if (!g.AppUI || !g.AppUI.dialog) return;
    var html = '<p class="note">Создано: ' + esc(x.message || '') + '</p><div class="btn-row">' +
      '<button class="btn secondary" data-p="mk">🖨 МК</button><button class="btn secondary" data-p="ok">🖨 ОК</button>' +
      '<button class="btn secondary" data-p="vo">🖨 ВО</button></div>';
    g.AppUI.dialog({ title: 'Документы ЕСТД', body: html, html: true, cancelText: 'Закрыть' });
    Array.prototype.forEach.call(document.querySelectorAll('[data-p]'), function (b) {
      b.addEventListener('click', function () { printEstd(ctx, b.dataset.p, x.route_id); });
    });
  }

  function open(opts) {
    opts = opts || {};
    var ctx = { token: opts.token };
    if (!ctx.token) { toast('Нет сессии', 'err'); return; }
    if (!g.AppWizard) { toast('Движок мастера не подключён', 'err'); return; }
    var parts = [], mats = [], ops = [];
    Promise.all([
      rpc('app_tech_wizard_options', { p_token: ctx.token, p_kind: 'part' }).catch(function () { return []; }),
      rpc('app_tech_wizard_options', { p_token: ctx.token, p_kind: 'material' }).catch(function () { return []; }),
      rpc('app_tech_wizard_options', { p_token: ctx.token, p_kind: 'operation' }).catch(function () { return []; })
    ]).then(function (r) {
      parts = r[0] || []; mats = r[1] || []; ops = r[2] || [];
      if (!parts.length) { toast('Нет типовых маршрутов — заполните «Справочники → Типовые маршруты»', 'err'); return; }
      g.AppWizard.open({
        id: 'techwiz', title: 'Мастер техпроцесса', icon: '🧭', submitText: 'Создать', doneText: 'Техпроцесс создан',
        steps: [
          { title: '1. Тип детали', hint: 'Типовая деталь → подбирается типовой маршрут.',
            html: function (d) { return '<label>Тип детали <span class="wz-req">*</span></label>' + optionsHtml(parts, 'code', d.code); },
            validate: function (d) { return d.code ? null : 'Выберите тип детали'; } },
          { title: '2. Материал и партия', html: function (d) {
              return '<label>Материал</label>' + optionsHtml(mats, 'material', d.material) +
                '<label>Количество, шт</label><input name="qty" type="number" min="1" step="1" value="' + esc(d.qty || 1) + '">';
            } },
          { title: '3. Предлагаемый техпроцесс', hint: 'Проверьте состав операций перед созданием.',
            html: function () { return '<div id="twPv"><span class="note">Выберите тип детали на шаге 1.</span></div>'; },
            onShow: function (box, d) {
              var host = box.querySelector('#twPv'); if (!host) return;
              if (!d.code) { host.innerHTML = '<span class="note">Выберите тип детали на шаге 1.</span>'; return; }
              host.innerHTML = '<span class="note">Загрузка…</span>';
              rpc('app_tech_wizard_preview', { p_token: ctx.token, p_code: d.code }).then(function (rows) {
                rows = rows || [];
                var total = rows.reduce(function (a, s) { return a + num(s.unit_min); }, 0);
                host.innerHTML = rows.length ? '<table class="mini"><thead><tr><th class="num">№</th><th>Операция</th><th>Оборудование</th><th>Требования</th><th class="num">Норма, мин/шт</th></tr></thead><tbody>' +
                  rows.map(function (s, i) { return '<tr><td class="num">' + (i + 1) + '</td><td>' + esc(s.operation) + '</td><td>' + esc(s.equipment) + '</td><td>' + esc(s.note || '') + '</td><td class="num">' + num(s.unit_min) + '</td></tr>'; }).join('') +
                  '</tbody><tfoot><tr><td colspan="4" style="text-align:right;color:var(--muted);">Итого на 1 шт:</td><td class="num"><b>' + total + '</b></td></tr></tfoot></table>'
                  : '<span class="note">Состав не задан в типовом маршруте.</span>';
              }).catch(function (e) { host.innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
            } },
          { title: '4. Вид обработки (уточнение)', hint: 'Ключевая операция добавится в маршрут, если её нет. Необязательно.',
            html: function (d) { return '<label>Операция</label>' + optionsHtml(ops, 'operation', d.operation, '— без уточнения —'); } },
          { title: '5. Записи и документы', hint: 'Мастер создаст маршрут, при необходимости — наряд и техкарту.',
            html: function (d) {
              return '<label>Название техпроцесса <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
                '<label>Срок наряда</label><input name="due" type="date" value="' + esc(d.due || '') + '">' +
                cb('make_naryad', 'Создать наряд', d.make_naryad !== false) + cb('make_doc', 'Создать документ (техкарта)', d.make_doc !== false);
            },
            validate: function (d) { return d.title ? null : 'Укажите название техпроцесса'; } }
        ],
        onSubmit: function (d) {
          ctx.lastTitleValue = d.title;
          return rpc('app_tech_wizard_run', {
            p_token: ctx.token, p_code: d.code, p_title: d.title, p_material: d.material || null,
            p_qty: d.qty ? Number(d.qty) : 1, p_due: d.due || null,
            p_make_naryad: d.make_naryad !== false, p_make_doc: d.make_doc !== false,
            p_operation: d.operation || null
          }).then(function (r) {
            var x = r && r[0];
            if (!x || x.ok === false) return (x && x.message) || 'Не удалось создать техпроцесс';
            toast(x.message || 'Готово', 'ok');
            offerPrint(ctx, x);
            if (opts.onDone) { try { opts.onDone(x); } catch (e) {} }
            return null;
          });
        }
      });
    }).catch(function (e) { toast('Ошибка: ' + e.message, 'err'); });
  }

  g.AppTechWizard = { open: open };
})(window);
