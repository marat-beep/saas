/* ============================================================
   P3 · Отраслевая аналитика
   обзор → бенчмарки → отчёт
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var DATA = {
    mech: { name: 'Механообработка', kpi: [['Средний чек', '184 000 ₽'], ['Средний срок', '9,4 дня'], ['Загрузка парка', '72%'], ['Доля брака', '1,8%']],
      bench: [['Фрезеровка ЧПУ', 2500, 2280, 'час'], ['Токарная обработка', 2200, 2410, 'час'], ['Шлифовка', 2600, 2400, 'час']] },
    tool: { name: 'Инструмент и штампы', kpi: [['Средний чек', '312 000 ₽'], ['Средний срок', '21 день'], ['Загрузка парка', '64%'], ['Доля брака', '2,4%']],
      bench: [['Штампы вырубные', 286000, 305000, 'шт'], ['Пресс-формы', 465000, 430000, 'шт'], ['Оснастка', 96000, 104000, 'компл.']] },
    laser: { name: 'Лазерная резка', kpi: [['Средний чек', '58 000 ₽'], ['Средний срок', '2,6 дня'], ['Загрузка парка', '81%'], ['Доля брака', '0,9%']],
      bench: [['Резка 4 мм', 1800, 1720, 'час'], ['Резка 6 мм', 2200, 2310, 'час'], ['Резка 10 мм', 3100, 2950, 'час']] },
    heat: { name: 'Термообработка', kpi: [['Средний чек', '96 000 ₽'], ['Средний срок', '5,1 дня'], ['Загрузка парка', '69%'], ['Доля брака', '1,2%']],
      bench: [['Вакуумная закалка', 180, 176, 'кг'], ['Отпуск', 120, 128, 'кг'], ['ТВЧ', 210, 198, 'кг']] }
  };

  var ind = 'mech';
  var screens = AppRouter.create({
    onShow: function (s) { window.scrollTo(0, 0); },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function render() {
    var d = DATA[ind];
    $('#kpiGrid').innerHTML = d.kpi.map(function (k, i) {
      var cls = ['accent', 'info', 'success', 'warning'][i % 4];
      return '<div class="stat"><div class="num ' + cls + '" style="font-size:1.25rem;">' + k[1] + '</div><div class="label">' + k[0] + '</div></div>';
    }).join('');

    $('#benchList').innerHTML = d.bench.map(function (b) {
      var name = b[0], mine = b[1], market = b[2], unit = b[3];
      var delta = Math.round((mine - market) / market * 100);
      var better = delta <= 0;
      var max = Math.max(mine, market);
      return '<div class="bm"><div class="lbl"><span>' + name + '</span><b style="color:' + (better ? 'var(--success)' : 'var(--danger)') + ';">' + (delta > 0 ? '+' : '') + delta + '% к рынку</b></div>' +
        '<div class="track"><i style="width:' + Math.round(mine / (mine + market) * 100) + '%;background:var(--accent);"></i><i style="width:' + Math.round(market / (mine + market) * 100) + '%;background:var(--border);"></i></div>' +
        '<div class="faint" style="font-size:.68rem;margin-top:4px;">Вы ' + money(mine) + '/' + unit + ' · рынок ' + money(market) + '/' + unit + '</div></div>';
    }).join('');

    $('#repInd').textContent = d.name;
    $('#repBody').innerHTML = d.kpi.map(function (k) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.85rem;"><span class="muted">' + k[0] + '</span><b>' + k[1] + '</b></div>'; }).join('');
  }

  $('#industryTabs').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    ind = c.dataset.ind; render();
  });

  $('#toBench').addEventListener('click', function () { screens.go('s2'); });
  $('#back1').addEventListener('click', function () { screens.back(); });
  $('#toReport').addEventListener('click', function () { screens.go('s3'); });
  $('#exportBtn').addEventListener('click', function () { App.toast('Демо: отчёт по отрасли выгружен'); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  render();
})();
