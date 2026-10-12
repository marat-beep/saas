/* ============================================================
   3DMP Service · apps/assistant — ИИ-помощник (база знаний + подбор)
   Данные: app_kb_*, app_tech_* (0023_assistant.sql). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, kb = [], mats = [], acIdx = -1;
  var GRP = { steel: 'Констр. сталь', tool_steel: 'Инстр. сталь', stainless: 'Нержавеющая', bearing: 'Подшипниковая', aluminum: 'Алюминий', bronze: 'Бронза', brass: 'Латунь', copper: 'Медь', cast_iron: 'Чугун', plastic: 'Пластик', titanium: 'Титан', copper_alloy: 'Медь/латунь' };

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function loadKb() {
    return rpc('app_kb_list', { p_token: token }).then(function (d) { kb = d || []; renderKb(); })
      .catch(function (e) { $('#kb').innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
  }
  function renderKb() {
    $('#kb').innerHTML = kb.length ? kb.map(function (k) {
      return '<div class="ans"><span class="cat">' + esc(k.category || 'Без категории') + '</span>' +
        '<h4>' + esc(k.question) + '</h4><p>' + esc(k.answer) + '</p>' +
        (k.tags ? '<div class="note" style="font-size:.72rem;margin-top:5px;"># ' + esc(k.tags) + '</div>' : '') + '</div>';
    }).join('') : '<span class="note">База знаний пуста.</span>';
  }

  function ask() {
    var q = $('#q').value.trim();
    if (!q) { $('#results').innerHTML = '<span class="note">Введите вопрос.</span>'; return; }
    $('#results').innerHTML = '<span class="note">Поиск…</span>';
    rpc('app_kb_search', { p_token: token, p_query: q }).then(function (list) {
      list = list || [];
      if (!list.length) { $('#results').innerHTML = '<div class="ans"><p>Ничего не найдено. Попробуйте другие слова или добавьте запись в базу знаний.</p></div>'; return; }
      $('#results').innerHTML = list.map(function (k) {
        return '<div class="ans"><span class="cat">' + esc(k.category || 'База знаний') + '</span>' +
          '<h4>' + esc(k.question) + '</h4><p>' + esc(k.answer) + '</p></div>';
      }).join('');
      window.Auth.log('Помощник: запрос', q);
    }).catch(function (e) { $('#results').innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
  }

  function recommend() {
    var mat = $('#rMat').value.trim();
    if (!mat) { $('#rec').innerHTML = '<span class="note">Укажите материал.</span>'; return; }
    rpc('app_tech_recommend', { p_token: token, p_material: mat, p_feature: $('#rFeat').value }).then(function (list) {
      list = list || [];
      if (!list.length) { $('#rec').innerHTML = '<div class="rec"><b>Нет точного правила</b><div class="note">Уточните материал/признак или добавьте правило.</div></div>'; return; }
      $('#rec').innerHTML = list.map(function (r) {
        return '<div class="rec"><b>' + esc(r.recommendation) + '</b>' +
          (r.note ? '<div class="note" style="margin-top:3px;">' + esc(r.note) + '</div>' : '') +
          '<div class="note" style="font-size:.7rem;margin-top:4px;">' + esc(r.matched_material || '*') + ' · ' + esc(r.matched_feature || '*') + '</div></div>';
      }).join('');
      window.Auth.log('Помощник: подбор', mat + '/' + $('#rFeat').value);
    }).catch(function (e) { $('#rec').innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
  }

  function renderCutting(rows) {
    var host = document.getElementById('cutRes'); if (!host) return;
    rows = rows || [];
    if (!rows.length) { host.innerHTML = '<div class="ans"><p>Режимы не найдены. Уточните материал/операцию (напр. «сталь фрезерование»).</p></div>'; return; }
    host.innerHTML = '<div class="ans"><b>📐 Режимы резания (' + rows.length + ')</b>' +
      '<div style="overflow:auto;margin-top:8px;"><table class="mini"><thead><tr><th>Материал</th><th>Операция</th><th>Инструмент</th><th class="num">Vc</th><th class="num">Подача</th><th class="num">ap</th><th>СОЖ</th></tr></thead><tbody>' +
      rows.map(function (r) {
        return '<tr><td>' + esc(GRP[r.material_group] || r.material_group || '') + '</td><td><b>' + esc(r.operation || '') + '</b></td>' +
          '<td>' + esc((r.tool_type || '') + (r.tool_material ? ' · ' + r.tool_material : '')) + '</td>' +
          '<td class="num">' + (r.vc == null ? '—' : r.vc) + '</td><td class="num">' + (r.feed == null ? '—' : r.feed) + '</td>' +
          '<td class="num">' + (r.ap == null ? '—' : r.ap) + '</td><td>' + esc(r.cooling || '') + '</td></tr>';
      }).join('') + '</tbody></table></div><div class="note" style="margin-top:6px;">Источник: справочник режимов резания (реестр «Справочники»).</div></div>';
    window.Auth.log('Помощник: режимы', ($('#q').value || ''));
  }

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    $('#t-ask').style.display = (b.dataset.t === 'ask') ? '' : 'none';
    $('#t-kb').style.display = (b.dataset.t === 'kb') ? '' : 'none';
  });
  $('#askBtn').addEventListener('click', ask);
  $('#q').addEventListener('keydown', function (e) { if (e.key === 'Enter') ask(); });
  $('#cutBtn').addEventListener('click', function () {
    var v = $('#q').value.trim();
    if (!v) { $('#cutRes').innerHTML = '<span class="note">Введите материал и/или операцию.</span>'; return; }
    $('#cutRes').innerHTML = '<span class="note">Подбор режимов…</span>';
    rpc('app_ref_cutting_find', { p_token: token, p_material: v, p_operation: null, p_limit: 30 })
      .then(renderCutting).catch(function (e) { $('#cutRes').innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
  });
  $('#toPick').addEventListener('click', function () {
    var v = $('#q').value.trim(), inp = document.getElementById('rMat');
    if (v && inp) { inp.value = v; acIdx = -1; acRender(); inp.focus(); inp.scrollIntoView({ behavior: 'smooth', block: 'center' }); }
    ui.toast('Запрос перенесён в «Подбор технологии»');
  });
  var _chips = document.getElementById('qChips');
  if (_chips) _chips.addEventListener('click', function (e) { var b = e.target.closest('.chip'); if (!b) return; $('#q').value = b.dataset.q; ask(); });
  $('#recBtn').addEventListener('click', recommend);
  $('#kAdd').addEventListener('click', function () {
    var q = $('#kQ').value.trim(), a = $('#kA').value.trim();
    if (!q || !a) { msg('#kMsg', 'Заполните вопрос и ответ.', 'err'); return; }
    rpc('app_kb_add', { p_token: token, p_category: $('#kCat').value.trim(), p_question: q, p_answer: a, p_tags: $('#kTags').value.trim() })
      .then(function (d) { var r = d && d[0]; msg('#kMsg', (r && r.message) || '', r && r.ok ? 'ok' : 'err'); if (r && r.ok) { ['#kCat', '#kQ', '#kA', '#kTags'].forEach(function (s) { $(s).value = ''; }); loadKb(); loadRefs(); } });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('#kMsg', 'Supabase не подключён.', 'err'); return; }
    loadKb(); loadRefs();
  });
  function acList() {
    var q = ($('#rMat').value || '').trim().toLowerCase();
    var list = mats;
    if (q) list = mats.filter(function (m) {
      return ((m.grade || '') + ' ' + (m.group_code || '') + ' ' + (m.standard || '')).toLowerCase().indexOf(q) >= 0;
    });
    return list.slice(0, 12);
  }
  function acRender() {
    var box = document.getElementById('acPanel'), inp = document.getElementById('rMat');
    if (!box || !inp) return;
    var list = acList();
    if (!list.length) { box.innerHTML = '<div class="ac-empty">Ничего не найдено — введите марку вручную</div>'; }
    else box.innerHTML = list.map(function (m, i) {
      return '<div class="ac-item' + (i === acIdx ? ' on' : '') + '" data-v="' + esc(m.grade) + '"><b>' + esc(m.grade) + '</b>' +
        '<span class="g">' + esc(GRP[m.group_code] || m.group_code || '') + '</span></div>';
    }).join('');
    box.hidden = false;
  }
  function acClose() { var box = document.getElementById('acPanel'); if (box) box.hidden = true; acIdx = -1; }
  function acPick(v) { var inp = document.getElementById('rMat'); if (inp) inp.value = v; acClose(); }
  function setupAc() {
    var inp = document.getElementById('rMat'), box = document.getElementById('acPanel');
    if (!inp || !box) return;
    inp.addEventListener('focus', function () { acIdx = -1; acRender(); });
    inp.addEventListener('input', function () { acIdx = -1; acRender(); });
    inp.addEventListener('keydown', function (e) {
      var list = acList();
      if (e.key === 'ArrowDown') { e.preventDefault(); if (box.hidden) acRender(); else { acIdx = Math.min(acIdx + 1, list.length - 1); acRender(); } }
      else if (e.key === 'ArrowUp') { e.preventDefault(); acIdx = Math.max(acIdx - 1, 0); acRender(); }
      else if (e.key === 'Enter') { if (!box.hidden && acIdx >= 0 && list[acIdx]) { e.preventDefault(); acPick(list[acIdx].grade); } }
      else if (e.key === 'Escape') { acClose(); }
    });
    inp.addEventListener('blur', function () { setTimeout(acClose, 150); });
    box.addEventListener('mousedown', function (e) {
      var it = e.target.closest('.ac-item'); if (!it) return;
      e.preventDefault(); acPick(it.dataset.v);
    });
  }

  function loadRefs() {
    rpc('app_ref_material_list', { p_token: token, p_group: null, p_q: null }).then(function (list) {
      mats = list || [];
    }).catch(function () {});
    rpc('app_tech_features_list', { p_token: token }).then(function (rows) {
      var sel = document.getElementById('rFeat'); if (!sel || !rows || !rows.length) return;
      var cur = sel.value;
      sel.innerHTML = rows.map(function (r) { return '<option value="' + esc(r.feature) + '">' + esc(r.feature) + '</option>'; }).join('');
      if (cur) { var ok = Array.prototype.some.call(sel.options, function (o) { return o.value === cur; }); if (ok) sel.value = cur; }
    }).catch(function () {});
  }
  var _af = document.getElementById('afBtn');
  if (_af) _af.addEventListener('click', function () {
    rpc('app_tech_rules_autofill', { p_token: token }).then(function (r) { var x = r && r[0]; ui.toast((x && x.message) || 'Готово', x && x.ok ? 'ok' : 'err'); if (x && x.ok) recommend(); }).catch(function (e) { ui.toast('Ошибка: ' + e.message); });
  });
  setupAc();
})();
