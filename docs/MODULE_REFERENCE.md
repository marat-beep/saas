# MODULE_REFERENCE — справочник модулей 3DMP Service

> Черновик. Автогенерируемый перечень из `assets/js/catalog.js` (наполнение — W37). Роли `*` — доступно всем авторизованным (staff/роль-специфично).

## Обзор по группам
- **core (7):** auth, dashboard, panel, guide, remarks, adoption, modules
- **production (22):** mes, planning, slots, setup, terminal, production, calendar, warehouse, iiot, oee, maintenance, tooling, eam, mdm, plm, logistics, pmo, ai, lean, issues, forecast, service
- **quality (4):** qc, quality, passport, claims
- **sales (14):** orders, tkp, procurement, suppliers, supplier, client, equipment, docs, docbuilder, labels, templates, crm, marketplace, partners
- **ktpp (8):** registry, bom, nc, norms, calc, reverse, config, assistant
- **economics (8):** economics, finance, bi, reports, teo, escrow, projbudget, accounting
- **platform (25):** admin, platform, org, roles, access, workflow, tasks, billing, usage, announcements, whitelabel, integrations, api, diagnostics, scale, industry, support, bugbox, files, builder, edo, kedo, itsm, safety, elearning, holding
- **staff (5):** hr, competences, departments, staff, org
- **refs (2):** dicts, eco (прототипы)

## Полный перечень (по группам)

### core
- Вход — `apps/auth`
- Гид по системе — `apps/guide`
- Замечания к странице — `apps/remarks`
- Карта внедрения — `apps/adoption`
- Личный кабинет — `apps/dashboard`
- Модули и функции — `apps/modules`
- Пульт управления — `apps/panel`

### production
- Бережливое производство — `apps/lean`
- Диспетчерская (MES) — `apps/mes`
- Инструмент и стойкость — `apps/tooling`
- Наладка — `apps/setup`
- Обслуживание и ремонт — `apps/maintenance`
- Планирование — `apps/planning`
- Проблемы и эскалация — `apps/issues`
- Прогноз загрузки — `apps/forecast`
- Производственный календарь — `apps/calendar`
- Производство — `apps/production`
- Пульт оператора — `apps/terminal`
- Сервис и ремонт — `apps/service`
- Склад — `apps/warehouse`
- Слоты и загрузка — `apps/slots`
- IIoT и DNC — `apps/iiot`
- Изделия и состав (PLM) — `apps/plm` (admin/owner/manager)
- ИИ-помощник — `apps/ai`
- Логистика (TMS) — `apps/logistics` (admin/owner/manager)
- НСИ / Мастер-данные — `apps/mdm` (admin/owner/manager)
- Портфель проектов (PMO) — `apps/pmo` (admin/owner/manager)
- EAM 2.0 (CMMS) — `apps/eam` (admin/owner/manager)
- OEE-монитор — `apps/oee`

### quality
- Качество/СМК — `apps/quality`
- ОТК — `apps/qc`
- Паспорта изделий — `apps/passport`
- Претензии и CAPA — `apps/claims`

### sales
- Документы — `apps/docs`
- Закупки — `apps/procurement`
- Заявки — `apps/orders`
- Кабинет заказчика — `apps/client` (client)
- Каталог оборудования — `apps/equipment`
- Конструктор документов — `apps/docbuilder`
- Маркетплейс мощностей — `apps/marketplace`
- Партнёры — `apps/partners`
- Портал поставщика — `apps/supplier`
- Реестр поставщиков — `apps/suppliers`
- Реестр ТКП — `apps/tkp`
- Упаковка и маркировка — `apps/labels`
- Шаблоны документов — `apps/templates`
- CRM — `apps/crm`

### ktpp
- ИИ-помощник — `apps/assistant`
- Калькуляторы — `apps/calc`
- Конфигуратор — `apps/config`
- Нормирование PRO — `apps/norms`
- Реверс-инжиниринг — `apps/reverse`
- Спецификации (BOM) — `apps/bom`
- Справочники — `apps/registry`
- УП/NC — `apps/nc`

### economics
- Аналитика — `apps/bi`
- Отчёты и экспорт — `apps/reports`
- ТЭО — `apps/teo`
- Финансы — `apps/finance`
- Экономика — `apps/economics`
- Эскроу — `apps/escrow`
- Бухгалтерия (задел) — `apps/accounting` (admin/owner)
- Бюджет проектов — `apps/projbudget` (admin/owner/manager)

### platform
- Администрирование — `apps/admin` (admin)
- Баг-бокс — `apps/bugbox`
- Брендирование — `apps/whitelabel` (admin/owner)
- Диагностика — `apps/diagnostics` (admin)
- Интеграции — `apps/integrations`
- Конструктор приложений — `apps/builder`
- Масштаб и эксплуатация — `apps/scale`
- Объявления — `apps/announcements` (admin/owner)
- Организации (SaaS) — `apps/platform` (admin)
- Отраслевая аналитика — `apps/industry`
- Роли и права — `apps/roles` (admin/owner)
- Служба поддержки — `apps/support`
- Счётчики использования — `apps/usage` (admin/owner)
- Файлы и журнал — `apps/files`
- API и интеграции — `apps/api`
- Биллинг и подписки — `apps/billing` (admin/owner)
- Документооборот (ЭДО) — `apps/edo`
- Задачи и проекты — `apps/tasks`
- ИТ-сервисы (ITSM) — `apps/itsm`
- Кадры (КЭДО) — `apps/kedo`
- Обучение (e-Learning) — `apps/elearning`
- Охрана труда (EHS) — `apps/safety`
- Права и согласования — `apps/access`
- Процессы и автоматизация — `apps/workflow`
- Холдинг (CPM) — `apps/holding` (admin/owner)

### staff
- Админ-панель клиента — `apps/org`
- Кадры — `apps/hr`
- Компетенции и обучение — `apps/competences`
- Подразделения — `apps/departments`
- CRM сотрудников — `apps/staff`

### refs
- Справочники (настраиваемые) — `apps/dicts`
- Прототипы экосистемы — `eco/`
