/* ============================================================
   3DMP Service · apps/guide — гид по системе
   Строит карту модулей из assets/js/catalog.js:
   назначение, функции, связи, вход/результат, аудитория. Гостю доступно.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, C = window.AppCatalog;

  var AUD = {
    guest: 'гость', user: 'пользователь', client_admin: 'админ клиента',
    saas_admin: 'SaaS-админ', developer: 'разработчик'
  };
  function esc(v) { return ui.esc(v); }
  function byId(id) { return (C.apps || []).filter(function (a) { return a.id === id; })[0]; }

  function moduleCard(a) {
    var feats = (a.features || []).map(function (f) { return '<li>' + esc(f) + '</li>'; }).join('');
    var conn = (a.connects || []).map(function (id) {
      var t = byId(id);
      if (!t) return '<span class="chip">↔ ' + esc(id) + '</span>';
      return '<a class="chip" href="../../' + t.href + '">↔ ' + esc(t.title) + '</a>';
    }).join('');
    return '<div class="mod">' +
      '<h3>' + a.icon + ' ' + esc(a.title) +
        '<a class="chip" href="../../' + a.href + '">открыть</a>' +
        '<span class="aud" style="margin-left:auto;">' + (AUD[a.audience] || a.audience || '') + '</span></h3>' +
      '<div class="note">' + esc(a.desc) + '</div>' +
      (a.purpose ? '<div class="purp"><b>Зачем:</b> ' + esc(a.purpose) + '</div>' : '') +
      (feats ? '<ul>' + feats + '</ul>' : '') +
      (conn ? '<div class="chips">' + conn + '</div>' : '') +
      ((a.in_ || a.out) ? '<div class="io">Вход: ' + esc(a.in_ || '—') + ' · Результат: ' + esc(a.out || '—') + '</div>' : '') +
      '</div>';
  }

  function render(filter) {
    var q = (filter || '').trim().toLowerCase();
    var match = function (a) {
      if (!q) return true;
      var hay = [a.title, a.desc, a.purpose, (a.features || []).join(' '), (a.connects || []).join(' ')].join(' ').toLowerCase();
      return hay.indexOf(q) >= 0;
    };
    var html = (C.groups || []).map(function (g) {
      var items = (C.apps || []).filter(function (a) { return a.group === g.id && match(a); });
      if (!items.length) return '';
      return '<div class="guide-grp"><h2>' + g.icon + ' ' + esc(g.title) + '</h2>' + items.map(moduleCard).join('') + '</div>';
    }).join('');
    $('#guide').innerHTML = html || '<div class="card"><span class="note">Ничего не найдено.</span></div>';
  }

  $('#q').addEventListener('input', function () { render(this.value); });

  var s = window.Auth && window.Auth.session ? window.Auth.session() : null;
  if (s) {
    $('#who').textContent = s.login + (s.role ? ' · ' + s.role : '');
    var lo = $('#logout'); lo.style.display = ''; lo.addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });
  } else {
    $('#who').textContent = 'гость';
  }
  render('');
})();
