/* ============================================================
   3DMP Service · apps/logistics — TMS (W23, 0172).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, carriers = [];
  var ST = { planned: 'Запланирован', in_transit: 'В пути', done: 'Выполнен', cancelled: 'Отменён' };
  function esc(v) { return ui.esc(v); }
  function msg(t, k) { var e = $('#m'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }
  function money(v) { return v == null ? '—' : (Number(v) || 0).toLocaleString('ru-RU', { maximumFractionDigits: 0 }) + ' ₽'; }
  function dd(v) { return v ? new Date(v).toLocaleDateString('ru-RU') : '—'; }
  function tbl(head, rows) { return '<div class="tbl-wrap"><table class="tbl"><thead><tr>' + head + '</tr></thead><tbody>' + rows + '</tbody></table></div>'; }

  function showTab(scr) { $$('#tabs button').forEach(function (b) { b.classList.toggle('active', b.dataset.scr === scr); }); $$('.screen').forEach(function (s) { s.classList.toggle('active', s.id === 'scr-' + scr); }); if (scr === 'ord') loadOrd(); else loadCar(); }
  $$('#tabs button').forEach(function (b) { b.addEventListener('click', function () { showTab(b.dataset.scr); }); });

  function loadKpi() { return rpc('app_tms_kpi', { p_token: token }).then(function (r) { var k = (r && r[0]) || {}; $('#kpis').innerHTML = cell('Перевозчиков', k.carriers || 0) + cell('Рейсов', k.orders || 0) + cell('Запланировано', k.planned || 0) + cell('В пути', k.in_transit || 0) + cell('Выполнено', k.done || 0) + cell('Стоимость', money(k.cost)); }); }
  function loadCarriersRef() { return rpc('app_carriers_list', { p_token: token }).then(function (r) { carriers = r || []; }).catch(function () { carriers = []; }); }

  function loadOrd() {
    return rpc('app_transport_list', { p_token: token, p_status: null }).then(function (r) {
      var list = r || [];
      $('#ord').innerHTML = list.length ? tbl('<th>№</th><th>Напр.</th><th>Контрагент</th><th>Маршрут</th><th>Даты</th><th>Перевозчик</th><th class="num">Стоимость</th><th>Статус</th><th></th>', list.map(function (x) {
        var a = '';
        if (x.status === 'planned') a = '<button class="act" data-st="in_transit" data-id="' + x.id + '">В путь</button>';
        else if (x.status === 'in_transit') a = '<button class="act" data-st="done" data-id="' + x.id + '">Выполнен</button>';
        return '<tr><td>' + esc(x.number || '') + '</td><td>' + (x.direction === 'in' ? 'вход' : 'выход') + '</td><td>' + esc(x.counterparty || '') + '</td><td>' + esc((x.from_loc || '') + ' → ' + (x.to_loc || '')) + '</td><td>' + dd(x.pickup_date) + '—' + dd(x.deliver_date) + '</td><td>' + esc(x.carrier || '') + '</td><td class="num">' + money(x.cost) + '</td><td>' + esc(ST[x.status] || x.status) + '</td><td>' + a + '</td></tr>';
      }).join('')) : '<span class="note">Рейсов нет.</span>';
      $$('#ord [data-st]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_transport_set_status', { p_token: token, p_id: b.dataset.id, p_status: b.dataset.st }).then(function () { loadOrd(); loadKpi(); }); }); });
    });
  }
  function carOpts() { return [{ value: '', label: '—' }].concat(carriers.map(function (c) { return { value: c.id, label: c.name }; })); }
  function ordForm() {
    ui.formDialog({ title: 'Заявка на перевозку', okText: 'Создать', size: 'lg', fields: [
      { name: 'number', label: 'Номер', type: 'text' }, { name: 'direction', label: 'Направление', type: 'select', options: [{ value: 'out', label: 'Исходящая' }, { value: 'in', label: 'Входящая' }] },
      { name: 'counterparty', label: 'Контрагент', type: 'text' }, { name: 'cargo', label: 'Груз', type: 'text' }, { name: 'weight', label: 'Вес, кг', type: 'number' },
      { name: 'from', label: 'Откуда', type: 'text' }, { name: 'to', label: 'Куда', type: 'text' },
      { name: 'pickup', label: 'Погрузка', type: 'date' }, { name: 'deliver', label: 'Доставка', type: 'date' },
      { name: 'carrier_id', label: 'Перевозчик', type: 'select', options: carOpts() }, { name: 'vehicle', label: 'ТС', type: 'text' }, { name: 'driver', label: 'Водитель', type: 'text' }, { name: 'cost', label: 'Стоимость, ₽', type: 'number' }
    ], values: { direction: 'out' } }).then(function (v) {
      if (!v) return;
      rpc('app_transport_save', { p_token: token, p_id: null, p_number: v.number || null, p_direction: v.direction, p_counterparty: v.counterparty || null, p_cargo: v.cargo || null, p_weight: v.weight ? Number(v.weight) : null, p_from: v.from || null, p_to: v.to || null, p_pickup: v.pickup || null, p_deliver: v.deliver || null, p_carrier_id: v.carrier_id || null, p_vehicle: v.vehicle || null, p_driver: v.driver || null, p_cost: v.cost ? Number(v.cost) : 0, p_note: null })
        .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadOrd(); loadKpi(); });
    });
  }
  function loadCar() {
    return rpc('app_carriers_list', { p_token: token }).then(function (r) {
      carriers = r || [];
      $('#car').innerHTML = carriers.length ? tbl('<th>Перевозчик</th><th>ИНН</th><th>Контакт</th><th class="num">Тариф</th><th>Активен</th><th></th>', carriers.map(function (c) { return '<tr><td><b>' + esc(c.name) + '</b></td><td>' + esc(c.inn || '') + '</td><td>' + esc(c.contact || '') + '</td><td class="num">' + (c.rate || 0) + '</td><td>' + (c.active ? 'да' : 'нет') + '</td><td><button class="act danger" data-del="' + c.id + '">Удалить</button></td></tr>'; }).join('')) : '<span class="note">Перевозчиков нет.</span>';
      $$('#car [data-del]').forEach(function (b) { b.addEventListener('click', function () { if (!confirm('Удалить?')) return; rpc('app_carrier_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadCar(); loadKpi(); }); }); });
    });
  }
  function carForm() { ui.formDialog({ title: 'Перевозчик', okText: 'Сохранить', fields: [{ name: 'name', label: 'Название', type: 'text', required: true }, { name: 'inn', label: 'ИНН', type: 'text' }, { name: 'contact', label: 'Контакт', type: 'text' }, { name: 'rate', label: 'Тариф', type: 'number' }], values: {} }).then(function (v) { if (!v) return; rpc('app_carrier_save', { p_token: token, p_id: null, p_name: v.name, p_inn: v.inn || null, p_contact: v.contact || null, p_rate: v.rate ? Number(v.rate) : 0, p_active: true }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); loadCar(); loadKpi(); }); }); }

  $('#addOrd').addEventListener('click', ordForm);
  $('#addCar').addEventListener('click', carForm);
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    loadCarriersRef().then(function () { loadKpi(); loadOrd(); });
  });
})();
