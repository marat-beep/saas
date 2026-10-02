/* ============================================================
   B13 · Инструмент и NC-программы
   склад инструмента + библиотека NC (превью G-кода)
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var STOCK = [
    { id: 'TL-001', name: 'Фреза концевая Ø8', cat: 'Фрезы', qty: 24, min: 10, unit: 'шт', loc: 'Стеллаж A-1' },
    { id: 'TL-002', name: 'Фреза концевая Ø12', cat: 'Фрезы', qty: 6, min: 10, unit: 'шт', loc: 'Стеллаж A-1' },
    { id: 'TL-003', name: 'Пластина ВК8', cat: 'Пластины', qty: 150, min: 50, unit: 'шт', loc: 'Стеллаж B-2' },
    { id: 'TL-004', name: 'Сверло Ø5,1', cat: 'Свёрла', qty: 38, min: 15, unit: 'шт', loc: 'Стеллаж A-3' },
    { id: 'TL-005', name: 'Метчик М6', cat: 'Метчики', qty: 9, min: 12, unit: 'шт', loc: 'Стеллаж C-1' },
    { id: 'TL-006', name: 'Шлифкруг 150×20', cat: 'Абразив', qty: 120, min: 40, unit: 'шт', loc: 'Стеллаж D-1' }
  ];

  var NC = [
    { id: 'NC-101', name: 'Корпус редуктора — фрезеровка', machine: 'Haas VF-4', status: 'Проверена', uses: 14,
      code: 'N10 G21 G90 G54\nN20 T1 M6 (ФРЕЗА D12)\nN30 S4000 M3\nN40 G0 X0 Y0 Z50\nN50 G1 Z-5 F200\nN60 G1 X100 Y0 F800\nN70 G1 X100 Y80\nN80 G3 X80 Y100 R20\n(g); comment' },
    { id: 'NC-102', name: 'Электрод ЭЭО — обработка', machine: 'Sodick AG', status: 'Черновик', uses: 3,
      code: 'N10 G90 G92 X0 Y0\nN20 S2500 M3\nN30 G1 Z-2 F150 (M;)\nN40 G1 X50 F600\nN50 G2 X70 Y20 R20\nN60 M30' },
    { id: 'NC-103', name: 'Вал-шестерня — токарка', machine: 'Okuma LB', status: 'Проверена', uses: 22,
      code: 'N10 G21 G99 G54\nN20 T2 M6 (РЕЗЕЦ)\nN30 S1800 M3 G96\nN40 G0 X40 Z2\nN50 G1 Z0 F0.2\nN60 G1 X0 F0.15\nN70 G0 X100 Z50\nN80 M30' }
  ];

  var current = null, currentType = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Табы ---------- */
  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('button', this).forEach(function (x) { x.classList.toggle('active', x === b); });
    $('#tab-stock').classList.toggle('hidden', b.dataset.t !== 'stock');
    $('#tab-nc').classList.toggle('hidden', b.dataset.t !== 'nc');
  });

  /* ---------- Склад ---------- */
  function renderStock() {
    $('#stockCount').textContent = STOCK.length + ' позиций';
    $('#stockList').innerHTML = STOCK.map(function (t, i) {
      var low = t.qty <= t.min;
      return '<div class="stock-row" data-i="' + i + '"><div><div style="font-weight:600;font-size:.84rem;">' + t.name + '</div><div class="faint" style="font-size:.68rem;">' + t.cat + ' · ' + t.loc + '</div></div><div style="text-align:right;"><b>' + t.qty + ' ' + t.unit + '</b><div class="faint" style="font-size:.66rem;">мин ' + t.min + '</div></div>' + (low ? '<span class="badge danger" style="margin-left:8px;">Заканчивается</span>' : '<span class="badge success" style="margin-left:8px;">ОК</span>') + '</div>';
    }).join('');
    $$('#stockList .stock-row').forEach(function (r) { r.addEventListener('click', function () { openTool(parseInt(r.dataset.i, 10)); }); });
  }

  function openTool(i) {
    current = { type: 'tool', data: STOCK[i] };
    var t = STOCK[i];
    $('#dNum').textContent = t.id;
    var b = $('#dBadge'); b.textContent = t.qty <= t.min ? 'Ниже минимума' : 'В наличии'; b.className = 'badge ' + (t.qty <= t.min ? 'danger' : 'success');
    $('#dTitle').textContent = t.name;
    $('#dTags').innerHTML = '<span class="tag">' + t.cat + '</span><span class="tag">' + t.loc + '</span>';
    $('#dBody').innerHTML = '<div class="section-title">Остаток</div><div class="card">' + row('Количество', t.qty + ' ' + t.unit) + row('Минимум', t.min + ' ' + t.unit) + row('Статус', t.qty <= t.min ? 'Требуется закупка' : 'Достаточно') + '</div>';
    $('#dActions').innerHTML = '<button class="btn btn-primary" data-act="in">Приход</button><button class="btn btn-secondary" data-act="out">Выдача</button>';
    bindActions(t);
    screens.go('s2');
  }

  /* ---------- NC ---------- */
  function renderNc() {
    $('#ncCount').textContent = NC.length + ' программ';
    $('#ncList').innerHTML = NC.map(function (p, i) {
      return '<div class="card clickable accent-left" data-i="' + i + '"><div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + p.id + '</span><span class="badge ' + (p.status === 'Проверена' ? 'success' : 'warning') + '">' + p.status + '</span></div><h3 class="mt-8" style="font-size:.88rem;">' + p.name + '</h3><div class="meta-row"><span>🖥 ' + p.machine + '</span><b>' + p.uses + ' запусков</b></div></div>';
    }).join('');
    $$('#ncList .card').forEach(function (c) { c.addEventListener('click', function () { openNc(parseInt(c.dataset.i, 10)); }); });
  }

  function hl(code) {
    return code.split('\n').map(function (line) {
      return line
        .replace(/\bN(\d+)/g, '<span class="cm">N$1</span>')
        .replace(/\bG(\d+\.?\d*)/g, '<span class="g">G$1</span>')
        .replace(/\bM(\d+)/g, '<span class="m">M$1</span>')
        .replace(/\b([XYZ])(-?\d+\.?\d*)/g, '<span class="ax">$1$2</span>')
        .replace(/\b([FS])(\d+\.?\d*)/g, '<span class="fs">$1$2</span>')
        .replace(/(\(.*?\))/g, '<span class="cm">$1</span>');
    }).join('\n');
  }

  function openNc(i) {
    current = { type: 'nc', data: NC[i] };
    var p = NC[i];
    $('#dNum').textContent = p.id;
    var b = $('#dBadge'); b.textContent = p.status; b.className = 'badge ' + (p.status === 'Проверена' ? 'success' : 'warning');
    $('#dTitle').textContent = p.name;
    $('#dTags').innerHTML = '<span class="tag">🖥 ' + p.machine + '</span><span class="tag">' + p.uses + ' запусков</span>';
    $('#dBody').innerHTML = '<div class="section-title">Код программы</div><pre class="gcode">' + hl(p.code) + '</pre>';
    $('#dActions').innerHTML = '<button class="btn btn-primary" data-act="dup">Создать копию версии</button>';
    bindActions(p);
    screens.go('s2');
  }

  /* ---------- Действия ---------- */
  function bindActions(entity) {
    $$('#dActions [data-act]').forEach(function (b) {
      b.addEventListener('click', function () {
        var a = b.dataset.act;
        if (a === 'in') { entity.qty += 10; renderStock(); done('Приход оформлен', '+10 шт к остатку ' + entity.name + '.', entity.id); }
        else if (a === 'out') { entity.qty = Math.max(0, entity.qty - 1); renderStock(); done('Выдача оформлена', 'Списана 1 шт: ' + entity.name + '.', entity.id); }
        else if (a === 'dup') { done('Копия создана', 'Создана новая версия программы ' + entity.id + '.', entity.id + '-v2'); }
      });
    });
  }
  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }
  function row(k, v) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderStock(); renderNc();
})();
