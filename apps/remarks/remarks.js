/* ============================================================
   3DMP Service · apps/remarks — страница-модуль «Замечания к странице».
   Использует виджет window.PageRemarks. Данные: RPC (0098) или local (демо).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null;

  function storageFor() {
    if (SB && token) { try { return window.RemarksStorage.rpc(SB, function () { return token; }); } catch (e) {} }
    return window.RemarksStorage.local();
  }

  function prefill() {
    var q = (location.search.match(/[?&]url=([^&]+)/) || [])[1];
    return q ? decodeURIComponent(q) : '';
  }

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role) && s.role !== 'client') { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);

    var widget = window.PageRemarks.init({
      mount: $('#remarksMount'),
      shotEndpoint: (window.AppConfig && window.AppConfig.shotEndpoint) || '', // пусто → mock
      module: 'remarks',
      user: { id: s.id || s.login, name: s.full_name || s.login, role: (s.role === 'client' ? 'client' : 'employee') },
      storage: storageFor(),
      onRemarkAdded: function () { if (window.Auth.log) window.Auth.log('Замечание', 'добавлено'); },
      onError: function (e) { if (window.console) console.warn('[remarks]', e); }
    });

    var pre = prefill(); var el = $('#prUrl');
    if (pre && el) { el.value = pre; }

    // deep-link #yaremark=<id> — подсветить метку (после загрузки)
    var m = location.hash.match(/yaremark=([\w-]+)/);
    if (m) { setTimeout(function () { try { var host = document.querySelector('[data-card="' + m[1] + '"]'); if (host) host.scrollIntoView({ behavior: 'smooth' }); } catch (e) {} }, 600); }
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
})();
