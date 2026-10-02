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
│  └─ dashboard/                  личный кабинет: профиль и организации
├─ assets/                        общие стили и скрипты (льётся на FTP)
│  ├─ css/app.css
│  └─ js/
│     ├─ config.js                Supabase URL + publishable/anon key
│     ├─ supabase-client.js       инициализация клиента (window.SB)
│     ├─ ui.js                    утилиты (esc, toast, qs)
│     ├─ status.js                проверка подключения (window.AppStatus)
│     ├─ session.js               сессия/профиль/тенанты (window.Session)
│     └─ catalog.js               список приложений для хаба (источник правды)
├─ supabase/migrations/           НЕ льётся на FTP
│  └─ 0001_init.sql               tenants/profiles/memberships + RLS
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
- кабинет `apps/dashboard/` (профиль, организации/тенанты).

Требуется применить миграцию `supabase/migrations/0001_init.sql` (SQL Editor), после чего заработают профиль и организации.

Далее: прикладные модули сервиса (доменная модель и экраны) — после утверждения ТЗ.
