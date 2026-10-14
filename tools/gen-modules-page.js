/* ============================================================
   tools/gen-modules-page.js — генератор modules.html (корень воркспейса, над SAAS/)
   «Дашборд готовности модулей»: описание возможностей (catalog.js) +
   аналитика (modules-analysis.js) + визуализация (SVG, offline):
   гейдж общей готовности, кольцевые диаграммы (статус/контуры/приоритет),
   карта модулей по статусу, раздел «Осталось сделать», фильтры.
   Запуск: node tools/gen-modules-page.js
   ============================================================ */
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
global.window = {};
require(path.join(root, 'assets/js/catalog.js'));
const C = global.window.AppCatalog;
const A = require(path.join(root, 'tools', 'modules-analysis.js'));
const PROPOSALS = require(path.join(root, 'tools', 'proposals.js'));

const OUT = path.resolve(root, '..', 'modules.html');
const AUD = { guest: 'гость', user: 'пользователь', client_admin: 'админ клиента', saas_admin: 'SaaS-админ', developer: 'разработчик' };
const PRI = { high: 'высокий', mid: 'средний', low: 'низкий' };
const titleById = {};
C.apps.forEach(a => { titleById[a.id] = a.title; });
const groupById = {};
(C.groups || []).forEach(g => { groupById[g.id] = g; });

function esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
function attr(s) { return esc(s).replace(/\n/g, ' '); }
function stars(u) { u = Math.max(1, Math.min(5, u | 0)); return '★'.repeat(u) + '☆'.repeat(5 - u); }
function roles(a) { return a.roles && a.roles.length ? a.roles.join(', ') : 'все авторизованные'; }
function isDoneItem(s) { return /✅/.test(String(s || '')); }

/* ---------- статус/готовность модуля ---------- */
function stOf(an) {
  if (!an) return 'none';
  if (an.partial) return 'partial';
  return (an.wave || an.done) ? 'done' : 'none';
}
function planRemain(an) { return an && an.plan ? an.plan.filter(x => !isDoneItem(x)).length : 0; }
function planDone(an) { return an && an.plan ? an.plan.filter(x => isDoneItem(x)).length : 0; }
function scoreOf(an) {
  const st = stOf(an);
  if (st === 'done') return 100;
  if (st === 'none') return 0;
  const total = (an.plan || []).length;
  if (!total) return 50;
  return Math.round(planDone(an) / total * 100);
}
const ST_LABEL = { done: '✅ реализовано', partial: '◐ частично', none: 'без статуса' };
const ST_COLOR = { done: '#10b981', partial: '#f59e0b', none: '#94a3b8' };

/* ---------- агрегаты ---------- */
const mods = C.apps.map(a => {
  const an = A[a.id] || null;
  return { a, an, status: stOf(an), remain: planRemain(an), score: scoreOf(an), group: a.group || '', pri: an ? an.pri : '' };
});
const stats = { n: C.apps.length, groups: (C.groups || []).length, uSum: 0, uAvg: 0, merges: 0, pri: { high: 0, mid: 0, low: 0 }, missing: [], status: { done: 0, partial: 0, none: 0 } };
C.apps.forEach(a => {
  const an = A[a.id];
  if (!an) { stats.missing.push(a.id); return; }
  stats.uSum += an.u;
  if (an.merge) stats.merges++;
  stats.pri[an.pri] = (stats.pri[an.pri] || 0) + 1;
});
stats.uAvg = (stats.uSum / C.apps.length).toFixed(1);
mods.forEach(m => { stats.status[m.status]++; });
const overall = Math.round(mods.reduce((s, m) => s + m.score, 0) / mods.length);
const remainTotal = mods.filter(m => m.status !== 'done').reduce((s, m) => s + m.remain, 0);
const waveList = Array.from(new Set(C.apps.map(a => A[a.id] && A[a.id].wave).filter(Boolean))).sort((x, y) => (parseInt(x.slice(1), 10) || 0) - (parseInt(y.slice(1), 10) || 0));

/* ---------- SVG-диаграммы (offline) ---------- */
function donut(segs, size) {
  size = size || 132; const r = size / 2 - 12, c = size / 2, circ = 2 * Math.PI * r;
  const tot = segs.reduce((s, x) => s + x.v, 0) || 1; let off = 0;
  const arcs = segs.map(s => {
    const len = circ * (s.v / tot);
    const el = '<circle cx="' + c + '" cy="' + c + '" r="' + r + '" fill="none" stroke="' + s.c + '" stroke-width="18" stroke-dasharray="' + len.toFixed(2) + ' ' + (circ - len).toFixed(2) + '" stroke-dashoffset="' + (-off).toFixed(2) + '" transform="rotate(-90 ' + c + ' ' + c + ')"></circle>';
    off += len; return el;
  }).join('');
  return '<svg viewBox="0 0 ' + size + ' ' + size + '" width="' + size + '" height="' + size + '" role="img">' + arcs + '</svg>';
}
function legend(segs) {
  return '<div class="dlegend">' + segs.map(s => '<span><i style="background:' + s.c + '"></i>' + esc(s.l) + ' <b>' + s.v + '</b></span>').join('') + '</div>';
}
function kpiDonut(title, segs, size) {
  return '<div class="dcard"><h4>' + esc(title) + '</h4><div class="drow">' + donut(segs, size) + legend(segs) + '</div></div>';
}
const R = 54, CIRC = 2 * Math.PI * R;
const gauge = '<div class="gauge"><svg viewBox="0 0 132 132" width="150" height="150" role="img" aria-label="Готовность">' +
  '<circle cx="66" cy="66" r="' + R + '" fill="none" stroke="#e2e8f0" stroke-width="16"></circle>' +
  '<circle id="gaugeArc" cx="66" cy="66" r="' + R + '" fill="none" stroke="#10b981" stroke-width="16" stroke-linecap="round" stroke-dasharray="' + (CIRC * overall / 100).toFixed(2) + ' ' + CIRC.toFixed(2) + '" transform="rotate(-90 66 66)"></circle>' +
  '</svg><div class="gauge-c"><b id="gaugePct">' + overall + '%</b><span>готовность</span></div></div>';

