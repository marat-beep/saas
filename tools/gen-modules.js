/* ============================================================
   tools/gen-modules.js — генератор docs/MODULES_CATALOG.md
   Собирает описание всех модулей системы (сгруппировано по контурам/подгруппам)
   из assets/js/catalog.js: назначение, возможности, связи, доступ.
   Предназначен для загрузки в новую сессию, анализа модулей на обновление
   и подготовки лендингов/рекламных описаний.
   Запуск: node tools/gen-modules.js
   ============================================================ */
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
global.window = {};
require(path.join(root, 'assets/js/catalog.js'));
const C = global.window.AppCatalog;

const FN = path.join(root, 'docs', 'MODULES_CATALOG.md');
const AUD = { guest: 'гость', user: 'пользователь', client_admin: 'админ клиента', saas_admin: 'SaaS-админ', developer: 'разработчик' };
const titleById = {}; C.apps.forEach(a => { titleById[a.id] = a.title; });

function esc(s) { return String(s == null ? '' : s).replace(/\|/g, '\\|'); }
function roles(a) { return a.roles && a.roles.length ? a.roles.join(', ') : 'все авторизованные'; }
function connects(a) { return (a.connects || []).map(id => titleById[id] ? titleById[id] + ' (' + id + ')' : id).join('; ') || '—'; }
function features(a) { return (a.features || []).map(f => '- ' + esc(f)).join('\n') || '- —'; }

const lines = [];
lines.push('# Каталог модулей 3DMP Service');
lines.push('');
lines.push('> Сгенерировано `tools/gen-modules.js` из `assets/js/catalog.js` (v' + C.version + ', ' + C.updated + ').');
lines.push('> Назначение файла: **загрузка в новую сессию** для анализа модулей на обновление и подготовки **лендингов/рекламных описаний** модулей.');
lines.push('');
lines.push('Состав: контуров **' + (C.groups || []).length + '**, модулей **' + C.apps.length + '**.');
lines.push('');

// Сводка
lines.push('## Сводка по контурам');
lines.push('');
lines.push('| Контур | Модулей | Ключ |');
lines.push('|---|---|---|');
(C.groups || []).forEach(g => {
  const n = C.apps.filter(a => a.group === g.id).length;
  lines.push('| ' + g.icon + ' ' + esc(g.title) + ' | ' + n + ' | `' + g.id + '` |');
});
const rest = C.apps.filter(a => !a.group);
if (rest.length) lines.push('| Прочее | ' + rest.length + ' | — |');
lines.push('');

lines.push('## Как использовать');
lines.push('- **Анализ на обновление:** берите модуль из списка, сверяйте `purpose`/`features`/`connects` с текущими мирами и ТЗ; фиксируйте задачи в `docs/BACKLOG.md`.');
lines.push('- **Лендинги:** для каждого модуля есть **Назначение** (лид), **Возможности** (список преимуществ) и блок **Рекламный акцент** — готовые формулировки.');
lines.push('- **Навигация:** `id` и `Ссылка` совпадают с каталогом (используются в хабе и гиде).');
lines.push('');

// Разделы по контурам
(C.groups || []).forEach(g => {
  const items = C.apps.filter(a => a.group === g.id);
  if (!items.length) return;
  lines.push('---');
  lines.push('');
  lines.push('## ' + g.icon + ' ' + g.title + ' — ' + items.length);
  if (g.desc) { lines.push(''); lines.push('_' + esc(g.desc) + '_'); }
  lines.push('');

  const subs = (C.subgroups && C.subgroups[g.id]) || null;
  const used = {};
  const emit = (a) => {
    used[a.id] = 1;
    lines.push('### ' + a.icon + ' ' + esc(a.title) + ' — `' + a.id + '`');
    lines.push('- **Ссылка:** `' + a.href + '` · **Аудитория:** ' + (AUD[a.audience] || a.audience || 'user') + (a.guest ? ' · **доступ:** гость' : '') + ' · **Роли:** ' + roles(a));
    if (a.desc) lines.push('- **Кратко:** ' + esc(a.desc));
    if (a.purpose) lines.push('- **Назначение:** ' + esc(a.purpose));
    if (a.in_ || a.out) lines.push('- **Вход/Результат:** ' + esc(a.in_ || '—') + ' → ' + esc(a.out || '—'));
    lines.push('- **Возможности:**');
    lines.push(features(a));
    lines.push('- **Связи:** ' + connects(a));
    lines.push('- **Рекламный акцент:** ' + esc(a.purpose || a.desc || a.title) + '.');
    lines.push('');
  };

  if (subs) {
    subs.forEach(s => {
      const subItems = items.filter(a => s.apps.indexOf(a.id) >= 0);
      if (!subItems.length) return;
      lines.push('### Подгруппа: ' + esc(s.title));
      lines.push('');
      subItems.forEach(emit);
    });
    const other = items.filter(a => !used[a.id]);
    if (other.length) { lines.push('### Прочее в контуре'); lines.push(''); other.forEach(emit); }
  } else {
    items.forEach(emit);
  }
});

// Без группы
if (rest.length) {
  lines.push('---'); lines.push('');
  lines.push('## Прочее — ' + rest.length);
  lines.push('');
  rest.forEach(a => {
    lines.push('### ' + a.icon + ' ' + esc(a.title) + ' — `' + a.id + '`');
    lines.push('- **Ссылка:** `' + a.href + '` · **Роли:** ' + roles(a));
    if (a.desc) lines.push('- **Кратко:** ' + esc(a.desc));
    lines.push('- **Рекламный акцент:** ' + esc(a.purpose || a.desc || a.title) + '.');
    lines.push('');
  });
}

lines.push('---');
lines.push('');
lines.push('_Конец файла. Сгенерировано автоматически: не редактировать вручную — обновляйте `assets/js/catalog.js` и перезапускайте `node tools/gen-modules.js`._');
lines.push('');

fs.writeFileSync(FN, lines.join('\n'), { encoding: 'utf8' });
console.log('gen-modules: записано ' + FN + ' (' + C.apps.length + ' модулей, ' + (C.groups || []).length + ' контуров)');
