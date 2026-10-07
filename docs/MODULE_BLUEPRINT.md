# MODULE_BLUEPRINT — типовая структура модуля и порядок правок по ТЗ

Назначение: воспроизводимая «формула» доведения любого модуля до уровня сервиса
(эталон — `apps/service` + миграции `0116…0132`). Применяется при доработке
других модулей: берём ТЗ/макет, сверяем (гап-анализ), **дополняем существующий**
модуль, не создавая дубль (см. `MODULE_STANDARD.md` §6 «Сверка с ТЗ», §7 «Приёмы и грабли»).

## 1. Эталон: что реализовано в сервисе
Заявки (SRV-) с приоритетом/SLA, каналом/источником, гарантией; история; выезды;
гарантии+контракты с **лицензиями** `WR-ГГГГ-NNNNN`; запчасти/резерв; снабжение;
KPI (SLA/MTTR/MTBF/FTFR/CSAT/загрузка); правила IIoT; ППР-автозаявки; SLA-эскалация;
акт/спецификация/отчёт/**паспорт станка** (PDF); история ремонта; инструкции оператору;
шаблоны; навигация к смежным модулям; поиск (модульный + системный); матрица ролей;
вкладка «Процесс»; офлайн-действия.

## 2. Слои модуля (порядок реализации)

### 2.1 Данные (миграции `supabase/migrations/NNNN_*.sql`)
- Таблицы `app_<сущность>`: `id uuid default gen_random_uuid()`, `tenant_id uuid`, `created_at timestamptz default now()`, RLS `enable`.
- Новые поля к существующим таблицам — только `add column if not exists` (без ломания).
- Справочники/номера: последовательность + `setval` после демо-вставок.
- Демо-данные и статьи БЗ — идемпотентно (`where not exists`), с глобальным guard при повторном прогоне.
- Сборка: блок в `apply_all.sql` строго между маркерами `-- >>>>>>>>>> NNNN_x.sql` / `-- <<<<<<<<<< NNNN_x.sql`.

### 2.2 RPC-контракт (единые имена и правила)
- Чтение: `app_<сущность>_list(token[,q])`, `app_<сущность>_get(token,id)`.
- Мутации: `app_<сущность>_save(...)` → `table(id|ok, message)`; `_set_status`; `_delete`.
- Спец-операции: `_assign`, `_scan` (SLA/ППР/IIoT), `_report`, `_spec`, `_act`, `_passport`, `_find`, `_search`.
- Правила plpgsql: `#variable_conflict use_column`; уникальные имена локальных переменных (не как OUT); `drop function` при смене подписи/типа; `security definer set search_path=public`; tenant-изоляция (`app_my_tenant`), роли (`app_production_allowed`/`app_can`); `grant execute ... to anon, authenticated`.
- **Один RPC — одна роль** (не создавать перегрузки с одинаковым именем: вызов без аргументов станет неоднозначным; пример конфликта — `app_equipment_list`).

### 2.3 UI (`apps/<id>/`)
- `index.html`: `topbar` + `hero` + `.sv-tabs` (вкладки-экраны) + `.screen` секции; подключение `config→supabase-client→ui→auth→router→notify→support-widget→nav→shell→offline-queue→export→<id>.js→realtime→module-info`.
- `<id>.js`: `Auth.guard` → `load()` (Promise.all RPC) → рендер; экраны через `AppRouter.create`; формы — `AppUI.formDialog`; модалки с контентом — `ui.dialog({onOpen})`.
- Дашборд (KPI + активные + загрузка/склад), «Процесс» (визуализация), «Доступ по ролям» (матрица `data-cap`).
- Экспорт: `AppExport.exportPdf/exportDoc/exportCsv` + `reportDocument`.

### 2.4 Роли (`data-cap` + карта `CAPS`)
- Кнопки/экраны помечаются `data-cap="...";` JS скрывает недоступное по роли. Карта ролей — единый объект `CAPS` в `<id>.js`; вкладка «Доступ по ролям» строится из неё.

### 2.5 Связи (важнее всего)
- `catalog.js`: `connects`, `in_`, `out` — **все id должны существовать** (проверка скриптом).
- Переходы из карточки: заказчик (`apps/client`), станок (`apps/equipment`), организация (`apps/org`), претензии (`apps/claims`), проблемы (`apps/issues`), паспорт (в модуле).
- Уведомления: `app_notif_roles_t`. Очередь интеграций: `app_integration_enqueue`. Офлайн: `offline-queue.js`.

### 2.6 Версии и процесс
- Изменённые ассеты — `?v=N` на всех страницах; `CATALOG_V` в `nav.js` и `shell.js`; синхронизировать.
- После миграций — смоук `app_smoke_test` (10/10) и `app_smoke_test_ext` (14/14); применять SQL только UTF-8 (Management API).
- Отметки: `BACKLOG.md` (§3 статус, §5 журнал), `PLAN_WAVES.md`, `STATUS.md`, `NOTES.md`, `PROMPTS.md`.

## 3. Чек-лист применения к другому модулю
- [ ] Прочитать ТЗ/макет; гап-анализ «есть/нет»; записать задачу в `BACKLOG`.
- [ ] Дополнить таблицы (`add column if not exists`), при необходимости — новые таблицы (идемпотентно).
- [ ] RPC: list/get/save/set_status + спец-операции; без перегрузок; grant.
- [ ] UI: вкладки, дашборд, форма-диалог, карточка, экспорт PDF/CSV.
- [ ] Роли: `data-cap` + `CAPS` + матрица.
- [ ] Связи: переходы к смежным модулям; `catalog.connects` (валидные id).
- [ ] Смоук + функц. тест; версии; `apply_all`; коммит/пуш; отметки.

## 4. Конфликты и грабли (проверено)
- **Перегрузка функций**: одинаковое имя с разными аргументами → неоднозначный вызов (фикс: уникальные имена, напр. `app_equipment_catalog_*`).
- **CSS**: общие классы должны существовать в `app.css` (`.screen{display:none}.screen.active{display:block}`, `.act`, `.sv-actions`) — иначе «съезжает» во всех модулях.
- **plpgsql**: record-присваивание (`select a,b into rec.a,rec.b`) недопустимо — скаляры; `setval` после фиксированных номеров; `left()` для больших текстов.
- **Каталог**: `connects` ссылается на несуществующие id (исправлять на реальные).
- **Версии**: забытый `?v=N` → старый кэш; пропущенный `nav.js` на странице.
- **Обработчики кнопок**: не передавать функцию с аргументом напрямую в `addEventListener('click', fn)` — браузер передаст `MouseEvent` как аргумент (ошибка вида `invalid input syntax for type uuid: "{isTrusted:true}"`). Оборачивать: `addEventListener('click', function(){ fn(); })`.

## 6. Промт для апгрейда модуля (шаблон для нового чата)
Скопировать и подставить `<id>`, `<Название>`, ссылку на ТЗ/макет (если есть).
```
Проект 3DMP Service. Рабочая папка: SAAS/. Прочитай: SAAS/docs/MODULE_BLUEPRINT.md, MODULE_STANDARD.md (§6–7), BACKLOG.md, catalog.js.
Задача: довести модуль <id> («<Название>», apps/<id>/) по принципу эталона apps/service, не создавая дубль.
1) Гап-анализ: сопоставь ТЗ/макет/features каталога с текущим модулем (таблицы/RPC/UI/связи/роли). Запиши план в BACKLOG (ID, артефакты, DoD).
2) Дополни: поля/таблицы (if not exists), RPC (list/get/save/set_status + спец), UI (вкладки, дашборд, formDialog, экспорт PDF/CSV), роли (data-cap+CAPS+матрица), связи (переходы к client/equipment/org/issues/claims/guide, integrations, notify, офлайн).
3) Проверь целостность: нет перегрузок функций; catalog.connects — валидные id; hrefs и id существуют; ?v=N и CATALOG_V; пересобрать apply_all (маркеры).
4) Смоук app_smoke_test (10/10) и app_smoke_test_ext (14/14), функц. тест RPC с очисткой тестовых данных; SQL — UTF-8 (Management API).
5) Отметки в BACKLOG/PLAN_WAVES/STATUS/NOTES/PROMPTS; коммит/пуш.
Инварианты: русский, светлая палитра #10b981, не ломать чужие схемы, секреты не логировать.
```

## 7. Очередь модулей на апгрейд (приоритет)
1. `maintenance` — ТОиР (начато: связка ППР→сервис).
2. `orders` — Заказы (ядро: источник работ/денег/документов).
3. `qc` / `claims` — Качество (доработка после SPC/CAPA).
4. `economics` — Экономика (затраты сервиса/ТОиР).
5. `hr`, `production`/`mes`, `procurement`, `warehouse`, `docs`, `finance`, `tooling`, `nc`, `oee`, `iiot`, `crm`/`client`, `org` — по мере необходимости.

## 5. Карта связей сервиса
`orders` (источник), `client`/`crm` (заказчик), `equipment`/`passport` (станок, паспорт),
`maintenance` (ТОиР/ППР), `iiot` (телеметрия/авто-тикеты), `warehouse`+`procurement`
(запчасти, снабжение), `issues` (проблемы/эскалация), `claims` (претензии),
`guide`/`app_knowledge` (БЗ), `integrations` (ERP/WMS/дилер), `bi`/`economics` (KPI/затраты).
