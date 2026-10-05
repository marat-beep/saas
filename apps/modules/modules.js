/* ============================================================
   3DMP Service · apps/modules — карта модулей и их концепт
   Источник: assets/js/catalog.js (AppCatalog). Показывает назначение,
   функции, связи, роли и вход/выход каждого модуля.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs;
  var C = window.AppCatalog;
  var me = null, q = '';

  function esc(v) { return ui.esc(v); }
  function canSee(a) { if (!a.roles) return true; return me && a.roles.indexOf(me.role) >= 0; }

  function render() {
    var list = C.apps.filter(function (a) {
      if (!canSee(a)) return false;
      if (!q) return true;
      var hay = [a.title, a.desc, a.purpose, (a.features || []).join(' ')].join(' ').toLowerCase();
      return hay.indexOf(q) >= 0;
    });
    $('#grid').innerHTML = list.map(function (a) {
      var conn = (a.connects || []).map(function (id) {
        var t = C.apps.filter(function (x) { return x.id === id; })[0];
        if (!t) return '';
        return '<a href="' + t.href + '">' + esc(t.title) + '</a>';
      }).join('');
      var feats = (a.features || []).map(function (f) { return '<li>' + esc(f) + '</li>'; }).join('');
      return '<div class="mcard">' +
        '<div class="ic">' + a.icon + '</div>' +
        '<h3>' + esc(a.title) + '</h3>' +
        '<div class="d">' + esc(a.desc || '') + '</div>' +
        (a.purpose ? '<div class="pz"><b>Назначение:</b> ' + esc(a.purpose) + '</div>' : '') +
        (feats ? '<div class="pz"><b>Функции:</b></div><ul class="feat">' + feats + '</ul>' : '') +
        ((a.in_ || a.out) ? '<div class="io">Вход: ' + esc(a.in_ || '—') + ' · Результат: ' + esc(a.out || '—') + '</div>' : '') +
        (conn ? '<div class="pz"><b>Связи:</b></div><div class="conn">' + conn + '</div>' : '') +
        '<div class="roles">Роли: ' + (a.roles ? a.roles.join(', ') : 'все сотрудники') + (a.guest ? ' · доступно без входа' : '') + '</div>' +
        '<a class="act" href="' + a.href + '">Открыть модуль</a>' +
        '</div>';
    }).join('') || '<span class="note">Ничего не найдено.</span>';
  }

  $('#q').addEventListener('input', function () { q = this.value.trim().toLowerCase(); render(); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    me = s;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    render();
  });
})();
