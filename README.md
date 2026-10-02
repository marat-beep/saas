# 3DMP Service (repo `saas`)

Сервисный контур экосистемы **3DMP**: не рекламный лендинг, а рабочий инструмент-сервис на **Supabase** (PostgreSQL + Auth + RLS + Storage), публикуемый статикой на **sapfir.eu/saas**.

- **Стек:** vanilla HTML/CSS/JS + `@supabase/supabase-js` (CDN), без сборки и фреймворков.
- **Данные:** Supabase (мультитенантность, RLS по `auth.uid()` и `tenant_id`).
- **Деплой:** заливка файлов по FTP в папку `sapfir.eu\saas` (вручную).
- **Границы:** не связан с `project/` (прототипы экосистемы) и `НОРМ_РАЗРАБ/` (проект «Нормирование PRO»). Схемы `gravirovka`, `norms_*` и их ключи не затрагиваются.

## Структура

```
SAAS/
├─ index.html                     точка входа: проверка подключения к Supabase
├─ assets/
│  ├─ css/app.css                 базовая дизайн-система сервиса
│  └─ js/
│     ├─ config.js                ← заполнить SUPABASE_URL и SUPABASE_ANON_KEY
│     ├─ supabase-client.js       инициализация клиента (window.SB)
│     └─ app.js                   старт и health-check
├─ supabase/migrations/
│  └─ 0001_init.sql               базовая схема: tenants/profiles/memberships + RLS
└─ docs/SETUP.md                  где взять URL, anon key, токен и как применить SQL
```

## Быстрый старт

1. Заполнить `assets/js/config.js` (значения брать из Supabase → Settings → API).
2. Применить схему: Supabase → **SQL Editor** → вставить `supabase/migrations/0001_init.sql` → Run.
3. Открыть `index.html` локально (должно появиться «Подключение к Supabase OK»).
4. Залить содержимое репозитория по FTP в `sapfir.eu\saas`.

Подробно — в `docs/SETUP.md`.

## Статус

Каркас инфраструктуры. Прикладной состав сервиса (экраны, доменная модель, сценарии) добавляется после утверждения ТЗ.
