/* ============================================================
   3DMP Service · apps/procurement — Закупки (закупщик)
   Потребность (заявка) → публикация → КП → победитель.
   Данные: 0008+0009+0032. Стандарт: docs/MODULE_STANDARD.md
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, tenders = [], orders = [], cur = null, filter = '', q = '';

  var ST = { open: 'Открыта', awarded: 'Победитель', closed: 'Закрыта' };

  /* ---------- Роли (data-cap) ---------- */
  var ALL = { edit: 1, reports: 1 };
  var CAPS = { admin: ALL, owner: ALL, director: ALL, manager: ALL, supply: ALL, chief: { reports: 1 }, economist: { reports: 1 }, default: { reports: 1 } };
  function can(c) { return !!(me && (CAPS[me.role] || CAPS['default'])[c]); }
  function applyCaps() { $$('[data-cap]').forEach(function (el) { var n = (el.dataset.cap || '').split('|'); if (!n.some(can)) el.style.display = 'none'; }); }
  function stBadge(s) { return '<span class="badge ' + s + '">' + (ST[s] || s) + '</span>'; }
  function bidBadge(s) { var m = { submitted: 'Подано', accepted: 'Принято', rejected: 'Отклонено' }; return '<span class="badge ' + (s === 'accepted' ? 'done' : s === 'rejected' ? 'cancelled' : '') + '">' + (m[s] || s) + '</span>'; }
  function esc(v) { return ui.esc(v); }
  function money(v) { return v == null ? '—' : (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function fmt(d) { if (!d) return ''; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return Promise.all([
      rpc('app_tender_list_full', { p_token: token }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      tenders = r[0] || []; orders = r[1] || [];
      $('#fOrder').innerHTML = '<option value="">— нет —</option>' + orders.map(function (o) { return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>'; }).join('');
      renderKpi(); render();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    var c = { open: 0, awarded: 0, closed: 0, bids: 0 };
    tenders.forEach(function (t) { c[t.status] = (c[t.status] || 0) + 1; c.bids += Number(t.bids_count) || 0; });
    $('#kpis').innerHTML =
      cell('Открыто', c.open) + cell('С победителем', c.awarded) + cell('Закрыто', c.closed) + cell('КП подано', c.bids);
    function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  }
  /* ---------- Отчёт (закупки) ---------- */
  function reportPdf() {
    if (!window.AppExport) { ui.toast('Экспорт недоступен'); return; }
    var best = tenders.reduce(function (s, t) { return s + (Number(t.best_price) || 0); }, 0);
    var cols = [
      { key: 'title', label: 'Закупка' }, { key: 'category', label: 'Категория' }, { key: 'material', label: 'Материал' },
      { key: 'qty', label: 'Кол-во', num: true }, { key: 'unit', label: 'Ед.' },
      { key: 'status', label: 'Статус', value: function (t) { return ST[t.status] || t.status; } },
      { key: 'deadline', label: 'Срок', value: function (t) { return t.deadline ? String(t.deadline).slice(0, 10) : ''; } },
      { key: 'bids_count', label: 'КП', num: true }, { key: 'best_price', label: 'Лучшая цена', num: true, value: function (t) { return money(t.best_price); } }
    ];
    AppExport.exportPdf('Закупки — отчёт', AppExport.reportDocument({
      brand: '3DMP Service', title: 'Отчёт по закупкам (тендеры)', subtitle: new Date().toLocaleDateString('ru-RU'),
      kpis: [{ label: 'Закупок', value: tenders.length }, { label: 'Сумма лучших КП', value: money(best) }],
      sections: [{ title: 'Закупки', columns: cols, rows: tenders }],
      sign: ['Отдел снабжения', 'Руководитель'], footer: '3DMP Service · закупки'
    }));
  }
  $('#repBtn').addEventListener('click', reportPdf);

  function filtered() {
    var s = q.toLowerCase();
    return tenders.filter(function (t) {
      if (filter && t.status !== filter) return false;
      if (!s) return true;
      return [t.title, t.category, t.material, t.order_number, t.customer, t.assignee].join(' ').toLowerCase().indexOf(s) >= 0;
    });
  }
  function render() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Закупок нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (t) {
      return '<div class="ocard" data-id="' + t.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' + stBadge(t.status) +
        (t.order_number ? '<span class="badge">📥 ' + esc(t.order_number) + '</span>' : '') +
        '<span class="note" style="margin-left:auto;">КП: ' + t.bids_count + (t.best_price ? ' · лучшая ' + money(t.best_price) : '') + '</span></div>' +
        '<h3 style="font-size:.95rem;margin:8px 0 4px;">' + esc(t.title) + '</h3>' +
        '<div style="font-size:.76rem;color:var(--muted);">' +
        (t.category ? '🗂 ' + esc(t.category) + ' · ' : '') + (t.material ? '🧱 ' + esc(t.material) + ' · ' : '') +
        (t.qty ? '📦 ' + esc(t.qty) + ' ' + esc(t.unit || '') + ' · ' : '') +
        (t.deadline ? 'до ' + fmt(t.deadline) : '') + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openDetail(c.dataset.id); }); });
  }

  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function openDetail(id) {
    rpc('app_tender_get', { p_token: token, p_id: id }).then(function (r) {
      cur = r && r[0]; if (!cur) { ui.toast('Закупка не найдена'); return; }
      $('#detail').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;">' + stBadge(cur.status) + '</div>' +
        '<h1 style="font-size:1.15rem;margin:10px 0;">' + esc(cur.title) + '</h1>' +
        (cur.description ? '<p style="color:var(--muted);line-height:1.6;">' + esc(cur.description) + '</p>' : '') +
        kv('Заявка', cur.order_number) + kv('Категория', cur.category) + kv('Материал', cur.material) +
        kv('Количество', cur.qty ? cur.qty + ' ' + (cur.unit || '') : '') + kv('Заказчик', cur.customer) +
        kv('Исполнитель', cur.assignee) + kv('Срок подачи', fmt(cur.deadline)) +
        kv('КП подано', String(cur.bids_count)) + kv('Лучшая цена', cur.best_price != null ? money(cur.best_price) : '');
      $('#dStatus').value = (cur.status === 'awarded') ? 'closed' : cur.status;
      clearMsg('#dMsg');
      loadBids();
      screens.go('s-detail');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function loadBids() {
    rpc('app_bids_for_tender', { p_token: token, p_tender_id: cur.id }).then(function (bids) {
      bids = bids || [];
      if (!bids.length) { $('#bids').innerHTML = '<span class="note">Предложений пока нет.</span>'; return; }
      var best = Math.min.apply(null, bids.map(function (b) { return Number(b.price) || Infinity; }));
      $('#bids').innerHTML = bids.map(function (b) {
        var isBest = (Number(b.price) === best);
        return '<div class="bid' + (isBest ? ' best' : '') + '"><div style="display:flex;gap:8px;align-items:center;">' + bidBadge(b.status) +
          (isBest ? '<span class="badge done">лучшая</span>' : '') +
          '<b style="margin-left:auto;">' + money(b.price) + '</b></div>' +
          '<div style="font-size:.84rem;margin-top:6px;">' + esc(b.supplier_name || '—') + ' · срок ' + (b.term_days != null ? b.term_days + ' дн.' : '—') + '</div>' +
          (b.comment ? '<div style="font-size:.78rem;color:var(--muted);margin-top:4px;">' + esc(b.comment) + '</div>' : '') +
          (cur.status !== 'awarded' ? '<button class="btn secondary" style="width:auto;margin-top:8px;padding:8px 14px;" data-award="' + b.id + '">Выбрать победителя</button>' : '') +
          '</div>';
      }).join('');
      $$('#bids [data-award]').forEach(function (btn) {
        btn.addEventListener('click', function () {
          rpc('app_tender_award', { p_token: token, p_tender_id: cur.id, p_bid_id: btn.dataset.award }).then(function (d) {
            var row = d && d[0];
            window.Auth.log('Победитель закупки', cur.title);
            ui.toast((row && row.message) || 'Победитель выбран');
            if (window.AppNotify) window.AppNotify.refresh(true);
            load().then(function () { openDetail(cur.id); });
          }).catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
        });
      });
    });
  }

  $('#toCreate').addEventListener('click', function () { clearMsg('#cMsg'); screens.go('s-create'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { load(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('#filters .chip').forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; render();
  });
  $('#q').addEventListener('input', function () { q = this.value; render(); });

  $('#createBtn').addEventListener('click', function () {
    var title = $('#fTitle').value.trim();
    if (!title) { msg('#cMsg', 'Укажите название.', 'err'); return; }
    var qty = parseFloat(($('#fQty').value || '').replace(',', '.'));
    rpc('app_tender_create', {
      p_token: token, p_title: title, p_description: $('#fDesc').value.trim(), p_category: $('#fCategory').value.trim(),
      p_material: $('#fMaterial').value.trim(), p_qty: isNaN(qty) ? null : qty, p_unit: $('#fUnit').value.trim(),
      p_customer: $('#fCustomer').value.trim(), p_deadline: $('#fDeadline').value || null,
      p_order_id: $('#fOrder').value || null, p_assignee: $('#fAssignee').value.trim()
    }).then(function () {
      window.Auth.log('Опубликована закупка', title);
      ui.toast('Закупка опубликована');
      ['#fTitle', '#fDesc', '#fCategory', '#fMaterial', '#fQty', '#fUnit', '#fCustomer', '#fDeadline', '#fAssignee'].forEach(function (s) { $(s).value = ''; });
      $('#fOrder').value = '';
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
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token; applyCaps();
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
