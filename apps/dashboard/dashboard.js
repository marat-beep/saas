/* ============================================================
   3DMP Service · apps/dashboard — личный кабинет
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs;

  var ROLE_LABEL = { owner: 'Собственник', manager: 'Менеджер', supplier: 'Поставщик', admin: 'Администратор' };
  function roleLabel(r) { return ROLE_LABEL[r] || r || '—'; }

  function kv(k, v) {
    return '<div class="tenant"><span class="note">' + ui.esc(k) + '</span><b style="margin-left:auto;">' + ui.esc(v) + '</b></div>';
  }
  function fmtDT(ts) {
    if (!ts) return '—';
    var d = new Date(ts); if (isNaN(d.getTime())) return String(ts);
    return d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  }

  function renderEvents(session) {
    if (!window.SB) return;
    window.SB.rpc('app_my_events', { p_token: session.token, p_limit: 8 }).then(function (r) {
      var list = (r && !r.error && r.data) || [];
      if (!list.length) { $('#events').innerHTML = '<span class="note">Действий пока нет.</span>'; return; }
      $('#events').innerHTML = list.map(function (e) {
        return '<div class="tenant"><span><b>' + ui.esc(e.action) + '</b>' +
          (e.detail ? ' <span class="note">— ' + ui.esc(e.detail) + '</span>' : '') +
          '</span><span class="rel" style="margin-left:auto;font-size:.72rem;color:var(--muted);">' + fmtDT(e.created_at) + '</span></div>';
      }).join('');
    }).catch(function () { $('#events').innerHTML = '<span class="note">Журнал недоступен.</span>'; });
  }

  function renderModules(session) {
    var apps = (window.AppCatalog && window.AppCatalog.apps) || [];
    var list = apps.filter(function (a) {
      if (a.id === 'auth' || a.id === 'dashboard') return false;
      if (a.roles && a.roles.indexOf(session.role) < 0) return false;
      return true;
    });
    if (!list.length) { $('#modules').innerHTML = '<span class="note">Модулей пока нет.</span>'; return; }
    $('#modules').innerHTML = list.map(function (a) {
      return '<div class="mod">' +
        '<div class="mod-ic">' + a.icon + '</div>' +
        '<div class="mod-tx"><b>' + ui.esc(a.title) + '</b><span>' + ui.esc(a.desc || '') + '</span></div>' +
        '<a class="mod-btn" href="../' + a.id + '/index.html">Открыть</a>' +
        '</div>';
    }).join('');
  }

  function rpc(n, a) { return window.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function tfaMsg(t, k) { var e = $('#tfaMsg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function renderTfa(s) {
    if (!window.SB) return;
    rpc('app_2fa_status', { p_token: s.token }).then(function (r) {
      var st = (r && r[0]) || {};
      $('#tfaSetup').style.display = 'none';
      if (st.enabled) {
        $('#tfaBox').innerHTML = '<div class="tenant"><b>Статус: включена</b></div>' +
          '<div class="field mt"><label>Код для отключения</label><input id="tfaOff" inputmode="numeric" placeholder="6 цифр"></div>' +
          '<div class="btn-row mt"><button class="btn secondary" id="tfaDisable">Отключить 2FA</button></div>';
        $('#tfaDisable').addEventListener('click', function () {
          rpc('app_2fa_disable', { p_token: s.token, p_code: $('#tfaOff').value })
            .then(function (r2) { var x = r2 && r2[0]; tfaMsg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) renderTfa(s); })
            .catch(function (e) { tfaMsg('Ошибка: ' + e.message, 'err'); });
        });
      } else {
        $('#tfaBox').innerHTML = '<div class="tenant"><b>Статус: выключена</b></div>' +
          '<div class="btn-row mt"><button class="btn" id="tfaStart">Настроить 2FA</button></div>';
        $('#tfaStart').addEventListener('click', function () {
          rpc('app_2fa_setup', { p_token: s.token }).then(function (r2) {
            var x = r2 && r2[0]; if (!x) return;
            $('#tfaSecret').value = x.secret; $('#tfaUri').value = x.uri;
            $('#tfaSetup').style.display = 'block'; tfaMsg('Введите код из приложения-аутентификатора', 'info');
          }).catch(function (e) { tfaMsg('Ошибка: ' + e.message, 'err'); });
        });
      }
    }).catch(function () { $('#tfaBox').innerHTML = '<span class="note">Недоступно.</span>'; });
  }

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    $('#tfaEnable').addEventListener('click', function () {
      rpc('app_2fa_enable', { p_token: s.token, p_code: $('#tfaCode').value })
        .then(function (r) { var x = r && r[0]; tfaMsg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { $('#tfaCode').value = ''; renderTfa(s); } })
        .catch(function (e) { tfaMsg('Ошибка: ' + e.message, 'err'); });
    });
    renderTfa(s);
    var out = $('#logout');
    out.style.display = '';
    out.addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

    $('#profile').innerHTML =
      kv('Логин', s.login) + kv('Имя', s.full_name || '—') +
      kv('Организация', s.tenant_name || '—') +
      kv('Роль', roleLabel(s.role)) +
      kv('Последний вход', fmtDT(s.last_login_at));
    renderModules(s);
    renderEvents(s);
  });
})();
