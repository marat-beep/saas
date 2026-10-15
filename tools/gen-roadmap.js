/* ============================================================
   tools/gen-roadmap.js — генератор docs/ROADMAP.md из tools/proposals.js.
   Единый «План изменений»: волны R1–R3, приоритеты, контуры, DoD.
   Запуск: node tools/gen-roadmap.js
   ============================================================ */
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const ITEMS = require(path.join(root, 'tools', 'proposals.js'));
const BIZ = ITEMS.BIZ || {};
const META = ITEMS.META || { waves: {} };
const OUT = path.join(root, 'docs', 'ROADMAP.md');

const WAVE_TITLE = { R1: 'Приоритетные контуры', R2: 'Поперечные и надёжность', R3: 'Гигиена и развитие', R4: 'По сравнению с рынком (ERP/MES/PLM/EAM)' };
const WAVES = ['R1', 'R2', 'R3', 'R4'];
const PRIO_TITLE = { P1: 'высокий', P2: 'средний', P3: 'низкий' };
const EFF = { S: 'S (малая)', M: 'M (средняя)', L: 'L (крупная)' };

function byWave(w) { return ITEMS.filter(x => x.wave === w); }
const total = ITEMS.length;
const done = ITEMS.filter(x => x.status === 'done').length;

let md = '';
md += '# План изменений 3DMP Service (Roadmap)\n\n';
md += '_Автогенерация `tools/gen-roadmap.js` из `tools/proposals.js` — единый источник правды. Не редактировать вручную._\n\n';
md += 'Дата: ' + new Date().toISOString().slice(0, 10) + '. Всего пунктов: **' + total + '** (выполнено: ' + done + ').\n\n';

md += '## Принципы и порядок\n\n';
md += '- Приоритетные контуры заказчика: **' + [BIZ.prod, BIZ.econ, BIZ.qa].filter(Boolean).join(' · ') + '**.\n';
md += '- Порядок волн: **R1 → R2 → R3** — сначала единый UX/сценарии приоритетных контуров, затем надёжность/API/метрика, затем гигиена и развитие уникальных фич.\n';
md += '- Единые точки правды: план и журнал — `docs/BACKLOG.md`; этот план — `docs/ROADMAP.md` + `tools/proposals.js`; дашборд — `modules.html`.\n';
md += '- Каждый пункт закрывается по DoD и отражается в журнале BACKLOG §5.\n\n';

md += '## Сводка\n\n';
md += '| Волна | Пунктов | P1 | P2 | P3 |\n|---|---|---|---|---|\n';
['R1', 'R2', 'R3', 'R4'].forEach(w => {
  const a = byWave(w);
  md += '| ' + w + ' — ' + (WAVE_TITLE[w] || '') + ' | ' + a.length + ' | ' + a.filter(x => x.prio === 'P1').length + ' | ' + a.filter(x => x.prio === 'P2').length + ' | ' + a.filter(x => x.prio === 'P3').length + ' |\n';
});
md += '\n';

['R1', 'R2', 'R3', 'R4'].forEach(w => {
  const a = byWave(w);
  if (!a.length) return;
  md += '## ' + w + ' — ' + (WAVE_TITLE[w] || '') + '\n\n';
  a.forEach(it => {
    const biz = (it.business || []).filter(Boolean).join(', ');
    const mods = (it.modules || []).filter(Boolean).join(', ');
    md += '### ' + it.id + ' · ' + it.title + (it.status === 'done' ? ' ✅' : '') + '\n\n';
    md += '- **Приоритет:** ' + it.prio + ' (' + (PRIO_TITLE[it.prio] || '') + ') · **Область:** ' + it.area + ' · **Оценка:** ' + (EFF[it.effort] || it.effort) + '\n';
    md += '- **Контуры:** ' + (biz || '—') + '\n';
    md += '- **Модули:** ' + (mods || '—') + '\n';
    md += '- **Проблема:** ' + it.problem + '\n';
    md += '- **Что сделать:** ' + it.action + '\n';
    md += '- **DoD:** ' + (it.dod || '—') + '\n';
    md += '- **Обоснование:** ' + (it.evidence || '—') + '\n\n';
  });
});

md += '---\n\n';
md += 'Источник данных: `tools/proposals.js`. Раздел «Предложения по изменениям» в дашборде (`modules.html`) строится из этого же файла.\n';

fs.writeFileSync(OUT, md, { encoding: 'utf8' });
console.log('gen-roadmap: записано ' + OUT + ' (' + total + ' пунктов; R1 ' + byWave('R1').length + ' / R2 ' + byWave('R2').length + ' / R3 ' + byWave('R3').length + ' / R4 ' + byWave('R4').length + ')');
