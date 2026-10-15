/* ============================================================
   3DMP Service · apps/planning/scn.js — X12: сценарии планирования,
   переналадки и зависимости Ганта. Требует planning.js (window.AppPlanning),
   ui.js (AppUI). API: app_plan_scenario_*, app_changeover_*, app_plan_dep*.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  function esc(v) { return ui.esc(v); }
  function num(v) { return Number(v) || 0; }
  function dd(s) { if (!s) return '—'; var x = new Date(s); return isNaN(x) ? '—' : x.toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit' }); }
  function today() { return new Date().toISOString().slice(0, 10); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function token() { var p = window.AppPlanning; return p && p.getToken ? p.getToken() : null; }
  function naryads() { var p = window.AppPlanning; return (p && p.getSched) ? (p.getSched() || []) : []; }
  function toast(t, k) { ui.toast(t, k); }

  function load() {
    var t = token(); if (!t) return;
    Promise.all([
      rpc('app_plan_scenario_list', { p_token: t }).catch(function () { return []; }),
      rpc('app_changeover_list', { p_token: t, p_q: null }).catch(function () { return []; }),
      rpc('app_plan_deps_list', { p_token: t }).catch(function () { return []; })
    ]).then(function (r) { renderScn(r[0] || []); renderCo(r[1] || []); renderDep(r[2] || []); })
      .catch(function (e) { $('#scnMsg').textContent = 'Ошибка: ' + e.message; });
  }

  function renderScn(list) {
    $('#scnList').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Название</th><th>Старт</th><th class="num">Дней</th><th>Создан</th><th>Действия</th></tr></thead><tbody>' +
      list.map(function (s) {
        return '<tr><td><b>' + esc(s.name) + '</b>' + (s.note ? ' <span class="note">' + esc(s.note) + '</span>' : '') + '</td><td>' + dd(s.from_date) + '</td><td class="num">' + s.days + '</td><td class="muted">' + dd(s.created_at) + '</td>' +
          '<td><button class="act" data-run="' + s.id + '">Построить</button> <button class="act" data-apply="' + s.id + '" data-from="' + s.from_date + '" data-days="' + s.days + '">Применить</button> <button class="act" data-del="' + s.id + '" aria-label="Удалить" title="Удалить">✕</button></td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Сценариев нет. Сохраните текущие параметры APS как сценарий.</span>';
    $$('#scnList [data-run]').forEach(function (b) { b.addEventListener('click', function () { run(b.dataset.run); }); });
    $$('#scnList [data-apply]').forEach(function (b) { b.addEventListener('click', function () {
      rpc('app_aps_apply', { p_token: token(), p_from: b.dataset.from, p_days: parseInt(b.dataset.days, 10) || 14 })
        .then(function (r) { var x = r && r[0]; toast((x && x.message) || 'Применено'); if (window.AppPlanning && window.AppPlanning.reload) window.AppPlanning.reload(); })
        .catch(function (e) { toast('Ошибка: ' + e.message, 'err'); });
    }); });
    $$('#scnList [data-del]').forEach(function (b) { b.addEventListener('click', function () {
      if (!window.confirm('Удалить сценарий?')) return;
      rpc('app_plan_scenario_delete', { p_token: token(), p_id: b.dataset.del }).then(function () { toast('Удалено'); load(); });
    }); });
  }
  function run(id) {
    $('#scnOut').innerHTML = '<span class="note">Построение…</span>';
    rpc('app_plan_scenario_run', { p_token: token(), p_id: id }).then(function (rows) {
      rows = rows || [];
      $('#scnOut').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Наряд</th><th>Название</th><th class="num">Остаток,ч</th><th>Начало</th><th>Окончание</th><th>Срок</th><th>Риск</th></tr></thead><tbody>' +
        rows.map(function (n) { return '<tr><td>' + esc(n.number) + '</td><td>' + esc(n.title || '') + '</td><td class="num">' + num(n.remaining) + '</td><td>' + dd(n.plan_start) + '</td><td>' + dd(n.plan_end) + '</td><td>' + dd(n.due_date) + '</td><td style="' + (n.risk === 'риск' ? 'color:#b91c1c;font-weight:700;' : '') + '">' + esc(n.risk || '—') + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Нет открытых нарядов.</span>';
    }).catch(function (e) { $('#scnOut').innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
  }

  function renderCo(list) {
    $('#coList').innerHTML = list.length ? '<table class="mini"><thead><tr><th>Из семейства</th><th>В семейство</th><th class="num">Мин</th><th></th></tr></thead><tbody>' +
      list.map(function (c) { return '<tr><td>' + esc(c.from_family || '—') + '</td><td>' + esc(c.to_family) + '</td><td class="num">' + num(c.minutes) + '</td><td><button class="act" data-codel="' + c.id + '" aria-label="Удалить" title="Удалить">✕</button></td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Переналадки не заданы (0 мин по умолчанию).</span>';
    $$('#coList [data-codel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_changeover_delete', { p_token: token(), p_id: b.dataset.codel }).then(function () { toast('Удалено'); load(); }); }); });
  }

  function renderDep(list) {
    $('#depList').innerHTML = list.length ? '<table class="mini"><thead><tr><th>Наряд</th><th>После</th><th class="num">Лаг, дн</th><th></th></tr></thead><tbody>' +
      list.map(function (d) { return '<tr><td>' + esc(d.naryad) + '</td><td>' + esc(d.pred) + '</td><td class="num">' + d.lag_days + '</td><td><button class="act" data-ddel="' + d.id + '" aria-label="Удалить" title="Удалить">✕</button></td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Зависимостей нет.</span>';
    $$('#depList [data-ddel]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_plan_dep_delete', { p_token: token(), p_id: b.dataset.ddel }).then(function () { toast('Удалено'); load(); }); }); });
  }

  function check() {
    rpc('app_plan_deps_check', { p_token: token() }).then(function (rows) {
      rows = rows || [];
      var bad = rows.filter(function (r) { return r.violation; });
      $('#depCheck').innerHTML = rows.length ? '<div class="note" style="margin:6px 0;">Нарушений: <b style="color:' + (bad.length ? '#b91c1c' : '#10b981') + '">' + bad.length + '</b> из ' + rows.length + '</div><table class="mini"><thead><tr><th>Наряд</th><th>После</th><th class="num">Лаг</th><th>Конец пред.</th><th>Старт</th><th>Ожид. старт</th><th></th></tr></thead><tbody>' +
        rows.map(function (r) { return '<tr><td>' + esc(r.naryad) + '</td><td>' + esc(r.pred) + '</td><td class="num">' + r.lag_days + '</td><td>' + dd(r.pred_end) + '</td><td>' + dd(r.plan_start) + '</td><td>' + dd(r.expected_start) + '</td><td>' + (r.violation ? '<span class="badge cancelled">нарушение</span>' : '<span class="badge done">ок</span>') + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Зависимостей нет.</span>';
    }).catch(function (e) { $('#depCheck').innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
  }

  function naryadOptions() {
    return naryads().map(function (n) { return { value: n.id, label: n.number + ' · ' + (n.title || '') }; });
  }

  $('#scnAdd').addEventListener('click', function () {
    ui.formDialog({ title: 'Новый сценарий APS', okText: 'Сохранить', fields: [
      { name: 'name', label: 'Название', required: true, value: 'Сценарий ' + today() },
      { name: 'from', label: 'Старт', type: 'date', value: today() },
      { name: 'days', label: 'Горизонт, дней', type: 'number', value: 14 },
      { name: 'note', label: 'Примечание' }
    ] }).then(function (v) {
      if (!v) return;
      rpc('app_plan_scenario_save', { p_token: token(), p_id: null, p_name: v.name, p_from: v.from, p_days: parseInt(v.days, 10) || 14, p_note: v.note })
        .then(function (r) { var x = r && r[0]; toast((x && x.message) || '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) load(); });
    });
  });
  $('#coAdd').addEventListener('click', function () {
    ui.formDialog({ title: 'Норма переналадки', okText: 'Сохранить', fields: [
      { name: 'from', label: 'Из семейства (пусто = любое)', value: '' },
      { name: 'to', label: 'В семейство', required: true, value: '' },
      { name: 'minutes', label: 'Минут', type: 'number', value: 30 },
      { name: 'note', label: 'Примечание' }
    ] }).then(function (v) {
      if (!v) return;
      rpc('app_changeover_save', { p_token: token(), p_id: null, p_from: v.from, p_to: v.to, p_minutes: Number(v.minutes) || 0, p_note: v.note })
        .then(function (r) { var x = r && r[0]; toast((x && x.message) || '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) load(); });
    });
  });
  $('#depAdd').addEventListener('click', function () {
    var opts = naryadOptions();
    if (opts.length < 2) { toast('Нужно минимум два наряда'); return; }
    ui.formDialog({ title: 'Зависимость наряда', okText: 'Сохранить', fields: [
      { name: 'naryad', label: 'Наряд', type: 'select', required: true, options: opts },
      { name: 'pred', label: 'Начинать после', type: 'select', required: true, options: opts },
      { name: 'lag', label: 'Лаг, дней', type: 'number', value: 0 },
      { name: 'note', label: 'Примечание' }
    ] }).then(function (v) {
      if (!v) return;
      rpc('app_plan_dep_save', { p_token: token(), p_id: null, p_naryad_id: v.naryad, p_pred_id: v.pred, p_lag: parseInt(v.lag, 10) || 0, p_note: v.note })
        .then(function (r) { var x = r && r[0]; toast((x && x.message) || '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) load(); });
    });
  });
  $('#depCheckBtn').addEventListener('click', check);

  window.AppPlanningScn = { load: load };
})();
