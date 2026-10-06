/* ============================================================
   3DMP Service · apps/reverse — A6 реверс-инжиниринг. Данные: 0086.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], cur = null, q = '';

  var M = { scan: '3D-скан', measure: 'Обмер', drawing: 'По чертежу', photo: 'По фото', sample: 'По образцу' };
  var R = { model: '3D-модель', drawing: 'Чертёж', both: 'Модель + чертёж' };
  var ST = { new: ['Новая', 'normal'], scanning: ['Сканирование', 'in_progress'], modelling: ['Моделирование', 'in_progress'], review: ['Проверка', 'new'], done: ['Готово', 'done'], cancelled: ['Отменена', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_reverse_list', { p_token: token, p_q: null }),
      rpc('app_reverse_kpi', { p_token: token })
    ]).then(function (r) {
      list = r[0] || [];
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('Новые', k.new_cnt || 0) + cell('В работе', k.in_progress || 0) + cell('Готово', k.done || 0) + cell('По чертежу', k.by_drawing || 0);
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (x) { return !s || [(x.title || ''), (x.customer || ''), (x.part || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (x) {
      var st = ST[x.status] || [x.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + esc(x.number) + '</span><span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(x.title) + '</b>' +
        '<span class="note" style="margin-left:auto;">' + esc(M[x.method] || x.method) + ' → ' + esc(R[x.result_type] || x.result_type) + '</span></div>' +
        '<div class="note mt">' + esc(x.customer || '') + (x.part ? ' · ' + esc(x.part) : '') + (x.assignee ? ' · исполнитель: ' + esc(x.assignee) : '') + '</div>' +
        '<div class="toolbar mt"><button class="btn secondary" data-edit="' + x.id + '" style="width:auto;padding:7px 12px;">Править</button>' +
        (x.status === 'new' ? '<button class="btn" data-st="scanning" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">Сканирование</button>' : '') +
        (x.status === 'scanning' ? '<button class="btn" data-st="modelling" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">Моделирование</button>' : '') +
        (x.status === 'modelling' ? '<button class="btn" data-st="review" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">На проверку</button>' : '') +
        (x.status !== 'done' ? '<button class="btn" data-st="done" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">Готово</button>' : '') +
        '</div></div>';
    }).join('') : '<span class="note">Заявок нет.</span>';
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { edit(b.dataset.edit); }); });
    $$('#list [data-st]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_reverse_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.st }).then(load).catch(function (e) { msg('#mMsg', e.message, 'err'); }); }); });
  }

  function edit(id) {
    cur = list.filter(function (x) { return x.id === id; })[0]; if (!cur) return;
    $('#fTitle').value = cur.title || ''; $('#fCustomer').value = cur.customer || ''; $('#fPart').value = cur.part || '';
    $('#fMethod').value = cur.method || 'scan'; $('#fResult').value = cur.result_type || 'model'; $('#fAssignee').value = cur.assignee || '';
    window.scrollTo(0, 0);
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fClear').addEventListener('click', function () { cur = null; ['fTitle', 'fCustomer', 'fPart', 'fAssignee'].forEach(function (i) { $('#' + i).value = ''; }); msg('#fMsg', ''); });
  $('#fSave').addEventListener('click', function () {
    rpc('app_reverse_save', { p_token: token, p_id: cur ? cur.id : null, p_title: $('#fTitle').value, p_customer: $('#fCustomer').value,
      p_part: $('#fPart').value, p_method: $('#fMethod').value, p_result_type: $('#fResult').value, p_assignee: $('#fAssignee').value, p_order_id: null, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? (x.message + ' ' + x.number) : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('Реверс-инжиниринг', x.number); cur = null; load(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
