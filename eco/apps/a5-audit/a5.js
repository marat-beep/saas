/* ============================================================
   A5 · Аудит цифровой зрелости
   6 вопросов → уровень, узкие места, рекомендации, консультация
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var QUESTIONS = [
    { cat: 'Данные', title: 'Как ведёте учёт заказов?', options: [
      { label: 'Бумажные журналы', v: 0 }, { label: 'Excel-таблицы', v: 1 }, { label: 'CRM / 1С', v: 2 }, { label: 'Единая система с интеграциями', v: 3 }] },
    { cat: 'Процессы', title: 'Есть ли регламенты и техпроцессы в единой базе?', options: [
      { label: 'Нет, всё в головах', v: 0 }, { label: 'Частично, папки', v: 1 }, { label: 'Электронный архив', v: 2 }, { label: 'База знаний с поиском', v: 3 }] },
    { cat: 'Оборудование', title: 'Подключены ли станки к учёту/сети?', options: [
      { label: 'Нет', v: 0 }, { label: 'Часть подключена', v: 1 }, { label: 'Диагностика по сети', v: 2 }, { label: 'MES / мониторинг загрузки', v: 3 }] },
    { cat: 'Автоматизация', title: 'Как планируете загрузку производства?', options: [
      { label: 'Вручную, «на глаз»', v: 0 }, { label: 'Excel', v: 1 }, { label: 'Диспетчерская доска', v: 2 }, { label: 'Автопланирование', v: 3 }] },
    { cat: 'Персонал', title: 'Как обучаете и допускаете сотрудников?', options: [
      { label: 'Наставничество, устно', v: 0 }, { label: 'Инструктажи на бумаге', v: 1 }, { label: 'Электронные инструкции', v: 2 }, { label: 'Обучение + тесты онлайн', v: 3 }] },
    { cat: 'Аналитика', title: 'Отчётность по срокам и себестоимости', options: [
      { label: 'Не считаем', v: 0 }, { label: 'Раз в месяц вручную', v: 1 }, { label: 'Регулярные отчёты', v: 2 }, { label: 'Дашборды в реальном времени', v: 3 }] }
  ];

  var RECS = {
    'Данные': 'Внедрить единый учёт заказов (CRM/1С). Устранит потери заявок и дублирование.',
    'Процессы': 'Оцифровать техпроцессы и регламенты — база знаний сократит простои и брак.',
    'Оборудование': 'Подключить станки к сети и мониторингу загрузки (шаг к MES).',
    'Автоматизация': 'Завести диспетчерскую доску планирования, затем автопланирование.',
    'Персонал': 'Перевести инструктажи в электронный вид и добавить онлайн-тесты.',
    'Аналитика': 'Настроить дашборды по срокам, загрузке и себестоимости.'
  };

  var answers = [], step = 0, result = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's-intro'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderQuestion() {
    var q = QUESTIONS[step];
    $('#qStep').textContent = 'Вопрос ' + (step + 1) + ' из ' + QUESTIONS.length + ' · ' + q.cat;
    $('#qBar').style.width = Math.round(((step + 1) / QUESTIONS.length) * 100) + '%';
    $('#qTitle').textContent = q.title;
    $('#qOptions').innerHTML = q.options.map(function (o, i) {
      return '<div class="option" data-i="' + i + '"><span class="opt-title">' + o.label + '</span></div>';
    }).join('');
  }

  $('#qOptions').addEventListener('click', function (e) {
    var el = e.target.closest('.option'); if (!el) return;
    answers[step] = parseInt(el.dataset.i, 10);
    if (step < QUESTIONS.length - 1) { step++; renderQuestion(); }
    else compute();
  });

  function compute() {
    var byCat = {};
    var total = 0, max = QUESTIONS.length * 3;
    QUESTIONS.forEach(function (q, i) {
      var v = q.options[answers[i]].v;
      total += v;
      byCat[q.cat] = { v: v, max: 3 };
    });
    var score = Math.round((total / max) * 100);
    var level, cls;
    if (score < 34) { level = 'Низкий'; cls = 'danger'; }
    else if (score < 59) { level = 'Базовый'; cls = 'warning'; }
    else if (score < 80) { level = 'Развитый'; cls = 'info'; }
    else { level = 'Высокий'; cls = 'success'; }
    var weak = Object.keys(byCat).filter(function (c) { return byCat[c].v <= 1; });
    result = { score: score, level: level, cls: cls, byCat: byCat, weak: weak };
    renderResult();
    screens.go('s-result');
  }

  function renderResult() {
    var r = result;
    $('#gScore').textContent = r.score;
    var arc = $('#gArc'); var len = 414; arc.style.strokeDashoffset = len - (len * r.score / 100);
    arc.setAttribute('stroke', r.score < 34 ? '#dc2626' : r.score < 59 ? '#d97706' : r.score < 80 ? '#0369a1' : '#16a34a');
    $('#levelBadge').textContent = 'Уровень: ' + r.level;
    $('#levelBadge').style.background = 'var(--' + (r.cls === 'success' ? 'success' : r.cls === 'warning' ? 'warning' : r.cls === 'danger' ? 'danger' : 'info') + '-bg)';
    $('#levelBadge').style.color = r.score < 34 ? '#b91c1c' : r.score < 59 ? '#b45309' : r.score < 80 ? '#0369a1' : '#15803d';

    $('#axes').innerHTML = Object.keys(r.byCat).map(function (c) {
      var pct = Math.round(r.byCat[c].v / 3 * 100);
      var col = pct <= 33 ? '#dc2626' : pct <= 66 ? '#d97706' : '#16a34a';
      return '<div class="axis"><div class="lbl"><span>' + c + '</span><b>' + pct + '%</b></div><div class="progress"><span style="width:' + pct + '%;background:' + col + ';"></span></div></div>';
    }).join('');

    if (!r.weak.length) {
      $('#weakList').innerHTML = '<div class="callout success"><span class="ci">🎉</span><div>Критичных узких мест нет — вы на высоком уровне зрелости.</div></div>';
    } else {
      $('#weakList').innerHTML = r.weak.map(function (c) {
        return '<div class="callout danger mb-8"><span class="ci">⚠️</span><div><b>' + c + '</b> — требует первоочередного внимания.</div></div>';
      }).join('');
    }
    $('#recList').innerHTML = Object.keys(RECS).map(function (c) {
      return '<div class="rec"><span>' + (r.weak.indexOf(c) >= 0 ? '🔴' : '✅') + '</span><span style="font-size:.8rem;line-height:1.45;">' + RECS[c] + '</span></div>';
    }).join('');
  }

  $('#consultBtn').addEventListener('click', function () {
    var ticket = App.randomTicket('AUD');
    App.Store.set('audits', (App.Store.get('audits', [])).concat([{ ticket: ticket, score: result.score, level: result.level, created: App.today() }]));
    if (window.AppData) AppData.requests.add({ source: 'A5', title: 'Аудит зрелости: ' + result.level + ' (' + result.score + '/100)', ref: ticket });
    $('#ticketNum').textContent = ticket;
    $('#resLevel').textContent = result.level;
    $('#resScore').textContent = result.score + ' / 100';
    $('#resFocus').textContent = result.weak[0] || 'Поддержание уровня';
    screens.go('s-success');
    App.toast('Обращение ' + ticket + ' создано');
  });

  $('#startBtn').addEventListener('click', function () { step = 0; answers = []; renderQuestion(); screens.go('s-quiz'); });
  $('#restartBtn').addEventListener('click', function () { step = 0; answers = []; renderQuestion(); screens.go('s-quiz'); });
  $('#newBtn').addEventListener('click', function () { location.reload(); });
  $('#backBtn').addEventListener('click', function () { if (screens.is('s-quiz') && step > 0) { step--; renderQuestion(); } else screens.back(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
