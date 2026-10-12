#!/usr/bin/env node
/* ============================================================
   3DMP Service · tools/catalog-connects.js
   U5: анализ связей каталога (connects) на двусторонность.
   Выводит: всего модулей/связей; асимметричные связи (A→B без B→A).
   Запуск: node tools/catalog-connects.js [--json]
   ============================================================ */
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const src = fs.readFileSync(path.join(root, 'assets', 'js', 'catalog.js'), 'utf8');

const chunks = src.split(/\n {4}\{\n/);
const map = {};
for (const ch of chunks) {
  const idm = ch.match(/\bid:\s*'([a-zA-Z0-9_]+)'/);
  const cm = ch.match(/connects:\s*\[([^\]]*)\]/);
  if (!idm || !cm) continue;
  const id = idm[1];
  if (!cm) continue;
  const ids = cm[1].split(',').map(s => s.trim().replace(/^['"]|['"]$/g, '')).filter(Boolean);
  if (map[id]) continue; // первое вхождение (основная запись)
  map[id] = ids;
}
const ids = Object.keys(map);
const missing = [];
let total = 0;
for (const a of ids) {
  for (const b of map[a]) {
    if (!map[b]) continue; // битая ссылка — ловится audit.ps1
    total++;
    if (map[b].indexOf(a) < 0) missing.push([a, b]);
  }
}
const out = { modules: ids.length, links: total, asymmetric: missing.length, pairs: missing };
if (process.argv.includes('--json')) {
  console.log(JSON.stringify(out, null, 2));
} else if (process.argv.includes('--md')) {
  const inDeg = {};
  ids.forEach(a => map[a].forEach(b => { if (map[b]) inDeg[b] = (inDeg[b] || 0) + 1; }));
  const hubs = Object.keys(inDeg).sort((x, y) => inDeg[y] - inDeg[x]).slice(0, 15);
  const bySrc = {};
  missing.forEach(p => { (bySrc[p[0]] = bySrc[p[0]] || []).push(p[1]); });
  let md = '# Связи модулей каталога (connects) — семантика и односторонние связи (U5)\n\n';
  md += `_Автогенерация \`tools/catalog-connects.js --md\`. Модулей: **${out.modules}**; связей: **${out.links}**; односторонних (A→B без B→A): **${out.asymmetric}**._\n\n`;
  md += '## Семантика\n\n';
  md += '`connects` в `assets/js/catalog.js` — это **направленные** связи: «модуль передаёт данные / ссылается на другой модуль». Поэтому отсутствие обратной связи — норма (а не дефект), кроме явно парных сценариев. Аудит `tools/audit.ps1` проверяет только **валидность** id (битые связи = 0). Односторонние связи здесь перечислены для прозрачности; часть из них — «хаб-модули» (в них ссылаются многие, сами ссылаются точечно).\n\n';
  md += '## Хаб-модули (по числу входящих ссылок)\n\n';
  md += '| Модуль | Входящих |\n|---|---|\n';
  hubs.forEach(h => { md += `| \`${h}\` | ${inDeg[h]} |\n`; });
  md += '\n## Односторонние связи по источникам\n\n';
  Object.keys(bySrc).sort().forEach(s => { md += `- \`${s}\` → ${bySrc[s].map(x => '`' + x + '`').join(', ')}\n`; });
  md += '\n> Если для парного сценария нужна обратная связь — добавляйте id в `connects` обоих модулей (только валидные id).\n';
  fs.writeFileSync(path.join(root, 'docs', 'CONNECTS.md'), md, 'utf8');
  console.log(`Модулей: ${out.modules}; связей: ${out.links}; односторонних: ${out.asymmetric} -> docs/CONNECTS.md`);
} else {
  console.log(`Модулей: ${out.modules}; связей: ${out.links}; односторонних: ${out.asymmetric}`);
  missing.forEach(p => console.log(`  ${p[0]} → ${p[1]}`));
}
