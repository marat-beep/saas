/* ============================================================
   B32 · Маркировка: децимальные номера и QR-ярлыки
   генерация децимального номера (ГОСТ 2.201) + QR + ярлык
   ============================================================ */
(function () {
  'use strict';
  var $ = App.$, $$ = App.$$;

  var CLASSES = {
    drawing: [['712000', 'Чертёж общего вида'], ['713000', 'Теоретический чертёж'], ['714000', 'Габаритный чертёж'], ['715000', 'Монтажный чертёж']],
    part: [['751000', 'Деталь механообработки'], ['752000', 'Деталь из листа'], ['753000', 'Корпусная деталь']],
    assembly: [['732000', 'Сборочная единица'], ['733000', 'Узел'], ['734000', 'Комплекс']],
    tool: [['762000', 'Режущий инструмент'], ['763000', 'Вспомогательный инструмент'], ['764000', 'Приспособление']],
    fixture: [['765000', 'Оснастка станочная'], ['766000', 'Кондуктор'], ['767000', 'Штамп']],
    machine: [['481000', 'Станок с ЧПУ'], ['482000', 'Измерительная система'], ['483000', 'Лазерный комплекс']]
  };
  var TYPE_NAMES = { drawing: 'Чертёж', part: 'Деталь', assembly: 'Сборочная единица', tool: 'Инструмент', fixture: 'Оснастка', machine: 'Станок / оборудование' };

  var qrInstance = null, payload = '', decNum = '';
  var screens = AppRouter.create({
    onShow: function (s) { $('#backBtn').hidden = (s.id === 's1'); $('#content').scrollTop = 0; },
    onBackEmpty: function () { location.href = '../../index.html'; }
  });

  function fillClasses() {
    var t = $('#type').value;
    $('#cls').innerHTML = (CLASSES[t] || []).map(function (c) { return '<option value="' + c[0] + '">' + c[0] + ' — ' + c[1] + '</option>'; }).join('');
  }
  $('#type').addEventListener('change', fillClasses);
  fillClasses();

  function gen() {
    var org = ($('#org').value || 'ЗДМП').toUpperCase().slice(0, 4);
    var cls = $('#cls').value || '000000';
    var serial = String(parseInt($('#serial').value, 10) || 1);
    while (serial.length < 3) serial = '0' + serial;
    var doc = ($('#doc').value || '00').toUpperCase().slice(0, 2);
    decNum = org + '.' + cls + '.' + serial + '.' + doc;
    var type = TYPE_NAMES[$('#type').value];
    var name = $('#name').value.trim() || type;
    payload = decNum + ' | ' + type + ' | ' + name + ' | ' + App.today();

    $('#decNum').textContent = decNum;
    $('#lpName').textContent = name;
    $('#lpDec').textContent = decNum;
    $('#lpType').textContent = type;
    $('#lpDate').textContent = 'Дата: ' + App.today();
    $('#qrPayload').textContent = payload;

    renderQR(payload);
    screens.go('s2');
  }

  function renderQR(text) {
    var box = $('#qrBox');
    box.innerHTML = '';
    if (window.QRCode) {
      try {
        qrInstance = new QRCode(box, { text: text, width: 120, height: 120, correctLevel: QRCode.CorrectLevel.M });
        return;
      } catch (e) {}
    }
    // fallback: детерминированный узор (не сканируется) + подпись
    var c = document.createElement('canvas'); c.width = 120; c.height = 120;
    var ctx = c.getContext('2d');
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, 120, 120);
    var seed = 0; for (var i = 0; i < text.length; i++) seed += text.charCodeAt(i) * (i + 1);
    ctx.fillStyle = '#0f172a';
    for (var r = 0; r < 20; r++) for (var col = 0; col < 20; col++) if (((seed * (r + 3) * (col + 7)) >> 2) % 3 === 0) ctx.fillRect(col * 6, r * 6, 6, 6);
    box.appendChild(c);
  }

  function getQrCanvas() { return $('#qrBox').querySelector('canvas') || $('#qrBox canvas'); }

  function buildLabelCanvas() {
    var qrc = getQrCanvas();
    var W = 520, H = 300;
    var c = document.createElement('canvas'); c.width = W; c.height = H;
    var ctx = c.getContext('2d');
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H);
    ctx.strokeStyle = '#0f172a'; ctx.lineWidth = 4; ctx.strokeRect(8, 8, W - 16, H - 16);
    if (qrc) ctx.drawImage(qrc, 20, 20, 200, 200);
    ctx.fillStyle = '#0f172a';
    ctx.font = 'bold 26px monospace'; ctx.fillText($('#name').value.trim() || decNum, 250, 60, 240);
    ctx.font = '20px monospace'; ctx.fillText(decNum, 250, 100, 240);
    ctx.font = '16px sans-serif'; ctx.fillText(TYPE_NAMES[$('#type').value], 250, 135);
    ctx.fillText('3DMP · ' + App.today(), 250, 165);
    ctx.font = '12px monospace';
    var words = payload.split(' | '); ctx.fillText(words.slice(2).join(' '), 250, 200, 240);
    return c;
  }

  function download() {
    var c = buildLabelCanvas();
    var a = document.createElement('a');
    a.href = c.toDataURL('image/png');
    a.download = decNum.replace(/\./g, '_') + '_label.png';
    document.body.appendChild(a); a.click(); a.remove();
    App.toast('Ярлык сохранён (PNG)');
  }

  function printLabel() {
    var c = buildLabelCanvas();
    var w = window.open('', '_blank');
    if (!w) { App.toast('Разрешите всплывающие окна для печати'); return; }
    w.document.write('<html><head><title>Ярлык ' + decNum + '</title></head><body style="margin:0;display:flex;align-items:center;justify-content:center;"><img src="' + c.toDataURL('image/png') + '" style="width:520px;"></body></html>');
    w.document.close(); w.focus();
    setTimeout(function () { w.print(); }, 300);
  }

  $('#genBtn').addEventListener('click', gen);
  $('#dlPng').addEventListener('click', download);
  $('#printBtn').addEventListener('click', printLabel);
  $('#editBtn').addEventListener('click', function () { screens.go('s1'); });
  $('#saveBtn').addEventListener('click', function () {
    App.Store.set('markings', (App.Store.get('markings', [])).concat([{ dec: decNum, name: $('#name').value.trim(), type: $('#type').value, created: App.today() }]));
    AppData.log.add({ action: 'Маркировка создана', detail: decNum });
    $('#actNum').textContent = decNum;
    screens.go('s3'); App.toast('Маркировка сохранена');
  });
  $('#againBtn').addEventListener('click', function () { $('#serial').value = (parseInt($('#serial').value, 10) || 1) + 1; screens.go('s1'); });
  $('#backBtn').addEventListener('click', function () { screens.back(); });
  $('#toHub').addEventListener('click', function () { location.href = '../../index.html'; });
  $('#homeBtn').addEventListener('click', function () { location.href = '../../index.html'; });
})();
