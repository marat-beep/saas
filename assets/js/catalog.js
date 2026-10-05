/* ============================================================
   3DMP Service · каталог приложений сервиса (источник правды)
   Хаб (index.html) строит список приложений отсюда.
   Новое приложение: добавить запись и создать apps/<id>/.
   guest:true  — доступно без входа;
   guest:false — требует авторизации (хаб перенаправит в apps/auth/).
   ============================================================ */
window.AppCatalog = {
  version: '1.5',
  updated: '05.10.2026',
  apps: [
    { id: 'auth', icon: '🔐', title: 'Вход', desc: 'Логин и пароль (без email).', href: 'apps/auth/index.html', guest: true },
    { id: 'eco', icon: '🌐', title: 'Прототипы экосистемы', desc: '72 приложения: клиенты, сотрудники, партнёры, платформа (демо).', href: 'eco/index.html', guest: true },
    { id: 'orders', icon: '📥', title: 'Заявки', desc: 'Единый приём заявок из модулей и сервисов, статусы.', href: 'apps/orders/index.html', guest: false },
    { id: 'production', icon: '🏭', title: 'Производство', desc: 'Наряды и операции: план, факт, закрытие.', href: 'apps/production/index.html', guest: false, roles: ['admin', 'owner', 'manager'] },
    { id: 'procurement', icon: '🛒', title: 'Закупки', desc: 'Публикация закупок, приём КП, выбор победителя.', href: 'apps/procurement/index.html', guest: false, roles: ['admin', 'owner', 'manager'] },
    { id: 'warehouse', icon: '📦', title: 'Склад', desc: 'Материалы, приход/расход, контроль минимума.', href: 'apps/warehouse/index.html', guest: false, roles: ['admin', 'owner', 'manager'] },
    { id: 'bom', icon: '📐', title: 'Спецификации', desc: 'Состав изделия (BOM): материалы и операции.', href: 'apps/bom/index.html', guest: false, roles: ['admin', 'owner', 'manager'] },
    { id: 'planning', icon: '🗓', title: 'Планирование', desc: 'Диаграмма Ганта и загрузка рабочих центров.', href: 'apps/planning/index.html', guest: false, roles: ['admin', 'owner', 'manager'] },
    { id: 'qc', icon: '✅', title: 'ОТК', desc: 'Чек-листы контроля, дефекты, решения.', href: 'apps/qc/index.html', guest: false, roles: ['admin', 'owner', 'manager'] },
    { id: 'passport', icon: '🪪', title: 'Паспорта изделий', desc: 'Цифровой паспорт изделия и QR-метка.', href: 'apps/passport/index.html', guest: false, roles: ['admin', 'owner', 'manager'] },
    { id: 'economics', icon: '💰', title: 'Экономика', desc: 'KPI, себестоимость заявок, нормочас.', href: 'apps/economics/index.html', guest: false, roles: ['admin', 'owner', 'manager'] },
    { id: 'reports', icon: '🧾', title: 'Отчёты и экспорт', desc: 'Выгрузки PDF/DOC/CSV/JSON и сводные отчёты.', href: 'apps/reports/index.html', guest: false, roles: ['admin', 'owner', 'manager'] },
    { id: 'org', icon: '🏢', title: 'Организация', desc: 'Тариф, пользователи и доступные модули.', href: 'apps/org/index.html', guest: false, roles: ['admin', 'owner', 'manager'] },
    { id: 'dashboard', icon: '📊', title: 'Личный кабинет', desc: 'Профиль, роль и модули.', href: 'apps/dashboard/index.html', guest: false },
    { id: 'supplier', icon: '📦', title: 'Портал закупок (поставщик)', desc: 'Витрина закупок, карточка, подача предложения, мои КП.', href: 'apps/supplier/index.html', guest: false },
    { id: 'admin', icon: '🛡', title: 'Администрирование', desc: 'Пользователи и роли сервиса (только для admin).', href: 'apps/admin/index.html', guest: false, roles: ['admin'] }
  ]
};
