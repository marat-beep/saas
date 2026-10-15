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
    id: 'PROP-14', wave: 'R1', prio: 'P1', area: 'Сценарии', status: 'done', effort: 'L',
    business: [BIZ.prod, BIZ.qa, BIZ.econ],
    modules: ['orders', 'bom', 'norms', 'production', 'planning', 'qc', 'warehouse', 'finance'],
    title: 'Сквозной сценарий «Заявка → ТП → наряд → ОТК → склад → отгрузка → счёт»',
    problem: 'Модули связаны RPC-контрактами (order→naryad→qc→stock→invoice), но не было сквозной автопроверки цепочки.',
    action: 'Проверены сигнатуры RPC цепочки; в `apps/orders` добавлена кнопка «Создать наряд» (order→naryad через app_naryad_create); в `tools/scenario-check.ps1` добавлен сквозной сценарий заявка→наряд→ОТК→склад→счёт→оплата→себестоимость (+ очистка SCN-данных).',
    dod: 'Сценарий в scenario-check проходит при наличии токена; UI связывает заявку и наряд. Реализовано (исполнение — с токеном sbp_).',
    evidence: 'tools/scenario-check.ps1 (шаг 15), apps/orders/orders.js'
  },
  {
    id: 'PROP-15', wave: 'R1', prio: 'P1', area: 'Сценарии', status: 'done', effort: 'M',
    business: [BIZ.qa],
    modules: ['claims', 'issues', 'service', 'passport', 'qc', 'quality'],
    title: 'Сквозной сценарий «Рекламация/CAPA → наряд → паспорт → KPI»',
    problem: 'Рекламации, CAPA, сервисные заявки и паспорт изделия были связаны слабо (нет прямой связи претензия↔сервис).',
    action: 'В `apps/claims` добавлена кнопка «Создать сервисную заявку» (claim→service через app_service_save); в `tools/scenario-check.ps1` добавлен сценарий претензия→CAPA→сервис→паспорт→KPI качества.',
    dod: 'Сценарий в scenario-check проходит (с токеном); UI связывает претензию и сервисную заявку. Реализовано.',
    evidence: 'tools/scenario-check.ps1 (шаг 16), apps/claims/claims.js'
  },
  {
    id: 'PROP-16', wave: 'R1', prio: 'P1', area: 'Экономика', status: 'done', effort: 'M',
    business: [BIZ.econ, BIZ.prod],
    modules: ['economics', 'teo', 'finance', 'projbudget', 'reports', 'bi'],
    title: 'Согласованность расчётов себестоимости, план-факта и бюджетов',
    problem: 'app_order_cost (ставка: операция.base_rate → центр.cost_hour) и app_order_cost_plan_fact (ставка: шаг маршрута; план-труд из BOM) использовали разные базы ставок.',
    action: 'Миграция 0256: app_order_cost_plan_fact приведён к единой базе ставок с app_order_cost (операция → центр, фолбэк — маршрут); план/факт труда по одной ставке, отклонение = (факт−план)×ставка. Добавлена проверка в scenario-check.',
    dod: 'Обе функции используют одну ставку; сценарий сверки в scenario-check. Реализовано (миграция идемпотентна, apply_all синхронизирован 247/247).',
    evidence: 'supabase/migrations/0256_cost_consistency.sql, tools/scenario-check.ps1 (шаг 17)'
  },
  {
    id: 'PROP-04', wave: 'R1', prio: 'P1', area: 'Производительность', status: 'done', effort: 'M',
    business: [BIZ.prod, BIZ.econ, BIZ.qa],
    modules: ['orders', 'production', 'qc', 'tasks', 'integrations'],
    title: 'Индексы и пагинация горячих списков',
    problem: 'Крупные списки (orders, naryads, qc_measures, tasks, integration_log, sessions) без tenant-scoped индексов и без серверного лимита.',
    action: 'Миграция 0257: добавлены индексы (orders/naryads/qc_measures/tasks/integration_log/sessions) и серверный limit 2000 для app_order_list/app_naryad_list.',
    dod: 'Индексы созданы идемпотентно; крупные списки лимитированы; apply_all синхронизирован (248/248). Реализовано.',
    evidence: 'supabase/migrations/0257_hot_indexes.sql'
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
    id: 'PROP-05', wave: 'R2', prio: 'P2', area: 'API', status: 'done', effort: 'M',
    business: [BIZ.common], modules: ['api', 'integrations'],
    title: 'Разобрать RPC без вызова из UI',
    problem: 'RPC без UI-вызова считались неточно: trace не учитывал вызовы из assets/js (общие движки), а api-surface сопоставлял по подстроке.',
    action: 'trace-matrix теперь сканирует apps+assets/js; api-surface классифицирует backend/API по категориям (права/аналитика/служебные/триггеры/офлайн/утилиты/внешний API) с точным сопоставлением по границам слова; docs/API_SURFACE.md содержит сводку и пояснение.',
    dod: 'API_SURFACE.md отражает фактическую поверхность и объясняет backend-функции; счётчики согласованы (trace 156, api-surface 124). Реализовано.',
    evidence: 'tools/api-surface.ps1, tools/trace-matrix.ps1, docs/API_SURFACE.md (v363)'
  },
  {
    id: 'PROP-03', wave: 'R2', prio: 'P2', area: 'Безопасность', status: 'done', effort: 'M',
    business: [BIZ.common], modules: [],
    title: 'Харденинг RLS и грантов',
    problem: 'Порталу закупок достаточно чтения tenders; запись в tenders/profiles шла через legacy-политики на auth.uid() (в сервисе Supabase Auth не используется). Helper app_support_ticket_link_issue не имеет grant — по замыслу (внутренний).',
    action: 'Миграция 0258: RLS включён на tenders/profiles; у anon/authenticated отозваны insert/update/delete и выдан только select на tenders; INSERT/UPDATE-политики сделаны явно запрещающими (defense-in-depth). Подтверждено: helper намеренно без grant (вызывается внутри app_support_*).',
    dod: 'Прямая запись клиента в tenders/profiles запрещена; запись — только через RPC (SECURITY DEFINER); apply_all синхронизирован (249/249), db-integrity ✅ 0 находок.',
    evidence: 'supabase/migrations/0258_rls_hardening.sql'
  },
  {
    id: 'PROP-08', wave: 'R2', prio: 'P2', area: 'Доступность', status: 'done', effort: 'M',
    business: [BIZ.common], modules: [],
    title: 'aria-label для иконочных кнопок',
    problem: '36 кнопок-иконок (✕ × ✎ ✓ ▶ → ← ↻) не имели доступного имени для скринридеров.',
    action: 'Добавлены aria-label и title всем иконочным кнопкам (удалить/изменить/сохранить/запустить/далее/назад/повернуть) в 18 модулях; подписи prev/next уточнены в scale. Реконструкция — probe-скриптом (0 остатка).',
    dod: 'Иконочные кнопки имеют доступное имя (probe: 0 без имени). Реализовано.',
    evidence: 'apps/**/*.js, apps/**/index.html (v365)'
  },
  {
    id: 'PROP-17', wave: 'R2', prio: 'P2', area: 'Метрика', status: 'done', effort: 'M',
    business: [BIZ.common], modules: [],
    title: 'Пересмотр метрики готовности (наличие → зрелость)',
    problem: '«100%» отражает наличие модуля, но не глубину/UX/сценарность; метрика вводила в заблуждение.',
    action: 'Добавлен tools/maturity.js: уровни L1 наличие → L2 данные+UX (RPC, поиск/пустое состояние, связи) → L3 сценарии (связи ≥3) → L4 автотесты (scenario-check). Дашборд показывает уровень (бейдж L1–L4 у модуля) и панель «Зрелость модулей» с распределением.',
    dod: 'В дашборде у каждого модуля виден уровень L1–L4 и есть панель распределения. Распределение: L4 24 · L3 69 · L2 3 · L1 4. Реализовано.',
    evidence: 'tools/maturity.js, tools/gen-modules-page.js (v366)'
  },
  {
    id: 'PROP-18', wave: 'R2', prio: 'P2', area: 'Тесты', status: 'done', effort: 'M',
    business: [BIZ.prod, BIZ.qa, BIZ.econ], modules: [],
    title: 'Автотесты сквозных сценариев',
    problem: 'scenario-check проверял RPC по одному, без сквозных цепочек и инвариантов.',
    action: 'В scenario-check добавлены сквозные цепочки (заявка→наряд→ОТК→склад→счёт→оплата, претензия→CAPA→сервис→паспорт, себестоимость) с проверками-инвариантами (наряд привязан к заявке, ОТК пройден, оплата учтена) и блок инвариантов (индексы PROP-04, RLS tenders, аудит заказов).',
    dod: 'Сквозные кейсы и инварианты зелёные в scenario-check (исполнение — с токеном). Реализовано.',
    evidence: 'tools/scenario-check.ps1 (шаги 15–18)'
  },
  {
    id: 'PROP-09', wave: 'R2', prio: 'P2', area: 'Прототипы', status: 'done', effort: 'L',
    business: [BIZ.qa, BIZ.common], modules: ['diagnostics', 'terminal', 'service', 'iiot', 'guide'],
    title: 'Довести 4 прототипа',
    problem: 'Прототипы A5/A12/B36/P12 перенесены частично; требовалось решение — доработать или явно закрыть.',
    action: 'Принято и зафиксировано решение: прототипы **вне периметра сервиса** с обоснованием (A5 — консалтинг; A12 — отдельный продукт, частично терминал+сервис; B36 — инфраструктура развёртывания, частично IIoT/мониторинг; P12 — услуга, частично гид+диагностика). Отражено в дашборде и docs/ECOSYSTEM.md.',
    dod: 'У каждого из 4 прототипов явный статус с обоснованием. Реализовано.',
    evidence: 'modules.html («Прототипы → реализация»), docs/ECOSYSTEM.md (v368)'
  },

  /* ============ R3 — гигиена и развитие ============ */
  {
    id: 'PROP-06', wave: 'R3', prio: 'P3', area: 'Документация', status: 'done', effort: 'S',
    business: [BIZ.common], modules: [],
    title: 'Консолидация планов и аудитов',
    problem: 'В docs/ лежали исторические планы (PLAN_UPDATE_V2/V3/V5, PLAN_WAVES) с перекрёстными ссылками.',
    action: 'Перенесены в `docs/archive/`: PLAN_UPDATE_V2/V3/V5, PLAN_WAVES (+ ранее V4 и промты). Все ссылки в docs обновлены на archive/. `docs/archive/README.md` описывает политику. Живые артефакты оставлены (UPDATE_PLAN.md — генератор, AUDIT_* — audit-фреймворк).',
    dod: 'В docs/ нет дублей планов; историческое — в docs/archive/ с указателем; stale-ссылок 0. Реализовано.',
    evidence: 'docs/archive/, docs/BACKLOG.md (v369)'
  },
  {
    id: 'PROP-07', wave: 'R3', prio: 'P3', area: 'Документация', status: 'done', effort: 'S',
    business: [BIZ.common], modules: [],
    title: 'Разгрузить журнал BACKLOG',
    problem: 'docs/BACKLOG.md разросся (≈264 КБ), §5 содержал 204 записи журнала — поиск и чтение замедлены.',
    action: 'Записи §5 старше v309 (144 шт.) вынесены в `docs/BACKLOG_ARCHIVE.md`; в BACKLOG оставлены последние 60 и указатель. Размер BACKLOG 264→151 КБ.',
    dod: 'BACKLOG обозрим (60 записей §5), архив доступен и связан указателем. Реализовано.',
    evidence: 'docs/BACKLOG.md, docs/BACKLOG_ARCHIVE.md (v370)'
  },
  {
    id: 'PROP-12', wave: 'R3', prio: 'P3', area: 'CI', status: 'done', effort: 'S',
    business: [BIZ.common], modules: [],
    title: 'Автопроверки в CI',
    problem: 'checks.yml запускал только audit.ps1 и db-smoke; offline-проверки (integrity/security/perf/ux/api/trace) в CI не гонялись, «краснел» только аудит.',
    action: 'В `.github/workflows/checks.yml` добавлены шаги offline-проверок и **gate**, который валит сборку при находках Critical/Major в `audit/checks/*.json`. Триггеры: push/PR/schedule.',
    dod: 'CI запускает audit + offline-проверки и краснеет при Critical/Major. Реализовано.',
    evidence: '.github/workflows/checks.yml (v371)'
  },
  {
    id: 'PROP-13', wave: 'R3', prio: 'P3', area: 'Мобильные', status: 'done', effort: 'S',
    business: [BIZ.prod, BIZ.qa, BIZ.econ],
    modules: ['orders', 'production', 'warehouse', 'service', 'qc', 'hr'],
    title: 'Осмысленные быстрые действия (mobile)',
    problem: 'catalog.quick был задан лишь для части модулей; остальные использовали синтез по связям.',
    action: 'Заданы явные catalog.quick ещё для 15 модулей (planning, finance, economics, reports, hr, procurement, registry, claims, quality, docs, norms, pmo, safety, oee, config) — всего 30; каталог v10.53, CATALOG_V 129.',
    dod: 'Для топ-30 модулей мобильная панель содержит осмысленные действия. Реализовано.',
    evidence: 'assets/js/catalog.js (quick), assets/js/mobile.js (v372)'
  },
  {
    id: 'PROP-11', wave: 'R3', prio: 'P3', area: 'Данные', status: 'done', effort: 'M',
    business: [BIZ.common], modules: [],
    title: 'Вынос крупных данных каталога',
    problem: 'catalog.js ≈129 КБ, modules-analysis.js ≈59 КБ — оценить необходимость выноса.',
    action: 'Замеры: catalog.js gzip **31 КБ** (клиент), app.css 8.3 КБ; modules-analysis.js/proposals.js — build-time (клиенту не отдаются). Решение: оставить единым файлом (обоснование — docs/PERFORMANCE.md), триггер пересмотра — >200 КБ raw / >150 модулей.',
    dod: 'Объём оценён и обоснован (docs/PERFORMANCE.md); вынос не требуется на текущем масштабе. Реализовано.',
    evidence: 'docs/PERFORMANCE.md (v373)'
  },
  {
    id: 'PROP-10', wave: 'R3', prio: 'P3', area: 'Планировки', status: 'done', effort: 'L',
    business: [BIZ.prod], modules: ['layout'],
    title: 'Развитие редактора планировок',
    problem: 'Не было привязки к стенам/зонам и размеров «от стены»; 3D без экспорта; не было типовых шаблонов.',
    action: 'В apps/layout: расширены магниты (рёбра стен/зон/оборудования + края плана, выравнивание лево/право/верх/низ), размеры «от стены» у выбранного узла, экспорт 3D-вида в PNG, меню «Шаблоны» (мехобработка/сборка/склад). `layout.js` v15→16.',
    dod: 'Узлы магнится к стенам; есть размер «от стены»; 3D сохраняется в PNG; шаблоны вставляются. Реализовано.',
    evidence: 'apps/layout/layout.js, apps/layout/index.html (v374)'
  },
  {
    id: 'PROP-19', wave: 'R3', prio: 'P3', area: 'Дифференциаторы', status: 'done', effort: 'L',
    business: [BIZ.prod, BIZ.qa],
    modules: ['iiot', 'nc', 'norms', 'config', 'ai', 'assistant', 'oee', 'tooling'],
    title: 'Углубление уникальных фич',
    problem: 'IIoT/DNC и конфигуратор были базовыми; требовались более «рабочие» сценарии.',
    action: 'IIoT: тренды по метрикам (sparkline) + экспорт показаний CSV. Конфигуратор: экспорт выбранной конфигурации в CSV. Нормирование/ИИ-помощник уже усилены ранее (мастера, поиск, подсказки). IIoT `iiot.js` v2→3, config `configurator.js` v3→4.',
    dod: 'IIoT показывает тренды и экспорт; конфигуратор экспортирует выбор. Реализовано (без новых RPC).',
    evidence: 'apps/iiot, apps/config (v375)'
  }
];

module.exports = ITEMS;
module.exports.BIZ = BIZ;
module.exports.META = { version: '1.0', waves: { R1: 'Приоритетные контуры', R2: 'Поперечные и надёжность', R3: 'Гигиена и развитие' } };
