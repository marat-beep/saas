/* ============================================================
   B7 · Бережливое производство
   дашборд → кайдзен-предложения → 5S-аудит
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var IDEAS = [
    { id: 'KD-114', title: 'Сократить переналадку станка ЧПУ', cat: 'Ускорение операций', author: 'А. Кузнецов', status: 'Внедрено', saving: 84000, date: '12.09', desc: 'Ввести предварительную подготовку инструмента и наладки вне станка (SMED).', effect: 'Сокращение переналадки с 40 до 18 минут.' },
    { id: 'KD-113', title: 'Быстросъёмное приспособление для ОТК', cat: 'Организация рабочих мест', author: 'Е. Соколова', status: 'Внедрено', saving: 46000, date: '05.09', desc: 'Сменные сменные базирующие вставки для контроля однотипных деталей.', effect: 'Снижение времени контроля на 30%.' },
    { id: 'KD-112', title: 'Повторное использование СОЖ', cat: 'Экономия материалов', author: 'В. Петров', status: 'На рассмотрении', saving: 32000, date: '28.08', desc: 'Система фильтрации и продление срока службы эмульсии.', effect: 'Экономия СОЖ и утилизации.' },
    { id: 'KD-111', title: 'Цветовая маркировка зон и инструмента', cat: 'Организация рабочих мест', author: 'М. Соколов', status: 'На рассмотрении', saving: 21000, date: '20.08', desc: 'Визуализация: маркировка мест хранения и контуров.', effect: 'Снижение времени поиска инструмента.' },
    { id: 'KD-110', title: 'Мелкие приспособления для стружкоудаления', cat: 'Безопасность', author: 'Д. Орлов', status: 'Внедрено', saving: 15000, date: '11.08', desc: 'Быстросъёмные скребки и порядок уборки рабочей зоны.', effect: 'Меньше простоев и травмоопасных ситуаций.' },
    { id: 'KD-109', title: 'Статистика брака по причинам', cat: 'Снижение брака', author: 'Е. Соколова', status: 'Отклонено', saving: 0, date: '02.08', desc: 'Сбор причин брака и разбор на планёрке.', effect: 'Требует доработки формулировки.' }
  ];

  var S5 = [
    { name: '1. Сортировка', hint: 'Убрано ли лишнее с рабочих мест?' },
    { name: '2. Самоорганизация', hint: 'У каждой вещи есть место и маркировка?' },
    { name: '3. Систематическая уборка', hint: 'Чистота станков и полов?' },
    { name: '4. Стандартизация', hint: 'Есть ли стандарты и визуальные инструкции?' },
    { name: '5. Совершенствование', hint: 'Соблюдается ли дисциплина и улучшения?' }
  ];

  var filter = 'all', current = null, level = 'strat';
  var s5Scores = [0, 0, 0, 0, 0];

  var LEVELS = {
    strat: { title: 'Стратегический уровень · собственник / директор',
      kpis: [['Экономия за квартал', '1,8 млн ₽'], ['Проектов в портфеле', '4'], ['ROI Lean-программы', '210%'], ['Цикл производства', '−30%']],
      init: [['Комплексный проект: механообработка', 'Внедрение', 65], ['VSM потока пресс-форм', 'Диагностика', 40], ['Обучение персонала Lean', 'План', 20]],
      note: 'Форматы работ: экспресс-диагностика этапа от 150 000 ₽, картирование VSM от 700 000 ₽, отдельный инструмент от 300 000 ₽, комплексный проект от 1 200 000 ₽.' },
    tact: { title: 'Тактический уровень · начальник цеха',
      kpis: [['Цикл участка', '8 дн (было 14)'], ['НЗП', '50 ед (было 120)'], ['Переналадка', '12 мин (было 45)'], ['Загрузка', '72%']],
      init: [['SMED: быстрая переналадка пресса', 'Внедрено', 100], ['Канбан между операциями', 'Внедрение', 70], ['Балансировка операций', 'Анализ', 45]],
      note: 'Инструменты: картирование потока (VSM), SMED, балансировка операций, управление запасами и НЗП.' },
    oper: { title: 'Операционный уровень · мастер / участок',
      kpis: [['Просрочек', '0'], ['Предложений', '6'], ['Осмотры TPM', '87%'], ['Метки инструмента', 'готовы']],
      init: [['5S: организация рабочих мест', 'В работе', 60], ['TPM: автономное обслуживание', 'План', 25], ['Poka-Yoke: защита от ошибок', 'Анализ', 35], ['Визуальное управление', 'Внедрение', 55]],
      note: 'Инструменты: 5S, TPM, Poka-Yoke, визуальное управление, стандартизация работы, ярлыки и метки.' }
  };

  // ---- Ежедневный инструмент: журнал потерь (7 видов) ----
  var LOSS_TYPES = ['Ожидание', 'Перепроизводство', 'Транспортировка', 'Излишняя обработка', 'Запасы', 'Лишние движения', 'Дефекты'];
  $('#lossType').innerHTML = LOSS_TYPES.map(function (t) { return '<option>' + t + '</option>'; }).join('');
  function renderLosses() {
    var l = App.Store.get('leanLosses', []);
    var total = l.reduce(function (a, x) { return a + (x.cost || 0); }, 0);
    $('#lossList').innerHTML = (l.length ? '<div class="faint" style="font-size:.72rem;margin-bottom:6px;">Записей: ' + l.length + ' · суммарно ' + money(total) + '</div>' + l.slice(0, 6).map(function (x) {
      return '<div class="row between" style="padding:7px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><span><b>' + x.type + '</b> — ' + x.text + '</span><b class="muted">' + (x.cost ? money(x.cost) : '—') + '</b></div>';
    }).join('') : '<div class="faint" style="font-size:.78rem;">Потерь не зафиксировано.</div>');
  }
  $('#lossText').addEventListener('input', function () { $('#addLoss').disabled = !this.value.trim(); });
  $('#addLoss').addEventListener('click', function () {
    var l = App.Store.get('leanLosses', []);
    l.unshift({ type: $('#lossType').value, cost: parseFloat($('#lossCost').value) || 0, text: $('#lossText').value.trim(), date: App.today() });
    App.Store.set('leanLosses', l.slice(0, 100));
    AppData.log.add({ action: 'Зафиксирована потеря', detail: $('#lossType').value });
    $('#lossText').value = ''; $('#lossCost').value = 0; $('#addLoss').disabled = true;
    renderLosses(); App.toast('Потеря зафиксирована');
  });

  function renderLevel() {
    var L = LEVELS[level];
    $('#lvBody').innerHTML =
      '<div class="faint" style="font-size:.72rem;margin-bottom:8px;">' + L.title + '</div>' +
      '<div class="grid two">' + L.kpis.map(function (k) { return '<div class="stat"><div class="num accent" style="font-size:1rem;">' + k[1] + '</div><div class="label">' + k[0] + '</div></div>'; }).join('') + '</div>' +
      '<div class="section-title">Инициативы и онлайн-трекинг</div>' +
      '<div class="card">' + L.init.map(function (i) { return '<div class="init"><div class="row between"><b style="font-size:.82rem;">' + i[0] + '</b><span class="badge ' + (i[2] >= 100 ? 'success' : 'accent') + '">' + i[1] + ' ' + i[2] + '%</span></div><div class="bar" style="width:' + i[2] + '%"></div></div>'; }).join('') + '</div>' +
      '<div class="callout info mt-12"><span class="ci">💡</span><div>' + L.note + '</div></div>' +
      '<button class="btn btn-secondary mt-12" id="labelsBtn">🏷 Скачать ярлыки и метки инструмента</button>';
    $('#labelsBtn').addEventListener('click', function () { location.href = '../b32-marking/index.html'; });
  }

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Дашборд ---------- */
  function renderDashboard() {
    var done = IDEAS.filter(function (i) { return i.status === 'Внедрено'; });
    $('#kIdeas').textContent = IDEAS.length;
    $('#kDone').textContent = done.length;
    $('#kSave').textContent = App.number(done.reduce(function (s, i) { return s + i.saving; }, 0) / 1000) + ' тыс.';
    var audit = App.Store.get('s5audit', null);
    if (audit) { $('#s5Score').textContent = audit.score + ' / 100'; $('#s5Badge').textContent = audit.score >= 80 ? 'Отлично' : audit.score >= 60 ? 'Норма' : 'Требует внимания'; $('#s5Date').textContent = audit.date; }
    else { $('#s5Score').textContent = '—'; $('#s5Badge').textContent = 'нет данных'; $('#s5Date').textContent = '—'; }
    renderList();
  }

  function renderList() {
    var list = IDEAS.filter(function (i) {
      if (filter === 'new') return i.status === 'На рассмотрении';
      if (filter === 'done') return i.status === 'Внедрено';
      return true;
    });
    $('#ideaCount').textContent = list.length + ' предложений';
    $('#ideaList').innerHTML = list.map(function (i) {
      var cls = i.status === 'Внедрено' ? 'done' : i.status === 'Отклонено' ? 'rejected' : '';
      var badge = i.status === 'Внедрено' ? 'success' : i.status === 'Отклонено' ? 'neutral' : 'warning';
      return '<div class="card clickable idea ' + cls + '" data-id="' + i.id + '"><div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + i.id + '</span><span class="badge ' + badge + '">' + i.status + '</span></div><h3 class="mt-8" style="font-size:.88rem;">' + i.title + '</h3><div class="meta-row"><span>👤 ' + i.author + ' · ' + i.date + '</span><b style="color:var(--accent-700);">' + (i.saving ? money(i.saving) : '—') + '</b></div></div>';
    }).join('');
    $$('#ideaList .card').forEach(function (c) { c.addEventListener('click', function () { openIdea(c.dataset.id); }); });
  }

  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });

  function openIdea(id) {
    current = IDEAS.find(function (i) { return i.id === id; });
    var i = current;
    $('#iNum').textContent = i.id + ' · ' + i.date;
    var b = $('#iStatus'); b.textContent = i.status; b.className = 'badge ' + (i.status === 'Внедрено' ? 'success' : i.status === 'Отклонено' ? 'neutral' : 'warning');
    $('#iTitle').textContent = i.title;
    $('#iTags').innerHTML = '<span class="tag">' + i.cat + '</span><span class="tag">👤 ' + i.author + '</span>';
    $('#iDesc').innerHTML = '<p class="muted" style="font-size:.82rem;line-height:1.55;">' + i.desc + '</p>';
    $('#iEffect').innerHTML = '<div style="font-size:.82rem;">' + i.effect + '</div>' + '<div class="row between mt-8"><span class="muted">Ожидаемая экономия</span><b style="color:var(--accent-700);">' + (i.saving ? money(i.saving) : '—') + '</b></div>';
    $('#approveBtn').disabled = i.status === 'Внедрено';
    $('#rejectBtn').disabled = i.status === 'Отклонено';
    screens.go('s2');
  }

  $('#approveBtn').addEventListener('click', function () { current.status = 'Внедрено'; App.toast('Предложение одобрено'); renderDashboard(); screens.replace('s1'); });
  $('#rejectBtn').addEventListener('click', function () { current.status = 'Отклонено'; App.toast('Предложение отклонено'); renderDashboard(); screens.replace('s1'); });

  /* ---------- Новое предложение ---------- */
  ['nTitle', 'nDesc'].forEach(function (id) { $('#' + id).addEventListener('input', checkIdea); });
  function checkIdea() { $('#sendIdea').disabled = !($('#nTitle').value.trim() && $('#nDesc').value.trim()); }
  $('#newIdeaBtn').addEventListener('click', function () { $('#sendIdea').disabled = true; screens.go('s3'); });
  $('#backDash').addEventListener('click', function () { screens.back(); });
  $('#sendIdea').addEventListener('click', function () {
    var id = 'KD-' + (115 + IDEAS.length);
    IDEAS.unshift({ id: id, title: $('#nTitle').value.trim(), cat: $('#nCat').value, author: 'Вы', status: 'На рассмотрении', saving: 0, date: App.today().slice(0, 5), desc: $('#nDesc').value.trim(), effect: 'Ожидает оценки эффекта.' });
    showSuccess('Предложение отправлено', 'Оно появится в списке на рассмотрении.', id);
  });

  /* ---------- 5S-аудит ---------- */
  function renderS5() {
    $('#s5List').innerHTML = S5.map(function (item, i) {
      return '<div class="s5-item"><b style="font-size:.84rem;">' + item.name + '</b><div class="faint" style="font-size:.72rem;">' + item.hint + '</div><div class="s5-scale" data-i="' + i + '">' +
        [1, 2, 3, 4, 5].map(function (n) { return '<button data-v="' + n + '"' + (s5Scores[i] === n ? ' class="on"' : '') + '>' + n + '</button>'; }).join('') + '</div></div>';
    }).join('');
    updateS5Total();
  }
  $('#s5List').addEventListener('click', function (e) {
    var b = e.target.closest('.s5-scale button'); if (!b) return;
    var i = parseInt(b.closest('.s5-scale').dataset.i, 10);
    s5Scores[i] = parseInt(b.dataset.v, 10);
    renderS5();
  });
  function updateS5Total() {
    var filled = s5Scores.filter(function (v) { return v > 0; });
    var score = filled.length ? Math.round(s5Scores.reduce(function (s, v) { return s + v; }, 0) / S5.length / 5 * 100) : 0;
    $('#s5Total').textContent = score + ' / 100';
    $('#saveAudit').disabled = filled.length < S5.length;
    $('#saveAudit').dataset.score = score;
  }
  $('#auditBtn').addEventListener('click', function () { s5Scores = [0, 0, 0, 0, 0]; renderS5(); screens.go('s4'); });
  $('#backDash2').addEventListener('click', function () { screens.back(); });
  $('#saveAudit').addEventListener('click', function () {
    var score = parseInt(this.dataset.score, 10);
    App.Store.set('s5audit', { score: score, date: App.today() });
    renderDashboard();
    showSuccess('5S-аудит сохранён', 'Индекс участка обновлён.', '5S-' + App.pad(Math.floor(1 + Math.random() * 999), 3));
  });

  /* ---------- Успех ---------- */
  function showSuccess(title, text, num) {
    $('#successTitle').textContent = title; $('#successText').textContent = text; $('#successNum').textContent = num;
    screens.go('s5');
  }
  $('#toDash').addEventListener('click', function () { screens.replace('s1'); });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  $('#lvTabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('button', this).forEach(function (x) { x.classList.toggle('active', x === b); });
    level = b.dataset.l; renderLevel();
  });

  renderDashboard();
  renderLevel();
  renderLosses();
})();
