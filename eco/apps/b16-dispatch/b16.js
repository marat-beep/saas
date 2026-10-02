/* ============================================================
   B16 · Диспетчер обращений
   каналы → единый список → маршрутизация и обработка
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var CHANNELS = { site: '🌐', phone: '☎️', email: '✉️', tg: '✈️' };
  var TICKETS = [
    { id: 'TK-301', ch: 'site', from: 'ООО «Привод»', subject: 'Запрос КП на корпус редуктора', dept: '', topic: 'sale', status: 'new', prio: 'Высокий', date: '02.10', body: 'Просим рассчитать стоимость 12 корпусов. Чертёж прилагаем.' },
    { id: 'TK-302', ch: 'phone', from: 'ЗАО «ТехноПарк»', subject: 'Станок встал, нужен сервис', dept: '', topic: 'service', status: 'new', prio: 'Критичный', date: '02.10', body: 'Фрезерный станок остановился, ошибка по оси Z. Требуется срочный выезд.' },
    { id: 'TK-303', ch: 'email', from: 'ООО «Металлист»', subject: 'Уточнение по счёту', dept: 'Финансы', topic: 'sale', status: 'work', prio: 'Средний', date: '01.10', body: 'Просим уточнить реквизиты и сроки оплаты по счёту СЧ-2024.' },
    { id: 'TK-304', ch: 'tg', from: 'ИП Смирнов', subject: 'Статус заказа 3DMP-0119', dept: 'Продажи', topic: 'sale', status: 'work', prio: 'Средний', date: '01.10', body: 'Когда будет готов вал-шестерня? Ориентировали на 05.08.' },
    { id: 'TK-305', ch: 'site', from: 'ООО «ЛазерПро»', subject: 'Заявка на субподряд', dept: 'Продажи', topic: 'sale', status: 'closed', prio: 'Низкий', date: '30.09', body: 'Интересует кооперация по лазерной резке.' },
    { id: 'TK-306', ch: 'email', from: 'Кандидат A. Петров', subject: 'Резюме на оператора ЧПУ', dept: 'HR', topic: 'service', status: 'closed', prio: 'Низкий', date: '29.09', body: 'Направляю резюме на вакансию оператора ЧПУ.' }
  ];

  var filter = 'all', current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderStats() {
    var open = TICKETS.filter(function (t) { return t.status === 'new'; }).length;
    var work = TICKETS.filter(function (t) { return t.status === 'work'; }).length;
    var closed = TICKETS.filter(function (t) { return t.status === 'closed'; }).length;
    $('#kOpen').textContent = open;
    $('#kWork').textContent = work;
    $('#kClosed').textContent = closed;
    App.Store.set('dispatchStats', { open: open, work: work, closed: closed });
    renderList();
  }

  function renderList() {
    var list = TICKETS.filter(function (t) {
      if (filter === 'new') return t.status === 'new';
      if (filter === 'work') return t.status === 'work';
      if (filter === 'sale') return t.topic === 'sale';
      if (filter === 'service') return t.topic === 'service';
      return true;
    });
    $('#tkList').innerHTML = list.map(function (t, i) {
      var st = t.status === 'new' ? ['warning', 'Новое'] : t.status === 'work' ? ['info', 'В работе'] : ['success', 'Закрыто'];
      return '<div class="tk" data-id="' + t.id + '"><div class="row"><span class="ch">' + (CHANNELS[t.ch] || '💬') + '</span><div><div style="font-weight:600;font-size:.84rem;">' + t.subject + '</div><div class="faint" style="font-size:.68rem;">' + t.from + ' · ' + t.date + (t.dept ? ' · ' + t.dept : '') + '</div></div></div><div style="text-align:right;"><span class="badge ' + st[0] + '">' + st[1] + '</span>' + (t.prio === 'Критичный' ? '<div><span class="badge danger" style="margin-top:4px;">' + t.prio + '</span></div>' : '') + '</div></div>';
    }).join('');
    $$('#tkList .tk').forEach(function (r) { r.addEventListener('click', function () { openTicket(r.dataset.id); }); });
  }
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });

  function openTicket(id) {
    current = TICKETS.find(function (t) { return t.id === id; });
    var t = current;
    $('#tNum').textContent = t.id + ' · ' + (CHANNELS[t.ch] || '') + ' ' + t.ch;
    var b = $('#tStatus'); b.textContent = t.status === 'new' ? 'Новое' : t.status === 'work' ? 'В работе' : 'Закрыто'; b.className = 'badge ' + (t.status === 'new' ? 'warning' : t.status === 'work' ? 'info' : 'success');
    $('#tSubject').textContent = t.subject;
    $('#tTags').innerHTML = '<span class="tag">👤 ' + t.from + '</span><span class="tag">' + t.prio + '</span>' + (t.dept ? '<span class="tag">→ ' + t.dept + '</span>' : '<span class="tag">не назначено</span>');
    $('#tBody').innerHTML = '<p class="muted" style="font-size:.82rem;line-height:1.55;">' + t.body + '</p>';
    $('#tDept').value = t.dept || 'Продажи';
    screens.go('s2');
  }

  function done(t, txt, num) { $('#actTitle').textContent = t; $('#actText').textContent = txt; $('#actNum').textContent = num; screens.go('s3'); App.toast(t); }

  $('#routeBtn').addEventListener('click', function () {
    current.dept = $('#tDept').value; current.status = 'work';
    renderStats(); done('Обращение назначено', 'Направлено в отдел «' + current.dept + '».', current.id);
  });
  $('#replyBtn').addEventListener('click', function () {
    current.status = 'work'; renderStats(); done('Ответ отправлен', 'Ответ клиенту доставлен по каналу обращения.', current.id);
  });
  $('#closeBtn').addEventListener('click', function () {
    current.status = 'closed'; renderStats(); done('Обращение закрыто', 'Обращение переведено в статус «Закрыто».', current.id);
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderStats(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderStats();
})();
