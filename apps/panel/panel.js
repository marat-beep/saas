/* ============================================================
   3DMP Service · apps/panel — Пульт управления (единая точка входа)
   5 зон аудиторий из assets/js/catalog.js (catalog.zones + zoneOf).
   Состав модулей — ТОЛЬКО из каталога, без хардкода.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, C = window.AppCatalog;

  function esc(v) { return ui.esc(v); }
  function card(a) {
    return '<a class="app-card" href="../../' + a.href + '">' +
      '<span class="ic">' + a.icon + '</span><h3>' + esc(a.title) + '</h3><p>' + esc(a.desc) + '</p></a>';
  }
  var role = null, query = '';
  function zonesForRole() { return (C.zones || []).filter(function (z) { return (z.roles || []).indexOf(role) >= 0; }); }
  function appsOfZone(zid) { return (C.apps || []).filter(function (a) { return (C.zoneOf ? C.zoneOf(a.id) : 'org_admin') === zid; }); }

  function render() {
    var zs = zonesForRole();
    if (!zs.length) { $('#zoneNav').innerHTML = ''; $('#sections').innerHTML = '<div class="card"><span class="note">Для вашей роли разделы не найдены.</span></div>'; return; }
    var s = query.toLowerCase();
    var matches = function (a) { return !s || (a.title + ' ' + a.desc).toLowerCase().indexOf(s) >= 0; };
    var nav = '', sec = '';
    zs.forEach(function (z) {
      var items = appsOfZone(z.id).filter(matches);
      if (!items.length) return;
      nav += '<a class="zone-link" href="#zone-' + z.id + '" data-z="' + z.id + '"><span>' + z.icon + ' ' + esc(z.title) + '</span><span class="zone-cnt">' + items.length + '</span></a>';
      sec += '<section class="card panel-sec" id="zone-' + z.id + '">' +
        '<h2><button class="sec-tog" type="button" data-tog="' + z.id + '" aria-label="Свернуть/развернуть">▾</button> ' +
        z.icon + ' ' + esc(z.title) + ' <span class="sec-badge">' + items.length + '</span></h2>' +
        '<div class="sec-body"><p class="note">' + esc(z.about) + '</p>' +
        '<div class="apps-grid">' + items.map(card).join('') + '</div></div></section>';
    });
    $('#zoneNav').innerHTML = nav;
    $('#sections').innerHTML = sec || '<div class="card"><span class="note">Ничего не найдено.</span></div>';
    $$('#zoneNav .zone-link').forEach(function (l) {
      l.addEventListener('click', function (e) { e.preventDefault(); var el = document.getElementById('zone-' + l.dataset.z); if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' }); });
    });
    $$('#sections [data-tog]').forEach(function (b) {
      b.addEventListener('click', function () { var s = b.closest('.panel-sec'); if (s) s.classList.toggle('collapsed'); });
    });
    if ('IntersectionObserver' in window) {
      var obs = new IntersectionObserver(function (es) {
        es.forEach(function (en) { if (en.isIntersecting) { var id = en.target.id.replace('zone-', ''); $$('#zoneNav .zone-link').forEach(function (l) { l.classList.toggle('on', l.dataset.z === id); }); } });
      }, { rootMargin: '-40% 0px -55% 0px' });
      $$('.panel-sec').forEach(function (x) { obs.observe(x); });
    }
  }

  var sEl = $('#search'); if (sEl) sEl.addEventListener('input', function () { query = this.value.trim(); render(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  if (window.AppStatus) window.AppStatus.render('#conn').catch(function () {});
  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    role = s.role;
    var rl = (window.Auth.roleLabel ? window.Auth.roleLabel(s.role) : '') || s.role;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + rl;
    render();
  });
})();
