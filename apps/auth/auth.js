/* ============================================================
   3DMP Service · apps/auth — вход по логину и паролю.
   Плитки аудиторий (K.2) + маршрутизация по роли.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa;

  function msg(text, kind) { var e = $('#msg'); e.className = 'msg show ' + (kind || 'info'); e.textContent = text; }
  function landing(role) {
    if (role === 'admin') return '../panel/index.html';   // администратор платформы → пульт (SaaS)
    if (role === 'client') return '../client/index.html'; // заказчик → кабинет
    return '../dashboard/index.html';                     // сотрудник/админ организации → кабинет
  }

  if (window.Auth && window.Auth.isLogged() && window.Auth.role && window.Auth.role()) {
    location.href = landing(window.Auth.role());
    return;
  }

  /* Плитки аудиторий: задают подсказку и предзаполняют демо-логин */
  var hint = { employee: 'Сотрудник — вход в рабочее место.', org_admin: 'Администратор организации — пользователи, роли, бренд.', saas_admin: 'Администратор SaaS — платформа и организации.', client: 'Заказчик — кабинет заказчика.' };
  $$('#atiles .atile').forEach(function (b) {
    b.addEventListener('click', function () {
      $$('#atiles .atile').forEach(function (z) { z.classList.remove('on'); });
      b.classList.add('on');
      var l = b.dataset.login || '';
      $('#login').value = l; $('#password').value = l; // демо: пароль = логин
      $('#entryHint').textContent = 'Выбрано: ' + hint[b.dataset.a] + (l ? ' Демо-логин: ' + l : '');
      $('#login').focus();
    });
  });

  $('#form').addEventListener('submit', function (e) {
    e.preventDefault();
    var login = $('#login').value.trim();
    var pass = $('#password').value;
    if (!login || !pass) { msg('Введите логин и пароль.', 'err'); return; }

    var b = $('#submit');
    b.disabled = true; b.textContent = 'Проверка…';

    window.Auth.login(login, pass).then(function (row) {
      b.disabled = false; b.textContent = 'Войти';
      if (!row) { msg(window.Auth.lastError || 'Неверный логин или пароль.', 'err'); return; }
      msg('Вход выполнен. Переход…', 'ok');
      var role = (row && row.role) || (window.Auth.role && window.Auth.role()) || '';
      setTimeout(function () { location.href = landing(role); }, 400);
    }).catch(function (err) {
      b.disabled = false; b.textContent = 'Войти';
      msg('Ошибка: ' + (err.message || err), 'err');
    });
  });
})();
