/* ============================================================
   P9 · Административная панель
   обзор, тенанты, пользователи/роли, модули (feature flags),
   аудит, настройки
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var TENANTS = [
    { name: 'ООО «Пресс-Технологии»', plan: 'Бизнес', status: 'active', modules: 10, mrr: 48900 },
    { name: 'АО «Урал-Штамп»', plan: 'Корпоративный', status: 'active', modules: 14, mrr: 91500 },
    { name: 'ООО «Точмаш-Сервис»', plan: 'Бизнес', status: 'active', modules: 8, mrr: 42100 },
    { name: 'ИП Ковалёв А.В.', plan: 'Старт', status: 'trial', modules: 4, mrr: 0 },
    { name: 'ООО «ЛазерПро-Юг»', plan: 'Старт', status: 'active', modules: 5, mrr: 25400 },
    { name: 'ООО «Металлист-2»', plan: 'Бизнес', status: 'risk', modules: 9, mrr: 44600 }
  ];

  var USERS = [
    { name: 'Иванов И.И.', login: 'ivanov@company.ru', role: 'client' },
    { name: 'Кузнецов А.', login: 'a.kuznetsov@3dmp.ru', role: 'staff' },
    { name: 'ООО «Гальваник»', login: 'partner@galvanik.ru', role: 'partner' },
    { name: 'Администратор', login: 'admin@3dmp.ru', role: 'admin' }
  ];

  var SERVICES = [
    ['Канбан производства', true], ['Монитор станков (OEE)', true], ['УП и DNC', true],
    ['Платежи и эскроу', true], ['Маркетплейс мощностей', true], ['Public API', false]
  ];

  var auditFilter = 'all';
  var screens = AppRouter.create({
    onShow: function (s) {
      $$('#nav button').forEach(function (b) { b.classList.toggle('active', b.dataset.s === s.id); });
      window.scrollTo(0, 0);
    },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#nav').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    screens.go(b.dataset.s);
  });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  /* ---------- Обзор ---------- */
  var C = window.AppCatalog;
  function renderOverview() {
    var mrr = TENANTS.reduce(function (a, t) { return a + t.mrr; }, 0);
    var unread = AppData.notifications.unread();
    var logs = AppData.log.all().length;
    var kpis = [
      ['accent', App.number(mrr / 1000) + ' тыс. ₽', 'MRR платформы'],
      ['info', TENANTS.length, 'Тенантов'],
      ['success', C.countModules(), 'Модулей в каталоге'],
      ['accent', C.countApps(), 'Приложений'],
      ['warning', unread, 'Новых уведомлений'],
      ['info', logs, 'Записей аудита']
    ];
    $('#kpiGrid').innerHTML = kpis.map(function (k) {
      return '<div class="stat"><div class="num ' + k[0] + '" style="font-size:1.3rem;">' + k[1] + '</div><div class="label">' + k[2] + '</div></div>';
    }).join('');
    $('#svcList').innerHTML = SERVICES.map(function (s) {
      return '<div class="svc"><span>' + s[0] + '</span><span class="badge ' + (s[1] ? 'success' : 'neutral') + '">' + (s[1] ? 'Онлайн' : 'Выключен') + '</span></div>';
    }).join('');
    var mon = App.Store.get('monitorStats', { oee: 74, alarms: 1 });
    var dsp = App.Store.get('dispatchStats', { open: 2, work: 2, closed: 2 });
    var open = AppData.problems.open().length, crit = AppData.problems.critical().length;
    $('#supportCard').innerHTML =
      '<div class="svc"><span>Мониторинг станков (B17)</span><span style="text-align:right;"><b>OEE ' + mon.oee + '%</b> · <span class="badge ' + (mon.alarms ? 'danger' : 'success') + '">' + (mon.alarms ? 'аварий: ' + mon.alarms : 'аварий нет') + '</span></span></div>' +
      '<div class="svc"><span>Диспетчер обращений (B16)</span><span><span class="badge warning">новых: ' + dsp.open + '</span> <span class="badge info">в работе: ' + dsp.work + '</span> <span class="badge success">закрыто: ' + dsp.closed + '</span></span></div>' +
      '<div class="svc"><span>Проблемы и эскалация (B24)</span><span><span class="badge ' + (crit ? 'danger' : 'success') + '">критичных: ' + crit + '</span> <span class="badge warning">открыто: ' + open + '</span></span></div>' +
      '<div class="svc"><span>Быстрые ссылки</span><span><a class="tag" href="../b17-monitor/index.html">Монитор</a> <a class="tag" href="../b16-dispatch/index.html">Поддержка</a> <a class="tag" href="../b24-escalation/index.html">Проблемы</a> <a class="tag" href="../p10-diagnostics/index.html">Диагностика</a> <a class="tag" href="../p4-api/index.html">API</a></span></div>';
  }

  /* ---------- Тенанты ---------- */
  function renderTenants() {
    $('#tenantList').innerHTML = TENANTS.map(function (t) {
      var st = t.status === 'active' ? ['success', 'Активен'] : t.status === 'trial' ? ['info', 'Пробный'] : ['danger', 'Риск оттока'];
      return '<div class="trow"><div class="tlogo">' + t.name.replace(/[^A-Za-zА-Яа-я]/g, '').slice(0, 2).toUpperCase() + '</div><div class="grow"><div style="font-weight:700;font-size:.86rem;">' + t.name + '</div><div class="faint" style="font-size:.7rem;">' + t.plan + ' · ' + t.modules + ' модулей</div></div><div style="text-align:right;min-width:90px;"><b>' + (t.mrr ? money(t.mrr) : '—') + '</b><div class="faint" style="font-size:.66rem;">MRR</div></div><span class="badge ' + st[0] + '">' + st[1] + '</span></div>';
    }).join('');
  }

  /* ---------- Пользователи и делегирование ---------- */
  function renderUsers() {
    $('#userList').innerHTML = USERS.map(function (u) {
      var label = window.AppAuth ? AppAuth.roleLabel(u.role) : u.role;
      return '<div class="trow"><div class="grow"><div style="font-weight:600;font-size:.84rem;">' + u.name + '</div><div class="faint" style="font-size:.7rem;">' + u.login + '</div></div><span class="badge accent">' + label + '</span></div>';
    }).join('');
    var team = AppData.team.all();
    $('#delegList').innerHTML = team.length ? team.map(function (m) {
      return '<div class="trow"><div class="grow"><div style="font-weight:600;font-size:.84rem;">' + m.name + '</div><div class="faint" style="font-size:.7rem;">' + m.role + ' · доступов ' + (m.functions || []).length + '</div></div><span class="badge ' + (m.status === 'Активен' ? 'success' : 'warning') + '">' + (m.status || 'Приглашён') + '</span></div>';
    }).join('') : '<div class="callout info"><span class="ci">👥</span><div>Делегирований нет. Настройте в A14 «CRM клиента и доступы».</div></div>';
  }

  /* ---------- Модули / feature flags ---------- */
  function getFlags() { return AppData.settings.get('flags', {}); }
  function setFlag(id, on) { var f = getFlags(); f[id] = on; AppData.settings.set('flags', f); }
  function renderModules() {
    var flags = getFlags();
    $('#moduleGroups').innerHTML = C.groups.map(function (g) {
      return '<div class="card"><h4 class="mb-8">' + g.icon + ' ' + g.title + ' <span class="faint" style="font-weight:400;">(' + g.apps.length + ')</span></h4>' +
        g.apps.map(function (a) {
          var on = flags[a.id] !== false;
          return '<div class="mod-row"><span style="font-family:var(--mono);font-size:.68rem;color:var(--faint);min-width:34px;">' + a.id + '</span><span class="grow">' + a.icon + ' ' + a.title + '</span><span class="badge ' + (on ? 'success' : 'neutral') + '" style="margin-right:8px;">' + (on ? 'вкл' : 'выкл') + '</span><div class="switch' + (on ? ' on' : '') + '" data-flag="' + a.id + '"></div></div>';
        }).join('') + '</div>';
    }).join('');
    $$('#moduleGroups .switch').forEach(function (sw) {
      sw.addEventListener('click', function () {
        var id = sw.dataset.flag; var now = getFlags()[id] !== false;
        setFlag(id, !now);
        AppData.log.add({ action: (!now ? 'Модуль включён' : 'Модуль выключен'), detail: id });
        renderModules();
        App.toast('Модуль ' + id + (now ? ' выключен' : ' включён'));
      });
    });
  }

  /* ---------- Аудит ---------- */
  var auditUser = '', auditPeriod = 'all';
  function renderLog() {
    var now = Date.now(), day = 86400000;
    // список пользователей в фильтр
    var whos = {};
    AppData.log.all().forEach(function (e) { whos[e.who] = 1; });
    var sel = $('#auditUser');
    var cur = sel.value;
    sel.innerHTML = '<option value="">Все пользователи</option>' + Object.keys(whos).map(function (w) { return '<option value="' + w + '"' + (cur === w ? ' selected' : '') + '>' + w + '</option>'; }).join('');
    var list = AppData.log.all().filter(function (e) {
      var access = /доступ|роль|пригла|активир|блокир|сотрудник|модуль/i.test(e.action || '');
      if (auditFilter === 'access' && !access) return false;
      if (auditFilter === 'other' && access) return false;
      if (auditUser && e.who !== auditUser) return false;
      if (auditPeriod === 'today' && (now - (e.ts || 0)) > day) return false;
      if (auditPeriod === '7' && (now - (e.ts || 0)) > 7 * day) return false;
      return true;
    });
    $('#logList').innerHTML = list.length ? list.map(function (e) {
      return '<div class="log-row"><div><div style="font-weight:600;">' + e.action + '</div><div class="faint" style="font-size:.68rem;">' + e.who + ' · ' + e.date + '</div></div><span class="muted" style="text-align:right;">' + (e.detail || '') + '</span></div>';
    }).join('') : '<div class="callout info"><span class="ci">🧾</span><div>Записей нет.</div></div>';
  }
  $('#auditFilters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    auditFilter = c.dataset.f; renderLog();
  });
  $('#auditUser').addEventListener('change', function () { auditUser = this.value; renderLog(); });
  $('#auditPeriod').addEventListener('change', function () { auditPeriod = this.value; renderLog(); });
  $('#expLog').addEventListener('click', function () { App.toast('Демо: журнал выгружен (CSV)'); });
  $('#clrLog').addEventListener('click', function () { if (window.AppData) { AppData.log.clear(); renderLog(); App.toast('Журнал очищен'); } });

  /* ---------- Настройки ---------- */
  function renderSettings() {
    var ch = (C.changelog || []).map(function (c) { return '<div class="faint" style="font-size:.72rem;padding:3px 0;">• ' + c + '</div>'; }).join('');
    $('#verCard').innerHTML = '<div class="row between mb-8"><span class="muted">Версия каталога</span><b>' + C.version + '</b></div><div class="row between mb-8"><span class="muted">Обновлено</span><b>' + C.updated + '</b></div>' + ch;
    $('#devSwitchAdmin').classList.toggle('on', !!AppData.settings.get('devMode', false));
  }
  $('#devSwitchAdmin').addEventListener('click', function () {
    var on = !AppData.settings.get('devMode', false);
    AppData.settings.set('devMode', on);
    AppData.log.add({ action: 'Dev-режим', detail: on ? 'включён' : 'выключен' });
    this.classList.toggle('on', on);
    App.toast('Dev-режим ' + (on ? 'включён' : 'выключен'));
  });
  $('#resetAll').addEventListener('click', function () {
    Object.keys(localStorage).filter(function (k) { return k.indexOf('3dmp:') === 0; }).forEach(function (k) { localStorage.removeItem(k); });
    App.toast('Демо-данные сброшены');
    renderOverview(); renderUsers(); renderModules(); renderLog();
  });

  /* ---------- Организация: размер предприятия ---------- */
  var SIZES = {
    small: { label: 'Малое предприятие', desc: 'до 30–50 сотрудников, простая структура', rec: ['A1', 'A2', 'A3', 'B1', 'B3', 'B8', 'B9', 'B28', 'B31', 'P11'] },
    medium: { label: 'Среднее предприятие', desc: '50–250 сотрудников, цеха и участки', rec: ['A1', 'A2', 'A3', 'A4', 'A6', 'A7', 'A9', 'A10', 'B1', 'B3', 'B6', 'B8', 'B9', 'B10', 'B11', 'B12', 'B13', 'B14', 'B17', 'B19', 'B21', 'B24', 'B28', 'B31', 'B33', 'P9', 'P11'] },
    large: { label: 'Крупное предприятие', desc: 'сложная структура, несколько цехов, службы', rec: 'all' }
  };
  function renderOrg() {
    var cur = AppData.settings.get('orgSize', 'medium');
    $('#orgCard').innerHTML = ['small', 'medium', 'large'].map(function (k) {
      var s = SIZES[k];
      return '<div class="role-card' + (cur === k ? ' active' : '') + '" data-size="' + k + '" style="display:flex;gap:12px;align-items:center;padding:12px;border:2px solid var(--border);border-radius:12px;margin-bottom:8px;cursor:pointer;' + (cur === k ? 'border-color:var(--accent);background:var(--accent-50);' : '') + '"><b style="font-size:.9rem;">' + s.label + '</b><span class="faint" style="font-size:.74rem;">' + s.desc + '</span></div>';
    }).join('');
    $$('#orgCard [data-size]').forEach(function (el) {
      el.addEventListener('click', function () { AppData.settings.set('orgSize', el.dataset.size); renderOrg(); });
    });
    var s = SIZES[cur];
    var ids = s.rec === 'all' ? null : s.rec;
    $('#orgModules').innerHTML = C.groups.map(function (g) {
      var apps = ids ? g.apps.filter(function (a) { return ids.indexOf(a.id) >= 0; }) : g.apps;
      if (!apps.length) return '';
      return '<div class="faint" style="font-size:.7rem;margin:6px 0 4px;">' + g.icon + ' ' + g.title + '</div>' + apps.map(function (a) { return '<span class="tag" style="margin:3px 4px 0 0;">' + a.id + ' ' + a.title + '</span>'; }).join('');
    }).join('');
  }
  $('#applyPreset').addEventListener('click', function () {
    var cur = AppData.settings.get('orgSize', 'medium');
    var rec = SIZES[cur].rec;
    var flags = {};
    C.groups.forEach(function (g) { g.apps.forEach(function (a) { flags[a.id] = (rec === 'all') ? true : (rec.indexOf(a.id) >= 0); }); });
    AppData.settings.set('flags', flags);
    AppData.log.add({ action: 'Применён пресет', detail: SIZES[cur].label });
    renderModules();
    App.toast('Пресет «' + SIZES[cur].label + '» применён');
  });

  /* ---------- Дашборды ---------- */
  function renderDash() {
    var plans = {}; TENANTS.forEach(function (t) { plans[t.plan] = (plans[t.plan] || 0) + 1; });
    var mrr = TENANTS.reduce(function (a, t) { return a + t.mrr; }, 0);
    $('#dashKpi').innerHTML =
      kpi('accent', App.number(mrr / 1000) + ' тыс.', 'MRR') +
      kpi('info', TENANTS.length, 'Тенантов') +
      kpi('success', C.countModules(), 'Модулей') +
      kpi('accent', C.countApps(), 'Приложений') +
      kpi('warning', AppData.problems.open().length, 'Проблем') +
      kpi('success', AppData.notifications.unread(), 'Уведомл.');
    var maxp = Math.max.apply(null, Object.keys(plans).map(function (k) { return plans[k]; }).concat([1]));
    $('#dashPlans').innerHTML = Object.keys(plans).map(function (k) {
      return '<div style="margin-bottom:10px;"><div class="row between" style="font-size:.8rem;"><span>' + k + '</span><b>' + plans[k] + '</b></div><div class="progress" style="margin-top:4px;"><span style="width:' + Math.round(plans[k] / maxp * 100) + '%"></span></div></div>';
    }).join('');
    $('#dashGroups').innerHTML = C.groups.map(function (g) {
      return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span>' + g.icon + ' ' + g.title + '</span><b>' + g.apps.length + '</b></div>';
    }).join('');
  }
  function kpi(c, v, l) { return '<div class="stat"><div class="num ' + c + '" style="font-size:1.3rem;">' + v + '</div><div class="label">' + l + '</div></div>'; }

  /* ---------- Размер шрифта ---------- */
  $('#fontMinus').addEventListener('click', function () { window.setFontScale(window.getFontScale() - 5); });
  $('#fontPlus').addEventListener('click', function () { window.setFontScale(window.getFontScale() + 5); });
  $('#fontReset').addEventListener('click', function () { window.setFontScale(100); });

  renderOverview(); renderOrg(); renderTenants(); renderUsers(); renderModules(); renderDash(); renderLog(); renderSettings();
})();
