/* ============================================================
   3DMP · backend-example/server.js — сервис снимков «/shot».
   Node + Express + Playwright (Chromium).
   Назначение: делать скриншоты внешних сайтов для модуля «Замечания к странице»
   (assets/js/page-remarks.js, screenshot.client.js).

   Безопасность:
     * Bearer-токен (SHOT_TOKEN) на /shot;
     * allow-list доменов (SHOT_ALLOWLIST);
     * анти-SSRF: запрет приватных/служебных IP (loopback, link-local, RFC1918,
       CGNAT, cloud-metadata 169.254.169.254, IPv6 ULA/link-local), проверка DNS и
       перехват запросов внутри страницы (редиректы/подресурсы);
     * только http/https, ограничение длины URL, ширины и таймаута;
     * ограничение параллельных снимков (семафор);
     * CORS только для разрешённых Origin.

   Запуск: см. README.md. Конфигурация — через переменные окружения (.env.example).
   ============================================================ */
'use strict';

const dns = require('dns').promises;
const net = require('net');
const express = require('express');
const { chromium } = require('playwright');

/* ---------- конфигурация ---------- */
const PORT = parseInt(process.env.PORT || '8787', 10);
const SHOT_TOKEN = (process.env.SHOT_TOKEN || '').trim();
const ALLOWLIST = (process.env.SHOT_ALLOWLIST || '')
  .split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '')
  .split(',').map((s) => s.trim()).filter(Boolean);
const ALLOW_PRIVATE = String(process.env.SHOT_ALLOW_PRIVATE || '').toLowerCase() === 'true';
const NAV_TIMEOUT = parseInt(process.env.SHOT_TIMEOUT_MS || '20000', 10);
const MAX_WIDTH = parseInt(process.env.SHOT_MAX_WIDTH || '1920', 10);
const MAX_CONCURRENCY = Math.max(1, parseInt(process.env.SHOT_CONCURRENCY || '2', 10));
const MAX_URL_LEN = 2048;

/* ---------- анти-SSRF: проверка IP ---------- */
function ipv4ToInt(ip) {
  return ip.split('.').reduce((acc, o) => (acc << 8) + (parseInt(o, 10) & 255), 0) >>> 0;
}
function inRange(ip, cidr, bits) {
  const mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
  return (ipv4ToInt(ip) & mask) === (ipv4ToInt(cidr) & mask);
}
const V4_BLOCKS = [
  ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8],
  ['169.254.0.0', 16], ['172.16.0.0', 12], ['192.0.0.0', 24], ['192.0.2.0', 24],
  ['192.168.0.0', 16], ['198.18.0.0', 15], ['198.51.100.0', 24], ['203.0.113.0', 24],
  ['224.0.0.0', 4], ['240.0.0.0', 4], ['255.255.255.255', 32]
];
function isPrivateIp(ip) {
  const fam = net.isIP(ip);
  if (fam === 4) return V4_BLOCKS.some(([cidr, bits]) => inRange(ip, cidr, bits));
  if (fam === 6) {
    const h = ip.toLowerCase();
    if (h === '::1' || h === '::') return true;
    if (h.startsWith('fe80:') || h.startsWith('fc') || h.startsWith('fd')) return true;
    if (h.startsWith('ff')) return true;
    if (h.startsWith('2001:db8:')) return true;
    const mapped = h.match(/^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/);
    if (mapped) return isPrivateIp(mapped[1]);
    return false;
  }
  return true; // не распознали — считаем небезопасным
}
function hostAllowed(host) {
  if (!ALLOWLIST.length) return true;
  return ALLOWLIST.some((d) => host === d || host.endsWith('.' + d));
}
async function checkUrl(rawUrl) {
  if (!rawUrl || rawUrl.length > MAX_URL_LEN) throw httpError(400, 'Некорректный или слишком длинный URL');
  let u;
  try { u = new URL(rawUrl); } catch (e) { throw httpError(400, 'Некорректный URL'); }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') throw httpError(400, 'Разрешены только http/https');
  const host = u.hostname.toLowerCase();
  if (!hostAllowed(host)) throw httpError(403, 'Домен не входит в allow-list');
  if (!ALLOW_PRIVATE) {
    const addrs = await dns.lookup(host, { all: true }).catch(() => null);
    if (!addrs || !addrs.length) throw httpError(400, 'Не удалось разрешить домен');
    if (addrs.some((a) => isPrivateIp(a.address))) throw httpError(403, 'Адрес ведёт в приватную/служебную зону');
  }
  return u.href;
}
function httpError(status, message) { const e = new Error(message); e.status = status; return e; }