const statusSegs = [
  { v: stats.status.done, c: ST_COLOR.done, l: '✅' },
  { v: stats.status.partial, c: ST_COLOR.partial, l: '◐' },
  { v: stats.status.none, c: ST_COLOR.none, l: 'без статуса' }
];
const groupSegs = (C.groups || []).map((g, i) => ({ v: C.apps.filter(a => a.group === g.id).length, c: ['#10b981', '#0ea5e9', '#6366f1', '#f59e0b', '#ef4444', '#14b8a6', '#a855f7', '#84cc16', '#f97316'][i % 9], l: g.title }));
const priSegs = [
  { v: stats.pri.high, c: '#dc2626', l: 'высокий' },
  { v: stats.pri.mid, c: '#d97706', l: 'средний' },
  { v: stats.pri.low, c: '#0ea5e9', l: 'низкий' }
];

/* карта модулей */
function mapTile(m) {
  const g = groupById[m.group];
  return '<a class="map-tile" href="#m-' + attr(m.a.id) + '" data-id="' + attr(m.a.id) + '" data-status="' + m.status + '" data-score="' + m.score + '" style="border-color:' + ST_COLOR[m.status] + '" title="' + attr(m.a.title + ' · ' + (ST_LABEL[m.status] || '') + ' · готовность ' + m.score + '%' + (m.remain ? ' · осталось ' + m.remain : '')) + '">' +
    '<span class="mt-ic">' + esc(m.a.icon || '•') + '</span><span class="mt-t">' + esc(m.a.title) + '</span>' +
    '<span class="mt-s" style="background:' + ST_COLOR[m.status] + '">' + m.score + '%</span></a>';
}
const mapHtml = (C.groups || []).map(g => {
  const items = mods.filter(m => m.group === g.id);
  if (!items.length) return '';
  return '<div class="map-grp"><div class="map-grp-h">' + esc(g.icon || '') + ' ' + esc(g.title) + ' <span class="cnt">' + items.length + '</span></div>' +
    '<div class="map-grid">' + items.map(mapTile).join('') + '</div></div>';
}).join('');

/* ---------- карточка модуля ---------- */
function card(m) {
  const a = m.a;
  const an = m.an || { u: 3, why: 'Аналитика не задана.', merge: '', add: [], pri: 'mid', plan: [] };
  const connects = (a.connects || []).map(id => {
    const t = titleById[id];
    return '<span class="chip" title="' + attr(id) + '">' + esc(t ? t : id) + '</span>';
  }).join('') || '<span class="muted">—</span>';
  const feats = (a.features || []).map(f => '<li>' + esc(f) + '</li>').join('') || '<li class="muted">—</li>';
  const adds = (an.add || []).map(f => '<li>' + esc(f) + '</li>').join('') || '<li class="muted">—</li>';
  const plan = (an.plan || []).map(f => '<li class="' + (isDoneItem(f) ? 'pdone' : 'prem') + '">' + esc(f) + '</li>').join('') || '<li class="muted">—</li>';
  const text = [a.title, a.id, a.desc, a.purpose, (a.features || []).join(' '), (a.connects || []).join(' '), an.why, an.merge, (an.add || []).join(' '), (an.plan || []).join(' ')].join(' ').toLowerCase();

  const mergeCls = an.merge ? 'has' : 'none';
  const st = m.status;
  const stBadge = st === 'done' ? '<span class="tag s-done">✅ реализовано</span>' : st === 'partial' ? '<span class="tag s-partial">◐ частично · осталось ' + m.remain + '</span>' : '<span class="tag s-none">без статуса</span>';
  return `
<details class="mc" id="m-${attr(a.id)}" data-id="${attr(a.id)}" data-group="${attr(a.group || '')}" data-pri="${attr(an.pri)}" data-u="${an.u}" data-merge="${an.merge ? 1 : 0}" data-wave="${attr(an.wave || '')}" data-status="${st}" data-score="${m.score}" data-remain="${m.remain}" data-text="${attr(text)}">
  <summary>
    <span class="mc-ic">${esc(a.icon || '•')}</span>
    <span class="mc-tt"><b>${esc(a.title)}</b><small>${esc(a.id)}${a.desc ? ' · ' + esc(a.desc) : ''}</small></span>
    <span class="badges">
      <span class="b b-score" style="background:${ST_COLOR[st]}" title="Готовность модуля">${m.score}%</span>
      <span class="b b-u" title="Полезность ${an.u}/5">${stars(an.u)}</span>
      <span class="b b-pri pri-${attr(an.pri)}" title="Приоритет обновления">обновление: ${esc(PRI[an.pri] || an.pri)}</span>
    </span>
    <span class="chev">⌄</span>
  </summary>
  <div class="mc-body">
    <div class="mc-meta">
      <span class="tag">Аудитория: ${esc(AUD[a.audience] || a.audience || 'пользователь')}${a.guest ? ' · доступ: гость' : ''}</span>
      <span class="tag">Роли: ${esc(roles(a))}</span>
      ${an.wave ? '<span class="tag wave" title="Волна плана обновления v5">план v5: ' + esc(an.wave) + '</span>' : ''}
      ${stBadge}
      <a class="tag link" href="${attr(a.href)}" target="_blank" rel="noopener">Открыть модуль →</a>
    </div>
    ${a.purpose ? '<p class="mc-purpose">' + esc(a.purpose) + '</p>' : ''}
    <div class="mc-cols">
      <div class="mc-col"><h4>Возможности</h4><ul class="feat">${feats}</ul></div>
      <div class="mc-col"><h4>Связи с модулями</h4><div class="chips">${connects}</div></div>
    </div>
    <div class="analysis">
      <div class="an an-u"><h4>Полезность</h4><div class="score"><span class="s-val">${an.u}/5</span><span class="s-stars">${stars(an.u)}</span></div><p>${esc(an.why)}</p></div>
      <div class="an an-merge ${mergeCls}"><h4>Объединение</h4><p>${an.merge ? esc(an.merge) : 'Объединение не требуется.'}</p></div>
      <div class="an an-add"><h4>Наполнение функциями</h4><ul>${adds}</ul></div>
      <div class="an an-plan"><h4>План обновления <span class="pri-dot pri-${attr(an.pri)}">${esc(PRI[an.pri] || an.pri)}</span> <span class="muted">· осталось ${m.remain}</span></h4><ol>${plan}</ol></div>
    </div>
  </div>
</details>`;
}

