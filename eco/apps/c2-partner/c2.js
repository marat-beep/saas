/* ============================================================
   C2 · Партнёрский кабинет
   регистрация → дашборд заявок → детали/этапы → документы
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var STAGES = ['Назначена', 'Принята', 'В работе', 'Готово'];

  var APPS = [
    { id: 'P-514', title: 'Гальваника: партия кронштейнов', stage: 0, amount: 84000, customer: '3DMP · цех №2', due: '28.10', op: 'Гальваника', urgent: true },
    { id: 'P-513', title: 'Лазерная резка листа 6 мм', stage: 0, amount: 96000, customer: '3DMP · лазерный участок', due: '27.10', op: 'Лазерная резка', urgent: true },
    { id: 'P-512', title: 'Термообработка пуансонов', stage: 1, amount: 54000, customer: '3DMP · инструментальный', due: '29.10', op: 'Термообработка', urgent: false },
    { id: 'P-511', title: 'Шлифовка плит', stage: 1, amount: 41000, customer: '3DMP · механообработка', due: '30.10', op: 'Шлифовка', urgent: false },
    { id: 'P-510', title: 'Сварка рамных конструкций', stage: 2, amount: 77000, customer: '3DMP · сборочный', due: '26.10', op: 'Сварка', urgent: false },
    { id: 'P-509', title: '3D-печать оснастки (SLA)', stage: 2, amount: 29000, customer: '3DMP · прототипирование', due: '25.10', op: '3D-печать', urgent: false },
    { id: 'P-508', title: 'Токарная обработка валов (субподряд)', stage: 2, amount: 112000, customer: '3DMP · ЧПУ-участок', due: '24.10', op: 'Мехобработка', urgent: true },
    { id: 'P-505', title: 'Сварка рамных конструкций', stage: 3, amount: 96000, customer: '3DMP · сборочный', due: '18.10', op: 'Сварка', urgent: false },
    { id: 'P-504', title: 'Шлифовка направляющих', stage: 3, amount: 47000, customer: '3DMP · механообработка', due: '20.10', op: 'Шлифовка', urgent: false },
    { id: 'P-503', title: 'Лазерная резка листа 4 мм', stage: 3, amount: 58000, customer: '3DMP · лазерный участок', due: '17.10', op: 'Лазерная резка', urgent: false },
    { id: 'P-502', title: 'Термообработка штампов', stage: 3, amount: 126000, customer: '3DMP · инструментальный', due: '16.10', op: 'Термообработка', urgent: false },
    { id: 'P-501', title: 'Гальваническое цинкование партии', stage: 3, amount: 84000, customer: '3DMP · цех №2', due: '15.10', op: 'Гальваника', urgent: false },
    { id: 'P-500', title: 'Анодирование алюминиевых деталей', stage: 3, amount: 62000, customer: '3DMP · цех №3', due: '12.10', op: 'Анодирование', urgent: false },
    { id: 'P-499', title: 'Полировка формообразующих', stage: 3, amount: 38000, customer: '3DMP · инструментальный', due: '10.10', op: 'Полировка', urgent: false }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1' || s.id === 's2'); $('#logoutBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Вход ---------- */
  function checkEnter() {
    var n = $('#pName').value.trim(), i = $('#pInn').value.trim();
    $('#enterBtn').disabled = !(n && i.length >= 10);
  }
  ['pName', 'pInn'].forEach(function (id) { $('#' + id).addEventListener('input', checkEnter); });
  $('#enterBtn').addEventListener('click', function () {
    $('#welcomeP').textContent = $('#pName').value.trim();
    $('#compBadge').textContent = '✓ ' + $('#pComp').value;
    renderDashboard(); screens.go('s2'); App.toast('Добро пожаловать!');
  });
  $('#logoutBtn').addEventListener('click', function () { screens.replace('s1'); });

  /* ---------- Дашборд ---------- */
  function renderDashboard() {
    var nw = APPS.filter(function (a) { return a.stage === 0; }).length;
    var wk = APPS.filter(function (a) { return a.stage === 1 || a.stage === 2; }).length;
    var dn = APPS.filter(function (a) { return a.stage === 3; }).length;
    $('#stNew').textContent = nw; $('#stWork').textContent = wk; $('#stDone').textContent = dn;
    $('#qaNew').textContent = nw + ' ожидают';
    $('#qaWork').textContent = wk + ' активных';
    $('#qaDone').textContent = dn + ' выполнено';
    renderList();
  }

  function renderList(filterStage) {
    var list = APPS.filter(function (a) { return filterStage == null || a.stage === filterStage; });
    $('#appCount').textContent = list.length + ' заявок';
    $('#appList').innerHTML = list.map(function (a) {
      var badge = a.stage === 0 ? 'danger' : a.stage === 3 ? 'success' : 'info';
      return '<div class="card clickable accent-left' + (a.urgent ? ' urgent' : '') + '" data-id="' + a.id + '">' +
        '<div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + a.id + '</span><span class="badge ' + badge + '">' + (a.urgent && a.stage === 0 ? '🔥 Срочно' : STAGES[a.stage]) + '</span></div>' +
        '<h3 class="mt-8" style="font-size:.9rem;">' + a.title + '</h3>' +
        '<div class="meta-row"><span>🛠 ' + a.op + ' · до ' + a.due + '</span><b>' + money(a.amount) + '</b></div></div>';
    }).join('');
    $$('#appList .card').forEach(function (c) { c.addEventListener('click', function () { openApp(c.dataset.id); }); });
  }

  $$('.qa-btn').forEach(function (b) {
    b.addEventListener('click', function () {
      var a = b.dataset.a;
      if (a === 'docs') { App.toast('Демо: раздел документов'); return; }
      if (a === 'new') renderList(0);
      else if (a === 'history') renderList(3);
      else renderList();
      App.toast(b.querySelector('.ql').textContent);
    });
  });

  /* ---------- Детали ---------- */
  function openApp(id) {
    current = APPS.find(function (a) { return a.id === id; });
    renderApp();
    screens.go('s3');
  }

  function renderApp() {
    var a = current;
    $('#aNum').textContent = a.id;
    var b = $('#aBadge'); b.textContent = STAGES[a.stage]; b.className = 'badge ' + (a.stage === 0 ? 'danger' : a.stage === 3 ? 'success' : 'info');
    $('#aTitle').textContent = a.title;
    $('#aTags').innerHTML = '<span class="tag">🛠 ' + a.op + '</span><span class="tag">🏭 ' + a.customer + '</span>' + (a.urgent ? '<span class="tag">🔥 Срочно</span>' : '');
    $('#aTracker').innerHTML = STAGES.map(function (s, i) {
      var cls = i < a.stage ? 'done' : i === a.stage ? 'current' : '';
      return '<div class="tr-item ' + cls + '"><div class="dot">' + (i < a.stage ? '✓' : '') + '</div><div class="tr-title">' + s + '</div></div>';
    }).join('');
    $('#aInfo').innerHTML =
      irow('Заказчик', a.customer) + irow('Сумма', money(a.amount)) + irow('Срок', a.due, a.urgent) + irow('Операция', a.op) + irow('Этап', STAGES[a.stage]);

    $('#acceptBtn').disabled = a.stage !== 0;
    $('#startBtn').disabled = a.stage !== 1;
    $('#finishBtn').disabled = a.stage !== 2;
  }
  function irow(k, v, alert) { return '<div class="row between" style="padding:8px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;' + (alert ? 'color:var(--danger);' : '') + '">' + v + '</b></div>'; }

  /* ---------- Действия по этапам ---------- */
  function advance(to, title, text) {
    current.stage = to;
    $('#actTitle').textContent = title;
    $('#actText').textContent = text;
    $('#actNum').textContent = current.id;
    renderApp(); renderDashboard();
    screens.go('s4');
  }
  $('#acceptBtn').addEventListener('click', function () { advance(1, 'Заявка принята', 'Вы подтвердили заявку. Можно приступать к работе.'); });
  $('#startBtn').addEventListener('click', function () { advance(2, 'Работа начата', 'Статус заявки переведён в «В работе».'); });
  $('#finishBtn').addEventListener('click', function () { advance(3, 'Заявка выполнена', 'Работа завершена. Сформируйте документы.'); });
  $('#docsBtn').addEventListener('click', function () { App.toast('Демо: акты, УПД и договор по заявке'); });

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#backApps').addEventListener('click', function () { renderDashboard(); screens.replace('s2'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
