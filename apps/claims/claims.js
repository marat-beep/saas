/* ============================================================
   3DMP Service · apps/claims — претензии и CAPA (W2).
   Данные: 0117 (app_claim_list/save/set_status/escalate/delete,
   app_capa_list/save/delete). Связь с app_issues (проблемы).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, claims = [], cur = null, filter = '', q = '';

  var ST = { new: 'Новая', accepted: 'Принята', in_work: 'В работе', capa: 'CAPA', closed: 'Закрыта', rejected: 'Отклонена' };
  var SEV = { minor: 'Незнач.', major: 'Значит.', critical: 'Критич.' };
  var CSTAT = { planned: 'Запланировано', in_work: 'В работе', done: 'Выполнено', verified: 'Проверено' };
  var CKIND = { corrective: 'Корректирующее', preventive: 'Предупреждающее' };

  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function fmt(ts) { if (!ts) return '—'; var d = new Date(ts); return isNaN(d.getTime()) ? String(ts) : d.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function sevBadge(s) { return '<span class="badge ' + (s === 'critical' ? 'cancelled' : s === 'major' ? 'in_progress' : '') + '">' + (SEV[s] || s) + '</span>'; }
  var screens = AppRouter.create({ onShow: function () { window.scrollTo(0, 0); }, onBackEmpty: function () { location.href = '../../index.html'; } });

  function load() {
    return rpc('app_claim_list', { p_token: token }).then(function (r) {
      claims = r || [];
      renderKpi(); render();
      if (cur) { var c = claims.filter(function (x) { return x.id === cur.id; })[0]; if (!c) { screens.go('s-list'); cur = null; } }
    }).catch(function (e) { msg('#listMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function renderKpi() {
    var k = { total: claims.length, open: 0, work: 0, closed: 0, capa: 0 };
    claims.forEach(function (c) {
      if (c.status === 'new') k.open++;
      if (c.status === 'in_work' || c.status === 'accepted') k.work++;
      if (c.status === 'closed' || c.status === 'rejected') k.closed++;
      k.capa += Math.max(0, num(c.capa_total) - num(c.capa_done));
    });
    $('#kpis').innerHTML = cell('Всего', k.total) + cell('Новых', k.open) + cell('В работе', k.work) +
      cell('Закрытых', k.closed) + cell('CAPA открыто', k.capa, k.capa ? '#b45309' : '');
    function cell(l, v, col) { return '<div class="kpi"><small>' + l + '</small><b' + (col ? ' style="color:' + col + '"' : '') + '>' + v + '</b></div>'; }
  }
  function filtered() {
    var s = q.toLowerCase();
    return claims.filter(function (c) {
      if (filter && c.status !== filter) return false;
      if (!s) return true;
      return [c.number, c.customer, c.product, c.reason].join(' ').toLowerCase().indexOf(s) >= 0;
    });
  }
  function render() {
    var list = filtered();
    if (!list.length) { $('#list').innerHTML = '<span class="note">Претензий нет.</span>'; return; }
    $('#list').innerHTML = list.map(function (c) {
      return '<div class="ocard" data-id="' + c.id + '">' +
        '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;"><span class="badge ' + (c.status === 'closed' ? 'done' : c.status === 'rejected' ? 'cancelled' : 'in_progress') + '">' + (ST[c.status] || c.status) + '</span>' +
        sevBadge(c.severity) +
        (c.capa_total ? '<span class="badge">CAPA ' + num(c.capa_done) + '/' + num(c.capa_total) + '</span>' : '') +
        (c.issue_id ? '<span class="badge cancelled">⚡ проблема</span>' : '') +
        '<span class="note" style="margin-left:auto;">' + esc(c.number) + '</span></div>' +
        '<h3 style="font-size:.94rem;margin:8px 0 4px;">' + esc(c.reason || 'Претензия') + '</h3>' +
        '<div style="font-size:.76rem;color:var(--muted);">' +
        (c.customer ? '🏢 ' + esc(c.customer) + ' · ' : '') + (c.product ? '📦 ' + esc(c.product) + ' · ' : '') +
        '×' + num(c.qty) + (c.assigned_login ? ' · 👤 ' + esc(c.assigned_login) : '') + '</div></div>';
    }).join('');
    $$('#list .ocard').forEach(function (c) { c.addEventListener('click', function () { openItem(c.dataset.id); }); });
  }

  function kv(k, v) { return v ? '<div class="kvr"><span class="k">' + k + '</span><b>' + esc(v) + '</b></div>' : ''; }
  function openItem(id) {
    if (!claims.length) return;
    cur = claims.filter(function (c) { return c.id === id; })[0]; if (!cur) return;
    $('#claim').innerHTML =
      '<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;"><span class="badge ' + (cur.status === 'closed' ? 'done' : 'in_progress') + '">' + (ST[cur.status] || cur.status) + '</span>' +
      sevBadge(cur.severity) + '<b style="margin-left:auto;">' + esc(cur.number) + '</b></div>' +
      '<h1 style="font-size:1.1rem;margin:10px 0;">' + esc(cur.reason || 'Претензия') + '</h1>' +
      kv('Заказчик', cur.customer) + kv('Изделие', cur.product) + kv('Количество', cur.qty) +
      kv('Ответственный', cur.assigned_login) + kv('Заявка', cur.order_number) +
      kv('Связанная проблема', cur.issue_title) + kv('Создана', fmt(cur.created_at));
    $('#stSel').value = cur.status;
    clearMsg('#iMsg');
    loadCapa();
    screens.go('s-item');
  }
  function loadCapa() {
    if (!cur) return;
    rpc('app_capa_list', { p_token: token, p_claim_id: cur.id }).then(function (a) {
      a = a || [];
      $('#capaList').innerHTML = a.length ? a.map(function (x) {
        return '<div class="capa-row"><span class="badge">' + (CKIND[x.kind] || x.kind) + '</span>' +
          '<b style="flex:1;">' + esc(x.title) + '</b>' +
          (x.responsible ? '<span class="note">👤 ' + esc(x.responsible) + '</span>' : '') +
          (x.due_date ? '<span class="note">до ' + esc(String(x.due_date).slice(0, 10)) + '</span>' : '') +
          '<span class="badge ' + (x.status === 'done' || x.status === 'verified' ? 'done' : 'in_progress') + '">' + (CSTAT[x.status] || x.status) + '</span>' +
          '<button class="act" data-edit="' + x.id + '">Изменить</button>' +
          '<button class="act danger" data-del="' + x.id + '">Удалить</button></div>';
      }).join('') : '<span class="note">Мероприятий нет.</span>';
      $$('#capaList [data-edit]').forEach(function (b) { b.addEventListener('click', function () { var x = a.filter(function (y) { return y.id === b.dataset.edit; })[0]; capaForm(x); }); });
      $$('#capaList [data-del]').forEach(function (b) {
        b.addEventListener('click', function () {
          if (!window.confirm('Удалить мероприятие?')) return;
          rpc('app_capa_delete', { p_token: token, p_id: b.dataset.del }).then(function (r) { var x = r && r[0]; msg('#iMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadCapa(); load(); });
        });
      });
    });
  }
  function capaForm(x) {
    x = x || {};
    ui.formDialog({
      title: x.id ? 'CAPA-мероприятие' : 'Новое мероприятие', okText: 'Сохранить', size: 'lg',
      fields: [
        { name: 'kind', label: 'Тип', type: 'select', options: [{ value: 'corrective', label: 'Корректирующее' }, { value: 'preventive', label: 'Предупреждающее' }] },
        { name: 'title', label: 'Мероприятие', type: 'text', required: true },
        { name: 'responsible', label: 'Ответственный', type: 'text' },
        { name: 'due_date', label: 'Срок', type: 'date' },
        { name: 'status', label: 'Статус', type: 'select', options: [{ value: 'planned', label: 'Запланировано' }, { value: 'in_work', label: 'В работе' }, { value: 'done', label: 'Выполнено' }, { value: 'verified', label: 'Проверено' }] },
        { name: 'note', label: 'Примечание', type: 'textarea', rows: 2 }
      ],
      values: {
        kind: x.kind || 'corrective', title: x.title || '', responsible: x.responsible || '',
        due_date: x.due_date ? String(x.due_date).slice(0, 10) : '', status: x.status || 'planned', note: x.note || ''
      }
    }).then(function (v) {
      if (!v) return;
      rpc('app_capa_save', { p_token: token, p_id: x.id || null, p_claim_id: cur.id, p_kind: v.kind, p_title: v.title, p_responsible: v.responsible, p_due_date: v.due_date || null, p_status: v.status, p_note: v.note })
        .then(function (r) { var y = r && r[0]; msg('#iMsg', y ? y.message : '', y && y.ok ? 'ok' : 'err'); if (y && y.ok) { window.Auth.log('CAPA', v.title); loadCapa(); load(); } })
        .catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
    });
  }

  $('#capaAdd').addEventListener('click', function () { if (cur) capaForm(null); });
  $('#stBtn').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_claim_set_status', { p_token: token, p_id: cur.id, p_status: $('#stSel').value, p_resolution: $('#stNote').value.trim() })
      .then(function (r) { var x = r && r[0]; msg('#iMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { window.Auth.log('Претензия статус', $('#stSel').value); load().then(function () { openItem(cur.id); }); } })
      .catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#escBtn').addEventListener('click', function () {
    if (!cur) return;
    rpc('app_claim_escalate', { p_token: token, p_id: cur.id })
      .then(function (r) { var x = r && r[0]; msg('#iMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { window.Auth.log('Эскалация претензии', cur.number); if (window.AppNotify) window.AppNotify.refresh(true); load().then(function () { openItem(cur.id); }); } })
      .catch(function (e) { msg('#iMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#toNew').addEventListener('click', function () { clearMsg('#nMsg'); screens.go('s-new'); });
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
    var reason = $('#nReason').value.trim();
    if (!reason) { msg('#nMsg', 'Укажите причину.', 'err'); return; }
    var qv = parseFloat(($('#nQty').value || '').replace(',', '.'));
    rpc('app_claim_save', { p_token: token, p_id: null, p_customer: $('#nCustomer').value.trim(), p_product: $('#nProduct').value.trim(),
      p_reason: reason, p_qty: isNaN(qv) ? 1 : qv, p_severity: $('#nSeverity').value, p_description: $('#nDescription').value.trim(),
      p_assigned_login: $('#nAssignee').value.trim() })
      .then(function (d) { var row = d && d[0]; if (!row || !row.ok) { msg('#nMsg', row ? row.message : 'Ошибка', 'err'); return; }
        window.Auth.log('Претензия', reason); ['#nCustomer', '#nProduct', '#nReason', '#nQty', '#nDescription', '#nAssignee'].forEach(function (s) { $(s).value = ''; });
        load().then(function () { openItem(row.id); }); })
      .catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#listMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
