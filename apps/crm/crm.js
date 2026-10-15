/* ============================================================
   3DMP Service · apps/crm — CRM (сделки/воронка, заказчики)
   Данные: 0056 (+ app_customer_list). Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, deals = [], customers = [], campaigns = [], inbox = [], q = '';

  var STAGES = [['lead', 'Лид'], ['qualified', 'Квалифицирована'], ['proposal', 'Предложение'], ['negotiation', 'Переговоры'], ['won', 'Выиграна'], ['lost', 'Проиграна']];
  var SNAME = { lead: 'Лид', qualified: 'Квалифицирована', proposal: 'Предложение', negotiation: 'Переговоры', won: 'Выиграна', lost: 'Проиграна' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return num(v).toLocaleString('ru-RU', { maximumFractionDigits: 0 }) + ' ₽'; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_deal_list', { p_token: token, p_q: null }),
      rpc('app_deal_kpi', { p_token: token }),
      rpc('app_customer_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_campaign_list', { p_token: token }).catch(function () { return []; }),
      rpc('app_inbox_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      deals = r[0] || []; var k = (r[1] && r[1][0]) || {}; customers = r[2] || []; campaigns = r[3] || []; inbox = r[4] || [];
      $('#fCust').innerHTML = '<option value="">— выберите —</option>' + customers.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + '</option>'; }).join('');
      $('#kpis').innerHTML = cell('Сделок', num(k.deals_total)) + cell('Открытых', num(k.open_deals)) +
        cell('Воронка (взвеш.)', money(k.pipeline)) + cell('Выиграно', money(k.won_sum), '#15803d') + cell('Конверсия', num(k.conversion) + '%');
      render(); renderCustomers(); loadReminders(); renderFunnel(); renderForecast(); renderMkt(); renderCredit();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  /* R5·PROP-30: воронка и конверсия лид→сделка (по стадиям и источникам) */
  function renderFunnel() {
    var host = $('#funnel'); if (!host) return;
    if (!deals.length) { host.innerHTML = '<div class="card"><h2>Воронка и конверсия</h2><span class="note">Нет данных — добавьте лиды/сделки выше.</span></div>'; return; }
    var cnt = {}, sum = {};
    STAGES.forEach(function (s) { cnt[s[0]] = 0; sum[s[0]] = 0; });
    deals.forEach(function (d) { cnt[d.stage] = (cnt[d.stage] || 0) + 1; sum[d.stage] = (sum[d.stage] || 0) + num(d.amount); });
    var total = deals.length, won = cnt.won || 0, lost = cnt.lost || 0;
    var conv = total ? Math.round(won / total * 100) : 0;
    var reach = {}, cum = 0;
    ['won', 'negotiation', 'proposal', 'qualified', 'lead'].forEach(function (st) { cum += cnt[st] || 0; reach[st] = cum; });
    var base = reach.lead || 0;
    var rows = ['lead', 'qualified', 'proposal', 'negotiation', 'won'].map(function (st) {
      var pct = base ? Math.round((reach[st] || 0) / base * 100) : 0;
      return '<div class="kvr"><b style="min-width:140px;">' + SNAME[st] + '</b><span class="note">' + (cnt[st] || 0) + ' шт · ' + money(sum[st] || 0) + '</span><span class="badge" style="margin-left:auto;">' + pct + '%</span></div>';
    }).join('');
    var bySrc = {};
    deals.forEach(function (d) { var s = d.source || '(без источника)'; bySrc[s] = bySrc[s] || { all: 0, won: 0 }; bySrc[s].all++; if (d.stage === 'won') bySrc[s].won++; });
    var srcRows = Object.keys(bySrc).sort(function (a, b) { return bySrc[b].all - bySrc[a].all; }).slice(0, 8).map(function (s) {
      var o = bySrc[s], c = o.all ? Math.round(o.won / o.all * 100) : 0;
      return '<div class="kvr"><b style="min-width:140px;">' + esc(s) + '</b><span class="note">' + o.all + ' сд. · ' + o.won + ' выигр.</span><span class="badge" style="margin-left:auto;">' + c + '%</span></div>';
    }).join('');
    host.innerHTML = '<div class="card"><h2>Воронка и конверсия</h2>' +
      '<div class="legend" style="margin:6px 0;"><span>Всего сделок: <b>' + total + '</b></span><span>Выиграно: <b>' + won + '</b></span><span>Проиграно: <b>' + lost + '</b></span><span>Конверсия в выигрыш: <b>' + conv + '%</b></span></div>' +
      '<div class="cols"><div><h3 style="margin:6px 0;font-size:.82rem;">По стадиям (накопительно)</h3>' + rows + '</div>' +
      '<div><h3 style="margin:6px 0;font-size:.82rem;">По источникам</h3>' + (srcRows || '<span class="note">Источники не заполнены.</span>') + '</div></div></div>';
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function render() {
    var list = deals.filter(function (d) { if (!q) return true; var s = q.toLowerCase(); return [d.title, d.customer, d.owner_login].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + list.length + ')';
    $('#board').innerHTML = STAGES.map(function (st) {
      var items = list.filter(function (d) { return d.stage === st[0]; });
      return '<div class="col"><h3>' + st[1] + ' (' + items.length + ')</h3>' + (items.length ? items.map(dcard).join('') : '<span class="note" style="font-size:.74rem;">—</span>') + '</div>';
    }).join('');
    $$('#board [data-stage]').forEach(function (sel) {
      sel.addEventListener('change', function () {
        rpc('app_deal_set_stage', { p_token: token, p_id: sel.dataset.stage, p_stage: sel.value })
          .then(function (d) { var r = d && d[0]; if (r && !r.ok) { ui.toast(r.message); return; } window.Auth.log('CRM стадия', sel.value); if (window.AppNotify) window.AppNotify.refresh(true); load(); })
          .catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
      });
    });
  }
  function dcard(d) {
    return '<div class="dcard"><div style="font-weight:600;font-size:.84rem;">' + esc(d.title) + '</div>' +
      '<div style="font-size:.74rem;color:var(--muted);margin-top:3px;">' + (d.customer ? '🏢 ' + esc(d.customer) + ' · ' : '') + (d.owner_login ? '👤 ' + esc(d.owner_login) : '') + '</div>' +
      '<div style="font-size:.8rem;margin-top:4px;">' + money(d.amount) + ' · ' + num(d.probability) + '% → <b>' + money(d.weighted) + '</b></div>' +
      (d.next_action ? '<div class="note" style="margin-top:3px;">→ ' + esc(d.next_action) + (d.due_date ? ' (до ' + esc(d.due_date) + ')' : '') + '</div>' : '') +
      '<select data-stage="' + d.id + '" style="margin-top:6px;width:100%;padding:6px;border:1px solid var(--border);border-radius:8px;font-size:.78rem;">' +
      STAGES.map(function (s) { return '<option value="' + s[0] + '"' + (d.stage === s[0] ? ' selected' : '') + '>' + s[1] + '</option>'; }).join('') + '</select></div>';
  }
  function renderCustomers() {
    $('#customers').innerHTML = customers.length ? customers.map(function (c) {
      return '<div class="kvr"><b>' + esc(c.name) + '</b><span class="note">' + (c.inn ? 'ИНН ' + esc(c.inn) + ' · ' : '') + (c.contact_person ? esc(c.contact_person) + ' · ' : '') + (c.phone || '') + (c.email ? ' · ' + esc(c.email) : '') + '</span>' +
        '<button class="btn secondary" data-prof="' + c.id + '" style="width:auto;padding:2px 8px;font-size:.72rem;margin-left:auto;" aria-label="Профиль клиента" title="Профиль клиента 360°">👁 профиль</button></div>';
    }).join('') : '<span class="note">Заказчиков нет.</span>';
    $$('#customers [data-prof]').forEach(function (b) { b.addEventListener('click', function () { openProfile(b.dataset.prof); }); });
  }
  /* R5·PROP-31: профиль клиента 360° + прогноз продаж */
  function openProfile(id) {
    rpc('app_customer_card', { p_token: token, p_customer_id: id }).then(function (r) {
      var c = (r && r[0]) || null; if (!c) { ui.toast('Нет данных'); return; }
      var my = deals.filter(function (d) { return d.customer_id === id || (c.name && d.customer === c.name); });
      var pipe = my.reduce(function (s, d) { var w = num(d.weighted); if (!w) w = num(d.amount) * num(d.probability) / 100; return s + w; }, 0);
      ui.dialog({ title: 'Профиль клиента 360°', html: true, cancelText: 'Закрыть', body:
        '<div class="kvr"><b>' + esc(c.name) + '</b><span class="note">' + (c.inn ? 'ИНН ' + esc(c.inn) : '') + (c.phone ? ' · ' + esc(c.phone) : '') + '</span></div>' +
        '<div class="kpi-row">' + cell('Заявок', num(c.requests)) + cell('Открытых', num(c.open_requests)) + cell('Выполнено', num(c.done_requests)) +
        cell('Сумма заявок', money(c.cost_sum)) + cell('Оборудование', num(c.equipment_count)) + cell('Активных гарантий', num(c.active_warranties)) +
        cell('Договоров', num(c.contracts)) + cell('Сделок / воронка', my.length + ' / ' + money(pipe)) + '</div>' +
        '<h3 style="margin:8px 0 4px;font-size:.82rem;">Сделки клиента</h3>' +
        (my.length ? my.map(function (d) { return '<div class="kvr"><b>' + esc(d.title) + '</b><span class="note">' + (SNAME[d.stage] || d.stage) + ' · ' + money(d.amount) + '</span><span class="badge" style="margin-left:auto;">' + num(d.probability) + '%</span></div>'; }).join('') : '<span class="note">Сделок нет.</span>') +
        '<p class="note" style="margin-top:8px;">Заявки/сервис/гарантии — в модулях «Заявки», «Сервис», «Качество».</p>' });
    }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
  }
  function renderForecast() {
    var host = $('#forecast'); if (!host) return;
    var months = {}, order = [], now = new Date();
    deals.forEach(function (d) {
      if (d.stage === 'won' || d.stage === 'lost') return;
      var w = num(d.weighted); if (!w) w = num(d.amount) * num(d.probability) / 100;
      var base = d.due_date ? new Date(d.due_date) : now;
      var k = base.getFullYear() + '-' + String(base.getMonth() + 1).padStart(2, '0');
      if (!months[k]) { months[k] = { w: 0, n: 0 }; order.push(k); }
      months[k].w += w; months[k].n++;
    });
    order.sort();
    var total = order.reduce(function (s, k) { return s + months[k].w; }, 0);
    host.innerHTML = '<div class="card"><h2>Прогноз продаж (взвешенная воронка)</h2>' +
      (order.length ? '<div class="legend" style="margin:6px 0;"><span>Прогноз всего: <b>' + money(total) + '</b></span></div>' +
        order.map(function (k) { return '<div class="kvr"><b style="min-width:110px;">' + k + '</b><span class="note">' + months[k].n + ' сд.</span><span class="badge" style="margin-left:auto;">' + money(months[k].w) + '</span></div>'; }).join('')
        : '<span class="note">Открытых сделок нет.</span>') + '</div>';
  }
  /* R4·PROP-22: кредитный лимит клиента (CPQ/ATP — конфигуратор + остатки) */
  function renderCredit() {
    var host = $('#credit'); if (!host) return;
    host.innerHTML = '<div class="card"><h2>Кредитный лимит и доступность</h2>' +
      '<div class="grid3"><div class="field"><label>Заказчик</label><select id="crCust"><option value="">— выберите —</option>' + customers.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + '</option>'; }).join('') + '</select></div>' +
      '<div class="field"><label>Лимит, ₽</label><input type="text" id="crLimit" inputmode="decimal"></div>' +
      '<div class="field" style="display:flex;align-items:flex-end;gap:6px;"><button class="btn secondary" id="crSet" style="width:auto;">Сохранить лимит</button><button class="btn secondary" id="crCheck" style="width:auto;">Проверить</button></div></div>' +
      '<div id="crRes" class="mt"></div>' +
      '<p class="note" style="margin-top:6px;">ATP (доступность) = остаток материала — «Справочники → Материалы» и «Склад»; CPQ (конфигурация предложения) — модули «Конфигуратор» и «ТКП».</p></div>';
    var ss = $('#crSet'); if (ss) ss.addEventListener('click', function () {
      rpc('app_customer_set_credit', { p_token: token, p_customer_id: $('#crCust').value || null, p_limit: parseFloat($('#crLimit').value.replace(',', '.')) || 0 })
        .then(function (r) { var x = r && r[0]; ui.toast(x ? x.message : ''); }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
    });
    var cc = $('#crCheck'); if (cc) cc.addEventListener('click', function () {
      if (!$('#crCust').value) { $('#crRes').innerHTML = '<span class="note">Выберите заказчика.</span>'; return; }
      rpc('app_customer_credit', { p_token: token, p_customer_id: $('#crCust').value }).then(function (r) {
        r = r || [];
        $('#crRes').innerHTML = r.length ? '<div class="kpi-row">' + cell('Лимит', money(r[0].credit_limit)) + cell('Долг', money(r[0].debt)) + cell('Доступно', money(r[0].available)) + cell('Статус', r[0].ok ? 'в пределах лимита' : 'превышение') + '</div>'
          : '<span class="note">Нет данных.</span>';
      }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
    });
  }
  /* R4·PROP-28: маркетинг (кампании) + контакт-центр (обращения) */
  function renderMkt() {
    var host = $('#mkt'); if (!host) return;
    var camp = campaigns.length ? '<div class="tbl-wrap mt"><table class="tbl"><thead><tr><th>Кампания</th><th>Канал</th><th>Сегмент</th><th>Статус</th><th class="num">Отпр.</th><th class="num">Отклик</th><th class="num">Конв.</th><th></th></tr></thead><tbody>' +
      campaigns.map(function (c) { var cv = num(c.sent) ? Math.round(num(c.response) / num(c.sent) * 100) : 0; return '<tr><td><b>' + esc(c.name) + '</b></td><td>' + esc(c.channel || '—') + '</td><td>' + esc(c.segment || '—') + '</td><td>' + esc(c.status) + '</td><td class="num">' + num(c.sent) + '</td><td class="num">' + num(c.response) + '</td><td class="num">' + cv + '%</td><td><button class="act danger" data-cdel="' + c.id + '" aria-label="Удалить" title="Удалить">✕</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Кампаний нет.</span>';
    var inb = inbox.length ? inbox.map(function (i) { var od = i.due_at && new Date(i.due_at).getTime() < Date.now() && i.status !== 'closed'; return '<div class="kvr"><b>' + esc(i.subject || '(без темы)') + '</b><span class="note">' + esc(i.channel || '') + (i.contact ? ' · ' + esc(i.contact) : '') + (i.due_at ? ' · до ' + ui.fmtDate(i.due_at) : '') + (od ? ' · ПРОСРОЧЕНО' : '') + '</span><span class="badge" style="margin-left:auto;">' + esc(i.status) + '</span>' + (i.status !== 'closed' ? '<button class="act" data-iclose="' + i.id + '">Закрыть</button>' : '') + '</div>'; }).join('') : '<span class="note">Обращений нет.</span>';
    host.innerHTML = '<div class="card"><h2>Маркетинг: кампании</h2>' +
      '<div class="grid3"><div class="field"><label>Название *</label><input type="text" id="mName"></div><div class="field"><label>Канал</label><input type="text" id="mChan" placeholder="e-mail / Telegram / звонок"></div><div class="field"><label>Сегмент</label><input type="text" id="mSeg" placeholder="ключевые клиенты"></div></div>' +
      '<div class="grid3"><div class="field"><label>Статус</label><select id="mStatus"><option value="planned">План</option><option value="active">Активна</option><option value="done">Завершена</option><option value="paused">Пауза</option></select></div><div class="field"><label>Дата</label><input type="date" id="mDate"></div><div class="field"><label>Бюджет, ₽</label><input type="text" id="mBud" inputmode="decimal"></div></div>' +
      '<div class="btn-row"><button class="btn" id="mSave">Добавить кампанию</button></div>' + camp + '</div>' +
      '<div class="card mt"><h2>Контакт-центр (обращения)</h2>' +
      '<div class="grid3"><div class="field"><label>Канал</label><input type="text" id="iChan" placeholder="телефон / e-mail / сайт"></div><div class="field"><label>Контакт</label><input type="text" id="iContact"></div><div class="field"><label>Тема</label><input type="text" id="iSubj"></div></div>' +
      '<div class="btn-row"><button class="btn" id="iAdd">Зарегистрировать обращение</button></div>' + inb + '</div>';
    if (window.AppUI && AppUI.dictSuggest) { AppUI.dictSuggest('mChan', 'contact_channels', token); AppUI.dictSuggest('iChan', 'contact_channels', token); }
    var ms = $('#mSave'); if (ms) ms.addEventListener('click', function () {
      rpc('app_campaign_save', { p_token: token, p_id: null, p_name: $('#mName').value.trim(), p_channel: $('#mChan').value.trim() || null, p_segment: $('#mSeg').value.trim() || null, p_status: $('#mStatus').value, p_planned_date: $('#mDate').value || null, p_budget: parseFloat($('#mBud').value.replace(',', '.')) || null, p_sent: 0, p_response: 0, p_note: null })
        .then(function (r) { var x = r && r[0]; ui.toast(x ? x.message : ''); if (x && x.ok) load(); }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
    });
    $$('#mkt [data-cdel]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить кампанию?')) return; rpc('app_campaign_delete', { p_token: token, p_id: b.dataset.cdel }).then(load); }); });
    var ia = $('#iAdd'); if (ia) ia.addEventListener('click', function () {
      rpc('app_inbox_add', { p_token: token, p_channel: $('#iChan').value.trim() || null, p_contact: $('#iContact').value.trim() || null, p_subject: $('#iSubj').value.trim() || null, p_body: null, p_priority: 'normal', p_sla_hours: 24, p_assignee: null })
        .then(function (r) { var x = r && r[0]; ui.toast(x ? x.message : ''); if (x && x.ok) load(); }).catch(function (e) { ui.toast('Ошибка: ' + e.message, 'err'); });
    });
    $$('#mkt [data-iclose]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_inbox_set_status', { p_token: token, p_id: b.dataset.iclose, p_status: 'closed' }).then(load); }); });
  }

  /* ---------- R1: напоминания ---------- */
  var CH = { call: 'Звонок', meeting: 'Встреча', email: 'E-mail', telegram: 'Telegram', sms: 'SMS', task: 'Задача' };
  var reminders = [];
  function loadReminders() {
    return rpc('app_crm_reminders_list', { p_token: token, p_status: null }).then(function (r) { reminders = r || []; renderReminders(); })
      .catch(function (e) { msg('#remMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderReminders() {
    var open = reminders.filter(function (x) { return x.status === 'open'; });
    $('#remCnt').textContent = '(' + open.length + ' открытых из ' + reminders.length + ')';
    $('#remList').innerHTML = reminders.length ? '<table class="mini"><thead><tr><th>Срок</th><th>Сделка</th><th>Тема</th><th>Канал</th><th class="num">Дней</th><th>Статус</th><th></th></tr></thead><tbody>' +
      reminders.map(function (r) {
        var st = r.status === 'open' ? '' : (r.status === 'done' ? 'done' : 'cancelled');
        var late = (r.days_left != null && r.days_left < 0 && r.status === 'open');
        return '<tr><td>' + (r.due_at ? new Date(r.due_at).toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—') + '</td>' +
          '<td>' + esc(r.deal_title || r.customer || '—') + '</td><td>' + esc(r.title) + '</td><td>' + esc(CH[r.channel] || r.channel) + '</td>' +
          '<td class="num" style="' + (late ? 'color:#b91c1c;font-weight:700;' : '') + '">' + (r.days_left != null ? r.days_left : '—') + '</td>' +
          '<td><span class="badge ' + st + '">' + (r.status === 'open' ? 'Открыто' : r.status === 'done' ? 'Готово' : 'Отменено') + '</span></td>' +
          '<td style="white-space:nowrap;">' + (r.status === 'open' ? '<button class="act" data-remdone="' + r.id + '" data-cap="edit">Готово</button>' : '') + '</td></tr>';
      }).join('') + '</tbody></table>' : '<span class="note">Напоминаний нет.</span>';
    $$('#remList [data-remdone]').forEach(function (b) {
      b.addEventListener('click', function () { rpc('app_crm_reminder_set_status', { p_token: token, p_id: b.dataset.remdone, p_status: 'done' }).then(loadReminders).catch(function (e) { msg('#remMsg', e.message, 'err'); }); });
    });
  }
  function openReminder() {
    ui.formDialog({
      title: 'Напоминание по сделке', okText: 'Создать', fields: [
        { name: 'deal_id', label: 'Сделка', type: 'select', options: [{ value: '', label: '— без сделки —' }].concat(deals.map(function (d) { return { value: d.id, label: d.title + (d.customer ? ' · ' + d.customer : '') }; })) },
        { name: 'title', label: 'Тема', type: 'text', required: true },
        { name: 'due_at', label: 'Срок', type: 'datetime-local' },
        { name: 'channel', label: 'Канал', type: 'select', options: Object.keys(CH).map(function (k) { return { value: k, label: CH[k] }; }) },
        { name: 'note', label: 'Заметка', type: 'text' }
      ], values: { channel: 'call' }
    }).then(function (v) {
      if (!v) return;
      rpc('app_crm_reminder_save', { p_token: token, p_id: null, p_deal_id: v.deal_id || null, p_title: v.title, p_due_at: v.due_at ? new Date(v.due_at).toISOString() : null, p_channel: v.channel, p_note: v.note || null })
        .then(function (r) { var x = r && r[0]; msg('#remMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadReminders(); });
    });
  }
  function scanReminders() {
    rpc('app_crm_reminder_scan', { p_token: token }).then(function (r) { var x = r && r[0]; msg('#remMsg', x ? x.message : '', 'ok'); loadReminders(); })
      .catch(function (e) { msg('#remMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#remAdd').addEventListener('click', openReminder);
  $('#remScan').addEventListener('click', scanReminders);
  $('#fAdd').addEventListener('click', function () {
    var title = $('#fTitle').value.trim(); if (!title) { msg('#fMsg', 'Укажите название сделки.', 'err'); return; }
    var amt = parseFloat(($('#fAmount').value || '').replace(',', '.')); var pr = parseInt($('#fProb').value || '', 10);
    rpc('app_deal_save', { p_token: token, p_id: null, p_customer_id: $('#fCust').value || null, p_title: title, p_stage: $('#fStage').value,
      p_amount: isNaN(amt) ? null : amt, p_probability: isNaN(pr) ? 10 : pr, p_source: $('#fSource').value.trim(), p_owner: $('#fOwner').value.trim(),
      p_next_action: $('#fNext').value.trim(), p_due_date: $('#fDue').value || null, p_order_id: null, p_note: null })
      .then(function (d) { var r = d && d[0]; msg('#fMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('CRM сделка', title); ['#fTitle', '#fAmount', '#fProb', '#fOwner', '#fSource', '#fNext', '#fDue'].forEach(function (s) { $(s).value = ''; }); load(); } })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#scoreBtn').addEventListener('click', function () {
    rpc('app_lead_score', { p_token: token }).then(function (rows) {
      rows = rows || [];
      var BAND = { 'горячий': '#b91c1c', 'тёплый': '#b45309', 'холодный': '#64748b' };
      var html = '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Сделка</th><th>Стадия</th><th class="num">Сумма</th><th class="num">Балл</th><th>Категория</th><th>Срок</th></tr></thead><tbody>' +
        (rows.length ? rows.map(function (r) {
          return '<tr><td>' + esc(r.title) + '</td><td>' + esc(r.stage) + '</td><td class="num">' + (Number(r.amount) || 0).toLocaleString('ru-RU') + ' ₽</td>' +
            '<td class="num"><b>' + r.score + '</b></td><td style="color:' + (BAND[r.band] || '#334155') + ';font-weight:600;">' + esc(r.band) + '</td><td>' + (r.due_date || '') + '</td></tr>';
        }).join('') : '<tr><td colspan="6" class="note">Открытых сделок нет</td></tr>') + '</tbody></table></div>';
      ui.dialog({ title: 'Скоринг лидов', body: html, html: true, cancelText: 'Закрыть' });
    }).catch(function (e) { window.alert('Ошибка: ' + e.message); });
  });
  $('#contactsBtn').addEventListener('click', function () {
    Promise.all([
      rpc('app_deal_list', { p_token: token, p_q: null }).catch(function () { return []; }),
      rpc('app_crm_contact_list', { p_token: token, p_deal_id: null }).catch(function () { return []; })
    ]).then(function (res) {
      var deals = res[0] || [], rows = res[1] || [];
      var KIND = { call: '📞 Звонок', email: '✉ Письмо', meeting: '🤝 Встреча', note: '📝 Заметка' };
      function listHtml() {
        return rows.length ? '<div class="tbl-wrap" style="max-height:260px;overflow:auto"><table class="tbl"><thead><tr><th>Когда</th><th>Сделка</th><th>Вид</th><th>Напр.</th><th>Тема</th><th>Кто</th></tr></thead><tbody>' +
          rows.map(function (k) { return '<tr><td class="muted">' + new Date(k.at).toLocaleString('ru-RU') + '</td><td>' + esc(k.deal || '—') + '</td><td>' + esc(KIND[k.kind] || k.kind) + '</td><td>' + (k.direction === 'in' ? '↙ вх' : '↗ исх') + '</td><td>' + esc(k.subject || k.body || '') + '</td><td class="muted">' + esc(k.by_login || '') + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<span class="note">Контактов нет.</span>';
      }
      var body = '<div class="form-grid" style="margin-bottom:10px">' +
        '<div class="field"><label>Сделка</label><select id="ctDeal"><option value="">— без сделки —</option>' + deals.map(function (d) { return '<option value="' + d.id + '">' + esc(d.title) + '</option>'; }).join('') + '</select></div>' +
        '<div class="field"><label>Вид</label><select id="ctKind"><option value="call">Звонок</option><option value="email">Письмо</option><option value="meeting">Встреча</option><option value="note">Заметка</option></select></div>' +
        '<div class="field"><label>Направление</label><select id="ctDir"><option value="out">Исходящий</option><option value="in">Входящий</option></select></div>' +
        '<div class="field"><label>Тема</label><input id="ctSubj"></div>' +
        '<div class="field" style="grid-column:1/-1"><label>Текст</label><input id="ctBody"></div></div>' +
        '<div class="btn-row"><button class="btn secondary" id="ctAdd">＋ Добавить контакт</button><span id="ctMsg" class="note"></span></div>' +
        '<div class="mt">' + listHtml() + '</div>';
      ui.dialog({ title: 'Журнал контактов (почта/телефония)', body: body, html: true, cancelText: 'Закрыть' });
      var add = document.getElementById('ctAdd');
      if (add) add.addEventListener('click', function () {
        rpc('app_crm_contact_add', { p_token: token, p_deal_id: document.getElementById('ctDeal').value || null, p_customer_id: null,
          p_kind: document.getElementById('ctKind').value, p_direction: document.getElementById('ctDir').value,
          p_subject: document.getElementById('ctSubj').value, p_body: document.getElementById('ctBody').value })
          .then(function (d) { var r = d && d[0]; var m = document.getElementById('ctMsg'); m.className = 'note ' + (r && r.ok ? 'ok' : 'err'); m.textContent = (r && r.message) || ''; if (r && r.ok) { window.Auth.log('CRM контакт', r.id); rows.unshift({ at: new Date().toISOString(), deal: (deals.filter(function (x) { return x.id === document.getElementById('ctDeal').value; })[0] || {}).title, kind: document.getElementById('ctKind').value, direction: document.getElementById('ctDir').value, subject: document.getElementById('ctSubj').value, by_login: me && me.login }); } })
          .catch(function (e) { window.alert('Ошибка: ' + e.message); });
      });
    }).catch(function (e) { window.alert('Ошибка: ' + e.message); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
  if (window.AppUI && AppUI.dictSuggest) AppUI.dictSuggest('fSource', 'request_sources', token);
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
