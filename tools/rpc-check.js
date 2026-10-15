/* ============================================================
   tools/rpc-check.js — проверка: все RPC, вызываемые из UI (apps + assets/js),
   реально определены в миграциях. Ловит опечатки/переименования.
   Запуск: node tools/rpc-check.js  (exit 1 при отсутствующих функциях)
   ============================================================ */
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');

function walk(dir, acc) {
  if (!fs.existsSync(dir)) return acc;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, acc);
    else if (/\.(js|html)$/.test(e.name)) acc.push(p);
  }
  return acc;
}

const files = walk(path.join(root, 'apps'), []).concat(walk(path.join(root, 'assets', 'js'), []));
const used = new Map();
for (const f of files) {
  const t = fs.readFileSync(f, 'utf8');
  for (const m of t.matchAll(/rpc\(\s*'(app_[a-z0-9_]+)'/g)) if (!used.has(m[1])) used.set(m[1], f);
}

const defined = new Set();
const md = path.join(root, 'supabase', 'migrations');
for (const f of fs.readdirSync(md)) {
  const t = fs.readFileSync(path.join(md, f), 'utf8');
  for (const m of t.matchAll(/create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)/gi)) defined.add(m[1]);
}

const missing = [...used.keys()].filter((x) => !defined.has(x)).sort();
console.log('rpc-check: вызывается из UI ' + used.size + ', определено в миграциях ' + defined.size + ', отсутствует ' + missing.length);
for (const x of missing) console.log('  MISSING: ' + x + '  (используется в ' + path.relative(root, used.get(x)).replace(/\\/g, '/') + ')');
process.exit(missing.length ? 1 : 0);
