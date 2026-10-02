/* ============================================================
   P2 · App Builder — конструктор отраслевых приложений
   каталог приложений → редактор → публикация
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var MODULES = ['Калькулятор', 'Кабинет заказчика', 'Канбан', 'ОТК', 'Паспорт изделия', 'Закупки', 'Поставщики', 'Партнёры', 'База знаний', 'Вакансии', 'Документация', 'Бережливое'];
  var COMPONENTS = ['Форма', 'Таблица', 'Канбан', 'Календарь', 'Дашборд', 'Чат', 'Уведомления', 'Файлы', 'Оплата', 'Карта'];

  var APPS = [
    { name: 'Снабжение завода', icon: '📦', modules: ['Закупки', 'Поставщики'], comps: ['Таблица', 'Форма', 'Уведомления'] },
    { name: 'Цех: заказы', icon: '🛠', modules: ['Канбан', 'ОТК'], comps: ['Канбан', 'Дашборд'] },
    { name: 'Продажи и КП', icon: '📊', modules: ['Калькулятор', 'Кабинет заказчика'], comps: ['Форма', 'Чат'] }
  ];

  var selectedModules = [], selectedComps = [];

  var screens = AppRouter.create({
    onShow: function (s) { window.scrollTo(0, 0); },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderApps() {
    $('#appGrid').innerHTML = APPS.map(function (a, i) {
      return '<div class="app-tile" data-i="' + i + '"><div class="ti">' + a.icon + '</div><div class="grow"><div style="font-weight:700;font-size:.92rem;">' + a.name + '</div><div class="faint" style="font-size:.72rem;">' + a.modules.length + ' модулей · ' + a.comps.length + ' компонентов</div></div><span class="badge success">Опубликовано</span></div>';
    }).join('');
    $$('#appGrid .app-tile').forEach(function (t) {
      t.addEventListener('click', function () {
        var a = APPS[parseInt(t.dataset.i, 10)];
        $('#appName').value = a.name; $('#appIcon').value = a.icon;
        selectedModules = a.modules.slice(); selectedComps = a.comps.slice();
        renderEditor(); screens.go('s2');
      });
    });
  }

  function renderEditor() {
    $('#moduleChips').innerHTML = MODULES.map(function (m) {
      return '<div class="chip-btn' + (selectedModules.indexOf(m) >= 0 ? ' on' : '') + '" data-m="' + m + '">' + m + '</div>';
    }).join('');
    $('#compChips').innerHTML = COMPONENTS.map(function (c) {
      return '<div class="chip-btn' + (selectedComps.indexOf(c) >= 0 ? ' on' : '') + '" data-c="' + c + '">' + c + '</div>';
    }).join('');
    $('#pvHead').textContent = $('#appIcon').value + ' ' + ($('#appName').value || 'Приложение');
    $('#pvModCount').textContent = selectedModules.length;
    $('#pvCompCount').textContent = selectedComps.length;
    $('#pvBody').innerHTML = (selectedComps.length ? selectedComps : ['Выберите компоненты']).slice(0, 5).map(function (c) {
      return '<div style="background:var(--surface-2);border:1px solid var(--border);border-radius:10px;padding:10px;margin-bottom:8px;font-size:.8rem;">▦ ' + c + (selectedModules[0] ? ' · ' + selectedModules[0] : '') + '</div>';
    }).join('');
  }

  $('#moduleChips').addEventListener('click', function (e) {
    var c = e.target.closest('.chip-btn'); if (!c) return;
    var m = c.dataset.m, i = selectedModules.indexOf(m);
    if (i >= 0) selectedModules.splice(i, 1); else selectedModules.push(m);
    renderEditor();
  });
  $('#compChips').addEventListener('click', function (e) {
    var c = e.target.closest('.chip-btn'); if (!c) return;
    var m = c.dataset.c, i = selectedComps.indexOf(m);
    if (i >= 0) selectedComps.splice(i, 1); else selectedComps.push(m);
    renderEditor();
  });
  $('#appName').addEventListener('input', renderEditor);
  $('#appIcon').addEventListener('change', renderEditor);

  $('#createBtn').addEventListener('click', function () {
    $('#appName').value = 'Новое приложение'; $('#appIcon').value = '📦';
    selectedModules = []; selectedComps = []; renderEditor(); screens.go('s2');
  });
  $('#cancelBtn').addEventListener('click', function () { screens.back(); });
  $('#publishBtn').addEventListener('click', function () {
    var name = $('#appName').value.trim() || 'Приложение';
    APPS.push({ name: name, icon: $('#appIcon').value, modules: selectedModules.slice(), comps: selectedComps.slice() });
    $('#pubId').textContent = 'APP-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    renderApps(); screens.go('s3');
    App.toast('Приложение «' + name + '» опубликовано');
  });
  $('#backApps').addEventListener('click', function () { renderApps(); screens.replace('s1'); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderApps();
})();
