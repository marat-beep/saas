/* ============================================================
   C1 · Портал поставщика
   регистрация → аккредитация → запросы → предложение
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var RFQS = [
    { id: 'RFQ-124', title: 'Сталь 40Х, пруток Ø60 — 600 кг', cat: 'metal', unit: 'кг', qty: 600, num: '3DMP-RFQ-0124', place: 'Москва', due: '18.02.2026', desc: 'Термообработанный пруток, сертификат 3.1.', price: 385, urgent: true },
    { id: 'RFQ-123', title: 'Подшипники SKF 6205 — 200 шт', cat: 'tool', unit: 'шт', qty: 200, num: '3DMP-RFQ-0123', place: 'Москва', due: '01.03.2026', desc: 'Оригинал или аналог, закрытые 2RS.', price: 520, urgent: false },
    { id: 'RFQ-122', title: 'Алюминий АМг6, лист 4 мм — 1,2 т', cat: 'metal', unit: 'кг', qty: 1200, num: '3DMP-RFQ-0122', place: 'Москва', due: '10.03.2026', desc: 'Лист 1500×3000×4, ГОСТ 21631.', price: 470, urgent: false },
    { id: 'RFQ-121', title: 'Гальваническое цинкование — субподряд', cat: 'sub', unit: 'кг', qty: 700, num: '3DMP-RFQ-0121', place: 'Москва', due: '12.03.2026', desc: 'Цинкование с хроматированием.', price: 210, urgent: false },
    { id: 'RFQ-118', title: 'Сталь 1.2379, пруток Ø40–80 — 250 кг', cat: 'metal', unit: 'кг', qty: 250, num: '3DMP-RFQ-0118', place: 'Москва', due: '20.02.2026', desc: 'Мягкий отжиг, сертификат качества обязателен.', price: 420, urgent: true },
    { id: 'RFQ-117', title: 'Фрезы твёрдосплавные D6–D12 — комплект', cat: 'tool', unit: 'компл.', qty: 20, num: '3DMP-RFQ-0117', place: 'Москва', due: '25.02.2026', desc: 'Покрытие AlTiN, допуск h6.', price: 6500, urgent: false },
    { id: 'RFQ-116', title: 'Латунь ЛС59-1, пруток Ø20–50 — 400 кг', cat: 'metal', unit: 'кг', qty: 400, num: '3DMP-RFQ-0116', place: 'Москва', due: '22.02.2026', desc: 'Срочная поставка, самовывоз.', price: 610, urgent: true },
    { id: 'RFQ-115', title: 'Вакуумная термообработка — 800 кг', cat: 'sub', unit: 'кг', qty: 800, num: '3DMP-RFQ-0115', place: 'Москва', due: '05.03.2026', desc: 'Закалка + отпуск, 58–62 HRC.', price: 180, urgent: false },
    { id: 'RFQ-114', title: 'Абразивные круги 150×20×32 — 300 шт', cat: 'tool', unit: 'шт', qty: 300, num: '3DMP-RFQ-0114', place: 'Москва', due: '10.03.2026', desc: 'Зерно 25А.', price: 240, urgent: false },
    { id: 'RFQ-113', title: 'Анодирование алюминия — субподряд', cat: 'sub', unit: 'кг', qty: 500, num: '3DMP-RFQ-0113', place: 'Москва', due: '15.03.2026', desc: 'Анодирование с окрашиванием.', price: 340, urgent: false },
    { id: 'RFQ-112', title: 'СОЖ для обработки — 200 л', cat: 'tool', unit: 'л', qty: 200, num: '3DMP-RFQ-0112', place: 'Москва', due: '08.03.2026', desc: 'Концентрат эмульсии для ЧПУ.', price: 320, urgent: false },
    { id: 'RFQ-111', title: 'Плоское шлифование деталей — субподряд', cat: 'sub', unit: 'кг', qty: 350, num: '3DMP-RFQ-0111', place: 'Москва', due: '14.03.2026', desc: 'Ra ≤ 0,4, партия 350 кг.', price: 260, urgent: false }
  ];

  var filter = 'all', current = null;
  var offers = App.Store.get('c1offers', []);

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1' || s.id === 's2'); $('#logoutBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Регистрация ---------- */
  function checkReg() {
    var n = $('#cName').value.trim(), i = $('#cInn').value.trim(), c = $('#cContact').value.trim();
    $('#regBtn').disabled = !(n && i.length >= 10 && c);
  }
  ['cName', 'cInn', 'cContact'].forEach(function (id) { $('#' + id).addEventListener('input', checkReg); });
  $('#regBtn').addEventListener('click', function () {
    $('#supName').textContent = $('#cName').value.trim();
    renderStats(); renderRfq(); screens.go('s2'); App.toast('Аккредитация начата');
  });
  $('#logoutBtn').addEventListener('click', function () { screens.replace('s1'); });

  /* ---------- Список ---------- */
  function renderStats() {
    $('#stOpen').textContent = RFQS.length;
    $('#stMy').textContent = offers.length;
    $('#stWin').textContent = offers.filter(function (o) { return o.status === 'Принято'; }).length;
  }
  function renderRfq() {
    var list = RFQS.filter(function (r) { return filter === 'all' || r.cat === filter; });
    $('#rfqCount').textContent = list.length + ' запросов';
    $('#rfqList').innerHTML = list.map(function (r) {
      return '<div class="card clickable accent-left' + (r.urgent ? ' urgent' : '') + '" data-id="' + r.id + '">' +
        '<div class="row between"><span class="rfq-num">' + r.num + '</span><span class="badge ' + (r.urgent ? 'danger' : 'success') + '">' + (r.urgent ? 'Срочно' : 'Открыт') + '</span></div>' +
        '<h3 class="mt-8" style="font-size:.9rem;">' + r.title + '</h3>' +
        '<div class="tag-row">' + '<span class="tag">📦 ' + App.number(r.qty) + ' ' + r.unit + '</span><span class="tag">📍 ' + r.place + '</span><span class="tag">📅 ' + r.due + '</span>' + '</div>' +
        '<div class="meta-row"><span class="muted">Ориентир: ' + money(r.price) + '/' + r.unit + '</span><b style="color:var(--accent-600);">Предложить →</b></div></div>';
    }).join('');
    $$('#rfqList .card').forEach(function (c) { c.addEventListener('click', function () { openRfq(c.dataset.id); }); });
  }
  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderRfq();
  });

  /* ---------- Детали ---------- */
  function openRfq(id) {
    current = RFQS.find(function (r) { return r.id === id; });
    $('#rNum').textContent = current.num;
    $('#rTitle').textContent = current.title;
    $('#rTags').innerHTML = '<span class="tag">📦 ' + App.number(current.qty) + ' ' + current.unit + '</span><span class="tag">📍 ' + current.place + '</span><span class="tag">📅 ' + current.due + '</span>';
    $('#rInfo').innerHTML =
      irow('Объём', App.number(current.qty) + ' ' + current.unit) +
      irow('Ориентир', money(current.price) + ' / ' + current.unit) +
      irow('Место', current.place) +
      irow('Срок подачи', current.due, true);
    $('#rDesc').innerHTML = '<p class="muted" style="font-size:.82rem;line-height:1.55;">' + current.desc + '</p>';
    screens.go('s3');
  }
  function irow(k, v, accent) { return '<div class="row between" style="padding:8px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;' + (accent ? 'color:var(--accent-700);' : '') + '">' + v + '</b></div>'; }

  /* ---------- Предложение ---------- */
  $('#toOffer').addEventListener('click', function () {
    $('#qty').value = current.qty; $('#price').value = current.price;
    updateTotal(); screens.go('s4');
  });
  $('#backRfq').addEventListener('click', function () { screens.back(); });
  function updateTotal() {
    var p = parseFloat($('#price').value) || 0, q = parseFloat($('#qty').value) || 0;
    var total = p * q;
    $('#total').textContent = money(total);
    $('#totalHint').textContent = p > 0 ? App.number(q) + ' × ' + money(p) : 'Укажите цену и количество';
    $('#submitOffer').disabled = !(p > 0 && q > 0);
  }
  ['price', 'qty'].forEach(function (id) { $('#' + id).addEventListener('input', updateTotal); });

  $('#submitOffer').addEventListener('click', function () {
    var num = 'C1-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    var p = parseFloat($('#price').value) || 0, q = parseFloat($('#qty').value) || 0;
    offers.unshift({ num: num, rfq: current.num, total: p * q, status: 'На рассмотрении', date: App.today() });
    App.Store.set('c1offers', offers);
    $('#offerNum').textContent = num;
    $('#resRfq').textContent = current.num;
    $('#resTotal').textContent = money(p * q);
    renderStats();
    screens.go('s5');
    App.toast('Предложение ' + num + ' отправлено');
  });

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderRfq(); screens.replace('s2'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