/* ---------- разделы ---------- */
const sections = [];
(C.groups || []).forEach(g => {
  const items = mods.filter(m => m.group === g.id);
  if (!items.length) return;
  const used = {};
  const subHtml = [];
  const subs = (C.subgroups && C.subgroups[g.id]) || null;
  const emit = m => { used[m.a.id] = 1; return card(m); };
  if (subs) {
    subs.forEach(s => {
      const si = items.filter(m => s.apps.indexOf(m.a.id) >= 0);
      if (!si.length) return;
      subHtml.push('<h3 class="sub">' + esc(s.title) + ' <span class="cnt">' + si.length + '</span></h3>' + si.map(emit).join(''));
    });
    const other = items.filter(m => !used[m.a.id]);
    if (other.length) subHtml.push('<h3 class="sub">Прочее в контуре <span class="cnt">' + other.length + '</span></h3>' + other.map(emit).join(''));
  } else {
    subHtml.push(items.map(emit).join(''));
  }
  sections.push(`
<section class="grp" data-group="${attr(g.id)}">
  <header class="grp-h"><span class="grp-ic">${esc(g.icon || '')}</span><h2>${esc(g.title)}</h2><span class="cnt">${items.length}</span></header>
  ${g.desc ? '<p class="grp-d">' + esc(g.desc) + '</p>' : ''}
  ${subHtml.join('\n')}
</section>`);
});

/* ---------- «Осталось сделать» ---------- */
const remainPanel = (() => {
  const parts = mods.filter(m => m.status === 'partial').map(m => {
    const items = (m.an.plan || []).filter(x => !isDoneItem(x));
    return '<div class="rem"><div class="rem-h"><a href="#m-' + attr(m.a.id) + '" data-target="' + attr(m.a.id) + '">' + esc(m.a.icon || '') + ' <b>' + esc(m.a.title) + '</b></a>' +
      '<span class="tag s-partial">осталось ' + items.length + ' · готовность ' + m.score + '%</span></div><ul>' +
      items.map(x => '<li>' + esc(x) + '</li>').join('') + '</ul></div>';
  });
  return '<details class="panel" open><summary class="panel-sum"><b>Осталось сделать</b> <span class="cnt">' + (stats.status.partial) + ' модулей ◐</span> <span class="muted">· ' + remainTotal + ' пунктов плана без ✅</span></summary><div class="rem-grid" style="margin-top:12px">' + (parts.join('') || '<span class="muted">Нет модулей с остатком.</span>') + '</div></details>';
})();

/* ---------- сводка / кластеры объединения ---------- */
const mergeList = C.apps.filter(a => A[a.id] && A[a.id].merge)
  .map(a => `<a class="mchip" href="#m-${attr(a.id)}" data-target="${attr(a.id)}"><b>${esc(a.title)}</b><span>→ ${esc(A[a.id].merge)}</span></a>`)
  .join('');
const priModules = { high: [], mid: [], low: [] };
C.apps.forEach(a => { const an = A[a.id]; if (an && priModules[an.pri]) priModules[an.pri].push(a); });
function priRow(k, label) {
  const arr = priModules[k] || [];
  return `<div class="prirow"><span class="b b-pri pri-${k}">${label} · ${arr.length}</span><div class="chips">${arr.map(a => `<a class="chip" href="#m-${attr(a.id)}" data-target="${attr(a.id)}">${esc(a.title)}</a>`).join('')}</div></div>`;
}

