/* ============================================================
   3DMP Service · apps/bugbox — дашборд багов (Bug Mode). Данные: 0099.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, list = [], q = '', status = '';

  var ST = { new: ['Новый', 'high'], in_work: ['В работе', 'in_progress'], fixed: ['Исправлен', 'done'], rejected: ['Отклонён', 'cancelled'] };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#mMsg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_bug_list', { p_token: token, p_status: status || null, p_module: null }),
      rpc('app_bug_kpi', { p_token: token })
    ]).then(function (r) {
      list = r[0] || [];
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Всего', k.total || 0) + cell('Новые', k.new_cnt || 0) + cell('В работе', k.in_work || 0) + cell('Исправлено', k.fixed || 0) + cell('Отклонено', k.rejected || 0);
      render();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }

  function ctxOf(p) { try { var c = p || {}; return [c.route && ('маршрут ' + c.route), c.browser, c.element && c.element.selector && ('селектор ' + c.element.selector)].filter(Boolean).join(' · '); } catch (e) { return ''; } }

  function render() {
    var s = q.toLowerCase();
    var rows = list.filter(function (b) { return !s || [(b.text || ''), (b.module || ''), (b.author || '')].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#cnt').textContent = '(' + rows.length + ')';
    $('#list').innerHTML = rows.length ? rows.map(function (b) {
      var st = ST[b.status] || [b.status, ''];
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + st[1] + '">' + esc(st[0]) + '</span><b>' + esc(b.text || 'без описания') + '</b>' +
        '<span class="badge">' + esc(b.module || '') + '</span>' +
        '<span class="note" style="margin-left:auto;">' + new Date(b.created_at).toLocaleString('ru-RU') + '</span></div>' +
        '<div class="note mt">' + esc(b.author || '') + ' · ' + esc(b.type || '') + ' · ' + esc(b.url || '') + '</div>' +
        (ctxOf(b.payload) ? '<div class="note">' + esc(ctxOf(b.payload)) + '</div>' : '') +
        '<div class="toolbar mt">' +
        (b.status !== 'in_work' ? '<button class="btn secondary" data-st="in_work" data-id="' + b.id + '" style="width:auto;padding:7px 12px;">В работу</button>' : '') +
        (b.status !== 'fixed' ? '<button class="btn" data-st="fixed" data-id="' + b.id + '" style="width:auto;padding:7px 12px;">Исправлен</button>' : '') +
        (b.status !== 'rejected' ? '<button class="btn secondary" data-st="rejected" data-id="' + b.id + '" style="width:auto;padding:7px 12px;">Отклонить</button>' : '') +
        '<button class="btn secondary" data-tk="' + b.id + '" style="width:auto;padding:7px 12px;">В поддержку</button>' +
        '</div></div>';
    }).join('') : '<span class="note">Баг-репортов нет.</span>';
    $$('#list [data-st]').forEach(function (bt) { bt.addEventListener('click', function () {
      rpc('app_bug_set_status', { p_token: token, p_id: bt.dataset.id, p_status: bt.dataset.st }).then(load).catch(function (e) { msg(e.message, 'err'); });
    }); });
    $$('#list [data-tk]').forEach(function (bt) { bt.addEventListener('click', function () {
      bt.disabled = true;
      rpc('app_support_from_remark', { p_token: token, p_remark_id: bt.dataset.tk })
        .then(function (r) { var x = r && r[0]; ui.toast(x ? (x.message + (x.number ? ': ' + x.number : '')) : 'Готово', x ? 'ok' : 'err'); msg(x ? (x.message + (x.number ? ': ' + x.number : '')) : '', 'ok'); })
        .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); })
        .finally(function () { bt.disabled = false; });
    }); });
  }

  $('#q').addEventListener('input', function () { q = this.value; render(); });
  $('#fStatus').addEventListener('change', function () { status = this.value; load(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!['admin', 'owner', 'manager'].includes(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    load();
  });
})();
