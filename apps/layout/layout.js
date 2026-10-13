/* ============================================================
   3DMP Service · apps/layout/layout.js (v2) — «Планировки».
   Порт функций конструктора robot: тема (светлая/тёмная), режимы
   редактор/демонстрация, инструменты (выделение/рука/метка/маршрут/связь),
   undo/redo, сетка/привязка, зум/весь план, метки-комментарии,
   коммуникации (связи), маршруты потока с анимацией и фазами, события,
   экспорт JSON/SVG/PNG/HTML и печать. Проекты — app_layout_plan_*.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function toast(t, k) { ui.toast(t, k); }
  function deep(o) { return JSON.parse(JSON.stringify(o)); }
  function uid(p) { return (p || 'i') + Date.now().toString(36) + Math.floor(Math.random() * 1000); }

  var token = null, planId = null, zoom = 1, tool = 'sel', mode = 'edit', sel = null, anim = null;
  var W = 12000, H = 8000, GRID = 100, phase = 0;
  var history = [], redo = [];
  var stage = 'new';
  var STAGES = { exist: { l: 'Действующее', c: '#94a3b8' }, 'new': { l: 'Новое', c: '#10b981' }, future: { l: 'Будущее', c: '#8b95a3' } };
  var S = { w: W, h: H, items: [], notes: [], links: [], routes: [] };
  var linkFrom = null, routePts = [], flow = { spd: 1800, playing: false, t: 0 }, flowBase = false;

  var TYPES = [
    { g: 'Станки и обработка', items: [
      { t: 'mill', n: 'ОЦ фрезерный', w: 3200, h: 2600, ic: '🌀' }, { t: 'lathe', n: 'ОЦ токарный', w: 2800, h: 1800, ic: '🔩' },
      { t: 'grind', n: 'Шлифовальный', w: 2600, h: 2000, ic: '✨' }, { t: 'edm', n: 'ЭЭО станок', w: 2200, h: 2000, ic: '⚡' },
      { t: 'press', n: 'Пресс', w: 2400, h: 2200, ic: '🧲' }, { t: 'saw', n: 'Ленточнопила', w: 2600, h: 1200, ic: '✂️' },
      { t: 'cmm', n: 'КИМ', w: 2000, h: 1600, ic: '📏' }, { t: 'bench', n: 'Верстак', w: 1600, h: 800, ic: '🧰' }
    ] },
    { g: 'Роботы и манипуляторы', items: [
      { t: 'robot6', n: 'Робот 6-осевой', w: 2500, h: 2500, ic: '🦾' }, { t: 'scara', n: 'Робот SCARA', w: 2200, h: 2200, ic: '🤖' },
      { t: 'delta', n: 'Дельта-робот', w: 2400, h: 2400, ic: '🎯' }, { t: 'pallet', n: 'Паллетизатор', w: 5200, h: 5200, ic: '📦' },
      { t: 'track', n: 'Робот на рельсе', w: 4400, h: 2300, ic: '🛤' }
    ] },
    { g: 'Конвейеры и транспорт', items: [
      { t: 'conv', n: 'Конвейер прямой', w: 3000, h: 900, ic: '➡️' }, { t: 'turn', n: 'Поворотный', w: 2400, h: 2400, ic: '🔄' },
      { t: 'accum', n: 'Накопитель', w: 6000, h: 1400, ic: '📥' }, { t: 'agv', n: 'AGV/погрузчик', w: 2000, h: 1200, ic: '🛻' },
      { t: 'lift', n: 'Подъёмник', w: 1600, h: 1600, ic: '↕️' }, { t: 'rail', n: 'Рельс/направляющая', w: 8000, h: 400, ic: '🛤' },
      { t: 'cross', n: 'Перегрузочный стол', w: 1600, h: 1600, ic: '➕' }, { t: 'buffer', n: 'Буфер накопления', w: 4000, h: 2000, ic: '🧱' }
    ] },
    { g: 'Хранение и оснастка', items: [
      { t: 'rack', n: 'Стеллаж', w: 2700, h: 1100, ic: '🗄' }, { t: 'pallet', n: 'Паллета', w: 1200, h: 800, ic: '▭' },
      { t: 'cabinet', n: 'Шкаф', w: 1000, h: 600, ic: '🚪' }, { t: 'tool', n: 'Верстак оснастки', w: 1800, h: 800, ic: '🧰' }
    ] },
    { g: 'Инфраструктура', items: [
      { t: 'panel', n: 'Шкаф управления', w: 1200, h: 600, ic: '🔌' }, { t: 'compressor', n: 'Компрессор', w: 2200, h: 1400, ic: '🌬' },
      { t: 'receiver', n: 'Ресивер', w: 1400, h: 1400, ic: '🛢' }, { t: 'dryer', n: 'Осушитель', w: 1200, h: 900, ic: '💧' },
      { t: 'chiller', n: 'Чиллер', w: 1800, h: 1200, ic: '❄️' }, { t: 'col', n: 'Колонна/опора', w: 600, h: 600, ic: '⬛' },
      { t: 'vision', n: 'СТЗ: камера', w: 1300, h: 1000, ic: '📷' }, { t: 'ap', n: 'Точка доступа Wi-Fi', w: 1300, h: 1300, ic: '📶' },
      { t: 'terminal', n: 'Терминал оператора', w: 1500, h: 1300, ic: '🖥' }, { t: 'printer', n: 'Принтер/маркиратор', w: 1300, h: 900, ic: '🖨' }
    ] },
    { g: 'Офис и помещения', items: [
      { t: 'desk', n: 'Стол', w: 1600, h: 800, ic: '🪑' }, { t: 'meet', n: 'Переговорный стол', w: 3200, h: 1400, ic: '🗣' },
      { t: 'shelf', n: 'Шкаф/стеллаж', w: 2000, h: 500, ic: '🗄' }, { t: 'door', n: 'Дверь', w: 1000, h: 200, ic: '🚪' },
      { t: 'wall', n: 'Перегородка', w: 3000, h: 150, ic: '🧱' }
    ] },
    { g: 'Зоны и безопасность', items: [
      { t: 'zone', n: 'Зона (безопасности)', w: 4000, h: 3000, ic: '⬜' }, { t: 'aisle', n: 'Проезд/проход', w: 2000, h: 6000, ic: '↔️' },
      { t: 'label', n: 'Подпись', w: 2400, h: 500, ic: '🏷' }
    ] }
  ];
  function typeDef(t) { for (var i = 0; i < TYPES.length; i++) for (var j = 0; j < TYPES[i].items.length; j++) if (TYPES[i].items[j].t === t) return TYPES[i].items[j]; return { t: t, n: t, w: 1200, h: 800, ic: '•' }; }

  /* ---------- векторные иконки оборудования (вид как в robot) ---------- */
  function glyph(it) {
    var w = it.w, h = it.h, t = it.type, sw = Math.max(6, Math.min(w, h) / 26);
    var st = 'stroke="rgba(255,255,255,.9)" fill="none" stroke-width="' + sw + '" stroke-linejoin="round"', fl = 'fill="rgba(255,255,255,.12)"';
    function rect(x, y, ww, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + ww + '" height="' + hh + '" rx="' + (r || 0) + '" ' + st + '/>'; }
    function fill(x, y, ww, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + ww + '" height="' + hh + '" rx="' + (r || 0) + '" ' + fl + ' stroke="none"/>'; }
    function ln(x1, y1, x2, y2) { return '<line x1="' + x1 + '" y1="' + y1 + '" x2="' + x2 + '" y2="' + y2 + '" ' + st + '/>'; }
    function ci(cx, cy, r) { return '<circle cx="' + cx + '" cy="' + cy + '" r="' + r + '" ' + st + '/>'; }
    function cf(cx, cy, r) { return '<circle cx="' + cx + '" cy="' + cy + '" r="' + r + '" fill="rgba(255,255,255,.85)" stroke="none"/>'; }
    var s = '';
    if (t === 'conv' || t === 'accum' || t === 'rail') {
      s += fill(0, 0, w, h, 6) + rect(0, 0, w, h, 6);
      var n = Math.max(3, Math.round(w / Math.max(h, 400)));
      for (var i = 1; i < n; i++) { var x = w * i / n; s += '<path d="M' + (x - h * 0.18) + ' ' + (h * 0.28) + ' L' + x + ' ' + (h * 0.5) + ' L' + (x - h * 0.18) + ' ' + (h * 0.72) + '" ' + st + '/>'; }
    } else if (t === 'turn') { s += cf(w / 2, h / 2, Math.min(w, h) / 2 - sw) ; s += ci(w / 2, h / 2, Math.min(w, h) / 2 - sw) + ci(w / 2, h / 2, Math.min(w, h) / 6); }
    else if (t === 'robot6' || t === 'scara' || t === 'delta' || t === 'track' || t === 'pallet' || t === 'manip') {
      s += cf(w * 0.3, h * 0.72, Math.min(w, h) * 0.14) + ci(w * 0.3, h * 0.72, Math.min(w, h) * 0.16);
      s += ln(w * 0.3, h * 0.72, w * 0.58, h * 0.34) + ln(w * 0.58, h * 0.34, w * 0.78, h * 0.56) + cf(w * 0.78, h * 0.56, Math.min(w, h) * 0.06);
      if (t === 'track') s += fill(0, h * 0.86, w, h * 0.1, 3) + rect(0, h * 0.86, w, h * 0.1, 3);
      if (t === 'pallet') s += fill(w * 0.55, h * 0.06, w * 0.4, h * 0.22, 3) + rect(w * 0.55, h * 0.06, w * 0.4, h * 0.22, 3);
    }
    else if (t === 'vision') { s += rect(w * 0.32, h * 0.12, w * 0.36, h * 0.3, 5) + '<path d="M' + (w * 0.5) + ' ' + (h * 0.42) + ' L' + (w * 0.2) + ' ' + (h * 0.92) + ' L' + (w * 0.8) + ' ' + (h * 0.92) + ' Z" ' + st + ' opacity=".5"/>'; }
    else if (t === 'ap') { s += cf(w / 2, h * 0.72, Math.min(w, h) * 0.06) + '<path d="M' + (w * 0.34) + ' ' + (h * 0.62) + ' A ' + (w * 0.28) + ' ' + (h * 0.28) + ' 0 0 1 ' + (w * 0.66) + ' ' + (h * 0.62) + '" ' + st + '/><path d="M' + (w * 0.22) + ' ' + (h * 0.62) + ' A ' + (w * 0.4) + ' ' + (h * 0.4) + ' 0 0 1 ' + (w * 0.78) + ' ' + (h * 0.62) + '" ' + st + '/>'; }
    else if (t === 'rack' || t === 'shelf') { s += fill(0, 0, w, h, 5) + rect(0, 0, w, h, 5); for (var j = 1; j < 4; j++) s += ln(0, h * j / 4, w, h * j / 4); }
    else if (t === 'panel' || t === 'compressor' || t === 'receiver' || t === 'dryer' || t === 'chiller' || t === 'terminal' || t === 'printer' || t === 'cabinet') {
      s += fill(0, 0, w, h, 7) + rect(0, 0, w, h, 7) + cf(w * 0.8, h * 0.24, Math.min(w, h) * 0.08);
      for (var k = 1; k < 4; k++) s += ln(w * 0.12, h * k / 5, w * 0.55, h * k / 5);
      if (t === 'compressor') s += ci(w * 0.72, h * 0.66, Math.min(w, h) * 0.14);
    }
    else if (t === 'zone') { s += '<rect x="' + sw + '" y="' + sw + '" width="' + (w - 2 * sw) + '" height="' + (h - 2 * sw) + '" rx="10" ' + st + ' stroke-dasharray="' + (sw * 6) + ' ' + (sw * 4) + '"/>'; }
    else if (t === 'aisle') { for (var a = 0; a < 3; a++) s += ln(w * 0.25, h * (a + 1) / 4, w * 0.75, h * (a + 1) / 4); }
    else if (t === 'door' || t === 'wall') { s += fill(0, 0, w, h, 3) + rect(0, 0, w, h, 3); }
    else if (t === 'desk' || t === 'meet') { s += fill(0, 0, w, h, 12) + rect(0, 0, w, h, 12); if (t === 'meet') { for (var d = 0; d < 3; d++) s += cf(w * (0.25 + d * 0.25), h / 2, Math.min(w, h) * 0.11); } }
    else if (t === 'bench' || t === 'tool') { s += fill(0, h * 0.35, w, h * 0.65, 4) + rect(0, h * 0.35, w, h * 0.65, 4) + ln(0, h * 0.35, w, h * 0.35) + '<path d="M' + (w * 0.3) + ' ' + (h * 0.35) + ' l' + (h * 0.12) + ' ' + (-h * 0.2) + ' l' + (h * 0.12) + ' ' + (h * 0.2) + '" ' + st + '/>'; }
    else if (t === 'label') { s += rect(0, h * 0.3, w, h * 0.4, 4); }
    else { s += fill(w * 0.1, h * 0.15, w * 0.8, h * 0.7, 6) + rect(w * 0.1, h * 0.15, w * 0.8, h * 0.7, 6) + ci(w * 0.5, h * 0.5, Math.min(w, h) * 0.18); }
    return s;
  }
  function snapv(v) { return $('#snapChk') && $('#snapChk').checked ? Math.round(v / GRID) * GRID : Math.round(v); }

  /* ---------- история ---------- */
  function snapshot() { history.push(deep(S)); if (history.length > 60) history.shift(); redo = []; syncHist(); }
  function syncHist() { var u = $('#undoBtn'), r = $('#redoBtn'); if (u) u.disabled = !history.length; if (r) r.disabled = !redo.length; }
  function undo() { if (!history.length) return; redo.push(deep(S)); S = history.pop(); sel = null; draw(); prop(); syncHist(); }
  function redoFn() { if (!redo.length) return; history.push(deep(S)); S = redo.pop(); draw(); prop(); syncHist(); }

  /* ---------- отрисовка ---------- */
  function draw() {
    var svg = $('#cv');
    svg.setAttribute('viewBox', '0 0 ' + S.w + ' ' + S.h);
    svg.style.width = (S.w * zoom) + 'px'; svg.style.height = (S.h * zoom) + 'px';
    var zs = $('#zSlider'); if (zs) zs.value = Math.round(zoom * 100);
    var g = '<defs><marker id="ah" markerWidth="5" markerHeight="5" refX="4" refY="2.5" orient="auto"><path d="M0,0 L5,2.5 L0,5 z" fill="#0ea5e9"/></marker><marker id="ahr" markerWidth="5" markerHeight="5" refX="4" refY="2.5" orient="auto"><path d="M0,0 L5,2.5 L0,5 z" fill="#2563eb"/></marker></defs>';
    if ($('#gridChk') && $('#gridChk').checked) {
      for (var x = 0; x <= S.w; x += GRID * 5) g += '<line x1="' + x + '" y1="0" x2="' + x + '" y2="' + S.h + '" class="gl" stroke-width="' + (GRID / 12) + '"/>';
      for (var y = 0; y <= S.h; y += GRID * 5) g += '<line x1="0" y1="' + y + '" x2="' + S.w + '" y2="' + y + '" class="gl" stroke-width="' + (GRID / 12) + '"/>';
    }
    g += S.links.map(function (l) { var a = byId(l.a), b = byId(l.b); if (!a || !b) return ''; return '<line class="lk" x1="' + (a.x + a.w) + '" y1="' + (a.y + a.h / 2) + '" x2="' + b.x + '" y2="' + (b.y + b.h / 2) + '" marker-end="url(#ah)" data-lk="' + l.id + '"/>'; }).join('');
    g += S.routes.map(function (r) { return '<polyline class="rt" marker-end="url(#ahr)" data-rt="' + r.id + '" points="' + r.pts.map(function (p) { return p[0] + ',' + p[1]; }).join(' ') + '"/>'; }).join('');
    g += S.items.map(function (it) {
      var c = (STAGES[it.stage] || STAGES['new']).c, isz = it.type === 'zone' || it.type === 'aisle';
      return '<g class="li" data-id="' + it.id + '" transform="translate(' + it.x + ',' + it.y + ') rotate(' + (it.rot || 0) + ',' + (it.w / 2) + ',' + (it.h / 2) + ')">' +
        '<rect x="0" y="0" width="' + it.w + '" height="' + it.h + '" rx="' + (GRID / 2) + '" fill="' + (isz ? 'rgba(16,185,129,.08)' : c + '22') + '" stroke="' + c + '" stroke-width="' + (sel === it.id ? GRID / 2 : GRID / 4) + '"' + (isz ? ' stroke-dasharray="' + GRID / 2 + ' ' + GRID / 3 + '"' : '') + '/>' +
        glyph(it) +
        '<text x="' + (it.w / 2) + '" y="' + (it.h / 2 + Math.max(70, Math.min(it.w, it.h) / 3.4)) + '" text-anchor="middle" font-size="' + Math.max(130, Math.min(it.w, it.h) / 9) + '" class="ln">' + esc(it.name) + '</text>' +
        (isz ? '' : '<circle cx="0" cy="' + (it.h / 2) + '" r="' + (GRID * 0.6) + '" fill="#0ea5e9"/><circle cx="' + it.w + '" cy="' + (it.h / 2) + '" r="' + (GRID * 0.6) + '" fill="#0ea5e9"/>') +
        (sel === it.id ? '<rect class="rz" x="' + (it.w - GRID) + '" y="' + (it.h - GRID) + '" width="' + (GRID * 1.6) + '" height="' + (GRID * 1.6) + '" fill="#10b981" stroke="#fff" stroke-width="20"/>' : '') +
        '</g>';
    }).join('');
    g += S.notes.map(function (n) { return '<g class="nt" data-note="' + n.id + '" transform="translate(' + n.x + ',' + n.y + ')"><circle r="' + GRID * 0.9 + '" fill="#f59e0b" stroke="#fff" stroke-width="' + GRID / 6 + '"/><text y="' + GRID * 0.35 + '" text-anchor="middle" font-size="' + GRID * 1.1 + '" fill="#fff">!</text></g>'; }).join('');
    var mark = flowMark(); if (mark) g += '<circle class="fm" cx="' + mark[0] + '" cy="' + mark[1] + '" r="' + GRID * 0.9 + '" fill="#2563eb" stroke="#fff" stroke-width="' + GRID / 6 + '"/>';
    if (!S.items.length) g += '<text x="' + (S.w / 2) + '" y="' + (S.h / 2) + '" text-anchor="middle" font-size="' + (GRID * 6) + '" fill="#94a3b8">Выберите элемент из палитры слева → он появится здесь</text>';
    svg.innerHTML = g;
    bind(); stat();
  }
  function byId(id) { return S.items.filter(function (x) { return x.id === id; })[0]; }
  function pathPts() { var r = S.routes[0]; return r ? r.pts : null; }
  function flowMark() {
    if (mode !== 'demo') return null;
    if (flowBase || !S.routes.length) {
      var list = S.items.filter(function (i) { return i.type !== 'zone' && i.type !== 'aisle'; });
      if (!list.length) return null;
      var k = Math.floor(flow.t) % list.length, it = list[k];
      return [it.x + it.w / 2, it.y + it.h / 2];
    }
    var r = S.routes[0]; if (!r || r.pts.length < 2) return null;
    var seg = flow.t % (r.pts.length - 1), i = Math.floor(seg), f = seg - i, a = r.pts[i], b = r.pts[i + 1] || a;
    return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f];
  }
  function stat() {
    var n = S.items.length, area = S.items.reduce(function (a, it) { return a + it.w * it.h; }, 0) / 1e6;
    var s = $('#stats'); if (s) s.textContent = 'Элементов: ' + n + ' · площадь: ' + area.toFixed(2) + ' м² · связей: ' + S.links.length + ' · маршрутов: ' + S.routes.length + ' · меток: ' + S.notes.length;
    var c = $('#coords');
    if (c && $('#cv').__ptr) c.textContent = 'x ' + Math.round($('#cv').__ptr[0]) + ' · y ' + Math.round($('#cv').__ptr[1]);
  }

  function bind() {
    var svg = $('#cv');
    svg.onmousemove = function (e) { svg.__ptr = stagePct(e); stat(); };
    $$('#cv .li').forEach(function (gEl) {
      gEl.onmousedown = function (e) {
        if (e.target.classList && e.target.classList.contains('rz')) return;
        var id = gEl.getAttribute('data-id');
        if (tool === 'route') { var p = stagePct(e); routePts.push(p); previewRoute(); e.preventDefault(); return; }
        if (tool === 'link') {
          if (linkFrom && linkFrom !== id) { snapshot(); S.links.push({ id: uid('l'), a: linkFrom, b: id, kind: 'conveyor' }); renderLists(); linkFrom = null; draw(); }
          else linkFrom = id; toast(linkFrom ? 'Выберите второй элемент для связи' : 'Готово');
          e.stopPropagation(); return;
        }
        if (mode === 'demo') return;
        sel = id; prop(); draw();
        var it = byId(id); if (!it) return;
        var sx = e.clientX, sy = e.clientY, ox = it.x, oy = it.y, sc = (S.w / zoom) / $('#cv').clientWidth, moved = 0;
        function mv(ev) { moved = 1; it.x = snapv(ox + (ev.clientX - sx) * sc); it.y = snapv(oy + (ev.clientY - sy) * sc); draw(); }
        function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); if (moved) { snapshot(); } }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up); e.preventDefault();
      };
    });
    var rz = $('#cv .rz');
    if (rz) rz.onmousedown = function (e) {
      var it = byId(sel); if (!it) return;
      var sx = e.clientX, sy = e.clientY, ow = it.w, oh = it.h, sc = (S.w / zoom) / $('#cv').clientWidth;
      function mv(ev) { it.w = Math.max(GRID * 3, snapv(ow + (ev.clientX - sx) * sc)); it.h = Math.max(GRID * 3, snapv(oh + (ev.clientY - sy) * sc)); draw(); }
      function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); snapshot(); }
      document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up); e.preventDefault(); e.stopPropagation();
    };
    $$('#cv .nt').forEach(function (gEl) { gEl.onclick = function (e) { var id = gEl.getAttribute('data-note'); var n = S.notes.filter(function (x) { return x.id === id; })[0]; if (n) alert('Комментарий: ' + (n.text || '(пусто)')); e.stopPropagation(); }; });
  }
  function stagePct(e) { var r = $('#cv').getBoundingClientRect(); return [ (e.clientX - r.left) / r.width * S.w, (e.clientY - r.top) / r.height * S.h ]; }
  function previewRoute() { draw(); var svg = $('#cv'); if (!routePts.length) return; svg.insertAdjacentHTML('beforeend', '<polyline points="' + routePts.map(function (p) { return p[0] + ',' + p[1]; }).join(' ') + '" fill="none" stroke="#2563eb" stroke-width="' + GRID / 2 + '" stroke-dasharray="' + GRID + '"/>'); }

  /* ---------- свойства/списки ---------- */
  function prop() {
    var it = byId(sel); var host = $('#prop');
    if (!it) { host.innerHTML = '<span class="note">Выберите элемент на плане.</span>'; return; }
    host.innerHTML =
      '<label>Название</label><input id="pName" value="' + esc(it.name) + '">' +
      '<label>Стадия</label><select id="pStage">' + Object.keys(STAGES).map(function (k) { return '<option value="' + k + '"' + (it.stage === k ? ' selected' : '') + '>' + STAGES[k].l + '</option>'; }).join('') + '</select>' +
      '<div class="grid2"><div><label>X, мм</label><input id="pX" type="number" value="' + it.x + '"></div><div><label>Y, мм</label><input id="pY" type="number" value="' + it.y + '"></div></div>' +
      '<div class="grid2"><div><label>Ширина</label><input id="pW" type="number" value="' + it.w + '"></div><div><label>Высота</label><input id="pH" type="number" value="' + it.h + '"></div></div>' +
      '<div class="btn-row mt"><button class="btn secondary" id="pRot">↻ 90°</button><button class="btn secondary" id="pDup">⧉ Копия</button><button class="btn secondary" id="pDel">✕ Удалить</button></div>';
    $('#pName').oninput = function () { it.name = this.value; draw(); };
    $('#pStage').onchange = function () { it.stage = this.value; draw(); };
    ['pX:x', 'pY:y', 'pW:w', 'pH:h'].forEach(function (pp) { var id = pp.split(':')[0], k = pp.split(':')[1]; $('#' + id).onchange = function () { it[k] = Number(this.value) || 0; draw(); }; });
    $('#pRot').onclick = function () { it.rot = ((it.rot || 0) + 90) % 360; draw(); };
    $('#pDup').onclick = function () { snapshot(); var c = deep(it); c.id = uid(); c.x += GRID * 3; c.y += GRID * 3; S.items.push(c); sel = c.id; draw(); prop(); };
    $('#pDel').onclick = function () { snapshot(); S.items = S.items.filter(function (x) { return x.id !== sel; }); sel = null; draw(); prop(); };
  }
  function renderLists() {
    var nl = $('#notesList'); if (nl) nl.innerHTML = S.notes.length ? S.notes.map(function (n) { return '<div class="lkrow"><span>' + esc(n.text || 'метка') + '</span><button class="act" data-ndel="' + n.id + '">✕</button></div>'; }).join('') : '<span class="note">Меток нет.</span>';
    var ll = $('#linksList'); if (ll) ll.innerHTML = S.links.length ? S.links.map(function (l) { var a = byId(l.a), b = byId(l.b); return '<div class="lkrow"><span>' + esc((a && a.name) || '?') + ' ↔ ' + esc((b && b.name) || '?') + '</span><button class="act" data-ldel="' + l.id + '">✕</button></div>'; }).join('') : '<span class="note">Связей нет.</span>';
    var rl = $('#routeList'); if (rl) rl.innerHTML = S.routes.length ? S.routes.map(function (r, i) { return '<div class="lkrow"><span>Маршрут ' + (i + 1) + ' · ' + r.pts.length + ' тчк</span><button class="act" data-rdel="' + r.id + '">✕</button></div>'; }).join('') : '<span class="note">Маршрутов нет.</span>';
    $$('[data-ndel]').forEach(function (b) { b.onclick = function () { snapshot(); S.notes = S.notes.filter(function (x) { return x.id !== b.dataset.ndel; }); renderLists(); draw(); }; });
    $$('[data-ldel]').forEach(function (b) { b.onclick = function () { snapshot(); S.links = S.links.filter(function (x) { return x.id !== b.dataset.ldel; }); renderLists(); draw(); }; });
    $$('[data-rdel]').forEach(function (b) { b.onclick = function () { snapshot(); S.routes = S.routes.filter(function (x) { return x.id !== b.dataset.rdel; }); renderLists(); draw(); }; });
  }

  /* ---------- палитра ---------- */
  function palette() {
    $('#palette').innerHTML = TYPES.map(function (grp, gi) {
      return '<button class="pal-h" data-g="' + gi + '"><span class="cr">▾</span>' + esc(grp.g) + '</button>' +
        '<div class="pal-grid" data-grid="' + gi + '">' + grp.items.map(function (it) { return '<button class="pal-i" data-t="' + it.t + '" title="' + esc(it.n) + ' · ' + (it.w / 1000).toFixed(1) + '×' + (it.h / 1000).toFixed(1) + ' м"><span>' + it.ic + '</span>' + esc(it.n) + '</button>'; }).join('') + '</div>';
    }).join('');
    $$('#palette .pal-h').forEach(function (h) {
      h.onclick = function () { var g = $('#palette [data-grid="' + h.dataset.g + '"]'); var on = g.style.display !== 'none'; g.style.display = on ? 'none' : ''; h.querySelector('.cr').textContent = on ? '▸' : '▾'; };
    });
    $$('#palette .pal-i').forEach(function (b) { b.onclick = function () { addType(b.dataset.t); }; });
  }
  function addType(t) { snapshot(); var d = typeDef(t); var it = { id: uid(), type: t, name: d.n, x: snapv(S.w / 2 - d.w / 2), y: snapv(S.h / 2 - d.h / 2), w: d.w, h: d.h, rot: 0, stage: stage }; S.items.push(it); sel = it.id; draw(); prop(); }

  /* ---------- проекты ---------- */
  function applyData(d) { S = { w: d.w || W, h: d.h || H, items: d.items || [], notes: d.notes || [], links: d.links || [], routes: d.routes || [] }; sel = null; history = []; redo = []; syncHist(); draw(); prop(); renderLists(); }
  function loadList() {
    return rpc('app_layout_plan_list', { p_token: token }).then(function (rows) {
      rows = rows || [];
      $('#plans').innerHTML = rows.length ? rows.map(function (p) { return '<div class="plrow' + (p.id === planId ? ' on' : '') + '" data-open="' + p.id + '"><b>' + esc(p.name) + '</b><small>' + esc(KINDS[p.kind] || p.kind) + ' · ' + p.items + ' эл.</small><span class="pl-act"><button class="act" data-del="' + p.id + '">✕</button></span></div>'; }).join('') : '<span class="note">Проектов нет.</span>';
      $$('#plans [data-open]').forEach(function (r) { r.onclick = function (e) { if (e.target.dataset.del) return; openPlan(r.dataset.open); }; });
      $$('#plans [data-del]').forEach(function (b) { b.onclick = function () { rpc('app_layout_plan_delete', { p_token: token, p_id: b.dataset.del }).then(function () { toast('Удалено'); if (b.dataset.del === planId) { planId = null; applyData({}); } loadList(); }); }; });
    });
  }
  var KINDS = { shop: 'Цех', office: 'Офис', compressor: 'Компрессорная', line: 'Линия', other: 'Другое' };
  function openPlan(id) { return rpc('app_layout_plan_get', { p_token: token, p_id: id }).then(function (r) { var p = r && r[0]; if (!p) return; planId = p.id; $('#proj').value = p.name || ''; $('#kind').value = p.kind || 'shop'; applyData(p.data || {}); fitZoom(); draw(); centerView(); loadList(); }); }
  function save() {
    var name = $('#proj').value.trim(); if (!name) { toast('Укажите название', 'err'); return; }
    rpc('app_layout_plan_save', { p_token: token, p_id: planId, p_name: name, p_kind: $('#kind').value, p_data: S, p_note: null })
      .then(function (r) { var x = r && r[0]; if (!x || x.ok === false) { toast((x && x.message) || 'Ошибка', 'err'); return; } planId = x.id; toast('Сохранено'); loadList(); });
  }

  /* ---------- экспорт ---------- */
  function svgString() { var svg = $('#cv').cloneNode(true); svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg'); svg.insertAdjacentHTML('afterbegin', '<rect width="' + S.w + '" height="' + S.h + '" fill="#ffffff"/>'); return new XMLSerializer().serializeToString(svg); }
  function dl(name, data, mime) { var b = new Blob([data], { type: mime || 'application/octet-stream' }); var a = document.createElement('a'); a.href = URL.createObjectURL(b); a.download = name; a.click(); }
  function exportSvg() { dl(($('#proj').value || 'layout') + '.svg', svgString(), 'image/svg+xml'); }
  function exportPng() {
    var svg = svgString(), img = new Image();
    img.onload = function () { var cv = document.createElement('canvas'); cv.width = S.w; cv.height = S.h; var ctx = cv.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, S.w, S.h); ctx.drawImage(img, 0, 0); cv.toBlob(function (b) { var a = document.createElement('a'); a.href = URL.createObjectURL(b); a.download = ($('#proj').value || 'layout') + '.png'; a.click(); }); };
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
  }
  function exportHtml() { dl(($('#proj').value || 'layout') + '.html', '<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>' + esc($('#proj').value) + '</title><style>body{margin:0}#cv{width:100%;height:auto}</style></head><body>' + svgString() + '</body></html>', 'text/html'); }
  function exportJson() { dl(($('#proj').value || 'layout') + '.json', JSON.stringify({ name: $('#proj').value, kind: $('#kind').value, w: S.w, h: S.h, items: S.items, notes: S.notes, links: S.links, routes: S.routes }, null, 2), 'application/json'); }
  function importJson(file) { var fr = new FileReader(); fr.onload = function () { try { var d = JSON.parse(fr.result); if (d.name) $('#proj').value = d.name; if (d.kind) $('#kind').value = d.kind; applyData(d); toast('Импортировано'); } catch (e) { toast('Некорректный JSON', 'err'); } }; fr.readAsText(file); }
  function exportNotes() { dl('notes.txt', S.notes.map(function (n, i) { return (i + 1) + '. ' + (n.text || '') + ' @(' + Math.round(n.x) + ',' + Math.round(n.y) + ')'; }).join('\n'), 'text/plain'); }
  function exportLinks() { dl('links.csv', 'A,B\n' + S.links.map(function (l) { var a = byId(l.a), b = byId(l.b); return '"' + ((a && a.name) || '') + '","' + ((b && b.name) || '') + '"'; }).join('\n'), 'text/csv'); }
  function exportRoutes() { dl('routes.csv', S.routes.map(function (r, i) { return 'Маршрут ' + (i + 1) + ': ' + r.pts.map(function (p) { return p[0] + ',' + p[1]; }).join(' '); }).join('\n'), 'text/csv'); }

  /* ---------- маршруты/анимация ---------- */
  function autoRoutes() {
    snapshot();
    var list = S.items.filter(function (i) { return i.type !== 'zone' && i.type !== 'aisle'; }).sort(function (a, b) { return a.x - b.x; });
    if (list.length < 2) { toast('Нужно ≥2 элемента'); return; }
    S.routes = [{ id: uid('r'), pts: list.map(function (it) { return [it.x + it.w / 2, it.y + it.h / 2]; }) }];
    renderLists(); draw(); toast('Маршрут построен (' + list.length + ' тчк)');
  }
  function addRoute() { tool = 'route'; routePts = []; toast('Кликайте точки маршрута; «Завершить» — сохранить'); }
  function finishRoute() { if (routePts.length < 2) { routePts = []; tool = 'sel'; return; } snapshot(); S.routes.push({ id: uid('r'), pts: routePts.slice() }); routePts = []; tool = 'sel'; renderLists(); draw(); }
  function animTick() { if (!flow.playing) return; flow.t += 0.06 * (flow.spd / 1800); draw(); anim = requestAnimationFrame(animTick); }
  function togglePlay() { flow.playing = !flow.playing; var b = $('#playBtn'); if (b) b.textContent = flow.playing ? '⏸ Пауза' : '▶ Пуск'; if (flow.playing && !anim) anim = requestAnimationFrame(animTick); if (!flow.playing && anim) { cancelAnimationFrame(anim); anim = null; } }
  function stepFwd() { phase++; flow.t += 1; draw(); }
  function stepBack() { phase = Math.max(0, phase - 1); flow.t = Math.max(0, flow.t - 1); draw(); }
  function logEvent(text) { var l = $('#log'); if (!l) return; var t = new Date().toLocaleTimeString('ru-RU'); l.insertAdjacentHTML('afterbegin', '<div>[' + t + '] ' + esc(text) + '</div>'); }

  /* ---------- тема ---------- */
  function setTheme(t) { var ed = $('#editor'); if (ed) ed.classList.toggle('theme-dark', t === 'dark'); localStorage.setItem('layout-theme', t); var b = $('#themeBtn'); if (b) b.textContent = t === 'dark' ? '☀' : '🌙'; }
  function toggleTheme() { var ed = $('#editor'); setTheme((ed && ed.classList.contains('theme-dark')) ? 'light' : 'dark'); }

  /* ---------- события ---------- */
  function setTool(t) { tool = t; $$('[data-tool]').forEach(function (b) { b.classList.toggle('active', b.dataset.tool === t); }); }
  function setMode(m) { mode = m; $('#mEdit').classList.toggle('active', m === 'edit'); $('#mDemo').classList.toggle('active', m === 'demo'); $('#playBtn').style.display = m === 'demo' ? '' : 'none'; if (m === 'edit' && flow.playing) togglePlay(); }
  $('#palette').onclick = function () {};
  $$('[data-tool]').forEach(function (b) { b.onclick = function () { setTool(b.dataset.tool); }; });
  $('#mEdit').onclick = function () { setMode('edit'); };
  $('#mDemo').onclick = function () { setMode('demo'); draw(); };
  $('#undoBtn').onclick = undo; $('#redoBtn').onclick = redoFn;
  $('#zi').onclick = function () { zoom = Math.min(4, zoom * 1.2); draw(); }; $('#zo').onclick = function () { zoom = Math.max(0.2, zoom / 1.2); draw(); };
  $('#zFit').onclick = function () { zoom = 1; draw(); };
  $('#gridChk').onchange = draw; $('#snapChk').onchange = draw;
  $('#palBtn').onclick = function () { $('#editor').classList.toggle('no-pal'); };
  $('#propsBtn').onclick = function () { $('#editor').classList.toggle('no-props'); };
  $('#soloBtn').onclick = function () { $('#editor').classList.toggle('solo'); };
  $('#themeBtn').onclick = toggleTheme;
  $$('#tabs button').forEach(function (b) { b.onclick = function () { $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); }); var id = b.dataset.tab; ['prop', 'notes', 'links', 'flow'].forEach(function (k) { $('#tab-' + k).style.display = k === id ? '' : 'none'; }); }; });
  $('#noteAdd').onclick = function () { setTool('note'); toast('Кликните место метки'); };
  $('#noteExport').onclick = exportNotes;
  $('#linkExport').onclick = exportLinks;
  $('#routeAdd').onclick = addRoute; $('#routeAuto').onclick = autoRoutes; $('#routeDone').onclick = finishRoute; $('#routeExport').onclick = exportRoutes;
  $('#playBtn').onclick = togglePlay; $('#stepPrev').onclick = stepBack; $('#stepNext').onclick = stepFwd;
  $('#spd').onchange = function () { flow.spd = Number(this.value) || 1800; };
  $('#expJson').onclick = exportJson; $('#expSvg').onclick = exportSvg; $('#expPng').onclick = exportPng; $('#expHtml').onclick = exportHtml;
  $('#printBtn').onclick = function () { window.print(); };
  $('#impFile').onchange = function () { if (this.files[0]) importJson(this.files[0]); this.value = ''; };
  $('#saveBtn').onclick = save;
  $('#newBtn').onclick = function () { snapshot(); planId = null; $('#proj').value = 'Новая планировка'; applyData({}); loadList(); };
  $$('#stageSeg button').forEach(function (b) { b.onclick = function () { stage = b.dataset.s; $$('#stageSeg button').forEach(function (x) { x.classList.toggle('active', x === b); }); }; });
  $('#cv').onmousedown = function (e) {
    if (tool !== 'pan' || e.target !== $('#cv')) return;
    var wrap = $('#cvWrap'), sx = e.clientX, sy = e.clientY, l = wrap.scrollLeft, t = wrap.scrollTop;
    function mv(ev) { wrap.scrollLeft = l - (ev.clientX - sx); wrap.scrollTop = t - (ev.clientY - sy); }
    function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); }
    document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up); e.preventDefault();
  };
  $('#cv').onclick = function (e) {
    if (tool === 'note') { var p = stagePct(e); var txt = prompt('Комментарий к метке:', ''); if (txt != null) { snapshot(); S.notes.push({ id: uid('n'), x: p[0], y: p[1], text: txt }); renderLists(); draw(); } setTool('sel'); return; }
    if (tool === 'route') { var pr = stagePct(e); routePts.push(pr); previewRoute(); return; }
    if (e.target === $('#cv')) { sel = null; prop(); draw(); }
  };
  document.onkeydown = function (e) {
    var tag = (document.activeElement || {}).tagName || '';
    if (/INPUT|SELECT|TEXTAREA/.test(tag)) return;
    if (e.key === 'Delete' && sel) { snapshot(); S.items = S.items.filter(function (x) { return x.id !== sel; }); sel = null; draw(); prop(); }
    if (e.ctrlKey && e.key.toLowerCase() === 'z') { e.preventDefault(); undo(); }
    if (e.ctrlKey && e.key.toLowerCase() === 'y') { e.preventDefault(); redoFn(); }
    if (e.ctrlKey && e.key.toLowerCase() === 's') { e.preventDefault(); save(); }
    if (e.key === 'Enter' && tool === 'route') finishRoute();
    if (e.key === 'Escape') { routePts = []; tool = 'sel'; setTool('sel'); draw(); }
    if (e.key.toLowerCase() === 'v') setTool('sel'); if (e.key.toLowerCase() === 'h') setTool('pan'); if (e.key.toLowerCase() === 'c') setTool('note');
  };
  function contentBox() {
    var list = S.items.length ? S.items : [{ x: 0, y: 0, w: S.w, h: S.h }];
    var x0 = Math.min.apply(null, list.map(function (i) { return i.x; })), y0 = Math.min.apply(null, list.map(function (i) { return i.y; }));
    var x1 = Math.max.apply(null, list.map(function (i) { return i.x + i.w; })), y1 = Math.max.apply(null, list.map(function (i) { return i.y + i.h; }));
    return { x: x0, y: y0, w: Math.max(x1 - x0, 800), h: Math.max(y1 - y0, 600) };
  }
  function fitZoom() { var w = $('#cvWrap'); if (!w) return; var b = contentBox(); var z = Math.min((w.clientWidth - 40) / b.w, (w.clientHeight - 40) / b.h); zoom = Math.max(0.1, Math.min(3, z || 1)); }
  function centerView() { var w = $('#cvWrap'); if (!w) return; var b = contentBox(); w.scrollLeft = Math.max(0, (b.x + b.w / 2) * zoom - w.clientWidth / 2); w.scrollTop = Math.max(0, (b.y + b.h / 2) * zoom - w.clientHeight / 2); }
  function showReport() {
    var len = 0; S.routes.forEach(function (r) { for (var i = 1; i < r.pts.length; i++) len += Math.sqrt(Math.pow(r.pts[i][0] - r.pts[i - 1][0], 2) + Math.pow(r.pts[i][1] - r.pts[i - 1][1], 2)); });
    var cnt = S.items.filter(function (i) { return i.type !== 'zone' && i.type !== 'aisle'; }).length;
    ui.dialog({ title: 'Отчёт по потоку', html: true, cancelText: 'Закрыть', body:
      '<p>Оборудование/элементы: <b>' + cnt + '</b></p><p>Связей: <b>' + S.links.length + '</b> · маршрутов: <b>' + S.routes.length + '</b></p>' +
      '<p>Длина маршрутов: <b>' + (len / 1000).toFixed(1) + ' м</b></p><p>Меток: <b>' + S.notes.length + '</b></p>' });
  }
  $('#zPlan').onclick = function () { fitZoom(); draw(); centerView(); };
  $('#zFit').onclick = function () { zoom = 1; draw(); };
  $('#clearBtn').onclick = function () { snapshot(); S.items = []; S.notes = []; S.links = []; S.routes = []; sel = null; draw(); prop(); renderLists(); logEvent('Схема очищена'); };
  $('#resetBtn').onclick = function () { snapshot(); planId = null; $('#proj').value = 'Новая планировка'; applyData({}); fitZoom(); draw(); logEvent('Полный сброс'); };
  $('#baseChk').onchange = function () { flowBase = this.checked; draw(); };
  $('#reportBtn').onclick = showReport;
  (function () {
    var gp = $('#gripPal'), gpr = $('#gripProps');
    if (gp) gp.onmousedown = function (e) {
      var sx = e.clientX, w0 = $('.epal').offsetWidth;
      function mv(ev) { var nw = Math.max(160, Math.min(440, w0 + (ev.clientX - sx))); $('.ebody').style.gridTemplateColumns = nw + 'px 1fr ' + ($('.eprops') ? $('.eprops').offsetWidth : 320) + 'px'; }
      function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); }
      document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up); e.preventDefault();
    };
    if (gpr) gpr.onmousedown = function (e) {
      var sx = e.clientX, w0 = $('.eprops').offsetWidth;
      function mv(ev) { var nw = Math.max(200, Math.min(480, w0 - (ev.clientX - sx))); $('.ebody').style.gridTemplateColumns = ($('.epal') ? $('.epal').offsetWidth : 250) + 'px 1fr ' + nw + 'px'; }
      function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); }
      document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up); e.preventDefault();
    };
  })();
  function pan(dx, dy) { var w = $('#cvWrap'); w.scrollLeft += dx * w.clientWidth * 0.6; w.scrollTop += dy * w.clientHeight * 0.6; }
  function zoomToBBox(list) {
    if (!list.length) { toast('Нет элементов для масштабирования'); return; }
    var x0 = Math.min.apply(null, list.map(function (i) { return i.x; })), y0 = Math.min.apply(null, list.map(function (i) { return i.y; }));
    var x1 = Math.max.apply(null, list.map(function (i) { return i.x + i.w; })), y1 = Math.max.apply(null, list.map(function (i) { return i.y + i.h; }));
    var w = $('#cvWrap'); var z = Math.min((w.clientWidth - 40) / Math.max(x1 - x0, 1000), (w.clientHeight - 40) / Math.max(y1 - y0, 1000));
    zoom = Math.max(0.05, Math.min(4, z)); draw(); w.scrollLeft = Math.max(0, (x0 - 200) * zoom); w.scrollTop = Math.max(0, (y0 - 200) * zoom);
  }
  if ($('#navL')) $('#navL').onclick = function () { pan(-1, 0); };
  if ($('#navR')) $('#navR').onclick = function () { pan(1, 0); };
  if ($('#navU')) $('#navU').onclick = function () { pan(0, -1); };
  if ($('#navD')) $('#navD').onclick = function () { pan(0, 1); };
  if ($('#zSlider')) $('#zSlider').oninput = function () { zoom = Math.max(0.2, Math.min(3, (Number(this.value) || 100) / 100)); draw(); };
  if ($('#zStage')) $('#zStage').onclick = function () { zoomToBBox(S.items.filter(function (i) { return i.stage === 'new'; })); };
  if ($('#fsBtn')) $('#fsBtn').onclick = function () {
    var ed = $('#editor');
    if (!document.fullscreenElement) { var rq = ed.requestFullscreen || ed.webkitRequestFullscreen || ed.msRequestFullscreen; if (rq) rq.call(ed); else toast('Полноэкранный режим недоступен', 'err'); }
    else if (document.exitFullscreen) document.exitFullscreen();
  };
  document.addEventListener('fullscreenchange', function () { setTimeout(function () { fitZoom(); draw(); centerView(); }, 60); });
  $('#logout').onclick = function () { window.Auth.logout(); location.href = '../../index.html'; };

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    token = s.token; $('#who').textContent = s.login + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    setTheme(localStorage.getItem('layout-theme') || 'dark');
    palette(); fitZoom(); draw(); centerView(); prop(); renderLists(); loadList().catch(function () {});
    logEvent('Проект загружен');
    window.addEventListener('resize', function () { fitZoom(); draw(); centerView(); });
  });
})();
