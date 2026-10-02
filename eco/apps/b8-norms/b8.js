/* ============================================================
   B8 · Нормирование операций
   параметры → норма + K-коэффициенты + экономика → в спецификацию
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var OPERATIONS = {
    mill3: { name: 'Фрезеровка 3 оси', baseMin: 35, costHour: 2200, saleHour: 3100 },
    mill5: { name: 'Фрезеровка 5 осей', baseMin: 55, costHour: 3200, saleHour: 4600 },
    turn: { name: 'Токарная обработка', baseMin: 28, costHour: 1900, saleHour: 2700 },
    edm: { name: 'Электроэрозия', baseMin: 42, costHour: 2600, saleHour: 3800 },
    grind: { name: 'Шлифовка', baseMin: 30, costHour: 2000, saleHour: 2900 },
    locks: { name: 'Слесарная', baseMin: 20, costHour: 1200, saleHour: 1700 }
  };
  var MATERIALS = { steel: ['Сталь конструкционная', 1.2], tool: ['Инструментальная сталь', 1.3], ss: ['Нержавеющая сталь', 1.4], al: ['Алюминий', 1.0], cu: ['Латунь/медь', 1.1], ti: ['Титан', 1.8] };

  var params = { op: 'mill3', mat: 'steel', prec: 1, geom: 1, fix: 0.9, qty: 1 };
  var result = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#op').innerHTML = Object.keys(OPERATIONS).map(function (k) { return '<option value="' + k + '">' + OPERATIONS[k].name + '</option>'; }).join('');
  $('#mat').innerHTML = Object.keys(MATERIALS).map(function (k) { return '<option value="' + k + '">' + MATERIALS[k][0] + '</option>'; }).join('');
  $('#op').addEventListener('change', function () { params.op = this.value; });
  $('#mat').addEventListener('change', function () { params.mat = this.value; });
  $('#qty').addEventListener('input', function () { params.qty = Math.max(1, parseInt(this.value, 10) || 1); });

  function seg(sel, key) {
    $(sel).addEventListener('click', function (e) {
      var b = e.target.closest('button'); if (!b) return;
      $$('button', this).forEach(function (x) { x.classList.toggle('active', x === b); });
      params[key] = parseFloat(b.dataset.k);
    });
  }
  seg('#prec', 'prec'); seg('#geom', 'geom'); seg('#fix', 'fix');

  function serialF(q) { return q <= 1 ? 1.30 : q <= 5 ? 1.00 : q <= 50 ? 0.85 : 0.75; }
  function serialName(q) { return q <= 1 ? 'единичное' : q <= 5 ? 'мелкая серия' : q <= 50 ? 'средняя серия' : 'массовое'; }

  function row(k, v) { return '<div class="k-chip"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }

  function calculate() {
    var op = OPERATIONS[params.op], matK = MATERIALS[params.mat][1], sf = serialF(params.qty);
    var normMin = op.baseMin * matK * params.prec * params.geom * params.fix * sf;
    var cost = normMin / 60 * op.costHour;
    var sale = normMin / 60 * op.saleHour;
    var vat = sale * 0.22;
    result = { op: op, mat: MATERIALS[params.mat][0], normMin: normMin, cost: cost, sale: sale, vat: vat, sf: sf };

    $('#normVal').textContent = App.number(normMin, 1) + ' мин';
    $('#normSub').textContent = App.number(normMin * params.qty, 0) + ' мин на партию · ' + params.qty + ' шт';

    $('#kList').innerHTML =
      row('Материал (Км)', params.mat + ' · ×' + matK) +
      row('Точность (Кт)', '×' + params.prec) +
      row('Геометрия (Кг)', '×' + params.geom) +
      row('Оснастка (Ко)', '×' + params.fix) +
      row('Серийность (Кс)', '×' + sf + ' · ' + serialName(params.qty));

    $('#econList').innerHTML =
      row('Норма времени', App.number(normMin, 1) + ' мин') +
      row('Себестоимость', money(cost)) +
      row('Цена без НДС', money(sale)) +
      row('НДС 22%', money(vat)) +
      '<div class="k-chip"><span class="muted">Цена с НДС</span><b style="color:var(--accent-700);">' + money(sale + vat) + '</b></div>';
    screens.go('s2');
  }
  $('#calcBtn').addEventListener('click', calculate);

  $('#saveBtn').addEventListener('click', function () {
    var pos = App.Store.get('specItems', []);
    var id = 'SPEC-' + App.pad(pos.length + 1, 3);
    pos.push({ id: id, op: result.op.name, material: result.mat, normMin: Math.round(result.normMin * 10) / 10, sale: Math.round(result.sale), qty: params.qty });
    App.Store.set('specItems', pos);
    $('#posNum').textContent = id;
    $('#savedCard').innerHTML =
      row('Операция', result.op.name) + row('Материал', result.mat) + row('Норма', App.number(result.normMin, 1) + ' мин') + row('Цена с НДС', money(result.sale + result.vat));
    screens.go('s3');
    App.toast('Позиция ' + id + ' добавлена в спецификацию');
  });

  $('#editBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#againBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
