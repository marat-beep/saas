/* ============================================================
   3DMP Service · apps/procurement — закупки (закупщик)
   Публикация закупок, приём КП, выбор победителя. Данные: app_tender_* (0008).
   Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, tenders = [], cur = null;

  var ST = { open: 'Открыта', awarded: 'Победитель', closed: 'Закрыта' };
  function stBadge(s) { return '<span class="b ' + s + '">' + (ST[s] || s) + '</span>'; }
  function bidBadge(s) { var m = { submitted: 'Подано', accepted: 'Принято', rejected: 'Отклонено' }; return '<span class="b ' + s + '">' + (m[s] || s) + '</span>'; }
  function esc(v) { return ui.esc(v); }
  function money(v) { return (Number(v) || 0).toLocaleString('ru-RU') + ' ₽'; }
  function fmt(d) { if (!d) return ''; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return rpc('app_tender_list_full', { p_token: token }).then(function (d) { tenders = d || []; render(); })
      .catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function render() {
    if (!tenders.length) { $('#list').innerHTML = '<span class="note">Закупок нет.</span>'; return; }
    $('#list').innerHTML = tenders.map(function (t) {
      return '<div class="tcard" data-id="' + t.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;">' + stBadge(t.status) +
        '<span class="note" style="margin-left:auto;">КП: ' + t.bids_count + '</span></div>' +
        '<h3 style="font-size:.95rem;margin:8px 0 4px;">' + esc(t.title) + '</h3>' +
        '<div style="font-size:.76rem;color:var(--muted);">' +
        (t.category ? '🗂 ' + esc(t.category) + ' · ' : '') + (t.customer ? esc(t.customer) + ' · ' : '') +
        (t.deadline ? 'до ' + fmt(t.deadline) : '') + '</div></div>';
    }).join('');
    $$('#list .tcard').forEach(function (c) { c.addEventListener('click', function () { openDetail(c.dataset.id); }); });
  }

  function openDetail(id) {
    cur = tenders.filter(function (t) { return t.id === id; })[0] || null;
    if (!cur) return;
    $('#detail').innerHTML =
      '<div style="display:flex;gap:8px;align-items:center;">' + stBadge(cur.status) + '</div>' +
      '<h1 style="font-size:1.15rem;margin:10px 0;">' + esc(cur.title) + '</h1>' +
      kv('Категория', cur.category) + kv('Заказчик', cur.customer) + kv('Срок', cur.deadline ? fmt(cur.deadline) : '') + kv('КП', String(cur.bids_count));
    $('#dStatus').value = cur.status === 'closed' ? 'closed' : 'open';
    clearMsg('#dMsg');
    rpc('app_bids_for_tender', { p_token: token, p_tender_id: id }).then(function (bids) {
      bids = bids || [];
      if (!bids.length) { $('#bids').innerHTML = '<span class="note">Предложений пока нет.</span>'; }
      else {
        $('#bids').innerHTML = bids.map(function (b) {
          return '<div class="bid"><div style="display:flex;gap:8px;align-items:center;">' + bidBadge(b.status) +
            '<b style="margin-left:auto;">' + money(b.price) + '</b></div>' +
            '<div style="font-size:.84rem;margin-top:6px;">' + esc(b.supplier_name || '—') + ' · срок ' + (b.term_days != null ? b.term_days + ' дн.' : '—') + '</div>' +
            (b.comment ? '<div style="font-size:.78rem;color:var(--muted);margin-top:4px;">' + esc(b.comment) + '</div>' : '') +
            (cur.status !== 'awarded' ? '<button class="btn secondary" style="width:auto;margin-top:8px;padding:8px 14px;" data-award="' + b.id + '">Выбрать победителя</button>' : '') +
            '</div>';
        }).join('');
        $$('#bids [data-award]').forEach(function (btn) {
          btn.addEventListener('click', function () {
            rpc('app_tender_award', { p_token: token, p_tender_id: id, p_bid_id: btn.dataset.award }).then(function (d) {
              var row = d && d[0];
              window.Auth.log('Победитель закупки', cur.title);
              msg('#dMsg', (row && row.message) || 'Готово', 'ok');
              load().then(function () { openDetail(id); });
            }).catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
          });
        });
      }
      screens.go('s-detail');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }

  $('#toCreate').addEventListener('click', function () { clearMsg('#cMsg'); screens.go('s-create'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  $('#createBtn').addEventListener('click', function () {
    var title = $('#fTitle').value.trim();
    if (!title) { msg('#cMsg', 'Укажите название.', 'err'); return; }
    var qty = parseFloat($('#fQty').value.replace(',', '.'));
    rpc('app_tender_create', {
      p_token: token, p_title: title, p_description: $('#fDesc').value.trim(), p_category: $('#fCategory').value.trim(),
      p_material: $('#fMaterial').value.trim(), p_qty: isNaN(qty) ? null : qty, p_unit: $('#fUnit').value.trim(),
      p_customer: $('#fCustomer').value.trim(), p_deadline: $('#fDeadline').value || null
    }).then(function (d) {
      var row = d && d[0];
      window.Auth.log('Опубликована закупка', title);
      ui.toast('Закупка опубликована');
      ['#fTitle', '#fDesc', '#fCategory', '#fMaterial', '#fQty', '#fUnit', '#fCustomer', '#fDeadline'].forEach(function (s) { $(s).value = ''; });
      load().then(function () { screens.go('s-list'); });
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#stBtn').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_tender_set_status', { p_token: token, p_tender_id: cur.id, p_status: $('#dStatus').value }).then(function () {
      window.Auth.log('Статус закупки', cur.title + ' → ' + $('#dStatus').value);
      msg('#dMsg', 'Статус обновлён.', 'ok'); load();
    }).catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (['admin', 'owner', 'manager'].indexOf(s.role) < 0) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
