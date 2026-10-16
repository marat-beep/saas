/* ============================================================
   tools/gen-site.js — генератор рекламного сайта (site/).
   Источник модулей: assets/js/catalog.js (единый источник правды).
   Контент: tools/site-data.js (групповые шаблоны + точечные расширения).
   Создаёт:
     site/m/<id>.html       — лендинг каждого модуля;
     site/modules.html      — каталог модулей по контурам;
     site/for-managers.html — страница «Руководителю».
   Запуск: node tools/gen-site.js
   ============================================================ */
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const SITE = path.join(root, 'site');
const D = require(path.join(root, 'tools', 'site-data.js'));

/* ---------- каталог ---------- */
function loadCatalog() {
  const code = fs.readFileSync(path.join(root, 'assets', 'js', 'catalog.js'), 'utf8');
  const fn = new Function('window', 'var window = {};\n' + code + '\nreturn window.AppCatalog;');
  return fn({});
}
const C = loadCatalog();
const ALL = (C.apps || []).filter(a => a.audience !== 'developer');
const TITLE = {}; ALL.forEach(a => { TITLE[a.id] = a.title; });
const FEATURED = D.FEATURED;

const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/* ---------- объединение каталога и контента ---------- */
function build(a) {
  const o = D.OVERRIDES[a.id] || {};
  const g = a.group;
  const ui = D.GROUP_UI[g] || {};
  return {
    id: a.id, icon: o.icon || a.icon || '▫', title: a.title || o.title, group: g,
    sub: o.sub || a.desc || a.purpose || '',
    get: o.get || a.purpose || a.desc || '',
    funcs: o.funcs || (a.features || []).slice(0, 8),
    replaces: o.replaces || (D.GROUP_REPLACES[g] || []).map(x => ({ b: x[0], a: x[1] })),
    problems: o.problems || D.GROUP_PROBLEMS[g] || [],
    impl: o.impl || D.GROUP_IMPL[g] || [],
    kpi: o.kpi || ui.kpi || [], cols: o.cols || ui.cols || [], rows: o.rows || ui.rows || [],
    connects: (a.connects || []).slice(0, 8), in_: a.in_, out: a.out,
    featured: FEATURED.indexOf(a.id) >= 0
  };
}
const MODELS = ALL.map(build);

/* ---------- каркас ---------- */
function head(title, desc, base) {
  return '<!DOCTYPE html>\n<html lang="ru">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' +
    '<title>' + esc(title) + '</title>\n<meta name="description" content="' + esc(desc) + '">\n' +
    '<link rel="stylesheet" href="' + base + 'promo.css">\n</head>\n<body>\n';
}
function nav(base, active) {
  const on = (k) => active === k ? ' style="color:var(--accent-700)"' : '';
  return '<header class="nav"><div class="wrap nav-in">' +
    '<a class="brand" href="' + base + 'index.html"><span class="lg">⚙</span> 3DMP Service</a>' +
    '<nav class="nav-links">' +
    '<a href="' + base + 'modules.html"' + on('modules') + '>Модули</a>' +
    '<a href="' + base + 'for-managers.html"' + on('managers') + '>Руководителю</a>' +
    '<a href="' + base + 'about.html">О компании</a>' +
    '<a href="' + base + 'contacts.html">Контакты</a>' +
    '</nav><div class="nav-cta"><a class="btn ghost sm" href="' + base + '../index.html">Войти в сервис</a><a class="btn sm" href="' + base + 'contacts.html">Связаться</a></div>' +
    '</div></header>\n';
}
function foot(base, note) {
  return '<footer class="foot"><div class="wrap foot-in"><div>3DMP Service · ООО «3Д Металлообработка Пресс» · <a href="tel:+74991977881">+7 499 197 78 81</a> · <a href="mailto:info@3dmp.ru">info@3dmp.ru</a></div>' +
    '<div>3DMP Service · ' + esc(note) + ' · <a href="' + base + 'about.html">О компании</a> · <a href="' + base + 'contacts.html">Контакты</a> · <a href="' + base + '../index.html">Рабочий сервис</a></div></div></footer>\n</body>\n</html>\n';
}
function cta(base, title, text) {
  return '<section class="band alt" id="demo"><div class="wrap"><div class="cta">' +
    '<div><h2>' + esc(title) + '</h2><p>' + esc(text) + '</p></div>' +
    '<div class="nav-cta"><a class="btn" href="' + base + 'contacts.html">Связаться</a><a class="btn ghost" href="' + base + '../index.html">Открыть сервис</a></div>' +
    '</div></div></section>\n';
}

