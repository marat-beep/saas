/* ============================================================
   P6 · White-label порталы
   список → настройка бренда → предпросмотр → публикация
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var COLORS = [
    { name: 'Изумруд', grad: 'linear-gradient(135deg,#064e3b,#10b981)' },
    { name: 'Индиго', grad: 'linear-gradient(135deg,#312e81,#6366f1)' },
    { name: 'Бирюза', grad: 'linear-gradient(135deg,#164e63,#06b6d4)' },
    { name: 'Фиолет', grad: 'linear-gradient(135deg,#4c1d95,#7c3aed)' },
    { name: 'Оранж', grad: 'linear-gradient(135deg,#9a3412,#ea580c)' }
  ];

  var PORTALS = [
    { name: 'Портал Пресс-Технологии', icon: '🏭', domain: 'press-tech', color: 0 },
    { name: 'Клиентский портал Урал-Штамп', icon: '⚙️', domain: 'ural-stamp', color: 1 }
  ];

  var draft = { name: '', icon: '🏭', domain: '', color: 0 };

  var screens = AppRouter.create({
    onShow: function (s) { window.scrollTo(0, 0); },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderPortals() {
    $('#portalList').innerHTML = PORTALS.map(function (p, i) {
      return '<div class="portal-row" data-i="' + i + '"><div class="portal-logo" style="background:' + COLORS[p.color].grad + ';">' + p.icon + '</div><div class="grow"><div style="font-weight:700;font-size:.9rem;">' + p.name + '</div><div class="faint" style="font-size:.72rem;">' + p.domain + '.3dmp.cloud</div></div><span class="badge success">Активен</span></div>';
    }).join('');
    $$('#portalList .portal-row').forEach(function (r) {
      r.addEventListener('click', function () {
        var p = PORTALS[parseInt(r.dataset.i, 10)];
        draft = { name: p.name, icon: p.icon, domain: p.domain, color: p.color };
        loadBrand(); screens.go('s2');
      });
    });
  }

  function renderSwatches() {
    $('#swatches').innerHTML = COLORS.map(function (c, i) {
      return '<div class="swatch' + (draft.color === i ? ' on' : '') + '" style="background:' + c.grad + ';" data-c="' + i + '" title="' + c.name + '"></div>';
    }).join('');
    $$('#swatches .swatch').forEach(function (sw) {
      sw.addEventListener('click', function () { draft.color = parseInt(sw.dataset.c, 10); renderSwatches(); });
    });
  }

  function loadBrand() {
    $('#wlName').value = draft.name; $('#wlIcon').value = draft.icon; $('#wlDomain').value = draft.domain;
    renderSwatches();
  }
  $('#wlName').addEventListener('input', function () { draft.name = this.value; });
  $('#wlIcon').addEventListener('change', function () { draft.icon = this.value; });
  $('#wlDomain').addEventListener('input', function () { draft.domain = this.value; });

  function renderPreview() {
    var grad = COLORS[draft.color].grad;
    var head = $('#pvHead');
    head.style.background = grad;
    head.innerHTML = '<span style="font-size:1.6rem;">' + draft.icon + '</span><b style="font-size:1rem;">' + (draft.name || 'Портал') + '</b>';
    $('#pvDomain').textContent = (draft.domain || 'portal') + '.3dmp.cloud';
  }

  $('#createPortal').addEventListener('click', function () {
    draft = { name: 'Новый портал', icon: '🚀', domain: 'portal', color: 3 };
    loadBrand(); screens.go('s2');
  });
  $('#cancel').addEventListener('click', function () { screens.back(); });
  $('#toPreview').addEventListener('click', function () { draft.name = $('#wlName').value; draft.icon = $('#wlIcon').value; draft.domain = $('#wlDomain').value; renderPreview(); screens.go('s3'); });
  $('#backBrand').addEventListener('click', function () { screens.back(); });
  $('#publish').addEventListener('click', function () {
    PORTALS.push({ name: draft.name, icon: draft.icon, domain: draft.domain, color: draft.color });
    $('#pubDomain').textContent = draft.domain + '.3dmp.cloud';
    renderPortals(); screens.go('s4');
    App.toast('Портал ' + draft.domain + '.3dmp.cloud опубликован');
  });
  $('#backList').addEventListener('click', function () { renderPortals(); screens.replace('s1'); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderPortals();
})();
