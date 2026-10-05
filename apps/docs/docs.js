/* ============================================================
   3DMP Service · apps/docs — документооборот
   Данные: app_doc_* (0017_docs.sql). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, docs = [], orders = [], cur = null, filter = '';

  var T = { kp: 'КП', contract: 'Договор', techcard: 'Техкарта', act: 'Акт', other: 'Другое' };
  var ST = { draft: 'Черновик', active: 'В работе', archived: 'Архив' };
  function esc(v) { return ui.esc(v); }
  function money(v) { return v == null ? '' : (Number(v) || 0).toLocaleString('ru-RU') + ' ₽'; }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return Promise.all([
      rpc('app_doc_list', { p_token: token, p_type: filter || null }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      docs = r[0] || []; orders = r[1] || [];
      $('#fOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      render();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function render() {
    if (!docs.length) { $('#list').innerHTML = '<span class="note">Документов нет.</span>'; return; }
    $('#list').innerHTML = docs.map(function (d) {
      return '<div class="dcard" data-id="' + d.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;"><span class="b ' + d.status + '">' + (ST[d.status] || d.status) + '</span>' +
        '<span class="note">' + (T[d.doc_type] || d.doc_type) + '</span>' +
        '<span class="note" style="margin-left:auto;">' + esc(d.number) + ' · v' + d.version + '</span></div>' +
        '<h3 style="font-size:.94rem;margin:8px 0 4px;">' + esc(d.title) + '</h3>' +
        '<div style="font-size:.78rem;color:var(--muted);">' + (d.counterparty ? esc(d.counterparty) + ' · ' : '') +
        (d.amount ? money(d.amount) + ' · ' : '') + (d.order_number ? '📥 ' + esc(d.order_number) + ' · ' : '') + fmt(d.updated_at) + '</div></div>';
    }).join('');
    $$('#list .dcard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function openItem(id) {
    rpc('app_doc_get', { p_token: token, p_id: id }).then(function (r) {
      var d = r && r[0]; if (!d) { ui.toast('Документ не найден'); return; }
      cur = d;
      $('#doc').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;"><span class="b ' + d.status + '">' + (ST[d.status] || d.status) + '</span>' +
        '<span class="note">' + (T[d.doc_type] || d.doc_type) + '</span>' +
        '<b style="margin-left:auto;">' + esc(d.number) + ' · v' + d.version + '</b></div>' +
        '<h1 style="font-size:1.1rem;margin:10px 0;">' + esc(d.title) + '</h1>' +
        kv('Контрагент', d.counterparty) + kv('Сумма', money(d.amount)) + kv('Автор', d.created_login) + kv('Создан', fmt(d.created_at)) +
        (d.content ? '<div style="margin-top:10px;white-space:pre-wrap;font-size:.85rem;">' + esc(d.content) + '</div>' : '');
      $('#uTitle').value = d.title || ''; $('#uCounter').value = d.counterparty || '';
      $('#uAmount').value = d.amount != null ? d.amount : ''; $('#uContent').value = d.content || '';
      clearMsg('#uMsg');
      loadVersions(id);
      screens.go('s-item');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function loadVersions(id) {
    rpc('app_doc_versions', { p_token: token, p_id: id }).then(function (list) {
      $('#versions').innerHTML = (list || []).map(function (v) {
        return '<div class="kvr"><span class="k">v' + v.version + '</span><b>' + esc(v.title || '') + '</b>' +
          '<span class="note" style="margin-left:auto;">' + fmt(v.created_at) + ' · ' + esc(v.by_login || '') + '</span></div>';
      }).join('') || '<span class="note">—</span>';
    });
  }

  $('#toNew').addEventListener('click', function () { clearMsg('#nMsg'); screens.go('s-new'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; load();
  });

  $('#createBtn').addEventListener('click', function () {
    var title = $('#fTitle').value.trim(); if (!title) { msg('#nMsg', 'Укажите название.', 'err'); return; }
    var amt = parseFloat($('#fAmount').value.replace(',', '.'));
    rpc('app_doc_create', { p_token: token, p_doc_type: $('#fType').value, p_title: title, p_order_id: $('#fOrder').value || null,
      p_counterparty: $('#fCounter').value.trim(), p_amount: isNaN(amt) ? null : amt, p_content: $('#fContent').value })
      .then(function (d) { var row = d && d[0]; if (!row) { msg('#nMsg', 'Ошибка', 'err'); return; }
        window.Auth.log('Документ', row.number); ui.toast('Документ ' + row.number + ' создан');
        ['#fTitle', '#fCounter', '#fAmount', '#fContent'].forEach(function (s) { $(s).value = ''; });
        load().then(function () { openItem(row.id); }); })
      .catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#saveBtn').addEventListener('click', function () {
    if (!cur) return;
    var amt = parseFloat($('#uAmount').value.replace(',', '.'));
    rpc('app_doc_update', { p_token: token, p_id: cur.id, p_title: $('#uTitle').value.trim(), p_counterparty: $('#uCounter').value.trim(), p_amount: isNaN(amt) ? null : amt, p_content: $('#uContent').value })
      .then(function (d) { var r = d && d[0]; msg('#uMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err');
        window.Auth.log('Правка документа', cur.number); load().then(function () { openItem(cur.id); }); })
      .catch(function (e) { msg('#uMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#activeBtn').addEventListener('click', function () { setStatus('active'); });
  $('#archBtn').addEventListener('click', function () { setStatus('archived'); });
  function setStatus(st) {
    if (!cur) return;
    rpc('app_doc_set_status', { p_token: token, p_id: cur.id, p_status: st })
      .then(function () { window.Auth.log('Статус документа', cur.number + ' → ' + st); load().then(function () { openItem(cur.id); }); });
  }

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
