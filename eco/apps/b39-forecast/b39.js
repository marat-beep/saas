/* ============================================================
   B39 · Прогноз загрузки мощностей
   тренд + сезонность → прогноз по месяцам, оценка, рекомендации
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;
  var PARAMS = { season: 0.9 };
  var result = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#season').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('button', this).forEach(function (x) { x.classList.toggle('active', x === b); });
    PARAMS.season = parseFloat(b.dataset.k);
  });

  function n(id) { return parseFloat($('#' + id).value) || 0; }

  function calc() {
    var base = n('base'), trend = n('trend') / 100, cap = n('cap'), hor = Math.max(1, Math.min(12, n('hor')));
    var months = [], start = new Date().getMonth();
    var names = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
    for (var i = 0; i < hor; i++) {
      var load = base * Math.pow(1 + trend, i) * PARAMS.season;
      load = Math.max(0, Math.round(load));
      months.push({ label: names[(start + i) % 12], load: load, hours: Math.round(cap * load / 100) });
    }
    result = { months: months };
    var max = Math.max.apply(null, months.map(function (m) { return m.load; }).concat([100]));
    $('#bars').innerHTML = months.map(function (m) {
      var cls = m.load > 95 ? ' over' : m.load < 50 ? ' low' : '';
      return '<div class="b' + cls + '" style="height:' + Math.round(m.load / max * 100) + '%"><span>' + m.load + '%</span><i>' + m.label + '</i></div>';
    }).join('');
    var peaks = months.filter(function (m) { return m.load > 95; });
    var lows = months.filter(function (m) { return m.load < 50; });
    var avg = Math.round(months.reduce(function (a, m) { return a + m.load; }, 0) / months.length);
    $('#verdict').innerHTML =
      row('Средняя загрузка', avg + '%') + row('Пиковые месяцы', peaks.length ? peaks.map(function (m) { return m.label; }).join(', ') : 'нет') + row('Недогрузка', lows.length ? lows.map(function (m) { return m.label; }).join(', ') : 'нет');
    $('#recs').innerHTML =
      (peaks.length ? '<div class="callout danger mb-8"><span class="ci">⚠️</span><div>Риск перегрузки в ' + peaks.length + ' мес. — рассмотрите вторую смену, субподряд (M1) или доп. слоты (B10).</div></div>' : '') +
      (lows.length ? '<div class="callout warning mb-8"><span class="ci">🟠</span><div>Недогрузка в ' + lows.length + ' мес. — привлеките заказы (B12) и мощности на маркетплейс (M1).</div></div>' : '') +
      '<div class="callout success"><span class="ci">✅</span><div>Планируйте закупки материалов (B14) и инструмента (B13) под пиковые месяцы.</div></div>';
    screens.go('s2');
  }
  function row(k, v) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }

  $('#calcBtn').addEventListener('click', calc);
  $('#editBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#saveBtn').addEventListener('click', function () {
    var num = 'FC-' + App.pad(Math.floor(1 + Math.random() * 999), 3);
    App.Store.set('forecasts', (App.Store.get('forecasts', [])).concat([{ num: num, months: result.months.map(function (m) { return m.load; }), created: App.today() }]));
    AppData.log.add({ action: 'Прогноз загрузки', detail: num });
    $('#actNum').textContent = num; screens.go('s3'); App.toast('Прогноз сохранён');
  });
  $('#againBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
  calc();
})();
