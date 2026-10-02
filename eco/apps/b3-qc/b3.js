/* ============================================================
   B3 · Мобильный ОТК
   скан/ввод → чек-лист с допусками → результат → подпись/PDF
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var ORDERS = {
    'K-201': { title: 'Пресс-форма втулки', checks: [
      { name: 'Диаметр формообразующей', nom: 42, tol: 0.02, unit: 'мм' },
      { name: 'Глубина ручья', nom: 65, tol: 0.05, unit: 'мм' },
      { name: 'Межосевое расстояние', nom: 120, tol: 0.03, unit: 'мм' },
      { name: 'Твёрдость', nom: 50, tol: 2, unit: 'HRC' },
      { name: 'Шероховатость Ra', nom: 0.4, tol: 0.1, unit: 'мкм' }
    ] },
    'K-205': { title: 'Вал-шестерня', checks: [
      { name: 'Диаметр шейки', nom: 30, tol: 0.01, unit: 'мм' },
      { name: 'Длина вала', nom: 210, tol: 0.2, unit: 'мм' },
      { name: 'Число зубьев (контроль)', nom: 24, tol: 0.001, unit: 'шт' },
      { name: 'Биение', nom: 0, tol: 0.02, unit: 'мм' },
      { name: 'Твёрдость зубьев', nom: 48, tol: 2, unit: 'HRC' }
    ] },
    'K-208': { title: 'Кронштейн датчика', checks: [
      { name: 'Межцентровое расстояние', nom: 75, tol: 0.1, unit: 'мм' },
      { name: 'Диаметр отверстия', nom: 8, tol: 0.05, unit: 'мм' },
      { name: 'Толщина стенки', nom: 6, tol: 0.1, unit: 'мм' },
      { name: 'Перпендикулярность', nom: 0, tol: 0.05, unit: 'мм' }
    ] },
    'K-203': { title: 'Электрод для ЭЭО', checks: [
      { name: 'Длина', nom: 120, tol: 0.1, unit: 'мм' },
      { name: 'Ширина', nom: 60, tol: 0.1, unit: 'мм' },
      { name: 'Высота', nom: 25, tol: 0.05, unit: 'мм' },
      { name: 'Шероховатость', nom: 0.8, tol: 0.2, unit: 'Ra' },
      { name: 'Отклонение от плоскости', nom: 0, tol: 0.03, unit: 'мм' }
    ] },
    'K-204': { title: 'Корпус редуктора', checks: [
      { name: 'Диаметр посадки', nom: 42, tol: 0.02, unit: 'мм' },
      { name: 'Глубина расточки', nom: 30, tol: 0.05, unit: 'мм' },
      { name: 'Межосевое расстояние', nom: 80, tol: 0.03, unit: 'мм' },
      { name: 'Твёрдость', nom: 48, tol: 2, unit: 'HRC' },
      { name: 'Шероховатость Ra', nom: 1.6, tol: 0.4, unit: 'мкм' },
      { name: 'Биение', nom: 0, tol: 0.02, unit: 'мм' }
    ] },
    'K-207': { title: 'Плита прижимная', checks: [
      { name: 'Длина', nom: 300, tol: 0.2, unit: 'мм' },
      { name: 'Ширина', nom: 150, tol: 0.2, unit: 'мм' },
      { name: 'Толщина', nom: 20, tol: 0.1, unit: 'мм' },
      { name: 'Параллельность', nom: 0, tol: 0.05, unit: 'мм' }
    ] }
  };

  var current = null, results = [], signed = false;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Старт ---------- */
  function renderOrders() {
    var keys = Object.keys(ORDERS);
    $('#qcCount').textContent = keys.length + ' заказа';
    $('#orders').innerHTML = keys.map(function (k) {
      return '<div class="card clickable accent-left" data-id="' + k + '"><div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.72rem;">' + k + '</span><span class="badge info">Ожидает</span></div><h3 class="mt-8" style="font-size:.9rem;">' + ORDERS[k].title + '</h3><div class="meta-row"><span class="muted">' + ORDERS[k].checks.length + ' параметров</span><span style="color:var(--accent-600);font-weight:700;">Начать →</span></div></div>';
    }).join('');
    $$('#orders .card').forEach(function (c) { c.addEventListener('click', function () { startOrder(c.dataset.id); }); });
  }

  $('#scanBtn').addEventListener('click', function () {
    var k = Object.keys(ORDERS)[Math.floor(Math.random() * Object.keys(ORDERS).length)];
    App.toast('QR распознан: ' + k);
    startOrder(k);
  });
  $('#manualBtn').addEventListener('click', function () {
    var v = $('#manual').value.trim().toUpperCase();
    if (ORDERS[v]) startOrder(v); else App.toast('Заказ ' + v + ' не найден');
  });

  /* ---------- Чек-лист ---------- */
  function startOrder(id) {
    current = { id: id, title: ORDERS[id].title, checks: ORDERS[id].checks };
    results = current.checks.map(function () { return null; });
    renderChecklist();
    screens.go('s2');
  }

  function renderChecklist() {
    $('#oNum').textContent = current.id;
    $('#oTitle').textContent = current.title;
    $('#checks').innerHTML = current.checks.map(function (c, i) {
      var st = getStatus(i);
      return '<div class="check-card ' + st + '" data-i="' + i + '">' +
        '<div class="cc-head"><b style="font-size:.86rem;">' + c.name + '</b><span class="badge ' + (st === 'ok' ? 'success' : st === 'bad' ? 'danger' : 'neutral') + '">' + (st === 'ok' ? '✓ В норме' : st === 'bad' ? '✗ Брак' : '⭕ —') + '</span></div>' +
        '<div class="nom">Номинал ' + c.nom + ' ± ' + c.tol + ' ' + c.unit + '</div>' +
        '<div class="val-row"><input type="number" step="any" placeholder="Значение" value="' + (results[i] == null ? '' : results[i]) + '" data-in="' + i + '"><span class="faint" style="font-size:.76rem;">' + c.unit + '</span>' +
        '<div class="qbtns"><button class="qbtn ok" data-q="ok" data-i="' + i + '">В норме</button><button class="qbtn bad" data-q="bad" data-i="' + i + '">Брак</button></div></div>' +
      '</div>';
    }).join('');
    updateProgress();
  }

  function getStatus(i) {
    if (results[i] == null) return 'empty';
    var c = current.checks[i];
    return Math.abs(results[i] - c.nom) <= c.tol + 1e-9 ? 'ok' : 'bad';
  }

  function updateProgress() {
    var filled = results.filter(function (r) { return r != null; }).length;
    $('#oProg').textContent = filled + '/' + current.checks.length;
    $('#oBar').style.width = Math.round(filled / current.checks.length * 100) + '%';
    $('#resultBtn').disabled = filled < current.checks.length;
  }

  $('#checks').addEventListener('input', function (e) {
    var input = e.target.closest('[data-in]'); if (!input) return;
    var i = parseInt(input.dataset.in, 10);
    var v = parseFloat(input.value);
    results[i] = isNaN(v) ? null : v;
    refreshCard(i);
  });
  $('#checks').addEventListener('click', function (e) {
    var b = e.target.closest('.qbtn'); if (!b) return;
    var i = parseInt(b.dataset.i, 10), c = current.checks[i];
    results[i] = b.dataset.q === 'ok' ? c.nom : c.nom + c.tol * 3;
    refreshCard(i, true);
  });

  function refreshCard(i, setInput) {
    var card = $('.check-card[data-i="' + i + '"]');
    var st = getStatus(i);
    card.className = 'check-card ' + st;
    var badge = card.querySelector('.badge');
    badge.className = 'badge ' + (st === 'ok' ? 'success' : st === 'bad' ? 'danger' : 'neutral');
    badge.textContent = st === 'ok' ? '✓ В норме' : st === 'bad' ? '✗ Брак' : '⭕ —';
    if (setInput) card.querySelector('input').value = results[i].toFixed(2);
    updateProgress();
  }

  /* ---------- Результат ---------- */
  $('#resultBtn').addEventListener('click', function () {
    var bad = 0, good = 0;
    current.checks.forEach(function (c, i) { getStatus(i) === 'bad' ? bad++ : good++; });
    var verdict = bad === 0 ? 'accepted' : 'rejected';
    $('#resultHero').innerHTML =
      '<div class="result-hero"><div class="check" style="background:' + (verdict === 'accepted' ? 'var(--accent-grad)' : 'linear-gradient(135deg,#dc2626,#991b1b)') + '">' + (verdict === 'accepted' ? '✓' : '✗') + '</div>' +
      '<h2>' + (verdict === 'accepted' ? 'Партия принята' : 'Партия забракована') + '</h2><p>' + good + ' из ' + current.checks.length + ' параметров в норме</p></div>';
    $('#resultList').innerHTML = current.checks.map(function (c, i) {
      var st = getStatus(i);
      return '<div class="row between" style="padding:8px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span>' + (st === 'ok' ? '✅' : '❌') + ' ' + c.name + '</span><b>' + results[i] + ' ' + c.unit + ' <span class="faint" style="font-weight:400;">(ном. ' + c.nom + '±' + c.tol + ')</span></b></div>';
    }).join('');
    signed = false;
    $('#saveBtn').disabled = true;
    screens.go('s3');
  });

  /* ---------- Подпись и PDF ---------- */
  $('#sigPad').addEventListener('click', function () {
    signed = true;
    this.textContent = '✓ ' + $('#inspector').value;
    this.style.borderStyle = 'solid';
    this.style.borderColor = 'var(--accent)';
    this.style.color = 'var(--accent-700)';
    this.style.fontWeight = '700';
    checkSave();
  });
  $('#inspector').addEventListener('input', function () { if (signed) { $('#sigPad').textContent = '✓ ' + this.value; } });
  function checkSave() { $('#saveBtn').disabled = !signed; }

  $('#pdfBtn').addEventListener('click', function () { App.toast('Демо: открытие PDF-протокола'); });

  $('#saveBtn').addEventListener('click', function () {
    var proto = 'ОТК-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    var bad = current.checks.filter(function (c, i) { return getStatus(i) === 'bad'; }).length;
    App.Store.set('protocols', (App.Store.get('protocols', [])).concat([{ proto: proto, order: current.id, bad: bad, created: App.today() }]));
    $('#protoNum').textContent = proto;
    $('#protoSum').innerHTML =
      '<div class="row between"><span class="muted">Заказ</span><b>' + current.id + ' · ' + current.title + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Контролёр</span><b>' + $('#inspector').value + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Параметров</span><b>' + current.checks.length + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Отклонений</span><b style="color:' + (bad ? 'var(--danger)' : 'var(--success)') + ';">' + bad + '</b></div>';
    screens.go('s4');
    App.toast('Протокол ' + proto + ' сохранён');
  });

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#newBtn').addEventListener('click', function () { renderOrders(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderOrders();
})();
