/* ============================================================
   A4 · Заявка на сервис
   тип → описание+фото → срочность/SLA → тикет
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var TYPES = [
    { id: 'emergency', icon: '🚨', title: 'Аварийный ремонт', desc: 'Станок встал, простой', sla: 'Реакция 1 ч · выезд 4 ч' },
    { id: 'maintenance', icon: '🧰', title: 'Плановое ТО', desc: 'Регламент, профилактика', sla: 'Реакция 1 раб. день' },
    { id: 'consult', icon: '💬', title: 'Консультация', desc: 'Вопрос по технологии/режимам', sla: 'Реакция 2 ч' },
    { id: 'diagnostic', icon: '🔬', title: 'Диагностика', desc: 'Выявление причин', sla: 'Реакция 4 ч' }
  ];
  var PRIORITIES = [
    { id: 'normal', icon: '🟢', title: 'Обычная', desc: 'В порядке очереди', k: 1 },
    { id: 'high', icon: '🟠', title: 'Высокая', desc: 'Приоритетная обработка', k: 1.5 },
    { id: 'critical', icon: '🔴', title: 'Критичная', desc: 'Останов производства', k: 2 }
  ];

  var draft = { type: null, equipment: '', desc: '', photos: [], prio: null, name: '', phone: '' };
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1' || s.id === 's4'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Тип ---------- */
  $('#typeOptions').innerHTML = TYPES.map(function (t) {
    return '<div class="option" data-id="' + t.id + '"><span class="opt-icon">' + t.icon + '</span><span class="opt-title">' + t.title + '</span><span class="opt-desc">' + t.desc + ' · ' + t.sla + '</span></div>';
  }).join('');
  $('#typeOptions').addEventListener('click', function (e) {
    var el = e.target.closest('.option'); if (!el) return;
    $$('.option', this).forEach(function (o) { o.classList.toggle('selected', o === el); });
    draft.type = el.dataset.id; $('#toS2').disabled = false;
  });

  /* ---------- Описание ---------- */
  $('#equipment').addEventListener('input', function () { draft.equipment = this.value; });
  $('#desc').addEventListener('input', function () { draft.desc = this.value; });
  $('#photoZone').addEventListener('click', function () {
    draft.photos.push('photo_' + Math.floor(100 + Math.random() * 900) + '.jpg');
    renderPhotos();
  });
  function renderPhotos() {
    $('#photoList').innerHTML = draft.photos.map(function (p, i) {
      return '<div class="row between" style="background:var(--surface);border:1px solid var(--border);border-radius:var(--r-sm);padding:8px 12px;margin-bottom:6px;"><span>🖼 ' + p + '</span><button class="btn btn-ghost btn-sm" data-rm="' + i + '">Убрать</button></div>';
    }).join('');
    $$('#photoList [data-rm]').forEach(function (b) {
      b.addEventListener('click', function () { draft.photos.splice(parseInt(b.dataset.rm, 10), 1); renderPhotos(); });
    });
  }

  /* ---------- Срочность ---------- */
  $('#prioOptions').innerHTML = PRIORITIES.map(function (p) {
    return '<div class="option" data-id="' + p.id + '"><span class="opt-icon">' + p.icon + '</span><span class="opt-title">' + p.title + '</span><span class="opt-desc">' + p.desc + '</span></div>';
  }).join('');
  $('#prioOptions').addEventListener('click', function (e) {
    var el = e.target.closest('.option'); if (!el) return;
    $$('.option', this).forEach(function (o) { o.classList.toggle('selected', o === el); });
    draft.prio = el.dataset.id;
    var t = TYPES.find(function (x) { return x.id === draft.type; });
    var p = PRIORITIES.find(function (x) { return x.id === draft.prio; });
    $('#slaInfo').querySelector('div').textContent = (t ? t.sla : '') + ' · приоритет «' + (p ? p.title : '') + '»';
  });

  $('#contactName').addEventListener('input', function () { draft.name = this.value; });
  $('#contactPhone').addEventListener('input', function () { draft.phone = this.value; });

  /* ---------- Отправка ---------- */
  $('#submitBtn').addEventListener('click', function () {
    if (!draft.equipment.trim()) { App.toast('Укажите оборудование'); return; }
    if (!draft.desc.trim()) { App.toast('Опишите проблему'); return; }
    if (!draft.prio) { App.toast('Выберите срочность'); return; }
    if (!draft.name.trim() || !draft.phone.trim()) { App.toast('Заполните контакты'); return; }
    var t = TYPES.find(function (x) { return x.id === draft.type; });
    var p = PRIORITIES.find(function (x) { return x.id === draft.prio; });
    var ticket = App.randomTicket('SRV');
    App.Store.set('serviceTickets', (App.Store.get('serviceTickets', [])).concat([{ ticket: ticket, type: t.title, prio: p.title, created: App.today() }]));
    if (window.AppData) AppData.requests.add({ source: 'A4', title: t.title + ' — ' + draft.equipment, ref: ticket });
    $('#ticketNum').textContent = ticket;
    $('#slaCard').innerHTML =
      '<div class="row between"><span class="muted">Тип</span><b>' + t.title + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Оборудование</span><b style="text-align:right;">' + draft.equipment + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">Приоритет</span><b>' + p.title + '</b></div>' +
      '<div class="row between mt-8"><span class="muted">SLA</span><b style="color:var(--accent-700);">' + t.sla + '</b></div>';
    screens.go('s4');
    App.toast('Тикет ' + ticket + ' создан');
  });

  /* ---------- Навигация ---------- */
  $('#toS2').addEventListener('click', function () { screens.go('s2'); });
  $('#toS3').addEventListener('click', function () { screens.go('s3'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#newBtn').addEventListener('click', function () { location.reload(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
