/* ============================================================
   B30 · КД и изменения (конструктор / технолог)
   комплекты КД, версии, ECN, нормоконтроль, утверждение
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var DOCS = [
    { id: 'KD-142', order: '3DMP-2025-0142', title: 'Пресс-форма втулки — комплект КД', version: 'v3', status: 'На нормоконтроле',
      items: [['Сборочный чертёж', 'SB-142', 'v3'], ['Формообразующая плита', 'DR-142-01', 'v2'], ['Плита матрицы', 'DR-142-02', 'v2'], ['Спецификация', 'SP-142', 'v3']],
      changes: [['ECN-014', '02.10', 'Изменён радиус галтели R2→R3'], ['ECN-011', '27.09', 'Уточнён допуск посадки']],
      check: [['Формат и рамка по ГОСТ', true], ['Обозначения шероховатости', true], ['Допуски и посадки проставлены', true], ['Оформление спецификации', false]] },
    { id: 'KD-141', order: '3DMP-2025-0141', title: 'Штамп вырубной — КД', version: 'v2', status: 'Утверждено',
      items: [['Сборочный чертёж', 'SB-141', 'v2'], ['Пуансон', 'DR-141-01', 'v2'], ['Матрица', 'DR-141-02', 'v2']],
      changes: [['ECN-009', '20.09', 'Увеличен зазор штампа'], ['ECN-006', '12.09', 'Изменён материал пуансона']],
      check: [['Формат и рамка по ГОСТ', true], ['Обозначения шероховатости', true], ['Допуски и посадки проставлены', true], ['Оформление спецификации', true]] },
    { id: 'KD-150', order: '3DMP-2025-0150', title: 'Плита прижимная — КД', version: 'v1', status: 'В разработке',
      items: [['Чертёж детали', 'DR-150-01', 'v1'], ['Спецификация', 'SP-150', 'v1']],
      changes: [['ECN-001', '18.09', 'Первичный выпуск']],
      check: [['Формат и рамка по ГОСТ', true], ['Обозначения шероховатости', false], ['Допуски и посадки проставлены', false], ['Оформление спецификации', false]] }
  ];

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderList() {
    $('#dCount').textContent = DOCS.length + ' комплектов';
    $('#docList').innerHTML = DOCS.map(function (d, i) {
      var st = d.status === 'Утверждено' ? ['success', 'Утверждено'] : d.status === 'На нормоконтроле' ? ['info', 'На нормоконтроле'] : ['warning', 'В разработке'];
      return '<div class="d-row" data-i="' + i + '"><div><div style="font-weight:600;font-size:.84rem;">' + d.title + '</div><div class="faint" style="font-size:.66rem;">' + d.id + ' · ' + d.order + ' · ' + d.version + ' · ' + d.items.length + ' документов</div></div><span class="badge ' + st[0] + '">' + st[1] + '</span></div>';
    }).join('');
    $$('#docList .d-row').forEach(function (el) { el.addEventListener('click', function () { openD(parseInt(el.dataset.i, 10)); }); });
  }

  function openD(i) {
    current = DOCS[i]; var d = current;
    $('#dId').textContent = d.id;
    var st = d.status === 'Утверждено' ? 'success' : d.status === 'На нормоконтроле' ? 'info' : 'warning';
    var b = $('#dStatus'); b.textContent = d.status; b.className = 'badge ' + st;
    $('#dTitle').textContent = d.title;
    $('#dTags').innerHTML = '<span class="tag">' + d.order + '</span><span class="tag">Версия ' + d.version + '</span>';
    $('#dItems').innerHTML = d.items.map(function (it) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span>' + it[0] + '</span><span class="muted" style="font-family:var(--mono);font-size:.72rem;">' + it[1] + ' · ' + it[2] + '</span></div>'; }).join('');
    $('#dChanges').innerHTML = d.changes.map(function (c) { return '<div class="ecn"><b>' + c[0] + '</b> <span class="faint">' + c[1] + '</span><div>' + c[2] + '</div></div>'; }).join('');
    $('#dCheck').innerHTML = d.check.map(function (c) { return '<div class="row between" style="padding:7px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><span>' + (c[1] ? '✅' : '⬜') + ' ' + c[0] + '</span><span class="badge ' + (c[1] ? 'success' : 'neutral') + '">' + (c[1] ? 'ОК' : 'нет') + '</span></div>'; }).join('');
    var ready = d.check.every(function (c) { return c[1]; });
    $('#reviewBtn').disabled = d.status !== 'В разработке';
    $('#approveBtn').disabled = d.status !== 'На нормоконтроле' || !ready;
    screens.go('s2');
  }
  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }

  $('#ecnBtn').addEventListener('click', function () {
    var n = 'ECN-' + App.pad(current.changes.length + 15, 3);
    current.changes.unshift([n, App.today().slice(0, 5), 'Новое изменение — уточните описание']);
    current.version = 'v' + (parseInt(current.version.replace('v', ''), 10) + 1);
    AppData.log.add({ action: 'Создано ECN', detail: n + ' · ' + current.id });
    openD(DOCS.indexOf(current));
    done('Создано ' + n, 'Новая версия ' + current.version + ' в разработке.', current.id);
  });
  $('#reviewBtn').addEventListener('click', function () { current.status = 'На нормоконтроле'; openD(DOCS.indexOf(current)); done('Отправлено на нормоконтроль', current.id + ' передан в нормоконтроль.', current.id); });
  $('#approveBtn').addEventListener('click', function () { current.status = 'Утверждено'; openD(DOCS.indexOf(current)); done('КД утверждена', current.id + ' утверждён, версия ' + current.version + '.', current.id); });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderList(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderList();
})();
