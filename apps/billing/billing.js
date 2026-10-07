/* ============================================================
   3DMP Service · apps/billing — биллинг и подписки (W7).
   Данные: 0152 (тарифы+лимиты, подписки, счета платформы, статус-борд).
   Доступ: администратор платформы (все организации) и владелец (своя).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB, EX = window.AppExport;
  var token = null, me = null, isAdmin = false;
  var plans = [], sub = null, usage = [], subsList = [], invoices = [], tenants = [];
  var board = [], history = [], healthLoaded = false;

  var STATUS = {
    trial: 'Пробный', active: 'Активна', past_due: 'Просрочена', suspended: 'Приостановлена', cancelled: 'Отменена'
  };
  var INV = {
    draft: { l: 'Черновик', k: '' }, issued: { l: 'Выставлен', k: 'on' },
    paid: { l: 'Оплачен', k: 'done' }, overdue: { l: 'Просрочен', k: 'cancelled' }, cancelled: { l: 'Отменён', k: 'cancelled' }
  };
  var HSTAT = { ok: { l: 'Норма', k: 'ok' }, warn: { l: 'Внимание', k: 'warn' }, fail: { l: 'Сбой', k: 'fail' } };

  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function money(v) { return (Number(v) || 0).toLocaleString('ru-RU') + ' ₽'; }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }
  function fmtD(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? '—' : x.toLocaleDateString('ru-RU'); }
  function statusLabel(s) { return STATUS[s] || s || '—'; }

  /* ---------- Вкладки ---------- */
  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'health' && !healthLoaded) { healthLoaded = true; loadHealth(); }
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  /* ---------- KPI и обзор ---------- */
  function renderKpi(k) {
    k = k || {};
    var mrr = Number(k.mrr) || 0;
    $('#kpis').innerHTML =
      cell('Организаций', k.tenants || 0) +
      cell('Активных подписок', k.active_subs || 0) +
      cell('MRR', money(mrr)) +
      cell('Просрочено', money(k.overdue_amount), (Number(k.overdue_amount) > 0) ? '#b91c1c' : '') +
      cell('Выставлено', money(k.issued_amount)) +
      cell('Оплачено', money(k.paid_amount));
  }

  function renderSub() {
    if (!sub) { $('#sub').innerHTML = '<span class="note">Подписка не оформлена.</span>'; return; }
    var days = sub.days_left;
    var dl = days == null ? '—' : (days < 0 ? ('просрочена на ' + Math.abs(days) + ' дн.') : (days + ' дн.'));
    $('#sub').innerHTML =
      '<div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap;">' +
        '<b style="font-size:1.1rem;">' + esc(sub.plan_name || sub.plan_code) + '</b>' +
        '<span class="bl-badge ' + (sub.status === 'active' ? 'ok' : sub.status === 'past_due' || sub.status === 'suspended' ? 'fail' : '') + '">' + esc(statusLabel(sub.status)) + '</span>' +
      '</div>' +
      '<div class="note" style="margin:8px 0;">' + esc(sub.tenant_name || '') + ' · ' + money(sub.amount) + ' / ' + (sub.price_period === 'year' ? 'год' : 'мес.') +
        ' · мест: ' + (sub.seats || '—') + ' · до ' + fmtD(sub.period_end) + ' (' + esc(dl) + ')</div>' +
      '<div class="note">Автопродление: ' + (sub.auto_renew ? 'включено' : 'выключено') + '</div>' +
      (sub.note ? '<div class="note" style="margin-top:6px;">' + esc(sub.note) + '</div>' : '');
  }

  function renderUsage() {
    if (!usage.length) { $('#usage').innerHTML = '<span class="note">Нет данных.</span>'; return; }
    $('#usage').innerHTML = usage.map(function (u) {
      var q = (u.quota == null) ? null : Number(u.quota);
      var used = Number(u.used) || 0;
      var pct = q == null ? null : (q === 0 ? 100 : Math.min(999, Math.round(used / q * 100)));
      var cls = pct == null ? '' : (pct >= 100 ? 'over' : pct >= 80 ? 'warn' : '');
      var right = q == null ? '∞' : (used + ' / ' + q + ' ' + (u.unit || ''));
      return '<div style="margin-bottom:12px;">' +
        '<div style="display:flex;justify-content:space-between;font-size:.82rem;"><span>' + esc(u.label) + '</span><b>' + esc(right) + '</b></div>' +
        (q == null ? '' : '<div class="bl-prog ' + cls + '"><i style="width:' + pct + '%"></i></div>') +
        '</div>';
    }).join('');
  }

  function renderSubsList() {
    $('#subsCnt').textContent = '(' + subsList.length + ')';
    $('#subs').innerHTML = '<thead><tr><th>Организация</th><th>Тариф</th><th>Статус</th><th>Период</th><th class="num">Сумма</th><th class="num">Польз.</th><th></th></tr></thead><tbody>' +
      subsList.map(function (s) {
        var ul = (s.users_limit == null) ? '∞' : s.users_limit;
        return '<tr><td><b>' + esc(s.tenant_name) + '</b></td>' +
          '<td>' + esc(s.plan_name || s.plan_code) + '</td>' +
          '<td><span class="bl-badge ' + (s.status === 'active' ? 'ok' : (s.status === 'past_due' || s.status === 'suspended') ? 'fail' : '') + '">' + esc(statusLabel(s.status)) + '</span></td>' +
          '<td class="muted">' + fmtD(s.period_start) + ' — ' + fmtD(s.period_end) + '</td>' +
          '<td class="num">' + money(s.amount) + '</td>' +
          '<td class="num">' + s.users_used + ' / ' + ul + '</td>' +
          '<td><button class="act" data-subedit="' + s.tenant_id + '">Изменить</button></td></tr>';
      }).join('') + '</tbody>';
    $$('#subs [data-subedit]').forEach(function (b) {
      b.addEventListener('click', function () { openSub(null, b.dataset.subedit); });
    });
  }

  function renderPlans() {
    $('#plans').innerHTML = plans.map(function (p) {
      var lim = p.limits || {};
      var keys = [['users', 'пользователей'], ['orders', 'заявок'], ['naryads', 'нарядов'], ['documents', 'документов'], ['storage_mb', 'МБ файлов'], ['suppliers', 'поставщиков']];
      var lis = keys.map(function (k) {
        var v = lim[k[0]]; return '<li>' + k[1] + ': ' + (v == null ? '∞' : v) + '</li>';
      }).join('');
      var cur = (sub && sub.plan_code === p.code) ? ' current' : '';
      return '<div class="bl-plan' + cur + '">' +
        '<h3>' + esc(p.name) + (cur ? ' <span class="bl-badge ok">текущий</span>' : '') + '</h3>' +
        '<div class="price">' + money(p.price) + ' <span class="note" style="font-size:.75rem;">/ ' + (p.period === 'year' ? 'год' : 'мес.') + '</span></div>' +
        '<div class="note">' + esc(p.description || '') + '</div>' +
        '<ul>' + lis + '</ul></div>';
    }).join('') || '<span class="note">Тарифы не заданы.</span>';
  }

  /* ---------- Счета ---------- */
  function renderInvoices() {
    if (!invoices.length) { $('#invoices').innerHTML = '<span class="note">Счетов нет.</span>'; return; }
    $('#invoices').innerHTML = '<div class="tbl-wrap"><table class="tbl"><thead><tr>' +
      '<th>Номер</th><th>Организация</th><th>Период</th><th class="num">Сумма</th><th>Статус</th><th>Срок</th><th>Действия</th>' +
      '</tr></thead><tbody>' + invoices.map(function (i) {
        var st = INV[i.status] || { l: i.status, k: '' };
        var acts = '';
        if (isAdmin) {
          if (i.status === 'draft') acts += '<button class="act" data-invset="' + i.id + '" data-to="issued">Выставить</button>';
          if (i.status === 'issued') acts += '<button class="act" data-invset="' + i.id + '" data-to="paid">Оплачен</button><button class="act danger" data-invset="' + i.id + '" data-to="overdue">Просрочен</button>';
          if (i.status === 'overdue') acts += '<button class="act" data-invset="' + i.id + '" data-to="paid">Оплачен</button>';
          acts += '<button class="act" data-invedit="' + i.id + '">Изменить</button>';
        }
        return '<tr><td><b>' + esc(i.number || '—') + '</b></td>' +
          '<td>' + esc(i.tenant_name || '—') + '</td>' +
          '<td class="muted">' + fmtD(i.period_start) + ' — ' + fmtD(i.period_end) + '</td>' +
          '<td class="num">' + money(i.amount) + '</td>' +
          '<td><span class="badge ' + st.k + '">' + esc(st.l) + '</span></td>' +
          '<td class="muted">' + fmtD(i.due_at) + '</td>' +
          '<td style="white-space:nowrap;">' + acts + '</td></tr>';
      }).join('') + '</tbody></table></div>';
    $$('#invoices [data-invset]').forEach(function (b) {
      b.addEventListener('click', function () {
        rpc('app_platform_invoice_set_status', { p_token: token, p_id: b.dataset.invset, p_status: b.dataset.to })
          .then(function (r) { var x = r && r[0]; msg('#iMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadInvoices(); });
      });
    });
    $$('#invoices [data-invedit]').forEach(function (b) {
      b.addEventListener('click', function () { openInvoice(invoices.filter(function (x) { return x.id === b.dataset.invedit; })[0]); });
    });
  }

  function invFields() {
    var tOpts = [{ value: '', label: '— выберите организацию —' }].concat(tenants.map(function (t) { return { value: t.id, label: t.name }; }));
    var pOpts = plans.map(function (p) { return { value: p.code, label: p.name }; });
    return [
      { name: 'tenant_id', label: 'Организация', type: 'select', options: tOpts, required: true },
      { name: 'plan_code', label: 'Тариф', type: 'select', options: pOpts },
      { name: 'period_start', label: 'Начало периода', type: 'date' },
      { name: 'period_end', label: 'Окончание периода', type: 'date' },
      { name: 'amount', label: 'Сумма, ₽', type: 'number' },
      { name: 'due_at', label: 'Оплатить до', type: 'date' },
      { name: 'note', label: 'Примечание', type: 'text' }
    ];
  }

  function openInvoice(i) {
    i = i || {};
    ui.formDialog({
      title: i.id ? 'Счёт ' + (i.number || '') : 'Новый счёт платформы',
      okText: i.id ? 'Сохранить' : 'Создать',
      fields: invFields(),
      values: {
        tenant_id: i.tenant_id || '', plan_code: i.plan_code || '',
        period_start: i.period_start || '', period_end: i.period_end || '',
        amount: i.amount != null ? i.amount : '', due_at: i.due_at || '', note: i.note || ''
      }
    }).then(function (v) {
      if (!v) return;
      rpc('app_platform_invoice_save', {
        p_token: token, p_id: i.id || null, p_tenant: v.tenant_id || null, p_plan: v.plan_code || null,
        p_period_start: v.period_start || null, p_period_end: v.period_end || null,
        p_amount: v.amount === '' ? null : Number(v.amount), p_due_at: v.due_at || null, p_note: v.note || null
      }).then(function (r) {
        var x = r && r[0];
        if (!x || !x.ok) { msg('#iMsg', x ? x.message : 'Ошибка', 'err'); return; }
        window.Auth.log(i.id ? 'Биллинг: изменён счёт' : 'Биллинг: создан счёт', x.message);
        msg('#iMsg', x.message, 'ok'); loadInvoices();
      }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
    });
  }

  /* ---------- Подписка (форма) ---------- */
  function openSub(s, tenantId) {
    var tid = tenantId || (s && s.tenant_id) || (sub && sub.tenant_id) || null;
    var cur = s || (sub && sub.tenant_id === tid ? sub : null) || {};
    var fields = [];
    if (isAdmin) {
      fields.push({ name: 'tenant_id', label: 'Организация', type: 'select', options: tenants.map(function (t) { return { value: t.id, label: t.name }; }), required: true });
    }
    fields = fields.concat([
      { name: 'plan_code', label: 'Тариф', type: 'select', options: plans.map(function (p) { return { value: p.code, label: p.name }; }) },
      { name: 'status', label: 'Статус', type: 'select', options: Object.keys(STATUS).map(function (k) { return { value: k, label: STATUS[k] }; }) },
      { name: 'seats', label: 'Мест (пользователей)', type: 'number' },
      { name: 'amount', label: 'Сумма, ₽ / период', type: 'number' },
      { name: 'period_start', label: 'Начало периода', type: 'date' },
      { name: 'period_end', label: 'Окончание периода', type: 'date' },
      { name: 'auto_renew', label: 'Автопродление', type: 'checkbox' },
      { name: 'note', label: 'Примечание', type: 'text' }
    ]);
    ui.formDialog({
      title: 'Подписка организации', okText: 'Сохранить', fields: fields,
      values: {
        tenant_id: tid || '', plan_code: cur.plan_code || '', status: cur.status || 'active',
        seats: cur.seats != null ? cur.seats : '', amount: cur.amount != null ? cur.amount : '',
        period_start: cur.period_start || '', period_end: cur.period_end || '',
        auto_renew: cur.auto_renew === false ? '' : 'да', note: cur.note || ''
      }
    }).then(function (v) {
      if (!v) return;
      rpc('app_subscription_save', {
        p_token: token, p_tenant: isAdmin ? (v.tenant_id || null) : null,
        p_plan: v.plan_code || null, p_status: v.status || 'active',
        p_seats: v.seats === '' ? null : Number(v.seats),
        p_amount: v.amount === '' ? null : Number(v.amount),
        p_period_start: v.period_start || null, p_period_end: v.period_end || null,
        p_auto_renew: !!v.auto_renew, p_note: v.note || null
      }).then(function (r) {
        var x = r && r[0];
        if (!x || !x.ok) { msg('#iMsg', x ? x.message : 'Ошибка', 'err'); return; }
        window.Auth.log('Биллинг: подписка', x.message);
        ui.toast(x.message);
        load();
      }).catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
    });
  }

  /* ---------- Доступность ---------- */
  function renderBoard() {
    if (!board.length) { $('#board').innerHTML = '<span class="note">Проверки ещё не выполнялись.</span>'; return; }
    $('#board').innerHTML = board.map(function (c) {
      var st = HSTAT[c.status] || { l: c.status, k: '' };
      return '<div class="bl-hcard">' +
        '<div style="display:flex;justify-content:space-between;align-items:center;gap:6px;"><b>' + esc(c.name) + '</b>' +
        '<span class="bl-badge ' + st.k + '">' + esc(st.l) + '</span></div>' +
        '<small>' + esc(c.detail || '') + '</small>' +
        '<small>' + (c.latency_ms != null ? (c.latency_ms + ' мс · ') : '') + fmtD(c.checked_at) + '</small>' +
        '</div>';
    }).join('');
  }
  function renderHistory() {
    if (!history.length) { $('#history').innerHTML = '<tbody><tr><td class="note">Нет записей.</td></tr></tbody>'; return; }
    $('#history').innerHTML = '<thead><tr><th>Проверка</th><th>Тип</th><th>Статус</th><th>Детали</th><th>Когда</th></tr></thead><tbody>' +
      history.map(function (c) {
        var st = HSTAT[c.status] || { l: c.status, k: '' };
        return '<tr><td>' + esc(c.name) + '</td><td class="muted">' + esc(c.kind) + '</td>' +
          '<td><span class="bl-badge ' + st.k + '">' + esc(st.l) + '</span></td>' +
          '<td class="muted">' + esc(c.detail || '') + '</td>' +
          '<td class="muted">' + new Date(c.checked_at).toLocaleString('ru-RU') + '</td></tr>';
      }).join('') + '</tbody>';
  }

  function loadHealth() {
    return Promise.all([
      rpc('app_health_board', { p_token: token }).catch(function () { return []; }),
      rpc('app_health_list', { p_token: token, p_limit: 40 }).catch(function () { return []; })
    ]).then(function (r) { board = r[0] || []; history = r[1] || []; renderBoard(); renderHistory(); });
  }

  function scan() {
    msg('#hMsg', 'Проверяю…', 'info');
    rpc('app_health_scan', { p_token: token })
      .then(function (r) {
        history = r || []; board = [];
        var seen = {};
        history.forEach(function (c) { if (!seen[c.kind]) { seen[c.kind] = 1; board.push(c); } });
        renderBoard(); renderHistory();
        var bad = board.filter(function (c) { return c.status !== 'ok'; }).length;
        msg('#hMsg', 'Проверка выполнена. Проблемных компонентов: ' + bad, bad ? 'err' : 'ok');
      })
      .catch(function (e) { msg('#hMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Загрузка ---------- */
  function loadInvoices() {
    return rpc('app_platform_invoice_list', { p_token: token, p_status: null })
      .then(function (r) { invoices = r || []; renderInvoices(); });
  }

  function load() {
    var tasks = [
      rpc('app_billing_kpi', { p_token: token }).catch(function () { return {}; }),
      rpc('app_billing_plans', { p_token: token }).catch(function () { return []; }),
      loadInvoices()
    ];
    if (isAdmin) {
      tasks.push(rpc('app_subscriptions_list', { p_token: token }).catch(function () { return []; }));
      tasks.push(rpc('app_platform_tenants', { p_token: token }).catch(function () { return []; }));
    } else {
      tasks.push(rpc('app_subscription_get', { p_token: token }).catch(function () { return []; }));
      tasks.push(rpc('app_billing_usage', { p_token: token }).catch(function () { return []; }));
    }
    return Promise.all(tasks).then(function (r) {
      renderKpi(r[0]);
      plans = r[1] || [];
      if (isAdmin) {
        subsList = r[3] || []; tenants = r[4] || [];
        $('#subsCard').style.display = '';
        renderSubsList();
      } else {
        sub = (r[3] && r[3][0]) || null; usage = r[4] || [];
        $('#subCard').style.display = ''; $('#usageCard').style.display = '';
        renderSub(); renderUsage();
      }
      renderPlans();
    }).catch(function (e) { ui.toast('Ошибка: ' + e.message); });
  }

  /* ---------- Действия ---------- */
  $('#btnSub').addEventListener('click', function () { openSub(null, null); });
  $('#btnInv').addEventListener('click', function () { openInvoice(null); });
  $('#btnScan').addEventListener('click', scan);
  $('#btnGen').addEventListener('click', function () {
    var now = new Date(), y = now.getFullYear(), m = now.getMonth();
    var p1 = new Date(y, m, 1), p2 = new Date(y, m + 1, 0);
    function iso(d) { return d.toISOString().slice(0, 10); }
    ui.formDialog({
      title: 'Сформировать счета за период', okText: 'Сформировать',
      fields: [
        { name: 'period_start', label: 'Начало периода', type: 'date' },
        { name: 'period_end', label: 'Окончание периода', type: 'date' }
      ],
      values: { period_start: iso(p1), period_end: iso(p2) }
    }).then(function (v) {
      if (!v) return;
      rpc('app_billing_generate_invoices', { p_token: token, p_period_start: v.period_start || null, p_period_end: v.period_end || null })
        .then(function (r) { var x = r && r[0]; msg('#iMsg', x ? x.message : '', 'ok'); loadInvoices(); });
    });
  });
  $('#btnInvPdf').addEventListener('click', function () {
    if (!EX) return;
    var rows = invoices.map(function (i) { return [i.number, i.tenant_name, fmtD(i.period_start) + '—' + fmtD(i.period_end), money(i.amount), (INV[i.status] || {}).l || i.status, fmtD(i.due_at)]; });
    EX.exportPdf('Счета платформы (' + new Date().toLocaleDateString('ru-RU') + ')',
      EX.tableHtml(['Номер', 'Организация', 'Период', 'Сумма', 'Статус', 'Срок'], rows));
  });
  $('#btnInvCsv').addEventListener('click', function () {
    if (!EX) return;
    EX.exportCsv('platform-invoices', ['Номер', 'Организация', 'Период с', 'Период по', 'Сумма', 'Статус', 'Срок'],
      invoices.map(function (i) { return [i.number, i.tenant_name, i.period_start, i.period_end, i.amount, i.status, i.due_at]; }));
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  /* ---------- Guard ---------- */
  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (s.role !== 'admin' && s.role !== 'owner') { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token; isAdmin = (s.role === 'admin');
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!isAdmin) { $$('[data-cap="platform"]').forEach(function (el) { el.style.display = 'none'; }); }
    if (!SB) { ui.toast('Supabase не подключён.'); return; }
    load();
  });
})();
