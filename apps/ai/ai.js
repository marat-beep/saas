/* ============================================================
   3DMP Service · apps/ai — ИИ-помощник (W11, 0156).
   Авто-нормирование, CV-ОТК, цифровой двойник, помощник по БЗ, журнал задач.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, normRows = [], qcList = [];

  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function msg(id, t, k) { var e = $(id); if (!e) return; e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function num(v) { return (Number(v) || 0).toLocaleString('ru-RU'); }
  function dt(v) { return v ? new Date(v).toLocaleString('ru-RU') : '—'; }

  function showTab(scr) {
    $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); });
    $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); });
    if (scr === 'cv' && !qcList.length) loadQc();
    if (scr === 'twin') loadTwin();
    if (scr === 'jobs') loadJobs();
  }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() {
    return rpc('app_ai_kpi', { p_token: token }).then(function (r) {
      var k = (r && r[0]) || {};
      $('#kpis').innerHTML = cell('ИИ-задач', k.jobs || 0) + cell('Выполнено', k.done || 0) + cell('В очереди', k.pending || 0) + cell('Ср. оценка', (k.avg_score != null ? k.avg_score : '—')) + cell('Последняя', dt(k.last_at));
    });
  }

  /* ---------- Нормирование ---------- */
  function loadNorm() {
    msg('#nMsg', 'Расчёт…', 'info');
    return rpc('app_ai_norming_suggest', { p_token: token, p_operation: null }).then(function (r) {
      normRows = r || [];
      $('#norm').innerHTML = normRows.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th></th><th>Операция</th><th>Тип</th><th class="num">Наладка, мин</th><th class="num">На ед., мин</th><th class="num">Наблюдений</th><th>Источник</th><th>Достоверность</th></tr></thead><tbody>' +
        normRows.map(function (x, i) {
          var c = Number(x.confidence) || 0;
          return '<tr><td><input type="checkbox" data-norm="' + i + '"></td><td><b>' + esc(x.operation) + '</b></td><td>' + esc(x.machine_kind || '—') + '</td>' +
            '<td class="num">' + num(x.setup_min) + '</td><td class="num">' + num(x.unit_min) + '</td><td class="num">' + (x.samples || 0) + '</td><td>' + esc(x.source) + '</td>' +
            '<td style="min-width:120px;"><div class="bar"><i style="width:' + Math.min(c, 100) + '%"></i></div><span class="note">' + c + '%</span></td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Нет операций для нормирования.</span>';
      msg('#nMsg', 'Операций: ' + normRows.length, 'ok');
    }).catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function applyNorm() {
    var items = $$('#norm [data-norm]').filter(function (c) { return c.checked; }).map(function (c) {
      var x = normRows[Number(c.dataset.norm)];
      return { operation: x.operation, machine_kind: x.machine_kind, setup_min: x.setup_min, unit_min: x.unit_min, rate_hour: x.rate_hour };
    });
    if (!items.length) { msg('#nMsg', 'Выберите операции.', 'err'); return; }
    rpc('app_ai_norming_apply', { p_token: token, p_items: items }).then(function (r) {
      var x = r && r[0]; msg('#nMsg', x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadNorm(); loadKpi();
    }).catch(function (e) { msg('#nMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- CV-ОТК ---------- */
  function loadQc() {
    return rpc('app_qc_list', { p_token: token }).then(function (r) {
      qcList = r || [];
      $('#cvSel').innerHTML = qcList.map(function (q) { return '<option value="' + q.id + '">' + esc(q.number + (q.product ? ' · ' + q.product : '')) + '</option>'; }).join('') || '<option value="">— нет проверок —</option>';
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  }
  function runCv() {
    var id = $('#cvSel').value; if (!id) { msg('#cMsg', 'Нет проверок.', 'err'); return; }
    rpc('app_ai_cv_qc', { p_token: token, p_check_id: id }).then(function (r) {
      var x = (r && r[0]) || {};
      var cls = x.verdict === 'годен' ? 'ok2' : (x.verdict === 'риск' ? 'warn2' : 'bad2');
      $('#cvRes').innerHTML = '<div class="ai-card"><div style="display:flex;justify-content:space-between;align-items:center;gap:8px;">' +
        '<b>Вердикт: <span class="badge ' + cls + '">' + esc(x.verdict) + '</span></b><span class="note">доля брака ' + num(x.score) + '%</span></div>' +
        '<small class="mt">' + esc(x.note || '') + '</small></div>';
      msg('#cMsg', 'Оценка выполнена', 'ok'); loadKpi();
    }).catch(function (e) { msg('#cMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Цифровой двойник ---------- */
  function loadTwin() {
    return rpc('app_ai_twin', { p_token: token, p_limit: 20 }).then(function (r) {
      var list = r || [];
      $('#twin').innerHTML = list.length ? list.map(function (x) {
        return '<div class="ai-card"><h4>' + esc(x.title) + '</h4><small>' + esc(x.detail) + '</small>' +
          '<div style="margin-top:6px;"><span class="note">Влияние: <b>' + num(x.impact) + '</b></span></div></div>';
      }).join('') : '<span class="note">Рекомендаций нет — узких мест не выявлено.</span>';
      msg('#tMsg', 'Рекомендаций: ' + list.length, 'ok');
    }).catch(function (e) { msg('#tMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Помощник ---------- */
  function ask() {
    var q = $('#askQ').value.trim(); if (!q) return;
    msg('#aMsg', 'Ищу ответ…', 'info');
    rpc('app_ai_ask', { p_token: token, p_prompt: q }).then(function (r) {
      var x = (r && r[0]) || {};
      $('#askRes').innerHTML = '<div class="ai-answer">' + esc(x.answer || '') + '</div><div class="note" style="margin-top:6px;">Источник: ' + esc(x.source || '—') + '</div>';
      msg('#aMsg', '', 'ok'); loadKpi();
    }).catch(function (e) { msg('#aMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  /* ---------- Журнал ---------- */
  function loadJobs() {
    var kind = $('#jKind').value || null;
    return rpc('app_ai_jobs_list', { p_token: token, p_kind: kind, p_limit: 50 }).then(function (r) {
      var list = r || [];
      var km = { norming: 'Нормирование', cv_qc: 'CV-ОТК', twin: 'Двойник', llm: 'Помощник' };
      $('#jobs').innerHTML = list.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr><th>Когда</th><th>Тип</th><th>Статус</th><th class="num">Оценка</th><th>Автор</th><th>Примечание</th></tr></thead><tbody>' +
        list.map(function (j) {
          return '<tr><td class="muted">' + dt(j.created_at) + '</td><td>' + esc(km[j.kind] || j.kind) + '</td><td>' + esc(j.status) + '</td>' +
            '<td class="num">' + (j.score != null ? j.score : '—') + '</td><td class="muted">' + esc(j.created_login || '') + '</td><td class="muted">' + esc(j.note || '') + '</td></tr>';
        }).join('') + '</tbody></table></div>' : '<span class="note">Задач нет.</span>';
    }).catch(function (e) { msg('#aMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  $('#normBtn').addEventListener('click', loadNorm);
  $('#normApply').addEventListener('click', applyNorm);
  $('#cvBtn').addEventListener('click', runCv);
  $('#twinBtn').addEventListener('click', loadTwin);
  $('#askBtn').addEventListener('click', ask);
  $('#askQ').addEventListener('keydown', function (e) { if (e.key === 'Enter') ask(); });
  $('#jobsBtn').addEventListener('click', loadJobs);
  $('#jKind').addEventListener('change', loadJobs);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#nMsg', 'Supabase не подключён.', 'err'); return; }
    loadKpi();
  });
})();