/* ---------- макет интерфейса ---------- */
function mock(m) {
  const kpis = (m.kpi || []).map(k => '<div class="kpi"><small>' + esc(k.l) + '</small><b>' + esc(k.v) + '</b></div>').join('');
  const th = (m.cols || []).map(c => '<th>' + esc(c) + '</th>').join('');
  const tr = (m.rows || []).map(r => '<tr>' + r.map((c, i) => '<td>' + (i === 0 ? '<b>' + esc(c) + '</b>' : esc(c)) + '</td>').join('') + '</tr>').join('');
  const table = (m.cols && m.cols.length) ? '<table><tr>' + th + '</tr>' + tr + '</table>' : '';
  return '<div class="mock">' +
    '<div class="top"><span class="mlg">⚙</span> 3DMP Service <span class="msearch">Поиск по системе…</span><span class="mright">🔔 · <span class="mava">А</span> admin</span></div>' +
    '<div class="sub"><span>Хаб</span> › <span>' + esc(D.GROUPS[m.group] || '') + '</span> › <span class="tb on">' + esc(m.title) + '</span></div>' +
    '<div class="mh"><span class="mi">' + esc(m.icon) + '</span><span><b>' + esc(m.title) + '</b><small>' + esc(m.sub) + '</small></span></div>' +
    '<div class="bar"><span class="find">Поиск…</span><span class="pill on">Все</span><span class="pill">Активные</span><span class="abtn pri">＋ Создать</span><span class="abtn">Экспорт</span></div>' +
    '<div class="body">' + (kpis ? '<div class="kpis" style="grid-template-columns:repeat(' + Math.min(4, (m.kpi || []).length) + ',1fr)">' + kpis + '</div>' : '') + table + '</div>' +
    '</div>';
}

/* ---------- страница модуля ---------- */
function modulePage(m) {
  const base = '../';
  const funcs = (m.funcs || []).map(f => '<li>' + esc(f) + '</li>').join('');
  const repl = (m.replaces || []).map(r => '<div class="rcard"><div class="before">' + esc(r.b) + '</div><div class="after">' + esc(r.a) + '</div></div>').join('');
  const probs = (m.problems || []).map(p => '<li>' + esc(p) + '</li>').join('');
  const impl = (m.impl || []).map(i => '<span>' + esc(i) + '</span>').join('');
  const kpiBig = (m.kpi || []).map(k => '<div class="bk"><b>' + esc(k.v) + '</b><small>' + esc(k.l) + '</small></div>').join('');
  const conn = (m.connects || []).map(id => '<span class="tag grey">' + esc(TITLE[id] || id) + '</span>').join('');

  const body =
    '<div class="wrap"><nav class="crumbs"><a href="' + base + 'index.html">Главная</a> / <a href="' + base + 'modules.html">Модули</a> / ' + esc(m.title) + '</nav>' +
    '<div class="mhead"><span class="mh-ic">' + esc(m.icon) + '</span><div><h1>' + esc(m.title) + '</h1><div class="mh-sub">' + esc(m.sub) + '</div></div></div>' +
    '<div class="meta-row"><span class="tag">Контур: ' + esc(D.GROUPS[m.group] || '') + '</span><span class="tag grey">Облако · роли · уведомления</span></div></div>' +

    '<section class="band"><div class="wrap"><div class="sec-head"><div class="eyebrow">Что вы получаете</div><h2>Результат для компании</h2></div>' +
    '<div class="vcard"><span class="vi">' + esc(m.icon) + '</span><div><p style="font-size:1rem;color:var(--ink)">' + esc(m.get) + '</p></div></div></div></section>' +

    '<section class="band alt"><div class="wrap"><div class="sec-head"><div class="eyebrow">Возможности</div><h2>Какие функции выполняются</h2></div>' +
    '<div class="card"><ul class="ticks">' + funcs + '</ul></div></div></section>' +

    '<section class="band"><div class="wrap"><div class="sec-head"><div class="eyebrow">Интерфейс</div><h2>Как это выглядит</h2><p>Рабочий экран модуля (нефункциональный макет).</p></div>' +
    mock(m) + '<div class="caption">Нефункциональный макет — реальные экраны доступны после входа в сервис.</div></div></section>' +

    '<section class="band alt"><div class="wrap"><div class="sec-head"><div class="eyebrow">Эффект</div><h2>Где заменяет ручной труд</h2></div>' +
    '<div class="replace">' + repl + '</div></div></section>' +

    '<section class="band"><div class="wrap"><div class="grid2"><div><div class="eyebrow">Зачем это нужно</div><h2 style="margin:8px 0 12px">Какие проблемы решает</h2>' +
    '<ul class="problems">' + probs + '</ul></div>' +
    '<div class="card"><div class="ic">⚙️</div><h3>Как реализовано</h3><p>Модуль работает в облачном сервисе: данные хранятся в защищённой базе (Postgres), доступ — по ролям, обмен — через внутренние функции. Отдельной установки и обслуживания не требуется.</p>' +
    '<div class="impl">' + impl + '</div>' +
    (conn ? '<div class="meta-row" style="margin-top:14px">' + conn + '</div>' : '') + '</div></div></div></section>' +

    '<section class="band alt"><div class="wrap"><div class="sec-head"><div class="eyebrow">Для руководителя</div><h2>Показатели на данных</h2><p>Ключевые цифры модуля видны руководителю без ручных сводок.</p></div>' +
    '<div class="big-kpi">' + kpiBig + '</div></div></section>' +

    cta(base, 'Покажем «' + m.title + '» на ваших данных', 'Разберём процесс и покажем, как модуль снимает ручную работу и риски.');

  return head(m.title + ' — 3DMP Service', m.sub, base) + nav(base, '') + body + foot(base, 'Модуль «' + m.title + '»');
}

