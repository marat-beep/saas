/* ============================================================
   3DMP Service · scan.js (window.AppScan) — W36
   Скан QR/ШК (камера через BarcodeDetector; фолбэк — USB-сканер/ручной ввод),
   фото (input capture) и геометка (navigator.geolocation).
   Возвращает Promise<string|null> / Promise<object|null>.
   ============================================================ */
(function (g) {
  'use strict';
  function toast(t) { if (g.AppUI && g.AppUI.toast) g.AppUI.toast(t); else alert(t); }
  function esc(v) { return (g.AppUI && g.AppUI.esc) ? g.AppUI.esc(v) : String(v == null ? '' : v); }

  function modal(title, inner, onMount) {
    var back = document.createElement('div'); back.className = 'modal-backdrop';
    back.innerHTML = '<div class="modal" role="dialog" aria-modal="true"><div class="modal-head">' + esc(title) + '</div>' +
      '<div class="modal-body">' + inner + '</div><div class="modal-foot"><button class="btn secondary" data-cancel>Закрыть</button></div></div>';
    document.body.appendChild(back);
    requestAnimationFrame(function () { back.classList.add('show'); });
    function close() { back.classList.remove('show'); setTimeout(function () { back.remove(); }, 160); if (stop) { try { stop(); } catch (e) {} } }
    back.addEventListener('click', function (e) { if (e.target === back || e.target.closest('[data-cancel]')) close(); });
    if (onMount) onMount(back, close);
    return { el: back, close: close };
  }

  /* Камера + BarcodeDetector (если поддерживается), иначе — ручной/USB ввод */
  function scan(opts) {
    opts = opts || {};
    var hasBD = ('BarcodeDetector' in g) && g.navigator && g.navigator.mediaDevices;
    if (!hasBD) return manual(opts);
    return new Promise(function (resolve) {
      var stop = null, ctl = modal('Скан QR/ШК', '<video id="scVid" playsinline style="width:100%;border-radius:10px;background:#0f172a"></video>' +
        '<div class="note" id="scHint">Наведите камеру на код…</div>', function (back, close) {
        var video = back.querySelector('#scVid');
        g.navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } }).then(function (stream) {
          video.srcObject = stream; video.play();
          stop = function () { stream.getTracks().forEach(function (t) { t.stop(); }); };
          var det = new g.BarcodeDetector();
          var iv = setInterval(function () {
            det.detect(video).then(function (codes) {
              if (codes && codes.length) { clearInterval(iv); var v = codes[0].rawValue || ''; close(); resolve(v); }
            }).catch(function () {});
          }, 350);
          var origClose = stop; stop = function () { clearInterval(iv); if (origClose) origClose(); };
        }).catch(function () { back.querySelector('#scHint').textContent = 'Камера недоступна — введите код вручную.'; });
      });
    });
  }

  function manual(opts) {
    return new Promise(function (resolve) {
      var ctl = modal('Скан QR/ШК', '<div class="field"><label>Код (сканер/вручную)</label>' +
        '<input id="scIn" autocomplete="off" placeholder="Отсканируйте или введите…"></div>', function (back, close) {
        var inp = back.querySelector('#scIn'); setTimeout(function () { inp.focus(); }, 60);
        inp.addEventListener('keydown', function (e) { if (e.key === 'Enter') { var v = inp.value.trim(); if (v) { close(); resolve(v); } } });
        var ok = back.querySelector('.modal-foot');
        var btn = document.createElement('button'); btn.className = 'btn'; btn.textContent = 'Принять';
        btn.addEventListener('click', function () { var v = inp.value.trim(); if (v) { close(); resolve(v); } });
        ok.insertBefore(btn, ok.firstChild ? ok.firstChild.nextSibling : null);
      });
    });
  }

  function photo() {
    return new Promise(function (resolve) {
      var inp = document.createElement('input'); inp.type = 'file'; inp.accept = 'image/*'; inp.capture = 'environment';
      inp.addEventListener('change', function () {
        var f = inp.files && inp.files[0]; if (!f) { resolve(null); return; }
        var r = new FileReader(); r.onload = function () { resolve({ name: f.name, type: f.type, size: f.size, dataUrl: r.result }); };
        r.onerror = function () { resolve(null); }; r.readAsDataURL(f);
      });
      inp.click();
    });
  }

  function geo() {
    return new Promise(function (resolve) {
      if (!g.navigator || !g.navigator.geolocation) { toast('Геолокация недоступна'); resolve(null); return; }
      g.navigator.geolocation.getCurrentPosition(function (p) {
        resolve({ lat: p.coords.latitude, lon: p.coords.longitude, acc: p.coords.accuracy });
      }, function () { toast('Не удалось определить геометку'); resolve(null); }, { enableHighAccuracy: true, timeout: 8000 });
    });
  }

  g.AppScan = { scan: scan, photo: photo, geo: geo };
})(window);
