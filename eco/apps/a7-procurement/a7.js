/* ============================================================
   A7 · Портал закупок (для поставщиков)
   регистрация → витрина → детали → КП → успех
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var TENDERS = [
    { id: 'T-0048', title: 'Сталь 40Х, пруток Ø60 — 600 кг', cat: ['metal', 'urgent'], urgent: true, unit: 'кг', qty: 600, num: '3DMP-T-0048', place: 'Москва', due: '18.02.2026', desc: 'Пруток Ø60 мм, термообработанный, сертификат 3.1.', price: 385 },
    { id: 'T-0047', title: 'Подшипники SKF 6205 — 200 шт', cat: ['tools'], urgent: false, unit: 'шт', qty: 200, num: '3DMP-T-0047', place: 'Москва', due: '01.03.2026', desc: 'Оригинал SKF или аналог, закрытые 2RS.', price: 520 },
    { id: 'T-0046', title: 'Алюминий АМг6, лист 4 мм — 1,2 т', cat: ['metal'], urgent: false, unit: 'кг', qty: 1200, num: '3DMP-T-0046', place: 'Москва', due: '10.03.2026', desc: 'Лист 1500×3000×4, ГОСТ 21631.', price: 470 },
    { id: 'T-0045', title: 'Услуги гальваники (цинк) — субподряд', cat: ['services'], urgent: false, unit: 'кг', qty: 700, num: '3DMP-T-0045', place: 'Москва', due: '12.03.2026', desc: 'Цинкование с хроматированием, партия 700 кг.', price: 210 },
    { id: 'T-0042', title: 'Сталь 1.2379 (Böhler K110) — 250 кг', cat: ['metal', 'urgent'], urgent: true, unit: 'кг', qty: 250, num: '3DMP-T-0042', place: 'Москва', due: '20.02.2026', desc: 'Пруток Ø40–80 мм, состояние поставки — мягкий отжиг, сертификат качества обязателен.', price: 420 },
    { id: 'T-0041', title: 'Твёрдый сплав ВК8 (пластины) — 150 шт', cat: ['metal'], urgent: false, unit: 'шт', qty: 150, num: '3DMP-T-0041', place: 'Москва', due: '25.02.2026', desc: 'Пластины ВК8, размер 10×10×5 мм, без покрытия.', price: 890 },
    { id: 'T-0040', title: 'Фрезы твёрдосплавные D6–D12 — комплект', cat: ['tools'], urgent: false, unit: 'компл.', qty: 20, num: '3DMP-T-0040', place: 'Москва', due: '28.02.2026', desc: 'Комплект концевых фрез, покрытие AlTiN, допуск h6.', price: 6500 },
    { id: 'T-0039', title: 'Услуги термообработки (вакуумная закалка)', cat: ['services'], urgent: false, unit: 'кг', qty: 800, num: '3DMP-T-0039', place: 'Москва', due: '05.03.2026', desc: 'Вакуумная закалка + отпуск, твёрдость 58–62 HRC.', price: 180 },
    { id: 'T-0038', title: 'Латунь ЛС59-1 — 400 кг', cat: ['metal', 'urgent'], urgent: true, unit: 'кг', qty: 400, num: '3DMP-T-0038', place: 'Москва', due: '19.02.2026', desc: 'Пруток Ø20–50 мм, срочная поставка.', price: 610 },
    { id: 'T-0037', title: 'Абразивные круги — 300 шт', cat: ['tools'], urgent: false, unit: 'шт', qty: 300, num: '3DMP-T-0037', place: 'Москва', due: '10.03.2026', desc: 'Круги 150×20×32, зерно 25А.', price: 240 },
    { id: 'T-0036', title: 'СОЖ для обработки — 200 л', cat: ['tools'], urgent: false, unit: 'л', qty: 200, num: '3DMP-T-0036', place: 'Москва', due: '08.03.2026', desc: 'Концентрат эмульсии для ЧПУ, 5%-ный раствор.', price: 320 },
    { id: 'T-0035', title: 'Услуги шлифовки плоскостей — субподряд', cat: ['services'], urgent: false, unit: 'кг', qty: 350, num: '3DMP-T-0035', place: 'Москва', due: '14.03.2026', desc: 'Плоское шлифование, Ra ≤ 0,4.', price: 260 }
  ];

  var filter = 'all';
  var current = null;
  var offers = App.Store.get('offers', []);

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1' || s.id === 's2'); $('#logoutBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  /* ---------- Вход ---------- */
  function checkLogin() {
    var c = $('#loginCompany').value.trim(), i = $('#loginInn').value.trim(), n = $('#loginContact').value.trim();
    $('#loginBtn').disabled = !(c && i.length >= 10 && n);
  }
  ['loginCompany', 'loginInn', 'loginContact'].forEach(function (id) { $('#' + id).addEventListener('input', checkLogin); });
  $('#loginBtn').addEventListener('click', function () {
    $('#welcomeCompany').textContent = $('#loginCompany').value.trim();
    renderTenders(); renderStats(); screens.go('s2'); App.toast('Добро пожаловать в портал!');
  });
  $('#logoutBtn').addEventListener('click', function () { screens.replace('s1'); });

  /* ---------- Витрина ---------- */
  function renderStats() {
    $('#stActive').textContent = TENDERS.length;
    $('#stOffers').textContent = offers.length;
    $('#stWon').textContent = offers.filter(function (o) { return o.status === 'Принято'; }).length;
  }

  function renderTenders() {
    var list = TENDERS.filter(function (t) {
      if (filter === 'urgent') return t.urgent;
      if (filter === 'all') return true;
      return t.cat.indexOf(filter) >= 0;
    });
    $('#tCount').textContent = list.length + ' активных';
    $('#tendersList').innerHTML = list.map(function (t) {
      return '<div class="card clickable accent-left' + (t.urgent ? ' urgent' : '') + '" data-id="' + t.id + '">' +
        '<div class="row between"><span class="tender-num">' + t.num + '</span>' +
        '<span class="badge ' + (t.urgent ? 'danger' : 'success') + '">' + (t.urgent ? 'Срочно' : 'Активна') + '</span></div>' +
        '<h3 class="mt-8" style="font-size:.92rem;">' + t.title + '</h3>' +
        '<div class="tag-row">' + tag('📦 ' + App.number(t.qty) + ' ' + t.unit) + tag('📍 ' + t.place) + tag('📅 До ' + t.due) + '</div>' +
        '<div class="meta-row"><span class="muted">Ориентир: ' + money(t.price) + '/' + t.unit + '</span><b style="color:var(--accent-600);">Подать КП →</b></div></div>';
    }).join('');
    $$('#tendersList .card').forEach(function (c) { c.addEventListener('click', function () { openTender(c.dataset.id); }); });
  }
  function tag(t) { return '<span class="tag">' + t + '</span>'; }

  $('#filters').addEventListener('click', function (e) {
    var c = e.target.closest('.chip'); if (!c) return;
    $$('.chip', this).forEach(function (x) { x.classList.toggle('active', x === c); });
    filter = c.dataset.f; renderTenders();
  });

  /* ---------- Детали ---------- */
  function openTender(id) {
    current = TENDERS.find(function (t) { return t.id === id; });
    $('#dNum').textContent = current.num;
    $('#dTitle').textContent = current.title;
    var b = $('#dBadge'); b.textContent = current.urgent ? 'Срочно' : 'Активна'; b.className = 'badge ' + (current.urgent ? 'danger' : 'success');
    $('#dInfo').innerHTML =
      irow('Объём', App.number(current.qty) + ' ' + current.unit) +
      irow('Ориентир цены', money(current.price) + ' / ' + current.unit) +
      irow('Место поставки', current.place) +
      irow('Срок подачи', current.due, true);
    $('#dDesc').innerHTML = '<p class="muted" style="font-size:.82rem;line-height:1.55;">' + current.desc + '</p>';
    $('#dFiles').innerHTML = ['ТЗ.pdf', 'Требования к поставщику.pdf'].map(function (f) {
      return '<div class="file-item"><div class="fi">📄</div><div class="grow"><div style="font-weight:600;font-size:.82rem;">' + f + '</div><div class="faint" style="font-size:.68rem;">PDF · скачать</div></div><span style="color:var(--accent-600);font-weight:700;">↓</span></div>';
    }).join('');
    $$('#dFiles .file-item').forEach(function (el) { el.addEventListener('click', function () { App.toast('Демо: скачивание'); }); });
    screens.go('s3');
  }

  function irow(k, v, accent) {
    return '<div class="row between" style="padding:8px 0;font-size:.82rem;border-bottom:1px solid var(--border-2);"><span class="muted">' + k + '</span><b style="text-align:right;' + (accent ? 'color:var(--accent-700);' : '') + '">' + v + '</b></div>';
  }

  /* ---------- КП ---------- */
  $('#toOffer').addEventListener('click', function () {
    $('#qty').value = current.qty;
    $('#price').value = current.price;
    updateTotal(); screens.go('s4');
  });
  $('#backToTender').addEventListener('click', function () { screens.back(); });

  function updateTotal() {
    var p = parseFloat($('#price').value) || 0;
    var q = parseFloat($('#qty').value) || 0;
    var nds = $('#nds').checked;
    var base = p * q;
    var total = nds ? base * 1.2 : base;
    $('#total').textContent = money(total);
    $('#totalHint').textContent = p > 0 ? (App.number(q) + ' × ' + money(p) + (nds ? ' + НДС 20%' : '')) : 'Укажите цену и количество';
    $('#submitOffer').disabled = !(p > 0 && q > 0);
  }
  ['price', 'qty'].forEach(function (id) { $('#' + id).addEventListener('input', updateTotal); });
  $('#nds').addEventListener('change', updateTotal);

  $('#submitOffer').addEventListener('click', function () {
    var offerNum = 'КП-' + App.pad(Math.floor(1 + Math.random() * 999), 4);
    var p = parseFloat($('#price').value) || 0, q = parseFloat($('#qty').value) || 0;
    var total = $('#nds').checked ? p * q * 1.2 : p * q;
    offers.unshift({ num: offerNum, tender: current.num, total: total, status: 'На рассмотрении', date: App.today() });
    App.Store.set('offers', offers);
    $('#offerNum').textContent = offerNum;
    $('#resTender').textContent = current.num;
    $('#resTotal').textContent = money(total);
    renderStats();
    screens.go('s5');
    App.toast('КП ' + offerNum + ' отправлено');
  });

  /* ---------- Навигация ---------- */
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toList').addEventListener('click', function () { renderTenders(); screens.replace('s2'); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
