/* ============================================================
   B5 · Портал вакансий и онбординга
   таб «Вакансии» + таб «Мой онбординг»
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var VACANCIES = [
    { id: 'V1', cat: 'prod', icon: '🪚', title: 'Оператор ЧПУ (фрезеровка)', salary: '90 000 – 140 000 ₽', badge: '🔥 Срочно', tags: ['Опыт 3+ года', 'Fanuc', 'Смены 5/2'], duties: ['Работа на 3–5-осевых станках', 'Наладка и контроль размеров', 'Ведение маршрутных карт'], req: ['Опыт от 3 лет', 'Чтение чертежей', 'Знание G-кода'], cond: ['Официальное трудоустройство', 'Обучение за счёт компании', 'Спецодежда и питание'], urgent: true },
    { id: 'V2', cat: 'eng', icon: '📐', title: 'Инженер-технолог', salary: '110 000 – 160 000 ₽', badge: '✨ Новая', tags: ['ВО', 'CAD/CAM', '5/2'], duties: ['Разработка техпроцессов', 'Проектирование оснастки', 'Нормирование операций'], req: ['ВО техническое', 'SolidWorks/CAM', 'Опыт от 2 лет'], cond: ['Гибридный формат', 'ДМС', 'Обучение'], urgent: false },
    { id: 'V3', cat: 'prod', icon: '⚙️', title: 'Наладчик станков', salary: '80 000 – 120 000 ₽', badge: 'Стандарт', tags: ['Опыт 2+ года', 'Смены'], duties: ['Наладка оборудования', 'Мелкий ремонт', 'Контроль качества партии'], req: ['Опыт от 2 лет', 'Знание механики'], cond: ['Полный соцпакет', 'Доплаты за смены'], urgent: false },
    { id: 'V4', cat: 'office', icon: '📊', title: 'Менеджер по закупкам', salary: '95 000 – 130 000 ₽', badge: 'Стандарт', tags: ['B2B', '1С', '5/2'], duties: ['Поиск поставщиков', 'Работа с договорами', 'Контроль поставок'], req: ['Опыт в закупках B2B', 'Знание 1С'], cond: ['Офис в Москве', 'ДМС', 'Обучение'], urgent: false },
    { id: 'V5', cat: 'eng', icon: '🧊', title: 'Конструктор пресс-форм', salary: '130 000 – 190 000 ₽', badge: '🔥 Срочно', tags: ['SolidWorks', 'Опыт 5+'], duties: ['Проектирование пресс-форм', 'Расчёт литников', 'Сопровождение производства'], req: ['Опыт проектирования форм', 'SolidWorks', 'Знание материалов'], cond: ['ДМС', 'Релокационный пакет', 'Премии по проектам'], urgent: true },
    { id: 'V6', cat: 'prod', icon: '🔬', title: 'Контролёр ОТК', salary: '75 000 – 105 000 ₽', badge: 'Стандарт', tags: ['КИМ', 'Внимательность'], duties: ['Измерения и контроль', 'Ведение протоколов', 'Работа с КИМ'], req: ['Опыт контроля', 'Чтение чертежей'], cond: ['Полный день', 'Обучение'], urgent: false },
    { id: 'V7', cat: 'office', icon: '💼', title: 'HR-специалист', salary: '85 000 – 115 000 ₽', badge: '✨ Новая', tags: ['Подбор', 'Онбординг'], duties: ['Подбор персонала', 'Адаптация новичков', 'Кадровое делопроизводство'], req: ['Опыт в HR от 2 лет', 'Знание ТК РФ'], cond: ['Офис', 'ДМС', 'Гибкое начало дня'], urgent: false },
    { id: 'V8', cat: 'eng', icon: '🛰', title: 'Инженер КИМ / метролог', salary: '100 000 – 145 000 ₽', badge: 'Стандарт', tags: ['Zeiss', 'ГДТ'], duties: ['Измерения на КИМ', 'Калибровка', 'Анализ отклонений'], req: ['Опыт работы с КИМ', 'Понимание GD&T'], cond: ['Обучение', 'ДМС'], urgent: false },
    { id: 'V9', cat: 'prod', icon: '⚡', title: 'Оператор электроэрозионного станка', salary: '95 000 – 135 000 ₽', badge: '✨ Новая', tags: ['ЭЭО', 'Опыт 2+'], duties: ['Работа на ЭЭО-станке', 'Изготовление электродов', 'Контроль размеров'], req: ['Опыт ЭЭО', 'Чтение чертежей'], cond: ['Официальное трудоустройство', 'Обучение'], urgent: false },
    { id: 'V10', cat: 'office', icon: '📞', title: 'Менеджер по работе с клиентами', salary: '90 000 – 125 000 ₽', badge: 'Стандарт', tags: ['B2B', 'CRM'], duties: ['Сопровождение заказов', 'Работа с клиентами', 'Подготовка КП'], req: ['Опыт в продажах B2B', 'CRM'], cond: ['Офис', 'ДМС', 'Премии'], urgent: false },
    { id: 'V11', cat: 'prod', icon: '🔦', title: 'Оператор лазерного комплекса', salary: '85 000 – 120 000 ₽', badge: '🔥 Срочно', tags: ['Лазер', 'Смены'], duties: ['Раскрой листа', 'Наладка программы', 'Контроль кромки'], req: ['Опыт на лазере', 'Знание металлов'], cond: ['Доплаты за смены', 'Спецодежда'], urgent: true },
    { id: 'V12', cat: 'eng', icon: '🧊', title: 'Инженер-программист ЧПУ (CAM)', salary: '120 000 – 170 000 ₽', badge: '✨ Новая', tags: ['CAM', 'Postprocessor'], duties: ['Разработка УП', 'Постпроцессоры', 'Оптимизация режимов'], req: ['Опыт CAM (Fusion/PowerMill)', 'Знание G-кода'], cond: ['Гибридный формат', 'ДМС', 'Обучение'], urgent: false }
  ];

  var ONBOARDING = [
    { t: 'Оформление документов', d: 'Отдел кадров, подписание договора' },
    { t: 'Инструктаж по ТБ', d: 'Вводный + первичный на рабочем месте' },
    { t: 'Получение СИЗ и пропуска', d: 'Спецодежда, обувь, электронный пропуск' },
    { t: 'Знакомство с командой', d: 'Представление в отделе и цехе' },
    { t: 'Изучение базы знаний', d: 'Регламенты и техпроцессы в B4' },
    { t: 'Обучение на рабочем месте', d: 'Работа с наставником' },
    { t: 'Промежуточная аттестация', d: 'Проверка знаний и допуск' },
    { t: 'План на 30 дней', d: 'Постановка целей с руководителем' }
  ];

  var filter = 'all', query = '', currentVac = null;
  var applied = App.Store.get('onboardingDone', [0, 1, 2]);

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Табы ---------- */
  $('#mainTabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('button', this).forEach(function (x) { x.classList.toggle('active', x === b); });
    var t = b.dataset.t;
    $('#tab-vac').classList.toggle('hidden', t !== 'vac');
    $('#tab-ob').classList.toggle('hidden', t !== 'ob');
    if (t === 'ob') renderOnboarding();
  });

  /* ---------- Вакансии ---------- */
  $('#vacFilters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderVacancies();
  });
  $('#search').addEventListener('input', function () { query = this.value.trim().toLowerCase(); renderVacancies(); });

  function renderVacancies() {
    var list = VACANCIES.filter(function (v) {
      if (filter === 'urgent' && !v.urgent) return false;
      if (['prod', 'eng', 'office'].indexOf(filter) >= 0 && v.cat !== filter) return false;
      if (query && (v.title + ' ' + v.tags.join(' ')).toLowerCase().indexOf(query) < 0) return false;
      return true;
    });
    $('#vacCount2').textContent = list.length;
    $('#vacList').innerHTML = list.length ? list.map(function (v) {
      return '<div class="vac-card" data-id="' + v.id + '"><div class="row between"><span class="badge ' + (v.urgent ? 'danger' : v.badge.indexOf('Новая') >= 0 ? 'success' : 'neutral') + '">' + v.badge + '</span><b style="font-size:.8rem;color:var(--accent-700);">' + v.salary + '</b></div><div style="display:flex;gap:10px;align-items:center;margin-top:8px;"><span style="font-size:1.3rem;">' + v.icon + '</span><div><div style="font-weight:700;font-size:.9rem;">' + v.title + '</div><div class="faint" style="font-size:.7rem;">' + v.tags.join(' · ') + '</div></div></div></div>';
    }).join('') : '<div class="callout info"><span class="ci">🔍</span><div>Вакансии не найдены.</div></div>';
    $$('#vacList .vac-card').forEach(function (el) { el.addEventListener('click', function () { openVacancy(el.dataset.id); }); });
  }

  function openVacancy(id) {
    currentVac = VACANCIES.find(function (v) { return v.id === id; });
    var v = currentVac;
    $('#vBadge').textContent = v.badge; $('#vBadge').className = 'badge ' + (v.urgent ? 'danger' : v.badge.indexOf('Новая') >= 0 ? 'success' : 'neutral');
    $('#vSalary').textContent = v.salary;
    $('#vTitle2').textContent = v.icon + ' ' + v.title;
    $('#vTags').innerHTML = v.tags.map(function (t) { return '<span class="tag">' + t + '</span>'; }).join('');
    $('#vDuties').innerHTML = v.duties.map(function (d) { return '<li>' + d + '</li>'; }).join('');
    $('#vReq').innerHTML = v.req.map(function (d) { return '<li>' + d + '</li>'; }).join('');
    $('#vCond').innerHTML = v.cond.map(function (d) { return '<div style="padding:4px 0;font-size:.82rem;">✅ ' + d + '</div>'; }).join('');
    screens.go('s2');
  }

  /* ---------- Отклик ---------- */
  $('#applyBtn').addEventListener('click', function () { $('#submitApply').disabled = true; screens.go('s3'); });
  ['fio', 'phone', 'email'].forEach(function (id) { $('#' + id).addEventListener('input', checkApply); });
  $('#cvZone').addEventListener('click', function () { this.dataset.cv = 'resume.pdf'; $('#cvLabel').textContent = '✓ resume.pdf'; checkApply(); });
  function checkApply() {
    var ok = $('#fio').value.trim() && $('#phone').value.trim() && $('#email').value.trim() && $('#cvZone').dataset.cv;
    $('#submitApply').disabled = !ok;
  }
  $('#submitApply').addEventListener('click', function () {
    var num = 'HR-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    App.Store.set('applications', (App.Store.get('applications', [])).concat([{ num: num, vacancy: currentVac.title, created: App.today() }]));
    $('#applyNum').textContent = num;
    $('#applySum').innerHTML =
      '<div class="row between"><span class="muted">Вакансия</span><b style="text-align:right;">' + currentVac.title + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Кандидат</span><b>' + $('#fio').value + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Статус</span><span class="badge warning">На рассмотрении</span></div>';
    screens.go('s4');
    App.toast('Отклик ' + num + ' отправлен');
  });

  /* ---------- Онбординг ---------- */
  function renderOnboarding() {
    var done = applied.length, pct = Math.round(done / ONBOARDING.length * 100);
    $('#obPct').textContent = pct + '%';
    $('#obBar').style.width = pct + '%';
    $('#obList').innerHTML = ONBOARDING.map(function (s, i) {
      var isDone = applied.indexOf(i) >= 0;
      return '<div class="ob-step' + (isDone ? ' done' : '') + '" data-i="' + i + '"><div class="n">' + (isDone ? '✓' : (i + 1)) + '</div><div class="grow"><div class="ob-t" style="font-weight:600;font-size:.84rem;">' + s.t + '</div><div class="faint" style="font-size:.72rem;">' + s.d + '</div></div></div>';
    }).join('');
    $$('#obList .ob-step').forEach(function (el) {
      el.addEventListener('click', function () {
        var i = parseInt(el.dataset.i, 10), k = applied.indexOf(i);
        if (k >= 0) applied.splice(k, 1); else applied.push(i);
        App.Store.set('onboardingDone', applied);
        renderOnboarding();
      });
    });
  }

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toVac').addEventListener('click', function () { screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderVacancies();
})();
