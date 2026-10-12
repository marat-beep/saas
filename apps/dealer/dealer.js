/* ============================================================
   3DMP Service · apps/dealer — Портал дилера (X17)
   Заявки дилера: подача и статус. Данные: 0196.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, data = [], q = '';

  var PST = { new: 'Новая', accepted: 'Принята', rejected: 'Отклонена', closed: 'Закрыта' };
  var PR = { high: 'Высокий', normal: 'Обычный', low: 'Низкий' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#msg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function fmt(d) { if (!d) return ''; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }

  function load() {
    return Promise.all([
      rpc('app_dealer_context', { p_token: token }).catch(function () { return []; }),
      rpc('app_dealer_requests_list', { p_token: token, p_all: false }).catch(function () { return []; })
    ]).then(function (r) {
      var ctx = (r[0] && r[0][0]) || null, list = r[1] || [];
      $('#ctx').textContent = ctx ? 'Организация: ' + ctx.customer + (ctx.tenant_name ? ' · ' + ctx.tenant_name : '') : 'Нет привязки дилера — обратитесь к администратору.';
      $('#kpis').innerHTML = cell('Всего', list.length) + cell('Новые', list.filter(function (x) { return x.status === 'new'; }).length) +
        cell('Принятые', list.filter(function (x) { return x.status === 'accepted'; }).length) + cell('Закрытые', list.filter(function (x) { return x.status === 'closed'; }).length);
      data = list; renderList();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }

  function renderList() {
    var list = q ? data.filter(function (x) { var s = ((x.title || '') + ' ' + (x.service_number || '') + ' ' + (PST[x.status] || '') + ' ' + (PR[x.priority] || '')).toLowerCase(); return s.indexOf(q) >= 0; }) : data;
    $('#list').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Тема</th><th>Приоритет</th><th>Статус</th><th>Сервисная заявка</th><th>Дата</th></tr></thead><tbody>' +
      list.map(function (x) { return '<tr><td><b>' + esc(x.title) + '</b></td><td>' + esc(PR[x.priority] || x.priority) + '</td><td>' + esc(PST[x.status] || x.status) + '</td><td>' + esc(x.service_number || '—') + '</td><td class="muted">' + fmt(x.created_at) + '</td></tr>'; }).join('') + '</tbody></table></div>'
      : '<span class="note">' + (q ? 'Ничего не найдено.' : 'Заявок нет.') + '</span>';
  }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  $('#addBtn').addEventListener('click', function () {
    var title = $('#fTitle').value.trim();
    if (!title) { msg('Укажите тему.', 'err'); return; }
    rpc('app_dealer_request_save', { p_token: token, p_id: null, p_customer_id: null, p_title: title, p_description: $('#fDesc').value || null, p_priority: $('#fPriority').value })
      .then(function (r) { var x = r && r[0]; if (!x || !x.ok) { msg((x && x.message) || 'Ошибка', 'err'); return; }
        window.Auth.log('Заявка дилера', title); ui.toast(x.message); $('#fTitle').value = ''; $('#fDesc').value = ''; load(); })
      .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  var _q = document.getElementById('q'); if (_q) _q.addEventListener('input', function () { q = this.value.trim().toLowerCase(); renderList(); });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (s.role !== 'dealer' && s.role !== 'admin') { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    load();
  });
})();
