/* ============================================================
   3DMP Service · apps/suppliers — реестр поставщиков
   Данные: 0064. Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], cur = null, q = '', cat = '';

  var ST = { pending: ['На аккредитации', 'normal'], accredited: ['Аккредитован', 'done'], blocked: ['Заблокирован', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_suppliers_list', { p_token: token, p_category: cat || null, p_q: null }),
      rpc('app_suppliers_kpi', { p_token: token })
    ]).then(function (r) {
      list = r[0] || [];
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('Аккредитовано', k.accredited || 0) + cell('На аккредитации', k.pending || 0) + cell('Заблокировано', k.blocked || 0);
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (x) { return !s || [(x.name || ''), (x.inn || ''), (x.contact || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (x) {
      var st = ST[x.status] || [x.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(x.name) + '</b>' +
        '<span class="badge">' + esc(x.category || '—') + '</span>' +
        '<span class="note" style="margin-left:auto;">рейтинг ' + (x.rating || 0) + '</span></div>' +
        '<div class="note mt">ИНН ' + esc(x.inn || '—') + ' · ' + esc(x.contact || '') + ' ' + esc(x.phone || '') + ' ' + esc(x.email || '') + '</div>' +
        '<div class="toolbar mt"><button class="btn secondary" data-edit="' + x.id + '" style="width:auto;padding:7px 12px;">Редактировать</button>' +
        (x.status !== 'accredited' ? '<button class="btn" data-st="accredited" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">Аккредитовать</button>' : '') +
        (x.status !== 'blocked' ? '<button class="btn secondary" data-st="blocked" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">Блокировать</button>' : '') +
        '</div></div>';
    }).join('') : '<span class="note">Поставщиков нет.</span>';
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { edit(b.dataset.edit); }); });
    $$('#list [data-st]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_suppliers_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.st }).then(function () { load(); }).catch(function (e) { msg('#mMsg', e.message, 'err'); });
    }); });
  }

  function edit(id) {
    cur = list.filter(function (x) { return x.id === id; })[0]; if (!cur) return;
    $('#fName').value = cur.name || ''; $('#fInn').value = cur.inn || ''; $('#fContact').value = cur.contact || '';
    $('#fPhone').value = cur.phone || ''; $('#fEmail').value = cur.email || ''; $('#fCat').value = cur.category || 'металл'; $('#fRating').value = cur.rating || 0;
    window.scrollTo(0, 0);
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fCatFilter').addEventListener('change', function () { cat = this.value; load(); });
  $('#fClear').addEventListener('click', function () { cur = null; ['fName', 'fInn', 'fContact', 'fPhone', 'fEmail'].forEach(function (i) { $('#' + i).value = ''; }); msg('#fMsg', ''); });
  $('#fSave').addEventListener('click', function () {
    var name = $('#fName').value.trim(); if (!name) { msg('#fMsg', 'Укажите наименование.', 'err'); return; }
    rpc('app_suppliers_save', { p_token: token, p_id: cur ? cur.id : null, p_name: name, p_inn: $('#fInn').value,
      p_contact: $('#fContact').value, p_phone: $('#fPhone').value, p_email: $('#fEmail').value, p_category: $('#fCat').value,
      p_rating: parseFloat($('#fRating').value) || 0, p_note: null })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('Поставщик', name); cur = null; load(); })
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
