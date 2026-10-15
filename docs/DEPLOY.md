# Деплой 3DMP Service (FTP)

Цель: залить статику из локальной `SAAS/` в серверную папку **`sapfir.eu\saas`** (строчными) → **https://sapfir.eu/saas/**.

## 1. Сборка релиза
```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-release.ps1
```
Результат: `dist\saas\` (стадия) и `dist\saas-<yyyyMMdd-HHmm>.zip` (архив). Скрипт копирует **только** деплой-артефакты и исключает `supabase/`, `docs/`, `tools/`, `dist/`, `.git`, `README.md`, `AGENTS.md`.

Деплой-артефакты (льём): `index.html`, `apps/`, `assets/`, `eco/`, `web.config`, `manifest.webmanifest`, `sw.js`.

## 2. Предполётные проверки
```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\audit.ps1      # каталог/версии/shell/синтаксис
node tools/gen-modules-page.js                                            # дашборд 100%
powershell -NoProfile -ExecutionPolicy Bypass -File tools\db-integrity.ps1 # apply_all синхронен
```
Проверить в `dist\saas`: нет `supabase/docs/tools/.git`; есть `index.html`, `web.config`, `manifest.webmanifest`, `sw.js`; `assets/js/config.js` содержит только `sb_publishable_…` (публичный).

## 3. Заливка
- Загрузить **содержимое** `dist\saas\` в `sapfir.eu\saas\` (перезаписать). Корректно заливать `sw.js` и `manifest.webmanifest` в корень `saas/`.
- Не заливать служебные файлы (они уже исключены сборкой).
- При отсутствии токена Supabase миграции/сид не применятся автоматически — при необходимости применить `supabase/apply_all.sql` в SQL Editor (это **не** льётся на FTP).

## 4. После заливки
- Открыть https://sapfir.eu/saas/ и нажать **Ctrl+F5** (кэш статики отключён `web.config`).
- Быстрый смоук: хаб → вход (admin/admin) → 2–3 модуля → проверка новых панелей (Справочники, ОС, Сертификаты, Закупки, Склад/отгрузка, CRM, IIoT/edge).
- Проверить PWA: `https://sapfir.eu/saas/sw.js` и `manifest.webmanifest` доступны (200).

## 5. Откат
Хранить предыдущий `dist\saas-*.zip`; при проблемах перезалить предыдущую сборку в `saas/` и Ctrl+F5.
