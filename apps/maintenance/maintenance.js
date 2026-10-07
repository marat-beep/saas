/* ============================================================
   3DMP Service · apps/maintenance — ТОиР (обслуживание и ремонт)
   Планы ТО/ППР, регистрация работ, история, KPI. Данные: 0052.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, plans = [], log = [], eq = [], pq = '', rq = '';

  var KINDS = { to1: 'ТО-1', to2: 'ТО-2', to3: 'ТО-3', ppr: 'ППР', repair: 'Ремонт', service: 'Сервис' };
  var STAT = { ok: 'в норме', due: 'истекает', overdue: 'просрочено', none: 'нет даты' };
  var SBADGE = { ok: 'done', due: 'in_progress', overdue: 'cancelled', none: '' };
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function money(v) { return num(v).toLocaleString('ru-RU', { maximumFractionDigits: 2 }) + ' ₽'; }
  function fmt(d) { if (!d) return '—'; var x = new Date(d); return isNaN(x.getTime()) ? String(d) : x.toLocaleDateString('ru-RU'); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_mnt_plans_list', { p_token: token, p_q: null }),
      rpc('app_mnt_log_list', { p_token: token, p_q: null }),
      rpc('app_mnt_kpi', { p_token: token }),
      rpc('app_equipment_list', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      plans = r[0] || []; log = r[1] || []; var k = (r[2] && r[2][0]) || {}; eq = r[3] || [];
      var eo = '<option value="">— выберите —</option>' + eq.map(function (e) { return '<option value="' + e.id + '">' + esc(e.name) + '</option>'; }).join('');
      $('#pEq').innerHTML = eo; $('#rEq').innerHTML = eo;
      $('#kpis').innerHTML = cell('Планов', num(k.plans_total)) + cell('Истекает (30 дн.)', num(k.due), k.due ? '#92400e' : '') +
        cell('Просрочено', num(k.overdue), k.overdue ? '#b91c1c' : '') + cell('Выполнено за месяц', num(k.done_month)) +
        cell('Затраты за месяц', money(k.cost_month));
      renderPlans(); renderLog();
    }).catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function cell(l, v, c) { return '<div class="kpi"><small>' + l + '</small><b' + (c ? ' style="color:' + c + '"' : '') + '>' + v + '</b></div>'; }

  function renderPlans() {
    var list = plans.filter(function (p) { if (!pq) return true; var s = pq.toLowerCase(); return [p.equipment, p.title, p.responsible].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#plansCnt').textContent = '(' + list.length + ')';
    $('#plans').innerHTML = list.length ? list.map(function (p) {
      var dl = p.days_left;
      var hint = dl == null ? '' : (dl < 0 ? 'просрочено ' + (-dl) + ' дн.' : 'через ' + dl + ' дн.');
      return '<div class="ocard"><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">' +
        '<span class="badge ' + (SBADGE[p.status] || '') + '">' + (STAT[p.status] || p.status) + '</span>' +
        '<span class="badge">' + (KINDS[p.kind] || p.kind) + '</span>' +
        '<b>' + esc(p.equipment || '—') + '</b>' +
        '<span class="note" style="margin-left:auto;">' + (p.title ? esc(p.title) + ' · ' : '') + 'след.: ' + fmt(p.next_due) + (hint ? ' (' + hint + ')' : '') + '</span></div>' +
        '<div style="font-size:.78rem;color:var(--muted);margin-top:5px;">' +
        (p.period_days ? 'период ' + p.period_days + ' дн. · ' : '') + (p.responsible ? '👤 ' + esc(p.responsible) + ' · ' : '') + 'последнее: ' + fmt(p.last_done) + '</div>' +
        '<div class="toolbar mt"><button class="btn secondary" data-reg="' + p.id + '" data-eq="' + (p.equipment_id || '') + '" data-kind="' + (p.kind || '') + '" style="width:auto;padding:8px 14px;">Зарегистрировать работу</button></div></div>';
    }).join('') : '<span class="note">Планов нет.</span>';
    $$('#plans [data-reg]').forEach(function (b) {
      b.addEventListener('click', function () {
        $('#rEq').value = b.dataset.eq || ''; $('#rKind').value = b.dataset.kind || 'to1';
        $('#rDate').value = new Date().toISOString().slice(0, 10);
        $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x.dataset.t === 'log'); });
        $('#t-plans').style.display = 'none'; $('#t-log').style.display = '';
        window.scrollTo(0, 0);
      });
    });
  }
  function renderLog() {
    var list = log.filter(function (l) { if (!rq) return true; var s = rq.toLowerCase(); return [l.equipment, l.works, l.executor].join(' ').toLowerCase().indexOf(s) >= 0; });
    $('#log').innerHTML = '<table class="tab" style="width:100%;border-collapse:collapse"><thead><tr><th>Дата</th><th>Оборудование</th><th>Вид</th><th>Работы</th><th>Заменено</th><th>Исполнитель</th><th>Стоимость</th></tr></thead><tbody>' +
      (list.length ? list.map(function (l) {
        return '<tr style="border-bottom:1px solid var(--border)"><td>' + fmt(l.work_date) + '</td><td><b>' + esc(l.equipment || '—') + '</b></td>' +
          '<td>' + (KINDS[l.kind] || l.kind || '') + '</td><td>' + esc(l.works || '') + '</td><td>' + esc(l.replaced || '') + '</td>' +
          '<td>' + esc(l.executor || '') + '</td><td>' + money(l.cost) + '</td></tr>';
      }).join('') : '<tr><td colspan="7"><span class="note">Записей нет.</span></td></tr>') + '</tbody></table>';
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    $('#t-plans').style.display = (b.dataset.t === 'plans') ? '' : 'none';
    $('#t-log').style.display = (b.dataset.t === 'log') ? '' : 'none';
  });
  $('#pq').addEventListener('input', function () { pq = this.value; renderPlans(); });
  $('#rQ').addEventListener('input', function () { rq = this.value; renderLog(); });

  $('#pAdd').addEventListener('click', function () {
    var eid = $('#pEq').value; if (!eid) { msg('#pMsg', 'Выберите оборудование.', 'err'); return; }
    var per = parseInt(($('#pPeriod').value || '').replace(',', '.'), 10);
    rpc('app_mnt_plan_save', { p_token: token, p_id: null, p_equipment_id: eid, p_kind: $('#pKind').value, p_title: $('#pTitle').value.trim(),
      p_period_days: isNaN(per) ? null : per, p_last_done: $('#pLast').value || null, p_next_due: null, p_responsible: $('#pResp').value.trim(), p_note: $('#pNote').value.trim() })
      .then(function (d) { var r = d && d[0]; msg('#pMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('План ТОиР', ''); ['#pTitle', '#pPeriod', '#pLast', '#pResp', '#pNote'].forEach(function (s) { $(s).value = ''; }); load(); } })
      .catch(function (e) { msg('#pMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#rAdd').addEventListener('click', function () {
    var eid = $('#rEq').value; if (!eid) { msg('#rMsg', 'Выберите оборудование.', 'err'); return; }
    var cost = parseFloat(($('#rCost').value || '').replace(',', '.'));
    rpc('app_mnt_register', { p_token: token, p_plan_id: null, p_equipment_id: eid, p_kind: $('#rKind').value, p_date: $('#rDate').value || null,
      p_executor: $('#rExec').value.trim(), p_cost: isNaN(cost) ? 0 : cost, p_works: $('#rWorks').value.trim(), p_replaced: $('#rRepl').value.trim(), p_note: null })
      .then(function (d) { var r = d && d[0]; msg('#rMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { window.Auth.log('ТОиР работа', $('#rWorks').value.trim()); if (window.AppNotify) window.AppNotify.refresh(true); ['#rExec', '#rCost', '#rWorks', '#rRepl'].forEach(function (s) { $(s).value = ''; }); load(); } })
      .catch(function (e) { msg('#rMsg', 'Ошибка: ' + e.message, 'err'); });
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#pMsg', 'Supabase не подключён.', 'err'); return; }
    load(); renderRuntime();
  });

  function renderRuntime() {
    rpc('app_mnt_runtime_status', { p_token: token }).then(function (list) {
      list = list || [];
      if (!list.length) { $('#runtime').innerHTML = '<span class="note">Планов нет.</span>'; return; }
      var pad = { ok: 'в норме', soon: 'скоро', overdue: 'просрочено' };
      var bdg = { ok: 'done', soon: 'in_progress', overdue: 'cancelled' };
      $('#runtime').innerHTML = '<table class="tab2" style="width:100%;border-collapse:collapse"><thead><tr><th>Оборудование</th><th>Вид</th><th>Период, дн</th><th>Наработка, ч</th><th>Норма, ч</th><th>%</th><th>Следующее ТО</th><th>Статус</th></tr></thead><tbody>' +
        list.map(function (r) {
          return '<tr><td>' + esc(r.equipment) + '</td><td>' + esc(r.kind || '') + '</td><td>' + num(r.period_days) + '</td>' +
            '<td>' + num(r.run_hours) + '</td><td>' + num(r.due_hours) + '</td><td>' + (r.pct != null ? r.pct + '%' : '—') + '</td>' +
            '<td>' + fmt(r.next_due) + '</td><td><span class="badge ' + (bdg[r.status] || '') + '">' + (pad[r.status] || r.status) + '</span></td></tr>';
        }).join('') + '</tbody></table>';
    }).catch(function () { $('#runtime').innerHTML = '<span class="note">Недоступно.</span>'; });
  }
})();
