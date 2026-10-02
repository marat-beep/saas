/* ============================================================
   3DMP Service · apps/auth — вход, регистрация, сброс пароля
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI;
  var $ = ui.qs;

  var mode = 'in';
  var DASH = '../dashboard/index.html';

  function msg(text, kind) {
    var el = $('#msg');
    el.className = 'msg show ' + (kind || 'info');
    el.textContent = text;
  }
  function clearMsg() { $('#msg').className = 'msg'; $('#msg').textContent = ''; }
  function busy(on, label) {
    var b = $('#submit');
    b.disabled = on;
    b.textContent = on ? 'Подождите…' : (mode === 'in' ? 'Войти' : 'Зарегистрироваться');
  }

  function setMode(next) {
    mode = next;
    ui.qsa('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.mode === mode); });
    $('#confirmWrap').classList.toggle('hidden', mode !== 'up');
    $('#password').setAttribute('autocomplete', mode === 'in' ? 'current-password' : 'new-password');
    $('#submit').textContent = mode === 'in' ? 'Войти' : 'Зарегистрироваться';
    clearMsg();
  }
  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    setMode(b.dataset.mode);
  });

  function ensureClient() {
    if (!window.SB) {
      msg(window.SB_ERROR || 'Клиент Supabase не создан. Проверьте assets/js/config.js', 'err');
      return false;
    }
    return true;
  }

  $('#form').addEventListener('submit', function (e) {
    e.preventDefault();
    if (!ensureClient()) return;
    var email = $('#email').value.trim();
    var pass = $('#password').value;
    if (!email || !pass) { msg('Заполните email и пароль.', 'err'); return; }

    if (mode === 'up') {
      if (pass.length < 6) { msg('Пароль — не короче 6 символов.', 'err'); return; }
      if (pass !== $('#password2').value) { msg('Пароли не совпадают.', 'err'); return; }
      busy(true);
      window.SB.auth.signUp({ email: email, password: pass }).then(function (res) {
        busy(false);
        if (res.error) { msg(translate(res.error.message), 'err'); return; }
        if (res.data && res.data.session) { msg('Аккаунт создан. Переход в кабинет…', 'ok'); setTimeout(function () { location.href = DASH; }, 700); }
        else { msg('Аккаунт создан. Подтвердите email по ссылке из письма, затем войдите.', 'ok'); setMode('in'); }
      }).catch(function (err) { busy(false); msg(translate(err.message), 'err'); });
      return;
    }

    busy(true);
    window.SB.auth.signInWithPassword({ email: email, password: pass }).then(function (res) {
      busy(false);
      if (res.error) { msg(translate(res.error.message), 'err'); return; }
      msg('Вход выполнен. Переход в кабинет…', 'ok');
      setTimeout(function () { location.href = DASH; }, 500);
    }).catch(function (err) { busy(false); msg(translate(err.message), 'err'); });
  });

  $('#reset').addEventListener('click', function () {
    if (!ensureClient()) return;
    var email = $('#email').value.trim();
    if (!email) { msg('Укажите email для сброса пароля.', 'err'); return; }
    window.SB.auth.resetPasswordForEmail(email).then(function (res) {
      if (res.error) { msg(translate(res.error.message), 'err'); return; }
      msg('Письмо для сброса пароля отправлено на ' + email + '.', 'ok');
    }).catch(function (err) { msg(translate(err.message), 'err'); });
  });

  function translate(m) {
    var s = String(m || '');
    if (/Invalid login credentials/i.test(s)) return 'Неверный email или пароль.';
    if (/Email not confirmed/i.test(s)) return 'Email не подтверждён — проверьте почту.';
    if (/User already registered/i.test(s)) return 'Пользователь с таким email уже зарегистрирован.';
    if (/Password should be at least/i.test(s)) return 'Пароль слишком короткий.';
    if (/rate limit|too many/i.test(s)) return 'Слишком много попыток, попробуйте позже.';
    return s || 'Ошибка. Попробуйте ещё раз.';
  }

  // Уже вошли? — сразу в кабинет.
  if (window.SB) {
    window.SB.auth.getSession().then(function (res) {
      var u = res && res.data && res.data.session && res.data.session.user;
      if (u) location.href = DASH;
    }).catch(function () {});
  }
})();
