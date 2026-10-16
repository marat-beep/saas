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

  var token = null, planId = null, zoom = 1, tool = 'sel', mode = 'edit', sel = null, anim = null, baseline = null, collHighlight = [];
  var ZMIN = 0.05, ZMAX = 8;   // диапазон масштаба: 5% … 800%
  var W = 12000, H = 8000, GRID = 100, phase = 0;
  var history = [], redo = [];
  var stage = 'new';
  var STAGES = { exist: { l: 'Действующее', c: '#94a3b8' }, 'new': { l: 'Новое', c: '#10b981' }, future: { l: 'Будущее', c: '#8b95a3' } };
  var S = { w: W, h: H, items: [], notes: [], links: [], routes: [], utils: [] };
  var linkFrom = null, routePts = [], utilPts = [], utilKind = null, flow = { spd: 1800, playing: false, t: 0 }, flowBase = false;
  /* L1: слои — видимость категорий объектов на плане */
  var LAYERS = [
    { k: 'equip', l: 'Оборудование', ic: '🌀' },
    { k: 'walls', l: 'Стены и перегородки', ic: '🧱' },
    { k: 'zones', l: 'Зоны и проезды', ic: '⬜' },
    { k: 'labels', l: 'Подписи', ic: '🏷' },
    { k: 'utils', l: 'Коммуникации', ic: '〰' },
    { k: 'routes', l: 'Маршруты потока', ic: '➡️' },
    { k: 'links', l: 'Связи', ic: '🔗' },
    { k: 'notes', l: 'Метки', ic: '💬' }
  ];
  var layers = (function () { try { var s = localStorage.getItem('layout-layers'); if (s) return JSON.parse(s); } catch (e) {} return {}; })();
  LAYERS.forEach(function (x) { if (layers[x.k] == null) layers[x.k] = true; });
  function layerOf(t) { if (t === 'wall' || t === 'door') return 'walls'; if (t === 'zone' || t === 'aisle') return 'zones'; if (t === 'label') return 'labels'; return 'equip'; }
  function saveLayers() { try { localStorage.setItem('layout-layers', JSON.stringify(layers)); } catch (e) {} }
  var UTILS = [
    { k: 'electric', l: 'Питание (электр.)', c: '#ef4444' }, { k: 'air', l: 'Воздух', c: '#06b6d4' },
    { k: 'water', l: 'Вода', c: '#3b82f6' }, { k: 'gas', l: 'Газ', c: '#f59e0b' }, { k: 'net', l: 'Сеть / данные', c: '#22c55e' }
  ];

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

  /* ---------- L3: подложка (растр/вектор DXF) ---------- */
  function bgRect() { var b = S.bg || {}; return { x: b.x != null ? b.x : 0, y: b.y != null ? b.y : 0, w: b.w != null ? b.w : S.w, h: b.h != null ? b.h : S.h }; }
  function bgLayer() {
    var b = S.bg; if (!b) return '';
    var r = bgRect(), op = (b.opacity != null ? b.opacity : 0.5);
    if (b.href) return '<image href="' + b.href + '" x="' + r.x + '" y="' + r.y + '" width="' + r.w + '" height="' + r.h + '" opacity="' + op + '" preserveAspectRatio="none"/>';
    if (b.dxf && b.dxf.length) {
      var bb = b.bbox || { x: 0, y: 0, w: 1, h: 1 }, sx = r.w / (bb.w || 1), sy = r.h / (bb.h || 1);
      var T = function (p) { return { x: r.x + (p[0] - bb.x) * sx, y: r.y + (bb.y + bb.h - p[1]) * sy }; };
      var sw = Math.max(GRID / 6, (b.lineWeight || 1) * (Math.min(sx, sy) || 1));
      return '<g fill="none" stroke="' + (b.color || '#334155') + '" stroke-width="' + sw + '" opacity="' + op + '">' + b.dxf.map(function (s) { var a = T(s[0]), c = T(s[1]); return '<line x1="' + a.x + '" y1="' + a.y + '" x2="' + c.x + '" y2="' + c.y + '"/>'; }).join('') + '</g>';
    }
    return '';
  }
  /* Минимальный DXF-парсер: LINE, LWPOLYLINE, POLYLINE+VERTEX, CIRCLE, ARC — для 2D-планов. */
  function parseDxf(text) {
    var lines = String(text).split(/\r?\n/), segs = [], ent = null, nums = {}, verts = [], polyFlag = 0;
    function num(code, val) { var v = parseFloat(val); return isNaN(v) ? null : v; }
    function finish() {
      if (!ent) return;
      var t = ent;
      if (t === 'LINE' && nums[10] != null && nums[20] != null && nums[11] != null && nums[21] != null) segs.push([[nums[10], nums[20]], [nums[11], nums[21]]]);
      else if ((t === 'LWPOLYLINE' || t === 'POLYLINE') && verts.length >= 2) {
        for (var i = 1; i < verts.length; i++) segs.push([verts[i - 1], verts[i]]);
        if (polyFlag & 1) segs.push([verts[verts.length - 1], verts[0]]);
      } else if (t === 'CIRCLE' && nums[10] != null && nums[20] != null && nums[40] != null) {
        var cx = nums[10], cy = nums[20], rr = nums[40], n = 24, pv = null, pf = null;
        for (var a = 0; a <= n; a++) { var ang = a / n * Math.PI * 2, p = [cx + rr * Math.cos(ang), cy + rr * Math.sin(ang)]; if (pf) segs.push([pf, p]); else pv = p; pf = p; }
      } else if (t === 'ARC' && nums[10] != null && nums[20] != null && nums[40] != null) {
        var a1 = (nums[50] || 0) * Math.PI / 180, a2 = (nums[51] || 360) * Math.PI / 180; if (a2 <= a1) a2 += Math.PI * 2;
        var m = 20, pp = null;
        for (var k = 0; k <= m; k++) { var aa = a1 + (a2 - a1) * k / m, q = [nums[10] + nums[40] * Math.cos(aa), nums[20] + nums[40] * Math.sin(aa)]; if (pp) segs.push([pp, q]); pp = q; }
      }
      ent = null; nums = {}; verts = []; polyFlag = 0;
    }
    for (var i = 0; i + 1 < lines.length; i += 2) {
      var code = parseInt(String(lines[i]).trim(), 10), val = String(lines[i + 1]).trim();
      if (isNaN(code)) continue;
      if (code === 0) {
        finish();
        if (val === 'LINE' || val === 'LWPOLYLINE' || val === 'POLYLINE' || val === 'CIRCLE' || val === 'ARC') ent = val;
        else if (val === 'VERTEX' && ent) { /* keep ent as POLYLINE */ var keep = verts; verts = keep; }
        continue;
      }
      if (!ent) continue;
      if (ent === 'LINE' || ent === 'CIRCLE' || ent === 'ARC') { var nv = num(code, val); if (nv != null && nums[code] == null) nums[code] = nv; }
      else if (ent === 'LWPOLYLINE') {
        if (code === 10) { nums._x = num(10, val); }
        else if (code === 20 && nums._x != null) { verts.push([nums._x, num(20, val)]); nums._x = null; }
        else if (code === 70) polyFlag = parseInt(val, 10) || 0;
      } else if (ent === 'POLYLINE') {
        if (code === 70) polyFlag = parseInt(val, 10) || 0;
        if (code === 10) { nums._x = num(10, val); }
        else if (code === 20 && nums._x != null) { verts.push([nums._x, num(20, val)]); nums._x = null; }
      }
    }
    finish();
    return segs;
  }
  function dxfBBox(segs) {
    var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    segs.forEach(function (s) { s.forEach(function (p) { if (p[0] < x0) x0 = p[0]; if (p[0] > x1) x1 = p[0]; if (p[1] < y0) y0 = p[1]; if (p[1] > y1) y1 = p[1]; }); });
    if (!isFinite(x0)) return { x: 0, y: 0, w: 1, h: 1 };
    return { x: x0, y: y0, w: Math.max(x1 - x0, 1), h: Math.max(y1 - y0, 1) };
  }
  function loadDxf(name, text) {
    var segs = parseDxf(text);
    if (!segs.length) { toast('В DXF не найдено линий (LINE/LWPOLYLINE/POLYLINE)', 'err'); return; }
    var bb = dxfBBox(segs), k = Math.min(S.w / bb.w, S.h / bb.h) * 0.9, w = bb.w * k, h = bb.h * k;
    S.bg = { dxf: segs, bbox: bb, opacity: 0.55, lineWeight: 1, color: '#334155', x: (S.w - w) / 2, y: (S.h - h) / 2, w: w, h: h };
    draw(); logEvent('Подложка DXF: ' + name + ' (' + segs.length + ' линий)'); toast('DXF-подложка загружена (' + segs.length + ' линий)');
  }

  /* ---------- L3: 3D-превью (изометрия) ---------- */
  var H3D = { mill: 2200, lathe: 1800, grind: 2000, edm: 2000, press: 2400, saw: 1200, cmm: 1600, bench: 900,
    robot6: 2000, scara: 1800, delta: 1800, pallet: 1800, track: 1600,
    conv: 900, turn: 1000, accum: 1000, agv: 1200, lift: 1600, rail: 300, cross: 900, buffer: 1200,
    rack: 2400, cabinet: 1800, tool: 900, panel: 1800, compressor: 1600, receiver: 1800, dryer: 1500, chiller: 1500, col: 3000, vision: 1800, ap: 300, terminal: 1500, printer: 1200,
    desk: 750, meet: 750, shelf: 1800, door: 2000, wall: 2700 };
  function shade(hex, f) { var n = parseInt(hex.slice(1), 16), r = Math.round(((n >> 16) & 255) * f), g = Math.round(((n >> 8) & 255) * f), b = Math.round((n & 255) * f); return 'rgb(' + r + ',' + g + ',' + b + ')'; }
  function iso3d(ang, ext) {
    var a = ang * Math.PI / 180, ca = Math.cos(a), sa = Math.sin(a);
    function rp(x, y) { return [x * ca - y * sa, x * sa + y * ca]; }
    function proj(x, y, z) { var q = rp(x, y); return [(q[0] - q[1]) * 0.866, (q[0] + q[1]) * 0.5 - z]; }
    var list = S.items.filter(function (it) { return layers[layerOf(it.type)]; });
    var boxes = list.map(function (it) {
      var z = (it.type === 'zone' || it.type === 'aisle' || it.type === 'label') ? 0 : (H3D[it.type] || 1500) * ext;
      var cx = it.x + it.w / 2, cy = it.y + it.h / 2, ra = (it.rot || 0) * Math.PI / 180, cr = Math.cos(ra), sr = Math.sin(ra);
      function corner(dx, dy) { var vx = it.x + dx - cx, vy = it.y + dy - cy; return [cx + vx * cr - vy * sr, cy + vx * sr + vy * cr]; }
      var c = [corner(0, 0), corner(it.w, 0), corner(it.w, it.h), corner(0, it.h)];
      var q = rp(cx, cy), depth = q[0] + q[1];
      return { z: z, c: c, depth: depth, col: (STAGES[it.stage] || STAGES['new']).c, name: it.name };
    }).sort(function (p, r) { return p.depth - r.depth; });
    var minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity, body = '';
    function pt(x, y, z) { var p = proj(x, y, z); if (p[0] < minx) minx = p[0]; if (p[0] > maxx) maxx = p[0]; if (p[1] < miny) miny = p[1]; if (p[1] > maxy) maxy = p[1]; return p[0].toFixed(1) + ',' + p[1].toFixed(1); }
    boxes.forEach(function (b) {
      var top = b.c.map(function (p) { return pt(p[0], p[1], b.z); }).join(' ');
      if (b.z <= 0) { body += '<polygon points="' + top + '" fill="' + b.col + '22" stroke="' + b.col + '" stroke-dasharray="40 24"/>'; return; }
      for (var i = 0; i < 4; i++) {
        var p1 = b.c[i], p2 = b.c[(i + 1) % 4];
        var poly = [pt(p1[0], p1[1], 0), pt(p2[0], p2[1], 0), pt(p2[0], p2[1], b.z), pt(p1[0], p1[1], b.z)].join(' ');
        body += '<polygon points="' + poly + '" fill="' + shade(b.col, 0.72) + '" stroke="' + shade(b.col, 0.55) + '"/>';
      }
      body += '<polygon points="' + top + '" fill="' + shade(b.col, 1) + '" stroke="' + shade(b.col, 0.8) + '"/>';
      var c0 = proj(b.c[2][0], b.c[2][1], b.z);
      body += '<text x="' + c0[0].toFixed(1) + '" y="' + c0[1].toFixed(1) + '" font-size="120" fill="#0f172a" opacity=".7">' + esc((b.name || '').slice(0, 14)) + '</text>';
    });
    var pad = 400, vw = Math.max(maxx - minx + pad * 2, 100), vh = Math.max(maxy - miny + pad * 2, 100);
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="' + (minx - pad).toFixed(0) + ' ' + (miny - pad).toFixed(0) + ' ' + vw.toFixed(0) + ' ' + vh.toFixed(0) + '" style="width:100%;height:60vh;background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px">' + body + '</svg>';
  }
  function iso3dSvgPng(svg, name) {
    var vb = (svg.match(/viewBox="([^"]+)"/) || [])[1]; if (!vb) return;
    var p = vb.trim().split(/\s+/).map(Number), W = Math.max(200, Math.round(p[2])), H = Math.max(150, Math.round(p[3]));
    var svg2 = svg.replace('<svg ', '<svg width="' + W + '" height="' + H + '" ');
    var blob = new Blob([svg2], { type: 'image/svg+xml;charset=utf-8' });
    var url = URL.createObjectURL(blob), img = new Image();
    img.onload = function () {
      var c = document.createElement('canvas'); c.width = W; c.height = H;
      var ctx = c.getContext('2d'); ctx.fillStyle = '#f8fafc'; ctx.fillRect(0, 0, W, H); ctx.drawImage(img, 0, 0, W, H);
      URL.revokeObjectURL(url);
      c.toBlob(function (b) { var a = document.createElement('a'); a.href = URL.createObjectURL(b); a.download = name; a.click(); setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000); });
    };
    img.onerror = function () { toast('Не удалось сохранить PNG', 'err'); };
    img.src = url;
  }
  function open3d() {
    ui.dialog({ title: '3D-превью (изометрия)', html: true, cancelText: 'Закрыть', body:
      '<div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:8px"><label>Угол обзора</label><input type="range" id="v3ang" min="0" max="360" value="55" style="flex:1;min-width:160px"><label>Высота</label><input type="range" id="v3ext" min="30" max="220" value="100"><button class="btn secondary" id="v3png" style="width:auto">Скачать PNG</button></div><div id="v3host">' + iso3d(55, 1) + '</div>' });
    var host = document.getElementById('v3host'), ra = document.getElementById('v3ang'), re = document.getElementById('v3ext');
    function cur() { return iso3d(Number(ra.value), Number(re.value) / 100); }
    function upd() { host.innerHTML = cur(); }
    if (ra) ra.oninput = upd; if (re) re.oninput = upd;
    var pb = document.getElementById('v3png');
    if (pb) pb.onclick = function () { iso3dSvgPng(cur(), ($('#proj').value || 'layout') + '-3d.png'); };
  }

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
    g += bgLayer();
    if ($('#gridChk') && $('#gridChk').checked) {
      for (var x = 0; x <= S.w; x += GRID * 5) g += '<line x1="' + x + '" y1="0" x2="' + x + '" y2="' + S.h + '" class="gl" stroke-width="' + (GRID / 12) + '"/>';
      for (var y = 0; y <= S.h; y += GRID * 5) g += '<line x1="0" y1="' + y + '" x2="' + S.w + '" y2="' + y + '" class="gl" stroke-width="' + (GRID / 12) + '"/>';
    }
    g += (layers.links ? S.links : []).map(function (l) { var a = byId(l.a), b = byId(l.b); if (!a || !b) return ''; return '<line class="lk" x1="' + (a.x + a.w) + '" y1="' + (a.y + a.h / 2) + '" x2="' + b.x + '" y2="' + (b.y + b.h / 2) + '" marker-end="url(#ah)" data-lk="' + l.id + '"/>'; }).join('');
    g += (layers.routes ? S.routes : []).map(function (r) { return '<polyline class="rt" marker-end="url(#ahr)" data-rt="' + r.id + '" points="' + r.pts.map(function (p) { return p[0] + ',' + p[1]; }).join(' ') + '"/>'; }).join('');
    g += (layers.utils ? (S.utils || []) : []).map(function (u) { var kk = UTILS.filter(function (x) { return x.k === u.kind; })[0] || { c: '#888' }; return '<polyline data-ut="' + u.id + '" fill="none" stroke="' + kk.c + '" stroke-width="' + (GRID * 0.45) + '" stroke-dasharray="' + (GRID * 2) + ' ' + (GRID) + '" stroke-linejoin="round" points="' + u.pts.map(function (p) { return p[0] + ',' + p[1]; }).join(' ') + '"/>'; }).join('');
    if (utilPts.length && utilKind) { var kc = (UTILS.filter(function (x) { return x.k === utilKind; })[0] || {}).c; g += '<polyline fill="none" stroke="' + kc + '" stroke-width="' + (GRID * 0.45) + '" stroke-dasharray="' + (GRID) + '" points="' + utilPts.map(function (p) { return p[0] + ',' + p[1]; }).join(' ') + '"/>'; }
    g += S.items.filter(function (it) { return layers[layerOf(it.type)]; }).map(function (it) {
      var c = (STAGES[it.stage] || STAGES['new']).c, isz = it.type === 'zone' || it.type === 'aisle';
      return '<g class="li" data-id="' + it.id + '" transform="translate(' + it.x + ',' + it.y + ') rotate(' + (it.rot || 0) + ',' + (it.w / 2) + ',' + (it.h / 2) + ')">' +
        '<rect x="0" y="0" width="' + it.w + '" height="' + it.h + '" rx="' + (GRID / 2) + '" fill="' + (isz ? 'rgba(16,185,129,.08)' : c + '22') + '" stroke="' + (collHighlight.indexOf(it.id) >= 0 ? '#ef4444' : c) + '" stroke-width="' + (collHighlight.indexOf(it.id) >= 0 ? GRID / 2 : (sel === it.id ? GRID / 2 : GRID / 4)) + '"' + (isz ? ' stroke-dasharray="' + GRID / 2 + ' ' + GRID / 3 + '"' : '') + '/>' +
        glyph(it) +
        '<text x="' + (it.w / 2) + '" y="' + (it.h / 2 + Math.max(70, Math.min(it.w, it.h) / 3.4)) + '" text-anchor="middle" font-size="' + Math.max(130, Math.min(it.w, it.h) / 9) + '" class="ln">' + esc(it.name) + '</text>' +
        ($('#dimChk') && $('#dimChk').checked ? '<text x="' + (it.w / 2) + '" y="' + (it.h / 2 - Math.max(70, Math.min(it.w, it.h) / 3.4)) + '" text-anchor="middle" font-size="' + Math.max(115, Math.min(it.w, it.h) / 11) + '" fill="#64748b">' + Math.round(it.w) + '×' + Math.round(it.h) + '</text>' : '') +
        (isz ? '' : '<circle cx="0" cy="' + (it.h / 2) + '" r="' + (GRID * 0.6) + '" fill="#0ea5e9"/><circle cx="' + it.w + '" cy="' + (it.h / 2) + '" r="' + (GRID * 0.6) + '" fill="#0ea5e9"/>') +
        (sel === it.id ? (function () {
          var R = GRID * 1.2, m = GRID * 1.8, hd = GRID * 1.1, t = Math.max(130, Math.min(it.w, it.h) / 12);
          var s = '';
          /* L2: размерные линии выбранного узла (ширина сверху, высота слева) */
          s += '<g stroke="#0ea5e9" stroke-width="' + (GRID / 6) + '">' +
            '<line x1="0" y1="' + (-m) + '" x2="' + it.w + '" y2="' + (-m) + '"/>' +
            '<line x1="0" y1="' + (-m - hd) + '" x2="0" y2="' + (-m + hd) + '"/>' +
            '<line x1="' + it.w + '" y1="' + (-m - hd) + '" x2="' + it.w + '" y2="' + (-m + hd) + '"/>' +
            '<line x1="' + (-m) + '" y1="0" x2="' + (-m) + '" y2="' + it.h + '"/>' +
            '<line x1="' + (-m - hd) + '" y1="0" x2="' + (-m + hd) + '" y2="0"/>' +
            '<line x1="' + (-m - hd) + '" y1="' + it.h + '" x2="' + (-m + hd) + '" y2="' + it.h + '"/></g>' +
            '<text x="' + (it.w / 2) + '" y="' + (-m - GRID * 0.4) + '" text-anchor="middle" font-size="' + t + '" fill="#0284c7">' + Math.round(it.w) + ' мм</text>' +
            '<text x="' + (-m - GRID * 0.5) + '" y="' + (it.h / 2) + '" text-anchor="middle" font-size="' + t + '" fill="#0284c7" transform="rotate(-90 ' + (-m - GRID * 0.5) + ' ' + (it.h / 2) + ')">' + Math.round(it.h) + ' мм</text>' +
            (it.rot ? '<text x="' + (it.w / 2) + '" y="' + (-m - GRID * 2.4) + '" text-anchor="middle" font-size="' + t + '" fill="#0284c7">' + Math.round(it.rot) + '°</text>' : '') +
            /* маркер поворота */
            '<line x1="' + (it.w / 2) + '" y1="0" x2="' + (it.w / 2) + '" y2="' + (-GRID * 3.4) + '" stroke="#10b981" stroke-width="' + (GRID / 6) + '"/>' +
            '<circle class="rh" data-h="rot" cx="' + (it.w / 2) + '" cy="' + (-GRID * 3.8) + '" r="' + (GRID * 0.7) + '" fill="#10b981" stroke="#fff" stroke-width="' + (GRID / 5) + '" style="cursor:grab"/>';
          /* L-P10: размеры «от стены» (ближайшая стена-объект слева/сверху, иначе край плана) */
          (function () {
            if (it.type === 'wall' || it.type === 'zone' || it.type === 'aisle') return;
            var dL = it.x, dT = it.y;
            S.items.forEach(function (o) {
              if (o.type !== 'wall' || o === it) return;
              var right = o.x + o.w; if (right <= it.x && (it.x - right) < dL) dL = it.x - right;
              var bot = o.y + o.h; if (bot <= it.y && (it.y - bot) < dT) dT = it.y - bot;
            });
            if (dL > 0) {
              s += '<line x1="' + (-dL) + '" y1="' + (it.h / 2) + '" x2="0" y2="' + (it.h / 2) + '" stroke="#64748b" stroke-dasharray="' + (GRID) + '"/>' +
                '<text x="' + (-dL / 2) + '" y="' + (it.h / 2 - GRID * 0.4) + '" text-anchor="middle" font-size="' + t + '" fill="#64748b">' + Math.round(dL) + '</text>';
            }
            if (dT > 0) {
              s += '<line x1="' + (it.w / 2) + '" y1="' + (-dT) + '" x2="' + (it.w / 2) + '" y2="0" stroke="#64748b" stroke-dasharray="' + (GRID) + '"/>' +
                '<text x="' + (it.w / 2 + GRID * 0.5) + '" y="' + (-dT / 2) + '" font-size="' + t + '" fill="#64748b">' + Math.round(dT) + '</text>';
            }
          })();
          s += ['nw', 'ne', 'sw', 'se'].map(function (d) {
            var cx = d.indexOf('e') >= 0 ? it.w : 0, cy = d.indexOf('s') >= 0 ? it.h : 0;
            return '<rect class="rz" data-h="' + d + '" x="' + (cx - R) + '" y="' + (cy - R) + '" width="' + (R * 2) + '" height="' + (R * 2) + '" rx="' + (R / 2) + '" fill="#10b981" stroke="#fff" stroke-width="' + (GRID / 5) + '" style="cursor:' + (d === 'nw' || d === 'se' ? 'nwse-resize' : 'nesw-resize') + '"/>';
          }).join('');
          return s;
        })() : '') +
        '</g>';
    }).join('');
    g += (layers.notes ? S.notes : []).map(function (n) { return '<g class="nt" data-note="' + n.id + '" transform="translate(' + n.x + ',' + n.y + ')"><circle r="' + GRID * 0.9 + '" fill="#f59e0b" stroke="#fff" stroke-width="' + GRID / 6 + '"/><text y="' + GRID * 0.35 + '" text-anchor="middle" font-size="' + GRID * 1.1 + '" fill="#fff">!</text></g>'; }).join('');
    var mark = flowMark(); if (mark) g += '<circle class="fm" cx="' + mark[0] + '" cy="' + mark[1] + '" r="' + GRID * 0.9 + '" fill="#2563eb" stroke="#fff" stroke-width="' + GRID / 6 + '"/>';
    svg.innerHTML = g;
    var eh = $('#emptyHint'); if (eh) eh.style.display = S.items.length ? 'none' : '';
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
        if (e.target.classList && (e.target.classList.contains('rz') || e.target.classList.contains('rh'))) return;
        var id = gEl.getAttribute('data-id');
        if (tool === 'route') { var p = stagePct(e); routePts.push(p); previewRoute(); e.preventDefault(); return; }
        if (tool === 'util') { utilPts.push(stagePct(e)); draw(); e.preventDefault(); return; }
        if (tool === 'link') {
          if (linkFrom && linkFrom !== id) { snapshot(); S.links.push({ id: uid('l'), a: linkFrom, b: id, kind: 'conveyor' }); renderLists(); linkFrom = null; draw(); }
          else linkFrom = id; toast(linkFrom ? 'Выберите второй элемент для связи' : 'Готово');
          e.stopPropagation(); return;
        }
        if (mode === 'demo') return;
        sel = id; prop(); draw();
        var it = byId(id); if (!it) return;
        var sx = e.clientX, sy = e.clientY, ox = it.x, oy = it.y, sc = 1 / zoom, moved = 0;
        function mv(ev) {
          moved = 1; var nx = snapv(ox + (ev.clientX - sx) * sc), ny = snapv(oy + (ev.clientY - sy) * sc);
          if ($('#snapChk') && $('#snapChk').checked) {
            var TH = GRID * 3;
            /* L-P10: магниты к краям плана */
            if (Math.abs(nx) < TH) nx = 0;
            if (Math.abs(ny) < TH) ny = 0;
            if (Math.abs((nx + it.w) - S.w) < TH) nx = S.w - it.w;
            if (Math.abs((ny + it.h) - S.h) < TH) ny = S.h - it.h;
            /* магниты к стенам/зонам/оборудованию по рёбрам */
            S.items.forEach(function (o) {
              if (o === it) return;
              var vcClose = Math.abs((ny + it.h / 2) - (o.y + o.h / 2)) < TH;
              var hcClose = Math.abs((nx + it.w / 2) - (o.x + o.w / 2)) < TH;
              if (vcClose) {
                if (Math.abs(nx - (o.x + o.w)) < TH) nx = o.x + o.w;
                else if (Math.abs((nx + it.w) - o.x) < TH) nx = o.x - it.w;
                else if (Math.abs(nx - o.x) < TH) nx = o.x;
                else if (Math.abs((nx + it.w) - (o.x + o.w)) < TH) nx = o.x + o.w - it.w;
              }
              if (hcClose) {
                if (Math.abs(ny - (o.y + o.h)) < TH) ny = o.y + o.h;
                else if (Math.abs((ny + it.h) - o.y) < TH) ny = o.y - it.h;
                else if (Math.abs(ny - o.y) < TH) ny = o.y;
                else if (Math.abs((ny + it.h) - (o.y + o.h)) < TH) ny = o.y + o.h - it.h;
              }
            });
          }
          it.x = nx; it.y = ny; draw();
        }
        function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); if (moved) { snapshot(); } }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up); e.preventDefault();
      };
    });
    $$('#cv .rz').forEach(function (h) {
      h.addEventListener('mousedown', function (e) {
        e.preventDefault(); e.stopPropagation();
        var it = byId(sel); if (!it) return;
        var dir = h.getAttribute('data-h') || 'se';
        var sx = e.clientX, sy = e.clientY, ow = it.w, oh = it.h, ox = it.x, oy = it.y, sc = 1 / zoom;
        function mv(ev) {
          var dx = (ev.clientX - sx) * sc, dy = (ev.clientY - sy) * sc, nw = ow, nh = oh, nx = ox, ny = oy;
          if (dir.indexOf('e') >= 0) nw = ow + dx;
          if (dir.indexOf('w') >= 0) { nw = ow - dx; nx = ox + dx; }
          if (dir.indexOf('s') >= 0) nh = oh + dy;
          if (dir.indexOf('n') >= 0) { nh = oh - dy; ny = oy + dy; }
          it.w = Math.max(GRID * 3, snapv(nw)); it.h = Math.max(GRID * 3, snapv(nh));
          it.x = snapv(nx); it.y = snapv(ny);
          draw();
        }
        function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); snapshot(); }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
      });
    });
    $$('#cv .nt').forEach(function (gEl) { gEl.onclick = function (e) { var id = gEl.getAttribute('data-note'); var n = S.notes.filter(function (x) { return x.id === id; })[0]; if (n) alert('Комментарий: ' + (n.text || '(пусто)')); e.stopPropagation(); }; });
    /* L2: поворот выбранного узла за маркер (привязка к 15°) */
    $$('#cv .rh').forEach(function (h) {
      h.addEventListener('mousedown', function (e) {
        e.preventDefault(); e.stopPropagation();
        var it = byId(sel); if (!it) return;
        var r = $('#cv').getBoundingClientRect();
        function mv(ev) {
          var cx = (ev.clientX - r.left) / r.width * S.w, cy = (ev.clientY - r.top) / r.height * S.h;
          var deg = Math.atan2(cy - (it.y + it.h / 2), cx - (it.x + it.w / 2)) * 180 / Math.PI + 90;
          if ($('#snapChk') && $('#snapChk').checked) deg = Math.round(deg / 15) * 15;
          it.rot = ((Math.round(deg) % 360) + 360) % 360; draw();
        }
        function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); snapshot(); prop(); }
        document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
      });
    });
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
      '<div class="grid2"><div><label>Ширина, мм</label><input id="pW" type="number" value="' + it.w + '"></div><div><label>Высота, мм</label><input id="pH" type="number" value="' + it.h + '"></div></div>' +
      '<div class="grid2"><div><label>Поворот, °</label><input id="pRot" type="number" min="0" max="359" step="15" value="' + (it.rot || 0) + '"></div><div style="display:flex;align-items:flex-end"><button class="btn secondary" id="pRot90" style="width:auto" aria-label="Повернуть на 90°" title="Повернуть на 90°">↻ 90°</button></div></div>' +
      '<div class="btn-row mt"><button class="btn secondary" id="pDup">⧉ Копия</button><button class="btn secondary" id="pDel">✕ Удалить</button></div>';
    $('#pName').oninput = function () { it.name = this.value; draw(); };
    $('#pStage').onchange = function () { it.stage = this.value; draw(); };
    ['pX:x', 'pY:y', 'pW:w', 'pH:h'].forEach(function (pp) { var id = pp.split(':')[0], k = pp.split(':')[1]; $('#' + id).onchange = function () { it[k] = Number(this.value) || 0; draw(); }; });
    $('#pRot90').onclick = function () { it.rot = ((it.rot || 0) + 90) % 360; draw(); prop(); };
    $('#pRot').onchange = function () { it.rot = ((Math.round(Number(this.value) || 0) % 360) + 360) % 360; draw(); };
    $('#pDup').onclick = function () { snapshot(); var c = deep(it); c.id = uid(); c.x += GRID * 3; c.y += GRID * 3; S.items.push(c); sel = c.id; draw(); prop(); };
    $('#pDel').onclick = function () { snapshot(); S.items = S.items.filter(function (x) { return x.id !== sel; }); sel = null; draw(); prop(); };
  }
  function renderLists() {
    var nl = $('#notesList'); if (nl) nl.innerHTML = S.notes.length ? S.notes.map(function (n) { return '<div class="lkrow"><span>' + esc(n.text || 'метка') + '</span><button class="act" data-ndel="' + n.id + '" aria-label="Удалить" title="Удалить">✕</button></div>'; }).join('') : '<span class="note">Меток нет.</span>';
    var ll = $('#linksList'); if (ll) ll.innerHTML = S.links.length ? S.links.map(function (l) { var a = byId(l.a), b = byId(l.b); return '<div class="lkrow"><span>' + esc((a && a.name) || '?') + ' ↔ ' + esc((b && b.name) || '?') + '</span><button class="act" data-ldel="' + l.id + '" aria-label="Удалить" title="Удалить">✕</button></div>'; }).join('') : '<span class="note">Связей нет.</span>';
    var rl = $('#routeList'); if (rl) rl.innerHTML = S.routes.length ? S.routes.map(function (r, i) { return '<div class="lkrow"><span>Маршрут ' + (i + 1) + ' · ' + r.pts.length + ' тчк</span><button class="act" data-rdel="' + r.id + '" aria-label="Удалить" title="Удалить">✕</button></div>'; }).join('') : '<span class="note">Маршрутов нет.</span>';
    $$('[data-ndel]').forEach(function (b) { b.onclick = function () { snapshot(); S.notes = S.notes.filter(function (x) { return x.id !== b.dataset.ndel; }); renderLists(); draw(); }; });
    $$('[data-ldel]').forEach(function (b) { b.onclick = function () { snapshot(); S.links = S.links.filter(function (x) { return x.id !== b.dataset.ldel; }); renderLists(); draw(); }; });
    $$('[data-rdel]').forEach(function (b) { b.onclick = function () { snapshot(); S.routes = S.routes.filter(function (x) { return x.id !== b.dataset.rdel; }); renderLists(); draw(); }; });
    renderUtils();
  }
  function pathLen(pts) { var L = 0; for (var i = 1; i < pts.length; i++) L += Math.sqrt(Math.pow(pts[i][0] - pts[i - 1][0], 2) + Math.pow(pts[i][1] - pts[i - 1][1], 2)); return L; }
  function renderUtils() {
    var host = $('#utilsList'); if (!host) return;
    var by = {}; (S.utils || []).forEach(function (u) { by[u.kind] = (by[u.kind] || 0) + pathLen(u.pts); });
    host.innerHTML = UTILS.map(function (x) {
      return '<div class="utrow"><span class="utsw" style="background:' + x.c + '"></span><span>' + x.l + '</span><b>' + ((by[x.k] || 0) / 1000).toFixed(2) + ' м</b><button class="act" data-util="' + x.k + '">Проложить</button></div>';
    }).join('');
    $$('#utilsList [data-util]').forEach(function (b) { b.onclick = function () { utilKind = b.dataset.util; utilPts = []; tool = 'util'; toast('Кликайте точки коммуникации; «Завершить» — сохранить'); }; });
  }

  /* ---------- L1: слои и легенда ---------- */
  function renderLayers() {
    var host = $('#layersPanel'); if (!host) return;
    host.innerHTML =
      '<div class="btn-row" style="gap:6px;margin-bottom:6px"><button class="btn secondary" id="lyAll" style="width:auto">Показать всё</button><button class="btn secondary" id="lyNone" style="width:auto">Скрыть всё</button></div>' +
      LAYERS.map(function (x) { return '<label class="utrow" style="cursor:pointer"><input type="checkbox" data-ly="' + x.k + '" style="width:auto;flex:0 0 auto"' + (layers[x.k] ? ' checked' : '') + '> <span>' + x.ic + ' ' + x.l + '</span></label>'; }).join('') +
      '<div class="pal-g" style="margin-top:10px">Этапы</div>' +
      Object.keys(STAGES).map(function (k) { return '<div class="utrow"><span class="utsw" style="background:' + STAGES[k].c + '"></span><span>' + STAGES[k].l + '</span></div>'; }).join('') +
      '<div class="pal-g" style="margin-top:10px">Коммуникации</div>' +
      UTILS.map(function (u) { return '<div class="utrow"><span class="utsw" style="background:' + u.c + '"></span><span>' + u.l + '</span></div>'; }).join('');
    $$('#layersPanel [data-ly]').forEach(function (c) { c.onchange = function () { layers[this.dataset.ly] = this.checked; saveLayers(); draw(); }; });
    var a = document.getElementById('lyAll'), n = document.getElementById('lyNone');
    if (a) a.onclick = function () { LAYERS.forEach(function (x) { layers[x.k] = true; }); saveLayers(); renderLayers(); draw(); };
    if (n) n.onclick = function () { LAYERS.forEach(function (x) { layers[x.k] = false; }); saveLayers(); renderLayers(); draw(); };
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
  function applyData(d) { S = { w: d.w || W, h: d.h || H, items: d.items || [], notes: d.notes || [], links: d.links || [], routes: d.routes || [], utils: d.utils || [], bg: d.bg || null }; sel = null; history = []; redo = []; syncHist(); draw(); prop(); renderLists(); }
  function loadList() {
    return rpc('app_layout_plan_list', { p_token: token }).then(function (rows) {
      rows = rows || [];
      $('#plans').innerHTML = rows.length ? rows.map(function (p) { return '<div class="plrow' + (p.id === planId ? ' on' : '') + '" data-open="' + p.id + '"><b>' + esc(p.name) + '</b><small>' + esc(KINDS[p.kind] || p.kind) + ' · ' + p.items + ' эл.</small><span class="pl-act"><button class="act" data-del="' + p.id + '" aria-label="Удалить" title="Удалить">✕</button></span></div>'; }).join('') : '<span class="note">Проектов нет.</span>';
      $$('#plans [data-open]').forEach(function (r) { r.onclick = function (e) { if (e.target.dataset.del) return; openPlan(r.dataset.open); }; });
      $$('#plans [data-del]').forEach(function (b) { b.onclick = function () { rpc('app_layout_plan_delete', { p_token: token, p_id: b.dataset.del }).then(function () { toast('Удалено'); if (b.dataset.del === planId) { planId = null; applyData({}); } loadList(); }); }; });
    });
  }
  var KINDS = { shop: 'Цех', office: 'Офис', compressor: 'Компрессорная', line: 'Линия', other: 'Другое' };
  function openPlan(id) { return rpc('app_layout_plan_get', { p_token: token, p_id: id }).then(function (r) { var p = r && r[0]; if (!p) return; planId = p.id; $('#proj').value = p.name || ''; $('#kind').value = p.kind || 'shop'; applyData(p.data || {}); fitZoom(); draw(); centerView(); baseline = deep(S); loadList(); }); }
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
  function exportJson() { dl(($('#proj').value || 'layout') + '.json', JSON.stringify({ name: $('#proj').value, kind: $('#kind').value, w: S.w, h: S.h, items: S.items, notes: S.notes, links: S.links, routes: S.routes, utils: S.utils, bg: S.bg || null }, null, 2), 'application/json'); }
  function importJson(file) { var fr = new FileReader(); fr.onload = function () { try { var d = JSON.parse(fr.result); if (d.name) $('#proj').value = d.name; if (d.kind) $('#kind').value = d.kind; applyData(d); baseline = deep(S); toast('Импортировано'); } catch (e) { toast('Некорректный JSON', 'err'); } }; fr.readAsText(file); }
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
  function finishRoute() {
    if (tool === 'util') { if (utilPts.length >= 2) { snapshot(); S.utils.push({ id: uid('u'), kind: utilKind, pts: utilPts.slice() }); } utilPts = []; utilKind = null; tool = 'sel'; renderLists(); draw(); return; }
    if (routePts.length < 2) { routePts = []; tool = 'sel'; return; }
    snapshot(); S.routes.push({ id: uid('r'), pts: routePts.slice() }); routePts = []; tool = 'sel'; renderLists(); draw();
  }
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
  $('#zi').onclick = function () { zoom = Math.min(ZMAX, zoom * 1.25); draw(); }; $('#zo').onclick = function () { zoom = Math.max(ZMIN, zoom / 1.25); draw(); };
  $('#zFit').onclick = function () { zoom = 1; draw(); };
  $('#gridChk').onchange = draw; $('#snapChk').onchange = draw; if ($('#dimChk')) $('#dimChk').onchange = draw;
  $('#palBtn').onclick = function () { $('#editor').classList.toggle('no-pal'); };
  $('#propsBtn').onclick = function () { $('#editor').classList.toggle('no-props'); };
  $('#soloBtn').onclick = function () { $('#editor').classList.toggle('solo'); };
  $('#themeBtn').onclick = toggleTheme;
  $$('#tabs button').forEach(function (b) { b.onclick = function () { $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); }); var id = b.dataset.tab; ['prop', 'notes', 'links', 'flow', 'layers'].forEach(function (k) { $('#tab-' + k).style.display = k === id ? '' : 'none'; }); if (id === 'layers') renderLayers(); }; });
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
    if (tool === 'util') { utilPts.push(stagePct(e)); draw(); return; }
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
    if (e.key === 'Escape') {
      var ed = $('#editor');
      if (ed && ed.classList.contains('expanded')) { ed.classList.remove('expanded'); document.body.classList.remove('ed-expanded'); var fb = $('#fsBtn'); if (fb) fb.textContent = '⤢ Развернуть'; setTimeout(function () { fitZoom(); draw(); centerView(); }, 60); }
      routePts = []; utilPts = []; utilKind = null; tool = 'sel'; setTool('sel'); draw();
    }
    if (e.key.toLowerCase() === 'v') setTool('sel'); if (e.key.toLowerCase() === 'h') setTool('pan'); if (e.key.toLowerCase() === 'c') setTool('note');
  };
  function contentBox() {
    var list = S.items.length ? S.items : [{ x: 0, y: 0, w: S.w, h: S.h }];
    var x0 = Math.min.apply(null, list.map(function (i) { return i.x; })), y0 = Math.min.apply(null, list.map(function (i) { return i.y; }));
    var x1 = Math.max.apply(null, list.map(function (i) { return i.x + i.w; })), y1 = Math.max.apply(null, list.map(function (i) { return i.y + i.h; }));
    return { x: x0, y: y0, w: Math.max(x1 - x0, 800), h: Math.max(y1 - y0, 600) };
  }
  function fitZoom() { var w = $('#cvWrap'); if (!w) return; var b = contentBox(); var z = Math.min((w.clientWidth - 40) / b.w, (w.clientHeight - 40) / b.h); zoom = Math.max(ZMIN, Math.min(ZMAX, z || 1)); }
  function centerView() { var w = $('#cvWrap'); if (!w) return; var b = contentBox(); w.scrollLeft = Math.max(0, (b.x + b.w / 2) * zoom - w.clientWidth / 2); w.scrollTop = Math.max(0, (b.y + b.h / 2) * zoom - w.clientHeight / 2); }
  function showReport() {
    var len = 0; S.routes.forEach(function (r) { for (var i = 1; i < r.pts.length; i++) len += Math.sqrt(Math.pow(r.pts[i][0] - r.pts[i - 1][0], 2) + Math.pow(r.pts[i][1] - r.pts[i - 1][1], 2)); });
    var cnt = S.items.filter(function (i) { return i.type !== 'zone' && i.type !== 'aisle'; }).length;
    ui.dialog({ title: 'Отчёт по потоку', html: true, cancelText: 'Закрыть', body:
      '<p>Оборудование/элементы: <b>' + cnt + '</b></p><p>Связей: <b>' + S.links.length + '</b> · маршрутов: <b>' + S.routes.length + '</b></p>' +
      '<p>Длина маршрутов: <b>' + (len / 1000).toFixed(1) + ' м</b></p><p>Меток: <b>' + S.notes.length + '</b></p>' });
  }
  $('#zPlan').onclick = function () { fitZoom(); draw(); centerView(); };
  /* Масштаб колёсиком мыши (зум к курсору) */
  function zoomAtPoint(cx, cy, factor) {
    var w = $('#cvWrap'); if (!w) return;
    var r = $('#cv').getBoundingClientRect();
    var px = (cx - r.left) / zoom, py = (cy - r.top) / zoom;   // координаты плана под курсором
    var old = zoom;
    zoom = Math.max(ZMIN, Math.min(ZMAX, zoom * factor));
    if (Math.abs(zoom - old) < 1e-6) return;
    draw();
    var r2 = $('#cv').getBoundingClientRect();
    w.scrollLeft += (px * zoom) - (cx - r2.left);
    w.scrollTop += (py * zoom) - (cy - r2.top);
  }
  (function () {
    var wrap = $('#cvWrap'), svg = $('#cv'); if (!wrap) return;
    function inCanvas(e) {
      var r = wrap.getBoundingClientRect();
      return e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom;
    }
    function onWheel(e) {
      if (!inCanvas(e)) return;                 // колесо над панелями — обычная прокрутка
      e.preventDefault();
      var dy = e.deltaY || 0;
      if (e.deltaMode === 1) dy *= 16; else if (e.deltaMode === 2) dy *= 100;
      if (!dy) return;
      zoomAtPoint(e.clientX, e.clientY, Math.exp(-dy * 0.0015));
    }
    wrap.addEventListener('wheel', onWheel, { passive: false });
    if (svg) svg.addEventListener('wheel', onWheel, { passive: false });
    document.addEventListener('keydown', function (e) {
      if (!(e.ctrlKey || e.metaKey)) return;
      if (e.key === '+' || e.key === '=') { e.preventDefault(); zoom = Math.min(ZMAX, zoom * 1.2); draw(); }
      else if (e.key === '-' || e.key === '_') { e.preventDefault(); zoom = Math.max(ZMIN, zoom / 1.2); draw(); }
      else if (e.key === '0') { e.preventDefault(); zoom = 1; draw(); }
    });
  })();
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
    if ($('#zSlider')) $('#zSlider').oninput = function () { zoom = Math.max(ZMIN, Math.min(ZMAX, (Number(this.value) || 100) / 100)); draw(); };
  if ($('#zStage')) $('#zStage').onclick = function () { zoomToBBox(S.items.filter(function (i) { return i.stage === 'new'; })); };
  if ($('#fsBtn')) $('#fsBtn').onclick = function () {
    var ed = $('#editor'); var on = ed.classList.toggle('expanded'); document.body.classList.toggle('ed-expanded', on);
    this.textContent = on ? '⤢ Свернуть' : '⤢ Развернуть';
    setTimeout(function () { fitZoom(); draw(); centerView(); }, 60);
  };
  var DEMO = {
    w: 16000, h: 9000, notes: [], links: [],
    items: [
      { id: 'd1', type: 'lathe', name: 'ОЦ токарный', x: 1500, y: 1200, w: 2800, h: 1800, rot: 0, stage: 'new' },
      { id: 'd2', type: 'mill', name: 'ОЦ фрезерный', x: 1500, y: 3600, w: 3200, h: 2600, rot: 0, stage: 'new' },
      { id: 'd3', type: 'turn', name: 'Поворотный', x: 5600, y: 4200, w: 2400, h: 2400, rot: 0, stage: 'new' },
      { id: 'd4', type: 'accum', name: 'Накопитель', x: 5600, y: 1200, w: 6000, h: 1400, rot: 0, stage: 'new' },
      { id: 'd5', type: 'robot6', name: 'Робот 6-осевой', x: 8800, y: 4200, w: 2500, h: 2500, rot: 0, stage: 'new' },
      { id: 'd6', type: 'robot6', name: 'Робот SCARA', x: 8800, y: 4200, w: 2200, h: 2200, rot: 0, stage: 'exist' },
      { id: 'd7', type: 'view', name: '', x: 0, y: 0, w: 0, h: 0, stage: 'exist' },
      { id: 'd8', type: 'conv', name: 'Конвейер', x: 11800, y: 1200, w: 3000, h: 900, rot: 0, stage: 'new' },
      { id: 'd9', type: 'rack', name: 'Стеллаж', x: 11800, y: 4200, w: 2700, h: 1100, rot: 0, stage: 'new' },
      { id: 'd10', type: 'cmm', name: 'КИМ', x: 1500, y: 6400, w: 2000, h: 1600, rot: 0, stage: 'new' },
      { id: 'd11', type: 'cabinet', name: 'Шкаф управления', x: 4200, y: 1200, w: 1200, h: 600, rot: 0, stage: 'new' },
      { id: 'd12', type: 'zone', name: 'Зона безопасности', x: 8200, y: 3600, w: 4200, h: 3400, rot: 0, stage: 'exist' }
    ],
    routes: [{ id: 'dr1', pts: [[2900, 2100], [2900, 4600], [5600, 5400], [8800, 5400], [11800, 1650]] }],
    utils: [{ id: 'du1', kind: 'electric', pts: [[2100, 1500], [4500, 1500], [4500, 5000], [9000, 5000]] }, { id: 'du2', kind: 'air', pts: [[2100, 3900], [7800, 3900]] }]
  };
  DEMO.items = DEMO.items.filter(function (i) { return i.w > 0; });
  if ($('#demoBtn')) $('#demoBtn').onclick = function () {
    snapshot(); planId = null; $('#proj').value = 'Демо: линия (из robot)'; $('#kind').value = 'line';
    applyData(deep(DEMO)); fitZoom(); draw(); centerView(); baseline = deep(S); logEvent('Загружен демо-проект (robot)');
  };
  document.addEventListener('fullscreenchange', function () { setTimeout(function () { fitZoom(); draw(); centerView(); }, 60); });
  function renderVersions(host) {
    rpc('app_layout_plan_version_list', { p_token: token, p_layout_id: planId }).then(function (rows) {
      rows = rows || [];
      host.innerHTML = rows.length ? rows.map(function (v) { return '<div class="plrow"><b>v' + v.version + '</b> <small>' + (v.name ? esc(v.name) + ' · ' : '') + new Date(v.at).toLocaleString('ru-RU') + ' · ' + esc(v.created_by || '') + '</small><span class="pl-act"><button class="act" data-restore="' + v.id + '">Откатить</button></span></div>'; }).join('') : '<span class="note">Версий нет.</span>';
      Array.prototype.forEach.call(host.querySelectorAll('[data-restore]'), function (b) {
        b.onclick = function () {
          rpc('app_layout_plan_version_get', { p_token: token, p_version_id: b.dataset.restore }).then(function (d) {
            var x = d && d[0]; if (!x) return; snapshot(); applyData(x.data || {}); fitZoom(); draw(); centerView(); toast('Восстановлена версия v' + x.version);
          });
        };
      });
    }).catch(function (e) { host.innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
  }
  if ($('#histBtn')) $('#histBtn').onclick = function () {
    if (!planId) { toast('Сохраните планировку, чтобы вести историю'); return; }
    ui.dialog({ title: 'История версий', html: true, cancelText: 'Закрыть', body: '<button class="btn secondary" id="verSave" style="width:auto">＋ Сохранить версию</button><div id="verList" class="mlist" style="margin-top:8px"></div>' });
    var host = document.getElementById('verList'); renderVersions(host);
    var vs = document.getElementById('verSave');
    if (vs) vs.onclick = function () {
      rpc('app_layout_plan_version_save', { p_token: token, p_layout_id: planId, p_name: prompt('Название версии (необязательно):', '') })
        .then(function (d) { var x = d && d[0]; toast((x && x.message) || 'Готово'); renderVersions(host); })
        .catch(function (e) { toast('Ошибка: ' + e.message, 'err'); });
    };
  };
  if ($('#setBtn')) $('#setBtn').onclick = function () {
    var html = '<label>Скорость потока</label><select id="setSpd">' + [['900', 'медленно'], ['1800', 'обычно'], ['3600', 'быстро']].map(function (o) { return '<option value="' + o[0] + '"' + (String(flow.spd) === o[0] ? ' selected' : '') + '>' + o[1] + '</option>'; }).join('') + '</select>' +
      '<label class="ck" style="display:flex;gap:6px;align-items:center;margin-top:8px"><input type="checkbox" id="setGrid" ' + ($('#gridChk').checked ? 'checked' : '') + '> Сетка</label>' +
      '<label class="ck" style="display:flex;gap:6px;align-items:center;margin-top:6px"><input type="checkbox" id="setSnap" ' + ($('#snapChk').checked ? 'checked' : '') + '> Привязка</label>' +
      '<label class="ck" style="display:flex;gap:6px;align-items:center;margin-top:6px"><input type="checkbox" id="setDim" ' + ($('#dimChk') && $('#dimChk').checked ? 'checked' : '') + '> Размеры на плане</label>' +
      '<label style="margin-top:8px">Прозрачность подложки</label><input type="range" id="setBgOp" min="5" max="100" value="' + Math.round(((S.bg && S.bg.opacity != null ? S.bg.opacity : 0.5)) * 100) + '">' +
      (S.bg ? (function () { var r = bgRect(); return '<div class="pal-g" style="margin-top:10px">Калибровка подложки, мм</div>' +
        '<div class="grid2" style="gap:6px"><div><label>X</label><input id="setBgX" type="number" value="' + Math.round(r.x) + '"></div><div><label>Y</label><input id="setBgY" type="number" value="' + Math.round(r.y) + '"></div></div>' +
        '<div class="grid2" style="gap:6px"><div><label>Ширина</label><input id="setBgW" type="number" value="' + Math.round(r.w) + '"></div><div><label>Высота</label><input id="setBgH" type="number" value="' + Math.round(r.h) + '"></div></div>'; })() : '') +
      '<div class="btn-row mt" style="flex-wrap:wrap"><button class="btn secondary" id="setBgOff" style="width:auto">Убрать подложку</button>' + (S.bg ? '<button class="btn secondary" id="setBgFit" style="width:auto">Подогнать по плану</button>' : '') + '<button class="btn secondary" id="setRestore" style="width:auto">↺ Вернуть исходную схему</button><button class="btn secondary" id="setClear" style="width:auto">✕ Очистить</button><button class="btn secondary" id="setReset" style="width:auto">⟲ Полный сброс</button></div>';
    ui.dialog({ title: 'Настройки', html: true, cancelText: 'Закрыть', body: html });
    var bo = document.getElementById('setBgOp'); if (bo) bo.oninput = function () { if (!S.bg) S.bg = { href: null }; S.bg.opacity = Number(this.value) / 100; draw(); };
    var bof = document.getElementById('setBgOff'); if (bof) bof.onclick = function () { S.bg = null; draw(); toast('Подложка убрана'); };
    ['setBgX:x', 'setBgY:y', 'setBgW:w', 'setBgH:h'].forEach(function (p) { var id = p.split(':')[0], k = p.split(':')[1], el = document.getElementById(id); if (el) el.onchange = function () { if (!S.bg) return; var b = bgRect(); b[k] = Number(this.value) || 0; S.bg.x = b.x; S.bg.y = b.y; S.bg.w = b.w; S.bg.h = b.h; draw(); }; });
    var bf = document.getElementById('setBgFit'); if (bf) bf.onclick = function () { if (!S.bg) return; S.bg.x = 0; S.bg.y = 0; S.bg.w = S.w; S.bg.h = S.h; draw(); toast('Подложка растянута по плану'); };
    var sp = document.getElementById('setSpd'); if (sp) sp.onchange = function () { flow.spd = Number(this.value); };
    var g = document.getElementById('setGrid'); if (g) g.onchange = function () { $('#gridChk').checked = this.checked; draw(); };
    var sn = document.getElementById('setSnap'); if (sn) sn.onchange = function () { $('#snapChk').checked = this.checked; };
    var dm = document.getElementById('setDim'); if (dm) dm.onchange = function () { if ($('#dimChk')) $('#dimChk').checked = this.checked; draw(); };
    var rr = document.getElementById('setRestore'); if (rr) rr.onclick = function () { if (!baseline) { toast('Нет исходной схемы'); return; } snapshot(); applyData(deep(baseline)); fitZoom(); draw(); centerView(); toast('Возвращена исходная схема'); };
    var cc = document.getElementById('setClear'); if (cc) cc.onclick = function () { $('#clearBtn').click(); };
    var rs = document.getElementById('setReset'); if (rs) rs.onclick = function () { $('#resetBtn').click(); };
  };
  function bbox(i) { var w = (i.rot % 180 === 90) ? i.h : i.w, h = (i.rot % 180 === 90) ? i.w : i.h; return { x: i.x, y: i.y, w: w, h: h }; }
  function overlaps(a, b) { var A = bbox(a), B = bbox(b); return A.x < B.x + B.w && A.x + A.w > B.x && A.y < B.y + B.h && A.y + A.h > B.y; }
  if ($('#collBtn')) $('#collBtn').onclick = function () {
    var list = S.items.filter(function (i) { return i.type !== 'zone' && i.type !== 'aisle' && i.type !== 'label'; });
    var pairs = []; var ids = {};
    for (var i = 0; i < list.length; i++) for (var j = i + 1; j < list.length; j++) if (overlaps(list[i], list[j])) { pairs.push([list[i], list[j]]); ids[list[i].id] = 1; ids[list[j].id] = 1; }
    collHighlight = Object.keys(ids); draw();
    ui.dialog({ title: 'Проверка коллизий', html: true, cancelText: 'Закрыть', body:
      (pairs.length ? '<p><b>Пересечений: ' + pairs.length + '</b> (подсвечены красным на плане)</p><ul>' + pairs.map(function (p) { return '<li>' + esc(p[0].name) + ' ↔ ' + esc(p[1].name) + '</li>'; }).join('') + '</ul>'
        : '<p>Коллизий не обнаружено. Оборудование не пересекается.</p>') });
    logEvent('Проверка коллизий: ' + pairs.length + ' пересечений');
  };
  if ($('#bgBtn')) $('#bgBtn').onclick = function () { var f = $('#bgFile'); if (f) f.click(); };
  if ($('#view3d')) $('#view3d').onclick = open3d;
  /* L-P10: шаблоны участков */
  function tplItem(type, name, x, y, w, h) { return { id: uid(), type: type, name: name, x: snapv(x), y: snapv(y), w: w, h: h, stage: 'new', rot: 0 }; }
  function buildTemplate(key, x0, y0) {
    if (key === 'machining') return [
      tplItem('mill', 'Фрезерный ОЦ', x0, y0, 2600, 2200), tplItem('lathe', 'Токарный', x0 + 3200, y0, 2600, 1800),
      tplItem('mill', 'Фрезерный ОЦ 2', x0, y0 + 2800, 2600, 2200), tplItem('bench', 'Верстак', x0 + 3200, y0 + 2200, 1800, 900),
      tplItem('rack', 'Стеллаж', x0 + 6000, y0, 1200, 2400)];
    if (key === 'assembly') return [
      tplItem('conv', 'Конвейер 1', x0, y0 + 1200, 6000, 800), tplItem('conv', 'Конвейер 2', x0, y0 + 2200, 6000, 800),
      tplItem('bench', 'Сборка 1', x0 + 300, y0, 1800, 900), tplItem('bench', 'Сборка 2', x0 + 2400, y0, 1800, 900),
      tplItem('cabinet', 'Шкаф инструмента', x0 + 4500, y0, 1200, 1800)];
    if (key === 'warehouse') return [
      tplItem('rack', 'Стеллаж A', x0, y0, 1200, 6000), tplItem('rack', 'Стеллаж B', x0 + 4000, y0, 1200, 6000),
      tplItem('pallet', 'Паллета', x0 + 1800, y0 + 800, 1200, 1000), tplItem('agv', 'AGV', x0 + 1800, y0 + 3000, 1200, 1200),
      tplItem('zone', 'Зона приёмки', x0 + 1800, y0 + 4500, 1800, 1200)];
    return null;
  }
  function openTemplates() {
    ui.formDialog({ title: 'Шаблоны участков', okText: 'Добавить', fields: [
      { name: 'tpl', label: 'Шаблон', type: 'select', options: [{ value: 'machining', label: 'Участок мехобработки' }, { value: 'assembly', label: 'Линия сборки' }, { value: 'warehouse', label: 'Склад-стеллажи' }] },
      { name: 'mode', label: 'Размещение', type: 'select', options: [{ value: 'add', label: 'Добавить к текущим' }, { value: 'replace', label: 'Заменить содержимое' }] }
    ] }).then(function (v) {
      if (!v) return;
      var r = buildTemplate(v.tpl, 1000, 1000); if (!r) return;
      snapshot();
      if (v.mode === 'replace') S.items = r; else S.items = S.items.concat(r);
      sel = null; draw(); prop(); renderLists(); toast('Шаблон добавлен: объектов ' + r.length);
    });
  }
  if ($('#tplBtn')) $('#tplBtn').onclick = openTemplates;
  if ($('#bgFile')) $('#bgFile').onchange = function () {
    var file = this.files[0]; this.value = ''; if (!file) return;
    var isDxf = /\.dxf$/i.test(file.name);
    var fr = new FileReader();
    fr.onload = function () {
      if (isDxf) { loadDxf(file.name, String(fr.result)); }
      else { S.bg = { href: fr.result, opacity: 0.5, x: 0, y: 0, w: S.w, h: S.h }; draw(); toast('Подложка добавлена'); logEvent('Подложка загружена'); }
    };
    if (isDxf) fr.readAsText(file); else fr.readAsDataURL(file);
  };
  if ($('#helpBtn')) $('#helpBtn').onclick = function () {
    ui.dialog({ title: 'Как работает редактор', html: true, cancelText: 'Понятно', body:
      '<p><b>Инструменты:</b> ↖ выделение (V), ✋ рука (H), 💬 метка (C), 〰 маршрут, 🔗 связь.</p>' +
      '<p><b>Маршрут:</b> включите инструмент, кликайте точки (можно по оборудованию), «Завершить» (Enter). <b>Связь:</b> выберите два элемента.</p>' +
      '<p><b>Коммуникации:</b> вкладка «Связи» → вид (Питание/Воздух/Вода/Газ/Сеть) → «Проложить» → кликайте точки → «Завершить».</p>' +
      '<p><b>Узлы:</b> включите «Размеры» — показываются габариты (мм). У выбранного узла — размерные линии и маркер поворота (зелёный круг сверху): тяните для поворота (привязка 15°), либо задайте угол в свойствах.</p>' +
      '<p><b>Демонстрация:</b> режим «Демонстрация» показывает движение по маршруту (▶/◀, скорость в настройках).</p>' +
      '<p><b>Экспорт/печать:</b> JSON/SVG/PNG/HTML и «Печать/PDF». История версий — 🕘.</p>' +
      '<p><b>Подложка:</b> «Подложка» — растровый план (PNG/JPG) или чертёж **DXF** (LINE/LWPOLYLINE/POLYLINE/CIRCLE/ARC). Калибровка (X/Y/Ш/В, мм) и прозрачность — в ⚙ Настройках.</p>' +
      '<p><b>3D-превью:</b> кнопка «3D» — изометрический вид: узлы вытягиваются по высоте; ползунки меняют угол обзора и высоту; «Скачать PNG» сохраняет 3D-вид.</p>' +
      '<p><b>Привязки и шаблоны:</b> включённая «Привязка» магнитит узлы к рёбрам стен/зон/оборудования и краям плана; у выбранного узла показываются размеры «от стены». Кнопка «Шаблоны» вставляет типовой участок (мехобработка/сборка/склад).</p>' });
  };
  $('#logout').onclick = function () { window.Auth.logout(); location.href = '../../index.html'; };

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    token = s.token; $('#who').textContent = s.login + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    setTheme(localStorage.getItem('layout-theme') || 'dark');
    palette(); fitZoom(); draw(); centerView(); prop(); renderLists(); renderLayers(); loadList().catch(function () {}); baseline = deep(S);
    logEvent('Проект загружен');
    window.addEventListener('resize', function () { fitZoom(); draw(); centerView(); });
  });
})();
