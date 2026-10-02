/* ============================================================
   P8 · Доступ и роли
   режим доступа, пользователи, матрица прав
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var GROUPS = [
    { id: 'clients', label: '👥 Клиенты' },
    { id: 'staff', label: '🏭 Сотрудники' },
    { id: 'partners', label: '🤝 Партнёры' },
    { id: 'platform', label: '🚀 Платформа' }
  ];

  var USERS = [
    { name: 'Иванов И.И.', login: 'ivanov@company.ru', role: 'client' },
    { name: 'Кузнецов А.', login: 'a.kuznetsov@3dmp.ru', role: 'staff' },
    { name: 'Смирнова О.', login: 'o.smirnova@3dmp.ru', role: 'staff' },
    { name: 'ООО «Гальваник»', login: 'partner@galvanik.ru', role: 'partner' },
    { name: 'Администратор', login: 'admin@3dmp.ru', role: 'admin' }
  ];

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderRoles() {
    $('#roleList').innerHTML = AppAuth.roles.map(function (r) {
      return '<div class="role-card' + (AppAuth.current() === r.id ? ' active' : '') + '" data-role="' + r.id + '"><span class="ri">' + r.icon + '</span><div class="grow"><b>' + r.label + '</b><span>' + r.desc + '</span></div>' + (AppAuth.current() === r.id ? '<span class="badge accent">активна</span>' : '') + '</div>';
    }).join('');
    $$('#roleList .role-card').forEach(function (c) {
      c.addEventListener('click', function () { AppAuth.set(c.dataset.role); renderRoles(); renderMatrix(); });
    });
  }

  function renderMatrix() {
    var head = '<tr><th>Группа</th>' + AppAuth.roles.map(function (r) { return '<th>' + r.icon + '<br>' + r.label + '</th>'; }).join('') + '</tr>';
    var body = GROUPS.map(function (g) {
      return '<tr><td>' + g.label + '</td>' + AppAuth.roles.map(function (r) {
        // вычисляем доступ для конкретной роли без смены текущей
        var ok = r.id === 'all' || r.id === 'admin' || ({ clients: ['client'], staff: ['staff'], partners: ['partner'], platform: [] }[g.id] || []).indexOf(r.id) >= 0;
        return '<td class="' + (ok ? 'yes' : 'no') + '">' + (ok ? '✓' : '—') + '</td>';
      }).join('') + '</tr>';
    }).join('');
    $('#matrix').innerHTML = head + body;
  }

  function renderDeleg() {
    var team = (window.AppData ? AppData.team.all() : []);
    $('#delegList').innerHTML = team.length ? team.map(function (m) {
      return '<div class="u-row"><div><div style="font-weight:600;font-size:.84rem;">' + m.name + '</div><div class="faint" style="font-size:.68rem;">' + m.role + ' · функций: ' + (m.functions || []).length + '</div></div><span class="badge ' + (m.status === 'Активен' ? 'success' : 'warning') + '">' + (m.status || 'Приглашён') + '</span></div>';
    }).join('') : '<div class="callout info"><span class="ci">👥</span><div>Делегирований нет. Настройте в A14 «CRM клиента и доступы».</div></div>';
  }

  function renderUsers() {
    $('#uCount').textContent = USERS.length + ' пользователей';
    $('#userList').innerHTML = USERS.map(function (u, i) {
      var opts = AppAuth.roles.map(function (r) { return '<option value="' + r.id + '"' + (u.role === r.id ? ' selected' : '') + '>' + r.label + '</option>'; }).join('');
      return '<div class="u-row"><div><div style="font-weight:600;font-size:.84rem;">' + u.name + '</div><div class="faint" style="font-size:.68rem;">' + u.login + '</div></div><select data-u="' + i + '" style="width:auto;padding:7px 10px;font-size:.78rem;">' + opts + '</select></div>';
    }).join('');
    $$('#userList select').forEach(function (sel) {
      sel.addEventListener('change', function () {
        USERS[parseInt(sel.dataset.u, 10)].role = sel.value;
        App.toast('Роль пользователя обновлена');
      });
    });
  }

  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#backBtn').addEventListener('click', function () { screens.back(); });

  renderRoles(); renderMatrix(); renderUsers(); renderDeleg();
})();
