# 3DMP Service (repo `saas`)

Сервисный контур экосистемы **3DMP**: не рекламный лендинг, а рабочий инструмент-сервис на **Supabase** (PostgreSQL + Auth + RLS + Storage), публикуемый статикой на **sapfir.eu/saas**.

- **Стек:** vanilla HTML/CSS/JS + `@supabase/supabase-js` (CDN), без сборки и фреймворков.
- **Данные:** Supabase (мультитенантность, RLS по `auth.uid()` и `tenant_id`).
- **Деплой:** заливка файлов по FTP в папку `sapfir.eu\saas` (вручную).
- **Границы:** не связан с `project/` (прототипы экосистемы) и `НОРМ_РАЗРАБ/` (проект «Нормирование PRO»). Схемы `gravirovka`, `norms_*` и их ключи не затрагиваются.

## Структура

```
SAAS/
├─ index.html                     хаб: статус подключения + список приложений
├─ apps/                          ПРИЛОЖЕНИЯ (льётся на FTP целиком)
│  ├─ auth/                       вход, регистрация, сброс пароля
│  ├─ dashboard/                  личный кабинет: профиль и организации
│  └─ supplier/                   портал закупок для поставщиков
├─ assets/                        общие стили и скрипты (льётся на FTP)
│  ├─ css/app.css
│  └─ js/
│     ├─ config.js                Supabase URL + publishable/anon key
│     ├─ supabase-client.js       инициализация клиента (window.SB)
│     ├─ ui.js                    утилиты (esc, toast, qs)
│     ├─ status.js                проверка подключения (window.AppStatus)
│     ├─ session.js               сессия/профиль/тенанты (window.Session)
│     ├─ router.js                роутер экранов (window.AppRouter)
│     └─ catalog.js               список приложений для хаба (источник правды)
├─ supabase/migrations/           НЕ льётся на FTP
│  ├─ 0001_init.sql               tenants/profiles/memberships + RLS
│  ├─ 0002_supplier.sql           tenders/bids + RLS + демо-закупки
│  └─ 0003_seed_users.sql         демо-пользователи и роли
├─ docs/SETUP.md                  НЕ льётся на FTP
└─ AGENTS.md, README.md           НЕ льётся на FTP
```

**На FTP** заливается только: `index.html`, `apps/`, `assets/`.

## Быстрый старт

1. Заполнить `assets/js/config.js` (значения брать из Supabase → Settings → API).
2. Применить схему: Supabase → **SQL Editor** → вставить `supabase/migrations/0001_init.sql` → Run.
3. Открыть `index.html` локально (должно появиться «Подключение к Supabase OK»).
4. Залить содержимое репозитория по FTP в `sapfir.eu\saas`.

Подробно — в `docs/SETUP.md`.

## Статус

Готово:
- хаб `index.html` (статус подключения + список приложений из `catalog.js`);
- авторизация `apps/auth/` (вход, регистрация, сброс пароля);
- кабинет `apps/dashboard/` (профиль, организации/тенанты);
- **портал закупок `apps/supplier/`** (витрина, карточка закупки, подача предложения, «Мои предложения»).

Требуется применить миграции в Supabase → SQL Editor (по порядку):
- `0001_init.sql` — профили и организации;
- `0002_supplier.sql` — закупки (`tenders`) и предложения (`bids`) + RLS + демо-закупки;
- `0003_seed_users.sql` — демо-пользователи и роли.

Демо-аккаунты:

| Email | Пароль | Роль |
|---|---|---|
| owner@3dmp.ru | Owner12345 | owner |
| manager@3dmp.ru | Manager12345 | manager |
| supplier@3dmp.ru | Supplier12345 | supplier |

Далее: следующие доменные модули сервиса.
