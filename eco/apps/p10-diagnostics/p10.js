/* ============================================================
   P10 · Диагностика и self-test
   проверка каталога, модулей и данных; dev-режим и инструменты
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var screens = AppRouter.create({
    onShow: function () { window.scrollTo(0, 0); },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function T(name, ok, detail, warn) { return { name: name, ok: ok, detail: detail || '', warn: !!warn }; }

  function runTests() {
    var res = [];
    var C = window.AppCatalog;
    res.push(T('Каталог загружен', !!C, C ? ('версия ' + C.version) : 'AppCatalog не найден'));
    if (C) {
      res.push(T('Приложений в каталоге', C.countApps() > 0, C.countApps() + ' шт'));
      res.push(T('Группы каталога', C.countGroups() > 0, C.countGroups() + ' групп'));
      var ids = {}, dup = [];
      C.groups.forEach(function (g) { g.apps.forEach(function (a) { if (ids[a.id]) dup.push(a.id); ids[a.id] = 1; }); });
      res.push(T('Уникальность ID приложений', dup.length === 0, dup.length ? ('дубли: ' + dup.join(', ')) : 'все уникальны'));
      var bad = [];
      C.groups.forEach(function (g) { g.apps.forEach(function (a) { if (!/^apps\/[a-z0-9-]+\/index\.html$/.test(a.href)) bad.push(a.id); }); });
      res.push(T('Формат ссылок каталога', bad.length === 0, bad.length ? ('проблемы: ' + bad.join(', ')) : 'корректны'));
    }
    res.push(T('Гид по системе (guide.js)', !!window.openGuide, window.openGuide ? 'подключён' : 'нет'));
    res.push(T('Тема (theme.js)', !!window.toggleTheme, window.toggleTheme ? 'подключена' : 'нет'));
    res.push(T('Единый слой (store.js)', !!window.AppData, window.AppData ? 'AppData доступен' : 'нет'));
    res.push(T('Роли (auth.js)', !!window.AppAuth, window.AppAuth ? 'AppAuth доступен' : 'нет'));
    res.push(T('Тема интерфейса', true, (document.documentElement.getAttribute('data-theme') || 'light') === 'dark' ? 'тёмная' : 'светлая'));
    res.push(T('Масштаб шрифта', !!window.getFontScale, (window.getFontScale ? getFontScale() : 100) + '%'));
    if (C) res.push(T('Версия каталога', true, C.version));
    if (window.AppData) {
      var sz = { small: 'малое', medium: 'среднее', large: 'крупное' }[AppData.settings.get('orgSize', 'medium')] || 'среднее';
      res.push(T('Размер предприятия', true, sz));
    }

    if (window.AppData) {
      var logged = AppData.profile.isLogged();
      res.push(T('Профиль пользователя', true, logged ? (AppData.profile.get().company || 'задан') : 'не задан (демо)', !logged));
      res.push(T('Заявки (единый слой)', true, AppData.requests.all().length + ' шт'));
      res.push(T('Команда клиента', true, AppData.team.all().length + ' сотрудников'));
      res.push(T('Контакты CRM', true, AppData.contacts.all().length + ' контактов'));
      res.push(T('Проблемы (эскалация)', true, AppData.problems.open().length + ' открыто, ' + AppData.problems.critical().length + ' критичных'));
      res.push(T('Журнал аудита', true, AppData.log.all().length + ' записей'));
      var flags = AppData.settings.get('flags', {});
      var off = Object.keys(flags).filter(function (k) { return flags[k] === false; });
      res.push(T('Feature flags', true, off.length ? ('выключено: ' + off.join(', ')) : 'все включены', off.length > 0));
      res.push(T('Dev-режим', true, AppData.settings.get('devMode', false) ? 'включён' : 'выключен'));
    }
    return res;
  }

  function render(res) {
    var ok = res.filter(function (r) { return r.ok && !r.warn; }).length;
    var warn = res.filter(function (r) { return r.warn; }).length;
    var fail = res.filter(function (r) { return !r.ok; }).length;
    var total = res.length || 1;
    var score = Math.round(ok / total * 100);
    $('#scoreVal').textContent = score + '%';
    $('#scoreBar').style.width = score + '%';
    $('#scoreBar').style.background = fail ? 'linear-gradient(135deg,#b91c1c,#ef4444)' : warn ? 'linear-gradient(135deg,#b45309,#f59e0b)' : '';
    $('#scoreHint').textContent = 'OK: ' + ok + ' · предупреждений: ' + warn + ' · ошибок: ' + fail + ' из ' + res.length;
    $('#tstCount').textContent = res.length + ' проверок';
    $('#tstList').innerHTML = res.map(function (r) {
      var icon = !r.ok ? '❌' : r.warn ? '⚠️' : '✅';
      return '<div class="tst"><div><span class="s">' + icon + '</span> ' + r.name + (r.detail ? ' <span class="faint" style="font-size:.74rem;">— ' + r.detail + '</span>' : '') + '</div><span class="badge ' + (!r.ok ? 'danger' : r.warn ? 'warning' : 'success') + '">' + (!r.ok ? 'ошибка' : r.warn ? 'внимание' : 'ok') + '</span></div>';
    }).join('');
  }

  function run() { var res = runTests(); render(res); App.toast('Проверка завершена'); }

  // dev-режим
  function renderDev() { $('#devSwitch').classList.toggle('on', !!AppData.settings.get('devMode', false)); }
  $('#devSwitch').addEventListener('click', function () {
    var on = !AppData.settings.get('devMode', false);
    AppData.settings.set('devMode', on); renderDev();
    AppData.log.add({ action: 'Dev-режим', detail: on ? 'включён' : 'выключен' });
    App.toast('Dev-режим ' + (on ? 'включён' : 'выключен'));
  });

  $('#runBtn').addEventListener('click', run);
  $('#seedProblems').addEventListener('click', function () {
    AppData.problems.add({ title: 'Тестовая проблема: контрольная проверка', source: 'P10', level: 'Средний', owner: 'Тест', due: '—', detail: 'Создана из диагностики.' });
    App.toast('Тестовая проблема создана'); run();
  });
  $('#resetFlags').addEventListener('click', function () { AppData.settings.set('flags', {}); App.toast('Feature flags сброшены'); run(); });
  $('#seedData').addEventListener('click', function () {
    if (!AppData.profile.isLogged()) AppData.profile.set({ company: 'ООО «Демо-Клиент»', role: 'client' });
    AppData.contacts.add({ name: 'Демо-контакт', phone: '+7 000 000-00-00', email: 'demo@3dmp.ru' });
    AppData.team.add({ name: 'Демо-сотрудник', role: 'Инженер', functions: ['orders', 'docs'], status: 'Активен' });
    App.toast('Демо-данные добавлены'); run();
  });
  $('#resetAll').addEventListener('click', function () {
    Object.keys(localStorage).filter(function (k) { return k.indexOf('3dmp:') === 0; }).forEach(function (k) { localStorage.removeItem(k); });
    App.toast('Все демо-данные сброшены'); run();
  });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderDev(); run();
})();
