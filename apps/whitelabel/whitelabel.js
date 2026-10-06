/* ============================================================
   3DMP Service · apps/whitelabel — P6 white-label. Данные: 0068.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null, brand = {}, theme = {};

  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  function preview() {
    var accent = $('#fAccent').value || '#0e7490';
    var logo = $('#fLogo').value || '3DMP';
    var slogan = $('#fSlogan').value || '';
    $('#pBar').style.background = accent;
    $('#pBtn').style.background = accent;
    $('#pLogo').textContent = logo;
    $('#pSlogan').textContent = slogan;
    var sub = ($('#fSub').value || 'demo').toLowerCase();
    var dom = $('#fDomain').value;
    $('#host').textContent = 'Адрес: ' + (dom ? dom : (sub + '.sapfir.eu')) + '/saas/';
  }

  function load() {
    return rpc('app_whitelabel_get', { p_token: token }).then(function (r) {
      var d = (r && r[0]) || {};
      brand = d.brand || {}; theme = d.theme || {};
      $('#fSub').value = d.subdomain || '';
      $('#fDomain').value = d.custom_domain || '';
      $('#fLogo').value = brand.logo || theme.logo || d.name || '';
      $('#fSlogan').value = brand.slogan || theme.slogan || '';
      $('#fAccent').value = theme.accent || '#0e7490';
      preview();
    }).catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  }

  ['fSub', 'fDomain', 'fLogo', 'fSlogan', 'fAccent'].forEach(function (id) { $('#' + id).addEventListener('input', preview); });

  $('#fSave').addEventListener('click', function () {
    var b = { logo: $('#fLogo').value, slogan: $('#fSlogan').value };
    var t = { accent: $('#fAccent').value, logo: $('#fLogo').value, slogan: $('#fSlogan').value };
    rpc('app_whitelabel_save', { p_token: token, p_subdomain: $('#fSub').value, p_custom_domain: $('#fDomain').value, p_brand: b, p_theme: t })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x && x.ok ? 'ok' : 'err'); if (x && x.ok) window.Auth.log('Бренд сохранён', $('#fSub').value); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    load();
  });
})();
