/* ============================================================
   B4 · База знаний
   каталог → статья / видео / тест → результат
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var QUICK = [
    { n: 24, l: 'Инструкции ТБ', c: 'tb', icon: '🦺' },
    { n: 38, l: 'Оборудование', c: 'equip', icon: '⚙️' },
    { n: 52, l: 'Техпроцессы', c: 'tech', icon: '📐' },
    { n: 18, l: 'HR и адаптация', c: 'hr', icon: '👥' }
  ];

  var MATERIALS = [
    { id: 'M1', cat: 'tb', type: 'article', icon: '🦺', title: 'Инструкция по охране труда при работе на ЧПУ', meta: 'Обязательно · 8 мин' },
    { id: 'M2', cat: 'equip', type: 'video', icon: '⚙️', title: 'Запуск и настройка фрезерного станка DMG', meta: 'Видео · 12 мин' },
    { id: 'M3', cat: 'tech', type: 'article', icon: '📐', title: 'Типовой техпроцесс фрезеровки корпусных деталей', meta: 'Регламент · 6 мин' },
    { id: 'M4', cat: 'hr', type: 'new', icon: '👥', title: 'Памятка нового сотрудника: первые 30 дней', meta: 'Новое · 5 мин' },
    { id: 'M5', cat: 'tb', type: 'test', icon: '📝', title: 'Тест: электробезопасность на производстве', meta: 'Тест · 5 вопросов' },
    { id: 'M6', cat: 'equip', type: 'article', icon: '🛠', title: 'Ежедневное ТО станков: чек-лист оператора', meta: 'Регламент · 4 мин' },
    { id: 'M7', cat: 'tb', type: 'article', icon: '🚒', title: 'Пожарная безопасность: эвакуация из цеха', meta: 'Обязательно · 7 мин' },
    { id: 'M8', cat: 'equip', type: 'article', icon: '🧪', title: 'СОЖ: настройка и контроль концентрации', meta: 'Регламент · 5 мин' },
    { id: 'M9', cat: 'tech', type: 'article', icon: '🔥', title: 'Термообработка: закалка и отпуск деталей', meta: 'Регламент · 9 мин' },
    { id: 'M10', cat: 'hr', type: 'article', icon: '📋', title: 'Правила внутреннего трудового распорядка', meta: 'Документ · 6 мин' },
    { id: 'M11', cat: 'tb', type: 'video', icon: '🎬', title: 'Видеоинструктаж: безопасная работа на станке', meta: 'Видео · 9 мин' },
    { id: 'M12', cat: 'equip', type: 'test', icon: '📝', title: 'Тест: ежедневное ТО оборудования', meta: 'Тест · 4 вопроса' },
    { id: 'M13', cat: 'tech', type: 'article', icon: '⚡', title: 'ЭЭО: подготовка и износ электродов', meta: 'Регламент · 5 мин' },
    { id: 'M14', cat: 'hr', type: 'article', icon: '🖥', title: 'Охрана труда для офисных сотрудников', meta: 'Инструкция · 4 мин' },
    { id: 'M15', cat: 'equip', type: 'article', icon: '🚨', title: 'Алармы Fanuc: частые коды и решения', meta: 'Справочник · 6 мин' },
    { id: 'M16', cat: 'equip', type: 'article', icon: '🚨', title: 'Алармы Siemens SINUMERIK и Heidenhain', meta: 'Справочник · 6 мин' },
    { id: 'M17', cat: 'tech', type: 'article', icon: '📦', title: 'Металлопрокат: сортамент, масса, ГОСТ', meta: 'Справочник · 7 мин' },
    { id: 'M18', cat: 'tech', type: 'article', icon: '🏷', title: 'Децимальные номера и маркировка (ГОСТ 2.201)', meta: 'Справочник · 5 мин' }
  ];

  var ARTICLES = {
    M1: {
      cat: 'ТБ', title: 'Инструкция по охране труда при работе на ЧПУ', meta: 'Обязательно для операторов · обновлено 12.09',
      body: '<div class="callout-block info"><h4>1. Общие требования</h4><p>К работе допускаются лица не моложе 18 лет, прошедшие обучение и инструктаж по охране труда, имеющие удостоверение.</p></div>' +
        '<div class="callout-block warn"><h4>2. Средства индивидуальной защиты</h4><p>Обязательны: защитные очки, спецобувь, headphones; при работе с СОЖ — перчатки.</p></div>' +
        '<div class="callout-block info"><h4>3. Перед началом работы</h4><p>Проверить заземление, целостность кабелей, работу аварийной кнопки, отсутствие посторонних предметов в рабочей зоне.</p></div>' +
        '<div class="callout-block info"><h4>4. Во время работы</h4><p>Не отвлекаться, не открывать защитные двери, не измерять деталь при вращении шпинделя.</p></div>' +
        '<div class="callout-block warn"><h4>5. Аварийные ситуации</h4><p>Нажать аварийный стоп, сообщить мастеру, не устранять неисправность самостоятельно.</p></div>'
    },
    M3: {
      cat: 'Техпроцессы', title: 'Типовой техпроцесс фрезеровки корпусных деталей', meta: 'Регламент производства · обновлено 02.08',
      body: '<div class="callout-block info"><h4>Этап 1. Базирование</h4><p>Установить заготовку по черновым базам, выверить параллельность в пределах 0,05 мм.</p></div>' +
        '<div class="callout-block info"><h4>Этап 2. Черновая обработка</h4><p>Снять основной припуск, оставив 0,5–1 мм на чистовую обработку.</p></div>' +
        '<div class="callout-block info"><h4>Этап 3. Чистовая обработка</h4><p>Обеспечить точность ±0,03 мм и шероховатость Ra 1,6.</p></div>' +
        '<div class="callout-block warn"><h4>Контроль</h4><p>Промежуточный контроль КИМ, фиксация в маршрутной карте.</p></div>'
    },
    M6: {
      cat: 'Оборудование', title: 'Ежедневное ТО станков: чек-лист оператора', meta: 'Регламент · обновлено 18.09',
      body: '<div class="callout-block info"><h4>Начало смены</h4><p>Проверить уровень масла и СОЖ, давление воздуха, чистоту направляющих.</p></div>' +
        '<div class="callout-block info"><h4>В течение смены</h4><p>Следить за стружкоудалением, не допускать перегрева шпинделя.</p></div>' +
        '<div class="callout-block warn"><h4>Конец смены</h4><p>Очистить рабочую зону, смазать направляющие, отключить питание.</p></div>'
    },
    M4: {
      cat: 'HR', title: 'Памятка нового сотрудника: первые 30 дней', meta: 'Новое · отдел персонала',
      body: '<div class="callout-block info"><h4>Неделя 1</h4><p>Инструктажи по ТБ, знакомство с цехом, получение СИЗ и пропуска.</p></div>' +
        '<div class="callout-block info"><h4>Неделя 2</h4><p>Работа под наставником, изучение регламентов в базе знаний.</p></div>' +
        '<div class="callout-block info"><h4>Недели 3–4</h4><p>Самостоятельные операции под контролем, промежуточная аттестация.</p></div>'
    },
    M7: {
      cat: 'ТБ', title: 'Пожарная безопасность: эвакуация из цеха', meta: 'Обязательно · обновлено 20.09',
      body: '<div class="callout-block info"><h4>Порядок действий при пожаре</h4><p>Сообщить по тел. 101 или мастеру, включить оповещение, начать эвакуацию по схеме.</p></div>' +
        '<div class="callout-block warn"><h4>Запрещено</h4><p>Пользоваться лифтами, тушить водой электрооборудование под напряжением, возвращаться за вещами.</p></div>' +
        '<div class="callout-block info"><h4>Эвакуационные выходы</h4><p>Основной — через центральные ворота, резервный — со стороны склада. Точка сбора — площадка у проходной.</p></div>'
    },
    M8: {
      cat: 'Оборудование', title: 'СОЖ: настройка и контроль концентрации', meta: 'Регламент · обновлено 05.09',
      body: '<div class="callout-block info"><h4>Концентрация</h4><p>Поддерживать 5–8% по рефрактометру. Проверка — в начале каждой смены.</p></div>' +
        '<div class="callout-block warn"><h4>Признаки износа</h4><p>Запах, изменение цвета, пена, рост бактерий — заменить эмульсию полностью.</p></div>' +
        '<div class="callout-block info"><h4>Замена</h4><p>Полная замена не реже 1 раза в квартал с промывкой бака.</p></div>'
    },
    M9: {
      cat: 'Техпроцессы', title: 'Термообработка: закалка и отпуск деталей', meta: 'Регламент · обновлено 28.08',
      body: '<div class="callout-block info"><h4>Закалка</h4><p>Нагрев до температуры аустенизации, выдержка, охлаждение в масле/вакууме.</p></div>' +
        '<div class="callout-block info"><h4>Отпуск</h4><p>Нагрев до 180–600 °C в зависимости от требуемой твёрдости, выдержка 1–2 ч.</p></div>' +
        '<div class="callout-block warn"><h4>Контроль</h4><p>Замер твёрдости не менее чем в 3 точках, фиксация в журнале термообработки.</p></div>'
    },
    M10: {
      cat: 'HR', title: 'Правила внутреннего трудового распорядка', meta: 'Документ · отдел персонала',
      body: '<div class="callout-block info"><h4>Режим работы</h4><p>Смены 8:00–17:00 и 16:00–24:00, обед 45 мин. Пропуск обязателен.</p></div>' +
        '<div class="callout-block info"><h4>Оплата труда</h4><p>Выплата 2 раза в месяц: аванс 25-го, окончательный расчёт 10-го.</p></div>' +
        '<div class="callout-block warn"><h4>Дисциплина</h4><p>Опоздания и отсутствие фиксируются; при опоздании предупредить руководителя заранее.</p></div>'
    },
    M13: {
      cat: 'Техпроцессы', title: 'ЭЭО: подготовка и износ электродов', meta: 'Регламент · обновлено 16.09',
      body: '<div class="callout-block info"><h4>Изготовление электрода</h4><p>Материал — медь или графит, припуск на износ 0,05–0,1 мм.</p></div>' +
        '<div class="callout-block warn"><h4>Износ</h4><p>Контролировать износ по длине; при превышении 0,2 мм электрод заменить.</p></div>' +
        '<div class="callout-block info"><h4>Режимы</h4><p>Ток и скважность подбирать по площади обработки и требуемой шероховатости.</p></div>'
    },
    M14: {
      cat: 'HR', title: 'Охрана труда для офисных сотрудников', meta: 'Инструкция · обновлено 01.09',
      body: '<div class="callout-block info"><h4>Рабочее место</h4><p>Освещение, эргономика кресла, перерывы при работе за ПК 10 мин каждый час.</p></div>' +
        '<div class="callout-block info"><h4>Электробезопасность</h4><p>Не перегружать розетки, не использовать повреждённые кабели.</p></div>' +
        '<div class="callout-block warn"><h4>Эвакуация</h4><p>Знать расположение выходов и огнетушителей на этаже.</p></div>'
    },
    M15: {
      cat: 'Оборудование', title: 'Алармы Fanuc: частые коды и решения', meta: 'Справочник оператора · обновлено 02.10',
      body: '<div class="callout-block info"><h4>OT — перегрев</h4><p>Проверить вентиляцию шкафа и фильтры, дать остыть, проверить нагрузку.</p></div>' +
        '<div class="callout-block warn"><h4>SV — сервопривод</h4><p>Проверить питание привода, разъёмы обратной связи, устранить механическое заклинивание.</p></div>' +
        '<div class="callout-block info"><h4>PS — питание</h4><p>Проверить предохранители и напряжение вводов, перезапустить стойку.</p></div>' +
        '<div class="callout-block warn"><h4>1010 / 1013</h4><p>Требуется повторный референс осей после аварии/сбоя.</p></div>' +
        '<div class="callout-block info"><h4>ALM-412 (пример)</h4><p>Низкий уровень рабочей жидкости — долить, проверить датчик уровня.</p></div>'
    },
    M16: {
      cat: 'Оборудование', title: 'Алармы Siemens SINUMERIK и Heidenhain', meta: 'Справочник оператора · обновлено 02.10',
      body: '<div class="callout-block info"><h4>Siemens 700000-серия</h4><p>Аппаратные ошибки: проверить питание модулей, связь PROFIBUS/PROFINET.</p></div>' +
        '<div class="callout-block warn"><h4>Heidenhain «Control voltage missing»</h4><p>Отсутствует напряжение управления — проверить цепь и предохранители.</p></div>' +
        '<div class="callout-block info"><h4>Переполнение буфера УП</h4><p>Уменьшить блок или использовать DNC-режим (B18).</p></div>' +
        '<div class="callout-block warn"><h4>Ошибка корректора</h4><p>Проверить таблицу корректоров T/H/D (B19), значения в пределах допуска.</p></div>'
    },
    M17: {
      cat: 'Техпроцессы', title: 'Металлопрокат: сортамент, масса, ГОСТ', meta: 'Справочник · обновлено 02.10',
      body: '<div class="callout-block info"><h4>Виды проката</h4><p>Круг, квадрат, шестигранник, полоса, лист, труба. Масса зависит от плотности материала (сталь ≈ 7850 кг/м³).</p></div>' +
        '<div class="callout-block info"><h4>Формулы массы</h4><p>Круг: m = π/4 · d² · ρ. Квадрат: m = a² · ρ. Шестигранник: m = 0,866 · a² · ρ. Лист: m = w · h · t · ρ.</p></div>' +
        '<div class="callout-block warn"><h4>ГОСТ</h4><p>Сортовой прокат — ГОСТ 1050; инструментальная сталь — ГОСТ 5950; нержавеющая — ГОСТ 5632. Расчёт — в модуле B34.</p></div>'
    },
    M18: {
      cat: 'Техпроцессы', title: 'Децимальные номера и маркировка (ГОСТ 2.201)', meta: 'Справочник · обновлено 02.10',
      body: '<div class="callout-block info"><h4>Структура</h4><p>Децимальный номер: код организации · классификационная характеристика (6) · порядковый номер (3) · код документа (2).</p></div>' +
        '<div class="callout-block info"><h4>Маркировка</h4><p>Ярлык содержит номер, наименование, тип и QR для прослеживаемости. Генерация — в модуле B32.</p></div>' +
        '<div class="callout-block warn"><h4>Связь</h4><p>QR ведёт к цифровому паспорту изделия (B6) и базе КД (B30).</p></div>'
    }
  };

  var VIDEOS = {
    M2: { title: 'Запуск и настройка фрезерного станка DMG', meta: 'Видеокурс · 12 мин',
      chapters: ['00:00 Введение', '01:20 Включение и референс', '04:10 Установка инструмента', '07:30 Пробный прогон', '10:15 Типовые ошибки'] },
    M11: { title: 'Видеоинструктаж: безопасная работа на станке', meta: 'Видео · 9 мин',
      chapters: ['00:00 Введение и цели', '01:00 СИЗ и проверка станка', '03:40 Рабочая зона и аварийный стоп', '06:20 Действия при аварии', '08:10 Итоги'] }
  };

  var TESTS = {
    M5: {
      name: 'Электробезопасность на производстве',
      questions: [
        { q: 'Что нужно сделать перед началом работы со станком?', a: ['Проверить заземление и кабели', 'Сразу включить шпиндель', 'Убрать защитные двери'], c: 0 },
        { q: 'Действие при возгорании электрощита?', a: ['Залить водой', 'Обесточить и применить углекислотный огнетушитель', 'Позвонить мастеру и ждать'], c: 1 },
        { q: 'Можно ли устранять неисправность станка самостоятельно?', a: ['Да, если быстро', 'Только с разрешения мастера', 'Нет, только сервисная служба'], c: 2 },
        { q: 'Периодичность инструктажа по электробезопасности?', a: ['Раз в год', 'Раз в квартал', 'Только при приёме на работу'], c: 1 },
        { q: 'Что означает маркировка заземления?', a: ['Красный треугольник', 'Жёлто-зелёный провод', 'Синий круг'], c: 1 }
      ]
    },
    M12: {
      name: 'Ежедневное ТО оборудования',
      questions: [
        { q: 'Когда проверяют уровень масла и СОЖ?', a: ['В начале смены', 'В конце месяца', 'Раз в год'], c: 0 },
        { q: 'Концентрация СОЖ по рефрактометру должна быть?', a: ['1–2%', '5–8%', '15–20%'], c: 1 },
        { q: 'Что делать при перегреве шпинделя?', a: ['Продолжить работу', 'Остановить станок и сообщить мастеру', 'Добавить масло'], c: 1 },
        { q: 'Что входит в конец смены?', a: ['Очистка зоны и смазка направляющих', 'Разборка станка', 'Замена шпинделя'], c: 0 }
      ]
    }
  };

  var cat = 'all', query = '', currentMat = null;
  var testState = { idx: 0, answers: [], matId: null, done: false };

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Каталог ---------- */
  $('#quick').innerHTML = QUICK.map(function (q) {
    return '<div class="qa" data-c="' + q.c + '"><div style="font-size:1.3rem;">' + q.icon + '</div><div class="q-n">' + q.n + '</div><div class="q-l">' + q.l + '</div></div>';
  }).join('');
  $('#quick').addEventListener('click', function (e) {
    var q = e.target.closest('.qa'); if (!q) return;
    cat = q.dataset.c;
    $$('#tabs .chip').forEach(function (x) { x.classList.toggle('active', x.dataset.c === cat); });
    renderArticles();
  });

  $('#tabs').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    cat = c.dataset.c; renderArticles();
  });
  $('#search').addEventListener('input', function () { query = this.value.trim().toLowerCase(); renderArticles(); });

  function renderArticles() {
    var list = MATERIALS.filter(function (m) {
      if (cat !== 'all' && m.cat !== cat) return false;
      if (query && (m.title + ' ' + m.meta).toLowerCase().indexOf(query) < 0) return false;
      return true;
    });
    $('#artCount').textContent = list.length + ' материалов';
    if (!list.length) { $('#articles').innerHTML = '<div class="callout info"><span class="ci">🔍</span><div>Материалы не найдены.</div></div>'; return; }
    $('#articles').innerHTML = list.map(function (m) {
      var badge = m.type === 'video' ? '<span class="badge info">Видео</span>' : m.type === 'test' ? '<span class="badge warning">Тест</span>' : m.type === 'new' ? '<span class="badge success">Новое</span>' : '<span class="badge neutral">Статья</span>';
      return '<div class="art-item" data-id="' + m.id + '"><div class="ai">' + m.icon + '</div><div class="grow"><div style="font-weight:600;font-size:.84rem;">' + m.title + '</div><div class="faint" style="font-size:.7rem;">' + m.meta + '</div></div>' + badge + '</div>';
    }).join('');
    $$('#articles .art-item').forEach(function (el) { el.addEventListener('click', function () { openMaterial(el.dataset.id); }); });
  }

  function openMaterial(id) {
    var m = MATERIALS.find(function (x) { return x.id === id; }); if (!m) return;
    currentMat = m;
    if (m.type === 'video') openVideo(id);
    else if (m.type === 'test') openTest(id);
    else openArticle(id);
  }

  /* ---------- Статья ---------- */
  function openArticle(id) {
    var a = ARTICLES[id];
    $('#aCat').textContent = a.cat;
    $('#aTitle').textContent = a.title;
    $('#aMeta').textContent = a.meta;
    $('#aBody').innerHTML = a.body;
    screens.go('s2');
  }
  $('#aDone').addEventListener('click', function () { App.toast('Материал отмечен как изученный'); screens.back(); });

  /* ---------- Видео ---------- */
  function openVideo(id) {
    var v = VIDEOS[id];
    $('#vTitle').textContent = v.title;
    $('#vMeta').textContent = v.meta;
    $('#vChapters').innerHTML = v.chapters.map(function (c) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span>' + c + '</span><span style="color:var(--accent-600);">▶</span></div>'; }).join('');
    screens.go('s3');
  }
  $('#playBtn').addEventListener('click', function () { App.toast('Демо: воспроизведение видео'); this.textContent = '⏸'; });

  /* ---------- Тест ---------- */
  function openTest(id) {
    testState = { idx: 0, answers: new Array(TESTS[id].questions.length).fill(null), matId: id, done: false };
    $('#tName').textContent = TESTS[id].name;
    renderTest();
    screens.go('s4');
  }
  function renderTest() {
    var t = TESTS[testState.matId], q = t.questions[testState.idx];
    $('#tCounter').textContent = (testState.idx + 1) + '/' + t.questions.length;
    $('#dots').innerHTML = t.questions.map(function (_, i) { return '<span class="dot ' + (i < testState.idx ? 'done' : i === testState.idx ? 'cur' : '') + '"></span>'; }).join('');
    $('#tQuestion').textContent = q.q;
    var sel = testState.answers[testState.idx];
    $('#answers').innerHTML = q.a.map(function (a, i) {
      return '<label class="answer' + (sel === i ? ' selected' : '') + '" data-i="' + i + '">' + a + '</label>';
    }).join('');
    $('#tPrev').disabled = testState.idx === 0;
    $('#tNext').textContent = testState.idx === t.questions.length - 1 ? 'Завершить' : 'Далее →';
  }
  $('#answers').addEventListener('click', function (e) {
    var el = e.target.closest('.answer'); if (!el) return;
    testState.answers[testState.idx] = parseInt(el.dataset.i, 10);
    $$('.answer', this).forEach(function (x) { x.classList.toggle('selected', x === el); });
  });
  $('#tPrev').addEventListener('click', function () { if (testState.idx > 0) { testState.idx--; renderTest(); } });
  $('#tNext').addEventListener('click', function () {
    var t = TESTS[testState.matId];
    if (testState.answers[testState.idx] == null) { App.toast('Выберите ответ'); return; }
    if (testState.idx < t.questions.length - 1) { testState.idx++; renderTest(); }
    else finishTest();
  });
  function finishTest() {
    var t = TESTS[testState.matId], correct = 0;
    t.questions.forEach(function (q, i) { if (testState.answers[i] === q.c) correct++; });
    var pct = Math.round(correct / t.questions.length * 100);
    var passed = pct >= 80;
    $('#tResultHero').innerHTML =
      '<div class="check" style="background:' + (passed ? 'var(--accent-grad)' : 'linear-gradient(135deg,#d97706,#b45309)') + '">' + (passed ? '✓' : '!') + '</div>' +
      '<h2>' + (passed ? 'Тест пройден!' : 'Попробуйте ещё раз') + '</h2><p>' + correct + ' из ' + t.questions.length + ' правильных ответов · ' + pct + '%</p>';
    $('#tSummary').innerHTML = t.questions.map(function (q, i) {
      var ok = testState.answers[i] === q.c;
      return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><span>' + (ok ? '✅' : '❌') + ' Вопрос ' + (i + 1) + '</span><b class="' + (ok ? '' : '') + '" style="color:' + (ok ? 'var(--success)' : 'var(--danger)') + ';">' + (ok ? 'верно' : 'неверно') + '</b></div>';
    }).join('');
    App.Store.set('testResults', (App.Store.get('testResults', [])).concat([{ test: t.name, pct: pct, passed: passed, created: App.today() }]));
    screens.go('s5');
  }
  $('#tRetake').addEventListener('click', function () { openTest(testState.matId); });
  $('#tBackCat').addEventListener('click', function () { screens.replace('s1'); });

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderArticles();
})();
