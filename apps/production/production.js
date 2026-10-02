/* ============================================================
   3DMP Service · apps/production — наряды и операции
   Данные: app_naryad_* (0007_production.sql). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, naryads = [], wcs = [], orders = [], cur = null;

  var ST = { open: 'Открыт', in_progress: 'В работе', closed: 'Закрыт' };
  function stBadge(s) { return '<span class="b ' + s + '">' + (ST[s] || s) + '</span>'; }
  function esc(v) { return ui.esc(v); }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleDateString('ru-RU'); }
  function num(v) { return (Number(v) || 0); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function loadAll() {
    return Promise.all([
      rpc('app_naryad_list', { p_token: token }),
      rpc('app_wc_list', { p_token: token }),
      rpc('app_order_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      naryads = r[0] || []; wcs = r[1] || []; orders = r[2] || [];
      $('#fWc').innerHTML = '<option value="">— не выбрано —</option>' + wcs.map(function (w) {
        return '<option value="' + w.id + '">' + esc(w.name) + (w.cost_hour ? ' · ' + w.cost_hour + ' ₽/ч' : '') + '</option>';
      }).join('');
      $('#fOrder').innerHTML = '<option value="">— без заявки —</option>' + orders.map(function (o) {
        return '<option value="' + o.id + '">' + esc(o.number) + ' · ' + esc(o.title) + '</option>';
      }).join('');
      renderList();
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderList() {
    if (!naryads.length) { $('#list').innerHTML = '<span class="note">Нарядов нет.</span>'; return; }
    $('#list').innerHTML = naryads.map(function (n) {
      return '<div class="ncard" data-id="' + n.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;">' + stBadge(n.status) +
        '<span class="note" style="margin-left:auto;">' + esc(n.number) + '</span></div>' +
        '<h3 style="font-size:.95rem;margin:8px 0 4px;">' + esc(n.title) + '</h3>' +
        '<div style="font-size:.76rem;color:var(--muted);">' +
        (n.wc_name ? '🏭 ' + esc(n.wc_name) + ' · ' : '') +
        (n.assignee ? '👤 ' + esc(n.assignee) + ' · ' : '') +
        'план ' + num(n.plan_hours) + ' ч / факт ' + num(n.fact_hours) + ' ч' +
        (n.order_number ? ' · 📥 ' + esc(n.order_number) : '') + '</div></div>';
    }).join('');
    $$('#list .ncard').forEach(function (c) { c.addEventListener('click', function () { openDetail(c.dataset.id); }); });
  }

  function openDetail(id) {
    Promise.all([rpc('app_naryad_get', { p_token: token, p_id: id }), rpc('app_naryad_ops', { p_token: token, p_id: id })]).then(function (r) {
      var n = r[0] && r[0][0]; if (!n) { ui.toast('Наряд не найден'); return; }
      cur = n;
      $('#detail').innerHTML =
        '<div style="display:flex;gap:8px;align-items:center;">' + stBadge(n.status) + '<b style="margin-left:auto;">' + esc(n.number) + '</b></div>' +
        '<h1 style="font-size:1.15rem;margin:10px 0;">' + esc(n.title) + '</h1>' +
        kv('Рабочий центр', n.wc_name) + kv('Исполнитель', n.assignee) + kv('Заявка', n.order_number) +
        kv('Срок', n.due_date ? fmt(n.due_date) : '') + kv('План / факт', num(n.plan_hours) + ' / ' + num(n.fact_hours) + ' ч') +
        kv('Автор', n.created_login);
      renderOps(r[1] || []);
      $('#closeBtn').disabled = n.status === 'closed';
      clearMsg('#opMsg');
      screens.go('s-detail');
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }

  function renderOps(ops) {
    if (!ops.length) { $('#ops').innerHTML = '<span class="note">Операций нет.</span>'; return; }
    $('#ops').innerHTML = ops.map(function (o) {
      return '<div class="opline" data-op="' + o.id + '">' +
        '<div class="n">' + o.seq + '</div>' +
        '<div>' + esc(o.operation) + (o.done ? ' <span class="b closed">готово</span>' : '') + '</div>' +
        '<div>' + num(o.plan_hours) + '</div>' +
        '<input type="text" data-fact="' + o.id + '" inputmode="decimal" value="' + num(o.fact_hours) + '">' +
        '<button class="act" data-done="' + o.id + '" style="background:none;border:1px solid var(--border);border-radius:8px;padding:5px 8px;cursor:pointer;font-size:.74rem;">✓</button>' +
        '</div>';
    }).join('');
    $$('#ops [data-done]').forEach(function (b) {
      b.addEventListener('click', function () {
        var fid = b.dataset.done; var fv = parseFloat(($('#ops [data-fact="' + fid + '"]') || {}).value || '0');
        rpc('app_naryad_op_done', { p_token: token, p_op_id: fid, p_fact_hours: isNaN(fv) ? 0 : fv, p_done: true })
          .then(function () { window.Auth.log('Операция выполнена', cur && cur.number); openDetail(cur.id); })
          .catch(function (e) { msg('#opMsg', 'Ошибка: ' + e.message, 'err'); });
      });
    });
  }

  $('#toCreate').addEventListener('click', function () { clearMsg('#cMsg'); screens.go('s-create'); });
  $('#back1').addEventListener('click', function () { screens.go('s-list'); });
  $('#back2').addEventListener('click', function () { loadAll(); screens.go('s-list'); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  $('#createBtn').addEventListener('click', function () {
    var title = $('#fTitle').value.trim();
    if (!title) { msg('#cMsg', 'Укажите название наряда.', 'err'); return; }
    rpc('app_naryad_create', {
      p_token: token, p_order_id: $('#fOrder').value || null, p_title: title,
      p_wc_id: $('#fWc').value || null, p_assignee: $('#fAssignee').value.trim(), p_due_date: $('#fDue').value || null
    }).then(function (d) {
      var row = d && d[0];
      window.Auth.log('Создан наряд', (row && row.number) || title);
      if (window.AppNotify) window.AppNotify.refresh(true);
      ui.toast('Наряд ' + ((row && row.number) || '') + ' создан');
      ['#fTitle', '#fAssignee', '#fDue'].forEach(function (s) { $(s).value = ''; });
      loadAll().then(function () { screens.go('s-list'); });
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#addOp').addEventListener('click', function () {
    if (!cur) return;
    var name = $('#opName').value.trim();
    if (!name) { msg('#opMsg', 'Укажите операцию.', 'err'); return; }
    var ph = parseFloat($('#opPlan').value.replace(',', '.'));
    rpc('app_naryad_add_op', { p_token: token, p_naryad_id: cur.id, p_operation: name, p_worker: '', p_plan_hours: isNaN(ph) ? 0 : ph })
      .then(function () { $('#opName').value = ''; $('#opPlan').value = ''; openDetail(cur.id); })
      .catch(function (e) { msg('#opMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#closeBtn').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_naryad_close', { p_token: token, p_id: cur.id }).then(function (d) {
      var row = d && d[0];
      if (!row || !row.ok) { msg('#opMsg', (row && row.message) || 'Не удалось', 'err'); return; }
      window.Auth.log('Закрыт наряд', cur.number);
      ui.toast('Наряд закрыт');
      openDetail(cur.id);
    }).catch(function (e) { msg('#opMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (['admin', 'owner', 'manager'].indexOf(s.role) < 0) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    // Автосоздание наряда по кнопке «Новый наряд»
    loadAll();
  });
})();
