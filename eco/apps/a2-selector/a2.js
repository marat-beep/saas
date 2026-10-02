/* ============================================================
   A2 · Мастер подбора технологии
   4 вопроса → рекомендации (scoring) → заявка
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var TECHS = {
    cnc_mill: { icon: '🪚', title: 'Фрезеровка ЧПУ', desc: 'Плоскостная и объёмная обработка 3–5 осей', from: 3500, lead: '3–7 дней', why: 'Универсальный метод для точных металлических деталей сложной формы.' },
    cnc_turn: { icon: '🌀', title: 'Токарная обработка', desc: 'Тела вращения: валы, втулки, фланцы, втулки', from: 2800, lead: '2–5 дней', why: 'Оптимально для осесимметричных деталей — быстро и точно.' },
    laser:    { icon: '🔦', title: 'Лазерная резка', desc: 'Листовой раскрой, высокая скорость, серии', from: 1500, lead: '1–3 дня', why: 'Лучший выбор для плоских деталей и серийного раскроя листа.' },
    edm:      { icon: '⚡', title: 'Электроэрозия (ЭЭО)', desc: 'Пазы, твёрдые сплавы, сложные контуры', from: 5000, lead: '4–8 дней', why: 'Единственный способ для очень твёрдых материалов и узких пазов.' },
    engrave:  { icon: '✒️', title: 'Гравировка', desc: 'Маркировка, шильды, серийные номера', from: 1200, lead: '1–2 дня', why: 'Идеально для нанесения маркировки и декора.' },
    heat:     { icon: '🔥', title: 'Термообработка', desc: 'Закалка, отпуск, повышение износостойкости', from: 4000, lead: '3–6 дней', why: 'Повышает твёрдость и срок службы детали.' },
    grinding: { icon: '💧', title: 'Шлифовка', desc: 'Высокая точность и чистота поверхности', from: 3200, lead: '3–6 дней', why: 'Даёт наилучшие допуски и шероховатость.' },
    print3d:  { icon: '🧊', title: '3D-печать', desc: 'Прототипы и оснастка (FDM/SLA)', from: 2000, lead: '1–2 дня', why: 'Самый быстрый способ получить прототип.' },
    welding:  { icon: '🔗', title: 'Сварка', desc: 'Восстановление и соединение деталей', from: 2500, lead: '2–5 дней', why: 'Подходит для восстановления изношенных деталей.' }
  };

  var QUESTIONS = [
    {
      id: 'goal', title: 'Что нужно сделать?',
      options: [
        { icon: '🆕', label: 'Изготовить новую деталь', scores: { cnc_mill: 2, cnc_turn: 2, laser: 1, print3d: 1 } },
        { icon: '♻️', label: 'Восстановить изношенную', scores: { welding: 2, grinding: 1, cnc_mill: 1, edm: 1 } },
        { icon: '✏️', label: 'Доработать / изменить', scores: { cnc_mill: 2, edm: 2, engrave: 1 } },
        { icon: '🏭', label: 'Серийное производство', scores: { cnc_mill: 2, cnc_turn: 2, laser: 2, print3d: -1 } }
      ]
    },
    {
      id: 'conditions', title: 'Условия и требования',
      options: [
        { icon: '🎯', label: 'Жёсткие допуски, высокая точность', scores: { cnc_mill: 2, edm: 2, grinding: 2, cnc_turn: 1 } },
        { icon: '🧪', label: 'Агрессивная среда, износ', scores: { heat: 2, cnc_mill: 1, grinding: 1 } },
        { icon: '🎨', label: 'Маркировка / декоративная', scores: { engrave: 3, laser: 1 } },
        { icon: '⚡', label: 'Быстрый прототип', scores: { print3d: 3, laser: 2 } }
      ]
    },
    {
      id: 'volume', title: 'Объём (серия)',
      options: [
        { icon: '1️⃣', label: '1 шт', scores: { print3d: 1, cnc_mill: 1 } },
        { icon: '📦', label: '2–50 шт', scores: { cnc_mill: 2, cnc_turn: 1, print3d: 1 } },
        { icon: '🚚', label: '50–500 шт', scores: { laser: 2, cnc_mill: 2, cnc_turn: 1 } },
        { icon: '🏭', label: '500+ шт', scores: { laser: 3, cnc_mill: 1, print3d: -1 } }
      ]
    },
    {
      id: 'priority', title: 'Приоритет',
      options: [
        { icon: '💰', label: 'Минимальная цена', scores: { laser: 1, cnc_turn: 1, print3d: 1 } },
        { icon: '⚖️', label: 'Баланс цены и качества', scores: { cnc_mill: 2, cnc_turn: 1 } },
        { icon: '⏱', label: 'Срочно', scores: { print3d: 2, laser: 1, cnc_mill: 1 } },
        { icon: '💎', label: 'Премиум-качество', scores: { grinding: 2, edm: 2, cnc_mill: 1 } }
      ]
    }
  ];

  var answers = [];
  var step = 0;
  var recommendations = [];

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's-intro'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Квиз ---------- */
  function renderQuestion() {
    var q = QUESTIONS[step];
    $('#qStep').textContent = 'Вопрос ' + (step + 1) + ' из ' + QUESTIONS.length;
    var pct = Math.round(((step + 1) / QUESTIONS.length) * 100);
    $('#qPct').textContent = pct + '%';
    $('#qBar').style.width = pct + '%';
    $('#qTitle').textContent = q.title;
    $('#qOptions').innerHTML = q.options.map(function (o, i) {
      return '<div class="option" data-i="' + i + '"><span class="opt-icon">' + o.icon + '</span><span class="opt-title">' + o.label + '</span></div>';
    }).join('');
  }

  $('#qOptions').addEventListener('click', function (e) {
    var el = e.target.closest('.option');
    if (!el) return;
    answers[step] = parseInt(el.dataset.i, 10);
    if (step < QUESTIONS.length - 1) { step++; renderQuestion(); }
    else { compute(); }
  });

  /* ---------- Скоринг ---------- */
  function compute() {
    var scores = {};
    Object.keys(TECHS).forEach(function (k) { scores[k] = 0; });
    answers.forEach(function (ai, qi) {
      var sc = QUESTIONS[qi].options[ai].scores;
      Object.keys(sc).forEach(function (k) { scores[k] = (scores[k] || 0) + sc[k]; });
    });
    var list = Object.keys(scores).map(function (k) { return { id: k, score: scores[k] }; })
      .filter(function (x) { return x.score > 0; })
      .sort(function (a, b) { return b.score - a.score; })
      .slice(0, 3);
    var max = list.length ? list[0].score : 0;
    recommendations = list.map(function (x) {
      return { tech: TECHS[x.id], id: x.id, match: Math.max(40, Math.round((x.score / max) * 100)) };
    });
    renderResult();
    screens.go('s-result');
  }

  function renderResult() {
    $('#resCount').textContent = recommendations.length + ' варианта';
    $('#resList').innerHTML = recommendations.map(function (r, i) {
      var t = r.tech;
      return '<div class="card tech-card' + (i === 0 ? ' best' : '') + ' mb-12">' +
        '<div class="row between"><div class="row"><span style="font-size:1.5rem;">' + t.icon + '</span><div><h3 class="mb-0">' + t.title + (i === 0 ? ' <span class="badge success">Лучший выбор</span>' : '') + '</h3><div class="faint" style="font-size:.72rem;">' + t.desc + '</div></div></div></div>' +
        '<div class="preview3d mt-12">' + t.icon + '</div>' +
        '<p class="muted" style="font-size:.8rem;line-height:1.5;">' + t.why + '</p>' +
        '<div class="row between mt-12"><div><div class="faint" style="font-size:.66rem;">Цена от</div><b>' + money(t.from) + '</b></div>' +
        '<div class="text-center"><div class="faint" style="font-size:.66rem;">Срок</div><b>' + t.lead + '</b></div>' +
        '<div class="text-center"><div class="faint" style="font-size:.66rem;">Совпадение</div><div class="match">' + r.match + '%</div></div></div>' +
      '</div>';
    }).join('');
  }

  /* ---------- Заявка ---------- */
  $('#requestBtn').addEventListener('click', function () {
    if (!recommendations.length) return;
    var best = recommendations[0];
    var ticket = App.randomTicket('3DMP');
    App.Draft.set({ ticket: ticket, source: 'A2', tech: best.tech.title, match: best.match, created: App.today() });
    if (window.AppData) AppData.requests.add({ source: 'A2', title: 'Подбор: ' + best.tech.title + ' (' + best.match + '%)', amount: best.tech.from, ref: ticket });
    $('#ticketNum').textContent = ticket;
    $('#successTech').innerHTML =
      '<div class="row"><span style="font-size:1.6rem;">' + best.tech.icon + '</span><div><h4 class="mb-0">' + best.tech.title + '</h4><div class="faint" style="font-size:.72rem;">Рекомендовано · совпадение ' + best.match + '%</div></div></div>' +
      '<div class="row between mt-12"><span class="muted">Цена от</span><b>' + money(best.tech.from) + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Срок</span><b>' + best.tech.lead + '</b></div>';
    screens.go('s-success');
    App.toast('Заявка ' + ticket + ' создана');
  });

  /* ---------- Навигация ---------- */
  $('#startBtn').addEventListener('click', function () { step = 0; answers = []; renderQuestion(); screens.go('s-quiz'); });
  $('#restartBtn').addEventListener('click', function () { step = 0; answers = []; renderQuestion(); screens.go('s-quiz'); });
  $('#newBtn').addEventListener('click', function () { location.reload(); });
  $('#backBtn').addEventListener('click', function () {
    if (screens.is('s-quiz') && step > 0) { step--; renderQuestion(); }
    else screens.back();
  });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
