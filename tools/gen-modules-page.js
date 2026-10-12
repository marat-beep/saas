/* ============================================================
   tools/gen-modules-page.js — генератор modules.html (корень воркспейса, над SAAS/)
   Собирает самодостаточную справочную страницу по всем модулям:
   описание возможностей (из assets/js/catalog.js) + экспертная
   аналитика (tools/modules-analysis.js): полезность, объединение,
   наполнение и план обновления. Работает без backend (статика + JS-фильтры).
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

const OUT = path.resolve(root, '..', 'modules.html');
const AUD = { guest: 'гость', user: 'пользователь', client_admin: 'админ клиента', saas_admin: 'SaaS-админ', developer: 'разработчик' };
const PRI = { high: 'высокий', mid: 'средний', low: 'низкий' };
const titleById = {};
C.apps.forEach(a => { titleById[a.id] = a.title; });

function esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
function attr(s) { return esc(s).replace(/\n/g, ' '); }
function stars(u) { u = Math.max(1, Math.min(5, u | 0)); return '★'.repeat(u) + '☆'.repeat(5 - u); }
function roles(a) { return a.roles && a.roles.length ? a.roles.join(', ') : 'все авторизованные'; }

/* ---------- статистика ---------- */
const stats = { n: C.apps.length, groups: (C.groups || []).length, uSum: 0, uAvg: 0, merges: 0, pri: { high: 0, mid: 0, low: 0 }, missing: [] };
C.apps.forEach(a => {
  const an = A[a.id];
  if (!an) { stats.missing.push(a.id); return; }
  stats.uSum += an.u;
  if (an.merge) stats.merges++;
  stats.pri[an.pri] = (stats.pri[an.pri] || 0) + 1;
});
stats.uAvg = (stats.uSum / C.apps.length).toFixed(1);
const waveList = Array.from(new Set(C.apps.map(a => A[a.id] && A[a.id].wave).filter(Boolean))).sort((x, y) => (parseInt(x.slice(1), 10) || 0) - (parseInt(y.slice(1), 10) || 0));

/* ---------- карточка модуля ---------- */
function card(a) {
  const an = A[a.id] || { u: 3, why: 'Аналитика не задана.', merge: '', add: [], pri: 'mid', plan: [] };
  const connects = (a.connects || []).map(id => {
    const t = titleById[id];
    return '<span class="chip" title="' + attr(id) + '">' + esc(t ? t : id) + '</span>';
  }).join('') || '<span class="muted">—</span>';
  const feats = (a.features || []).map(f => '<li>' + esc(f) + '</li>').join('') || '<li class="muted">—</li>';
  const adds = (an.add || []).map(f => '<li>' + esc(f) + '</li>').join('') || '<li class="muted">—</li>';
  const plan = (an.plan || []).map(f => '<li>' + esc(f) + '</li>').join('') || '<li class="muted">—</li>';
  const text = [a.title, a.id, a.desc, a.purpose, (a.features || []).join(' '), (a.connects || []).join(' '), an.why, an.merge, (an.add || []).join(' '), (an.plan || []).join(' ')].join(' ').toLowerCase();

  const mergeCls = an.merge ? 'has' : 'none';
  return `
<details class="mc" id="m-${attr(a.id)}" data-id="${attr(a.id)}" data-group="${attr(a.group || '')}" data-pri="${attr(an.pri)}" data-u="${an.u}" data-merge="${an.merge ? 1 : 0}" data-wave="${attr(an.wave || '')}" data-text="${attr(text)}">
  <summary>
    <span class="mc-ic">${esc(a.icon || '•')}</span>
    <span class="mc-tt"><b>${esc(a.title)}</b><small>${esc(a.id)}${a.desc ? ' · ' + esc(a.desc) : ''}</small></span>
    <span class="badges">
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
      ${(an.wave || an.done) ? (an.partial ? '<span class="tag" style="background:#fff7ed;border-color:#fed7aa;color:#9a3412;font-weight:700">◐ частично реализовано</span>' : '<span class="tag" style="background:#ecfdf5;border-color:#a7f3d0;color:#065f46;font-weight:700">✅ реализовано</span>') : ''}
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
      <div class="an an-plan"><h4>План обновления <span class="pri-dot pri-${attr(an.pri)}">${esc(PRI[an.pri] || an.pri)}</span></h4><ol>${plan}</ol></div>
    </div>
  </div>
</details>`;
}

