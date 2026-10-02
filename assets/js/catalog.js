/* ============================================================
   3DMP Service · каталог приложений сервиса (источник правды)
   Хаб (index.html) строит список приложений отсюда.
   Новое приложение: добавить запись и создать apps/<id>/.
   guest:true  — доступно без входа;
   guest:false — требует авторизации (хаб перенаправит в apps/auth/).
   ============================================================ */
window.AppCatalog = {
  version: '0.6',
  updated: '02.10.2026',
  apps: [
    { id: 'auth', icon: '🔐', title: 'Вход', desc: 'Логин и пароль (без email).', href: 'apps/auth/index.html', guest: true },
    { id: 'eco', icon: '🌐', title: 'Прототипы экосистемы', desc: '72 приложения: клиенты, сотрудники, партнёры, платформа (демо).', href: 'eco/index.html', guest: true },
    { id: 'dashboard', icon: '📊', title: 'Личный кабинет', desc: 'Профиль, роль и модули.', href: 'apps/dashboard/index.html', guest: false },
    { id: 'supplier', icon: '📦', title: 'Портал закупок (поставщик)', desc: 'Витрина закупок, карточка, подача предложения, мои КП.', href: 'apps/supplier/index.html', guest: false },
    { id: 'admin', icon: '🛡', title: 'Администрирование', desc: 'Пользователи и роли сервиса (только для admin).', href: 'apps/admin/index.html', guest: false, roles: ['admin'] }
  ]
};