/* ---------- прототипы eco/apps → реализация ---------- */
const PROTO = [
  ['A1 Калькулятор заказа; B21/B25/B26/B28/B34', 'calc, orders'],
  ['A2 Мастер подбора технологии', 'assistant, calc'],
  ['A3 Кабинет заказчика', 'client'],
  ['A4/B29 Заявка на сервис / АРМ инженера', 'service, dealer'],
  ['A6 Реверс-инжиниринг', 'reverse'],
  ['A7 Портал закупок', 'supplier'],
  ['A8 Конфигуратор спец-технологий', 'config'],
  ['A9 Заказ документации', 'docbuilder, docs'],
  ['A10 Измерения как услуга', 'quality, qc'],
  ['A11 Поставки оборудования', 'equipment'],
  ['A13 Отраслевые решения', 'industry'],
  ['A14 CRM клиента и доступы', 'client, access'],
  ['B1 Канбан', 'mes, production'],
  ['B2 Библиотека техпроцессов', 'registry'],
  ['B3 Мобильный ОТК', 'qc'],
  ['B4 База знаний', 'assistant, elearning'],
  ['B5 Вакансии/онбординг', 'staff, hr'],
  ['B6 Цифровой паспорт', 'passport'],
  ['B7 Бережливое производство', 'lean'],
  ['B8/B14 Нормирование/склад+закупки', 'norms, warehouse, procurement'],
  ['B9 Спецификации/BOM', 'bom'],
  ['B10 Планирование и Гант', 'planning'],
  ['B11 Наряды', 'production'],
  ['B12 CRM и воронка', 'crm'],
  ['B13/B18/B19/B27 Инструмент/NC/G-код', 'tooling, nc, iiot'],
  ['B15/B20 ТОиР/наладка', 'maintenance, setup'],
  ['B16 Диспетчер обращений', 'tasks, support'],
  ['B17 Монитор станков OEE', 'oee, iiot'],
  ['B22 Мобильный пульт', 'terminal'],
  ['B23 Дашборд руководителя', 'bi, dashboard'],
  ['B24 Эскалация', 'issues'],
  ['B30 КД и изменения', 'plm, docbuilder'],
  ['B31 Экономика заказа', 'economics, teo'],
  ['B32 Маркировка/QR', 'labels, passport'],
  ['B33 Конструктор документов', 'docbuilder, templates'],
  ['B35 Справочники', 'registry, dicts, mdm'],
  ['B37 Кадры: личные дела', 'hr, staff'],
  ['B38 Производственный календарь', 'calendar'],
  ['B39 Прогноз загрузки', 'forecast'],
  ['C1 Портал поставщика', 'supplier'],
  ['C2 Партнёрский кабинет', 'partners'],
  ['C3 Клуб поставщиков', 'suppliers'],
  ['P1 3DMP Cloud', 'platform, billing'],
  ['P2 App Builder', 'builder'],
  ['P3 Отраслевая аналитика', 'industry'],
  ['P4 Public API', 'api, integrations'],
  ['P5 Платежи/эскроу', 'escrow, finance'],
  ['P6 White-label', 'whitelabel'],
  ['P7 Финансы предприятия', 'finance, accounting'],
  ['P8 Доступ и роли', 'roles, access'],
  ['P9 Административная панель', 'admin, org'],
  ['P10 Диагностика', 'diagnostics, scale'],
  ['P11 Инструкция', 'guide'],
  ['P13 Подразделения', 'departments'],
  ['P14 Нормирование PRO', 'norms'],
  ['P15 Центр экспорта/отчётов', 'reports'],
  ['M1 Маркетплейс мощностей', 'marketplace']
];
const PROTO_OPEN = ['A5 Аудит цифровой зрелости (частично diagnostics)', 'A12 АРМ (частично terminal/service)', 'B36 ИТ-инфраструктура (частично iiot)', 'P12 Технологический путь (частично guide/diagnostics)'];
const protoTable = '<table class="mini"><thead><tr><th>Прототип (eco/apps)</th><th>Реализация (apps)</th></tr></thead><tbody>' +
  PROTO.map(function (r) { return '<tr><td>' + esc(r[0]) + '</td><td><b>' + esc(r[1]) + '</b></td></tr>'; }).join('') + '</tbody></table>';
const protoBlock = '<details class="panel"><summary class="panel-sum"><b>Прототипы → реализация</b> <span class="cnt">' + PROTO.length + '</span> <span class="muted">· без прямой реализации: ' + PROTO_OPEN.length + ' — развернуть</span></summary>' +
  '<p class="note" style="margin:8px 0;">Сопоставление 72 прототипов eco/apps с реализованными модулями: что было в прототипе → что стало в сервисе.</p>' + protoTable +
  '<h4 style="margin:12px 0 6px;font-size:.8rem;">Прототипы без прямой реализации</h4><ul>' + PROTO_OPEN.map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ul></details>';

/* ---------- Предложения по изменениям (tools/proposals.js) ---------- */
function propCard(p) {
  const pc = p.prio === 'P1' ? 'high' : p.prio === 'P2' ? 'mid' : 'low';
  return '<div class="prop' + (p.status === 'done' ? ' is-done' : '') + '">' +
    '<div class="prop-h"><span class="b b-pri pri-' + pc + '">' + esc(p.prio) + '</span>' +
    '<span class="tag">' + esc(p.area) + '</span><b>' + esc(p.title) + '</b>' +
    (p.status === 'done' ? '<span class="tag s-done">✅ выполнено</span>' : '') + '</div>' +
    '<div class="prop-p">' + esc(p.problem) + '</div>' +
    '<div class="prop-a"><b>Что сделать:</b> ' + esc(p.action) + '</div>' +
    '<div class="prop-e muted">' + esc(p.evidence) + ' · оценка: ' + (p.effort === 'S' ? 'малая' : p.effort === 'M' ? 'средняя' : 'крупная') + ' · ' + esc(p.id) + '</div></div>';
}
const propCounts = { P1: 0, P2: 0, P3: 0, done: 0 };
PROPOSALS.forEach(p => { if (propCounts[p.prio] != null) propCounts[p.prio]++; if (p.status === 'done') propCounts.done++; });
const proposalsBlock = '<details class="panel" open><summary class="panel-sum"><b>Предложения по изменениям</b> <span class="cnt">' + PROPOSALS.length + '</span> <span class="muted">· по итогам аудита — развернуть</span></summary>' +
  '<p class="note" style="margin:8px 0;">Рекомендации по итогам большого аудита проекта (каталог, UX, производительность, API, документация, доступность, безопасность). Источник — <code>tools/proposals.js</code> (единый список для дашборда).</p>' +
  '<div class="legend" style="margin-bottom:10px;"><span><b>P1</b> · ' + propCounts.P1 + '</span><span><b>P2</b> · ' + propCounts.P2 + '</span><span><b>P3</b> · ' + propCounts.P3 + '</span><span>✅ выполнено · ' + propCounts.done + '</span></div>' +
  ['P1', 'P2', 'P3'].map(k => '<h4 style="margin:12px 0 6px;font-size:.82rem;">' + k + ' · ' + propCounts[k] + '</h4>' + PROPOSALS.filter(p => p.prio === k).map(propCard).join('')).join('') +
  '</details>';

