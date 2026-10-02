/* ============================================================
   P5 · Платежи и эскроу
   дашборд → сделки → эскроу-этапы → оплата/спор
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var STAGES = ['Сделка создана', 'Средства зарезервированы', 'Работа выполняется', 'Готово к приёмке', 'Оплата высвобождена'];

  var DEALS = [
    { id: 'DEAL-2041', buyer: 'ООО «Привод»', seller: 'ООО «ЛазерПро»', title: 'Фрезеровка корпуса, 12 шт', amount: 158000, rate: 0.03, stage: 2, status: 'escrow', date: '18.09' },
    { id: 'DEAL-2038', buyer: 'ЗАО «ТехноПарк»', seller: 'ООО «Гальваник»', title: 'Цинкование, 500 кг', amount: 105000, rate: 0.03, stage: 1, status: 'escrow', date: '15.09' },
    { id: 'DEAL-2035', buyer: 'ООО «АвтоПласт»', seller: 'ЗАО «Термо+»', title: 'Вакуумная закалка, 300 кг', amount: 54000, rate: 0.02, stage: 3, status: 'escrow', date: '12.09' },
    { id: 'DEAL-2030', buyer: 'ООО «Металлист»', seller: 'ООО «Гальваник»', title: 'Анодирование партии', amount: 62000, rate: 0.03, stage: 4, status: 'done', date: '05.09' },
    { id: 'DEAL-2027', buyer: 'ИП Смирнов', seller: 'АО «Урал-Штамп»', title: 'Токарная обработка валов', amount: 132000, rate: 0.02, stage: 4, status: 'done', date: '01.09' },
    { id: 'DEAL-2024', buyer: 'ООО «ЛазерПро»', seller: 'ИП Смирнов', title: 'Поставка абразива', amount: 38000, rate: 0.03, stage: 3, status: 'dispute', date: '28.08' }
  ];

  var filter = 'all', current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Дашборд ---------- */
  function renderDashboard() {
    var gmv = DEALS.reduce(function (s, d) { return s + d.amount; }, 0);
    var commission = DEALS.reduce(function (s, d) { return s + d.amount * d.rate; }, 0);
    var escrow = DEALS.filter(function (d) { return d.status === 'escrow'; }).reduce(function (s, d) { return s + d.amount; }, 0);
    var paid = DEALS.filter(function (d) { return d.status === 'done'; }).reduce(function (s, d) { return s + d.amount; }, 0);
    $('#gmv').textContent = money(gmv);
    $('#gmvSub').textContent = DEALS.length + ' сделок · средние ' + money(gmv / DEALS.length);
    $('#stCommission').textContent = money(commission).replace(' ₽', '');
    $('#stEscrow').textContent = money(escrow).replace(' ₽', '');
    $('#stPaid').textContent = money(paid).replace(' ₽', '');
    renderList();
  }

  function renderList() {
    var list = DEALS.filter(function (d) {
      if (filter === 'escrow') return d.status === 'escrow';
      if (filter === 'done') return d.status === 'done';
      if (filter === 'dispute') return d.status === 'dispute';
      return true;
    });
    $('#dealCount').textContent = list.length + ' сделок';
    $('#dealList').innerHTML = list.map(function (d) {
      var cls = d.status === 'done' ? 'done' : d.status === 'dispute' ? 'dispute' : '';
      var badge = d.status === 'done' ? ['success', 'Завершена'] : d.status === 'dispute' ? ['danger', 'Спор'] : ['accent', 'В эскроу'];
      return '<div class="card clickable deal ' + cls + '" data-id="' + d.id + '"><div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + d.id + '</span><span class="badge ' + badge[0] + '">' + badge[1] + '</span></div><h3 class="mt-8" style="font-size:.86rem;">' + d.title + '</h3><div class="meta-row"><span class="muted">' + STAGES[d.stage] + '</span><b>' + money(d.amount) + '</b></div></div>';
    }).join('');
    $$('#dealList .deal').forEach(function (c) { c.addEventListener('click', function () { openDeal(c.dataset.id); }); });
  }
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });

  /* ---------- Сделка ---------- */
  function openDeal(id) {
    current = DEALS.find(function (d) { return d.id === id; });
    var d = current;
    $('#dNum').textContent = d.id + ' · ' + d.date;
    var b = $('#dStatus'); b.textContent = d.status === 'done' ? 'Завершена' : d.status === 'dispute' ? 'Спор' : 'В эскроу';
    b.className = 'badge ' + (d.status === 'done' ? 'success' : d.status === 'dispute' ? 'danger' : 'accent');
    $('#dTitle').textContent = d.title;
    $('#dTags').innerHTML = '<span class="tag">🏭 ' + d.buyer + '</span><span class="tag">→ ' + d.seller + '</span>';

    $('#dTracker').innerHTML = STAGES.map(function (s, i) {
      var cls = i < d.stage ? 'done' : i === d.stage ? 'current' : '';
      return '<div class="tr-item ' + cls + '"><div class="dot">' + (i < d.stage ? '✓' : '') + '</div><div class="tr-t">' + s + '</div></div>';
    }).join('');

    var commission = d.amount * d.rate;
    $('#dFinance').innerHTML =
      frow('Сумма сделки', money(d.amount)) + frow('Комиссия платформы (' + (d.rate * 100).toFixed(1) + '%)', money(commission)) + frow('К выплате исполнителю', money(d.amount - commission), true);

    $('#releaseBtn').disabled = d.status !== 'escrow' || d.stage < 3;
    $('#disputeBtn').disabled = d.status === 'done';
    screens.go('s2');
  }
  function frow(k, v, accent) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b style="text-align:right;' + (accent ? 'color:var(--accent-700);' : '') + '">' + v + '</b></div>'; }

  /* ---------- Действия ---------- */
  function finishPaid(dispute) {
    var d = current;
    var commission = d.amount * d.rate;
    $('#payIcon').textContent = dispute ? '⚠️' : '✓';
    $('#payTitle').textContent = dispute ? 'Спор открыт' : 'Оплата высвобождена';
    $('#payText').textContent = dispute ? 'Средства удерживаются до разрешения спора арбитражем платформы.' : 'Средства переведены исполнителю за вычетом комиссии.';
    $('#payNum').textContent = d.id;
    $('#payCard').innerHTML = frow('Сумма', money(d.amount)) + frow('Комиссия', money(commission)) + frow('К выплате', money(d.amount - commission), true);
    screens.go('s3');
    App.toast(dispute ? 'Спор открыт по ' + d.id : 'Оплата по ' + d.id + ' высвобождена');
  }
  $('#releaseBtn').addEventListener('click', function () {
    current.stage = 4; current.status = 'done'; renderDashboard();
    finishPaid(false);
  });
  $('#disputeBtn').addEventListener('click', function () {
    current.status = 'dispute'; renderDashboard();
    finishPaid(true);
  });

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toDeals').addEventListener('click', function () { renderDashboard(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderDashboard();
})();
