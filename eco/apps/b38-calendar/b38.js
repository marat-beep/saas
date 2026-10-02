/* ============================================================
   B38 · Производственный календарь (РФ, демо)
   рабочие дни, часы, праздники по месяцам
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;
  var HOURS = 8;
  var MONTHS = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
  // фиксированные праздники (месяц-день)
  var HOLIDAYS = {
    2025: [[1, 1], [1, 2], [1, 3], [1, 4], [1, 5], [1, 6], [1, 7], [1, 8], [2, 23], [3, 8], [5, 1], [5, 9], [6, 12], [11, 4]],
    2026: [[1, 1], [1, 2], [1, 3], [1, 4], [1, 5], [1, 6], [1, 7], [1, 8], [2, 23], [3, 8], [5, 1], [5, 9], [6, 12], [11, 4]]
  };
  var screens = AppRouter.create({ onShow: function () {}, onBackEmpty: function () { location.href = '../../index.html'; } });

  function isHoliday(y, m, d) { return (HOLIDAYS[y] || []).some(function (h) { return h[0] === m && h[1] === d; }); }

  function calc() {
    var y = parseInt($('#year').value, 10);
    var perMonth = [], workMonth = [], holMonth = [];
    var totalWork = 0, totalHol = 0, totalWeekend = 0;
    for (var m = 1; m <= 12; m++) {
      var days = new Date(y, m, 0).getDate(), work = 0, hol = 0, week = 0;
      for (var d = 1; d <= days; d++) {
        var wd = new Date(y, m - 1, d).getDay(); // 0=Sun,6=Sat
        if (isHoliday(y, m, d)) hol++;
        else if (wd === 0 || wd === 6) week++;
        else work++;
      }
      perMonth.push({ m: m, days: days, work: work, hol: hol, week: week });
      totalWork += work; totalHol += hol; totalWeekend += week;
    }
    $('#totals').innerHTML =
      '<div class="stat"><div class="num accent">' + totalWork + '</div><div class="label">Рабочих дней</div></div>' +
      '<div class="stat"><div class="num info">' + (totalWork * HOURS) + '</div><div class="label">Рабочих часов</div></div>' +
      '<div class="stat"><div class="num warning">' + totalHol + '</div><div class="label">Праздничных</div></div>';
    $('#months').innerHTML = perMonth.map(function (p) {
      return '<div class="mo"><b>' + MONTHS[p.m - 1] + '</b><div class="n">' + p.work + '</div><span>раб. дней · ' + (p.work * HOURS) + ' ч</span><div class="faint" style="font-size:.64rem;margin-top:4px;">выходных ' + (p.week + p.hol) + '</div></div>';
    }).join('');
    $('#holidays').innerHTML = (HOLIDAYS[y] || []).map(function (h) { return '<span class="tag" style="margin:3px 4px 0 0;">' + String(h[1]).padStart(2, '0') + '.' + String(h[0]).padStart(2, '0') + '</span>'; }).join('');
  }

  $('#year').addEventListener('change', calc);
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  calc();
})();
