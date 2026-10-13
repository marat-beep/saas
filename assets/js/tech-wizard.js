/* ============================================================
   3DMP Service · tech-wizard.js (v5) — «Мастер техпроцесса» (мощный).
   • Поисковые селекты (AppUI.comboHtml/initCombos) с иконками.
   • Корректировка норм по массе детали (app_weight_factor).
   • Опции: оснастка (проектирование+изготовление), электроды, прототип.
   • Просмотр МК/ОК/ВО в окне (без немедленной печати) + печать.
     window.AppTechWizard.open({ token, onDone })
   ============================================================ */
(function (g) {
  'use strict';
  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }
  function toast(t, k) { if (g.AppUI && g.AppUI.toast) g.AppUI.toast(t, k); }
  function num(v) { return Number(v) || 0; }
  function rpc(n, a) { return g.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cb(name, label, on) { return '<label style="display:flex;gap:8px;align-items:center;font-weight:600;"><input type="checkbox" name="' + name + '" style="width:auto;flex:0 0 auto;" ' + (on ? 'checked' : '') + '> ' + label + '</label>'; }
  function combo(name, opts, sel, ph) { return g.AppUI.comboHtml(name, opts, sel, ph); }

  var SHAPE_ICON = { 'Тело вращения': '🌀', 'Диск/плита': '💿', 'Диск': '💿', 'Корпус': '🧱', 'Плоская': '▱', 'Сложная 3D': '🧩', 'Круг': '⚪', 'Квадрат': '◼', 'Плита': '▭' };
  function shapeIcon(s) { return SHAPE_ICON[s] || '⚙'; }
  function opIcon(op) {
    var o = (op || '').toLowerCase();
    if (/заготов|резка|отрез/.test(o)) return '✂️';
    if (/токар/.test(o)) return '🔩';
    if (/фрез/.test(o)) return '🌀';
    if (/сверл|резьб|расточ/.test(o)) return '🔧';
    if (/шлиф|хонинг|притир|полир|доводк/.test(o)) return '✨';
    if (/зуб/.test(o)) return '⚙️';
    if (/термо|закал|цемент|азот|отжиг|твч/.test(o)) return '🔥';
    if (/сварк|пайк/.test(o)) return '🔥';
    if (/контроль|измер|ким|отк/.test(o)) return '📏';
    if (/гибк|штамп|прав/.test(o)) return '🧲';
    if (/зачист|слесар|сборк|маркир|снятие/.test(o)) return '🧰';
    if (/ээо|эрозион|electro/.test(o)) return '⚡';
    if (/гравир/.test(o)) return '🖊';
    if (/оснастк|проектир/.test(o)) return '📐';
    if (/электрод/.test(o)) return '🔌';
    return '•';
  }

  var ESTD = { mk: 'app_route_mk', ok: 'app_route_ok', vo: 'app_route_vo' };
  var ESTD_HEAD = { mk: 'МАРШРУТНАЯ КАРТА (ГОСТ 3.1118-82)', ok: 'ОПЕРАЦИОННАЯ КАРТА (ОК, ГОСТ 3.1404-86)', vo: 'ВЕДОМОСТЬ ОСНАСТКИ (ВО, ГОСТ 3.1130-93)' };
  function formatEstd(kind, rows) {
    return rows.map(function (s) {
      if (kind === 'vo') return s.seq + '. [' + (s.kind || '') + '] ' + (s.designation || '') + ' — ' + (s.name || '') + (s.standard ? ' (' + s.standard + ')' : '') + ' ×' + num(s.qty) + (s.note ? ' | ' + s.note : '');
      if (kind === 'ok') return s.seq + '. ' + s.operation + ' | ' + (s.equipment || '—') + ' | Тпз ' + num(s.setup_min) + ' | Тшт ' + num(s.unit_min) + ' | план ' + num(s.plan_min) + ' мин' + (s.note ? ' | ' + s.note : '');
      return s.seq + '. ' + s.operation + ' | ' + (s.equipment || '—') + ' | ' + num(s.plan_min) + ' мин' + (s.note ? ' | ' + s.note : '');
    }).join('\n');
  }
  function printText(title, text) {
    var w = window.open('', '_blank'); if (!w) { toast('Разрешите всплывающие окна', 'err'); return; }
    w.document.write('<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>' + esc(title) + '</title></head><body style="font:13px/1.5 Consolas,monospace;white-space:pre-wrap;padding:24px;">' + esc(text) + '</body></html>');
    w.document.close(); w.focus(); w.print();
  }

  function offerEstd(ctx, x) {
    if (!x || !x.route_id || !g.AppUI || !g.AppUI.dialog) return;
    ctx.lastRoute = x.route_number;
    var html = '<p class="note">Создано: ' + esc(x.message || '') + '</p>' +
      '<div class="btn-row" style="margin-bottom:8px;"><button class="act" data-view="mk">📄 МК</button><button class="act" data-view="ok">📄 ОК</button><button class="act" data-view="vo">📄 ВО</button><button class="btn" id="estdPrint" style="width:auto;padding:8px 14px;">🖨 Печать</button></div>' +
      '<pre id="estdView" style="max-height:340px;overflow:auto;background:#f8fafc;border:1px solid var(--border);border-radius:10px;padding:12px;font:12px/1.5 Consolas,monospace;white-space:pre-wrap;">Выберите документ: МК / ОК / ВО — откроется предпросмотр (без печати).</pre>';
    g.AppUI.dialog({ title: 'Документы ЕСТД — предпросмотр', body: html, html: true, cancelText: 'Закрыть' });
    var area = document.getElementById('estdView');
    Array.prototype.forEach.call(document.querySelectorAll('[data-view]'), function (b) {
      b.addEventListener('click', function () {
        var kind = b.dataset.view; area.textContent = 'Загрузка…';
        rpc(ESTD[kind], { p_token: ctx.token, p_id: x.route_id }).then(function (rows) {
          area.textContent = ESTD_HEAD[kind] + '\n' + (ctx.lastTitleValue || '') + ' · ' + (ctx.lastRoute || '') + '\n\n' + formatEstd(kind, rows || []);
          area.scrollTop = 0;
        }).catch(function (e) { area.textContent = 'Ошибка: ' + e.message; });
      });
    });
    var pr = document.getElementById('estdPrint');
    if (pr) pr.addEventListener('click', function () { printText((ctx.lastTitleValue || '') + ' ' + (ctx.lastRoute || ''), area.textContent); });
  }

  function open(opts) {
    opts = opts || {};
    var ctx = { token: opts.token };
    if (!ctx.token) { toast('Нет сессии', 'err'); return; }
    if (!g.AppWizard || !g.AppUI || !g.AppUI.comboHtml) { toast('Компоненты мастера не подключены', 'err'); return; }
    var parts = [], mats = [], ops = [];
    Promise.all([
      rpc('app_tech_wizard_options', { p_token: ctx.token, p_kind: 'part' }).catch(function () { return []; }),
      rpc('app_tech_wizard_options', { p_token: ctx.token, p_kind: 'material' }).catch(function () { return []; }),
      rpc('app_tech_wizard_options', { p_token: ctx.token, p_kind: 'operation' }).catch(function () { return []; })
    ]).then(function (r) {
      parts = (r[0] || []).map(function (x) { return { value: x.code, label: x.name, info: x.info, icon: shapeIcon((x.info || '').split(' · ')[0]) }; });
      mats = (r[1] || []).map(function (x) { return { value: x.code, label: x.name, info: x.info, icon: '🧪' }; });
      ops = (r[2] || []).map(function (x) { return { value: x.code, label: x.name, info: x.info, icon: opIcon(x.name) }; });
      if (!parts.length) { toast('Нет типовых маршрутов — заполните «Справочники → Типовые маршруты»', 'err'); return; }

      function renderPreview(box, d) {
        var host = box.querySelector('#twPv'); if (!host) return;
        if (!d.code) { host.innerHTML = '<span class="note">Выберите тип детали на шаге 1.</span>'; return; }
        host.innerHTML = '<span class="note">Загрузка…</span>';
        Promise.all([
          rpc('app_tech_wizard_preview', { p_token: ctx.token, p_code: d.code }).catch(function () { return []; }),
          rpc('app_tech_route_variants', { p_token: ctx.token, p_code: d.code }).catch(function () { return []; }),
          d.weight ? rpc('app_weight_factor', { p_token: ctx.token, p_kg: Number(d.weight) }).catch(function () { return 1; }) : Promise.resolve(1)
        ]).then(function (res) {
          var rows = res[0] || [], vars = res[1] || [], wf = Number(res[2]) || 1;
          var total = rows.reduce(function (a, s) { return a + num(s.unit_min); }, 0);
          var qty = d.qty ? Number(d.qty) : 1;
          var sel = '<label>Вариант техпроцесса</label>' + g.AppUI.comboHtml('variant', vars.map(function (v) { return { value: v.code, label: v.code + ' · ' + v.name, info: (v.shape || '') + ' · ' + (v.material || '') + ' · ' + v.steps + ' оп.', icon: shapeIcon(v.shape) }; }), null, 'поиск варианта…');
          host.innerHTML = (vars.length ? sel : '') +
            '<div class="wz-pv"><table class="mini mt"><thead><tr><th class="num">№</th><th>Операция</th><th>Оборудование</th><th>Требования</th><th class="num">Норма, мин/шт</th></tr></thead><tbody>' +
            rows.map(function (s, i) { return '<tr><td class="num">' + (i + 1) + '</td><td>' + opIcon(s.operation) + ' ' + esc(s.operation) + '</td><td>' + esc(s.equipment) + '</td><td>' + esc(s.note || '') + '</td><td class="num">' + num(s.unit_min) + '</td></tr>'; }).join('') +
            '</tbody><tfoot><tr><td colspan="4" style="text-align:right;color:var(--muted);">Итого на 1 шт × партия ' + qty + ' × коэф. веса ' + wf + ':</td><td class="num"><b>' + Math.round(total * qty * wf) + ' мин</b></td></tr></tfoot></table></div>';
          g.AppUI.initCombos(box);
          var vs = box.querySelector('[data-combo-wrap] [data-combo]');
          var vhid = box.querySelector('[data-combo-wrap] input[type=hidden]');
          if (vhid) {
            var pane = box.querySelector('[data-combo-wrap] .ac-panel');
            if (pane) pane.addEventListener('mousedown', function () { setTimeout(function () { if (vhid.value) { d.code = vhid.value; renderPreview(box, d); } }, 0); });
          }
        }).catch(function (e) { host.innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
      }

      g.AppWizard.open({
        id: 'techwiz', title: 'Мастер техпроцесса', icon: '🧭', submitText: 'Создать', doneText: 'Техпроцесс создан',
        steps: [
          { title: '1. Тип детали', hint: 'Найдите тип (вал, фланец, корпус…) — подберётся типовой маршрут.',
            html: function (d) { return '<label>Тип детали <span class="wz-req">*</span></label>' + combo('code', parts, d.code, 'поиск: вал, фланец, корпус…'); },
            onShow: function (box) { g.AppUI.initCombos(box); },
            validate: function (d) { return d.code ? null : 'Выберите тип детали'; } },
          { title: '2. Материал, партия и масса', hint: 'Масса влияет на норму времени (коэффициент).',
            html: function (d) {
              return '<label>Материал</label>' + combo('material', mats, d.material, 'поиск: сталь, алюминий, Д16Т…') +
                '<label>Количество, шт</label><input name="qty" type="number" min="1" value="' + esc(d.qty || 1) + '">' +
                '<label>Масса детали, кг</label><input name="weight" type="number" min="0" step="0.1" value="' + esc(d.weight || '') + '" placeholder="напр. 12.5">';
            },
            onShow: function (box) { g.AppUI.initCombos(box); } },
          { title: '3. Предлагаемый техпроцесс', hint: 'Проверьте состав, нормы и при необходимости выберите вариант.',
            html: function () { return '<div id="twPv"><span class="note">Выберите тип детали на шаге 1.</span></div>'; },
            onShow: function (box, d) { renderPreview(box, d); } },
          { title: '4. Вид обработки и опции', hint: 'Уточняющая операция и дополнительные работы.',
            html: function (d) {
              return '<label>Уточняющая операция</label>' + combo('operation', ops, d.operation, 'поиск: хонингование, зубофрезерование…') +
                '<label style="margin-top:8px;">Дополнительно</label>' +
                cb('ex_tooling', '📐 Нужна оснастка (проектирование + задание на изготовление)', d.ex_tooling) +
                cb('ex_electrodes', '🔌 Нужны электроды (для прошивной ЭЭО)', d.ex_electrodes) +
                cb('ex_prototype', '🧩 Изготовление прототипа', d.ex_prototype);
            },
            onShow: function (box) { g.AppUI.initCombos(box); } },
          { title: '5. Записи и документы', hint: 'Мастер создаст маршрут, наряд и техкарту; далее — предпросмотр МК/ОК/ВО.',
            html: function (d) {
              return '<label>Название техпроцесса <span class="wz-req">*</span></label><input name="title" value="' + esc(d.title || '') + '">' +
                '<label>Срок наряда</label><input name="due" type="date" value="' + esc(d.due || '') + '">' +
                cb('make_naryad', 'Создать наряд', d.make_naryad !== false) + cb('make_doc', 'Создать документ (техкарта)', d.make_doc !== false);
            },
            validate: function (d) { return d.title ? null : 'Укажите название техпроцесса'; } }
        ],
        onSubmit: function (d) {
          ctx.lastTitleValue = d.title;
          var extras = [];
          if (d.ex_tooling) extras.push('tooling');
          if (d.ex_electrodes) extras.push('electrodes');
          if (d.ex_prototype) extras.push('prototype');
          return rpc('app_tech_wizard_run', {
            p_token: ctx.token, p_code: d.code, p_title: d.title, p_material: d.material || null,
            p_qty: d.qty ? Number(d.qty) : 1, p_due: d.due || null,
            p_make_naryad: d.make_naryad !== false, p_make_doc: d.make_doc !== false,
            p_operation: d.operation || null, p_weight: d.weight ? Number(d.weight) : null,
            p_extras: extras.length ? extras : null
          }).then(function (r) {
            var x = r && r[0];
            if (!x || x.ok === false) return (x && x.message) || 'Не удалось создать техпроцесс';
            toast(x.message || 'Готово', 'ok');
            offerEstd(ctx, x);
            if (opts.onDone) { try { opts.onDone(x); } catch (e) {} }
            return null;
          });
        }
      });
    }).catch(function (e) { toast('Ошибка: ' + e.message, 'err'); });
  }

  g.AppTechWizard = { open: open };
})(window);