/* ---------- семафор ---------- */
function createSemaphore(max) {
  let active = 0; const queue = [];
  function next() {
    if (active >= max || !queue.length) return;
    active++; const { fn, res, rej } = queue.shift();
    Promise.resolve().then(fn).then(
      (v) => { active--; next(); res(v); },
      (e) => { active--; next(); rej(e); }
    );
  }
  return function run(fn) {
    return new Promise((res, rej) => { queue.push({ fn, res, rej }); next(); });
  };
}
const runShot = createSemaphore(MAX_CONCURRENCY);

/* ---------- CORS ---------- */
function applyCors(req, res) {
  const origin = req.headers.origin;
  if (!origin) return;
  if (ALLOWED_ORIGINS.includes('*')) { res.setHeader('Access-Control-Allow-Origin', '*'); return; }
  if (ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
}
function auth(req, res) {
  if (!SHOT_TOKEN) return true; // токен не задан — режим разработки
  const h = req.headers.authorization || '';
  const m = h.match(/^Bearer\s+(.+)$/i);
  if (m && m[1] === SHOT_TOKEN) return true;
  res.status(401).json({ error: 'Не авторизовано' });
  return false;
}

/* ---------- приложение ---------- */
let browser = null;
const app = express();
app.disable('x-powered-by');

app.use((req, res, next) => { applyCors(req, res); if (req.method === 'OPTIONS') return res.sendStatus(204); next(); });

app.get('/healthz', (req, res) => res.json({ ok: true, allowlist: ALLOWLIST, concurrency: MAX_CONCURRENCY }));

app.get('/shot', async (req, res) => {
  if (!auth(req, res)) return;
  if (!browser) return res.status(503).json({ error: 'Браузер не готов' });
  let target;
  try { target = await checkUrl(String(req.query.url || '')); }
  catch (e) { return res.status(e.status || 400).json({ error: e.message }); }

  const width = Math.min(MAX_WIDTH, Math.max(320, parseInt(req.query.width, 10) || 1280));
  const fullPage = String(req.query.fullPage || 'true') === 'true';

  try {
    const png = await runShot(async () => {
      const context = await browser.newContext({
        viewport: { width, height: 900 },
        userAgent: '3DMP-Shot/1.0 (+https://sapfir.eu/saas/)',
        ignoreHTTPSErrors: true
      });
      try {
        // анти-SSRF: блокируем редиректы/подресурсы в приватную зону
        if (!ALLOW_PRIVATE) {
          await context.route('**/*', async (route) => {
            try {
              const rh = new URL(route.request().url()).hostname.toLowerCase();
              if (!hostAllowed(rh)) return route.abort();
              const addrs = await dns.lookup(rh, { all: true }).catch(() => null);
              if (addrs && addrs.some((a) => isPrivateIp(a.address))) return route.abort();
            } catch (e) { /* относительно-адресные схемы пропускаем */ }
            return route.continue();
          });
        }
        const page = await context.newPage();
        page.setDefaultNavigationTimeout(NAV_TIMEOUT);
        await page.goto(target, { waitUntil: 'networkidle', timeout: NAV_TIMEOUT });
        return await page.screenshot({ type: 'png', fullPage, animations: 'disabled' });
      } finally {
        await context.close().catch(() => {});
      }
    });
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'private, max-age=60');
    return res.end(png);
  } catch (e) {
    const msg = String(e && e.message || e);
    if (/Timeout|timeout/i.test(msg)) return res.status(504).json({ error: 'Страница не успела загрузиться' });
    return res.status(502).json({ error: 'Не удалось сделать снимок' });
  }
});

/* ---------- запуск ---------- */
(async () => {
  browser = await chromium.launch({ headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  app.listen(PORT, () => {
    // eslint-disable-next-line no-console
    console.log('3DMP shot server on :' + PORT + ' | token=' + (SHOT_TOKEN ? 'on' : 'off') +
      ' | allowlist=' + (ALLOWLIST.length ? ALLOWLIST.join(',') : 'any') +
      ' | allowPrivate=' + ALLOW_PRIVATE);
  });
})().catch((e) => { console.error('Не удалось запустить shot-сервер:', e); process.exit(1); });

process.on('SIGINT', async () => { if (browser) await browser.close().catch(() => {}); process.exit(0); });
process.on('SIGTERM', async () => { if (browser) await browser.close().catch(() => {}); process.exit(0); });
