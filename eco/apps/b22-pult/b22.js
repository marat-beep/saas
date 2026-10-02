/* ============================================================
   B22 · Мобильный пульт оператора
   станок → действие (первая деталь / наладчик / стоп) → уведомление
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var STATE = { run: ['Работа', 'success'], idle: ['Простой', 'neutral'], setup: ['Наладка', 'warning'], alarm: ['Авария', 'danger'] };
  var MACHINES = [
    { id: 'EQ-01', name: 'DMG Mori NHX', state: 'run', order: '3DMP-2025-0142' },
    { id: 'EQ-02', name: 'Haas VF-4', state: 'run', order: '3DMP-2025-0141' },
    { id: 'EQ-03', name: 'Sodick AG', state: 'alarm', order: '3DMP-2025-0142' },
    { id: 'EQ-04', name: 'Okuma LB3000', state: 'setup', order: '3DMP-2025-0119' }
  ];
  var ACTIONS = [
    { id: 'first', icon: '✅', title: 'Первая деталь', desc: 'Отметить готовность и вызвать ОТК' },
    { id: 'call', icon: '📣', title: 'Вызвать наладчика', desc: 'Требуется помощь по настройке' },
    { id: 'stop', icon: '⛔', title: 'Проблема / стоп', desc: 'Станок остановлен, нужна помощь' }
  ];

  var current = null, action = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    $('#pList').innerHTML = MACHINES.map(function (m, i) {
      return '<div class="p-row" data-i="' + i + '"><div><div style="font-weight:600;font-size:.86rem;">' + m.name + '</div><div class="faint" style="font-size:.68rem;">' + m.order + '</div></div><span class="badge ' + STATE[m.state][1] + '">' + STATE[m.state][0] + '</span></div>';
    }).join('');
    $$('#pList .p-row').forEach(function (r) { r.addEventListener('click', function () { openM(parseInt(r.dataset.i, 10)); }); });
  }

  function openM(i) {
    current = MACHINES[i]; action = null;
    $('#dId').textContent = current.id;
    var b = $('#dState'); b.textContent = STATE[current.state][0]; b.className = 'badge ' + STATE[current.state][1];
    $('#dTitle').textContent = current.name;
    $('#actions').innerHTML = ACTIONS.map(function (a) {
      return '<button class="act-btn" data-a="' + a.id + '"><span class="ai">' + a.icon + '</span><span><b>' + a.title + '</b><span>' + a.desc + '</span></span></button>';
    }).join('');
    $$('#actions .act-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        action = btn.dataset.a;
        $$('#actions .act-btn').forEach(function (x) { x.classList.toggle('active', x === btn); });
        check();
      });
    });
    $('#comment').value = '';
    check();
    screens.go('s2');
  }
  function check() { $('#sendBtn').disabled = !(action && (action !== 'stop' || $('#comment').value.trim())); }
  $('#comment').addEventListener('input', check);

  $('#sendBtn').addEventListener('click', function () {
    var map = { first: ['Первая деталь готова', 'Вызван контролёр ОТК, деталь направлена на приёмку (B3).'], call: ['Вызван наладчик', 'Наладчик уведомлён, ожидайте у станка.'], stop: ['Зарегистрирован стоп', 'Мастер и диспетчер уведомлены, простой фиксируется в B17.'] };
    var m = map[action];
    if (action === 'stop') current.state = 'alarm';
    var num = 'PULT-' + App.pad(Math.floor(1 + Math.random() * 999), 4);
    $('#actTitle').textContent = m[0]; $('#actText').textContent = m[1]; $('#actNum').textContent = num;
    renderList();
    if (window.AppData) AppData.requests.add({ source: 'B22', title: current.name + ': ' + m[0], ref: num });
    screens.go('s3'); App.toast(m[0]);
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderList(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
