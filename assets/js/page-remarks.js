/* ============================================================
   3DMP · page-remarks.js — виджет «Замечания к странице» + Bug Mode.
   Публичный API: window.PageRemarks.init(opts)
   Зависимости (опц.): jsPDF (window.jspdf), html2canvas.
   Данные — через storage-адаптер: .rpc(SB,token) (Supabase RPC) | .local() (демо).
   v1.0.
   ============================================================ */
(function (g) {
  'use strict';

  /* ---------- storage-адаптеры ---------- */
  function key(module, url) { return 'pr:' + (module || '') + ':' + (url || ''); }
  var RemarksStorage = {
    /* локальный (демо/офлайн) */
    local: function () {
      return {
        kind: 'local',
        list: function (module, url) { try { return Promise.resolve(JSON.parse(localStorage.getItem(key(module, url)) || '[]')); } catch (e) { return Promise.resolve([]); } },
        add: function (r) { return this.list(r.module, r.url).then(function (a) { a.push(r); localStorage.setItem(key(r.module, r.url), JSON.stringify(a)); return r; }); },
        addBug: function (r) { return this.add(r); },
        resolve: function (r) { return this.list(r.module, r.url).then(function (a) { a.forEach(function (x) { if (x.id === r.id) x.resolved = r.resolved; }); localStorage.setItem(key(r.module, r.url), JSON.stringify(a)); return r; }); },
        remove: function (r) { return this.list(r.module, r.url).then(function (a) { a = a.filter(function (x) { return x.id !== r.id; }); localStorage.setItem(key(r.module, r.url), JSON.stringify(a)); }); },
        clear: function (module, url) { localStorage.removeItem(key(module, url)); return Promise.resolve(); }
      };
    },
    /* серверный (Supabase RPC, token-провайдер: строка или функция) */
    rpc: function (SB, token) {
      function tk() { return (typeof token === 'function') ? token() : token; }
      function call(fn, args) { return SB.rpc(fn, args).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
      return {
        kind: 'rpc',
        list: function (module, url) { return call('app_remark_list', { p_token: tk(), p_module: module || null, p_url: url || null }); },
        add: function (r) { return call('app_remark_create', { p_token: tk(), p_module: r.module, p_url: r.url, p_x: r.x, p_y: r.y, p_role: r.role, p_role_name: r.roleName, p_author: r.author, p_type: r.type, p_text: r.text }).then(function (d) { return (d && d[0]) ? Object.assign(r, { id: d[0].id }) : r; }); },
        addBug: function (r) { return call('app_bug_create', { p_token: tk(), p_module: r.module, p_url: r.url, p_x: r.x, p_y: r.y, p_role_name: r.roleName, p_author: r.author, p_type: r.type, p_text: r.text, p_payload: r.payload || {} }).then(function (d) { return (d && d[0]) ? Object.assign(r, { id: d[0].id }) : r; }); },
        resolve: function (r) { return call('app_remark_resolve', { p_token: tk(), p_id: r.id, p_resolved: r.resolved }); },
        remove: function (r) { return call('app_remark_delete', { p_token: tk(), p_id: r.id }); },
        clear: function (module, url) { return call('app_remark_delete_all', { p_token: tk(), p_module: module || null, p_url: url || null }); }
      };
    }
  };

  var MOCK_SVG = 'data:image/svg+xml;utf8,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="800"><rect width="1280" height="800" fill="#eef2f7"/>' +
    '<rect x="0" y="0" width="1280" height="64" fill="#0b2a4a"/><text x="24" y="40" fill="#fff" font-size="24" font-family="Arial">3DMP · демо-страница (mock)</text>' +
    '<rect x="0" y="64" width="1280" height="736" fill="#fff"/><text x="40" y="130" fill="#334155" font-size="22" font-family="Arial">Это заглушка снимка. Backend /shot подключите для реальных страниц.</text>' +
    '<rect x="40" y="170" width="560" height="220" fill="#f1f5f9"/><text x="60" y="205" fill="#64748b" font-size="16" font-family="Arial">Блок контента</text>' +
    '<rect x="640" y="170" width="600" height="480" fill="#f8fafc"/><text x="660" y="205" fill="#64748b" font-size="16" font-family="Arial">Панель</text></svg>');

  /* ---------- «чёрный ящик» + Bug Mode ---------- */
  var PR_LOG = g.__PR_LOG || (g.__PR_LOG = []);
  function prlog(level, m, extra) { PR_LOG.push({ ts: new Date().toISOString(), level: level, msg: String(m).slice(0, 500), extra: extra || null }); if (PR_LOG.length > 180) PR_LOG.shift(); }
  if (!g.__prHooks) {
    g.__prHooks = true;
    g.addEventListener('error', function (e) { prlog('error', e.message, { src: (e.filename || '') + ':' + (e.lineno || 0) }); });
    g.addEventListener('unhandledrejection', function (e) { prlog('rejection', (e.reason && e.reason.message) || String(e.reason)); });
  }
  function cssSelector(el) {
    if (!el || el.nodeType !== 1) return '';
    if (el.id) return '#' + el.id;
    var parts = [];
    while (el && el.nodeType === 1 && parts.length < 4) {
      var s = el.tagName.toLowerCase();
      if (el.className && typeof el.className === 'string') s += '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.');
      parts.unshift(s); el = el.parentElement;
    }
    return parts.join(' > ');
  }
  function ctxEnvelope(S, el) {
    return { route: location.pathname + location.search, viewport: innerWidth + 'x' + innerHeight, ua: navigator.userAgent,
      lang: navigator.language, ts: new Date().toISOString(), appVersion: (g.AppCatalog && g.AppCatalog.version) || '',
      catalogVersion: (g.AppCatalog && g.AppCatalog.version) || '', module: S.module, url: S.url,
      element: el ? { selector: cssSelector(el), text: (el.textContent || '').trim().slice(0, 120), aria: el.getAttribute && el.getAttribute('aria-label') } : null,
      console: PR_LOG.slice(-60), breadcrumbs: (g.Auth && g.Auth.__log ? g.Auth.__log() : []).slice(-30) };
  }
  function downloadJson(obj, name) { try { var b = new Blob([JSON.stringify(obj, null, 2)], { type: 'application/json' }); var a = document.createElement('a'); a.href = URL.createObjectURL(b); a.download = name; a.click(); setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000); } catch (e) {} }

  function esc(v) { return String(v == null ? '' : v).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
  function uid() { return 'r-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 7); }
  function nowISO() { return new Date().toISOString(); }

  var TYPES = ['Опечатка', 'Вёрстка', 'Картинка', 'Контекст', 'Ошибка', 'Цены', 'Другое'];

  var PageRemarks = {
    init: function (opts) {
      opts = opts || {};
      var mount = opts.mount;
      if (!mount) throw new Error('page-remarks: не задан mount');
      var storage = opts.storage || RemarksStorage.local();
      var S = {
        module: opts.module || (location.pathname.replace(/.*\/apps\//, '').replace(/\/.*/, '') || 'page'),
        url: '', shot: '', mode: 'click', remarks: [], filter: 'all', user: opts.user || { name: '', role: 'employee' },
        shotEndpoint: opts.shotEndpoint || '', shotParams: opts.shotParams || { width: 1280, fullPage: true }, busy: false, bug: false
      };

      mount.innerHTML =
        '<div class="pr-root">' +
        '<div class="pr-top">' +
        '<input class="pr-inp" id="prUrl" placeholder="https://… — адрес страницы для снимка" />' +
        '<button class="pr-btn" id="prLoad">Загрузить</button>' +
        '<button class="pr-chip on" id="prMode">Режим: клик</button>' +
        '<button class="pr-chip" id="prBug" title="Режим бага: клик по элементу + контекст">🐞 Баг</button>' +
        '<button class="pr-btn sec" id="prPdf">PDF</button>' +
        '<button class="pr-btn sec" id="prClear">Удалить все</button>' +
        '</div>' +
        '<div class="pr-msg" id="prMsg"></div>' +
        '<div class="pr-wrap"><div class="pr-snapshot-wrap" id="prShot"><div class="pr-empty">Введите URL и нажмите «Загрузить» (без backend — демо-заглушка).</div></div>' +
        '<div class="pr-layer" id="prLayer"></div></div>' +
        '<div class="pr-line" style="margin-top:10px;justify-content:space-between"><b>Замечания</b>' +
        '<span><button class="pr-chip on" data-f="all">Все</button> <button class="pr-chip" data-f="open">Открытые</button> <button class="pr-chip" data-f="done">Решённые</button></span></div>' +
        '<div class="pr-list" id="prList"></div>' +
        '</div>';

      var $ = function (id) { return mount.querySelector('#' + id); };
      var wrap = $('prShot'), layer = $('prLayer');

      function msg(t, kind) { var e = $('prMsg'); e.textContent = t || ''; e.style.color = kind === 'err' ? '#b91c1c' : (kind === 'ok' ? '#047857' : '#64748b'); }
      function overlay(t) { var o = document.createElement('div'); o.className = 'pr-overlay'; o.innerHTML = '<div class="pr-spin"></div><div>' + esc(t) + '</div>'; document.body.appendChild(o); return function () { o.remove(); }; }
      function normUrl(u) { u = (u || '').trim(); if (!u) return ''; if (!/^https?:\/\//i.test(u)) u = 'https://' + u; return u; }

      function load() {
        var u = normUrl($('prUrl').value);
        if (!u) { msg('Введите адрес.', 'err'); return; }
        S.url = u; $('prUrl').value = u; msg('Загружаю снимок…');
        var done = overlay('Делаем снимок…');
        function withShot(src) {
          S.shot = src; renderShot(); done(); msg('Снимок готов.', 'ok');
          return reloadRemarks();
        }
        if (!S.shotEndpoint) { withShot(MOCK_SVG); return; }
        fetch(S.shotEndpoint + '?url=' + encodeURIComponent(u) + '&width=' + (S.shotParams.width || 1280) + '&fullPage=' + (S.shotParams.fullPage ? 'true' : 'false'), { headers: S.shotHeaders || {} })
          .then(function (r) { if (!r.ok) throw new Error('backend: ' + r.status); return r.blob(); })
          .then(function (b) { return new Promise(function (res, rej) { var fr = new FileReader(); fr.onload = function () { res(fr.result); }; fr.onerror = rej; fr.readAsDataURL(b); }); })
          .then(withShot)
          .catch(function (e) { done(); msg('Не удалось получить снимок (' + e.message + '). Показана заглушка.', 'err'); withShot(MOCK_SVG); });
      }

      function renderShot() {
        wrap.innerHTML = '<img src="' + S.shot + '" alt="снимок страницы" />';
        layer.className = 'pr-layer' + (S.mode === 'view' ? ' view' : '');
        renderMarks();
      }

      function renderMarks() {
        layer.innerHTML = '';
        S.remarks.forEach(function (r, i) {
          var m = document.createElement('div');
          m.className = 'pr-mark ' + (r.role === 'client' ? 'client ' : '') + (r.resolved ? 'resolved ' : '') + (r._hl ? 'pulse' : '');
          m.style.left = r.x + '%'; m.style.top = r.y + '%';
          m.textContent = String(i + 1);
          m.title = r.type + ' · ' + (r.text || '—');
          m.dataset.id = r.id;
          m.addEventListener('click', function (ev) { ev.stopPropagation(); focusRemark(r.id); });
          layer.appendChild(m);
        });
        renderList();
      }

      function openModal(x, y, preset) {
        var role = (S.user.role === 'client') ? 'client' : (preset && preset.role ? preset.role : 'employee');
        var dlg = document.createElement('div'); dlg.className = 'pr-modal';
        dlg.innerHTML = '<div class="pr-dialog" role="dialog" aria-modal="true">' +
          '<div class="pr-line" style="justify-content:space-between"><b>Новое замечание</b><span class="pr-mut">x=' + x.toFixed(1) + '%, y=' + y.toFixed(1) + '%</span></div>' +
          '<div class="pr-field"><label>Роль</label><span><button class="pr-chip role-emp ' + (role === 'employee' ? 'on' : '') + '">Сотрудник</button> <button class="pr-chip role-cli ' + (role === 'client' ? 'on' : '') + '">Клиент</button></span></div>' +
          '<div class="pr-field"><label>Имя</label><input id="prAf" value="' + esc(preset && preset.author || S.user.name || '') + '"/></div>' +
          '<div class="pr-field"><label>Тип</label><span id="prTypes">' + TYPES.map(function (t, i) { return '<button class="pr-chip ' + (i === 0 ? 'on' : '') + '" data-t="' + t + '">' + t + '</button> '; }).join('') + '</span></div>' +
          '<div class="pr-field"><label>Описание (необязательно)</label><textarea id="prAt" rows="3" placeholder="Кратко: что не так">' + esc(preset && preset.text || '') + '</textarea></div>' +
          '<div class="pr-acts"><button class="pr-btn" id="prSave">Сохранить</button><button class="pr-btn sec" id="prCancel">Отмена</button></div></div>';
        document.body.appendChild(dlg);
        var chosenType = (preset && preset.type) || TYPES[0];
        function pick(sel, cls, val) { dlg.querySelectorAll(sel).forEach(function (b) { b.classList.toggle('on', b.dataset ? b.dataset.t === val : false); }); }
        dlg.querySelectorAll('.role-emp,.role-cli').forEach(function (b) { b.addEventListener('click', function () { role = b.classList.contains('role-cli') ? 'client' : 'employee'; dlg.querySelector('.role-emp').classList.toggle('on', role === 'employee'); dlg.querySelector('.role-cli').classList.toggle('on', role === 'client'); }); });
        dlg.querySelectorAll('#prTypes .pr-chip').forEach(function (b) { b.addEventListener('click', function () { chosenType = b.dataset.t; dlg.querySelectorAll('#prTypes .pr-chip').forEach(function (z) { z.classList.toggle('on', z === b); }); }); });
        function close() { dlg.remove(); document.removeEventListener('keydown', onEsc); }
        function onEsc(e) { if (e.key === 'Escape') close(); }
        document.addEventListener('keydown', onEsc);
        dlg.querySelector('#prCancel').addEventListener('click', close);
        dlg.addEventListener('click', function (e) { if (e.target === dlg) close(); });
        setTimeout(function () { var f = dlg.querySelector('#prAf'); if (f) f.focus(); }, 30);
        dlg.querySelector('#prSave').addEventListener('click', function () {
          var isBug = !!(preset && preset._bug);
          var r = { id: uid(), module: S.module, url: S.url, x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10,
            role: role, roleName: role === 'client' ? 'Клиент' : 'Сотрудник', author: dlg.querySelector('#prAf').value.trim() || S.user.name || '—',
            type: chosenType, text: dlg.querySelector('#prAt').value.trim(), date: nowISO(), resolved: false };
          if (isBug) { r.kind = 'bug'; r.status = 'new'; r.payload = ctxEnvelope(S, preset && preset._el); }
          var op = (isBug && storage.addBug) ? storage.addBug(r) : storage.add(r);
          op.then(function () {
            S.remarks.push(r); close(); renderMarks();
            msg(isBug ? 'Баг передан разработчику.' : 'Замечание сохранено.', 'ok');
            if (isBug) {
              downloadJson({ kind: 'bug', id: r.id, url: S.url, module: S.module, x: r.x, y: r.y, type: r.type, text: r.text || '—', context: r.payload }, 'bug_' + r.id + '.json');
              var link = location.origin + location.pathname + '?module=' + encodeURIComponent(S.module) + '#yaremark=' + r.id;
              try { if (navigator.clipboard) navigator.clipboard.writeText(link); } catch (e) {}
              if (g.AppNotify && g.AppNotify.info) g.AppNotify.info('Баг отправлен. Ссылка скопирована.');
            }
            if (opts.onRemarkAdded) opts.onRemarkAdded(r);
          }).catch(function (e) { msg('Ошибка сохранения: ' + e.message, 'err'); });
        });
      }

      layer.addEventListener('click', function (e) {
        if (S.mode !== 'click' || !S.shot) return;
        var rect = layer.getBoundingClientRect();
        var x = ((e.clientX - rect.left) / rect.width) * 100, y = ((e.clientY - rect.top) / rect.height) * 100;
        if (x < 0 || x > 100 || y < 0 || y > 100) return;
        if (S.bug) {
          var prev = layer.style.pointerEvents; layer.style.pointerEvents = 'none';
          var el = document.elementFromPoint(e.clientX, e.clientY);
          layer.style.pointerEvents = prev || '';
          openModal(x, y, { type: 'Ошибка', _bug: true, _el: el, author: S.user.name, text: '' });
          return;
        }
        openModal(x, y, null);
      });

      function focusRemark(id) { S.remarks.forEach(function (r) { r._hl = (r.id === id); }); renderMarks(); var c = $('prList').querySelector('[data-card="' + id + '"]'); if (c) c.scrollIntoView({ behavior: 'smooth', block: 'center' }); setTimeout(function () { S.remarks.forEach(function (r) { r._hl = false; }); renderMarks(); }, 2600); }

      function toggle(id) { var r = S.remarks.filter(function (x) { return x.id === id; })[0]; if (!r) return; r.resolved = !r.resolved; storage.resolve(r).then(function () { renderMarks(); if (r.resolved && opts.onRemarkResolved) opts.onRemarkResolved(r); }); }
      function del(id) { var r = S.remarks.filter(function (x) { return x.id === id; })[0]; if (!r) return; storage.remove(r).then(function () { S.remarks = S.remarks.filter(function (x) { return x.id !== id; }); renderMarks(); }); }

      function renderList() {
        var host = $('prList');
        var rows = S.remarks.filter(function (r) { return S.filter === 'all' || (S.filter === 'open' ? !r.resolved : r.resolved); }).slice().reverse();
        if (!rows.length) { host.innerHTML = '<div class="pr-empty">Замечаний нет.</div>'; return; }
        host.innerHTML = rows.map(function (r) {
          var idx = S.remarks.indexOf(r) + 1;
          return '<div class="pr-card ' + (r.resolved ? 'resolved' : '') + '" data-card="' + r.id + '">' +
            '<div class="pr-line"><span class="pr-badge ' + (r.role === 'client' ? 'cli' : 'emp') + '">' + esc(r.roleName) + '</span>' +
            '<b>№' + idx + '</b> <span class="pr-badge">' + esc(r.type) + '</span>' +
            '<span class="pr-mut" style="margin-left:auto">' + r.x.toFixed(1) + '%, ' + r.y.toFixed(1) + '% · ' + new Date(r.date).toLocaleString('ru-RU') + '</span></div>' +
            '<div class="pr-txt">' + esc(r.text || '—') + '</div>' +
            '<div class="pr-mut">Автор: ' + esc(r.author) + (r.resolved ? ' · решено' : '') + '</div>' +
            '<div class="pr-acts"><button class="pr-btn sec" data-show="' + r.id + '">Показать</button>' +
            '<button class="pr-btn sec" data-tog="' + r.id + '">' + (r.resolved ? 'Вернуть' : 'Решено') + '</button>' +
            '<button class="pr-btn sec" data-del="' + r.id + '">Удалить</button></div></div>';
        }).join('');
        host.querySelectorAll('[data-show]').forEach(function (b) { b.addEventListener('click', function () { focusRemark(b.dataset.show); }); });
        host.querySelectorAll('[data-tog]').forEach(function (b) { b.addEventListener('click', function () { toggle(b.dataset.tog); }); });
        host.querySelectorAll('[data-del]').forEach(function (b) { b.addEventListener('click', function () { del(b.dataset.del); }); });
      }

      function reloadRemarks() { return storage.list(S.module, S.url).then(function (a) { S.remarks = (a || []).map(function (r) { return Object.assign({ role: 'employee', roleName: 'Сотрудник', type: 'Другое', text: '', resolved: false, date: nowISO() }, r); }); renderMarks(); }); }

      /* ---------- PDF ---------- */
      function exportPdf() {
        if (!S.remarks.length) { alert('Нет замечаний для экспорта.'); return; }
        if (!g.html2canvas || !(g.jspdf && g.jspdf.jsPDF)) { alert('PDF-библиотеки не загружены (html2canvas, jsPDF).'); return; }
        var done = overlay('Формируем PDF…');
        g.html2canvas(wrap, { scale: 1, useCORS: true, backgroundColor: '#ffffff' }).then(function (canvas) {
          var jsPDF = g.jspdf.jsPDF; var pdf = new jsPDF({ orientation: 'p', unit: 'pt', format: 'a4' });
          var pw = pdf.internal.pageSize.getWidth(), ph = pdf.internal.pageSize.getHeight(), margin = 24;
          pdf.setFontSize(14); pdf.text('Замечания к странице', margin, margin + 4);
          pdf.setFontSize(9); pdf.text('URL: ' + S.url, margin, margin + 20);
          pdf.text('Дата: ' + new Date().toLocaleString('ru-RU') + '   Всего: ' + S.remarks.length + '   Решено: ' + S.remarks.filter(function (r) { return r.resolved; }).length, margin, margin + 34);
          var imgW = pw - margin * 2, ratio = canvas.height / canvas.width, imgH = imgW * ratio;
          var pages = Math.max(1, Math.ceil(imgH / ph));
          for (var p = 0; p < pages; p++) {
            var srcY = Math.round(canvas.height / pages * p), srcH = Math.round(canvas.height / pages);
            var sub = document.createElement('canvas'); sub.width = canvas.width; sub.height = srcH;
            sub.getContext('2d').drawImage(canvas, 0, srcY, canvas.width, srcH, 0, 0, canvas.width, srcH);
            if (p > 0) pdf.addPage();
            pdf.addImage(sub.toDataURL('image/jpeg', 0.85), 'JPEG', margin, 60, imgW, imgH / pages);
          }
          pdf.addPage();
          pdf.setFontSize(13); pdf.text('Таблица замечаний', margin, margin + 4);
          var y = margin + 22; var cols = [margin, margin + 24, margin + 96, margin + 210, margin + 330, margin + 430, margin + 500];
          pdf.setFontSize(9);
          function line(vals) { if (y > ph - margin) { pdf.addPage(); y = margin + 16; } cols.forEach(function (cx, i) { pdf.text(String(vals[i] == null ? '' : vals[i]).slice(0, 40), cx, y); }); y += 14; }
          line(['№', 'Автор', 'Тип', 'Описание', 'Коорд.', 'Дата', 'Статус']);
          S.remarks.forEach(function (r, i) { line([i + 1, r.author, r.type, r.text || '—', r.x.toFixed(0) + '%,' + r.y.toFixed(0) + '%', new Date(r.date).toLocaleDateString('ru-RU'), r.resolved ? 'решено' : 'открыто']); });
          pdf.save('zamechania_' + new Date().toISOString().slice(0, 10) + '.pdf');
          done(); msg('PDF сформирован.', 'ok');
        }).catch(function (e) { done(); alert('Ошибка PDF: ' + e.message); });
      }

      $('prLoad').addEventListener('click', load);
      $('prUrl').addEventListener('keydown', function (e) { if (e.key === 'Enter') load(); });
      $('prMode').addEventListener('click', function () { S.mode = (S.mode === 'click') ? 'view' : 'click'; this.textContent = 'Режим: ' + (S.mode === 'click' ? 'клик' : 'просмотр'); layer.className = 'pr-layer' + (S.mode === 'view' ? ' view' : ''); });
      $('prBug').addEventListener('click', function () { S.bug = !S.bug; this.classList.toggle('on', S.bug); if (S.bug && S.mode === 'view') { S.mode = 'click'; $('prMode').textContent = 'Режим: клик'; layer.className = 'pr-layer'; } if (g.AppNotify && g.AppNotify.info) g.AppNotify.info(S.bug ? 'Режим бага включён: клик по элементу.' : 'Режим бага выключен.'); });
      $('prPdf').addEventListener('click', exportPdf);
      $('prClear').addEventListener('click', function () { if (!confirm('Удалить все замечания для этой страницы?')) return; storage.clear(S.module, S.url).then(function () { S.remarks = []; renderMarks(); msg('Замечания удалены.', 'ok'); }); });
      mount.querySelectorAll('[data-f]').forEach(function (b) { b.addEventListener('click', function () { S.filter = b.dataset.f; mount.querySelectorAll('[data-f]').forEach(function (z) { z.classList.toggle('on', z === b); }); renderList(); }); });

      return { setUser: function (u) { S.user = u || S.user; }, getRemarks: function () { return S.remarks.slice(); }, storage: storage, state: S };
    },
    TYPES: TYPES,
    Storage: RemarksStorage
  };

  g.RemarksStorage = RemarksStorage;
  g.PageRemarks = PageRemarks;
})(window);
