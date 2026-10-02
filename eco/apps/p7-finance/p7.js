/* ============================================================
   P7 · Финансы предприятия
   дашборд (экономика, ТБУ) → счета → фиксация оплаты
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var INVOICES = [
    { id: 'СЧ-2031', client: 'ООО «Привод»', contract: 'Д-142', amount: 486000, paid: 0, due: '18.10', status: 'partial' },
    { id: 'СЧ-2029', client: 'ЗАО «ТехноПарк»', contract: 'Д-141', amount: 312000, paid: 0, due: '12.10', status: 'overdue' },
    { id: 'СЧ-2026', client: 'ООО «АвтоПласт»', contract: 'Д-138', amount: 214500, paid: 214500, due: '30.09', status: 'paid' },
    { id: 'СЧ-2024', client: 'ООО «Металлист»', contract: 'Д-135', amount: 88000, paid: 44000, due: '05.10', status: 'partial' },
    { id: 'СЧ-2021', client: 'ИП Смирнов', contract: 'Д-119', amount: 132000, paid: 132000, due: '20.09', status: 'paid' }
  ];

  // сквозной сценарий: счета, созданные из CRM (B12)
  var linked = App.Store.get('linkedInvoices', []);
  linked.forEach(function (i) { if (!INVOICES.some(function (x) { return x.id === i.id; })) INVOICES.unshift(i); });

  var current = null;
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function renderDashboard() {
    var revenue = INVOICES.reduce(function (a, i) { return a + i.paid; }, 0);
    var debt = INVOICES.reduce(function (a, i) { return a + (i.amount - i.paid); }, 0);
    var margin = 34;
    $('#revenue').textContent = money(revenue);
    $('#revenueSub').textContent = 'Поступления · ' + INVOICES.filter(function (i) { return i.status === 'paid'; }).length + ' счетов закрыто';
    $('#stDebt').textContent = App.number(debt / 1000) + ' тыс.';
    $('#stMargin').textContent = margin + '%';
    $('#stKpi').textContent = '108%';

    var tbu = 2800000, rev = 1950000;
    $('#tbuRev').textContent = money(rev) + ' из ' + money(tbu);
    $('#tbuBar').style.width = Math.min(100, Math.round(rev / tbu * 100)) + '%';
    $('#tbuHint').textContent = rev >= tbu ? 'Выше точки безубыточности ✓' : ('До безубыточности: ' + money(tbu - rev));

    $('#invCount').textContent = INVOICES.length + ' счетов';
    $('#invList').innerHTML = INVOICES.map(function (i, idx) {
      var badge = i.status === 'paid' ? ['success', 'Оплачен'] : i.status === 'overdue' ? ['danger', 'Просрочен'] : ['warning', 'Частично'];
      return '<div class="inv" data-i="' + idx + '"><div class="grow"><div style="font-weight:600;font-size:.84rem;">' + i.id + ' · ' + i.client + '</div><div class="faint" style="font-size:.7rem;">' + i.contract + ' · до ' + i.due + '</div></div><div style="text-align:right;margin-right:10px;"><b>' + money(i.amount) + '</b><div class="faint" style="font-size:.68rem;">оплачено ' + money(i.paid) + '</div></div><span class="badge ' + badge[0] + '">' + badge[1] + '</span></div>';
    }).join('');
    $$('#invList .inv').forEach(function (el) { el.addEventListener('click', function () { openInv(parseInt(el.dataset.i, 10)); }); });
  }

  function openInv(idx) {
    current = INVOICES[idx];
    var i = current;
    $('#iNum').textContent = i.id + ' · ' + i.contract;
    var b = $('#iStatus'); b.textContent = i.status === 'paid' ? 'Оплачен' : i.status === 'overdue' ? 'Просрочен' : 'Частично'; b.className = 'badge ' + (i.status === 'paid' ? 'success' : i.status === 'overdue' ? 'danger' : 'warning');
    $('#iTitle').textContent = i.client;
    $('#iTags').innerHTML = '<span class="tag">📄 ' + i.contract + '</span><span class="tag">📅 до ' + i.due + '</span>';
    $('#iInfo').innerHTML =
      row('Сумма счёта', money(i.amount)) + row('Оплачено', money(i.paid)) + row('К доплате', money(i.amount - i.paid), true) + row('НДС 22%', money(i.amount * 0.22 / 1.22));
    $('#payBtn').disabled = i.status === 'paid';
    screens.go('s2');
  }
  function row(k, v, accent) { return '<div class="row between" style="padding:8px 0;border-bottom:1px solid var(--border-2);font-size:.82rem;"><span class="muted">' + k + '</span><b style="' + (accent ? 'color:var(--accent-700);' : '') + '">' + v + '</b></div>'; }

  $('#payBtn').addEventListener('click', function () {
    current.paid = current.amount; current.status = 'paid';
    $('#payNum').textContent = current.id;
    renderDashboard(); screens.go('s3');
    App.toast('Оплата по ' + current.id + ' зафиксирована');
  });

  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#back1').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderDashboard(); screens.replace('s1'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  renderDashboard();
})();