/* ---------- каталог ---------- */
function modulesPage() {
  const base = '';
  let dir = '';
  D.GROUP_ORDER.forEach(g => {
    const items = MODELS.filter(m => m.group === g);
    if (!items.length) return;
    dir += '<div class="grp-title">' + esc(D.GROUPS[g]) + ' · ' + items.length + '</div><div class="dir">';
    dir += items.map(m => '<a class="ditem" href="' + (m.featured ? m.id + '.html' : 'm/' + m.id + '.html') + '"><span class="mi">' + esc(m.icon) + '</span><span><b>' + esc(m.title) + '</b><small>' + esc(m.sub) + '</small></span><span class="go">→</span></a>').join('');
    dir += '</div>';
  });
  const rest = MODELS.filter(m => D.GROUP_ORDER.indexOf(m.group) < 0);
  if (rest.length) dir += '<div class="grp-title">Прочее · ' + rest.length + '</div><div class="dir">' + rest.map(m => '<a class="ditem" href="m/' + m.id + '.html"><span class="mi">' + esc(m.icon) + '</span><span><b>' + esc(m.title) + '</b><small>' + esc(m.sub) + '</small></span><span class="go">→</span></a>').join('') + '</div>';

  const body = '<div class="wrap"><nav class="crumbs"><a href="index.html">Главная</a> / Модули</nav>' +
    '<div class="mhead"><span class="mh-ic">🧩</span><div><h1>Модули системы</h1><div class="mh-sub">Все модули 3DMP Service по контурам предприятия. Откройте модуль — увидите описание, функции, эффект и показатели.</div></div></div>' +
    '<div class="meta-row" style="margin-bottom:8px"><span class="tag">' + MODELS.length + ' модулей</span><span class="tag grey">9 контуров</span><span class="tag grey">единая база данных</span></div></div>' +
    '<section class="band"><div class="wrap">' + dir + '</div></section>' +
    cta(base, 'Не нашли нужный модуль?', 'В сервисе ' + MODELS.length + ' модулей — расскажем и покажем под ваш процесс.');
  return head('Модули — 3DMP Service', 'Каталог модулей системы 3DMP Service по контурам предприятия.', base) + nav(base, 'modules') + body + foot(base, 'Каталог модулей');
}

