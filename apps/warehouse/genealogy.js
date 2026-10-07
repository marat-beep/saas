/* ============================================================
   3DMP Service · apps/warehouse/genealogy.js — R3: генеалогия партий (0157).
   Партия → движение → наряд → паспорт.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB, token = null, lots = [];
  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function msg(t, k) { var e = $('#genMsg'); if (!e) return; e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function dt(v) { return v ? new Date(v).toLocaleString('ru-RU') : '—'; }

  function fill() {
    return rpc('app_lot_list', { p_token: token, p_material_id: null }).then(function (r) {
      lots = r || [];
      $('#genLot').innerHTML = lots.length ? lots.map(function (l) { return '<option value="' + l.id + '">' + esc(l.lot + ' · ' + (l.material || '')) + '</option>'; }).join('') : '<option value="">— партий нет —</option>';
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  function show() {
    var id = $('#genLot').value; if (!id) { msg('Нет партий.', 'err'); return; }
    msg('Загрузка…', 'info');
    Promise.all([
      rpc('app_lot_genealogy', { p_token: token, p_lot_id: id }),
      rpc('app_lot_trace_list', { p_token: token, p_lot_id: id })
    ]).then(function (r) {
      var chain = r[0] || [], trace = r[1] || [];
      $('#genChain').innerHTML = chain.length ? '<table class="mini"><thead><tr><th>Этап</th><th>Ссылка</th><th>Детали</th><th class="num">Кол-во</th><th>Когда</th></tr></thead><tbody>' +
        chain.map(function (x) { return '<tr><td><b>' + esc(x.stage) + '</b></td><td>' + esc(x.ref || '') + '</td><td class="muted">' + esc(x.detail || '') + '</td><td class="num">' + (x.qty != null ? x.qty : '—') + '</td><td class="muted">' + dt(x.at) + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Данных нет.</span>';
      $('#genTrace').innerHTML = trace.length ? '<table class="mini"><thead><tr><th>Наряд</th><th>Паспорт</th><th class="num">Кол-во</th><th>Примечание</th><th>Когда</th></tr></thead><tbody>' +
        trace.map(function (x) { return '<tr><td>' + esc(x.naryad_number || '—') + '</td><td>' + esc(x.passport_number || '—') + '</td><td class="num">' + (x.qty != null ? x.qty : '—') + '</td><td class="muted">' + esc(x.note || '') + '</td><td class="muted">' + dt(x.created_at) + '</td></tr>'; }).join('') + '</tbody></table>' : '<span class="note">Связей нет.</span>';
      msg('Этапов: ' + chain.length + ' · связей: ' + trace.length, 'ok');
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    token = s.token;
    if (!SB) return;
    fill();
    $('#genBtn').addEventListener('click', show);
    $('#genLot').addEventListener('change', show);
  });
})();
