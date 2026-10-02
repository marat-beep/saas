/* ============================================================
   B24 · Эскалация и проблемы
   единый реестр проблем с подсветкой, эскалацией и решением
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var LEVELS = { 'Критично': 'crit', 'Высокий': 'high', 'Средний': 'mid' };
  var ORDER = ['Средний', 'Высокий', 'Критично'];

  // стартовые проблемы (подтягиваются из контуров)
  AppData.problems.seed([
    { title: 'Авария станка Sodick AG (ALM-412)', source: 'B17', level: 'Критично', owner: 'Сервис', due: 'сегодня', detail: 'Низкий уровень рабочей жидкости, станок остановлен.' },
    { title: 'Заказ 3DMP-2025-0141 — срок под угрозой', source: 'B10', level: 'Критично', owner: 'Производство', due: '12.10', detail: 'Слот ОТК сдвинут, риск просрочки поставки.' },
    { title: 'Инструмент T01 Ø12 — износ 98%', source: 'B19', level: 'Высокий', owner: 'Инструментальный', due: 'сегодня', detail: 'Требуется замена до следующего запуска.' },
    { title: 'Дефицит стали 1.2379 на складе', source: 'B14', level: 'Высокий', owner: 'Снабжение', due: '18.10', detail: 'Остаток ниже минимума, нужна закупка.' },
    { title: 'Претензия по срокам — ООО «Металлист»', source: 'B16', level: 'Высокий', owner: 'Продажи', due: '14.10', detail: 'Клиент уведомил о задержке, нужен ответ.' },
    { title: 'Ожидание наладчика — Okuma LB3000', source: 'B22', level: 'Средний', owner: 'Цех', due: 'сегодня', detail: 'Оператор вызвал наладчика, простой.' }
  ]);

  var filter = 'open', current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderStats() {
    var all = AppData.problems.all();
    $('#kCrit').textContent = all.filter(function (p) { return p.level === 'Критично' && p.status !== 'Решена'; }).length;
    $('#kHigh').textContent = all.filter(function (p) { return p.level === 'Высокий' && p.status !== 'Решена'; }).length;
    $('#kRes').textContent = all.filter(function (p) { return p.status === 'Решена'; }).length;
    renderList();
  }

  function renderList() {
    var list = AppData.problems.all().filter(function (p) {
      if (filter === 'open') return p.status !== 'Решена';
      if (filter === 'crit') return p.level === 'Критично' && p.status !== 'Решена';
      return true;
    });
    $('#prbList').innerHTML = list.length ? list.map(function (p) {
      var cls = LEVELS[p.level] || 'mid';
      var st = p.status === 'Решена' ? 'success' : p.status === 'В работе' ? 'info' : 'warning';
      return '<div class="prb ' + cls + '" data-id="' + p.id + '"><div><div class="row" style="gap:8px;align-items:center;"><span class="lvl ' + cls + '">' + p.level + '</span><span class="faint" style="font-size:.66rem;">' + p.id + ' · ' + p.source + '</span></div><div style="font-weight:600;font-size:.84rem;margin-top:5px;">' + p.title + '</div><div class="faint" style="font-size:.66rem;">' + (p.owner || '') + ' · срок ' + (p.due || '—') + '</div></div><span class="badge ' + st + '">' + p.status + '</span></div>';
    }).join('') : '<div class="callout success"><span class="ci">✅</span><div>Открытых проблем нет.</div></div>';
    $$('#prbList .prb').forEach(function (el) { el.addEventListener('click', function () { openP(el.dataset.id); }); });
  }
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });

  function openP(id) {
    current = AppData.problems.all().filter(function (p) { return p.id === id; })[0];
    renderDetail();
    screens.go('s2');
  }
  function renderDetail() {
    var p = current, cls = LEVELS[p.level] || 'mid';
    $('#dId').textContent = p.id + ' · ' + p.source + ' · ' + p.date;
    var lv = $('#dLevel'); lv.textContent = p.level; lv.className = 'lvl ' + cls;
    $('#dTitle').textContent = p.title;
    $('#dTags').innerHTML = '<span class="tag">👤 ' + (p.owner || '—') + '</span><span class="tag">📅 ' + (p.due || '—') + '</span><span class="badge ' + (p.status === 'Решена' ? 'success' : p.status === 'В работе' ? 'info' : 'warning') + '">' + p.status + '</span>';
    $('#dInfo').innerHTML = '<p class="muted" style="font-size:.82rem;line-height:1.55;margin-bottom:8px;">' + (p.detail || '—') + '</p>' +
      row('Источник', p.source) + row('Ответственный', p.owner || '—') + row('Уровень', p.level) + row('Статус', p.status);
    $('#workBtn').disabled = p.status !== 'Открыта';
    $('#escBtn').disabled = p.status === 'Решена' || p.level === 'Критично';
    $('#resBtn').disabled = p.status === 'Решена';
  }
  function row(k, v) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }
  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }

  $('#workBtn').addEventListener('click', function () {
    AppData.problems.update(current.id, { status: 'В работе' });
    AppData.log.add({ action: 'Проблема в работе', detail: current.title });
    renderStats(); done('Взято в работу', current.title + ' — назначен ответственный.', current.id);
  });
  $('#escBtn').addEventListener('click', function () {
    var i = ORDER.indexOf(current.level);
    var next = ORDER[Math.min(ORDER.length - 1, i + 1)];
    AppData.problems.update(current.id, { level: next, status: 'В работе' });
    AppData.log.add({ action: 'Эскалация проблемы', detail: current.title + ' → ' + next });
    renderStats(); done('Эскалировано до «' + next + '»', 'Проблема поднята на уровень выше, уведомление отправлено.', current.id);
  });
  $('#resBtn').addEventListener('click', function () {
    AppData.problems.update(current.id, { status: 'Решена' });
    AppData.log.add({ action: 'Проблема решена', detail: current.title });
    renderStats(); done('Проблема решена', current.title + ' закрыта.', current.id);
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderStats(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderStats();
})();
