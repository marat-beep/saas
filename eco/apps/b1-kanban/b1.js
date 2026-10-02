/* ============================================================
   B1 · Канбан-доска производства
   6 колонок, фильтры, карточка задачи, смена этапа, комментарии
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var COLUMNS = [
    { id: 'queue', title: 'Очередь' },
    { id: 'design', title: 'Проектирование' },
    { id: 'cnc', title: 'ЧПУ' },
    { id: 'edm', title: 'Электроэрозия' },
    { id: 'qc', title: 'ОТК' },
    { id: 'ready', title: 'Готово' }
  ];

  var tasks = [
    { id: 'K-201', title: 'Пресс-форма втулки', col: 'cnc', prio: 'Высокий', overdue: false, tags: ['ЧПУ', 'Сталь'], assignee: 'АК', due: '12.10', customer: 'ООО «АвтоПласт»', op: 'Фрезеровка', comments: [{ a: 'АК', t: 'Начал черновую обработку', time: '09:12' }] },
    { id: 'K-202', title: 'Штамп вырубной, серия 50', col: 'design', prio: 'Средний', overdue: false, tags: ['Проект'], assignee: 'МС', due: '15.10', customer: 'ЗАО «ТехноПарк»', op: 'Проектирование', comments: [] },
    { id: 'K-203', title: 'Электрод для ЭЭО', col: 'edm', prio: 'Высокий', overdue: true, tags: ['ЭЭО', 'Графит'], assignee: 'ВП', due: '09.10', customer: 'ООО «Металлист»', op: 'Электроэрозия', comments: [{ a: 'ВП', t: 'Износ электрода выше нормы', time: '08:40' }] },
    { id: 'K-204', title: 'Корпус редуктора', col: 'qc', prio: 'Средний', overdue: false, tags: ['ОТК'], assignee: 'ЕС', due: '11.10', customer: 'ООО «Привод»', op: 'Контроль', comments: [] },
    { id: 'K-205', title: 'Вал-шестерня', col: 'ready', prio: 'Низкий', overdue: false, tags: ['Готово'], assignee: 'АК', due: '08.10', customer: 'ИП Смирнов', op: 'Токарка', comments: [] },
    { id: 'K-206', title: 'Оснастка для лазера', col: 'queue', prio: 'Средний', overdue: false, tags: ['Лазер'], assignee: 'МС', due: '18.10', customer: 'ООО «ЛазерПро»', op: 'Лазер', comments: [] },
    { id: 'K-207', title: 'Плита прижимная', col: 'cnc', prio: 'Высокий', overdue: false, tags: ['ЧПУ'], assignee: 'ВП', due: '10.10', customer: 'ООО «АвтоПласт»', op: 'Фрезеровка', comments: [] },
    { id: 'K-208', title: 'Кронштейн датчика', col: 'queue', prio: 'Низкий', overdue: true, tags: ['ЧПУ', 'Срочно'], assignee: 'АК', due: '07.10', customer: 'ЗАО «ТехноПарк»', op: 'Фрезеровка', comments: [] },
    { id: 'K-209', title: 'Форма для силиконовой манжеты', col: 'design', prio: 'Средний', overdue: false, tags: ['Проект', 'Пресс-форма'], assignee: 'МС', due: '17.10', customer: 'ИП Смирнов', op: 'Проектирование', comments: [{ a: 'МС', t: 'Согласована конструкция формообразующих', time: '11:05' }] },
    { id: 'K-210', title: 'Крышка корпуса, 40 шт', col: 'cnc', prio: 'Средний', overdue: false, tags: ['ЧПУ', 'Серия'], assignee: 'АК', due: '14.10', customer: 'ООО «Привод»', op: 'Фрезеровка', comments: [] },
    { id: 'K-211', title: 'Пуансон гибочный', col: 'edm', prio: 'Средний', overdue: false, tags: ['ЭЭО'], assignee: 'ВП', due: '16.10', customer: 'ЗАО «ТехноПарк»', op: 'Электроэрозия', comments: [] },
    { id: 'K-212', title: 'Направляющие втулки, 24 шт', col: 'cnc', prio: 'Низкий', overdue: false, tags: ['Токарка'], assignee: 'ВП', due: '13.10', customer: 'ООО «Металлист»', op: 'Токарка', comments: [] },
    { id: 'K-213', title: 'Штамп-компаунд', col: 'qc', prio: 'Высокий', overdue: false, tags: ['ОТК'], assignee: 'ЕС', due: '09.10', customer: 'ООО «АвтоПласт»', op: 'Контроль', comments: [] },
    { id: 'K-214', title: 'Державка расточная', col: 'ready', prio: 'Низкий', overdue: false, tags: ['Готово'], assignee: 'АК', due: '06.10', customer: 'ИП Смирнов', op: 'Фрезеровка', comments: [] },
    { id: 'K-215', title: 'Матрица вырубная, 2 шт', col: 'queue', prio: 'Высокий', overdue: false, tags: ['ЧПУ', 'Сталь'], assignee: 'ВП', due: '19.10', customer: 'ЗАО «ТехноПарк»', op: 'Фрезеровка', comments: [] },
    { id: 'K-216', title: 'Электрод-шина ЭЭО', col: 'queue', prio: 'Средний', overdue: false, tags: ['ЭЭО', 'Медь'], assignee: 'ВП', due: '20.10', customer: 'ООО «Металлист»', op: 'Электроэрозия', comments: [] },
    { id: 'K-217', title: 'Оправка сборочная', col: 'design', prio: 'Низкий', overdue: false, tags: ['Оснастка'], assignee: 'МС', due: '21.10', customer: 'ООО «ЛазерПро»', op: 'Проектирование', comments: [] },
    { id: 'K-218', title: 'Плита-основание лазера', col: 'cnc', prio: 'Средний', overdue: true, tags: ['ЧПУ', 'Алюминий'], assignee: 'АК', due: '08.10', customer: 'ООО «ЛазерПро»', op: 'Фрезеровка', comments: [{ a: 'АК', t: 'Ожидание материала', time: '07:55' }] }
  ];

  var filter = 'all';
  var current = null;

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Доска ---------- */
  function renderBoard() {
    var overdue = tasks.filter(function (t) { return t.overdue && t.col !== 'ready'; }).length;
    $('#alerts').innerHTML = overdue
      ? '<span class="alert-pill">⚠️ Просрочено: ' + overdue + '</span>'
      : '<span class="alert-pill ok">✓ Просрочек нет</span>';

    $('#board').innerHTML = COLUMNS.map(function (c) {
      var list = tasks.filter(function (t) {
        if (t.col !== c.id) return false;
        if (filter === 'mine') return t.assignee === 'АК';
        if (filter === 'urgent') return t.prio === 'Высокий' || t.overdue;
        if (filter === 'cnc') return t.tags.indexOf('ЧПУ') >= 0;
        return true;
      });
      return '<div class="col"><div class="col-head"><b>' + c.title + '</b><span class="cnt">' + list.length + '</span></div>' +
        '<div class="col-body" data-col="' + c.id + '">' + list.map(card).join('') + '</div></div>';
    }).join('');
    $$('#board .tcard').forEach(function (el) { el.addEventListener('click', function () { openTask(el.dataset.id); }); });

    // drag & drop между колонками
    $$('#board .tcard').forEach(function (el) {
      el.setAttribute('draggable', 'true');
      el.addEventListener('dragstart', function (e) {
        e.dataTransfer.setData('text/plain', el.dataset.id);
        e.dataTransfer.effectAllowed = 'move';
        el.style.opacity = '.5';
      });
      el.addEventListener('dragend', function () { el.style.opacity = ''; });
    });
    $$('#board .col-body').forEach(function (z) {
      z.addEventListener('dragover', function (e) { e.preventDefault(); z.style.background = 'var(--accent-50)'; });
      z.addEventListener('dragleave', function () { z.style.background = ''; });
      z.addEventListener('drop', function (e) {
        e.preventDefault(); z.style.background = '';
        var id = e.dataTransfer.getData('text/plain');
        var t = tasks.filter(function (x) { return x.id === id; })[0];
        if (t && t.col !== z.dataset.col) {
          t.col = z.dataset.col;
          var col = COLUMNS.filter(function (c) { return c.id === t.col; })[0];
          renderBoard();
          App.toast(t.id + ' → ' + col.title);
        }
      });
    });
  }

  function card(t) {
    return '<div class="tcard' + (t.overdue && t.col !== 'ready' ? ' overdue' : '') + '" data-id="' + t.id + '" draggable="true">' +
      '<div class="row between"><span class="num">' + t.id + '</span>' + (t.prio === 'Высокий' ? '<span class="badge danger">Высокий</span>' : '') + '</div>' +
      '<h4>' + t.title + '</h4>' +
      '<div class="tags">' + t.tags.map(function (x) { return '<span class="tag">' + x + '</span>'; }).join('') + '</div>' +
      '<div class="foot"><span class="avatar">' + t.assignee + '</span><span class="due' + (t.overdue && t.col !== 'ready' ? ' overdue' : '') + '">' + (t.overdue && t.col !== 'ready' ? '⚠ ' : '📅 ') + t.due + '</span></div></div>';
  }

  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderBoard();
  });

  /* ---------- Задача ---------- */
  function openTask(id) {
    current = tasks.find(function (t) { return t.id === id; });
    renderTask();
    screens.go('s2');
  }

  function renderTask() {
    var t = current;
    var ci = COLUMNS.findIndex(function (c) { return c.id === t.col; });
    $('#tkNum').textContent = t.id + ' · ' + t.customer;
    var pb = $('#tkPrio'); pb.textContent = t.prio; pb.className = 'badge ' + (t.prio === 'Высокий' ? 'danger' : t.prio === 'Средний' ? 'warning' : 'neutral');
    $('#tkTitle').textContent = t.title;
    $('#tkTags').innerHTML = t.tags.map(function (x) { return '<span class="tag">' + x + '</span>'; }).join('') + '<span class="tag">👤 ' + t.assignee + '</span>';
    $('#tkProgress').style.width = Math.round(((ci + (t.col === 'ready' ? 1 : 0)) / COLUMNS.length) * 100) + '%';

    $('#tkStages').innerHTML = COLUMNS.map(function (c, i) {
      var st = i < ci ? 'done' : i === ci ? 'current' : '';
      return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);"><span style="font-size:.84rem;font-weight:' + (st ? '700' : '500') + ';color:' + (st ? 'var(--text)' : 'var(--muted)') + ';">' + (i < ci ? '✅ ' : i === ci ? '🔵 ' : '⚪ ') + c.title + '</span>' + (i === ci ? '<span class="badge info">Текущий</span>' : '') + '</div>';
    }).join('');

    $('#tkInfo').innerHTML =
      irow('Заказчик', t.customer) + irow('Операция', t.op) + irow('Исполнитель', t.assignee) + irow('Срок', t.due, t.overdue);
    $('#advanceBtn').disabled = ci >= COLUMNS.length - 1;
    $('#advanceBtn').textContent = ci >= COLUMNS.length - 1 ? 'Задача завершена' : 'Перевести: ' + COLUMNS[ci + 1].title + ' →';
    renderComments();
  }

  function irow(k, v, alert) {
    return '<div class="row between" style="padding:8px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="' + (alert ? 'color:var(--danger);' : '') + '">' + v + '</b></div>';
  }

  function renderComments() {
    var cs = current.comments;
    $('#cmCount').textContent = cs.length + ' шт';
    $('#tkComments').innerHTML = cs.length ? cs.map(function (c) {
      return '<div class="card mb-8" style="padding:10px 12px;"><div class="row between"><b style="font-size:.76rem;">' + c.a + '</b><span class="faint" style="font-size:.68rem;">' + c.time + '</span></div><div style="font-size:.82rem;margin-top:4px;">' + c.t + '</div></div>';
    }).join('') : '<div class="callout info"><span class="ci">💬</span><div>Комментариев пока нет.</div></div>';
  }

  $('#advanceBtn').addEventListener('click', function () {
    var ci = COLUMNS.findIndex(function (c) { return c.id === current.col; });
    if (ci >= COLUMNS.length - 1) return;
    current.col = COLUMNS[ci + 1].id;
    current.comments.push({ a: 'АК', t: 'Этап переведён: ' + COLUMNS[ci + 1].title, time: App.nowTime() });
    App.toast('Переведено: ' + COLUMNS[ci + 1].title);
    renderTask(); renderBoard();
  });

  function sendComment() {
    var v = $('#commentInput').value.trim();
    if (!v) return;
    current.comments.push({ a: 'АК', t: v, time: App.nowTime() });
    $('#commentInput').value = '';
    renderComments();
  }
  $('#sendComment').addEventListener('click', sendComment);
  $('#commentInput').addEventListener('keydown', function (e) { if (e.key === 'Enter') sendComment(); });

  $('#commentBtn').addEventListener('click', function () { $('#commentInput').focus(); });
  $('#fileBtn').addEventListener('click', function () { current.comments.push({ a: 'АК', t: '📎 Прикреплён файл: ' + current.id + '_rev' + (current.comments.length + 1) + '.pdf', time: App.nowTime() }); renderComments(); App.toast('Файл прикреплён'); });
  $('#problemBtn').addEventListener('click', function () { current.comments.push({ a: 'АК', t: '⚠️ Отмечена проблема — требуется решение технолога', time: App.nowTime() }); current.overdue = true; renderTask(); renderBoard(); App.toast('Проблема отмечена'); });
  $('#drawingBtn').addEventListener('click', function () { App.toast('Демо: открытие чертежа в 3D-viewer'); });

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { renderBoard(); screens.back(); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderBoard();
})();
