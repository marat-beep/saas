# Backend «/shot» — реальные снимки внешних страниц

Пример боевого сервиса для модуля **«Замечания к странице»** (`apps/remarks`, `assets/js/page-remarks.js`,
`assets/js/screenshot.client.js`). Делает PNG-снимок произвольного публичного URL через headless Chromium
(Playwright) и отдаёт его клиенту по `GET /shot`.

> ⚠ Это **dev-сервис**, отдельный от статики сервиса. На FTP (`sapfir.eu\saas`) его **не заливать**.

## Установка и запуск
```bash
cd SAAS/apps/remarks/backend-example
cp .env.example .env        # задайте SHOT_TOKEN, SHOT_ALLOWLIST, ALLOWED_ORIGINS
npm install                 # установит Playwright Chromium (postinstall)
npm start                   # 0.0.0.0:8787
```

## API
`GET /shot?url=<URL>&width=<px>&fullPage=<true|false>`
- Заголовок `Authorization: Bearer <SHOT_TOKEN>` (если `SHOT_TOKEN` задан).
- Ответ: `image/png`; ошибки — JSON `{ "error": "..." }` (400/401/403/502/504).
- `GET /healthz` — статус и конфигурация.

## Безопасность (обязательно в бою)
- **Bearer-токен** (`SHOT_TOKEN`) — закрывает эндпоинт.
- **Allow-list доменов** (`SHOT_ALLOWLIST`) — только разрешённые сайты.
- **Анти-SSRF:** запрет loopback/RFC1918/CGNAT/link-local/ULA и cloud-metadata (169.254.169.254);
  проверка по DNS-резолву + перехват запросов страницы (включая редиректы и подресурсы).
- **Только http/https**, ограничение длины URL, ширины, таймаута; семафор параллельных снимков.
- **CORS** только для разрешённых Origin; заголовки безопасности Express (`x-powered-by` off).
- В бою ставить за reverse-proxy (TLS), запускать в контейнере с ограничением ресурсов,
  без доступа к внутренней сети.

## Подключение на клиенте
Вариант A — указать в `SAAS/assets/js/config.js` в `window.APP_CONFIG`:
```js
shotEndpoint: 'https://shot.example.com/shot'
```
Вариант B — задать глобально или через `<meta>`:
```html
<meta name="shot-endpoint" content="https://shot.example.com/shot">
<meta name="shot-token" content="...">
<script>window.SHOT_CONFIG = { endpoint: 'https://shot.example.com/shot', token: '...' };</script>
```
При заданном endpoint виджет «Замечания» шлёт `fetch(<endpoint>?url=…)` и рисует реальный снимок;
без него работает демо/same-origin режим (iframe + html2canvas).

## Переменные окружения
См. `.env.example`: `PORT`, `SHOT_TOKEN`, `SHOT_ALLOWLIST`, `ALLOWED_ORIGINS`,
`SHOT_ALLOW_PRIVATE`, `SHOT_TIMEOUT_MS`, `SHOT_MAX_WIDTH`, `SHOT_CONCURRENCY`.
