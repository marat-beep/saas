/* ============================================================
   B28 · Стоимость нормочаса станка с ЧПУ
   амортизация + энергия + персонал + расходники + ремонт + накладные
   → себестоимость и цена нормочаса
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var PRESETS = {
    dmg: { name: 'DMG Mori NHX (5 осей)', price: 18500000, power: 18, maint: 700000, consume: 420 },
    haas: { name: 'Haas VF-4 (3 оси)', price: 6800000, power: 15, maint: 380000, consume: 300 },
    okuma: { name: 'Okuma LB3000 (токарный)', price: 9800000, power: 11, maint: 450000, consume: 260 },
    sodick: { name: 'Sodick AG (ЭЭО)', price: 7600000, power: 9, maint: 620000, consume: 540 },
    robodrill: { name: 'Fanuc Robodrill', price: 5400000, power: 7, maint: 300000, consume: 240 },
    laser: { name: 'Лазер 6 кВт', price: 14700000, power: 22, maint: 850000, consume: 480 }
  };

  var result = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#preset').innerHTML = Object.keys(PRESETS).map(function (k) { return '<option value="' + k + '">' + PRESETS[k].name + '</option>'; }).join('');
  $('#preset').addEventListener('change', function () {
    var p = PRESETS[this.value];
    $('#price').value = p.price; $('#power').value = p.power; $('#maint').value = p.maint; $('#consume').value = p.consume;
  });

  function n(id) { return parseFloat($('#' + id).value) || 0; }
  function row(k, v, cls) { return '<div class="brk"><span class="muted">' + k + '</span><b' + (cls ? ' style="color:' + cls + '"' : '') + '>' + v + '</b></div>'; }

  function calc() {
    var hours = Math.max(1, n('hours'));
    var amort = (n('price') - n('salvage')) / Math.max(1, n('life')) / hours;
    var energy = n('power') * n('load') * n('kwh');
    var repair = n('maint') / hours;
    var consume = n('consume');
    var labor = (n('salary') * (1 + n('tax') / 100) * Math.max(1, n('operators'))) / Math.max(1, n('norm'));
    var direct = amort + energy + repair + consume + labor;
    var overhead = direct * (n('overhead') / 100);
    var cost = direct + overhead;
    var priceNet = cost * (1 + n('margin') / 100);
    var priceGross = priceNet * (1 + n('vat') / 100);
    result = { cost: cost, priceNet: priceNet, priceGross: priceGross, parts: [
      ['Амортизация', amort, '#6366f1'], ['Энергия', energy, '#0891b2'], ['Ремонт и обслуживание', repair, '#f59e0b'],
      ['Расходники и СОЖ', consume, '#10b981'], ['Персонал (оператор)', labor, '#a855f7'], ['Накладные', overhead, '#94a3b8']
    ] };

    $('#costOut').textContent = money(cost) + ' / ч';
    $('#priceOut').textContent = 'Цена без НДС ' + money(priceNet) + ' · с НДС ' + money(priceGross);
    var max = Math.max.apply(null, result.parts.map(function (p) { return p[1]; })) || 1;
    $('#brkList').innerHTML = result.parts.map(function (p) {
      return '<div class="brk" style="display:block;"><div class="row between"><span>' + p[0] + '</span><b>' + money(p[1]) + ' <span class="faint" style="font-weight:400;">(' + Math.round(p[1] / cost * 100) + '%)</span></b></div><div class="bar" style="width:' + Math.round(p[1] / max * 100) + '%;background:' + p[2] + ';"></div></div>';
    }).join('') + '<div class="brk" style="margin-top:6px;padding-top:10px;border-top:2px solid var(--border);"><span><b>Итого себестоимость</b></span><b style="color:var(--accent-700);">' + money(cost) + '</b></div>';
    $('#priceCard').innerHTML =
      row('Себестоимость / ч', money(cost)) +
      row('Маржа ' + n('margin') + '%', money(priceNet - cost)) +
      row('Цена без НДС', money(priceNet)) +
      row('НДС ' + n('vat') + '%', money(priceGross - priceNet)) +
      '<div class="brk" style="padding-top:10px;border-top:2px solid var(--border);"><span><b>Цена с НДС / ч</b></span><b style="color:var(--accent-700);">' + money(priceGross) + '</b></div>';
    screens.go('s2');
  }

  $('#calcBtn').addEventListener('click', calc);
  $('#editBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#saveBtn').addEventListener('click', function () {
    var num = 'NH-' + App.pad(Math.floor(1 + Math.random() * 999), 3);
    App.Store.set('machineHourRates', (App.Store.get('machineHourRates', [])).concat([{ num: num, cost: Math.round(result.cost), price: Math.round(result.priceGross), created: App.today() }]));
    $('#actNum').textContent = num;
    screens.go('s3'); App.toast('Нормочас ' + num + ' сохранён');
  });
  $('#againBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
