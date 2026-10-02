/* ============================================================
   B17 · Монитор станков (OEE)
   состояние стоек, OEE, простои, алармы, текущий запуск
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var STATE = { run: ['Работа', 'success'], idle: ['Простой', 'neutral'], setup: ['Наладка', 'warning'], alarm: ['Авария', 'danger'] };

  var MACHINES = [
    { id: 'EQ-01', name: 'DMG Mori NHX', ctrl: 'Heidenhain TNC 640', state: 'run', oee: 82, avail: 90, perf: 93, qual: 98, hours: 4200, order: '3DMP-2025-0142', program: 'KORPUS_142_v3.H', alarm: '',
      shifts: [['Д', '6,8 ч', '92%'], ['Н', '5,4 ч', '86%'], ['Д', '7,1 ч', '94%']] },
    { id: 'EQ-02', name: 'Haas VF-4', ctrl: 'Fanuc 0i-MF', state: 'run', oee: 76, avail: 88, perf: 90, qual: 96, hours: 3100, order: '3DMP-2025-0141', program: 'STAMP_141_V2.NC', alarm: '',
      shifts: [['Д', '7,0 ч', '90%'], ['Н', '6,1 ч', '88%']] },
    { id: 'EQ-03', name: 'Sodick AG (ЭЭО)', ctrl: 'Sodick LN2W', state: 'alarm', oee: 41, avail: 55, perf: 78, qual: 95, hours: 2600, order: '3DMP-2025-0142', program: 'EDM_FORG_12.NC', alarm: 'ALM-412: низкий уровень рабочей жидкости',
      shifts: [['Д', '3,2 ч', '52%'], ['Н', '0 ч', '0%']] },
    { id: 'EQ-04', name: 'Okuma LB3000', ctrl: 'OSP-P300', state: 'setup', oee: 58, avail: 70, perf: 85, qual: 97, hours: 3800, order: '3DMP-2025-0119', program: 'VAL_119_V4.NC', alarm: '',
      shifts: [['Д', '5,5 ч', '80%'], ['Н', '4,0 ч', '72%']] },
    { id: 'EQ-05', name: 'Fanuc Robodrill', ctrl: 'Fanuc 31i', state: 'idle', oee: 63, avail: 72, perf: 88, qual: 99, hours: 1900, order: '—', program: '—', alarm: '',
      shifts: [['Д', '4,8 ч', '74%']] },
    { id: 'EQ-06', name: 'КИМ Zeiss', ctrl: 'CALYPSO', state: 'run', oee: 88, avail: 95, perf: 94, qual: 99, hours: 1200, order: '3DMP-2025-0138', program: 'CMM_QC_38', alarm: '',
      shifts: [['Д', '7,6 ч', '96%']] }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    var avg = Math.round(MACHINES.reduce(function (a, m) { return a + m.oee; }, 0) / MACHINES.length);
    $('#kOee').textContent = avg + '%';
    $('#kRun').textContent = MACHINES.filter(function (m) { return m.state === 'run'; }).length;
    var alarms = MACHINES.filter(function (m) { return m.state === 'alarm'; }).length;
    $('#kAlarm').textContent = alarms;
    App.Store.set('monitorStats', { oee: avg, alarms: alarms });
    $('#mCount').textContent = MACHINES.length + ' единиц';
    $('#machines').innerHTML = MACHINES.map(function (m, i) {
      return '<div class="m-row" data-i="' + i + '"><span class="m-dot ' + m.state + '"></span><div class="grow"><div class="row between"><b style="font-size:.84rem;">' + m.name + '</b><span class="badge ' + STATE[m.state][1] + '">' + STATE[m.state][0] + '</span></div><div class="faint" style="font-size:.68rem;">' + m.ctrl + ' · ' + m.program + '</div><div class="oee-bar"><i style="width:' + m.oee + '%"></i></div></div><b style="font-size:.9rem;min-width:42px;text-align:right;">' + m.oee + '%</b></div>';
    }).join('');
    $$('#machines .m-row').forEach(function (r) { r.addEventListener('click', function () { openM(parseInt(r.dataset.i, 10)); }); });
  }

  function openM(i) {
    current = MACHINES[i]; var m = current;
    $('#dName').textContent = m.id + ' · ' + m.ctrl;
    var b = $('#dState'); b.textContent = STATE[m.state][0]; b.className = 'badge ' + STATE[m.state][1];
    $('#dTitle').textContent = m.name;
    $('#dTags').innerHTML = '<span class="tag">⏱ ' + App.number(m.hours) + ' ч</span>' + (m.alarm ? '<span class="tag" style="color:var(--danger);">⚠ ' + m.alarm + '</span>' : '<span class="tag">Алармов нет</span>');
    $('#dOee').innerHTML = '<div><b>' + m.oee + '%</b><span>OEE</span></div><div><b>' + m.avail + '%</b><span>Доступность</span></div><div><b>' + m.perf + '%</b><span>Производит.</span></div><div><b>' + m.qual + '%</b><span>Качество</span></div>';
    $('#dRun').innerHTML = row('Заказ', m.order) + row('Программа', m.program) + row('Состояние', STATE[m.state][0]) + row('Аларм', m.alarm || '—');
    $('#dShifts').innerHTML = m.shifts.map(function (s) { return '<div class="row between" style="padding:7px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><span>Смена ' + s[0] + '</span><span class="muted">наработка ' + s[1] + '</span><b>' + s[2] + '</b></div>'; }).join('');
    screens.go('s2');
  }
  function row(k, v, accent) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b style="text-align:right;' + (accent ? 'color:var(--danger);' : '') + '">' + v + '</b></div>'; }
  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }

  $('#stopBtn').addEventListener('click', function () { current.state = 'alarm'; current.oee = Math.max(0, current.oee - 8); current.alarm = 'Простой: ожидание наладчика'; renderList(); done('Простой зарегистрирован', 'Станок переведён в аварию, мастер уведомлён.', current.id); });
  $('#resetBtn').addEventListener('click', function () { current.state = 'run'; current.alarm = ''; renderList(); done('Авария снята', 'Станок возвращён в работу.', current.id); });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
