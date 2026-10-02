/* ============================================================
   3DMP Service · apps/supplier — Портал закупок для поставщиков
   Вход по токену сессии (Auth). Данные — Supabase:
   tenders (публичное чтение), bids — через RPC supplier_* (0003_app_auth.sql).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa;
  var SB = window.SB;

  var user = null, token = null, tenders = [], bids = [];
  var filter = 'all', q = '', cur = null;
  var migrationNote = false;

  var screens = AppRouter.create({
    onShow: function (s) {
      $$('#nav button').forEach(function (b) { b.classList.toggle('active', b.dataset.go === s.id); });
      window.scrollTo(0, 0);
    },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  $('#nav').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    if (b.dataset.go === 's-bids') renderMyBids();
    screens.go(b.dataset.go);
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  $('#backToList').addEventListener('click', function () { screens.go('s-list'); });

  /* ---------- утилиты ---------- */
  function fmtMoney(v) { return (Number(v) || 0).toLocaleString('ru-RU') + ' ₽'; }
  function statusBadge(s) {
    var map = { open: ['open', 'Открыта'], closed: ['closed', 'Закрыта'], awarded: ['awarded', 'Победитель'] };
    var m = map[s] || ['closed', s || '—'];
    return '<span class="badge ' + m[0] + '">' + m[1] + '</span>';
  }
  function bidBadge(s) {
    var map = { submitted: ['submitted', 'Подано'], accepted: ['accepted', 'Принято'], rejected: ['rejected', 'Отклонено'] };
    var m = map[s] || ['submitted', s || '—'];
    return '<span class="badge ' + m[0] + '">' + m[1] + '</span>';
  }
  function esc(v) { return ui.esc(v); }
  function msg(el, text, kind) { var e = $(el); e.className = 'msg show ' + (kind || 'info'); e.textContent = text; }
  function clearMsg(el) { var e = $(el); e.className = 'msg'; e.textContent = ''; }

  function isMissing(err) {
    if (!err) return false;
    var s = (err.message || '') + ' ' + (err.code || '');
    return /Could not find the table|Could not find the function|PGRST205|PGRST202|42P01|42883/i.test(s);
  }
  function showMigrationNote(el) {
    msg(el, 'Таблицы/функции закупок не найдены. Примените миграции 0002_supplier.sql и 0003_app_auth.sql в Supabase → SQL Editor.', 'info');
  }

  /* ---------- загрузка ---------- */
  function loadTenders() {
    return SB.from('tenders').select('*').order('created_at', { ascending: false }).then(function (r) {
      if (r.error) throw r.error;
      return r.data || [];
    });
  }
  function loadBids() {
    return SB.rpc('supplier_my_bids', { p_token: token }).then(function (r) {
      if (r.error) throw r.error;
      return r.data || [];
    });
  }

  function reload() {
    return Promise.all([
      loadTenders().catch(function (e) { if (isMissing(e)) migrationNote = true; return []; }),
      loadBids().catch(function (e) { if (isMissing(e)) migrationNote = true; return []; })
    ]).then(function (res) {
      tenders = res[0]; bids = res[1];
      renderList();
      if (migrationNote) showMigrationNote('#listMsg');
    });
  }

  /* ---------- витрина ---------- */
  function filtered() {
    var qq = q.trim().toLowerCase();
    return tenders.filter(function (t) {
      if (filter === 'open' && t.status !== 'open') return false;
      if (filter === 'awarded' && t.status !== 'awarded') return false;
      if (!qq) return true;
      return ([t.title, t.category, t.customer, t.material, t.description].join(' ').toLowerCase().indexOf(qq) >= 0);
    });
  }
  function renderList() {
    var list = filtered(), el = $('#list');
    if (!list.length) { el.innerHTML = '<span class="note">Закупок не найдено.</span>'; return; }
    el.innerHTML = list.map(function (t) {
      var my = bids.filter(function (b) { return b.tender_id === t.id; })[0];
      return '<div class="tcard" data-id="' + t.id + '">' +
        '<div style="display:flex;gap:10px;align-items:center;">' + statusBadge(t.status) +
        (my ? '<span class="badge submitted" style="margin-left:auto;">Ваше КП</span>' : '') + '</div>' +
        '<h3 style="margin-top:8px;">' + esc(t.title) + '</h3>' +
        '<div class="tmeta">' +
        (t.category ? '<span>🗂 ' + esc(t.category) + '</span>' : '') +
        (t.qty ? '<span>📦 ' + esc(t.qty) + ' ' + esc(t.unit || '') + '</span>' : '') +
        (t.material ? '<span>🧱 ' + esc(t.material) + '</span>' : '') +
        '</div>' +
        '<div class="tfoot"><span class="note">' + esc(t.customer || '') + '</span>' +
        '<span class="dl">до ' + ui.fmtDate(t.deadline) + '</span></div></div>';
    }).join('');
    $$('#list .tcard').forEach(function (c) { c.addEventListener('click', function () { openTender(c.dataset.id); }); });
  }

  /* ---------- карточка ---------- */
  function openTender(id) {
    cur = tenders.filter(function (t) { return t.id === id; })[0];
    if (!cur) return;
    var my = bids.filter(function (b) { return b.tender_id === id; })[0];
    $('#tender').innerHTML =
      '<div style="display:flex;gap:10px;align-items:center;">' + statusBadge(cur.status) + '</div>' +
      '<h1 style="font-size:1.2rem;margin:10px 0;">' + esc(cur.title) + '</h1>' +
      (cur.description ? '<p style="color:var(--muted);line-height:1.6;margin-bottom:10px;">' + esc(cur.description) + '</p>' : '') +
      kv('Категория', cur.category) + kv('Материал', cur.material) +
      kv('Количество', cur.qty ? cur.qty + ' ' + (cur.unit || '') : '') +
      kv('Заказчик', cur.customer) + kv('Срок подачи', ui.fmtDate(cur.deadline));
    $('#bidTitle').textContent = my ? 'Изменить предложение' : 'Подать предложение';
    $('#bidPrice').value = my ? my.price : '';
    $('#bidTerm').value = my && my.term_days != null ? my.term_days : '';
    $('#bidComment').value = my && my.comment ? my.comment : '';
    clearMsg('#bidMsg');
    screens.go('s-tender');
  }
  function kv(k, v) { return v ? '<div class="kv"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }

  /* ---------- подача предложения ---------- */
  $('#bidSubmit').addEventListener('click', function () {
    if (!cur || !token) return;
    var price = parseFloat(String($('#bidPrice').value).replace(/\s/g, '').replace(',', '.'));
    var term = parseInt($('#bidTerm').value, 10);
    if (!price || price <= 0) { msg('#bidMsg', 'Укажите цену больше нуля.', 'err'); return; }
    SB.rpc('supplier_submit_bid', {
      p_token: token, p_tender_id: cur.id, p_price: price,
      p_term_days: isNaN(term) ? null : term, p_comment: $('#bidComment').value.trim()
    }).then(function (r) {
      if (r.error) { if (isMissing(r.error)) { showMigrationNote('#bidMsg'); return; } msg('#bidMsg', 'Ошибка: ' + r.error.message, 'err'); return; }
      var row = r.data && r.data[0];
      if (!row || !row.ok) { msg('#bidMsg', (row && row.message) || 'Не удалось сохранить.', 'err'); return; }
      msg('#bidMsg', row.message || 'Предложение сохранено.', 'ok');
      return reload().then(function () { $('#bidTitle').textContent = 'Изменить предложение'; });
    }).catch(function (e) { msg('#bidMsg', 'Ошибка: ' + (e.message || e), 'err'); });
  });

  /* ---------- мои предложения ---------- */
  function renderMyBids() {
    var el = $('#myBids');
    if (migrationNote) showMigrationNote('#bidsMsg');
    if (!bids.length) { el.innerHTML = '<span class="note">Вы ещё не подавали предложений.</span>'; return; }
    el.innerHTML = bids.map(function (b) {
      return '<div class="tcard" data-tid="' + b.tender_id + '">' +
        '<div style="display:flex;gap:10px;align-items:center;">' + bidBadge(b.status) +
        '<b style="margin-left:auto;">' + fmtMoney(b.price) + '</b></div>' +
        '<h3 style="margin-top:8px;">' + esc(b.tender_title || 'Закупка') + '</h3>' +
        '<div class="tmeta"><span>Срок: ' + (b.term_days != null ? b.term_days + ' дн.' : '—') + '</span>' +
        '<span>от ' + ui.fmtDate(b.created_at) + '</span></div></div>';
    }).join('');
    $$('#myBids .tcard').forEach(function (c) { c.addEventListener('click', function () { openTender(c.dataset.tid); }); });
  }
  $('#q').addEventListener('input', function () { q = this.value; renderList(); });
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });

  /* ---------- старт ---------- */
  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    user = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#listMsg', 'Supabase не подключён. Проверьте config.js.', 'err'); return; }
    reload();
  });
})();
