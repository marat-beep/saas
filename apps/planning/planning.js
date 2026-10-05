/* ============================================================
   3DMP Service · apps/planning — Гант и загрузка центров
   Данные: app_schedule, app_capacity, app_naryad_schedule (0011). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, sched = [], cap = [];

  function esc(v) { return ui.esc(v); }
  function num(v) { return (Number(v) || 0); }
  function d(s) { return s ? new Date(s) : null; }
  function days(a, b) { return Math.round((d(b) - d(a)) / 86400000); }
  function dd(s) { var x = d(s); return x && !isNaN(x) ? x.toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit' }) : '—'; }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg(id) { var e = $(id); e.className = 'msg'; e.textContent = ''; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function load() {
    return Promise.all([
      rpc('app_schedule', { p_token: token }).catch(function () { return []; }),
      rpc('app_capacity', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) { sched = r[0] || []; cap = r[1] || []; renderGantt(); renderCap(); renderSched(); })
      .catch(function (e) { msg('#gMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  function renderGantt() {
    var items = sched.filter(function (n) { return n.plan_start && n.plan_end; });
    if (!items.length) { $('#gantt').innerHTML = '<span class="note">Нет нарядов с план-датами.</span>'; $('#scaleDates').textContent = ''; return; }
    var min = items[0].plan_start, max = items[0].plan_end;
    items.forEach(function (n) { if (n.plan_start < min) min = n.plan_start; if (n.plan_end > max) max = n.plan_end; });
    var total = days(min, max) + 1;
    $('#scaleDates').textContent = dd(min) + ' — ' + dd(max) + ' (' + total + ' дн.)';
    $('#gantt').innerHTML = items.map(function (n) {
      var left = days(min, n.plan_start) / total * 100;
      var width = (days(n.plan_start, n.plan_end) + 1) / total * 100;
      var label = esc(n.number) + ' · ' + esc(n.title) + (n.wc_name ? ' (' + esc(n.wc_name) + ')' : '');
      return '<div class="grow"><div title="' + label + '" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">' + esc(n.number) + ' · ' + esc(n.title) + '</div>' +
        '<div class="track"><div class="bar ' + n.status + '" style="left:' + left.toFixed(2) + '%;width:' + Math.max(width, 1.5).toFixed(2) + '%;" title="' + dd(n.plan_start) + ' — ' + dd(n.plan_end) + '"></div></div></div>';
    }).join('');
  }

  function renderCap() {
    if (!cap.length) { $('#cap').innerHTML = '<span class="note">Рабочих центров нет.</span>'; return; }
    var maxh = Math.max.apply(null, cap.map(function (c) { return num(c.plan_hours) || 0; }).concat([1]));
    $('#cap').innerHTML = cap.map(function (c) {
      var pct = num(c.plan_hours) / maxh * 100;
      return '<div class="barrow"><div><b>' + esc(c.wc_name) + '</b>' +
        (c.kind ? ' <span class="note">' + esc(c.kind) + '</span>' : '') +
        ' <span class="note">· ' + c.active_naryads + ' наряд(ов) · ' + num(c.plan_hours) + ' н/ч · ' + num(c.cost_hour) + ' ₽/ч</span></div>' +
        '<div class="capwrap"><div class="capbar" style="width:' + pct.toFixed(1) + '%;"></div></div></div>';
    }).join('');
  }

  function renderSched() {
    if (!sched.length) { $('#sched').innerHTML = '<span class="note">Нарядов нет.</span>'; return; }
    $('#sched').innerHTML = sched.map(function (n) {
      return '<div class="sched" data-id="' + n.id + '">' +
        '<div>' + esc(n.number) + ' · ' + esc(n.title) + '</div>' +
        '<input type="date" data-k="s" value="' + (n.plan_start || '') + '">' +
        '<input type="date" data-k="e" value="' + (n.plan_end || '') + '">' +
        '<button class="btn secondary" data-save="' + n.id + '" style="width:auto;padding:7px 10px;">✓</button></div>';
    }).join('');
    $$('#sched [data-save]').forEach(function (b) {
      b.addEventListener('click', function () {
        var row = b.closest('.sched');
        var s = row.querySelector('[data-k="s"]').value || null;
        var e = row.querySelector('[data-k="e"]').value || null;
        rpc('app_naryad_schedule', { p_token: token, p_id: b.dataset.save, p_start: s, p_end: e })
          .then(function () { window.Auth.log('План наряда', b.dataset.save); ui.toast('Сроки сохранены'); load(); })
          .catch(function (err) { msg('#gMsg', 'Ошибка: ' + err.message, 'err'); });
      });
    });
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    $('#t-gantt').style.display = (b.dataset.t === 'gantt') ? '' : 'none';
    $('#t-cap').style.display = (b.dataset.t === 'cap') ? '' : 'none';
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#gMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
