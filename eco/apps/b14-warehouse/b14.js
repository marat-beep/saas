/* ============================================================
   B14 · Склад материалов и закупки
   остатки → материал (движения) → заявка/списание
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var MATERIALS = [
    { id: 'MT-001', name: 'Сталь 40Х, пруток Ø60', qty: 620, min: 300, unit: 'кг', loc: 'Склад металла', price: 385 },
    { id: 'MT-002', name: 'Сталь 1.2379, пруток Ø40–80', qty: 180, min: 250, unit: 'кг', loc: 'Склад металла', price: 420 },
    { id: 'MT-003', name: 'Алюминий АМг6, лист 4 мм', qty: 900, min: 400, unit: 'кг', loc: 'Склад металла', price: 470 },
    { id: 'MT-004', name: 'Латунь ЛС59-1, пруток', qty: 210, min: 200, unit: 'кг', loc: 'Цветной склад', price: 610 },
    { id: 'MT-005', name: 'Графит МПГ-7', qty: 40, min: 60, unit: 'кг', loc: 'Склад ЭЭО', price: 1250 },
    { id: 'MT-006', name: 'СОЖ концентрат', qty: 85, min: 40, unit: 'л', loc: 'Склад расходников', price: 320 }
  ];

  var MOVES = {
    'MT-001': [['Приход', '+600 кг', '28.09'], ['Списание', '−120 кг', '30.09'], ['Приход', '+200 кг', '02.10']],
    'MT-002': [['Приход', '+250 кг', '20.09'], ['Списание', '−70 кг', '01.10']],
    'MT-005': [['Списание', '−40 кг', '25.09'], ['Списание', '−20 кг', '30.09']]
  };

  var requests = [], current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    $('#wSku').textContent = MATERIALS.length;
    $('#wLow').textContent = MATERIALS.filter(function (m) { return m.qty <= m.min; }).length;
    $('#wReq').textContent = requests.length;
    $('#matCount').textContent = MATERIALS.length + ' позиций';
    $('#matList').innerHTML = MATERIALS.map(function (m, i) {
      var low = m.qty <= m.min;
      return '<div class="mat-row" data-i="' + i + '"><div><div style="font-weight:600;font-size:.84rem;">' + m.name + '</div><div class="faint" style="font-size:.68rem;">' + m.loc + '</div></div><div style="text-align:right;"><b>' + App.number(m.qty) + ' ' + m.unit + '</b><div class="faint" style="font-size:.66rem;">мин ' + m.min + '</div></div>' + (low ? '<span class="badge danger" style="margin-left:8px;">Заканчивается</span>' : '<span class="badge success" style="margin-left:8px;">ОК</span>') + '</div>';
    }).join('');
    $$('#matList .mat-row').forEach(function (r) { r.addEventListener('click', function () { openMat(parseInt(r.dataset.i, 10)); }); });
  }

  function openMat(i) {
    current = MATERIALS[i];
    var m = current;
    $('#mNum').textContent = m.id;
    var b = $('#mBadge'); b.textContent = m.qty <= m.min ? 'Ниже минимума' : 'В наличии'; b.className = 'badge ' + (m.qty <= m.min ? 'danger' : 'success');
    $('#mTitle').textContent = m.name;
    $('#mTags').innerHTML = '<span class="tag">' + m.loc + '</span><span class="tag">' + money(m.price) + '/' + m.unit + '</span>';
    $('#mInfo').innerHTML =
      row('Остаток', App.number(m.qty) + ' ' + m.unit) + row('Минимум', m.min + ' ' + m.unit) + row('Стоимость остатка', money(m.qty * m.price)) + row('Статус', m.qty <= m.min ? 'Требуется закупка' : 'Достаточно');
    var mv = MOVES[m.id] || [['Приход', '+100 ' + m.unit, '01.10']];
    $('#mMoves').innerHTML = mv.map(function (x) { return '<div class="row between" style="padding:7px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><span>' + x[0] + '</span><span class="muted">' + x[2] + '</span><b>' + x[1] + '</b></div>'; }).join('');
    screens.go('s2');
  }
  function row(k, v, accent) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b style="' + (accent ? 'color:var(--accent-700);' : '') + '">' + v + '</b></div>'; }
  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }

  $('#reqBtn').addEventListener('click', function () {
    var need = Math.max(current.min * 2 - current.qty, current.min);
    var num = 'ЗК-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    requests.push({ num: num, mat: current.name, qty: need });
    App.Store.set('purchaseRequests', (App.Store.get('purchaseRequests', [])).concat([{ num: num, mat: current.name, qty: need, sum: need * current.price, created: App.today() }]));
    renderList();
    done('Заявка на закупку создана', 'Запрошено ' + App.number(need) + ' ' + current.unit + ' на ' + money(need * current.price) + '.', num);
  });
  $('#issueBtn').addEventListener('click', function () {
    var take = Math.min(current.qty, Math.round(current.min * 0.4));
    current.qty -= take; current.qty = Math.max(0, current.qty);
    renderList(); openMat(MATERIALS.indexOf(current));
    done('Списано в производство', 'Списано ' + App.number(take) + ' ' + current.unit + ': ' + current.name + '.', current.id);
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
