/* ============================================================
   P12 · Технический путь и сетевая инфраструктура (для разработчика)
   целевая платформа, сеть, подключение станков, дорожная карта, чек-лист
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var NET = ''
    + '<div class="net">'
    + '<div class="net-row"><div class="node"><b>Интернет</b>канал + резерв</div><div class="node"><b>Firewall / шлюз</b>маршрутизация, VPN</div></div>'
    + '<div class="arrow">▼</div>'
    + '<div class="net-row">'
    + '<div class="node"><b>IT-сегмент</b>офис, 1С, файлы</div>'
    + '<div class="node ot"><b>OT-сегмент</b>станки ЧПУ, изолирован</div>'
    + '<div class="node dmz"><b>DMZ</b>внешние сервисы, API</div>'
    + '<div class="node"><b>Guest</b>Wi-Fi для гостей</div>'
    + '</div>'
    + '<div class="arrow">▼</div>'
    + '<div class="net-row"><div class="node"><b>Сервер / NAS</b>БД, файлы, бэкапы</div><div class="node"><b>ИБП</b>питание</div><div class="node"><b>MES-шлюз</b>сбор со станков</div></div>'
    + '</div>';

  var SECTIONS = [
    { id: 'arch', title: '1. Целевая платформа', html:
      '<ol class="steps">' +
      '<li>Backend — отдельный проект/схема (напр. <b>Supabase</b>, схема <code>eco</code> или проект <code>3dmp-eco</code>), чтобы не пересекаться с чужими проектами.</li>' +
      '<li>Таблицы <code>eco_orders, eco_requests, eco_tenders, eco_tasks, eco_team, eco_problems, eco_log, eco_user_roles</code> + RLS по <code>auth.uid()</code> и ролям.</li>' +
      '<li>Auth (email) + роли <i>клиент/сотрудник/партнёр/админ</i> + делегирование функций (как A14).</li>' +
      '<li>Storage — файлы (чертежи, КД, фото ОТК, резюме); единый клиент <code>sbClient</code>.</li>' +
      '<li>Версионирование <code>?v=N</code> в HTML; каталог приложений — источник правды (<code>catalog.js</code>).</li>' +
      '</ol><div style="margin-top:8px;">' + tag('../p4-api/index.html', 'P4 API') + tag('../p1-cloud/index.html', 'P1 Cloud') + tag('../p9-admin/index.html', 'P9 Админ') + '</div>' },
    { id: 'net', title: '2. Сетевая инфраструктура на предприятии', html: NET +
      '<ol class="steps" style="margin-top:10px;">' +
      '<li>Сегментация: отдельные <b>VLAN</b> для IT, OT (оборудование), DMZ и гостей; правило — станки не в общей сети.</li>' +
      '<li>Шлюз/firewall: резервный канал, VPN для удалённого доступа, политики между сегментами.</li>' +
      '<li>Wi-Fi: корпоративный SSID (802.1X) и гостевой с изоляцией клиентов.</li>' +
      '<li>Сервер/NAS + ИБП; статическая адресация для оборудования, DHCP для офиса, DNS.</li>' +
      '</ol>' },
    { id: 'cnc', title: '3. Подключение станков', html:
      '<ol class="steps">' +
      '<li>OT-сегмент: каждый станок в изолированной сети, доступ — через MES-шлюз/промышленный ПК.</li>' +
      '<li>Протоколы: <b>FOCAS</b> (Fanuc), <b>OPC UA</b>, <b>MTConnect</b> — чтение состояния, наработки, алармов.</li>' +
      '<li>Сбор данных → модуль мониторинга (B17) и OEE; DNC/УП — через защищённый канал (B18).</li>' +
      '<li>Безопасность: только исходящие соединения из OT, сегментация, отсутствие прямого интернета у станков.</li>' +
      '</ol><div style="margin-top:8px;">' + tag('../b17-monitor/index.html', 'B17 Монитор') + tag('../b18-nc/index.html', 'B18 УП/DNC') + tag('../b36-it/index.html', 'B36 ИТ-инфраструктура') + '</div>' },
    { id: 'road', title: '4. Дорожная карта (технический путь)', html:
      '<div class="tl">' +
      phase('#94a3b8', '0', 'Прототипы (текущее)', 'Данные в localStorage, единый каталог и слои, 67 приложений.') +
      phase('#3b82f6', '1', 'Данные и API', 'Схема данных, замена моков на Supabase, флаг <code>USE_MOCK</code>, чтение/запись.') +
      phase('#7c3aed', '2', 'Auth + RLS + роли', 'Аутентификация, права и делегирование; экраны входа A3/A7/C1/A14, иерархия P13.') +
      phase('#0891b2', '3', 'Storage и станки', 'Файлы (чертежи, КД, фото ОТК) и интеграции станков: мониторинг (B17), DNC (B18).') +
      phase('#ea580c', '4', 'Безопасность и надёжность', 'Резервное копирование 3-2-1, аудит, мониторинг доступности, план восстановления.') +
      phase('#10b981', '5', 'Масштабирование', 'Мультитенантность/SaaS (P1), биллинг (P5), маркетплейс (M1), отраслевая аналитика (P3).') +
      '</div>' },
    { id: 'ops', title: '5. Чек-лист разработчика и эксплуатации', html:
      '<ol class="steps">' +
      '<li>Секреты — только на сервере/в переменных, не в репозитории и не в клиенте.</li>' +
      '<li>Резервные копии: ежедневно БД, недельно — полная выгрузка; проверять восстановление.</li>' +
      '<li>Обновления и патчи ОС/СУБД; отдельные учётки служб; принцип минимальных прав.</li>' +
      '<li>Мониторинг: доступность сервисов, место на дисках, ошибки приложений; алерты.</li>' +
      '<li>Документация: схемы сети, IP-план, регламенты доступа, инструкции (P11).</li>' +
      '</ol><div style="margin-top:8px;">' + tag('../p11-manual/index.html', 'P11 Инструкция') + tag('../p10-diagnostics/index.html', 'P10 Диагностика') + tag('../p9-admin/index.html', 'P9 Админ') + '</div>' },
    { id: 'risk', title: '6. Риски и безопасность', html:
      '<ol class="steps">' +
      '<li>Один ключ на несколько проектов недопустим — для экосистемы отдельный проект/ключ.</li>' +
      '<li>Токены/пароли не в клиентском коде; RLS обязателен для каждой таблицы.</li>' +
      '<li>Изоляция OT от интернета; доступ к станкам — через контролируемый шлюз.</li>' +
      '<li>План восстановления (RPO/RTO) и тесты восстановления.</li>' +
      '<li>Регулярный аудит прав и журналирование действий (P9 → Аудит).</li>' +
      '</ol>' }
  ];

  function tag(href, label) { return '<a class="tag" href="' + href + '">' + label + '</a>'; }
  function phase(color, n, title, text) {
    return '<div class="phase"><div class="d" style="background:' + color + '">' + n + '</div><b>' + title + '</b><p>' + text + '</p></div>';
  }

  $('#toc').innerHTML = SECTIONS.map(function (s) { return '<a href="#' + s.id + '">' + s.title.replace(/^\d+\.\s*/, '') + '</a>'; }).join('');
  $('#roadmap').innerHTML = SECTIONS.map(function (s) { return '<div class="sec" id="' + s.id + '"><h2>' + s.title + '</h2>' + s.html + '</div>'; }).join('');

  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
