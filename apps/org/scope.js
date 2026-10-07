/* ============================================================
   3DMP Service · apps/org/scope.js — R4: гейтинг по подразделению (0157).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function msg(t, k) { var e = $('#scopeMsg'); if (!e) return; e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  var token = null;
  function state() {
    Promise.all([
      rpc('app_dept_scope_get', { p_token: token }).then(function (v) { return v; }).catch(function () { return false; }),
      rpc('app_my_department', { p_token: token }).catch(function () { return []; })
    ]).then(function (r) {
      var md = (r[1] && r[1][0]) || {};
      $('#scopeState').textContent = (r[0] ? 'Включён' : 'Выключен') + ' · ваше подразделение: ' + (md.department_name || 'не задано');
    });
  }
  function set(en) {
    rpc('app_dept_scope_set', { p_token: token, p_enabled: en }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); state(); })
      .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }
  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (['admin', 'owner'].indexOf(s.role) < 0) return;
    token = s.token;
    if (!SB) return;
    state();
    $('#scopeOn').addEventListener('click', function () { set(true); });
    $('#scopeOff').addEventListener('click', function () { set(false); });
  });
})();
