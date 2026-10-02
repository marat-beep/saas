/* ============================================================
   B29 · Рабочее место сервисного инженера
   заявки на обслуживание, диагностика, выезд, закрытие
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var TASKS = [
    { id: 'SRV-501', equip: 'Sodick AG (ЭЭО)', type: 'emergency', client: 'ООО «АвтоПласт»', addr: 'Москва, цех 2', sla: 'выезд 4 ч', status: 'Новая', problem: 'ALM-412: низкий уровень рабочей жидкости, станок остановлен.',
      checks: [['Проверить уровень и датчик рабочей жидкости', false], ['Осмотреть насос и фильтры', false], ['Проверить ошибки на пульте', false], ['Пробный запуск', false]] },
    { id: 'SRV-502', equip: 'DMG Mori NHX', type: 'maintenance', client: 'ООО «Привод»', addr: 'Москва, цех 1', sla: 'плановое ТО', status: 'В работе', problem: 'Плановое ТО: смазка направляющих, проверка геометрии.',
      checks: [['Проверить уровень масла', true], ['Смазать направляющие', true], ['Проверить СОЖ', false], ['Тест по программе', false]] },
    { id: 'SRV-503', equip: 'Haas VF-4', type: 'diagnostic', client: 'ЗАО «ТехноПарк»', addr: 'Подольск', sla: 'реакция 4 ч', status: 'Новая', problem: 'Периодический шум в районе шпинделя.',
      checks: [['Прослушать шпиндель', false], ['Проверить люфт', false], ['Проверить крепление инструмента', false]] },
    { id: 'SRV-504', equip: 'Okuma LB3000', type: 'consult', client: 'ИП Смирнов', addr: 'Москва', sla: 'реакция 2 ч', status: 'Закрыта', problem: 'Подбор режимов для нержавейки.',
      checks: [['Консультация по режимам', true], ['Проверка инструмента', true]] }
  ];

  var filter = 'open', current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderStats() {
    $('#kNew').textContent = TASKS.filter(function (t) { return t.status === 'Новая'; }).length;
    $('#kWork').textContent = TASKS.filter(function (t) { return t.status === 'В работе'; }).length;
    $('#kDone').textContent = TASKS.filter(function (t) { return t.status === 'Закрыта'; }).length;
    renderList();
  }
  function renderList() {
    var list = TASKS.filter(function (t) {
      if (filter === 'open') return t.status !== 'Закрыта';
      if (filter === 'emergency') return t.type === 'emergency' && t.status !== 'Закрыта';
      return true;
    });
    var names = { emergency: ['danger', 'Аварийная'], maintenance: ['info', 'Плановое ТО'], diagnostic: ['warning', 'Диагностика'], consult: ['neutral', 'Консультация'] };
    $('#svcList').innerHTML = list.length ? list.map(function (t) {
      var n = names[t.type];
      return '<div class="svc-row" data-id="' + t.id + '"><div><div class="row" style="gap:8px;"><span class="badge ' + n[0] + '">' + n[1] + '</span><span class="faint" style="font-size:.66rem;">' + t.id + '</span></div><div style="font-weight:600;font-size:.84rem;margin-top:5px;">' + t.equip + '</div><div class="faint" style="font-size:.66rem;">' + t.client + ' · ' + t.addr + '</div></div><span class="badge ' + (t.status === 'Закрыта' ? 'success' : t.status === 'В работе' ? 'info' : 'warning') + '">' + t.status + '</span></div>';
    }).join('') : '<div class="callout success"><span class="ci">✅</span><div>Открытых заявок нет.</div></div>';
    $$('#svcList .svc-row').forEach(function (el) { el.addEventListener('click', function () { openT(el.dataset.id); }); });
  }
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });

  function openT(id) {
    current = TASKS.filter(function (t) { return t.id === id; })[0];
    renderDetail();
    screens.go('s2');
  }
  function renderDetail() {
    var t = current;
    var names = { emergency: 'Аварийная', maintenance: 'Плановое ТО', diagnostic: 'Диагностика', consult: 'Консультация' };
    $('#dId').textContent = t.id + ' · ' + names[t.type];
    var b = $('#dStatus'); b.textContent = t.status; b.className = 'badge ' + (t.status === 'Закрыта' ? 'success' : t.status === 'В работе' ? 'info' : 'warning');
    $('#dTitle').textContent = t.equip;
    $('#dTags').innerHTML = '<span class="tag">🏭 ' + t.client + '</span><span class="tag">📍 ' + t.addr + '</span><span class="tag">⏱ ' + t.sla + '</span>';
    $('#dInfo').innerHTML = row('Проблема', t.problem) + row('Тип', names[t.type]) + row('SLA', t.sla) + row('Статус', t.status);
    $('#dChecks').innerHTML = t.checks.map(function (c, i) { return '<div class="chk ' + (c[1] ? 'done' : '') + '" data-i="' + i + '"><span class="box">' + (c[1] ? '✓' : '') + '</span><span class="lbl">' + c[0] + '</span></div>'; }).join('');
    $$('#dChecks .chk').forEach(function (el) {
      el.addEventListener('click', function () { var i = parseInt(el.dataset.i, 10); t.checks[i][1] = !t.checks[i][1]; renderDetail(); });
    });
    $('#startBtn').disabled = t.status !== 'Новая';
    $('#closeBtn').disabled = t.status === 'Закрыта' || !t.checks.every(function (c) { return c[1]; });
  }
  function row(k, v) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;gap:12px;"><span class="muted" style="flex-shrink:0;">' + k + '</span><b style="text-align:right;">' + v + '</b></div>'; }
  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }

  $('#startBtn').addEventListener('click', function () { current.status = 'В работе'; AppData.log.add({ action: 'Сервис: выезд', detail: current.id + ' · ' + current.equip }); renderStats(); done('Заявка принята', 'Статус «В работе», выезд назначен.', current.id); });
  $('#closeBtn').addEventListener('click', function () { current.status = 'Закрыта'; AppData.log.add({ action: 'Сервис: закрыт', detail: current.id + ' · ' + current.equip }); renderStats(); done('Выезд завершён', 'Заявка закрыта, диагностика зафиксирована.', current.id); });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderStats(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderStats();
})();
