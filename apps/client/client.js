/* ============================================================
   3DMP Service · apps/client — Кабинет заказчика (роль client)
   Read-проекции: заявки, документы, счета, ТКП. Данные: 0058.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, ctx = null, tab = 'ord', cache = {};

  var OST = { new: 'Новая', in_progress: 'В работе', done: 'Выполнена', cancelled: 'Отменена' };
  var DST = { kp: 'КП', contract: 'Договор', techcard: 'Техкарта', act: 'Акт' };
  var IST = { draft: 'Черновик', sent: 'Отправлен', paid: 'Оплачен', overdue: 'Просрочен', cancelled: 'Отменён' };
  var TST = { actual: 'Актуальное', expired: 'Истёк срок', contracted: 'Договор', closed: 'Закрыто' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return v == null ? '—' : num(v).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }
  function msg(t, k) { var e = $('#msg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_client_context', { p_token: token }),
      rpc('app_client_orders', { p_token: token }),
      rpc('app_client_docs', { p_token: token }),
      rpc('app_client_invoices', { p_token: token }),
      rpc('app_client_tkp', { p_token: token })
    ]).then(function (r) {
      ctx = (r[0] && r[0][0]) || null; cache.ord = r[1] || []; cache.doc = r[2] || []; cache.inv = r[3] || []; cache.tkp = r[4] || [];
      if (ctx) { $('#ctx').textContent = 'Организация: ' + ctx.customer + (ctx.tenant_name ? ' · ' + ctx.tenant_name : ''); }
      var bal = cache.inv.reduce(function (s, i) { return s + num(i.balance); }, 0);
      $('#kpis').innerHTML = cell('Заявок', cache.ord.length) + cell('Документов', cache.doc.length) +
        cell('Счетов', cache.inv.length) + cell('К оплате', money(bal), bal > 0 ? '#b91c1c' : '#15803d') + cell('Предложений', cache.tkp.length);
      render();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); $('#panel').innerHTML = '<span class="note">Нет доступа или данных.</span>'; });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function table(head, rows) {
    return '<table class="table" style="width:100%;border-collapse:collapse"><thead><tr>' + head.map(function (h) { return '<th>' + h + '</th>'; }).join('') + '</tr></thead><tbody>' +
      (rows.length ? rows.map(function (r) { return '<tr style="border-bottom:1px solid var(--border)">' + r.map(function (c) { return '<td>' + c + '</td>'; }).join('') + '</tr>'; }).join('') : '<tr><td colspan="' + head.length + '"><span class="note">Нет данных.</span></td></tr>') + '</tbody></table>';
  }
  function render() {
    var p = '#panel';
    if (tab === 'ord') {
      $(p).innerHTML = table(['Номер', 'Тема', 'Статус', 'Срок', 'Сумма'], cache.ord.map(function (o) {
        return ['<b>' + esc(o.number) + '</b>', esc(o.title), '<span class="badge ' + o.status + '">' + (OST[o.status] || o.status) + '</span>', fmt(o.due_date), money(o.amount)];
      }));
    } else if (tab === 'doc') {
      $(p).innerHTML = table(['Номер', 'Тип', 'Название', 'Статус', 'Сумма', 'Срок'], cache.doc.map(function (d) {
        return ['<b>' + esc(d.number) + '</b>', DST[d.doc_type] || d.doc_type, esc(d.title), esc(d.status), money(d.amount), fmt(d.valid_until)];
      }));
    } else if (tab === 'inv') {
      $(p).innerHTML = table(['Счёт', 'Сумма', 'Оплачено', 'Остаток', 'Статус', 'Срок', 'Оплата'], cache.inv.map(function (i) {
        return ['<b>' + esc(i.number) + '</b>', money(i.amount), money(i.paid), money(i.balance),
          '<span class="badge ' + (i.is_overdue ? 'overdue' : i.status) + '">' + (i.is_overdue ? 'Просрочен' : (IST[i.status] || i.status)) + '</span>', fmt(i.due_date),
          (i.status === 'paid' ? '<span class="note">оплачен</span>' : '<button class="act" data-pay="' + esc(i.number) + '">💳 Оплатить</button>')];
      }));
      $$('#panel [data-pay]').forEach(function (b) {
        b.addEventListener('click', function () {
          var num = b.dataset.pay;
          rpc('app_client_pay', { p_token: token, p_invoice_number: num })
            .then(function (r) { var x = r && r[0]; msg((x && x.message) || '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { window.Auth.log('Оплата счёта', num); load(); } })
            .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
        });
      });
    } else {
      $(p).innerHTML = table(['Номер', 'Предмет', 'Срок', 'Цена', 'Статус'], cache.tkp.map(function (t) {
        return ['<b>' + esc(t.number) + '</b>', esc(t.subject), fmt(t.valid_until), money(t.price), (TST[t.status] || t.status)];
      }));
    }
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    tab = b.dataset.t; render();
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  function loadChat() {
    if (!$('#chatList')) return;
    rpc('app_client_chat_list', { p_token: token, p_customer_id: null, p_order_id: null }).then(function (rows) {
      rows = rows || [];
      $('#chatList').innerHTML = rows.length ? rows.map(function (m) {
        var mine = m.direction === 'client';
        return '<div style="display:flex;margin:4px 0;justify-content:' + (mine ? 'flex-end' : 'flex-start') + '"><div style="max-width:75%;padding:8px 11px;border-radius:12px;font-size:.85rem;background:' + (mine ? 'var(--accent-100)' : '#f1f5f9') + '"><div>' + esc(m.body) + '</div><div class="note" style="font-size:.68rem">' + esc(m.by_login || '') + ' · ' + new Date(m.at).toLocaleString('ru-RU') + '</div></div></div>';
      }).join('') : '<span class="note">Сообщений нет. Напишите менеджеру.</span>';
    }).catch(function (e) { $('#chatList').innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
  }
  if ($('#chatSend')) $('#chatSend').addEventListener('click', function () {
    var b = $('#chatInput').value.trim(); if (!b) return;
    rpc('app_client_chat_post', { p_token: token, p_customer_id: null, p_order_id: null, p_body: b })
      .then(function (d) { var x = d && d[0]; if (x && x.ok === false) { $('#chatMsg').className = 'msg show err'; $('#chatMsg').textContent = x.message; return; } $('#chatInput').value = ''; loadChat(); })
      .catch(function (e) { $('#chatMsg').className = 'msg show err'; $('#chatMsg').textContent = e.message; });
  });
  if ($('#chatInput')) $('#chatInput').addEventListener('keydown', function (e) { if (e.key === 'Enter') $('#chatSend').click(); });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (s.role !== 'client' && s.role !== 'admin') { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    load(); loadChat();
  });
})();