/* ---------- «Руководителю» ---------- */
function managersPage() {
  const base = '';
  const globalKpi = [
    { l: 'Выручка под контролем', v: '9,4 млн ₽/мес' }, { l: 'Загрузка цеха', v: '84%' },
    { l: 'Средняя маржа заказов', v: '28%' }, { l: 'Доля брака', v: '0,7%' }
  ].map(k => '<div class="bk"><b>' + esc(k.v) + '</b><small>' + esc(k.l) + '</small></div>').join('');
  const gain = [
    ['📈', 'Одна картина предприятия', 'Показатели по продажам, производству, качеству и деньгам — из единой базы, без ручных сводок и споров о цифрах.'],
    ['⏱', 'Решения быстрее', 'Просрочки, перегрузка центров и отклонения себестоимости видны сразу, а не в конце месяца.'],
    ['💸', 'Деньги под контролем', 'Маржа по каждому заказу, дебиторка с напоминаниями, план-факт себестоимости — потери не прячутся в общих цифрах.'],
    ['🔐', 'Управляемый доступ', 'Каждый видит только своё: роли, права по модулям, журнал действий — данные защищены.'],
    ['🧩', 'Без сложного внедрения', 'Облачный сервис, вход через браузер, работает на ПК и планшете; подключаем модулями, по шагам.'],
    ['🔌', 'Связь с внешними системами', 'Обмен с 1С, складом и оборудованием; сбор данных со станков (OPC-UA, DNC).']
  ].map(g => '<div class="vcard"><span class="vi">' + g[0] + '</span><div><b>' + esc(g[1]) + '</b><p>' + esc(g[2]) + '</p></div></div>').join('');
  const replaces = [
    ['Сводки для руководства', 'Отчёты собирают полдня в Excel', 'Живые дашборды по данным системы'],
    ['Планирование сроков', 'План на доске и в Excel', 'Гант, ёмкость и APS-солвер'],
    ['Контроль производства', 'Обход цеха и звонки', 'Канбан цеха в реальном времени'],
    ['Себестоимость заказа', 'Считают в конце месяца', 'План/факт и маржа онлайн'],
    ['Сбор данных со станков', 'Оператор отмечает вручную', 'Автосбор (OPC-UA, DNC, OEE)'],
    ['Контроль дебиторки', 'Ручной реестр и «напоминания»', 'AR/AP с aging и календарём']
  ].map(r => '<div class="rcard"><h4>' + esc(r[0]) + '</h4><div class="before">' + esc(r[1]) + '</div><div class="after">' + esc(r[2]) + '</div></div>').join('');
  const problems = [
    'Руководство видит устаревшие цифры и принимает решения «вслепую».',
    'Заказы незаметно уходят в минус: маржа всплывает только в конце месяца.',
    'Срывы сроков из-за перегрузки центров — узнают по факту.',
    'Брак и простои не видно в деньгах — нет рычагов для снижения потерь.',
    'Часть информации «в головах» и в мессенджерах — компания зависит от людей.',
    'Двойной ввод данных в разные программы и вечная проблема сверки.'
  ].map(p => '<li>' + esc(p) + '</li>').join('');
  const implChips = ['Облачная база Postgres', 'Доступ по ролям и RLS', 'Сессии-токены', 'Журнал аудита', 'Обмен через внутренние функции (RPC)', 'REST API и очередь интеграций', 'Уведомления', 'PWA (ПК и планшет)'].map(i => '<span>' + esc(i) + '</span>').join('');
  const TD = '<td style="padding:11px 14px;border-top:1px solid #eef2f7">';
  const rowsHtml = [
    ['Продажи и заказы', 'Конверсия КП → заказ, сумма заявок', 'Заявки, КП, CRM, документы'],
    ['Подготовка производства', 'Нормы и состав, время подготовки', 'Справочники, BOM, нормы, УП'],
    ['Производство', 'Загрузка центров, OEE, простои', 'Наряды, MES, планирование, IIoT'],
    ['Качество', 'Доля брака, потери ₽, CAPA', 'ОТК, СМК, сертификаты'],
    ['Экономика и финансы', 'Маржа, план-факт, дебиторка', 'Себестоимость, финансы, BI'],
    ['Персонал', 'ФОТ, компетенции, допуски', 'Кадры, компетенции, подбор']
  ].map(r => '<tr>' + TD + '<b>' + esc(r[0]) + '</b></td>' + TD + esc(r[1]) + '</td>' + TD + esc(r[2]) + '</td></tr>').join('');
  const steps = [
    ['Ядро и вход', 'Пользователи, роли, база справочников — основа для всех модулей.'],
    ['Продажи и заказы', 'Заявки, КП и документы: единый путь от обращения до оплаты.'],
    ['Производство', 'Наряды, планирование и MES — цех под контролем.'],
    ['Качество, экономика, персонал', 'Расширение контура: качество, деньги, кадры и данные для решений.']
  ].map(s => '<div class="step"><h4>' + esc(s[0]) + '</h4><p>' + esc(s[1]) + '</p></div>').join('');

  const body = '<div class="wrap"><nav class="crumbs"><a href="index.html">Главная</a> / Руководителю</nav>' +
    '<div class="mhead"><span class="mh-ic">🎯</span><div><h1>Руководителю</h1><div class="mh-sub">Что даёт система руководителю: единая картина предприятия, контроль денег и сроков, меньше ручной работы и зависимости от людей.</div></div></div></div>' +
    '<section class="band"><div class="wrap"><div class="sec-head"><div class="eyebrow">Эффект на данных</div><h2>Показатели, которые видит руководитель</h2><p>Цифры — пример по данным системы; в рабочем контуре отражают ваши фактические показатели.</p></div><div class="big-kpi">' + globalKpi + '</div></div></section>' +
    '<section class="band alt"><div class="wrap"><div class="sec-head"><div class="eyebrow">Что получаете</div><h2>Ценность для управления</h2></div><div class="valgrid">' + gain + '</div></div></section>' +
    '<section class="band"><div class="wrap"><div class="sec-head"><div class="eyebrow">Эффект</div><h2>Где система заменяет ручной труд</h2></div><div class="replace">' + replaces + '</div></div></section>' +
    '<section class="band alt"><div class="wrap"><div class="grid2"><div><div class="eyebrow">Проблемы бизнеса</div><h2 style="margin:8px 0 12px">Какие проблемы решает</h2><ul class="problems">' + problems + '</ul></div>' +
    '<div class="card"><div class="ic">☁️</div><h3>Как реализовано</h3><p>3DMP Service — облачный сервис для производственной компании: единая база данных, доступ по ролям, работа в браузере без установки и сложного внедрения.</p><div class="impl">' + implChips + '</div></div></div></div></section>' +
    '<section class="band"><div class="wrap"><div class="sec-head"><div class="eyebrow">Данные для решений</div><h2>Показатели по контурам</h2></div>' +
    '<div class="card" style="padding:0;overflow:hidden"><table style="width:100%;border-collapse:collapse;font-size:.86rem">' +
    '<tr style="background:#f8fafc;color:var(--muted)"><th style="text-align:left;padding:11px 14px">Контур</th><th style="text-align:left;padding:11px 14px">Ключевые показатели</th><th style="text-align:left;padding:11px 14px">Модули</th></tr>' + rowsHtml + '</table></div></div></section>' +
    '<section class="band alt"><div class="wrap"><div class="sec-head"><div class="eyebrow">Внедрение</div><h2>По шагам, без «большого взрыва»</h2></div><div class="steps">' + steps + '</div></div></section>' +
    cta(base, 'Обсудим задачи руководителя', 'Покажем, как система отвечает на ваши вопросы по срокам, деньгам и загрузке.');
  return head('Руководителю — 3DMP Service', 'Что даёт система руководителю: единая картина, контроль денег и сроков, меньше ручной работы.', base) + nav(base, 'managers') + body + foot(base, 'Руководителю');
}

/* ---------- запись ---------- */
function main() {
  const mdir = path.join(SITE, 'm');
  if (!fs.existsSync(mdir)) fs.mkdirSync(mdir, { recursive: true });
  /* чистка старых страниц модулей */
  fs.readdirSync(mdir).filter(f => /\.html$/.test(f)).forEach(f => fs.unlinkSync(path.join(mdir, f)));
  let n = 0;
  MODELS.forEach(m => { if (m.featured) return; fs.writeFileSync(path.join(mdir, m.id + '.html'), modulePage(m), 'utf8'); n++; });
  fs.writeFileSync(path.join(SITE, 'modules.html'), modulesPage(), 'utf8');
  fs.writeFileSync(path.join(SITE, 'for-managers.html'), managersPage(), 'utf8');
  console.log('gen-site: модулей в каталоге ' + MODELS.length + ', сгенерировано страниц ' + n);
}
main();
