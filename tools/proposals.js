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