/* ---------- разделы ---------- */
const sections = [];
(C.groups || []).forEach(g => {
  const items = C.apps.filter(a => a.group === g.id);
  if (!items.length) return;
  const used = {};
  const subHtml = [];
  const subs = (C.subgroups && C.subgroups[g.id]) || null;
  const emit = a => { used[a.id] = 1; return card(a); };
  if (subs) {
    subs.forEach(s => {
      const si = items.filter(a => s.apps.indexOf(a.id) >= 0);
      if (!si.length) return;
      subHtml.push('<h3 class="sub">' + esc(s.title) + ' <span class="cnt">' + si.length + '</span></h3>' + si.map(emit).join(''));
    });
    const other = items.filter(a => !used[a.id]);
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

const generated = new Date().toISOString().slice(0, 10);

const html = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Справочник модулей 3DMP — возможности, полезность, план обновления</title>
<meta name="description" content="Справочная страница по всем модулям сервиса 3DMP: полное описание возможностей, оценка полезности, варианты объединения, наполнение и план обновления.">
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

.foot{color:var(--muted);font-size:.78rem;margin-top:30px;border-top:1px solid var(--border);padding-top:14px}
.hidden{display:none !important}
@media (max-width:820px){.mc-cols,.analysis{grid-template-columns:1fr}.wrap{padding:18px 12px 50px}.hero h1{font-size:1.4rem}}
@media print{.toolbar{display:none}.mc{break-inside:avoid}.mc-body{display:block}.mc>summary{cursor:default}}
</style>
</head>
<body>
<header class="topbar">
  <a class="brand" href="index.html"><span class="logo">🏭</span><span>3DMP <span style="opacity:.7;font-weight:400">· справочник модулей</span></span></a>
  <span class="spacer"></span>
  <a class="tbtn" href="apps/guide/index.html">Гид по системе</a>
  <a class="tbtn" href="apps/modules/index.html">Карта модулей</a>
  <a class="tbtn" href="index.html">Хаб</a>
</header>

<main class="wrap">
  <div class="hero">
    <h1>Справочник модулей 3DMP</h1>
    <p>Полное описание возможностей каждого модуля, экспертная оценка полезности, варианты объединения с другими модулями, направления наполнения функциями и поэтапный план обновления. Используйте поиск и фильтры ниже.</p>
    <p class="gen">Сгенерировано ${generated} из <code>assets/js/catalog.js</code> (v${esc(C.version || '')}) и <code>tools/modules-analysis.js</code>. Не редактировать вручную.</p>
  </div>

  <div class="cards">
    <div class="stat"><b>${stats.n}</b><span>модулей</span></div>
    <div class="stat"><b>${stats.groups}</b><span>контуров</span></div>
    <div class="stat"><b>${stats.uAvg}</b><span>средняя полезность</span></div>
    <div class="stat"><b>${stats.pri.high || 0}</b><span>высокий приоритет</span></div>
    <div class="stat"><b>${stats.merges}</b><span>с рек. объединения</span></div>
  </div>

  <div class="panel">
    <h2>Легенда оценки</h2>
    <div class="legend">
      <span><b>Полезность 5</b> — ядро, критично для работы</span>
      <span><b>4</b> — важно, высокая отдача</span>
      <span><b>3</b> — полезно, ниша/средняя отдача</span>
      <span><b>2</b> — вспомогательное/прототип</span>
      <span><b>Приоритет обновления:</b> <span class="b b-pri pri-high">высокий</span> <span class="b b-pri pri-mid">средний</span> <span class="b b-pri pri-low">низкий</span></span>
    </div>
  </div>

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

  <div class="toolbar" id="toolbar">
    <input type="search" id="q" placeholder="Поиск: модуль, функция, связь…">
    <select id="f-group"><option value="">Все контуры</option>${(C.groups || []).map(g => `<option value="${attr(g.id)}">${esc(g.icon)} ${esc(g.title)}</option>`).join('')}</select>
    <select id="f-pri"><option value="">Любой приоритет</option><option value="high">высокий</option><option value="mid">средний</option><option value="low">низкий</option></select>
    <select id="f-u"><option value="0">Любая полезность</option><option value="5">5 — ядро</option><option value="4">4 и выше</option><option value="3">3 и выше</option></select>
    <select id="f-wave"><option value="">Любая волна v5</option>${waveList.map(w => `<option value="${attr(w)}">${esc(w)}</option>`).join('')}</select>
    <label class="ck"><input type="checkbox" id="f-merge"> только с рек. объединения</label>
    <span class="shown" id="shown"></span>
    <button class="reset" id="reset">Сброс</button>
  </div>

  ${sections.join('\n')}

  <p class="foot">Справочный файл для анализа (лежит в корне проекта, вне <code>SAAS/</code>; на FTP не заливается). Источник: <code>SAAS/assets/js/catalog.js</code> + <code>SAAS/tools/modules-analysis.js</code> → <code>SAAS/tools/gen-modules-page.js</code> → <code>modules.html</code>. Волны <code>план v5</code> ссылаются на <code>SAAS/docs/PLAN_UPDATE_V5.md</code>. Маркер 🆕 — модули новой волны.</p>
</main>

<script>
(function(){
  var q=document.getElementById('q'), fg=document.getElementById('f-group'), fp=document.getElementById('f-pri'),
      fu=document.getElementById('f-u'), fw=document.getElementById('f-wave'), fm=document.getElementById('f-merge'), shown=document.getElementById('shown');
  var cards=[].slice.call(document.querySelectorAll('.mc'));
  function apply(){
    var s=(q.value||'').trim().toLowerCase(), g=fg.value, p=fp.value, u=parseInt(fu.value||'0',10), m=fm.checked, n=0;
    cards.forEach(function(c){
      var ok=true;
      if(s && c.getAttribute('data-text').indexOf(s)<0) ok=false;
      if(ok && g && c.getAttribute('data-group')!==g) ok=false;
      if(ok && p && c.getAttribute('data-pri')!==p) ok=false;
      if(ok && u && parseInt(c.getAttribute('data-u'),10)<u) ok=false;
      if(ok && fw.value && c.getAttribute('data-wave')!==fw.value) ok=false;
      if(ok && m && c.getAttribute('data-merge')!=='1') ok=false;
      c.classList.toggle('hidden',!ok); if(ok) n++;
    });
    shown.textContent='показано '+n+' из '+cards.length;
    document.querySelectorAll('.grp').forEach(function(sec){
      var vis=sec.querySelectorAll('.mc:not(.hidden)').length; sec.classList.toggle('hidden', vis===0);
    });
  }
  ['input','change'].forEach(function(ev){ [q,fg,fp,fu,fw,fm].forEach(function(el){ el.addEventListener(ev,apply); }); });
  document.getElementById('reset').addEventListener('click',function(){ q.value=''; fg.value=''; fp.value=''; fu.value='0'; fw.value=''; fm.checked=false; apply(); });
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
console.log('gen-modules-page: записано ' + OUT + ' (' + C.apps.length + ' модулей, ' + stats.merges + ' к объединению)');
if (stats.missing.length) console.warn('НЕТ аналитики для: ' + stats.missing.join(', '));
