/* ============================================================
   tools/proposals.js — единый источник «Плана изменений» (Roadmap).
   Используется: tools/gen-roadmap.js (docs/ROADMAP.md) и tools/gen-modules-page.js
   (раздел дашборда «Предложения по изменениям»).
   Поля: id, wave (R1|R2|R3), prio (P1|P2|P3), area, business[] (контуры),
   modules[] (затронутые модули), title, problem, action, dod (критерий), evidence, effort (S|M|L), status (open|done).
   ============================================================ */
'use strict';

const BIZ = {
  prod: 'Заказы и производство',
  econ: 'Экономика и управление',
  qa: 'Качество и сервис',
  common: 'Общее'
};

const ITEMS = [
  /* ============ R1 — приоритетные контуры ============ */
  {
    id: 'PROP-01', wave: 'R1', prio: 'P1', area: 'UX', status: 'done', effort: 'M',
    business: [BIZ.prod, BIZ.econ, BIZ.qa],
    modules: ['orders', 'production', 'planning', 'mes', 'norms', 'economics', 'finance', 'teo', 'bi', 'reports', 'qc', 'quality', 'service', 'claims', 'passport'],
    title: 'Единый поиск и пустые состояния в модулях',
    problem: 'Раньше: 3 модуля со списками без поиска и часть модулей без пустого состояния; ux-check игнорировал JS-списки.',
    action: 'Добавлен единый поиск через AppUI.autoSearch (input[data-search]) в 16 модулей; в 4 модулях добавлены плейсхолдеры; ux-check теперь учитывает JS-списки и требует пустое состояние только у модулей со списками.',
    dod: 'ux-check: 0 модулей «без поиска» и 0 «без пустого состояния». ✅ достигнуто.',
    evidence: 'docs/UX_REPORT.md (tools/ux-check.ps1), assets/js/ui.js (autoSearch)'
  },
  {
    id: 'PROP-14', wave: 'R1', prio: 'P1', area: 'Сценарии', status: 'open', effort: 'L',
    business: [BIZ.prod, BIZ.qa, BIZ.econ],
    modules: ['orders', 'bom', 'norms', 'production', 'planning', 'qc', 'warehouse', 'finance'],
    title: 'Сквозной сценарий «Заявка → ТП → наряд → ОТК → склад → отгрузка → счёт»',
    problem: 'Модули реализованы по отдельности; не подтверждена сквозная передача данных и статусов между контурами (разрывы: заявка↔маршрут↔наряд↔движение материала↔счёт).',
    action: 'Провести и автоматизировать сквозной прогон: заявка → расчёт/нормы → наряд → приёмка ОТК → списание/приход → отгрузка → счёт/дебиторка. Устранить разрывы.',
    dod: 'Сценарий проходит end-to-end на демо-данных; каждое звено связано (FK/связь или RPC); есть проверка в scenario-check.',
    evidence: 'catalog.connects, tools/scenario-check.ps1'
  },
  {
    id: 'PROP-15', wave: 'R1', prio: 'P1', area: 'Сценарии', status: 'open', effort: 'M',
    business: [BIZ.qa],
    modules: ['claims', 'issues', 'service', 'passport', 'qc', 'quality'],
    title: 'Сквозной сценарий «Рекламация/CAPA → наряд → паспорт → KPI»',
    problem: 'Рекламации, CAPA, сервисные наряды и цифровой паспорт существуют раздельно; не прослеживается «дефект → мероприятие → исправление → паспорт».',
    action: 'Связать рекламацию/дефект с CAPA-мероприятием, сервисным нарядом и записью в паспорте изделия; вывести в KPI качества.',
    dod: 'Цепочка рекламация→CAPA→наряд→паспорт проходит; KPI качества считаются из этих данных.',
    evidence: 'apps/claims, apps/issues, apps/service, apps/passport'
  },
  {
    id: 'PROP-16', wave: 'R1', prio: 'P1', area: 'Экономика', status: 'open', effort: 'M',
    business: [BIZ.econ, BIZ.prod],
    modules: ['economics', 'teo', 'finance', 'projbudget', 'reports', 'bi'],
    title: 'Согласованность расчётов себестоимости, план-факта и бюджетов',
    problem: 'Себестоимость, ТЭО, финансы и бюджеты проектов могут считать разными формулами/ставками; нет единой гарантии совпадения итогов.',
    action: 'Сверить методики (ставки, накладные, K-коэффициенты), вывести единые показатели, добавить контрольную сверку план-факт.',
    dod: 'Итог расчёта по заказу совпадает в economics/teo/finance; есть отчёт сверки план-факт без расхождений.',
    evidence: 'apps/economics, apps/teo, apps/finance, apps/projbudget'
  },
  {
    id: 'PROP-04', wave: 'R1', prio: 'P1', area: 'Производительность', status: 'open', effort: 'M',
    business: [BIZ.prod, BIZ.econ, BIZ.qa],
    modules: ['orders', 'production', 'qc', 'tasks', 'integrations'],
    title: 'Индексы и пагинация горячих списков',
    problem: 'Большое число RPC (≈1282); крупные списки (orders, naryads, qc_measures, tasks, integration_log, sessions) без явной пагинации/индексов.',
    action: 'Добавить индексы по горячим фильтрам/сортировке и limit/offset (keyset) для крупных списков приоритетных контуров.',
    dod: 'Индексы созданы миграцией; списки лимитированы; проверка планов запросов пройдена.',
    evidence: 'audit/checks/perf.json (F-0001)'
  },
  {
    id: 'PROP-02', wave: 'R1', prio: 'P1', area: 'Каталог', status: 'done', effort: 'S',
    business: [BIZ.common], modules: [],
    title: 'Заполнить audience у модулей',
    problem: '14 модулей каталога не имели поля audience — фильтры хаба не относили их к «пользовательским».',
    action: 'Проставлено audience:"user" (mdm, plm, edo, tasks, kedo, eam, safety, holding, projbudget, pmo, logistics, itsm, elearning, accounting). Каталог v10.52, CATALOG_V 128.',
    dod: 'Все 100 модулей имеют audience; audit ✅.',
    evidence: 'assets/js/catalog.js (v355)'
  },

  /* ============ R2 — поперечные / надёжность ============ */
  {
    id: 'PROP-05', wave: 'R2', prio: 'P2', area: 'API', status: 'open', effort: 'M',
    business: [BIZ.common], modules: ['api', 'integrations'],
    title: 'Разобрать RPC без вызова из UI',
    problem: '≈172 функции объявлены в БД и не вызываются из клиента — риск «мёртвой» поверхности и неясных контрактов.',
    action: 'Классифицировать: backend/helper → API_SURFACE.md; лишнее → закрыть grant/удалить; недостающее UI → добавить вызов.',
    dod: 'API_SURFACE.md отражает фактическую поверхность; счётчик «RPC без UI» снижен или объяснён.',
    evidence: 'audit/checks/trace.json (F-0002)'
  },
  {
    id: 'PROP-03', wave: 'R2', prio: 'P2', area: 'Безопасность', status: 'open', effort: 'M',
    business: [BIZ.common], modules: [],
    title: 'Харденинг RLS и грантов',
    problem: 'Зафиксированы 2 пермиссивные INSERT-политики (tenders, profiles) и helper без явного grant.',
    action: 'Пересмотреть WITH CHECK (роль/тенант), выдать/закрыть grant у helper; проверить default-deny у app_*.',
    dod: 'security-check ✅; INSERT-политики ограничены ролью/тенантом; нет helper без назначения.',
    evidence: 'docs/BACKLOG.md (v278)'
  },
  {
    id: 'PROP-08', wave: 'R2', prio: 'P2', area: 'Доступность', status: 'open', effort: 'M',
    business: [BIZ.common], modules: [],
    title: 'aria-label для иконочных кнопок',
    problem: 'Тулбары модулей используют только символы (↶ ↷ ✋ 🔗 …) без текста скринридеру.',
    action: 'Добавить aria-label (и title) всем кнопкам без текста; начать с приоритетных модулей.',
    dod: 'У иконочных кнопок есть доступное имя; ручная проверка ключевых экранов.',
    evidence: 'apps/**/index.html, assets/js/*.js'
  },
  {
    id: 'PROP-17', wave: 'R2', prio: 'P2', area: 'Метрика', status: 'open', effort: 'M',
    business: [BIZ.common], modules: [],
    title: 'Пересмотр метрики готовности (наличие → зрелость)',
    problem: '«100%» отражает наличие модуля/связей/валидного JS, но не глубину и удобство; метрика вводит в заблуждение.',
    action: 'Ввести уровни зрелости (L1 наличие → L2 данные+UX → L3 сценарии → L4 автотесты) и пересчитать дашборд по ним.',
    dod: 'Дашборд показывает готовность по уровням; для каждого модуля видна «тонкая» зрелость, а не только ✅.',
    evidence: 'tools/modules-analysis.js, tools/gen-modules-page.js'
  },
  {
    id: 'PROP-18', wave: 'R2', prio: 'P2', area: 'Тесты', status: 'open', effort: 'M',
    business: [BIZ.prod, BIZ.qa, BIZ.econ], modules: [],
    title: 'Автотесты сквозных сценариев',
    problem: 'scenario-check проверяет RPC по одному, но не сквозные бизнес-цепочки из R1.',
    action: 'Добавить сценарные кейсы (заявка→…→счёт; рекламация→…→паспорт) в scenario-check/db-smoke.',
    dod: 'Сквозные кейсы зелёные в scenario-check; регрессы ловятся автоматически.',
    evidence: 'tools/scenario-check.ps1, tools/db-smoke.ps1'
  },
  {
    id: 'PROP-09', wave: 'R2', prio: 'P2', area: 'Прототипы', status: 'open', effort: 'L',
    business: [BIZ.qa, BIZ.common], modules: ['diagnostics', 'terminal', 'service', 'iiot', 'guide'],
    title: 'Довести 4 прототипа',
    problem: 'A5 «Аудит зрелости», A12 «АРМ», B36 «ИТ-инфраструктура», P12 «Технологический путь» перенесены частично.',
    action: 'Спланировать доработку (диагностика / терминал-сервис / iiot / гид) или явно пометить «вне периметра».',
    dod: 'У каждого прототипа статус закрыт (реализовано или «вне периметра» с обоснованием).',
    evidence: 'modules.html → «Прототипы → реализация»'
  },

  /* ============ R3 — гигиена и развитие ============ */
  {
    id: 'PROP-06', wave: 'R3', prio: 'P3', area: 'Документация', status: 'open', effort: 'S',
    business: [BIZ.common], modules: [],
    title: 'Консолидация планов и аудитов',
    problem: 'Дублирующие исторические документы (PLAN_UPDATE_V2/V3/V5, PLAN_WAVES, UPDATE_PLAN, часть AUDIT_*) затрудняют навигацию.',
    action: 'Перенести историческое в docs/archive/ с указателем; в корне docs оставить актуальное; источник правды — BACKLOG.md + ROADMAP.md.',
    dod: 'В docs/ нет дублей; историческое — в docs/archive/ с README.',
    evidence: 'docs/'
  },
  {
    id: 'PROP-07', wave: 'R3', prio: 'P3', area: 'Документация', status: 'open', effort: 'S',
    business: [BIZ.common], modules: [],
    title: 'Разгрузить журнал BACKLOG',
    problem: 'docs/BACKLOG.md ≈249 КБ — журнал §5 содержит сотни записей.',
    action: 'Вынести записи старше N версий в docs/BACKLOG_ARCHIVE.md, оставить последние ~40–50.',
    dod: 'BACKLOG обозрим; архив доступен и связан ссылкой.',
    evidence: 'docs/BACKLOG.md'
  },
  {
    id: 'PROP-12', wave: 'R3', prio: 'P3', area: 'CI', status: 'open', effort: 'S',
    business: [BIZ.common], modules: [],
    title: 'Автопроверки в CI',
    problem: 'Есть .github/workflows (audit.yml, checks.yml) — нужно подтвердить, что offline-проверки гоняются на push/PR.',
    action: 'Проверить/дополнить workflow: audit.ps1 + security/ux/perf; падать при регрессах; бейдж.',
    dod: 'CI запускает проверки и краснеет на регрессах.',
    evidence: '.github/workflows/'
  },
  {
    id: 'PROP-13', wave: 'R3', prio: 'P3', area: 'Мобильные', status: 'open', effort: 'S',
    business: [BIZ.prod, BIZ.qa, BIZ.econ],
    modules: ['orders', 'production', 'warehouse', 'service', 'qc', 'hr'],
    title: 'Осмысленные быстрые действия (mobile)',
    problem: 'mobile.js синтезирует quick по связям, но для части модулей действия неочевидны.',
    action: 'Задать явные catalog.quick для 10–15 топ-модулей.',
    dod: 'Для топ-модулей мобильная панель содержит 2–3 осмысленных действия.',
    evidence: 'assets/js/mobile.js, catalog.quick'
  },
  {
    id: 'PROP-11', wave: 'R3', prio: 'P3', area: 'Данные', status: 'open', effort: 'M',
    business: [BIZ.common], modules: [],
    title: 'Вынести крупные данные каталога',
    problem: 'assets/js/catalog.js ≈129 КБ и tools/modules-analysis.js ≈60 КБ растут и грузятся целиком.',
    action: 'При росте — вынести данные в JSON и грузить по требованию (или оставить, если объём приемлем).',
    dod: 'Размер критичного бандла ясен; при выносе — данные грузятся лениво.',
    evidence: 'assets/js/catalog.js'
  },
  {
    id: 'PROP-10', wave: 'R3', prio: 'P3', area: 'Планировки', status: 'open', effort: 'L',
    business: [BIZ.prod], modules: ['layout'],
    title: 'Развитие редактора планировок',
    problem: 'Есть слои, размеры, поворот, DXF-подложка и 3D-превью, но нет привязки к стенам/зонам и размеров «от стены».',
    action: 'Магниты к стенам/зонам, размеры от стены, экспорт 3D в PNG, шаблоны участков.',
    dod: 'Узлы прилипают к стенам; есть размер «от стены»; 3D экспортируется в PNG.',
    evidence: 'apps/layout (L1–L3)'
  },
  {
    id: 'PROP-19', wave: 'R3', prio: 'P3', area: 'Дифференциаторы', status: 'open', effort: 'L',
    business: [BIZ.prod, BIZ.qa],
    modules: ['iiot', 'nc', 'norms', 'config', 'ai', 'assistant', 'oee', 'tooling'],
    title: 'Углубление уникальных фич',
    problem: 'IIoT/DNC, нормирование, конфигуратор спец-технологий и ИИ-помощник — сильные отличия, но реализованы базово.',
    action: 'Довести реальные сценарии: опрос телеметрии/DNC, авто-нормирование, расчёт конфигуратора, ИИ-ответы по БЗ.',
    dod: 'Каждая фича закрывает реальный сценарий, а не демонстрацию.',
    evidence: 'apps/iiot, apps/nc, apps/norms, apps/config, apps/ai'
  }
];

module.exports = ITEMS;
module.exports.BIZ = BIZ;
module.exports.META = { version: '1.0', waves: { R1: 'Приоритетные контуры', R2: 'Поперечные и надёжность', R3: 'Гигиена и развитие' } };