const generated = new Date().toISOString().slice(0, 10);
const html = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Дашборд готовности модулей 3DMP — статус, прогресс, остаток</title>
<meta name="description" content="Дашборд готовности модулей сервиса 3DMP: общая готовность, распределение по статусам/контурам/приоритетам, карта модулей, раздел «Осталось сделать».">
<style>
:root{
  --bg:#f1f5f9; --surface:#fff; --text:#0f172a; --muted:#64748b; --border:#e2e8f0;
  --accent:#10b981; --accent-700:#047857; --accent-100:#d1fae5;
  --danger:#ef4444; --warning:#f59e0b; --high:#dc2626; --mid:#d97706; --low:#0ea5e9;
  --r:14px; --r2:10px;
}
*{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Segoe UI Emoji','Apple Color Emoji',sans-serif;background:var(--bg);color:var(--text);line-height:1.5;overflow-x:hidden}
a{color:inherit}
code{background:#f8fafc;border:1px solid var(--border);border-radius:6px;padding:1px 6px;font-size:.82em}

.topbar{background:linear-gradient(135deg,#064e3b,#047857,#10b981);color:#fff;padding:12px 20px;display:flex;align-items:center;gap:12px;flex-wrap:wrap}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;text-decoration:none;color:#fff}
.brand .logo{width:34px;height:34px;border-radius:10px;background:rgba(255,255,255,.18);display:flex;align-items:center;justify-content:center;font-size:1.1rem}
.spacer{flex:1}
.tbtn{background:rgba(255,255,255,.16);color:#fff;border:1px solid rgba(255,255,255,.35);border-radius:9px;padding:7px 12px;font-size:.78rem;font-weight:600;cursor:pointer;text-decoration:none}
.tbtn:hover{background:rgba(255,255,255,.28)}

.wrap{max-width:1180px;margin:0 auto;padding:24px 18px 60px}
.hero{margin-bottom:18px}
.hero h1{font-size:1.7rem;margin-bottom:8px;letter-spacing:-.01em}
.hero p{color:var(--muted);max-width:900px}
.hero .gen{font-size:.76rem;color:var(--muted);margin-top:8px}

.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:18px 0}
.stat{background:var(--surface);border:1px solid var(--border);border-radius:var(--r);padding:14px 16px}
.stat b{display:block;font-size:1.5rem;line-height:1.1}
.stat span{font-size:.74rem;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}

.panel{background:var(--surface);border:1px solid var(--border);border-radius:var(--r);padding:16px;margin-bottom:16px}
.panel h2{font-size:1rem;margin-bottom:10px}
details.panel>summary.panel-sum{display:flex;align-items:center;gap:10px;cursor:pointer;list-style:none;font-size:.98rem}
.panel-sum::-webkit-details-marker{display:none}
details.panel[open] .panel-sum .muted{display:none}
.legend{display:flex;gap:16px;flex-wrap:wrap;font-size:.8rem;color:var(--muted)}
.legend b{color:var(--text)}

/* дашборд */
.dash{display:grid;grid-template-columns:220px 1fr;gap:16px;align-items:center}
.gauge{position:relative;display:flex;align-items:center;justify-content:center;width:150px;height:150px;margin:0 auto}
.gauge svg{position:absolute;inset:0}
.gauge-c{position:relative;text-align:center}
.gauge-c b{font-size:2rem;line-height:1}
.gauge-c span{display:block;font-size:.72rem;color:var(--muted)}
.dgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px}
.dcard{background:var(--bg);border:1px solid var(--border);border-radius:var(--r2);padding:12px}
.dcard h4{font-size:.7rem;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin-bottom:8px}
.drow{display:flex;gap:14px;align-items:center;flex-wrap:wrap}
.dlegend{display:flex;flex-direction:column;gap:5px;font-size:.76rem}
.dlegend i{display:inline-block;width:11px;height:11px;border-radius:3px;margin-right:6px;vertical-align:middle}

.map-grp{margin-bottom:12px}
.map-grp-h{font-size:.8rem;font-weight:700;color:#334155;margin:10px 0 6px;display:flex;align-items:center;gap:8px}
.map-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:8px}
.map-tile{display:flex;align-items:center;gap:8px;border:2px solid var(--border);border-radius:var(--r2);padding:8px 10px;background:#fff;text-decoration:none;color:var(--text)}
.map-tile:hover{box-shadow:0 6px 16px rgba(15,23,42,.10);transform:translateY(-1px)}
.mt-ic{font-size:1.05rem}
.mt-t{flex:1;font-size:.78rem;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.mt-s{color:#fff;font-size:.68rem;font-weight:800;border-radius:999px;padding:2px 7px}

/* осталось сделать */
.rem-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:10px}
.rem{border:1px solid #fed7aa;background:#fffbeb;border-radius:var(--r2);padding:10px 12px}
.rem-h{display:flex;align-items:center;gap:8px;justify-content:space-between;margin-bottom:6px}
.rem-h a{text-decoration:none}
.rem ul{margin-left:18px;display:flex;flex-direction:column;gap:3px}
.rem li{font-size:.79rem;color:#334155}

.toolbar{position:sticky;top:0;z-index:20;background:rgba(241,245,249,.92);backdrop-filter:blur(6px);border:1px solid var(--border);border-radius:var(--r);padding:12px;margin-bottom:18px;display:flex;gap:10px;flex-wrap:wrap;align-items:center}
.toolbar input[type=search],.toolbar select{border:1px solid var(--border);border-radius:9px;padding:8px 11px;font-size:.83rem;background:#fff;color:var(--text)}
.toolbar input[type=search]{flex:1;min-width:200px}
.toolbar label.ck{display:flex;align-items:center;gap:6px;font-size:.82rem;color:var(--text);cursor:pointer}
.toolbar .reset{margin-left:auto;background:var(--accent-100);color:var(--accent-700);border:1px solid var(--accent);border-radius:9px;padding:8px 14px;font-size:.8rem;font-weight:700;cursor:pointer}
.toolbar .shown{font-size:.78rem;color:var(--muted);font-weight:600}

.grp{margin:26px 0}
.grp-h{display:flex;align-items:center;gap:10px;border-bottom:2px solid var(--border);padding-bottom:8px;margin-bottom:12px}
.grp-h h2{font-size:1.15rem}
.grp-ic{font-size:1.3rem}
.cnt{background:var(--accent-100);color:var(--accent-700);border-radius:999px;padding:2px 10px;font-size:.75rem;font-weight:800}
.grp-d{color:var(--muted);font-size:.83rem;margin:-6px 0 10px}
h3.sub{font-size:.8rem;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin:18px 0 8px;display:flex;align-items:center;gap:8px}

.mc{background:var(--surface);border:1px solid var(--border);border-radius:var(--r);margin-bottom:10px;overflow:hidden;scroll-margin-top:70px}
.mc>summary{display:flex;align-items:center;gap:12px;padding:13px 16px;cursor:pointer;list-style:none}
.mc>summary::-webkit-details-marker{display:none}
.mc-ic{width:36px;height:36px;border-radius:10px;background:var(--accent-100);color:var(--accent-700);display:flex;align-items:center;justify-content:center;font-size:1.1rem;flex:0 0 auto}
.mc-tt{flex:1;min-width:0;display:flex;flex-direction:column;gap:1px}
.mc-tt b{font-size:.95rem}
.mc-tt small{font-size:.76rem;color:var(--muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.badges{display:flex;gap:8px;align-items:center;flex-wrap:wrap;justify-content:flex-end}
.b{font-size:.7rem;font-weight:800;border-radius:999px;padding:4px 10px;white-space:nowrap}
.b-u{background:#fef3c7;color:#b45309;letter-spacing:1px}
.b-score{color:#fff}
.b-pri{color:#fff}
.pri-high{background:var(--high)}
.pri-mid{background:var(--mid)}
.pri-low{background:var(--low)}
.chev{color:var(--muted);transition:transform .15s;font-size:1.1rem}
.mc[open] .chev{transform:rotate(180deg)}
.mc[open]{border-color:var(--accent)}

.mc-body{border-top:1px solid var(--border);padding:14px 16px}
.mc-meta{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:10px}
.tag{font-size:.72rem;background:var(--bg);border:1px solid var(--border);border-radius:999px;padding:4px 10px;color:var(--muted)}
.tag.link{color:var(--accent-700);font-weight:700;border-color:var(--accent);text-decoration:none}
.tag.link:hover{background:var(--accent-100)}
.tag.wave{background:#eef2ff;border-color:#c7d2fe;color:#4338ca;font-weight:700}
.s-done{background:#ecfdf5;border-color:#a7f3d0;color:#065f46;font-weight:700}
.s-partial{background:#fff7ed;border-color:#fed7aa;color:#9a3412;font-weight:700}
.s-none{background:#f1f5f9;border-color:#e2e8f0;color:#64748b;font-weight:700}
.mc-purpose{font-size:.86rem;color:#334155;margin-bottom:12px}
.mc-cols{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:14px}
.mc-col h4,.an h4{font-size:.7rem;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin-bottom:8px}
ul.feat{list-style:none;display:flex;flex-direction:column;gap:5px}
ul.feat li{font-size:.82rem;padding-left:18px;position:relative;color:#334155}
ul.feat li::before{content:'✓';position:absolute;left:0;color:var(--accent-700);font-weight:800}
.chips{display:flex;flex-wrap:wrap;gap:6px}
.chip{font-size:.75rem;border:1px solid var(--border);border-radius:999px;padding:4px 11px;background:#fff;text-decoration:none;color:var(--text)}
.chip:hover{border-color:var(--accent);background:var(--accent-100)}
.muted{color:var(--muted)}

.analysis{display:grid;grid-template-columns:1fr 1fr;gap:12px;border-top:1px dashed var(--border);padding-top:14px}
.an{background:var(--bg);border:1px solid var(--border);border-radius:var(--r2);padding:12px}
.an p{font-size:.82rem;color:#334155}
.an ul,.an ol{margin-left:18px;display:flex;flex-direction:column;gap:4px}
.an li{font-size:.8rem;color:#334155}
.an ol .prem{color:#9a3412;font-weight:600}
.an ol .pdone{color:#64748b;text-decoration:line-through}
.an-merge.has{border-color:var(--warning);background:#fffbeb}
.an-merge.none{opacity:.85}
.score{display:flex;align-items:center;gap:10px;margin-bottom:6px}
.s-val{font-weight:800;font-size:1rem}
.s-stars{color:#f59e0b;letter-spacing:1px}
.pri-dot{font-size:.68rem;color:#fff;border-radius:999px;padding:2px 8px;margin-left:6px}

.merge-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:10px}
.mchip{display:flex;flex-direction:column;gap:2px;text-decoration:none;border:1px solid var(--border);border-radius:var(--r2);padding:10px 12px;background:#fff}
.mchip:hover{border-color:var(--warning);background:#fffbeb}
.mchip b{font-size:.84rem}
.mchip span{font-size:.76rem;color:var(--muted)}
.prirow{display:flex;gap:12px;align-items:flex-start;margin-bottom:10px;flex-wrap:wrap}
.prirow .b{flex:0 0 auto}

.prop{border:1px solid var(--border);border-radius:var(--r2);padding:10px 12px;margin-bottom:8px;background:var(--surface)}
.prop.is-done{opacity:.7}
.prop-h{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:4px}
.prop-p{font-size:.82rem;color:var(--text)}
.prop-a{font-size:.82rem;margin-top:4px}
.prop-e{font-size:.72rem;margin-top:4px}
.s-done{background:#ecfdf5 !important;border-color:#a7f3d0 !important;color:#047857 !important;font-weight:700}

.foot{color:var(--muted);font-size:.78rem;margin-top:30px;border-top:1px solid var(--border);padding-top:14px}
.hidden{display:none !important}
@media (max-width:820px){.mc-cols,.analysis{grid-template-columns:1fr}.dash{grid-template-columns:1fr}.wrap{padding:18px 12px 50px}.hero h1{font-size:1.4rem}}
@media print{.toolbar{display:none}.mc{break-inside:avoid}.mc-body{display:block}.mc>summary{cursor:default}.map-tile{break-inside:avoid}}
</style>
</head>
<body>
<header class="topbar">
  <a class="brand" href="index.html"><span class="logo">🏭</span><span>3DMP <span style="opacity:.7;font-weight:400">· дашборд готовности модулей</span></span></a>
  <span class="spacer"></span>
  <a class="tbtn" href="apps/guide/index.html">Гид по системе</a>
  <a class="tbtn" href="apps/modules/index.html">Карта модулей</a>
  <a class="tbtn" href="index.html">Хаб</a>
</header>

<main class="wrap">
  <div class="hero">
    <h1>Дашборд готовности модулей 3DMP</h1>
    <p>Общая готовность, распределение по статусам/контурам/приоритетам, карта модулей по статусу и раздел «Осталось сделать» (только ◐). Плюс полное описание возможностей, полезность и план обновления.</p>
    <p class="gen">Сгенерировано ${generated} из <code>assets/js/catalog.js</code> (v${esc(C.version || '')}) и <code>tools/modules-analysis.js</code>. Не редактировать вручную.</p>
  </div>

  <div class="cards">
    <div class="stat"><b>${overall}%</b><span>общая готовность</span></div>
    <div class="stat"><b>${stats.n}</b><span>модулей</span></div>
    <div class="stat"><b style="color:#047857">${stats.status.done}</b><span>✅ реализовано</span></div>
    <div class="stat"><b style="color:#b45309">${stats.status.partial}</b><span>◐ частично</span></div>
    <div class="stat"><b>${remainTotal}</b><span>пунктов плана без ✅</span></div>
    <div class="stat"><b>${stats.groups}</b><span>контуров</span></div>
    <div class="stat"><b>${PROPOSALS.length}</b><span>предложений по изменениям</span></div>
  </div>

  <div class="panel">
    <h2>Карта и прогресс</h2>
    <div class="dash">
      <div>
        ${gauge}
        <div class="legend" style="justify-content:center;margin-top:8px;gap:10px;">
          <span>✅ ${stats.status.done}</span><span>◐ ${stats.status.partial}</span><span>без статуса ${stats.status.none}</span>
        </div>
      </div>
      <div class="dgrid">
        ${kpiDonut('По статусу', statusSegs)}
        ${kpiDonut('По контурам', groupSegs)}
        ${kpiDonut('По приоритету', priSegs)}
      </div>
    </div>
    <div class="legend" style="margin-top:12px;">
      <span><b>Легенда карты:</b></span>
      <span><i style="display:inline-block;width:11px;height:11px;background:${ST_COLOR.done};border-radius:3px;margin-right:5px;vertical-align:middle"></i>✅ готов</span>
      <span><i style="display:inline-block;width:11px;height:11px;background:${ST_COLOR.partial};border-radius:3px;margin-right:5px;vertical-align:middle"></i>◐ частично (остаток)</span>
      <span><i style="display:inline-block;width:11px;height:11px;background:${ST_COLOR.none};border-radius:3px;margin-right:5px;vertical-align:middle"></i>без статуса</span>
    </div>
    <div style="margin-top:14px;">${mapHtml}</div>
  </div>

  <div class="panel">
    <h2>Легенда оценки</h2>
    <div class="legend">
      <span><b>Готовность модуля:</b> ✅ → 100%, ◐ → доля пунктов плана с ✅, без статуса → 0%</span>
      <span><b>Полезность:</b> 5 — ядро · 4 — важно · 3 — ниша · 2 — вспомогательное</span>
      <span><b>Приоритет:</b> <span class="b b-pri pri-high">высокий</span> <span class="b b-pri pri-mid">средний</span> <span class="b b-pri pri-low">низкий</span></span>
    </div>
  </div>

  ${remainPanel}

  <div class="panel">
    <h2>Приоритеты обновления</h2>
    ${priRow('high', 'Высокий')}
    ${priRow('mid', 'Средний')}
    ${priRow('low', 'Низкий')}
  </div>

  <details class="panel">
    <summary class="panel-sum"><b>Направления объединения и встраивания</b> <span class="cnt">${stats.merges}</span> <span class="muted">— развернуть</span></summary>
    <div class="merge-grid" style="margin-top:12px">${mergeList}</div>
  </details>

  ${protoBlock}

  ${proposalsBlock}

  <div class="toolbar" id="toolbar">
    <input type="search" id="q" placeholder="Поиск: модуль, функция, связь…">
    <select id="f-group"><option value="">Все контуры</option>${(C.groups || []).map(g => `<option value="${attr(g.id)}">${esc(g.icon)} ${esc(g.title)}</option>`).join('')}</select>
    <select id="f-pri"><option value="">Любой приоритет</option><option value="high">высокий</option><option value="mid">средний</option><option value="low">низкий</option></select>
    <select id="f-u"><option value="0">Любая полезность</option><option value="5">5 — ядро</option><option value="4">4 и выше</option><option value="3">3 и выше</option></select>
    <select id="f-wave"><option value="">Любая волна v5</option>${waveList.map(w => `<option value="${attr(w)}">${esc(w)}</option>`).join('')}</select>
    <select id="f-status"><option value="">Все статусы</option><option value="partial">Только остаток (◐)</option><option value="hide_done">Скрыть ✅</option><option value="done">Только ✅</option><option value="none">Без статуса</option></select>
    <label class="ck"><input type="checkbox" id="f-merge"> только с рек. объединения</label>
    <span class="shown" id="shown"></span>
    <button class="reset" id="reset">Сброс</button>
  </div>

  ${sections.join('\n')}

  <p class="foot">Дашборд для анализа (корень проекта, вне <code>SAAS/</code>; на FTP не заливается). Источники: <code>SAAS/assets/js/catalog.js</code> + <code>SAAS/tools/modules-analysis.js</code> → <code>SAAS/tools/gen-modules-page.js</code> → <code>modules.html</code>. Обновление — <code>node tools/gen-modules-page.js</code> после каждой волны.</p>
</main>

<script>
(function(){
  var q=document.getElementById('q'), fg=document.getElementById('f-group'), fp=document.getElementById('f-pri'),
      fu=document.getElementById('f-u'), fw=document.getElementById('f-wave'), fs=document.getElementById('f-status'), fm=document.getElementById('f-merge'), shown=document.getElementById('shown');
  var cards=[].slice.call(document.querySelectorAll('.mc'));
  var tiles=[].slice.call(document.querySelectorAll('.map-tile'));
  var arc=document.getElementById('gaugeArc'), pct=document.getElementById('gaugePct');
  var CIRC=2*Math.PI*54;
  function apply(){
    var s=(q.value||'').trim().toLowerCase(), g=fg.value, p=fp.value, u=parseInt(fu.value||'0',10), st=fs.value, m=fm.checked, n=0, scoreSum=0;
    cards.forEach(function(c){
      var ok=true;
      if(s && c.getAttribute('data-text').indexOf(s)<0) ok=false;
      if(ok && g && c.getAttribute('data-group')!==g) ok=false;
      if(ok && p && c.getAttribute('data-pri')!==p) ok=false;
      if(ok && u && parseInt(c.getAttribute('data-u'),10)<u) ok=false;
      if(ok && fw.value && c.getAttribute('data-wave')!==fw.value) ok=false;
      if(ok && st){
        var cs=c.getAttribute('data-status');
        if(st==='partial' && cs!=='partial') ok=false;
        else if(st==='done' && cs!=='done') ok=false;
        else if(st==='none' && cs!=='none') ok=false;
        else if(st==='hide_done' && cs==='done') ok=false;
      }
      if(ok && m && c.getAttribute('data-merge')!=='1') ok=false;
      c.classList.toggle('hidden',!ok); if(ok){ n++; scoreSum+=parseInt(c.getAttribute('data-score'),10)||0; }
    });
    shown.textContent='показано '+n+' из '+cards.length;
    document.querySelectorAll('.grp').forEach(function(sec){
      var vis=sec.querySelectorAll('.mc:not(.hidden)').length; sec.classList.toggle('hidden', vis===0);
    });
    tiles.forEach(function(t){
      var el=document.querySelector('.mc[data-id="'+t.getAttribute('data-id')+'"]');
      t.classList.toggle('hidden', !el || el.classList.contains('hidden'));
    });
    var P = n ? Math.round(scoreSum/n) : 0;
    if(pct) pct.textContent=P+'%';
    if(arc) arc.setAttribute('stroke-dasharray',(CIRC*P/100).toFixed(2)+' '+CIRC.toFixed(2));
  }
  ['input','change'].forEach(function(ev){ [q,fg,fp,fu,fw,fs,fm].forEach(function(el){ el.addEventListener(ev,apply); }); });
  document.getElementById('reset').addEventListener('click',function(){ q.value=''; fg.value=''; fp.value=''; fu.value='0'; fw.value=''; fs.value=''; fm.checked=false; apply(); });
  document.querySelectorAll('[data-target]').forEach(function(a){ a.addEventListener('click',function(e){
    var id=a.getAttribute('data-target'), el=document.querySelector('.mc[data-id="'+id+'"]');
    if(el){ e.preventDefault(); el.classList.remove('hidden'); el.open=true; el.scrollIntoView({behavior:'smooth',block:'start'}); }
  }); });
  apply();
})();
</script>
</body>
</html>`;

fs.writeFileSync(OUT, html, { encoding: 'utf8' });
console.log('gen-modules-page: записано ' + OUT + ' (' + C.apps.length + ' модулей; готовность ' + overall + '%; ✅ ' + stats.status.done + ' / ◐ ' + stats.status.partial + ' / без ' + stats.status.none + '; остаток ' + remainTotal + ' п.)');
if (stats.missing.length) console.warn('НЕТ аналитики для: ' + stats.missing.join(', '));
