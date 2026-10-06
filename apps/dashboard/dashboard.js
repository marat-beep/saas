/* ============================================================
   3DMP Service · apps/dashboard — личный кабинет (современный).
   Аккаунт, KPI, быстрые действия, плитки модулей по контурам, 2FA, журнал.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs;

  function esc(v) { return ui.esc(v); }
  function fmtDT(ts) {
    if (!ts) return '—';
    var d = new Date(ts); if (isNaN(d.getTime())) return String(ts);
    return d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  }
  function rpc(n, a) { return window.SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function tfaMsg(t, k) { var e = $('#tfaMsg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }

  function visibleApps(session) {
    var apps = (window.AppCatalog && window.AppCatalog.apps) || [];
    return apps.filter(function (a) {
      if (a.id === 'auth' || a.id === 'dashboard') return false;
      if (a.roles && a.roles.indexOf(session.role) < 0) return false;
      return true;
    });
  }

  function renderAccount(session) {
    var name = session.full_name || session.login || '';
    var ini = (name.trim().split(/\s+/).map(function (w) { return w[0] || ''; }).slice(0, 2).join('') || (session.login || '?').slice(0, 1)).toUpperCase();
    $('#ava').textContent = ini;
    $('#cabName').textContent = name || 'Личный кабинет';
    $('#cabSub').textContent = (session.tenant_name ? session.tenant_name + ' · ' : '') +
      (window.Auth.roleLabel(session.role) || session.role || '') +
      ' · последний вход: ' + fmtDT(session.last_login_at);
    $('#cabBadges').innerHTML =
      '<span class="badge">' + esc(window.Auth.roleLabel(session.role) || session.role || '') + '</span>' +
      (session.tenant_name ? '<span class="badge">' + esc(session.tenant_name) + '</span>' : '') +
      '<span class="badge" id="b2fa">2FA: …</span>';
  }

  function renderKpi(session, list) {
    var groups = (window.AppCatalog && window.AppCatalog.groups) || [];
    var usedGroups = groups.filter(function (g) { return list.some(function (a) { return a.group === g.id; }); });
    $('#kpis').innerHTML =
      '<div class="kpi"><small>Модулей</small><b>' + list.length + '</b></div>' +
      '<div class="kpi"><small>Контуров</small><b>' + usedGroups.length + '</b></div>' +
      '<div class="kpi"><small>Роль</small><b style="font-size:1rem;">' + esc(window.Auth.roleLabel(session.role) || session.role || '—') + '</b></div>' +
      '<div class="kpi"><small>Организация</small><b style="font-size:1rem;">' + esc(session.tenant_name || '—') + '</b></div>';
  }

  function renderQuick(list) {
    var cand = ['orders', 'crm', 'docbuilder', 'tkp', 'bom', 'mes', 'terminal', 'qc', 'remarks', 'support'];
    var byId = {}; list.forEach(function (a) { byId[a.id] = a; });
    var items = cand.map(function (id) { return byId[id]; }).filter(Boolean).slice(0, 6);
    if (!items.length) return;
    $('#quickCard').style.display = '';
    $('#quick').innerHTML = items.map(function (a) {
      return '<a href="../' + a.id + '/index.html">' + a.icon + ' ' + esc(a.title) + '</a>';
    }).join('');
  }

  function renderModules(session, list) {
    var groups = (window.AppCatalog && window.AppCatalog.groups) || [];
    var html = '';
    groups.forEach(function (g) {
      var items = list.filter(function (a) { return a.group === g.id; });
      if (!items.length) return;
      html += '<div class="grp"><div class="grp-t">' + (g.icon || '') + ' ' + esc(g.title) + '</div>' +
        '<div class="apps-grid">' + items.map(function (a) {
          return '<a class="app-card" href="../' + a.id + '/index.html">' +
            '<div class="ic">' + a.icon + '</div><h3>' + esc(a.title) + '</h3>' +
            '<p>' + esc(a.desc || '') + '</p><span class="tag">Открыть</span></a>';
        }).join('') + '</div></div>';
    });
    // модули без контура
    var rest = list.filter(function (a) { return !a.group || !groups.some(function (g) { return g.id === a.group; }); });
    if (rest.length) {
      html += '<div class="grp"><div class="grp-t">Прочее</div><div class="apps-grid">' + rest.map(function (a) {
        return '<a class="app-card" href="../' + a.id + '/index.html"><div class="ic">' + a.icon + '</div><h3>' + esc(a.title) + '</h3><p>' + esc(a.desc || '') + '</p></a>';
      }).join('') + '</div></div>';
    }
    $('#modules').innerHTML = html || '<span class="note">Модулей пока нет.</span>';
  }

  function renderKpiLive(session) {
    if (!window.SB) return;
    function add(label, val) {
      if (val == null) return;
      var el = document.createElement('div'); el.className = 'kpi';
      el.innerHTML = '<small>' + esc(label) + '</small><b>' + esc(String(val)) + '</b>';
      $('#kpis').appendChild(el);
    }
    Promise.all([
      rpc('app_notif_unread', { p_token: session.token }).catch(function () { return null; }),
      rpc('app_naryad_list', { p_token: session.token }).catch(function () { return null; }),
      rpc('app_support_ticket_list', { p_token: session.token, p_status: null, p_scope: null, p_mine: true }).catch(function () { return null; })
    ]).then(function (res) {
      add('Новых уведомлений', res[0]);
      if (res[1]) add('Нарядов', res[1].length);
      if (res[2]) add('Моих тикетов', res[2].length);
    });
  }

  function renderNotifications(session) {
    if (!window.SB) return;
    function href(link) { if (!link) return ''; return /^apps\//.test(link) ? '../' + link.replace(/^apps\//, '') : link; }
    rpc('app_notif_list', { p_token: session.token, p_limit: 6 }).then(function (list) {
      list = list || [];
      var un = list.filter(function (n) { return !n.read_at; }).length;
      $('#notifCnt').textContent = un ? '(' + un + ' новых)' : '';
      $('#notifs').innerHTML = list.length ? list.map(function (n) {
        var h = href(n.link);
        var inner = '<span><b>' + esc(n.title) + '</b>' + (n.body ? ' <span class="note">— ' + esc(n.body) + '</span>' : '') + '</span>' +
          '<span class="role">' + fmtDT(n.created_at) + '</span>';
        return h ? '<a class="tenant" style="text-decoration:none;color:inherit" href="' + esc(h) + '">' + inner + '</a>'
                 : '<div class="tenant">' + inner + '</div>';
      }).join('') : '<span class="note">Уведомлений нет.</span>';
    }).catch(function () { $('#notifs').innerHTML = '<span class="note">Недоступно.</span>'; });
    var b = $('#notifAll');
    if (b) b.addEventListener('click', function () { rpc('app_notif_mark_all', { p_token: session.token }).then(function () { renderNotifications(session); }).catch(function () {}); });
  }

  function renderEvents(session) {
    if (!window.SB) return;
    rpc('app_my_events', { p_token: session.token, p_limit: 8 }).then(function (list) {
      list = list || [];
      if (!list.length) { $('#events').innerHTML = '<span class="note">Действий пока нет.</span>'; return; }
      $('#events').innerHTML = list.map(function (e) {
        return '<div class="tenant"><span><b>' + esc(e.action) + '</b>' +
          (e.detail ? ' <span class="note">— ' + esc(e.detail) + '</span>' : '') + '</span>' +
          '<span class="role">' + fmtDT(e.created_at) + '</span></div>';
      }).join('');
    }).catch(function () { $('#events').innerHTML = '<span class="note">Журнал недоступен.</span>'; });
  }

  function renderTfa(session) {
    if (!window.SB) return;
    rpc('app_2fa_status', { p_token: session.token }).then(function (r) {
      var st = (r && r[0]) || {};
      var b = $('#b2fa'); if (b) { b.textContent = '2FA: ' + (st.enabled ? 'включена' : 'выключена'); b.className = 'badge ' + (st.enabled ? 'done' : ''); }
      $('#tfaSetup').style.display = 'none';
      if (st.enabled) {
        $('#tfaBox').innerHTML = '<div class="tenant"><b>Статус: включена</b></div>' +
          '<div class="field mt"><label>Код для отключения</label><input id="tfaOff" inputmode="numeric" placeholder="6 цифр"></div>' +
          '<div class="btn-row mt"><button class="btn secondary" id="tfaDisable">Отключить 2FA</button></div>';
        $('#tfaDisable').addEventListener('click', function () {
          rpc('app_2fa_disable', { p_token: session.token, p_code: $('#tfaOff').value })
            .then(function (r2) { var x = r2 && r2[0]; tfaMsg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) renderTfa(session); })
            .catch(function (e) { tfaMsg('Ошибка: ' + e.message, 'err'); });
        });
      } else {
        $('#tfaBox').innerHTML = '<div class="tenant"><b>Статус: выключена</b></div>' +
          '<div class="btn-row mt"><button class="btn" id="tfaStart">Настроить 2FA</button></div>';
        $('#tfaStart').addEventListener('click', function () {
          rpc('app_2fa_setup', { p_token: session.token }).then(function (r2) {
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
    var out = $('#logout');
    if (out) { out.style.display = ''; out.addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; }); }
    if (!window.SB) return;

    var list = visibleApps(s);
    renderAccount(s);
    renderKpi(s, list);
    renderKpiLive(s);
    renderQuick(list);
    renderNotifications(s);
    renderModules(s, list);
    renderEvents(s);
    renderTfa(s);

    $('#tfaEnable').addEventListener('click', function () {
      rpc('app_2fa_enable', { p_token: s.token, p_code: $('#tfaCode').value })
        .then(function (r) { var x = r && r[0]; tfaMsg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); if (x && x.ok) { $('#tfaCode').value = ''; renderTfa(s); } })
        .catch(function (e) { tfaMsg('Ошибка: ' + e.message, 'err'); });
    });
  });
})();
