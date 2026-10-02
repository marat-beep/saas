/* ============================================================
   3DMP Service · apps/supplier — Портал закупок для поставщиков
   Витрина закупок → карточка → подача предложения → мои КП.
   Данные: Supabase (таблицы tenders, bids из миграции 0002).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa;
  var SB = window.SB;

  var user = null, tenders = [], bids = [];
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
  $('#logout').addEventListener('click', function () {
    window.Session.signOut().then(function () { location.href = '../../index.html'; });
  });
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
  function msg(el, text, kind) {
    var e = $(el);
    e.className = 'msg show ' + (kind || 'info'); e.textContent = text;
  }
  function clearMsg(el) { var e = $(el); e.className = 'msg'; e.textContent = ''; }

  function isMissingTable(err) {
    if (!err) return false;
    var s = (err.message || '') + ' ' + (err.code || '');
    return /Could not find the table|PGRST205|42P01/i.test(s);
  }
  function showMigrationNote(el) {
    msg(el, 'Таблицы закупок не найдены. Примените миграцию supabase/migrations/0002_supplier.sql в Supabase → SQL Editor.', 'info');
  }

  /* ---------- загрузка ---------- */
  function loadTenders() {
    return SB.from('tenders').select('*').order('created_at', { ascending: false }).then(function (r) {
      if (r.error) throw r.error;
      return r.data || [];
    });
  }
  function loadBids() {
    return SB.from('bids')
      .select('id, tender_id, price, term_days, comment, status, created_at, tender:tenders ( title )')
      .eq('supplier_id', user.id)
      .order('created_at', { ascending: false })
      .then(function (r) { if (r.error) throw r.error; return r.data || []; });
  }

  function reload() {
    return Promise.all([
      loadTenders().catch(function (e) { if (isMissingTable(e)) migrationNote = true; return []; }),
      loadBids().catch(function (e) { if (isMissingTable(e)) migrationNote = true; return []; })
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
      return ([t.title, t.category, t.customer, t.material, t.description] .join(' ').toLowerCase().indexOf(qq) >= 0);
    });
  }
  function renderList() {
    var list = filtered();
    var el = $('#list');
    if (!list.length) { el.innerHTML = '<span class="note">Закупок не найдено.</span>'; return; }
    el.innerHTML = list.map(function (t) {
      var my = bids.filter(function (b) { return b.tender_id === t.id; })[0];
      return '<div class="tcard" data-id="' + t.id + '">' +
        '<div style="display:flex;gap:10px;align-items:center;">' + statusBadge(t.status) +
        (my ? '<span class="badge submitted" style="margin-left:auto;">Ваше КП: ' + bidBadge(my.status).replace(/<[^>]+>/g, '').trim() + '</span>' : '') + '</div>' +
        '<h3 style="margin-top:8px;">' + esc(t.title) + '</h3>' +
        '<div class="tmeta">' +
        (t.category ? '<span>🗂 ' + esc(t.category) + '</span>' : '') +
        (t.qty ? '<span>📦 ' + esc(t.qty) + ' ' + esc(t.unit || '') + '</span>' : '') +
        (t.material ? '<span>🧱 ' + esc(t.material) + '</span>' : '') +
        '</div>' +
        '<div class="tfoot"><span class="note">' + esc(t.customer || '') + '</span>' +
        '<span class="dl">до ' + ui.fmtDate(t.deadline) + '</span></div>' +
        '</div>';
    }).join('');
    $$('#list .tcard').forEach(function (c) {
      c.addEventListener('click', function () { openTender(c.dataset.id); });
    });
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
    if (!cur || !user) return;
    var price = parseFloat(String($('#bidPrice').value).replace(/\s/g, '').replace(',', '.'));
    var term = parseInt($('#bidTerm').value, 10);
    if (!price || price <= 0) { msg('#bidMsg', 'Укажите цену больше нуля.', 'err'); return; }
    var payload = {
      tender_id: cur.id,
      supplier_id: user.id,
      supplier_name: (window.Session && (window.Session.user && window.Session.user.email)) || '',
      price: price,
      term_days: isNaN(term) ? null : term,
      comment: $('#bidComment').value.trim() || null
    };
    SB.from('bids').upsert(payload, { onConflict: 'tender_id,supplier_id' }).then(function (r) {
      if (r.error) {
        if (isMissingTable(r.error)) { showMigrationNote('#bidMsg'); return; }
        msg('#bidMsg', 'Ошибка: ' + r.error.message, 'err'); return;
      }
      msg('#bidMsg', 'Предложение отправлено.', 'ok');
      return reload().then(function () {
        var my = bids.filter(function (b) { return b.tender_id === cur.id; })[0];
        if (my) $('#bidTitle').textContent = 'Изменить предложение';
      });
    }).catch(function (e) { msg('#bidMsg', 'Ошибка: ' + (e.message || e), 'err'); });
  });

  /* ---------- мои предложения ---------- */
  function renderMyBids() {
    var el = $('#myBids');
    if (migrationNote) { showMigrationNote('#bidsMsg'); }
    if (!bids.length) { el.innerHTML = '<span class="note">Вы ещё не подавали предложений.</span>'; return; }
    el.innerHTML = bids.map(function (b) {
      var t = b.tender || {};
      return '<div class="tcard" data-tid="' + b.tender_id + '">' +
        '<div style="display:flex;gap:10px;align-items:center;">' + bidBadge(b.status) +
        '<b style="margin-left:auto;">' + fmtMoney(b.price) + '</b></div>' +
        '<h3 style="margin-top:8px;">' + esc(t.title || 'Закупка') + '</h3>' +
        '<div class="tmeta"><span>Срок: ' + (b.term_days != null ? b.term_days + ' дн.' : '—') + '</span>' +
        '<span>от ' + ui.fmtDate(b.created_at) + '</span></div></div>';
    }).join('');
    $$('#myBids .tcard').forEach(function (c) {
      c.addEventListener('click', function () { openTender(c.dataset.tid); });
    });
  }
  $('#q').addEventListener('input', function () { q = this.value; renderList(); });
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderList();
  });

  /* ---------- старт ---------- */
  window.Session.guard('../auth/index.html').then(function (u) {
    if (!u) return;
    user = u;
    $('#who').textContent = u.email || '';
    if (!SB) { msg('#listMsg', 'Supabase не подключён. Проверьте config.js.', 'err'); return; }
    reload();
  });
})();
