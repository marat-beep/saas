/* ============================================================
   3DMP Service · apps/engraving — реестр гравирования (B36)
   Данные: 0064. Стандарт модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], orders = [], cur = null, q = '';

  var ST = { new: ['Новый', 'new'], in_progress: ['В работе', 'in_progress'], done: ['Выполнен', 'done'], cancelled: ['Отменён', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function d(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }

  function load() {
    return Promise.all([
      rpc('app_engraving_list', { p_token: token, p_q: null }),
      rpc('app_engraving_kpi', { p_token: token }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      list = r[0] || []; orders = r[2] || [];
      $('#fOrder').innerHTML = '<option value="">— не выбрана —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('В очереди', k.queue || 0) + cell('Выполнено', k.done || 0) + cell('Минут', k.minutes_sum || 0);
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (g) { return !s || [(g.number || ''), (g.detail || ''), (g.engraving_number || ''), (g.order_number || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (g) {
      var st = ST[g.status] || [g.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge">' + esc(g.number) + '</span><span class="badge ' + st[1] + '">' + esc(st[0]) + '</span>' +
        '<b>' + esc(g.detail || '—') + '</b>' + (g.order_number ? '<span class="note">заявка ' + esc(g.order_number) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">отгрузка ' + d(g.ship_date) + ' · ' + (g.minutes || 0) + ' мин</span></div>' +
        '<div class="note mt">Станок: ' + esc(g.machine || '—') + ' · гравировка: ' + esc(g.engraving_number || '—') + '</div>' +
        '<div class="toolbar mt">' +
        '<button class="btn secondary" data-edit="' + g.id + '" style="width:auto;padding:7px 12px;">Редактировать</button>' +
        (g.status !== 'in_progress' && g.status !== 'done' ? '<button class="btn" data-st="in_progress" data-id="' + g.id + '" style="width:auto;padding:7px 12px;">В работу</button>' : '') +
        (g.status !== 'done' ? '<button class="btn" data-st="done" data-id="' + g.id + '" style="width:auto;padding:7px 12px;">Выполнено</button>' : '') +
        '</div></div>';
    }).join('') : '<span class="note">Заказов нет.</span>';
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { edit(b.dataset.edit); }); });
    $$('#list [data-st]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_engraving_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.st }).then(function () { load(); }).catch(function (e) { msg('#mMsg', e.message, 'err'); });
    }); });
  }

  function edit(id) {
    cur = list.filter(function (g) { return g.id === id; })[0]; if (!cur) return;
    $('#fOrder').value = cur.order_id || ''; $('#fDetail').value = cur.detail || ''; $('#fMachine').value = cur.machine || '';
    $('#fGnum').value = cur.engraving_number || ''; $('#fMinutes').value = cur.minutes || ''; $('#fShip').value = cur.ship_date || '';
    $('#fNote').value = ''; window.scrollTo(0, 0);
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fClear').addEventListener('click', function () { cur = null; ['fDetail', 'fMachine', 'fGnum', 'fNote'].forEach(function (i) { $('#' + i).value = ''; }); msg('#fMsg', ''); });
  $('#fSave').addEventListener('click', function () {
    rpc('app_engraving_save', { p_token: token, p_id: cur ? cur.id : null, p_order_id: $('#fOrder').value || null,
      p_detail: $('#fDetail').value, p_machine: $('#fMachine').value, p_engraving_number: $('#fGnum').value,
      p_minutes: parseFloat($('#fMinutes').value) || null, p_ship_date: $('#fShip').value || null, p_note: $('#fNote').value })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('Гравирование', x.number); cur = null; load(); })
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
