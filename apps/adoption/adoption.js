/* ============================================================
   3DMP Service · apps/adoption — Карта внедрения (Партия I). Данные: 0096/0097.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, role = null, map = {};

  var TITLE = { orders:'Заявки', crm:'CRM', docs:'Документы', templates:'Шаблоны', dicts:'Списки', norms:'Нормирование', calc:'Калькуляторы', slots:'Слоты', setup:'Наладка', lean:'Lean', partners:'Партнёры', equipment:'Каталог оборудования', staff:'CRM сотрудников', config:'Конфигуратор', reverse:'Реверс-инжиниринг', escrow:'Эскроу', marketplace:'Маркетплейс', suppliers:'Поставщики', teo:'ТЭО', labels:'Маркировка', engraving:'Гравирование', files:'Файлы', iiot:'IIoT/DNC' };
  // модуль → волна внедрения
  var WAVE = { orders:1, crm:1, docs:1, templates:1, dicts:1, norms:2, calc:2, partners:2, equipment:2, suppliers:2, slots:2, setup:2, config:2, reverse:2, iiot:3, lean:3, staff:3, teo:4, escrow:4, marketplace:4, labels:3, engraving:3, files:3 };
  var WAVE_T = { 1:'Волна 1 — Старт и продажи', 2:'Волна 2 — Продажи/КТПП/производство', 3:'Волна 3 — Производство/качество', 4:'Волна 4 — Экономика/масштаб' };
  var PROFILE = { small:[1,2], mid:[1,2,3], large:[1,2,3,4] };

  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#mMsg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function load() {
    return Promise.all([
      rpc('app_adoption_map', { p_token: token }),
      rpc('app_adoption_kpi', { p_token: token })
    ]).then(function (r) {
      map = {}; (r[0] || []).forEach(function (m) { map[m.module] = m; });
      var k = (r[1] && r[1][0]) || {};
      $('#kpis').innerHTML = cell('Модулей учтено', k.modules_known || 0) + cell('Включено', k.enabled || 0) + cell('Используется', k.used || 0) + cell('Прогресс', (k.progress_pct || 0) + '%');
      render();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }

  function render() {
    var prof = PROFILE[$('#profile').value] || [1,2,3,4];
    var html = '';
    [1,2,3,4].forEach(function (w) {
      var mods = Object.keys(map).filter(function (m) { return WAVE[m] === w; });
      if (!mods.length) return;
      var recommended = prof.indexOf(w) >= 0;
      html += '<div class="wave">' + esc(WAVE_T[w]) + (recommended ? ' <span class="st used">рекомендуется профилю</span>' : ' <span class="st off">позже</span>') + '</div>';
      html += '<table class="mini"><thead><tr><th>Модуль</th><th>Статус</th><th class="num">Записей</th><th></th></tr></thead><tbody>';
      mods.forEach(function (m) {
        var x = map[m];
        var st = x.used ? '<span class="st used">используется</span>' : (x.enabled ? '<span class="st on">включён</span>' : '<span class="st off">не включён</span>');
        html += '<tr><td>' + esc(TITLE[m] || m) + '</td><td>' + st + '</td><td class="num">' + (x.records || 0) + '</td>' +
          '<td>' + (x.enabled ? '' : '<button class="btn secondary" data-on="' + m + '" style="width:auto;padding:4px 10px;font-size:.72rem;">Включить</button>') +
          (x.enabled ? '<button class="btn secondary" data-off="' + m + '" style="width:auto;padding:4px 10px;font-size:.72rem;">Отключить</button>' : '') + '</td></tr>';
      });
      html += '</tbody></table>';
    });
    $('#map').innerHTML = html || '<span class="note">Нет данных.</span>';
    $$('#map [data-on]').forEach(function (b) { b.addEventListener('click', function () { setMod(b.dataset.on, true); }); });
    $$('#map [data-off]').forEach(function (b) { b.addEventListener('click', function () { setMod(b.dataset.off, false); }); });
  }

  function setMod(m, en) {
    rpc('app_tenant_module_set', { p_token: token, p_module: m, p_enabled: en })
      .then(function (r) { var x = r && r[0]; msg(x ? x.message : 'Готово', x && x.ok ? 'ok' : 'err'); load(); })
      .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }

  $('#profile').addEventListener('change', render);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token; role = s.role;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    load();
  });
})();
