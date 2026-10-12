/* ============================================================
   3DMP Service · apps/assistant — ИИ-помощник (база знаний + подбор)
   Данные: app_kb_*, app_tech_* (0023_assistant.sql). Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, me = null, kb = [];

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

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('#tabs button').forEach(function (x) { x.classList.toggle('active', x === b); });
    $('#t-ask').style.display = (b.dataset.t === 'ask') ? '' : 'none';
    $('#t-kb').style.display = (b.dataset.t === 'kb') ? '' : 'none';
  });
  $('#askBtn').addEventListener('click', ask);
  $('#q').addEventListener('keydown', function (e) { if (e.key === 'Enter') ask(); });
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
  function loadRefs() {
    rpc('app_ref_material_list', { p_token: token, p_group: null, p_q: null }).then(function (list) {
      var dl = document.getElementById('matList'); if (!dl) return;
      dl.innerHTML = (list || []).map(function (m) { return '<option value="' + esc(m.grade) + '">' + esc(m.group_code || '') + '</option>'; }).join('');
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
})();
