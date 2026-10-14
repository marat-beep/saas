/* ============================================================
   tools/proposals.js — «Предложения по изменениям» для дашборда готовности.
   Единственный источник правды для раздела дашборда (modules.html).
   Поля: id, area, prio (P1|P2|P3), title, problem, action, evidence, effort (S|M|L), status (open|done).
   Раздел рендерит tools/gen-modules-page.js.
   ============================================================ */
'use strict';

module.exports = [
  {
    id: 'PROP-01', area: 'UX', prio: 'P1', status: 'open', effort: 'M',
    title: 'Поиск и пустые состояния в списках',
    problem: '3 модуля со списками без поиска (economics, roles, terminal) и 15 модулей без явного пустого состояния (accounting, bi, elearning, guide, itsm, logistics, mes, modules, panel, platform, pmo, product, remarks, safety, whitelabel).',
    action: 'Добавить поиск и осмысленное пустое состояние (пустой список + подсказка «добавить») по стандарту MODULE_STANDARD §4. Приоритет — модули с таблицами.',
    evidence: 'docs/UX_REPORT.md (автоген tools/ux-check.ps1)'
  },
  {
    id: 'PROP-02', area: 'Каталог', prio: 'P1', status: 'done', effort: 'S',
    title: 'Заполнить audience у модулей',
    problem: '14 модулей каталога не имели поля audience — из-за этого хаб/фильтры не относили их к «пользовательским».',
    action: 'Проставлено audience: "user" для mdm, plm, edo, tasks, kedo, eam, safety, holding, projbudget, pmo, logistics, itsm, elearning, accounting. Каталог v10.52, CATALOG_V 128.',
    evidence: 'assets/js/catalog.js (v355)'
  },
  {
    id: 'PROP-03', area: 'Безопасность', prio: 'P1', status: 'open', effort: 'M',
    title: 'Харденинг RLS и грантов',
    problem: 'Ранее зафиксированы 2 пермиссивные INSERT-политики (tenders, profiles) и helper без явного grant (app_support_ticket_link_issue).',
    action: 'Пересмотреть WITH CHECK у INSERT-политик (роль/тенант), выдать/закрыть grant у helper по назначению. Проверить default-deny у app_*.',
    evidence: 'docs/BACKLOG.md (v278), tools/security-check.ps1 ✅'
  },
  {
    id: 'PROP-04', area: 'Производительность', prio: 'P2', status: 'open', effort: 'M',
    title: 'Пагинация и индексы горячих списков',
    problem: 'Большое число RPC-функций (≈1282) при отсутствии явной пагинации части крупных списков (orders, naryads, qc_measures, tasks, integration_log, sessions).',
    action: 'Добавить индексы по горячим фильтрам/сортировке и limit/offset (или keyset) для крупных списков; проверять планы запросов.',
    evidence: 'audit/checks/perf.json (F-0001)'
  },
  {
    id: 'PROP-05', area: 'API', prio: 'P2', status: 'open', effort: 'M',
    title: 'Разобрать RPC без вызова из UI',
    problem: '≈172 функции объявлены в БД и не вызываются из клиента — риск «мёртвой» поверхности и неясных контрактов.',
    action: 'Классифицировать: (а) backend/helper — задокументировать в API_SURFACE.md; (б) лишнее — закрыть grant/удалить; (в) недостающее UI — добавить вызов.',
    evidence: 'audit/checks/trace.json (F-0002)'
  },
  {
    id: 'PROP-06', area: 'Документация', prio: 'P2', status: 'open', effort: 'S',
    title: 'Консолидация планов и аудитов',
    problem: 'Дублирующие исторические документы (PLAN_UPDATE_V2…V5, PLAN_WAVES, UPDATE_PLAN, часть AUDIT_*) затрудняют навигацию; единый источник — BACKLOG.md.',
    action: 'Перенести историческое в docs/archive/ с коротким README-указателем; в корне docs оставить актуальные гайды и BACKLOG.',
    evidence: 'docs/'
  },
  {
    id: 'PROP-07', area: 'Документация', prio: 'P2', status: 'open', effort: 'S',
    title: 'Разгрузить журнал BACKLOG',
    problem: 'docs/BACKLOG.md разросся (≈249 КБ) — журнал §5 содержит сотни записей, поиск и чтение замедлены.',
    action: 'Вынести записи старше N версий в docs/BACKLOG_ARCHIVE.md, оставить в §5 последние ~40–50; ссылаться на архив.',
    evidence: 'docs/BACKLOG.md'
  },
  {
    id: 'PROP-08', area: 'Доступность', prio: 'P2', status: 'open', effort: 'M',
    title: 'aria-label для иконочных кнопок',
    problem: 'Тулбары редакторов и модулей используют только символы (↶ ↷ ✋ 🔗 …) — без текста скринридеру; часть кнопок без title.',
    action: 'Добавить aria-label (и title) всем кнопкам без текстового содержимого; проверить контраст и фокус.',
    evidence: 'apps/**/index.html, assets/js/*.js'
  },
  {
    id: 'PROP-09', area: 'Прототипы', prio: 'P3', status: 'open', effort: 'L',
    title: 'Довести 4 прототипа',
    problem: 'A5 «Аудит зрелости», A12 «АРМ», B36 «ИТ-инфраструктура», P12 «Технологический путь» перенесены в сервис лишь частично.',
    action: 'Спланировать доработку (диагностика/терминал-сервис/iiot/гид) или явно пометить как «вне периметра сервиса».',
    evidence: 'modules.html → «Прототипы → реализация»'
  },
  {
    id: 'PROP-10', area: 'Планировки', prio: 'P3', status: 'open', effort: 'L',
    title: 'Развитие редактора планировок',
    problem: 'Есть слои, размеры, поворот, DXF-подложка и 3D-превью, но нет привязки к стенам/зонам и размеров «от стены».',
    action: 'Добавить магниты к стенам/зонам, размеры от стены, экспорт 3D-вида в PNG, шаблоны типовых участков.',
    evidence: 'apps/layout (L1–L3, v354)'
  },
  {
    id: 'PROP-11', area: 'Данные', prio: 'P3', status: 'open', effort: 'M',
    title: 'Вынести крупные данные каталога',
    problem: 'assets/js/catalog.js (≈129 КБ) и tools/modules-analysis.js (≈60 КБ) растут; грузятся полностью.',
    action: 'При дальнейшем росте вынести данные в JSON и грузить по требованию; либо оставить как есть (текущий объём приемлем).',
    evidence: 'assets/js/catalog.js'
  },
  {
    id: 'PROP-12', area: 'CI', prio: 'P3', status: 'open', effort: 'S',
    title: 'Автопроверки в CI',
    problem: 'Есть workflow .github/workflows/audit.yml и checks.yml, но нужно подтвердить, что offline-часть (audit, security, ux, perf) реально гоняется на push/PR.',
    action: 'Убедиться, что шаги запускают tools/audit.ps1 + security/ux/perf и падают при регрессах; добавить бейдж.',
    evidence: '.github/workflows/'
  },
  {
    id: 'PROP-13', area: 'Мобильные', prio: 'P3', status: 'open', effort: 'S',
    title: 'Осмысленные быстрые действия',
    problem: 'mobile.js теперь синтезирует quick по связям каталога для всех модулей, но для части модулей действия неочевидны.',
    action: 'Задать явные catalog.quick для 10–15 топ-модулей (заказы, наряды, склад, сервис, ОТК, кадры).',
    evidence: 'assets/js/mobile.js, catalog.quick'
  }
];
