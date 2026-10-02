/* ============================================================
   3DMP Service · каталог приложений сервиса (источник правды)
   Хаб (index.html) строит список приложений отсюда.
   Новое приложение: добавить запись и создать apps/<id>/.
   guest:true  — доступно без входа;
   guest:false — требует авторизации (хаб перенаправит в apps/auth/).
   ============================================================ */
window.AppCatalog = {
  version: '0.3',
  updated: '02.10.2026',
  apps: [
    { id: 'auth', icon: '🔐', title: 'Вход и регистрация', desc: 'Аккаунт, вход, восстановление пароля.', href: 'apps/auth/index.html', guest: true },
    { id: 'dashboard', icon: '📊', title: 'Личный кабинет', desc: 'Профиль, организации (тенанты), роли.', href: 'apps/dashboard/index.html', guest: false },
    { id: 'supplier', icon: '📦', title: 'Портал закупок (поставщик)', desc: 'Витрина закупок, карточка, подача предложения, мои КП.', href: 'apps/supplier/index.html', guest: false }
  ]
};
