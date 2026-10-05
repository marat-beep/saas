/* ============================================================
   3DMP Service · файлы/вложения (window.AppFiles)
   Единый блок «Файлы» для карточек сущностей.
   Данные: app_attachment_* (0046). До 8 МБ, tenant-изоляция.
   Использование:
     AppFiles.mount({ token, entityType:'order', entityId:'…', el:'#filesBox', canEdit:true });
   ============================================================ */
(function (g) {
  'use strict';

  function esc(s) { return (g.AppUI && AppUI.esc) ? AppUI.esc(s) : String(s == null ? '' : s); }
  function size(v) { v = Number(v) || 0; if (v < 1024) return v + ' Б'; if (v < 1048576) return (v / 1024).toFixed(0) + ' КБ'; return (v / 1048576).toFixed(1) + ' МБ'; }
  function fmt(ts) { var d = new Date(ts); return isNaN(d.getTime()) ? '' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }); }
  function rpc(n, a) { return g.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function toast(t, k) { if (g.AppUI && AppUI.toast) AppUI.toast(t); }
  function b64ToBlob(b64, mime) {
    var bin = atob(b64 || ''); var len = bin.length; var u8 = new Uint8Array(len);
    for (var i = 0; i < len; i++) u8[i] = bin.charCodeAt(i);
    return new Blob([u8], { type: mime || 'application/octet-stream' });
  }
  function saveBlob(blob, filename) {
    var url = URL.createObjectURL(blob); var a = document.createElement('a');
    a.href = url; a.download = filename || 'file'; document.body.appendChild(a); a.click();
    setTimeout(function () { if (a.parentNode) a.parentNode.removeChild(a); URL.revokeObjectURL(url); }, 400);
  }
  function fileToBase64(file) {
    return new Promise(function (res, rej) {
      var fr = new FileReader();
      fr.onload = function () { var s = String(fr.result || ''); var i = s.indexOf(','); res(i >= 0 ? s.slice(i + 1) : s); };
      fr.onerror = function () { rej(new Error('Не удалось прочитать файл')); };
      fr.readAsDataURL(file);
    });
  }

  function mount(opts) {
    var token = opts.token, entityType = opts.entityType, entityId = opts.entityId, canEdit = opts.canEdit !== false;
    var el = (typeof opts.el === 'string') ? document.querySelector(opts.el) : opts.el;
    if (!el) return;
    el.innerHTML = '<div class="files-head"><b>Файлы</b>' +
      (canEdit ? '<button class="chip" id="attAdd" type="button">＋ Прикрепить</button>' : '') +
      '<input type="file" id="attInput" style="display:none"></div>' +
      '<div id="attList"><span class="note">Загрузка…</span></div>';
    var list = el.querySelector('#attList');
    var input = el.querySelector('#attInput');
    var addBtn = el.querySelector('#attAdd');

    function load() {
      rpc('app_attachment_list', { p_token: token, p_entity_type: entityType, p_entity_id: entityId }).then(function (rows) {
        rows = rows || [];
        list.innerHTML = rows.length ? rows.map(function (a) {
          return '<div class="kvr"><b>' + esc(a.name) + '</b>' +
            '<span class="note">' + size(a.size) + ' · ' + fmt(a.created_at) + ' · ' + esc(a.uploaded_by || '') + '</span>' +
            '<button class="chip" data-dl="' + a.id + '" type="button" style="margin-left:auto;">Скачать</button>' +
            (canEdit ? '<button class="chip" data-del="' + a.id + '" type="button">✕</button>' : '') + '</div>';
        }).join('') : '<span class="note">Файлов нет.</span>';
        Array.prototype.forEach.call(list.querySelectorAll('[data-dl]'), function (b) {
          b.addEventListener('click', function () {
            rpc('app_attachment_get', { p_token: token, p_id: b.dataset.dl }).then(function (r) {
              var f = r && r[0]; if (!f) { toast('Файл не найден'); return; }
              saveBlob(b64ToBlob(f.data, f.mime), f.name);
            }).catch(function (e) { toast('Ошибка: ' + e.message); });
          });
        });
        Array.prototype.forEach.call(list.querySelectorAll('[data-del]'), function (b) {
          b.addEventListener('click', function () {
            if (!g.confirm('Удалить файл?')) return;
            rpc('app_attachment_delete', { p_token: token, p_id: b.dataset.del }).then(function () { if (g.Auth && Auth.log) Auth.log('Удалён файл', entityType); toast('Файл удалён'); load(); });
          });
        });
      }).catch(function (e) { list.innerHTML = '<span class="note">Ошибка: ' + esc(e.message) + '</span>'; });
    }
    if (addBtn && input) {
      addBtn.addEventListener('click', function () { input.value = ''; input.click(); });
      input.addEventListener('change', function () {
        var file = input.files && input.files[0]; if (!file) return;
        if (file.size > 8388608) { toast('Файл больше 8 МБ'); return; }
        fileToBase64(file).then(function (b64) {
          return rpc('app_attachment_add', { p_token: token, p_entity_type: entityType, p_entity_id: entityId, p_name: file.name, p_mime: file.type, p_data: b64 });
        }).then(function () { if (g.Auth && Auth.log) Auth.log('Загружен файл', entityType + ' · ' + file.name); toast('Файл прикреплён'); load(); })
          .catch(function (e) { toast('Ошибка: ' + e.message); });
      });
    }
    load();
    return { reload: load };
  }

  g.AppFiles = { mount: mount, fileToBase64: fileToBase64, saveBlob: saveBlob, b64ToBlob: b64ToBlob };
})(window);
