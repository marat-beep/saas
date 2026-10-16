# Сравнение с рынком: состав функций SaaS/ERP/MES/PLM/EAM и наши пробелы

_Исследование по открытым источникам (октябрь 2026). Источники — раздел «Источники» внизу; сравнение — с нашим каталогом 100 модулей (9 контуров). Итог — волна предложений **R4** в `tools/proposals.js`; продолжение по остаточным пробелам — волна **R6 «BPM 2.0, договоры и финансы»** (PROP-36…PROP-41)._

## 1. Референс-карта (эталонный состав)

### ERP (Enterprise resource planning)
Функциональные области (типовой набор модулей):
- **Финансовый учёт:** главная книга (GL), основные средства, дебиторка (AR), кредиторка (AP: vouchering/matching/payment), касса/ликвидность, консолидация.
- **Управленческий учёт:** бюджетирование, расчёт себестоимости, ABC-костинг, биллинг, выставление счетов.
- **Персонал:** подбор, обучение, графики (rostering), расчёт зарплаты (payroll), льготы, выход/увольнение.
- **Производство:** инжиниринг, BOM, наряды/заказы, расписание, мощность, workflow, контроль качества, PLM.
- **Обработка заказов:** order-to-cash, ввод заказов, **кредитная проверка**, ценообразование, **ATP** (available-to-promise), запасы, отгрузка, анализ продаж, комиссии.
- **SCM:** планирование цепочки, расписание поставщиков, **продуктовый конфигуратор**, закупки, запасы, обработка рекламаций, склад (приёмка/размещение/**сборка/упаковка**).
- **Проекты:** планирование, ресурсы, проектная себестоимость, **WBS**, биллинг, **учёт времени/расходов**.
- **CRM:** продажи/маркетинг, комиссии, сервис, контакты, контакт-центр.
- **SRM:** поставщики, заказы, платежи.
- **Data services:** self-service порталы для клиентов/поставщиков/сотрудников.
- **Управление договорами:** шаблоны, ЭП, **алерты по вехам**, поиск.
- Тренды: two-tier ERP, postmodern ERP, влияние ИИ (агентные интерфейсы, предиктив).

### MES (ISA-95 / MESA, уровень 3)
- Управление определениями продукта (маршруты, BOM, BoR, уставки, рецепты, версии).
- Управление ресурсами; расписание; **диспетчеризация** заказов; исполнение; **сбор данных** (historian); анализ производительности (WIP, OEE); **track & trace**.
- Смежные: LIMS (лаборатория), WMS (склад), CMMS (ТОиР).
- Интерфейсы: PLM (определения), ERP (планирование/заказы), CRM (жалобы), HRM (навыки); уровень 2 — SCADA/PLC/DCS, **OPC-UA**, **MQTT/Sparkplug**.

### PLM (управление жизненным циклом изделия)
- 5 областей: системная инженерия, продуктовый портфель (PPM), проектирование (CAD/CAE/CAM), **управление техпроцессами** (MPM/CAPP/ЧПУ/оснастка), **PDM** (данные, **изменения ECN/ECO**).
- Фазы: Conceive → Design → Realize → Service; **замкнутый цикл** (CL2M), compliance (**RoHS**, 21 CFR Part 11).

### EAM / CMMS
- Управление жизненным циклом активов, **планово-предупредительное ТО**, **гарантия**, мобильный EAM, наряды с приоритетами/навыками/материалами/инструментом.

## 2. Сопоставление с нашим каталогом (сильные стороны)

| Область рынка | У нас | Оценка |
|---|---|---|
| Производство/MES | production, mes, planning (APS), terminal, oee, slots, setup, lean | ✅ сильно |
| КТПП/нормирование | registry, bom, norms, calc, nc, reverse, config, assistant | ✅ сильно (уникально) |
| Планировки цеха | layout (слои, DXF, 3D, шаблоны) | ✅ уникально |
| Качество | qc (SPC), quality (СИ), passport, claims (CAPA) | ✅ сильно |
| Track & trace | passport, quality.trace, warehouse лоты, qc.trace | ✅ |
| ТОиР/EAM | maintenance, eam, tooling | ✅ |
| IIoT/DNC | iiot (коннекторы OPC-UA/MTConnect/Modbus, DNC, OEE, износ) | ✅ (нет MQTT) |
| Проекты | pmo, projbudget (EVM), tasks, calendar | ◐ (нет WBS/timesheets явно) |
| CRM/продажи | crm, client, dealer, partners, marketplace, supplier | ◐ |
| Закупки/SRM | procurement, suppliers, tenders | ◐ |
| Склад/WMS | warehouse (адресное), logistics (TMS) | ◐ |
| Экономика/финансы | economics, teo, finance, bi, reports, projbudget, accounting(задел) | ◐ |
| HR | hr, staff, competences, kedo | ◐ (нет payroll/подбора) |
| Платформа | platform, admin, roles, access, billing, usage, whitelabel, builder, workflow, integrations, edo, api | ✅ сильно |
| Портал/self-service | client, supplier, dealer, product | ✅ |

## 3. Пробелы (что улучшить) → волна R4

1. **Финансы: основные средства и амортизация** — в ERP обязательный контур; у нас `accounting` задел без ОС/амортизации. → PROP-20.
2. **HR: расчёт зарплаты и подбор** — нет payroll и recruiting. → PROP-21.
3. **Продажи: CPQ + кредитный лимит + ATP** — нет проверки кредитного лимита, доступности к обещанию и клиентского конфигуратора цен. → PROP-22.
4. **Склад: отгрузочные задания (picking/packing)** — адресное хранение есть, сборка/упаковка заказа нет. → PROP-23.
5. **Закупки/SRM: планирование закупок, скоринг поставщиков, 3-way match** — нет сопоставления «заказ–приёмка–счёт». → PROP-24.
6. **Проекты: WBS и учёт времени (timesheets)** — нет иерархии работ и табелей времени. → PROP-25.
7. **Качество/LIMS: сертификаты и регламенты (RoHS/отраслевые), лаборатория** — нет сертификатов/деклараций и LIMS. → PROP-26.
8. **IIoT: MQTT/Sparkplug и edge-профиль** — подключены OPC-UA/MTConnect/Modbus, нет MQTT и буферизации на edge. → PROP-27.
9. **CRM: маркетинг/кампании и контакт-центр** — обработка обращений/кампаний отсутствует. → PROP-28.
10. **Экономика: ABC-костинг и консолидация группы** — есть план-факт и holding, нет activity-based costing и полной консолидации. → PROP-29.

## 4. CRM (углублённо)

Типовые функции CRM (по Wikipedia): **операционный CRM** (автоматизация продаж, маркетинга, сервиса), **аналитический** (хранилище данных, аналитика, единый профиль клиента), **коллаборативный** (омниканальность, соцсети, контакт-центр), **стратегический**, **CDP**. Компоненты: управление возможностями/сделками, кампании, call/contact-center, автоматизация продаж (SFA), customer success, предиктивная аналитика/ИИ, единое представление клиента.

| Функция CRM | У нас | Пробел |
|---|---|---|
| Лиды → воронка → сделки | crm (воронка, стадии) | ◐ нет явных **лидов** и конверсии/квалификации |
| Компании/контакты | crm, client | ✅ |
| Активности/напоминания | crm (звонок/встреча/e-mail/Telegram/SMS) | ✅ |
| Маркетинг/кампании | — | ❌ (см. PROP-28) |
| Сервис/обращения, контакт-центр, SLA | service, issues, support | ◐ нет омниканального контакт-центра |
| Единый профиль клиента (360°) | client | ◐ разрознено (заказы/сервис/деньги) |
| Аналитика/прогноз продаж | bi, forecast | ◐ нет воронки в деньгах/прогноза по стадиям |
| Комиссии | partners | ◐ |
| Омниканальность | crm (каналы) | ◐ нет единого inbox |

## 5. BPM / бизнес-процессы (углублённо)

BPM (Wikipedia): дисциплина «моделирование → исполнение → мониторинг → оптимизация». Жизненный цикл: **Design** (поток, алерты/уведомления, **эскалации**, SOP, **SLA**, передача задач), **Modeling** (what-if), **Execution** (автоматизация; human+system; **BPMS/iBPMS/low-code**; **RPA** на уровне представления; **бизнес-правила**), **Monitoring** (**BAM**, **process mining**, предиктивный мониторинг), **Optimization**, **Re-engineering**. Инструменты: SIPOC, RACI, CTQ.

BPMN 2.0 (ISO 19510): элементы — **события** (start/intermediate/end; catching/throwing), **действия** (task, sub-process, transaction, call activity), **шлюзы** (exclusive, event-based, parallel, inclusive, complex), **связи** (sequence/message/association), **дорожки** (pool/lane), **артефакты** (data object, group, annotation). Суб-модели: private / abstract (public) / collaboration. Смежные стандарты: **CMMN** (кейсы), **DMN** (решения).

| Возможность BPM | У нас | Пробел |
|---|---|---|
| Конструктор процессов/задач/форм | workflow (low-code: процессы, задачи этапов, правила, формы) | ◐ нет графической **BPMN-схемы** и экспорта BPMN |
| Шлюзы/условия/маршрутизация | workflow (правила-триггеры) | ◐ нет явных шлюзов (parallel/inclusive) |
| SLA/таймеры/эскалации | support (SLA), tasks | ◐ нет таймеров/эскалаций в процессах |
| Мониторинг/BAM/process mining | bi, reports | ❌ нет process mining и BAM по процессам |
| Реестр процессов (BPMN-диаграммы) | — | ❌ (см. PROP-32) |
| Кейсы (CMMN) и решения (DMN) | — | ❌ (вне/частично) |

## 6. Справочники (reference data)
Полный предлагаемый реестр и что завести в БД — в **`docs/REFERENCE_DATA.md`**. Базовый сид реализован: `supabase/migrations/0259_reference_dicts.sql` (`app_seed_reference_dicts`), кнопка «Загрузить базовые» в «Справочниках».

## 7. Что оставить как есть (осознанно вне периметра)
- **CAD/CAE/CAM** (проектирование геометрии), **LIMS-лабораторные испытания**, **SCADA/PLC/уровень 0-1** — вне периметра сервиса (интеграция через IIoT/API).
- Двухуровневая ERP (two-tier) и межорганизационная консолидация — частично закрыты `holding`.

## Источники (реальные, проверены)
- Wikipedia: [Enterprise resource planning](https://en.wikipedia.org/wiki/Enterprise_resource_planning) (функциональные области ERP).
- Wikipedia: [Manufacturing execution system](https://en.wikipedia.org/wiki/Manufacturing_execution_system) (функции MES, ISA-95, OPC-UA/MQTT, связи с LIMS/WMS/CMMS).
- Wikipedia: [Product lifecycle](https://en.wikipedia.org/wiki/Product_lifecycle) (PLM: PPM/CAx/MPM/PDM, фазы, compliance).
- Wikipedia: [Enterprise asset management](https://en.wikipedia.org/wiki/Enterprise_asset_management) (EAM/CMMS, ППР, гарантия, мобильный EAM).
- Wikipedia: [Customer relationship management](https://en.wikipedia.org/wiki/Customer_relationship_management) (типы CRM, SFA, маркетинг/сервис, контакт-центр, единый профиль).
- Wikipedia: [Business process management](https://en.wikipedia.org/wiki/Business_process_management) (жизненный цикл, SLA/эскалации, BPMS/low-code, RPA, BAM, process mining).
- Wikipedia: [Business Process Model and Notation](https://en.wikipedia.org/wiki/Business_Process_Model_and_Notation) (BPMN 2.0, ISO 19510; CMMN/DMN).
- Wikipedia: [G-code](https://en.wikipedia.org/wiki/G-code) (RS-274 / ISO 6983, стойки FANUC/Sinumerik/Heidenhain/Mazak/Okuma/Haas, canned cycles, DNC).

_Методика: открытые энциклопедические источники (стабильные), сопоставление — с `docs/MODULES_CATALOG.md` и `assets/js/catalog.js`._
