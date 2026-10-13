#!/usr/bin/env node
/* ============================================================
   3DMP Service · tools/import-norms-wiki.js
   I: перенос вики из внешнего проекта «Нормирование PRO» (ТОЛЬКО ЧТЕНИЕ).
   Читает <root>/../НОРМ_РАЗРАБ/norms-wiki.js, извлекает BUILTIN-статьи,
   чистит HTML и генерирует supabase/migrations/0230_norms_wiki.sql
   (идемпотентные вставки в app_knowledge). Источник НЕ изменяется.
   Запуск: node tools/import-norms-wiki.js
   ============================================================ */
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const src = path.resolve(root, '..', 'НОРМ_РАЗРАБ', 'norms-wiki.js');
const out = path.join(root, 'supabase', 'migrations', '0230_norms_wiki.sql');

function stripHtml(s) {
  return String(s || '')
    .replace(/<br\s*\/?>/gi, ' ')
    .replace(/<\/(p|li|h3|h4|h5|tr|div)>/gi, ' ')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&mdash;/g, '—').replace(/&ndash;/g, '–')
    .replace(/\s+/g, ' ').trim();
}
function q(s) { return "'" + String(s == null ? '' : s).replace(/'/g, "''") + "'"; }

const text = fs.readFileSync(src, 'utf8');
const start = text.indexOf('const BUILTIN = [');
if (start < 0) { console.error('BUILTIN not found'); process.exit(1); }
const chunk = text.slice(start);
const re = /\{\s*key:\s*'([^']*)',\s*section:\s*'([^']*)',\s*title:\s*'([^']*)',\s*body:\s*`([\s\S]*?)`\s*\}/g;
const items = [];
let m;
while ((m = re.exec(chunk))) {
  items.push({ key: m[1], section: m[2], title: m[3], body: stripHtml(m[4]) });
}
if (!items.length) { console.error('no items parsed'); process.exit(1); }

const lines = [];
lines.push('-- ============================================================');
lines.push('-- 3DMP Service · 0230_norms_wiki.sql');
lines.push('-- I: перенос вики внешнего проекта «Нормирование PRO» в базу знаний');
lines.push('-- 3DMP Service (app_knowledge, глобальные статьи). Источник — только чтение.');
lines.push('-- Генератор: tools/import-norms-wiki.js. Идемпотентно. Зависит от 0001..0229.');
lines.push('-- ============================================================');
lines.push('');
items.forEach((it) => {
  const category = 'Нормирование PRO — ' + it.section;
  const tags = ('нормирование PRO wiki ' + it.key + ' ' + it.section).toLowerCase();
  lines.push('insert into public.app_knowledge (tenant_id, category, question, answer, tags)');
  lines.push('select null, ' + q(category) + ', ' + q(it.title) + ', ' + q(it.body) + ', ' + q(tags));
  lines.push('where not exists (select 1 from public.app_knowledge k where k.question = ' + q(it.title) + ');');
  lines.push('');
});
fs.writeFileSync(out, lines.join('\n'), 'utf8');
console.log(`import-norms-wiki: статей ${items.length} -> ${path.relative(root, out)}`);
