/* ============================================================
   3DMP Service · apps/auth — вход по логину и паролю
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs;

  function msg(text, kind) {
    var e = $('#msg');
    e.className = 'msg show ' + (kind || 'info');
    e.textContent = text;
  }

  if (window.Auth && window.Auth.isLogged()) {
    location.href = '../dashboard/index.html';
    return;
  }

  $('#form').addEventListener('submit', function (e) {
    e.preventDefault();
    var login = $('#login').value.trim();
    var pass = $('#password').value;
    if (!login || !pass) { msg('Введите логин и пароль.', 'err'); return; }

    var b = $('#submit');
    b.disabled = true; b.textContent = 'Проверка…';

    window.Auth.login(login, pass).then(function (row) {
      b.disabled = false; b.textContent = 'Войти';
      if (!row) { msg('Неверный логин или пароль.', 'err'); return; }
      msg('Вход выполнен. Переход…', 'ok');
      setTimeout(function () { location.href = '../dashboard/index.html'; }, 400);
    }).catch(function (err) {
      b.disabled = false; b.textContent = 'Войти';
      msg('Ошибка: ' + (err.message || err), 'err');
    });
  });
})();
