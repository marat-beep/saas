/* ============================================================
   A14 · CRM клиента и делегирование доступов
   контакты (простая CRM) + команда с правами по функциям + заявки
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  // функции, которые клиент может делегировать сотрудникам
  var FUNCTIONS = [
    { id: 'calc', label: 'Расчёты и подбор', apps: ['A1', 'A2'] },
    { id: 'orders', label: 'Заказы и статусы', apps: ['A3'] },
    { id: 'docs', label: 'Документы и КД', apps: ['A9'] },
    { id: 'procure', label: 'Закупки', apps: ['A7'] },
    { id: 'service', label: 'Сервис и ремонт', apps: ['A4'] },
    { id: 'measure', label: 'Измерения', apps: ['A10'] },
    { id: 'special', label: 'Спец-технологии', apps: ['A8'] },
    { id: 'reverse', label: 'Реверс-инжиниринг', apps: ['A6'] }
  ];

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's2'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Табы ---------- */
  $('#tabs').addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    $$('button', this).forEach(function (x) { x.classList.toggle('active', x === b); });
    var t = b.dataset.t;
    $('#tab-contacts').classList.toggle('hidden', t !== 'contacts');
    $('#tab-team').classList.toggle('hidden', t !== 'team');
    $('#tab-req').classList.toggle('hidden', t !== 'req');
    $('#tab-log').classList.toggle('hidden', t !== 'log');
    if (t === 'req') renderRequests();
    if (t === 'log') renderLog();
  });

  /* ---------- Контакты ---------- */
  ['cName', 'cPhone', 'cEmail'].forEach(function (id) { $('#' + id).addEventListener('input', checkContact); });
  function checkContact() { $('#addContact').disabled = !$('#cName').value.trim(); }
  $('#addContact').addEventListener('click', function () {
    var c = AppData.contacts.add({ name: $('#cName').value.trim(), phone: $('#cPhone').value.trim(), email: $('#cEmail').value.trim() });
    AppData.log.add({ action: 'Добавлен контакт', detail: $('#cName').value.trim() });
    $('#cName').value = ''; $('#cPhone').value = ''; $('#cEmail').value = '';
    $('#addContact').disabled = true; renderContacts(); App.toast('Контакт добавлен');
  });

  function renderContacts() {
    var list = AppData.contacts.all();
    $('#ctCount').textContent = list.length + ' контактов';
    $('#ctList').innerHTML = list.length ? list.map(function (c) {
      return '<div class="contact" data-id="' + c.id + '"><div><div style="font-weight:600;font-size:.84rem;">' + c.name + '</div><div class="faint" style="font-size:.68rem;">' + [c.phone, c.email].filter(Boolean).join(' · ') + '</div></div><span style="color:var(--accent-600);font-weight:700;font-size:.76rem;">Карточка →</span></div>';
    }).join('') : '<div class="callout info"><span class="ci">👥</span><div>Контактов пока нет. Добавьте первого.</div></div>';
    $$('#ctList .contact').forEach(function (el) {
      el.addEventListener('click', function () {
        openCard(AppData.contacts.all().filter(function (x) { return x.id === el.dataset.id; })[0]);
      });
    });
  }

  /* ---------- Команда и доступы ---------- */
  ['mName'].forEach(function (id) { $('#' + id).addEventListener('input', checkMember); });
  function checkMember() { $('#addMember').disabled = !$('#mName').value.trim(); }
  $('#addMember').addEventListener('click', function () {
    var name = $('#mName').value.trim();
    var code = 'INV-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    AppData.team.add({ name: name, role: $('#mRole').value, functions: [], status: 'Приглашён', invite: code });
    AppData.log.add({ action: 'Приглашён сотрудник', detail: name + ' (' + code + ')' });
    $('#mName').value = ''; $('#addMember').disabled = true; renderTeam();
    App.toast('Приглашение ' + code + ' создано');
  });

  function renderTeam() {
    var list = AppData.team.all();
    $('#tmCount').textContent = list.length + ' сотрудников';
    if (!list.length) { $('#tmList').innerHTML = '<div class="callout info"><span class="ci">🔑</span><div>Сотрудников нет. Добавьте и выдайте доступы по функциям.</div></div>'; return; }
    $('#tmList').innerHTML = list.map(function (m) {
      var chips = FUNCTIONS.map(function (f) {
        var on = (m.functions || []).indexOf(f.id) >= 0;
        return '<span class="fn' + (on ? ' on' : '') + '" data-m="' + m.id + '" data-f="' + f.id + '">' + f.label + '</span>';
      }).join('');
      var st = m.status === 'Активен' ? 'success' : 'warning';
      return '<div class="member"><div class="mh"><div><div style="font-weight:700;font-size:.86rem;">' + m.name + '</div><div class="faint" style="font-size:.7rem;">' + m.role + ' · доступов: ' + (m.functions || []).length + ' из ' + FUNCTIONS.length + (m.invite ? ' · код ' + m.invite : '') + '</div></div><span class="badge ' + st + '">' + (m.status || 'Приглашён') + '</span></div><div>' + chips + '</div><div class="row between mt-8"><span class="faint" style="font-size:.68rem;">Отметьте функции доступа</span><div><button class="btn btn-ghost btn-sm" data-act="' + m.id + '">' + (m.status === 'Активен' ? 'Заблокировать' : 'Активировать') + '</button><button class="btn btn-ghost btn-sm" data-del="' + m.id + '">Удалить</button></div></div></div>';
    }).join('');
    $$('#tmList .fn').forEach(function (el) {
      el.addEventListener('click', function () {
        var id = el.dataset.m, fid = el.dataset.f;
        var m = AppData.team.all().filter(function (x) { return x.id === id; })[0];
        var fns = (m.functions || []).slice();
        var i = fns.indexOf(fid); if (i >= 0) fns.splice(i, 1); else fns.push(fid);
        AppData.team.update(id, { functions: fns });
        var f = FUNCTIONS.filter(function (x) { return x.id === fid; })[0];
        AppData.log.add({ action: (i >= 0 ? 'Снят доступ' : 'Выдан доступ'), detail: m.name + ': ' + (f ? f.label : fid) });
        renderTeam();
      });
    });
    $$('#tmList [data-del]').forEach(function (b) {
      b.addEventListener('click', function () {
        var m = AppData.team.all().filter(function (x) { return x.id === b.dataset.del; })[0];
        AppData.team.remove(b.dataset.del);
        if (m) AppData.log.add({ action: 'Удалён сотрудник', detail: m.name });
        renderTeam();
      });
    });
    $$('#tmList [data-act]').forEach(function (b) {
      b.addEventListener('click', function () {
        var m = AppData.team.all().filter(function (x) { return x.id === b.dataset.act; })[0];
        var ns = m.status === 'Активен' ? 'Приглашён' : 'Активен';
        AppData.team.update(m.id, { status: ns });
        AppData.log.add({ action: ns === 'Активен' ? 'Активирован доступ' : 'Доступ заблокирован', detail: m.name });
        renderTeam();
      });
    });
  }

  /* ---------- Заявки ---------- */
  function renderRequests() {
    var reqs = AppData.requests.all();
    $('#rqCount').textContent = reqs.length + ' заявок';
    $('#rqList').innerHTML = reqs.length ? reqs.map(function (r) {
      return '<div class="card accent-left mb-8"><div class="row between"><span class="faint" style="font-family:var(--mono);font-size:.7rem;">' + r.id + ' · ' + AppData.sourceTitle(r.source) + '</span><span class="badge ' + (r.status === 'Новая' ? 'warning' : 'info') + '">' + r.status + '</span></div><h3 class="mt-8" style="font-size:.86rem;">' + r.title + '</h3><div class="meta-row"><span>📅 ' + r.created + '</span><b>' + (r.amount ? money(r.amount) : '—') + '</b></div></div>';
    }).join('') : '<div class="callout info"><span class="ci">📝</span><div>Заявок нет. Оформите расчёт в клиентских приложениях.</div></div>';
  }

  /* ---------- Журнал ---------- */
  function renderLog() {
    var list = AppData.log.all();
    $('#lgCount').textContent = list.length + ' записей';
    $('#lgList').innerHTML = list.length ? list.map(function (e) {
      return '<div class="row between" style="padding:9px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><div><div style="font-weight:600;">' + e.action + '</div><div class="faint" style="font-size:.68rem;">' + e.who + ' · ' + e.date + '</div></div><span class="muted" style="text-align:right;">' + (e.detail || '') + '</span></div>';
    }).join('') : '<div class="callout info"><span class="ci">🧾</span><div>Журнал пуст.</div></div>';
  }

  /* ---------- Единая карточка клиента ---------- */
  function row(k, v) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b>' + v + '</b></div>'; }
  function openCard(c) {
    if (!c) return;
    var profile = AppData.profile.get() || {};
    var company = profile.company || '—';
    $('#cardId').textContent = c.id;
    $('#cardName').textContent = c.name;
    $('#cardContacts').innerHTML = ([c.phone, c.email].filter(Boolean).map(function (x) { return '<span class="tag">' + x + '</span>'; }).join('')) || '<span class="tag">нет контактных данных</span>';
    var reqs = AppData.requests.all().filter(function (r) {
      return (company !== '—' && r.customer === company) || (r.title && r.title.toLowerCase().indexOf((c.name || '').toLowerCase()) >= 0);
    });
    if (!reqs.length) reqs = AppData.requests.all();
    var orders = App.Store.get('orders', []);
    $('#cardSummary').innerHTML = row('Компания', company) + row('Заявок', reqs.length) + row('Заказов', orders.length) + row('Сумма заявок', money(reqs.reduce(function (a, r) { return a + (r.amount || 0); }, 0)));
    $('#cardRequests').innerHTML = reqs.length ? reqs.map(function (r) {
      return '<div class="row between" style="padding:7px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><span>' + r.id + ' · ' + r.title + '</span><b>' + (r.amount ? money(r.amount) : '—') + '</b></div>';
    }).join('') : '<div class="faint" style="font-size:.8rem;">Заявок нет.</div>';
    $('#cardOrders').innerHTML = orders.length ? orders.slice(0, 8).map(function (o) {
      return '<div class="row between" style="padding:7px 0;border-bottom:1px solid var(--border-2);font-size:.8rem;"><span>' + o.number + ' · ' + o.title + '</span><b>' + (o.amount ? money(o.amount) : '—') + '</b></div>';
    }).join('') : '<div class="faint" style="font-size:.8rem;">Заказов нет.</div>';
    screens.go('s3');
  }

  $('#toCrm').addEventListener('click', function () { screens.replace('s1'); });
  $('#backCrm').addEventListener('click', function () { screens.go('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#backBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderContacts(); renderTeam();
})();
