/* ============================================================
   P4 · Public API и интеграции
   обзор → ключи → интеграции → создание ключа
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var KEYS = [
    { name: 'Production', prefix: 'sk_live_9f2a', scopes: 'orders, procurement', created: '01.08' },
    { name: '1С синхронизация', prefix: 'sk_live_3c11', scopes: 'orders, tasks', created: '14.07' },
    { name: 'Аналитика BI', prefix: 'sk_test_7b0d', scopes: 'read-only', created: '22.06' }
  ];

  var INTEGRATIONS = [
    { icon: '🏢', name: '1С:Предприятие', desc: 'Заказы, номенклатура, счета', on: true },
    { icon: '🗄', name: 'ERP (SAP/Oracle)', desc: 'Планирование и производство', on: false },
    { icon: '📇', name: 'CRM (Bitrix24/amoCRM)', desc: 'Клиенты и сделки', on: true },
    { icon: '🧊', name: 'CAM (SolidWorks/Fusion)', desc: 'Модели и техпроцессы', on: false },
    { icon: '✈️', name: 'Telegram-бот', desc: 'Уведомления и согласования', on: true },
    { icon: '📊', name: 'BI (Power BI/Tableau)', desc: 'Дашборды и отчёты', on: false }
  ];

  var screens = AppRouter.create({
    onShow: function (s) { window.scrollTo(0, 0); },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderKeys() {
    $('#keyList').innerHTML = KEYS.map(function (k, i) {
      return '<div class="key-row"><div class="grow"><div style="font-weight:700;font-size:.86rem;">' + k.name + '</div><div class="faint" style="font-size:.7rem;margin-top:2px;">' + k.scopes + ' · создан ' + k.created + '</div></div><span class="key-code">' + k.prefix + '••••</span><button class="btn btn-ghost btn-sm" data-rev="' + i + '">Отозвать</button></div>';
    }).join('');
    $$('#keyList [data-rev]').forEach(function (b) {
      b.addEventListener('click', function () { KEYS.splice(parseInt(b.dataset.rev, 10), 1); renderKeys(); App.toast('Ключ отозван'); });
    });
  }

  function renderInt() {
    $('#intList').innerHTML = INTEGRATIONS.map(function (it, i) {
      return '<div class="int-row"><div class="int-logo">' + it.icon + '</div><div class="grow"><div style="font-weight:700;font-size:.86rem;">' + it.name + '</div><div class="faint" style="font-size:.72rem;">' + it.desc + '</div></div><span class="badge ' + (it.on ? 'success' : 'neutral') + '" style="margin-right:8px;">' + (it.on ? 'Подключено' : 'Отключено') + '</span><div class="switch' + (it.on ? ' on' : '') + '" data-int="' + i + '"></div></div>';
    }).join('');
    $$('#intList .switch').forEach(function (sw) {
      sw.addEventListener('click', function () {
        var i = parseInt(sw.dataset.int, 10);
        INTEGRATIONS[i].on = !INTEGRATIONS[i].on;
        renderInt(); App.toast(INTEGRATIONS[i].name + (INTEGRATIONS[i].on ? ' подключена' : ' отключена'));
      });
    });
  }

  $$('[data-go]').forEach(function (b) { b.addEventListener('click', function () { screens.go(b.dataset.go); }); });
  $('#createKey').addEventListener('click', function () {
    var rand = Math.random().toString(36).slice(2, 10);
    var key = 'sk_live_' + rand;
    KEYS.unshift({ name: 'Новый ключ', prefix: key.slice(0, 12), scopes: 'orders, procurement, tasks', created: App.today().slice(0, 5) });
    $('#newKey').textContent = key + '••••••••••••';
    renderKeys();
    screens.go('s4');
    App.toast('API-ключ создан');
  });
  $('#back1').addEventListener('click', function () { screens.back(); });
  $('#back2').addEventListener('click', function () { screens.back(); });
  $('#backKeys').addEventListener('click', function () { renderKeys(); screens.replace('s2'); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderKeys(); renderInt();
})();
