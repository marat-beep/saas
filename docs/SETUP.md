# SETUP · подключение GitHub, Supabase, FTP

## 1. GitHub (репозиторий `marat-beep/saas`, ветка `main`)

Репозиторий привязан локально: папка `SAAS/` → `origin` = `https://github.com/marat-beep/saas.git`, ветка `main`.
Push уже работает через сохранённые учётные данные (Git Credential Manager). Первый каркас отправлен коммитом `6fa76f8`.

Если push перестанет авторизовываться: github.com → **Settings → Developer settings → Personal access tokens → Tokens (classic)** → Generate, scope **`repo`** — и ввести токен по запросу Git. В файлы токен не сохраняется (`.gitignore` исключает `.env` и `.env.*`).

## 2. Supabase (проект `saas`)

Настроено и проверено (auth endpoint отвечает 200, REST принимает ключ):

```js
// assets/js/config.js
SUPABASE_URL: 'https://zfkbzzmtbrueaksfaqbf.supabase.co',
SUPABASE_ANON_KEY: 'sb_publishable_akJbBxWd13audl8KMtdB5Q_0_kT51pa'
```

`sb_publishable_*` — новый публичный клиентский ключ, аналог `anon`. Его нормально держать в клиенте; доступ к данным ограничивает **RLS**.
`service_role` / `sb_secret_*` сюда **не** вставлять никогда.

Если ключ менялся: проект `saas` → **Project Settings → API** → скопировать Project URL и **publishable/anon** key.

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
