/* ============================================================
   3DMP Service · apps/forecast — прогноз загрузки + аналитика L4 (W8).
   Данные: 0076 (загрузка) + 0153 (спрос/риски) + app_mnt_runtime_status (ТОиР).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null;

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function d(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }
  function money(v) { return (Number(v) || 0).toLocaleString('ru-RU') + ' ₽'; }
  function monthLabel(dt) { var x = new Date(dt); return isNaN(x.getTime()) ? '—' : x.toLocaleDateString('ru-RU', { month: 'short', year: '2-digit' }); }

  /* ---------- Вкладки ---------- */
  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'demand' && !demandLoaded) loadDemand();
    if (scr === 'risks' && !risksLoaded) loadRisks();
    if (scr === 'mnt' && !mntLoaded) loadMnt();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  /* ---------- Загрузка (0076) ---------- */
  function loadKpi() {
    return rpc('app_forecast_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('Открытых нарядов', k.open_naryads || 0) + cell('Остаток часов', k.open_hours || 0) + cell('Мощность/день, ч', k.avg_daily_capacity || 0) + cell('Загрузка (14 дн)', (k.avg_load_pct || 0) + '%') + cell('Просрочено', k.overdue || 0);
    });
  }
  function loadLoad() {
    var days = parseInt($('#days').value, 10) || 14;
    return rpc('app_forecast_load', { p_token: token, p_days: days }).then(function (r) {
      var rows = r || [];
      $('#load').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Дата</th><th class="num">План, ч</th><th class="num">Мощность, ч</th><th>Загрузка</th></tr></thead><tbody>' +
        rows.map(function (x) {
          var pct = x.load_pct || 0, cls = pct > 100 ? 'over' : (pct > 85 ? 'warn' : '');
          return '<tr><td>' + esc(x.day) + '</td><td class="num">' + x.planned + '</td><td class="num">' + x.capacity + '</td>' +
            '<td style="min-width:140px;"><div class="bar"><i class="' + cls + '" style="width:' + Math.min(pct, 100) + '%"></i></div><span class="note">' + pct + '%</span></td></tr>';
        }).join('') + '</tbody></table>' : '<span class="note">Нет данных.</span>';
    }).catch(function (e) { msg('#lMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function loadOrders() {
    return rpc('app_forecast_orders', { p_token: token, p_limit: 100 }).then(function (r) {
      var rows = r || [];
      $('#cnt').textContent = '(' + rows.length + ')';
      $('#orders').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Наряд</th><th>Название</th><th>Центр</th><th>Заказ</th><th class="num">Остаток, ч</th><th class="num">ETA, дн</th><th>ETA</th><th>Срок</th><th>Риск</th></tr></thead><tbody>' +
        rows.map(function (o) {
          return '<tr><td>' + esc(o.number || '') + '</td><td>' + esc(o.title || '') + '</td><td>' + esc(o.center || '') + '</td><td>' + esc(o.order_number || '') + '</td>' +
            '<td class="num">' + o.remaining + '</td><td class="num">' + o.eta_days + '</td><td>' + d(o.eta_date) + '</td><td>' + d(o.due_date) + '</td>' +
            '<td class="risk-' + esc(o.risk) + '">' + esc(o.risk) + '</td></tr>';
        }).join('') + '</tbody></table>' : '<span class="note">Открытых нарядов нет.</span>';
    });
  }
  function refresh() { loadKpi(); loadLoad(); loadOrders(); }

  /* ---------- Спрос и прогноз (0153) ---------- */
  var demandLoaded = false;
  function linreg(vals) {
    var n = vals.length; if (n < 2) return { a: vals[0] || 0, b: 0 };
    var sx = 0, sy = 0, sxx = 0, sxy = 0;
    vals.forEach(function (y, x) { sx += x; sy += y; sxx += x * x; sxy += x * y; });
    var denom = n * sxx - sx * sx;
    var b = denom ? (n * sxy - sx * sy) / denom : 0;
    var a = (sy - b * sx) / n;
    return { a: a, b: b };
  }
  function loadDemand() {
    demandLoaded = true;
    var months = parseInt($('#months').value, 10) || 12;
    msg('#dMsg', 'Загрузка…', 'info');
    return rpc('app_forecast_demand', { p_token: token, p_months: months }).then(function (r) {
      var rows = r || [];
      var orders = rows.map(function (x) { return Number(x.orders) || 0; });
      var labels = rows.map(function (x) { return monthLabel(x.month); });
      var lr = linreg(orders);
      var proj = [], projLabels = [];
      for (var i = orders.length; i < orders.length + 3; i++) {
        proj.push(Math.max(0, Math.round(lr.a + lr.b * i)));
        var dd = new Date(rows.length ? new Date(rows[rows.length - 1].month) : new Date());
        dd.setMonth(dd.getMonth() + (i - orders.length + 1));
        projLabels.push(monthLabel(dd));
      }
      $('#demandChart').innerHTML = svgDemand(orders.concat(proj), labels.concat(projLabels), orders.length);
      var totalOrders = orders.reduce(function (s, v) { return s + v; }, 0);
      var totalRev = rows.reduce(function (s, x) { return s + (Number(x.revenue) || 0); }, 0);
      msg('#dMsg', 'Всего заявок за период: ' + totalOrders + ' · выручка: ' + money(totalRev) + ' · прогноз (3 мес): ' + proj.join(', '), 'ok');
      $('#demandTable').innerHTML = '<table class="mini"><thead><tr><th>Месяц</th><th class="num">Заявки</th><th class="num">Выручка</th><th>Прогноз</th></tr></thead><tbody>' +
        rows.map(function (x, i) {
          return '<tr><td>' + esc(monthLabel(x.month)) + '</td><td class="num">' + (x.orders || 0) + '</td><td class="num">' + money(x.revenue) + '</td><td class="muted">—</td></tr>';
        }).join('') + proj.map(function (v, i) {
          return '<tr style="background:#f8fafc;"><td><i>' + esc(projLabels[i]) + '</i></td><td class="num muted">—</td><td class="num muted">—</td><td class="num"><b>' + v + '</b></td></tr>';
        }).join('') + '</tbody></table>';
    }).catch(function (e) { msg('#dMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function svgDemand(vals, labels, realCount) {
    if (!vals.length) return '<span class="note">Нет данных.</span>';
    var w = 760, h = 260, padL = 36, padR = 12, padT = 14, padB = 46;
    var max = Math.max.apply(null, vals) || 1;
    var bw = (w - padL - padR) / vals.length;
    var bars = vals.map(function (v, i) {
      var bh = (v / max) * (h - padT - padB);
      var x = padL + i * bw + bw * 0.15, bwid = bw * 0.7;
      var proj = i >= realCount;
      var y = h - padB - bh;
      return '<rect x="' + x.toFixed(1) + '" y="' + y.toFixed(1) + '" width="' + bwid.toFixed(1) + '" height="' + bh.toFixed(1) + '" rx="3" fill="' + (proj ? '#a7f3d0' : '#10b981') + '"><title>' + esc(labels[i]) + ': ' + v + '</title></rect>' +
        '<text x="' + (x + bwid / 2).toFixed(1) + '" y="' + (y - 4).toFixed(1) + '" font-size="10" text-anchor="middle" fill="#334155">' + v + '</text>' +
        '<text x="' + (x + bwid / 2).toFixed(1) + '" y="' + (h - padB + 14) + '" font-size="9" text-anchor="middle" fill="#64748b">' + esc(labels[i]) + '</text>';
    }).join('');
    return '<svg class="fc-chart" viewBox="0 0 ' + w + ' ' + h + '" role="img" aria-label="Прогноз спроса">' +
      '<line x1="' + padL + '" y1="' + (h - padB) + '" x2="' + (w - padR) + '" y2="' + (h - padB) + '" stroke="#cbd5e1"/>' +
      bars + '</svg>' +
      '<div class="note" style="display:flex;gap:16px;margin-top:6px;"><span><span style="display:inline-block;width:12px;height:12px;background:#10b981;border-radius:3px;"></span> факт</span>' +
      '<span><span style="display:inline-block;width:12px;height:12px;background:#a7f3d0;border-radius:3px;"></span> прогноз</span></div>';
  }

  /* ---------- Риски по срокам (0153) ---------- */
  var risksLoaded = false;
  function loadRisks() {
    risksLoaded = true;
    return rpc('app_forecast_risks', { p_token: token, p_limit: 100 }).then(function (r) {
      var rows = r || [];
      $('#risks').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Заявка</th><th>Тема</th><th>Заказчик</th><th class="num">Сумма</th><th>Срок</th><th class="num">Дней</th><th>Статус</th><th>Риск</th></tr></thead><tbody>' +
        rows.map(function (o) {
          return '<tr><td>' + esc(o.number || '') + '</td><td>' + esc(o.title || '') + '</td><td>' + esc(o.customer || '') + '</td>' +
            '<td class="num">' + money(o.amount) + '</td><td>' + d(o.due_date) + '</td><td class="num">' + o.days_left + '</td><td>' + esc(o.status) + '</td>' +
            '<td class="risk-' + esc(o.risk) + '">' + esc(o.risk) + '</td></tr>';
        }).join('') + '</tbody></table>' : '<span class="note">Заявок с риском по срокам нет.</span>';
      msg('#rMsg', 'Заявок в риске: ' + rows.filter(function (o) { return o.risk !== 'норма'; }).length, 'ok');
    }).catch(function (e) { msg('#rMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Предиктив ТОиР ---------- */
  var mntLoaded = false;
  function loadMnt() {
    mntLoaded = true;
    return rpc('app_mnt_runtime_status', { p_token: token }).then(function (r) {
      var rows = r || [];
      $('#mnt').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Оборудование</th><th>Вид ТО</th><th>Период, дн</th><th class="num">Наработка, ч</th><th class="num">До ТО, ч</th><th>Осталось</th><th>Следующее</th><th>Статус</th></tr></thead><tbody>' +
        rows.map(function (o) {
          var pct = Number(o.pct) || 0, cls = pct >= 100 ? 'over' : (pct >= 85 ? 'warn' : '');
          return '<tr><td><b>' + esc(o.equipment || '—') + '</b></td><td>' + esc(o.kind || '') + '</td><td class="num">' + (o.period_days || '—') + '</td>' +
            '<td class="num">' + (o.run_hours != null ? o.run_hours : '—') + '</td><td class="num">' + (o.due_hours != null ? o.due_hours : '—') + '</td>' +
            '<td style="min-width:130px;"><div class="bar"><i class="' + cls + '" style="width:' + Math.min(pct, 100) + '%"></i></div><span class="note">' + pct + '%</span></td>' +
            '<td>' + d(o.next_due) + '</td><td>' + esc(o.status || '') + '</td></tr>';
        }).join('') + '</tbody></table>' : '<span class="note">Планы ТОиР не заданы.</span>';
      msg('#mMsg', 'Позиций ТОиР: ' + rows.length, 'ok');
    }).catch(function (e) { msg('#mMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  $('#refresh').addEventListener('click', refresh);
  $('#demandBtn').addEventListener('click', loadDemand);
  $('#risksBtn').addEventListener('click', loadRisks);
  $('#mntBtn').addEventListener('click', loadMnt);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#lMsg', 'Supabase не подключён.', 'err'); return; }
    refresh();
  });
})();
