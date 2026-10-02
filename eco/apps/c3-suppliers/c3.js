/* ============================================================
   C3 · Клуб поставщиков
   рейтинг → профиль → тендерная аналитика
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var SUPPLIERS = [
    { name: 'ООО «МеталлСнаб»', cat: 'metal', rating: 4.9, onTime: 98, quality: 99, docs: 100, deals: 142, risk: 'низкий',
      history: [['Сталь 40Х, 600 кг', '10.09', 'В срок'], ['Латунь ЛС59, 400 кг', '22.08', 'В срок'], ['Сталь 1.2379, 250 кг', '05.08', 'В срок']] },
    { name: 'ООО «ЛазерПро-Юг»', cat: 'sub', rating: 4.8, onTime: 96, quality: 97, docs: 98, deals: 88, risk: 'низкий',
      history: [['Лазерная резка листа', '14.09', 'В срок'], ['Оснастка для лазера', '30.08', 'В срок']] },
    { name: 'ЗАО «Термообработка+»', cat: 'sub', rating: 4.7, onTime: 94, quality: 98, docs: 95, deals: 76, risk: 'низкий',
      history: [['Вакуумная закалка 800 кг', '11.09', 'В срок'], ['Отпуск штампов', '19.08', 'С задержкой 1 д.']] },
    { name: 'ООО «Гальваник»', cat: 'sub', rating: 4.6, onTime: 91, quality: 95, docs: 94, deals: 54, risk: 'средний',
      history: [['Цинкование 500 кг', '02.09', 'В срок'], ['Анодирование', '12.08', 'В срок']] },
    { name: 'ООО «ИнструментТорг»', cat: 'tool', rating: 4.5, onTime: 89, quality: 93, docs: 90, deals: 61, risk: 'средний',
      history: [['Фрезы D6–D12', '28.08', 'В срок'], ['Подшипники SKF', '10.08', 'С задержкой 2 д.']] },
    { name: 'ИП Смирнов (абразив)', cat: 'tool', rating: 4.2, onTime: 82, quality: 88, docs: 80, deals: 29, risk: 'повышенный',
      history: [['Круги абразивные', '21.08', 'С задержкой 3 д.'], ['Круги абразивные', '02.08', 'В срок']] }
  ];

  var filter = 'all', current = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    var list = SUPPLIERS.filter(function (s) { return filter === 'all' || s.cat === filter; })
      .sort(function (a, b) { return b.rating - a.rating; });
    $('#supList').innerHTML = list.map(function (s, i) {
      var globalRank = SUPPLIERS.slice().sort(function (a, b) { return b.rating - a.rating; }).indexOf(s) + 1;
      var riskBadge = s.risk === 'низкий' ? 'success' : s.risk === 'средний' ? 'warning' : 'danger';
      return '<div class="card clickable sup-card" data-name="' + s.name + '"><div class="row"><div class="rank' + (globalRank === 1 ? ' gold' : '') + '">' + globalRank + '</div><div class="grow"><div class="row between"><b style="font-size:.86rem;">' + s.name + '</b><span class="rating">★ ' + s.rating.toFixed(1) + '</span></div><div class="tag-row mt-8"><span class="tag">Срок ' + s.onTime + '%</span><span class="tag">Качество ' + s.quality + '%</span><span class="badge ' + riskBadge + '">Риск ' + s.risk + '</span></div></div></div></div>';
    }).join('');
    $$('#supList .sup-card').forEach(function (c) { c.addEventListener('click', function () { openSupplier(c.dataset.name); }); });
  }
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });

  function openSupplier(name) {
    current = SUPPLIERS.find(function (s) { return s.name === name; });
    var s = current;
    var globalRank = SUPPLIERS.slice().sort(function (a, b) { return b.rating - a.rating; }).indexOf(s) + 1;
    $('#pRank').textContent = globalRank;
    $('#pName').textContent = s.name;
    $('#pCat').textContent = { metal: 'Металлопрокат', tool: 'Инструмент', sub: 'Субподряд' }[s.cat] || s.cat;
    $('#pRating').textContent = '★ ' + s.rating.toFixed(1);
    $('#pMetrics').innerHTML =
      metric('Поставки в срок', s.onTime + '%') + metric('Качество', s.quality + '%') + metric('Документы / сертификаты', s.docs + '%') + metric('Всего сделок', s.deals + '') + metric('Уровень риска', s.risk);
    $('#pHistory').innerHTML = s.history.map(function (h) {
      var ok = h[2] === 'В срок';
      return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><div><div style="font-weight:600;">' + h[0] + '</div><div class="faint" style="font-size:.68rem;">' + h[1] + '</div></div><span class="badge ' + (ok ? 'success' : 'warning') + '">' + h[2] + '</span></div>';
    }).join('');
    screens.go('s2');
  }
  function metric(k, v) { return '<div class="metric"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }

  /* ---------- Аналитика ---------- */
  $('#toAnalytics').addEventListener('click', function () { renderAnalytics(); screens.go('s3'); });

  var MARKET = [
    { name: 'Сталь 40Х', mine: 385, market: 402 },
    { name: 'Латунь ЛС59', mine: 610, market: 595 },
    { name: 'Фрезы D6–D12', mine: 6500, market: 6900 },
    { name: 'Термообработка', mine: 180, market: 175 }
  ];
  function renderAnalytics() {
    var s = current;
    $('#aWin').textContent = Math.round(s.deals ? (s.onTime * 0.9) : 0) + '%';
    $('#aDeals').textContent = s.deals;
    $('#aRank').textContent = '#' + (SUPPLIERS.slice().sort(function (a, b) { return b.rating - a.rating; }).indexOf(s) + 1);
    $('#aPrices').innerHTML = MARKET.map(function (m) {
      var delta = Math.round((m.mine - m.market) / m.market * 100);
      var better = delta <= 0;
      var max = Math.max(m.mine, m.market);
      return '<div class="bar-row"><div class="bl"><span>' + m.name + '</span><b style="color:' + (better ? 'var(--success)' : 'var(--danger)') + ';">' + (delta > 0 ? '+' : '') + delta + '%</b></div>' +
        '<div class="progress" style="margin-bottom:4px;"><span style="width:' + Math.round(m.mine / max * 100) + '%;background:var(--accent);"></span></div>' +
        '<div class="faint" style="font-size:.68rem;">Вы ' + money(m.mine) + ' · рынок ' + money(m.market) + '</div></div>';
    }).join('');
    $('#aRecs').innerHTML =
      '<div class="callout success mb-8"><span class="ci">✅</span><div>По стали и инструменту вы дешевле рынка — можно участвовать в больших объёмах.</div></div>' +
      '<div class="callout warning"><span class="ci">⚠️</span><div>По латуни и термообработке цена выше рынка — риск проиграть тендер. Стоит пересмотреть себестоимость.</div></div>';
  }

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
