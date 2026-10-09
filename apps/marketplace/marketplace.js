/* ============================================================
   3DMP Service · apps/marketplace — M1 маркетплейс мощностей. Данные: 0071.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, listings = [], requests = [], q = '';

  var PR = { cnc: 'ЧПУ', edm: 'ЭЭО', grinding: 'Шлифование', heat: 'Термообработка', assembly: 'Сборка', engraving: 'Гравирование', other: 'Прочее' };
  var EK = { connector: 'Коннектор', template: 'Шаблон', report: 'Отчёт', dataset: 'Набор данных', kb: 'БЗ', widget: 'Виджет' };
  var extList = [];
  var RS = { new: ['Новая', 'new'], quoted: ['Предложение', 'in_progress'], accepted: ['Принята', 'done'], declined: ['Отклонена', 'cancelled'], closed: ['Закрыта', ''] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function money(v) { return (v == null ? 0 : Number(v)).toLocaleString('ru-RU') + ' ₽'; }

  function load() {
    return Promise.all([
      rpc('app_market_listings_list', { p_token: token, p_process: null, p_q: null }),
      rpc('app_market_requests_list', { p_token: token, p_q: null }),
      rpc('app_market_kpi', { p_token: token })
    ]).then(function (r) {
      listings = r[0] || []; requests = r[1] || [];
      var k = (r[2] && r[2][0]) || {};
      $('#kpis').innerHTML = cell('Мои объявления', k.my_listings || 0) + cell('Активные', k.active_listings || 0) + cell('Мои заявки', k.my_requests || 0) + cell('Принято', k.accepted || 0);
      renderShop(); renderReq();
    }).catch(function (e) { msg('#lMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderShop() {
    var s = q.toLowerCase();
    var rows = listings.filter(function (l) { return !s || [(l.title || ''), (l.machine || ''), (l.region || ''), (l.seller || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#shop').innerHTML = rows.length ? rows.map(function (l) {
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + esc(PR[l.process] || l.process || '—') + '</span><b>' + esc(l.title) + '</b>' +
        (l.mine ? '<span class="badge done">моё</span>' : '<span class="note">' + esc(l.seller || '') + '</span>') +
        '<span class="note" style="margin-left:auto;">' + (l.capacity_hours || 0) + ' ч/мес · от ' + money(l.price_from) + ' · ' + (l.lead_days || '—') + ' дн</span></div>' +
        '<div class="note mt">' + esc(l.machine || '') + (l.region ? ' · ' + esc(l.region) : '') + ' · ' + esc(l.status === 'active' ? 'активно' : l.status) + '</div>' +
        '<div class="toolbar mt">' +
        (!l.mine ? '<button class="btn" data-req="' + l.id + '" style="width:auto;padding:7px 12px;">Отправить заявку</button>' : '') +
        (l.mine && l.status === 'active' ? '<button class="btn secondary" data-pause="' + l.id + '" style="width:auto;padding:7px 12px;">Пауза</button>' : '') +
        (l.mine && l.status !== 'active' ? '<button class="btn secondary" data-act="' + l.id + '" style="width:auto;padding:7px 12px;">Активировать</button>' : '') +
        '</div></div>';
    }).join('') : '<span class="note">Объявлений нет.</span>';
    $$('#shop [data-req]').forEach(function (b) { b.addEventListener('click', function () { sendRequest(b.dataset.req); }); });
    $$('#shop [data-pause]').forEach(function (b) { b.addEventListener('click', function () { setListing(b.dataset.pause, 'paused'); }); });
    $$('#shop [data-act]').forEach(function (b) { b.addEventListener('click', function () { setListing(b.dataset.act, 'active'); }); });
  }

  function renderReq() {
    $('#reqList').innerHTML = requests.length ? requests.map(function (r) {
      var st = RS[r.status] || [r.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(r.title) + '</b>' +
        (r.listing_title ? '<span class="note">' + esc(r.listing_title) + '</span>' : '') +
        (r.seller ? '<span class="note">исполнитель: ' + esc(r.seller) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + (r.qty || 0) + ' шт · бюджет ' + money(r.budget) + '</span></div>' +
        '<div class="toolbar mt">' +
        (r.mine ? '<button class="btn secondary" data-rst="quoted" data-id="' + r.id + '" style="width:auto;padding:7px 12px;">Предложение</button>' : '') +
        (r.mine ? '<button class="btn secondary" data-rst="accepted" data-id="' + r.id + '" style="width:auto;padding:7px 12px;">Принять</button>' : '') +
        (r.mine ? '<button class="btn secondary" data-rst="declined" data-id="' + r.id + '" style="width:auto;padding:7px 12px;">Отклонить</button>' : '') +
        (!r.mine ? '<button class="btn secondary" data-rst="closed" data-id="' + r.id + '" style="width:auto;padding:7px 12px;">Закрыть</button>' : '') +
        '</div></div>';
    }).join('') : '<span class="note">Заявок нет.</span>';
    $$('#reqList [data-rst]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_market_request_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.rst }).then(load).catch(function (e) { msg('#rMsg', e.message, 'err'); });
    }); });
  }

  /* ---------- W35: расширения ---------- */
  function loadExt() {
    return rpc('app_ext_list', { p_token: token }).then(function (list) { extList = list || []; renderExt(); })
      .catch(function (e) { msg('#eMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function extCard(e) {
    var kl = EK[e.kind] || e.kind;
    var adm = window.Auth && window.Auth.session && window.Auth.session() && window.Auth.session().role === 'admin';
    var btns = !e.installed
      ? '<button class="btn" data-ext-install="' + e.id + '" style="width:auto;padding:7px 12px;">Установить</button>'
      : '<button class="btn secondary" data-ext-toggle="' + e.id + '" data-on="' + (e.enabled ? '0' : '1') + '" style="width:auto;padding:7px 12px;">' + (e.enabled ? 'Выключить' : 'Включить') + '</button>' +
        '<button class="btn secondary" data-ext-del="' + e.id + '" style="width:auto;padding:7px 12px;">Удалить</button>';
    if (adm) btns += '<button class="act" data-ext-edit="' + e.id + '" title="Редактор">✎</button>';
    return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
      '<span class="badge">' + esc(kl) + '</span><b>' + esc(e.name) + '</b>' +
      (e.installed ? '<span class="badge done">' + (e.enabled ? 'включено' : 'установлено') + '</span>' : '') +
      (e.private ? '<span class="badge">приватное</span>' : '') +
      '<span class="note" style="margin-left:auto;">v' + esc(e.version) + (e.vendor ? ' · ' + esc(e.vendor) : '') + '</span></div>' +
      (e.description ? '<div class="note mt">' + esc(e.description) + '</div>' : '') +
      (e.deps && e.deps.length ? '<div class="note">Зависимости: ' + esc(e.deps.join(', ')) + '</div>' : '') +
      (e.permissions && e.permissions.length ? '<div class="note">Права: ' + esc(e.permissions.join(', ')) + '</div>' : '') +
      '<div class="toolbar mt">' + btns + '</div></div>';
  }
  function renderExt() {
    var only = $('#extOnlyInstalled') && $('#extOnlyInstalled').checked;
    var rows = extList.filter(function (e) { return !only || e.installed; });
    if ($('#eCnt')) $('#eCnt').textContent = '(' + rows.length + ')';
    $('#extList').innerHTML = rows.length ? rows.map(extCard).join('') : '<span class="note">Расширений нет.</span>';
    $$('#extList [data-ext-install]').forEach(function (b) { b.addEventListener('click', function () { extAct('app_ext_install', { p_token: token, p_id: b.dataset.extInstall }); }); });
    $$('#extList [data-ext-toggle]').forEach(function (b) { b.addEventListener('click', function () { extAct('app_ext_toggle', { p_token: token, p_id: b.dataset.extToggle, p_enabled: b.dataset.on === '1' }); }); });
    $$('#extList [data-ext-del]').forEach(function (b) { b.addEventListener('click', function () {
      ui.confirmDialog('Удалить расширение?', 'Удаление').then(function (ok) { if (ok) extAct('app_ext_uninstall', { p_token: token, p_id: b.dataset.extDel }); });
    }); });
    $$('#extList [data-ext-edit]').forEach(function (b) { b.addEventListener('click', function () {
      openExtEditor(extList.filter(function (x) { return x.id === b.dataset.extEdit; })[0]);
    }); });
  }

  /* ---------- W40: редактор манифеста (админ платформы) ---------- */
  var editingExt = null, tenantId = null;
  function openExtEditor(e) {
    var s = window.Auth && window.Auth.session && window.Auth.session();
    if (!s || s.role !== 'admin') return;
    editingExt = e ? e.id : null;
    $('#eeTitle').textContent = e ? ('Редактор: ' + e.name) : 'Новый манифест';
    $('#extEditorCard').style.display = '';
    var set = function (x) {
      $('#eeCode').value = x.code || ''; $('#eeName').value = x.name || ''; $('#eeKind').value = x.kind || 'connector';
      $('#eeVersion').value = x.version || '1.0.0'; $('#eeVendor').value = x.vendor || ''; $('#eeDesc').value = x.description || '';
      $('#eeDeps').value = (x.deps || []).join(', '); $('#eePerm').value = (x.permissions || []).join(', ');
      $('#eeActive').checked = x.active !== false; $('#eePrivate').checked = !!x.private;
    };
    if (e) { set(e); rpc('app_ext_detail', { p_token: token, p_id: e.id }).then(function (d) { if (d && d[0]) set(d[0]); }).catch(function () {}); }
    else { set({}); }
    msg('#eeMsg', '', 'info');
  }
  function saveExt() {
    var deps = ($('#eeDeps').value || '').split(',').map(function (x) { return x.trim(); }).filter(Boolean);
    var perm = ($('#eePerm').value || '').split(',').map(function (x) { return x.trim(); }).filter(Boolean);
    rpc('app_ext_save', {
      p_token: token, p_id: editingExt, p_code: $('#eeCode').value.trim(), p_name: $('#eeName').value.trim(),
      p_kind: $('#eeKind').value, p_version: $('#eeVersion').value.trim(), p_vendor: $('#eeVendor').value.trim(),
      p_description: $('#eeDesc').value.trim(), p_deps: deps, p_permissions: perm, p_active: $('#eeActive').checked,
      p_tenant_id: $('#eePrivate').checked ? tenantId : null
    }).then(function (r) {
      var x = r && r[0]; if (x && x.ok === false) { msg('#eeMsg', x.message, 'err'); return; }
      msg('#eeMsg', (x && x.message) || 'Сохранено', 'ok'); $('#extEditorCard').style.display = 'none'; loadExt();
    }).catch(function (e) { msg('#eeMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  var extNew = $('#extNew'); if (extNew) extNew.addEventListener('click', function () { openExtEditor(null); });
  var eeSave = $('#eeSave'); if (eeSave) eeSave.addEventListener('click', saveExt);
  var eeCancel = $('#eeCancel'); if (eeCancel) eeCancel.addEventListener('click', function () { $('#extEditorCard').style.display = 'none'; });
  function extAct(fn, args) {
    rpc(fn, args).then(function (r) {
      var x = r && r[0];
      if (x && x.ok === false) { msg('#eMsg', x.message, 'err'); return; }
      window.Auth.log('Расширение', x ? x.message : '');
      msg('#eMsg', x ? x.message : 'Готово', 'ok'); loadExt();
    }).catch(function (e) { msg('#eMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  var exOnly = $('#extOnlyInstalled'); if (exOnly) exOnly.addEventListener('change', renderExt);

  function setListing(id, st) {
    rpc('app_market_listing_set_status', { p_token: token, p_id: id, p_status: st }).then(load).catch(function (e) { msg('#lMsg', e.message, 'err'); });
  }
  function sendRequest(listingId) {
    var l = listings.filter(function (x) { return x.id === listingId; })[0];
    var title = prompt('Предмет заявки:', l ? l.title : '');
    if (!title) return;
    var qty = parseFloat(prompt('Количество, шт:', '1')) || 1;
    rpc('app_market_request_save', { p_token: token, p_id: null, p_listing_id: listingId, p_title: title, p_qty: qty, p_due_date: null, p_budget: null, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#lMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); load(); })
      .catch(function (e) { msg('#lMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function loadDict() {
    return rpc('app_dict_items_by_code', { p_token: token, p_code: 'marketplace_process' }).then(function (r) {
      if (!r || !r.length) return;
      var map = {}; r.forEach(function (x) { map[x.value] = x.label; }); PR = map;
      $('#lProcess').innerHTML = r.map(function (x) { return '<option value="' + esc(x.value) + '">' + esc(x.label) + '</option>'; }).join('');
      renderShop();
    }).catch(function () {});
  }

  var TABS = { shop: 'tabShop', req: 'tabReq', ext: 'tabExt' };
  $$('.tab').forEach(function (b) { b.addEventListener('click', function () {
    $$('.tab').forEach(function (x) { x.classList.remove('active'); }); b.classList.add('active');
    Object.keys(TABS).forEach(function (k) { var el = $('#' + TABS[k]); if (el) el.style.display = (k === b.dataset.tab) ? 'block' : 'none'; });
  }); });
  $('#q').addEventListener('input', function () { q = this.value; renderShop(); });
  $('#lSave').addEventListener('click', function () {
    rpc('app_market_listing_save', { p_token: token, p_id: null, p_title: $('#lTitle').value, p_process: $('#lProcess').value,
      p_machine: $('#lMachine').value, p_capacity_hours: parseFloat($('#lCap').value) || 0, p_price_from: parseFloat($('#lPrice').value) || 0,
      p_region: $('#lRegion').value, p_lead_days: parseInt($('#lLead').value, 10) || null, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#lMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) { $('#lTitle').value = ''; window.Auth.log('Мощность размещена', $('#lTitle').value); load(); } })
      .catch(function (e) { msg('#lMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#lMsg', 'Supabase не подключён.', 'err'); return; }
    if (s.role === 'admin') {
      var nb = $('#extNew'); if (nb) nb.style.display = '';
      rpc('app_my_tenant_id', { p_token: token }).then(function (t) { tenantId = t; }).catch(function () {});
    }
    load().then(loadDict); loadExt();
  });
})();
