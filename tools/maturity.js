/* ============================================================
   tools/maturity.js — зрелость модулей L1–L4 (PROP-17), статически из репозитория.
   L1 «наличие»   — модуль в каталоге и есть apps/<id>/index.html.
   L2 «данные+UX» — вызывает >=1 RPC и имеет поиск/пустое состояние и связи (connects).
   L3 «сценарии»  — встроен в сквозные потоки (connects >= 3).
   L4 «автотесты» — покрыт сквозными проверками (scenario-check / db-smoke).
   Уровень = максимум достигнутого. Экспорт: compute(root) -> { byId, counts, total }.
   ============================================================ */
'use strict';
const fs = require('fs');
const path = require('path');

// Модули, покрытые сквозными сценариями scenario-check/db-smoke (L4).
const TESTED_SCENARIO = new Set([
  'orders', 'bom', 'production', 'planning', 'qc', 'warehouse', 'logistics', 'workflow',
  'kedo', 'docs', 'suppliers', 'hr', 'quality', 'claims', 'procurement', 'mdm', 'tooling',
  'reports', 'service', 'passport', 'economics', 'finance', 'tasks', 'mes'
]);

function compute(root, catalog) {
  let C = catalog || (global.window && global.window.AppCatalog);
  if (!C) {
    global.window = global.window || {};
    require(path.join(root, 'assets/js/catalog.js'));
    C = global.window.AppCatalog;
  }

  const byId = {};
  const counts = { L1: 0, L2: 0, L3: 0, L4: 0 };

  for (const a of C.apps) {
    const dir = path.join(root, 'apps', a.id);
    const hasPage = fs.existsSync(path.join(dir, 'index.html'));
    let js = '';
    try {
      for (const f of fs.readdirSync(dir)) { if (f.endsWith('.js')) js += fs.readFileSync(path.join(dir, f), 'utf8'); }
    } catch (e) {}
    const rpcCount = (js.match(/rpc\(\s*'app_[a-z0-9_]+'/g) || []).length;
    const search = /type="search"|class="search"|id="[a-zA-Z0-9_]*[Qq]"|data-search/.test(js);
    const empty = /Ничего не найдено|нет данных|Загрузка|нет\.|Нет |пока нет|Нет записей|пусто/i.test(js);
    const connects = (a.connects || []).length;

    let L = 1;
    if (hasPage) L = 1;
    if (rpcCount >= 1 && (search || empty) && connects >= 1) L = 2;
    if (connects >= 3) L = 3;
    if (TESTED_SCENARIO.has(a.id)) L = 4;

    const reasons = [];
    reasons.push(hasPage ? 'страница' : 'нет страницы');
    reasons.push('RPC ' + rpcCount);
    reasons.push('UX ' + (search || empty ? 'да' : 'нет'));
    reasons.push('связи ' + connects);
    if (TESTED_SCENARIO.has(a.id)) reasons.push('сценарии');
    byId[a.id] = { L, rpc: rpcCount, connects, search, empty, reasons: reasons.join(' · ') };
    counts['L' + L]++;
  }
  return { byId, counts, total: C.apps.length };
}

module.exports = { compute, TESTED_SCENARIO };
