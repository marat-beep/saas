# SETUP · подключение GitHub, Supabase, FTP

## 1. GitHub (репозиторий `marat-beep/saas`, ветка `main`)

Репозиторий уже привязан локально: папка `SAAS/` → `origin` = `https://github.com/marat-beep/saas.git`.

Чтение работает без авторизации (репозиторий публичный). **Для push нужен токен:**

1. github.com → аватар → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**.
2. Name: `3dmp-saas`, Expiration: по желанию, Scope: ✅ **repo** (при необходимости ✅ `workflow` для Actions).
3. Сгенерировать и **скопировать токен** (показывается один раз).
4. Передать токен мне — я выполню `commit` и `push` без сохранения токена в файлы. Либо сохрани сам и не передавай: тогда push сделаешь вручную.

Токен **не коммитится**: `.gitignore` уже исключает `.env` и `.env.*`.

## 2. Supabase (проект `saas`)

1. Открыть проект `saas` → **Project Settings** (шестерёнка) → **API** (или **Data API**).
2. Скопировать:
   - **Project URL** — вида `https://<project-ref>.supabase.co`;
   - **anon / public** key — длинный JWT, начинается на `eyJ...`.
3. Вставить их в `assets/js/config.js`:
   ```js
   SUPABASE_URL: 'https://<project-ref>.supabase.co',
   SUPABASE_ANON_KEY: 'eyJ...'
   ```
   `anon` — публичный ключ, его нормально держать в клиенте. Доступ к данным ограничивает **RLS**.
   `service_role` сюда **не** вставлять никогда.

> Важно: хост проекта должен резолвиться (`https://<ref>.supabase.co`). На текущий момент `zfkbzmtbrueaksqafdbf.supabase.co` не резолвится (DNS: non-existent) — проверь точный ref в Dashboard и пришли строкой.

## 3. Схема БД

1. Supabase → **SQL Editor** → **New query**.
2. Вставить содержимое `supabase/migrations/0001_init.sql` целиком → **Run**.
3. Проверить: **Table Editor** покажет `tenants`, `profiles`, `memberships`.

Позже удобно перейти на Supabase CLI (`supabase db push`), но он не обязателен — миграции применяются вручную.

## 4. Публикация (FTP)

Заливаешь сам содержимое папки `SAAS/` (кроме `.git`, `supabase/`, `docs/` — по желанию) в серверную папку `sapfir.eu\saas`.
Адрес: `https://sapfir.eu/saas/`.

При обновлении статики поднимать версию в ссылках (`?v=N`), чтобы сбросить кэш.

## 5. Проверка работоспособности

Открыть `index.html`: на экране появится статус «Подключение к Supabase OK» и чек-лист (конфиг → CDN → клиент → связь).
