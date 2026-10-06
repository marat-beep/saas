/* ============================================================
   3DMP Service · apps/lean — B7 бережливое производство. Данные: 0078.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], cur = null, q = '';

  var CAT = { overproduction: 'Перепроизводство', waiting: 'Ожидание', transport: 'Транспортировка', overprocessing: 'Излишняя обработка', inventory: 'Запасы', motion: 'Движения', defects: 'Дефекты', other: 'Прочее' };
  var ST = { idea: ['Идея', 'normal'], approved: ['Одобрено', 'new'], in_progress: ['В работе', 'in_progress'], done: ['Внедрено', 'done'], rejected: ['Отклонено', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function money(v) { return (v == null ? 0 : Number(v)).toLocaleString('ru-RU') + ' ₽'; }

  function load() {
    return Promise.all([
      rpc('app_lean_list', { p_token: token, p_q: null }),
      rpc('app_lean_kpi', { p_token: token })
    ]).then(function (r) {
      list = r[0] || [];
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('Идей', k.ideas || 0) + cell('В работе', k.active || 0) + cell('Внедрено', k.done || 0) + cell('Экономия', money(k.savings_sum)) + cell('Топ потерь', CAT[k.top_category] || k.top_category || '—');
      render();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (x) { return !s || [(x.title || ''), (x.author || ''), (x.description || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (x) {
      var st = ST[x.status] || [x.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(x.title) + '</b>' +
        '<span class="badge">' + esc(CAT[x.category] || x.category) + '</span>' +
        '<span class="note" style="margin-left:auto;">' + money(x.savings) + '/год</span></div>' +
        (x.description ? '<div class="note mt">' + esc(x.description) + '</div>' : '') +
        '<div class="toolbar mt">' +
        '<button class="btn secondary" data-edit="' + x.id + '" style="width:auto;padding:7px 12px;">Править</button>' +
        (x.status === 'idea' ? '<button class="btn" data-st="approved" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">Одобрить</button>' : '') +
        (x.status === 'approved' ? '<button class="btn" data-st="in_progress" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">В работу</button>' : '') +
        (x.status !== 'done' && x.status !== 'rejected' ? '<button class="btn" data-st="done" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">Внедрено</button>' : '') +
        (x.status !== 'rejected' && x.status !== 'done' ? '<button class="btn secondary" data-st="rejected" data-id="' + x.id + '" style="width:auto;padding:7px 12px;">Отклонить</button>' : '') +
        '<button class="btn secondary" data-del="' + x.id + '" style="width:auto;padding:7px 12px;">Удалить</button></div></div>';
    }).join('') : '<span class="note">Предложений нет.</span>';
    $$('#list [data-edit]').forEach(function (b) { b.addEventListener('click', function () { edit(b.dataset.edit); }); });
    $$('#list [data-st]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_lean_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.st }).then(load).catch(function (e) { msg('#mMsg', e.message, 'err'); }); }); });
    $$('#list [data-del]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_lean_delete', { p_token: token, p_id: b.dataset.del }).then(load); }); });
  }

  function edit(id) {
    cur = list.filter(function (x) { return x.id === id; })[0]; if (!cur) return;
    $('#fTitle').value = cur.title || ''; $('#fCat').value = cur.category || 'other'; $('#fAuthor').value = cur.author || '';
    $('#fSavings').value = cur.savings || 0; $('#fEffect').value = cur.effect || ''; $('#fDescr').value = cur.description || '';
    window.scrollTo(0, 0);
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fClear').addEventListener('click', function () { cur = null; ['fTitle', 'fAuthor', 'fEffect', 'fDescr'].forEach(function (i) { $('#' + i).value = ''; }); msg('#fMsg', ''); });
  $('#fSave').addEventListener('click', function () {
    rpc('app_lean_save', { p_token: token, p_id: cur ? cur.id : null, p_title: $('#fTitle').value, p_category: $('#fCat').value,
      p_description: $('#fDescr').value, p_author: $('#fAuthor').value, p_savings: parseFloat($('#fSavings').value) || 0, p_effect: $('#fEffect').value })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); if (x) window.Auth.log('Кайдзен', $('#fTitle').value); cur = null; load(); })
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
