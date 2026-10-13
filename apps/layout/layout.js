/* ============================================================
   3DMP Service · apps/layout/layout.js — конструктор планировок.
   Расстановка оборудования (цех/офис/компрессорная/линия): палитра,
   SVG-редактор (перемещение/размер/поворот), стадии, сетка, зум,
   экспорт/импорт JSON, печать, сохранение проектов (app_layout_plan_*).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function toast(t, k) { ui.toast(t, k); }

  var token = null, planId = null, zoom = 1, snap = true, sel = null, items = [];
  var W = 24000, H = 14000, GRID = 100;
  var stage = 'new';
  var STAGES = { exist: { l: 'Действующее', c: '#94a3b8' }, 'new': { l: 'Новое', c: '#10b981' }, future: { l: 'Будущее', c: '#8b95a3' } };

  var TYPES = [
    { g: 'Станки и обработка', items: [
      { t: 'mill', n: 'ОЦ фрезерный', w: 3200, h: 2600, ic: '🌀' }, { t: 'lathe', n: 'ОЦ токарный', w: 2800, h: 1800, ic: '🔩' },
      { t: 'grind', n: 'Шлифовальный', w: 2600, h: 2000, ic: '✨' }, { t: 'edm', n: 'ЭЭО станок', w: 2200, h: 2000, ic: '⚡' },
      { t: 'press', n: 'Пресс', w: 2400, h: 2200, ic: '🧲' }, { t: 'saw', n: 'Ленточнопила', w: 2600, h: 1200, ic: '✂️' },
      { t: 'cmm', n: 'КИМ', w: 2000, h: 1600, ic: '📏' }, { t: 'bench', n: 'Верстак', w: 1600, h: 800, ic: '🧰' }
    ] },
    { g: 'Роботы и манипуляторы', items: [
      { t: 'robot6', n: 'Робот 6-осевой', w: 2500, h: 2500, ic: '🦾' }, { t: 'scara', n: 'Робот SCARA', w: 2200, h: 2200, ic: '🤖' },
      { t: 'delta', n: 'Дельта-робот', w: 2400, h: 2400, ic: '🎯' }, { t: 'pallet', n: 'Паллетизатор', w: 5200, h: 5200, ic: '📦' }
    ] },
    { g: 'Конвейеры и транспорт', items: [
      { t: 'conv', n: 'Конвейер прямой', w: 3000, h: 900, ic: '➡️' }, { t: 'turn', n: 'Поворотный', w: 2400, h: 2400, ic: '🔄' },
      { t: 'accum', n: 'Накопитель', w: 6000, h: 1400, ic: '📥' }, { t: 'agv', n: 'AGV/погрузчик', w: 2000, h: 1200, ic: '🛻' }
    ] },
    { g: 'Хранение и оснастка', items: [
      { t: 'rack', n: 'Стеллаж', w: 2700, h: 1100, ic: '🗄' }, { t: 'pallet', n: 'Паллета', w: 1200, h: 800, ic: '▭' },
      { t: 'cabinet', n: 'Шкаф', w: 1000, h: 600, ic: '🚪' }, { t: 'tool', n: 'Верстак оснастки', w: 1800, h: 800, ic: '🧰' }
    ] },
    { g: 'Инфраструктура', items: [
      { t: 'panel', n: 'Шкаф управления', w: 1200, h: 600, ic: '🔌' }, { t: 'compressor', n: 'Компрессор', w: 2200, h: 1400, ic: '🌬' },
      { t: 'receiver', n: 'Ресивер', w: 1400, h: 1400, ic: '🛢' }, { t: 'dryer', n: 'Осушитель', w: 1200, h: 900, ic: '💧' },
      { t: 'chiller', n: 'Чиллер', w: 1800, h: 1200, ic: '❄️' }, { t: 'col', n: 'Колонна/опора', w: 600, h: 600, ic: '⬛' }
    ] },
    { g: 'Офис и помещения', items: [
      { t: 'desk', n: 'Стол', w: 1600, h: 800, ic: '🪑' }, { t: 'meet', n: 'Переговорный стол', w: 3200, h: 1400, ic: '🗣' },
      { t: 'shelf', n: 'Шкаф/стеллаж', w: 2000, h: 500, ic: '🗄' }, { t: 'printer', n: 'Принтер', w: 700, h: 600, ic: '🖨' },
      { t: 'door', n: 'Дверь', w: 1000, h: 200, ic: '🚪' }, { t: 'wall', n: 'Перегородка', w: 3000, h: 150, ic: '🧱' }
    ] },
    { g: 'Зоны и безопасность', items: [
      { t: 'zone', n: 'Зона (безопасности)', w: 4000, h: 3000, ic: '⬜' }, { t: 'aisle', n: 'Проезд/проход', w: 2000, h: 6000, ic: '↔️' },
      { t: 'label', n: 'Подпись', w: 2400, h: 500, ic: '🏷' }
    ] }
  ];
  function typeDef(t) { for (var i = 0; i < TYPES.length; i++) for (var j = 0; j < TYPES[i].items.length; j++) if (TYPES[i].items[j].t === t) return TYPES[i].items[j]; return { t: t, n: t, w: 1200, h: 800, ic: '•' }; }
  function uid() { return 'i' + Date.now().toString(36) + Math.floor(Math.random() * 1000); }
  function snapv(v) { return snap ? Math.round(v / GRID) * GRID : Math.round(v); }

  /* ---------- отрисовка ---------- */
  function draw() {
    var svg = $('#cv');
    var vbW = W / zoom, vbH = H / zoom;
    svg.setAttribute('viewBox', '0 0 ' + vbW + ' ' + vbH);
    svg.setAttribute('width', vbW); svg.setAttribute('height', vbH);
    svg.style.width = vbW + 'px'; svg.style.height = vbH + 'px';
    var g = '';
    if (snap) {
      for (var x = 0; x <= W; x += GRID * 5) g += '<line x1="' + x + '" y1="0" x2="' + x + '" y2="' + H + '" stroke="#eef2f7" stroke-width="' + (GRID / 6) + '"/>';
      for (var y = 0; y <= H; y += GRID * 5) g += '<line x1="0" y1="' + y + '" x2="' + W + '" y2="' + y + '" stroke="#eef2f7" stroke-width="' + (GRID / 6) + '"/>';
    }
    svg.innerHTML = g + items.map(function (it) {
      var c = (STAGES[it.stage] || STAGES['new']).c, isz = it.type === 'zone' || it.type === 'aisle';
      return '<g class="li" data-id="' + it.id + '" transform="translate(' + it.x + ',' + it.y + ') rotate(' + (it.rot || 0) + ',' + (it.w / 2) + ',' + (it.h / 2) + ')">' +
        '<rect x="0" y="0" width="' + it.w + '" height="' + it.h + '" rx="' + (GRID / 2) + '" fill="' + (isz ? 'rgba(16,185,129,.08)' : c + '22') + '" stroke="' + c + '" stroke-width="' + (sel === it.id ? GRID / 2 : GRID / 4) + '"' + (isz ? ' stroke-dasharray="' + GRID / 2 + ' ' + GRID / 3 + '"' : '') + '/>' +
        '<text x="' + (it.w / 2) + '" y="' + (it.h / 2 - 40) + '" text-anchor="middle" font-size="' + Math.max(140, Math.min(it.w, it.h) / 6) + '" fill="#0f172a">' + esc(typeDef(it.type).ic) + '</text>' +
        '<text x="' + (it.w / 2) + '" y="' + (it.h / 2 + Math.max(240, Math.min(it.w, it.h) / 3)) + '" text-anchor="middle" font-size="' + Math.max(140, Math.min(it.w, it.h) / 9) + '" fill="#334155">' + esc(it.name) + '</text>' +
        (sel === it.id ? '<rect class="rz" x="' + (it.w - GRID) + '" y="' + (it.h - GRID) + '" width="' + (GRID * 1.6) + '" height="' + (GRID * 1.6) + '" fill="#10b981" stroke="#fff" stroke-width="20"/>' : '') +
        '</g>';
    }).join('');
    bind();
    var n = items.length, area = items.reduce(function (a, it) { return a + it.w * it.h; }, 0) / 1e6;
    $('#kpi').textContent = 'Элементов: ' + n + ' · площадь: ' + area.toFixed(2) + ' м²';
  }

  function bind() {
    $$('#cv .li').forEach(function (g) {
      g.addEventListener('mousedown', function (e) {
        if (e.target.classList.contains('rz')) return;
        var id = g.getAttribute('data-id'); sel = id; prop(); draw();
        var it = items.filter(function (x) { return x.id === id; })[0]; if (!it) return;
        var sx = e.clientX, sy = e.clientY, ox = it.x, oy = it.y, sc = (W / zoom) / $('#cv').clientWidth;
        function mv(ev) { it.x = snapv(ox + (ev.clientX - sx) * sc); it.y = snapv(oy + (ev.clientY - sy) * sc); draw(); }
        function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
        e.preventDefault();
      });
    });
    var rz = $('#cv .rz');
    if (rz) rz.addEventListener('mousedown', function (e) {
      var it = items.filter(function (x) { return x.id === sel; })[0]; if (!it) return;
      var sx = e.clientX, sy = e.clientY, ow = it.w, oh = it.h, sc = (W / zoom) / $('#cv').clientWidth;
      function mv(ev) { it.w = Math.max(GRID * 3, snapv(ow + (ev.clientX - sx) * sc)); it.h = Math.max(GRID * 3, snapv(oh + (ev.clientY - sy) * sc)); draw(); }
      function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); }
      document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
      e.preventDefault(); e.stopPropagation();
    });
  }

  /* ---------- панель свойств ---------- */
  function prop() {
    var it = items.filter(function (x) { return x.id === sel; })[0];
    if (!it) { $('#prop').innerHTML = '<span class="note">Выберите элемент на плане.</span>'; return; }
    $('#prop').innerHTML =
      '<label>Название</label><input id="pName" value="' + esc(it.name) + '">' +
      '<label>Стадия</label><select id="pStage">' + Object.keys(STAGES).map(function (k) { return '<option value="' + k + '"' + (it.stage === k ? ' selected' : '') + '>' + STAGES[k].l + '</option>'; }).join('') + '</select>' +
      '<label>X, мм</label><input id="pX" type="number" value="' + it.x + '"><label>Y, мм</label><input id="pY" type="number" value="' + it.y + '">' +
      '<label>Ширина, мм</label><input id="pW" type="number" value="' + it.w + '"><label>Высота, мм</label><input id="pH" type="number" value="' + it.h + '">' +
      '<div class="btn-row mt"><button class="btn secondary" id="pRot">↻ 90°</button><button class="btn secondary" id="pDup">⧉ Копия</button><button class="btn secondary" id="pDel">✕ Удалить</button></div>';
    $('#pName').addEventListener('input', function () { it.name = this.value; draw(); });
    $('#pStage').addEventListener('change', function () { it.stage = this.value; draw(); });
    ['pX:x', 'pY:y', 'pW:w', 'pH:h'].forEach(function (p) {
      var id = p.split(':')[0], k = p.split(':')[1];
      $('#' + id).addEventListener('change', function () { it[k] = Number(this.value) || 0; draw(); });
    });
    $('#pRot').addEventListener('click', function () { it.rot = ((it.rot || 0) + 90) % 360; draw(); });
    $('#pDup').addEventListener('click', function () { var c = JSON.parse(JSON.stringify(it)); c.id = uid(); c.x += GRID * 3; c.y += GRID * 3; items.push(c); sel = c.id; draw(); prop(); });
    $('#pDel').addEventListener('click', function () { items = items.filter(function (x) { return x.id !== sel; }); sel = null; draw(); prop(); });
  }

  /* ---------- палитра ---------- */
  function palette() {
    $('#palette').innerHTML = TYPES.map(function (grp) {
      return '<div class="pal-g">' + esc(grp.g) + '</div><div class="pal-grid">' + grp.items.map(function (it) {
        return '<button class="pal-i" data-t="' + it.t + '" title="' + esc(it.n) + ' · ' + (it.w / 1000).toFixed(1) + '×' + (it.h / 1000).toFixed(1) + ' м"><span>' + it.ic + '</span>' + esc(it.n) + '</button>';
      }).join('') + '</div>';
    }).join('');
    $$('#palette .pal-i').forEach(function (b) { b.addEventListener('click', function () { addType(b.dataset.t); }); });
  }
  function addType(t) {
    var d = typeDef(t); var it = { id: uid(), type: t, name: d.n, x: snapv(W / 2 - d.w / 2), y: snapv(H / 2 - d.h / 2), w: d.w, h: d.h, rot: 0, stage: stage };
    items.push(it); sel = it.id; draw(); prop();
  }

  /* ---------- проекты ---------- */
  function loadList() {
    return rpc('app_layout_plan_list', { p_token: token }).then(function (rows) {
      rows = rows || [];
      $('#plans').innerHTML = rows.length ? rows.map(function (p) {
        return '<div class="plrow' + (p.id === planId ? ' on' : '') + '" data-open="' + p.id + '"><b>' + esc(p.name) + '</b><small>' + esc(KINDS[p.kind] || p.kind) + ' · ' + p.items + ' эл.</small>' +
          '<span class="pl-act"><button class="act" data-del="' + p.id + '">✕</button></span></div>';
      }).join('') : '<span class="note">Проектов нет. Создайте планировку и сохраните.</span>';
      $$('#plans [data-open]').forEach(function (r) { r.addEventListener('click', function (e) { if (e.target.dataset.del) return; openPlan(r.dataset.open); }); });
      $$('#plans [data-del]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_layout_plan_delete', { p_token: token, p_id: b.dataset.del }).then(function () { toast('Удалено'); if (b.dataset.del === planId) { planId = null; items = []; draw(); } loadList(); }); }); });
    });
  }
  var KINDS = { shop: 'Цех', office: 'Офис', compressor: 'Компрессорная', line: 'Линия', other: 'Другое' };
  function openPlan(id) {
    return rpc('app_layout_plan_get', { p_token: token, p_id: id }).then(function (r) {
      var p = r && r[0]; if (!p) return;
      planId = p.id; var d = p.data || {};
      items = d.items || []; W = d.w || 24000; H = d.h || 14000;
      $('#proj').value = p.name || ''; $('#kind').value = p.kind || 'shop'; sel = null; draw(); prop(); loadList();
    });
  }
  function save() {
    var name = $('#proj').value.trim(); if (!name) { toast('Укажите название', 'err'); return; }
    var data = { w: W, h: H, items: items };
    rpc('app_layout_plan_save', { p_token: token, p_id: planId, p_name: name, p_kind: $('#kind').value, p_data: data, p_note: null })
      .then(function (r) { var x = r && r[0]; if (!x || x.ok === false) { toast((x && x.message) || 'Ошибка', 'err'); return; } planId = x.id; toast('Сохранено'); loadList(); })
      .catch(function (e) { toast('Ошибка: ' + e.message, 'err'); });
  }
  function exportJson() { var blob = new Blob([JSON.stringify({ name: $('#proj').value, kind: $('#kind').value, w: W, h: H, items: items }, null, 2)], { type: 'application/json' }); var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = ($('#proj').value || 'layout') + '.json'; a.click(); }
  function importJson(file) { var fr = new FileReader(); fr.onload = function () { try { var d = JSON.parse(fr.result); items = d.items || []; W = d.w || W; H = d.h || H; if (d.name) $('#proj').value = d.name; if (d.kind) $('#kind').value = d.kind; draw(); toast('Импортировано'); } catch (e) { toast('Некорректный JSON', 'err'); } }; fr.readAsText(file); }

  /* ---------- события ---------- */
  $('#newBtn').addEventListener('click', function () { planId = null; items = []; sel = null; $('#proj').value = 'Новая планировка'; draw(); prop(); loadList(); });
  $('#saveBtn').addEventListener('click', save);
  $('#expBtn').addEventListener('click', exportJson);
  $('#impFile').addEventListener('change', function () { if (this.files[0]) importJson(this.files[0]); this.value = ''; });
  $('#printBtn').addEventListener('click', function () { window.print(); });
  $('#zi').addEventListener('click', function () { zoom = Math.min(3, zoom * 1.2); draw(); });
  $('#zo').addEventListener('click', function () { zoom = Math.max(0.25, zoom / 1.2); draw(); });
  $('#z1').addEventListener('click', function () { zoom = 1; draw(); });
  $('#snap').addEventListener('change', function () { snap = this.checked; draw(); });
  $$('#stageSeg button').forEach(function (b) { b.addEventListener('click', function () { stage = b.dataset.s; $$('#stageSeg button').forEach(function (x) { x.classList.toggle('active', x === b); }); }); });
  document.addEventListener('keydown', function (e) { if ((e.key === 'Delete' || e.key === 'Backspace') && sel && !/INPUT|SELECT|TEXTAREA/.test((document.activeElement || {}).tagName || '')) { items = items.filter(function (x) { return x.id !== sel; }); sel = null; draw(); prop(); } });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token; $('#who').textContent = s.login + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    palette(); draw(); prop(); loadList().catch(function () {});
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
})();
