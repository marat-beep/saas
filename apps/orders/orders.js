/* ============================================================
   3DMP Service · apps/orders — единый приём заявок
   Список/создание/детали/статусы. Данные: app_order_* (0006_orders.sql).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, orders = [], filter = 'all', cur = null;

  var ST = { new: 'Новая', in_progress: 'В работе', done: 'Выполнена', cancelled: 'Отменена' };
  var PR = { high: 'Высокий', normal: 'Обычный', low: 'Низкий' };
  function stBadge(s) { return '<span class="b ' + s + '">' + (ST[s] || s) + '</span>'; }
  function prBadge(p) { return '<span class="b ' + p + '">' + (PR[p] || p) + '</span>'; }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }

  var screens = AppRouter.create({
    onShow: function (s) { window.scrollTo(0, 0); },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return rpc('app_order_list', { p_token: token }).then(function (d) { orders = d || []; render(); })
      .catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function filtered() { return orders.filter(function (o) { return filter === 'all' || o.status === filter; }); }
  function render() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Заявок нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (o) {
      return '<div class="ocard" data-id="' + o.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;">' + stBadge(o.status) + prBadge(o.priority) +
        '<span class="note" style="margin-left:auto;">' + esc(o.number) + '</span></div>' +
        '<h3 style="font-size:.95rem;margin:8px 0 4px;">' + esc(o.title) + '</h3>' +
        '<div style="font-size:.76rem;color:var(--muted);">' +
        (o.source ? '📎 ' + esc(o.source) + ' · ' : '') + (o.customer ? esc(o.customer) + ' · ' : '') + fmt(o.created_at) + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openDetail(c.dataset.id); }); });
  }

  function openDetail(id) {
    cur = null;
    rpc('app_order_get', { p_token: token, p_id: id }).then(function (rows) {
      var o = rows && rows[0]; if (!o) { ui.toast('Заявка не найдена'); return; }
      cur = o;
      $('#detail').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;">' + stBadge(o.status) + prBadge(o.priority) +
        '<b style="margin-left:auto;">' + esc(o.number) + '</b></div>' +
        '<h1 style="font-size:1.2rem;margin:10px 0;">' + esc(o.title) + '</h1>' +
        (o.description ? '<p style="color:var(--muted);line-height:1.6;margin-bottom:10px;">' + esc(o.description) + '</p>' : '') +
        kv('Источник', o.source) + kv('Заказчик', o.customer) + kv('Контакт', o.contact) +
        kv('Автор', o.created_login) + kv('Создана', fmt(o.created_at)) + kv('Обновлена', fmt(o.updated_at));
      $('#stStatus').value = o.status;
      return rpc('app_order_history_list', { p_token: token, p_id: id });
    }).then(function (h) {
      $('#history').innerHTML = (h || []).map(function (x) {
        return '<div class="kvr"><span class="k">' + fmt(x.created_at) + '</span><b>' + (ST[x.status] || x.status) + '</b>' +
          '<span class="note" style="margin-left:auto;">' + esc(x.by_login || '') + (x.comment ? ' · ' + esc(x.comment) : '') + '</span></div>';
      }).join('') || '<span class="note">—</span>';
      clearMsg('#stMsg');
      screens.go('s-detail');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }

  $('#toCreate').addEventListener('click', function () { clearMsg('#cMsg'); screens.go('s-create'); });
  $('#backToList1').addEventListener('click', function () { screens.go('s-list'); });
  $('#backToList2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  $('#createBtn').addEventListener('click', function () {
    var title = $('#fTitle').value.trim();
    if (!title) { msg('#cMsg', 'Укажите тему заявки.', 'err'); return; }
    rpc('app_order_create', {
      p_token: token, p_title: title, p_description: $('#fDesc').value.trim(),
      p_source: $('#fSource').value.trim(), p_customer: $('#fCustomer').value.trim(),
      p_contact: $('#fContact').value.trim(), p_priority: $('#fPriority').value
    }).then(function (d) {
      var row = d && d[0];
      window.Auth.log('Создана заявка', (row && row.number) || title);
      if (window.AppNotify) window.AppNotify.refresh(true);
      ui.toast('Заявка ' + ((row && row.number) || '') + ' создана');
      ['#fTitle', '#fDesc', '#fSource', '#fCustomer', '#fContact'].forEach(function (s) { $(s).value = ''; });
      load().then(function () { screens.go('s-list'); });
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#stBtn').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_order_set_status', { p_token: token, p_id: cur.id, p_status: $('#stStatus').value, p_comment: $('#stComment').value.trim() })
      .then(function (d) {
        var row = d && d[0];
        if (!row || !row.ok) { msg('#stMsg', (row && row.message) || 'Не удалось', 'err'); return; }
        window.Auth.log('Статус заявки', cur.number + ' → ' + $('#stStatus').value);
        msg('#stMsg', 'Статус обновлён.', 'ok');
        $('#stComment').value = '';
        openDetail(cur.id);
      }).catch(function (e) { msg('#stMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; render();
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
