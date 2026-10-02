/* ============================================================
   B36 · ИТ-инфраструктура предприятия
   сеть, оборудование, подключение станков, резерв, чек-лист
   (для сетевого инженера и системного администратора)
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var DATA = {
    net: { title: 'Сегментация сети (VLAN)', cols: ['VLAN', 'Назначение', 'Примечание'], rows: [
      ['VLAN 10', 'IT / офис', 'ПК, 1С, файлы, интернет'],
      ['VLAN 20', 'OT / оборудование', 'Станки ЧПУ, изолирован от интернета'],
      ['VLAN 30', 'DMZ', 'Внешние сервисы, API, публикация порталов'],
      ['VLAN 40', 'Guest Wi-Fi', 'Гости, изоляция клиентов'],
      ['VLAN 50', 'Серверы / NAS', 'БД, файлы, резервные копии'],
      ['VLAN 99', 'Управление', 'Коммутаторы, шлюз, мониторинг']
    ] },
    equip: { title: 'Оборудование предприятия', cols: ['Устройство', 'Назначение', 'Примечание'], rows: [
      ['Интернет-шлюз / firewall', 'Маршрутизация, VPN, правила', 'Резервный канал'],
      ['Управляемые коммутаторы', 'VLAN, агрегация', 'По одному на сегмент'],
      ['Wi-Fi точка доступа', 'Беспроводная сеть', '802.1X + гостевой SSID'],
      ['Сервер / NAS', 'БД, файлы, бэкапы', 'RAID, ИБП'],
      ['MES-шлюз / пром. ПК', 'Сбор данных со станков', 'OT-сегмент'],
      ['ИБП', 'Защита питания', 'Серверы и шлюз']
    ] },
    cnc: { title: 'Подключение станков', cols: ['Станок / протокол', 'Канал', 'Примечание'], rows: [
      ['Fanuc — FOCAS', 'Ethernet (OT)', 'Чтение состояния, алармы'],
      ['Siemens — OPC UA', 'Ethernet (OT)', 'Наработка, программа'],
      ['Heidenhain — MTConnect/шлюз', 'Пром. ПК', 'Мониторинг'],
      ['Sodick / прочие — шлюз', 'Пром. ПК / реле', 'Сигналы запуск/простой'],
      ['DNC (передача УП)', 'Отдельный канал', 'Только исходящие из OT'],
      ['КИМ / метрология', 'IT/DMZ', 'Передача протоколов']
    ] },
    backup: { title: 'Резервное копирование (3-2-1)', cols: ['Правило', 'Описание'], rows: [
      ['Ежедневно', 'БД + журнал изменений; хранение 30 дней'],
      ['Еженедельно', 'Полная выгрузка данных и конфигурации'],
      ['3-2-1', '3 копии, 2 носителя, 1 вне площадки'],
      ['Проверка', 'Ежемесячный тест восстановления'],
      ['Сроки', 'RPO ≤ 24 ч, RTO ≤ 4 ч'],
      ['Доступ', 'Отдельные учётки, минимальные права']
    ] }
  };

  var CHECKS = [
    'Схема сети и IP-план заведены и подписаны',
    'Станки в отдельном OT-сегменте, без выхода в интернет',
    'Firewall: правила между IT/OT/DMZ, VPN для удалённого доступа',
    'Отдельные учётные записи служб, принцип минимальных прав',
    'Резервное копирование 3-2-1 и тест восстановления',
    'Мониторинг доступности сервисов и места на дисках',
    'Обновления ОС/ПО по расписанию, антивирус',
    'Журналирование действий и регулярный аудит прав',
    'Документация и инструкции (P11), доступ к P12 у команды'
  ];
  var done = App.Store.get('itChecklist', []);
  var tab = 'net';

  var screens = AppRouter.create({ onShow: function () {}, onBackEmpty: function () { location.href = '../../index.html'; } });

  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('button', this).forEach(function (x) { x.classList.toggle('active', x === b); });
    tab = b.dataset.t; render();
  });

  function render() {
    if (tab === 'check') {
      $('#list').innerHTML = '<div class="faint" style="font-size:.72rem;margin-bottom:8px;">Чек-лист организации ИТ — отмечено ' + done.length + ' из ' + CHECKS.length + '</div>' +
        CHECKS.map(function (c, i) { return '<div class="chk ' + (done.indexOf(i) >= 0 ? 'done' : '') + '" data-i="' + i + '"><span class="box">' + (done.indexOf(i) >= 0 ? '✓' : '') + '</span><span class="lbl">' + c + '</span></div>'; }).join('');
      $$('#list .chk').forEach(function (el) {
        el.addEventListener('click', function () {
          var i = parseInt(el.dataset.i, 10), k = done.indexOf(i);
          if (k >= 0) done.splice(k, 1); else done.push(i);
          App.Store.set('itChecklist', done); render();
        });
      });
      return;
    }
    var d = DATA[tab];
    $('#list').innerHTML = '<div class="faint" style="font-size:.72rem;margin-bottom:8px;">' + d.title + '</div>' +
      d.rows.map(function (r) { return '<div class="ref"><span>' + r[0] + '</span><span class="r">' + r.slice(1).join(' · ') + '</span></div>'; }).join('');
  }

  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
  render();
})();
