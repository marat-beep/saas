/* ============================================================
   B33 · Конструктор документов
   КП, договор, наряд, технологическая карта: сборка и печать
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$, money = App.money;

  var PREFIX = { kp: 'КП', contract: 'Д', naryad: 'НР', techcard: 'ТК' };
  var TITLES = { kp: 'Коммерческое предложение', contract: 'Договор', naryad: 'Сменный наряд', techcard: 'Технологическая карта' };
  var COLS = { kp: ['Наименование', 'Кол-во', 'Цена, ₽'], contract: ['Наименование', 'Кол-во', 'Сумма, ₽'], naryad: ['Операция', 'Кол-во', 'Расценка, ₽'], techcard: ['Операция', 'Оборудование', 'Норма, мин'] };
  var rows = [];

  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function initForm() {
    var t = $('#dtype').value;
    $('#dnum').value = PREFIX[t] + '-' + App.pad(Math.floor(1 + Math.random() * 9999), 4);
    $('#ddate').value = App.today();
    rows = [{ name: '', q: 1, p: 0 }];
    renderRows();
  }
  $('#dtype').addEventListener('change', initForm);

  function renderRows() {
    var cols = COLS[$('#dtype').value];
    $('#items').innerHTML = '<div class="faint" style="font-size:.68rem;margin-bottom:4px;">' + cols.join(' · ') + '</div>' +
      rows.map(function (r, i) {
        return '<div class="rowitem"><input type="text" data-i="' + i + '" data-k="name" value="' + (r.name || '') + '" placeholder="' + cols[0] + '"><input type="number" data-i="' + i + '" data-k="q" value="' + r.q + '"><input type="number" data-i="' + i + '" data-k="p" value="' + r.p + '"><button class="rm" data-rm="' + i + '">✕</button></div>';
      }).join('');
    $('#rowCount').textContent = rows.length + ' позиций';
    $$('#items input').forEach(function (inp) {
      inp.addEventListener('input', function () {
        var i = parseInt(inp.dataset.i, 10), k = inp.dataset.k;
        rows[i][k] = k === 'name' ? inp.value : (parseFloat(inp.value) || 0);
        updateTotal();
      });
    });
    $$('#items .rm').forEach(function (b) {
      b.addEventListener('click', function () { rows.splice(parseInt(b.dataset.rm, 10), 1); if (!rows.length) rows = [{ name: '', q: 1, p: 0 }]; renderRows(); });
    });
    updateTotal();
  }
  $('#addRow').addEventListener('click', function () { rows.push({ name: '', q: 1, p: 0 }); renderRows(); });

  function totalNet() { return rows.reduce(function (a, r) { return a + (r.q || 0) * (r.p || 0); }, 0); }
  function updateTotal() { $('#dTotal').textContent = money(totalNet() * 1.22); }

  function buildDoc() {
    var t = $('#dtype').value, cols = COLS[t];
    var net = totalNet(), vat = net * 0.22;
    var items = rows.map(function (r) {
      return '<tr><td>' + (r.name || '—') + '</td><td>' + r.q + '</td><td>' + (t === 'techcard' ? r.p : money(r.p)) + '</td></tr>';
    }).join('');
    $('#docView').innerHTML =
      '<h1>ООО «3Д Металлообработка Пресс»</h1>' +
      '<div class="meta">' + TITLES[t] + ' № ' + $('#dnum').value + ' от ' + $('#ddate').value + '</div>' +
      '<div><b>Заказчик:</b> ' + ($('#dclient').value || '—') + ( $('#dcontact').value ? ' (' + $('#dcontact').value + ')' : '') + '</div>' +
      ($('#dsubject').value ? '<div><b>Предмет:</b> ' + $('#dsubject').value + '</div>' : '') +
      '<table><tr><th>' + cols[0] + '</th><th>' + cols[1] + '</th><th>' + cols[2] + '</th></tr>' + items + '</table>' +
      (t !== 'techcard' ? '<div class="tot">Сумма без НДС: ' + money(net) + '<br>НДС 22%: ' + money(vat) + '<br>Итого: ' + money(net + vat) + '</div>' : '') +
      '<div class="sign"><span>Исполнитель: 3DMP _____________</span><span>Заказчик: _____________</span></div>';
    screens.go('s2');
  }

  function printDoc() {
    var w = window.open('', '_blank');
    if (!w) { App.toast('Разрешите всплывающие окна'); return; }
    w.document.write('<html><head><title>' + $('#dnum').value + '</title><style>body{font-family:Arial;padding:24px;color:#0f172a;font-size:13px}h1{text-align:center;font-size:16px;margin:0}.meta{text-align:center;color:#475569;margin:6px 0 16px}table{width:100%;border-collapse:collapse;margin:12px 0}th,td{border:1px solid #cbd5e1;padding:6px 8px;text-align:left}.tot{text-align:right;font-weight:700}.sign{margin-top:24px;display:flex;justify-content:space-between}</style></head><body>' + $('#docView').innerHTML + '</body></html>');
    w.document.close(); w.focus();
    setTimeout(function () { w.print(); }, 300);
  }

  $('#buildBtn').addEventListener('click', buildDoc);
  $('#editBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#printBtn').addEventListener('click', printDoc);
  $('#copyBtn').addEventListener('click', function () {
    var txt = $('#docView').innerText;
    if (navigator.clipboard) navigator.clipboard.writeText(txt).catch(function () {});
    App.toast('Текст документа скопирован');
  });
  $('#saveBtn').addEventListener('click', function () {
    App.Store.set('documents', (App.Store.get('documents', [])).concat([{ num: $('#dnum').value, type: $('#dtype').value, sum: Math.round(totalNet() * 1.22), created: App.today() }]));
    AppData.log.add({ action: 'Сформирован документ', detail: $('#dnum').value });
    $('#actNum').textContent = $('#dnum').value;
    screens.go('s3'); App.toast('Документ сохранён');
  });
  $('#againBtn').addEventListener('click', function () { initForm(); screens.go('s1'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });

  initForm();
})();
