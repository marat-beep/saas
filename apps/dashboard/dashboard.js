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

  var GD = {
    core: 'Ядро: вход, кабинеты, пульт и гиды.',
    sales: 'Заявки, КП, документы, продажи и маркетинг.',
    ktpp: 'Спецификации, маршруты, нормы, УП, КТПП.',
    production: 'Наряды, MES, планирование, терминал, IIoT.',
    quality: 'ОТК, дефекты, паспорта, метрология, СМК.',
    economics: 'Себестоимость, финансы, КП и аналитика.',
    staff: 'Кадры, компетенции, оргструктура.',
    platform: 'Организации, пользователи, роли, аудит, API.',
    refs: 'Библиотека прототипов экосистемы.'
  };
  function urow(a) {
    return '<a class="urow" href="../' + a.id + '/index.html">' +
      '<span class="uic">' + a.icon + '</span><span class="lbl">' + esc(a.title) + '</span><span class="chev">›</span></a>';
  }
  function renderModules(session, list) {
    var groups = (window.AppCatalog && window.AppCatalog.groups) || [];
    var html = '';
    groups.forEach(function (g) {
      var items = list.filter(function (a) { return a.group === g.id; });
      if (!items.length) return;
      html += '<div class="ucard"><h3>' + (g.icon || '') + ' ' + esc(g.title) + '</h3>' +
        '<div class="udesc">' + esc(GD[g.id] || '') + '</div>' +
        '<div class="ulist">' + items.map(urow).join('') + '</div></div>';
    });
    var rest = list.filter(function (a) { return !a.group || !groups.some(function (g) { return g.id === a.group; }); });
    if (rest.length) html += '<div class="ucard"><h3>Прочее</h3><div class="ulist">' + rest.map(urow).join('') + '</div></div>';
    $('#modules').innerHTML = html ? '<div class="ugrid">' + html + '</div>' : '<span class="note">Модулей пока нет.</span>';
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
      rpc('app_support_ticket_list', { p_token: session.token, p_status: null, p_scope: null, p_mine: true }).catch(function () { return null; }),
      rpc('app_order_list', { p_token: session.token }).catch(function () { return null; })
    ]).then(function (res) {
      add('Новых уведомлений', res[0]);
      if (res[1]) add('Нарядов', res[1].length);
      if (res[2]) add('Моих тикетов', res[2].length);
      if (res[3]) add('Заявок', res[3].length);
    });
  }

  function wpRow(href, title, sub, status) {
    return '<a class="tenant" style="text-decoration:none;color:inherit" href="' + href + '">' +
      '<span><b>' + esc(title || '') + '</b>' + (sub ? ' <span class="note">' + esc(sub) + '</span>' : '') + '</span>' +
      '<span class="role">' + (status ? '<span class="badge">' + esc(status) + '</span>' : '') + '</span></a>';
  }
  function wpShow(title, inner, link) {
    $('#wpTitle').textContent = title;
    $('#workplace').innerHTML = inner || '<span class="note">Нет данных.</span>';
    var a = $('#wpAll'); if (a) { if (link) { a.href = link; a.style.display = ''; } else { a.style.display = 'none'; } }
    $('#workplaceCard').style.display = '';
  }
  function renderWorkplace(session) {
    if (!window.SB) return;
    var role = session.role;
    var openNar = function () { return rpc('app_naryad_list', { p_token: session.token }).then(function (l) { return (l || []).filter(function (x) { return ['done', 'closed', 'cancelled'].indexOf(x.status) < 0; }); }); };
    var p = null;
    if (role === 'qc') {
      p = rpc('app_qc_list', { p_token: session.token }).then(function (l) {
        l = (l || []).filter(function (x) { return ['done', 'closed', 'passed', 'completed'].indexOf(x.status) < 0; });
        wpShow('Рабочее место · ОТК', l.length ? l.slice(0, 6).map(function (x) { return wpRow('../qc/index.html', x.number + ' · ' + (x.product || ''), x.inspector || '', x.status); }).join('') : '<span class="note">Очередь ОТК пуста.</span>', '../qc/index.html');
      });
    } else if (role === 'supply') {
      p = rpc('app_material_list', { p_token: session.token }).then(function (l) {
        l = (l || []).filter(function (x) { return x.low; });
        wpShow('Рабочее место · Снабжение', l.length ? l.slice(0, 8).map(function (x) { return wpRow('../warehouse/index.html', x.name, (x.qty || 0) + ' / мин ' + (x.min_qty || 0) + ' ' + (x.unit || ''), 'нехватка'); }).join('') : '<span class="note">Дефицита нет.</span>', '../warehouse/index.html');
      });
    } else if (role === 'support') {
      p = rpc('app_support_ticket_list', { p_token: session.token, p_status: null, p_scope: null, p_mine: false }).then(function (l) {
        l = (l || []).filter(function (x) { return ['resolved', 'closed'].indexOf(x.status) < 0; });
        wpShow('Рабочее место · Поддержка', l.length ? l.slice(0, 6).map(function (x) { return wpRow('../support/index.html', x.number + ' · ' + (x.subject || ''), x.requester_name || '', x.priority); }).join('') : '<span class="note">Открытых тикетов нет.</span>', '../support/index.html');
      });
    } else if (['manager', 'owner', 'director', 'economist', 'chief'].indexOf(role) >= 0) {
      p = rpc('app_finance_kpi', { p_token: session.token }).then(function (r) {
        var k = (r && r[0]) || {};
        var inn = '<div class="kpi-row">' +
          '<div class="kpi"><small>Счетов</small><b>' + (k.invoices_total || 0) + '</b></div>' +
          '<div class="kpi"><small>Сумма</small><b>' + Math.round(k.sum_total || 0) + '</b></div>' +
          '<div class="kpi"><small>Оплачено</small><b>' + Math.round(k.sum_paid || 0) + '</b></div>' +
          '<div class="kpi"><small>Дебиторка</small><b>' + Math.round(k.receivable || 0) + '</b></div>' +
          '<div class="kpi"><small>Просрочено</small><b>' + (k.overdue || 0) + '</b></div></div>';
        wpShow('Рабочее место · Финансы', inn, '../finance/index.html');
      });
    } else if (['operator', 'master', 'technologist'].indexOf(role) >= 0) {
      p = openNar().then(function (l) {
        wpShow('Рабочее место · Производство', l.length ? l.slice(0, 6).map(function (x) { return wpRow('../production/index.html', x.number + ' · ' + (x.title || ''), (x.wc_name || '') + (x.assignee ? ' · ' + x.assignee : ''), x.status); }).join('') : '<span class="note">Открытых нарядов нет.</span>', '../production/index.html');
      });
    } else { return; }
    (p || Promise.resolve()).catch(function () { $('#workplaceCard').style.display = 'none'; });
  }

  function renderOrders(session) {
    if (!window.SB) return;
    var ST = { new: 'Новая', open: 'Открыта', in_progress: 'В работе', waiting: 'Ожидание', done: 'Выполнена', closed: 'Закрыта', cancelled: 'Отменена' };
    rpc('app_order_list', { p_token: session.token }).then(function (list) {
      list = list || [];
      if (!list.length) { $('#orders').innerHTML = '<span class="note">Заявок нет.</span>'; return; }
      var by = {}; list.forEach(function (o) { by[o.status] = (by[o.status] || 0) + 1; });
      var today = new Date(); today.setHours(0, 0, 0, 0);
      var overdue = list.filter(function (o) { return o.due_date && new Date(o.due_date) < today && ['done', 'closed', 'cancelled'].indexOf(o.status) < 0; }).length;
      var chips = Object.keys(by).map(function (k) {
        return '<span class="badge" style="margin:0 6px 6px 0;">' + esc(ST[k] || k) + ': <b>' + by[k] + '</b></span>';
      }).join('');
      $('#orders').innerHTML = '<div>' + chips + '</div>' +
        (overdue ? '<div class="note" style="color:#b91c1c;font-weight:700;margin-top:6px;">Просрочено: ' + overdue + '</div>' : '<div class="note" style="margin-top:6px;">Просрочек нет.</div>');
    }).catch(function () { $('#orders').innerHTML = '<span class="note">Недоступно.</span>'; });
  }

  function renderMes(session) {
    if (!window.SB) return;
    rpc('app_mes_board', { p_token: session.token }).then(function (list) {
      list = (list || []).filter(function (t) { return t.status !== 'done'; });
      list.sort(function (a, b) {
        var ao = (a.operator === session.login) ? 0 : 1, bo = (b.operator === session.login) ? 0 : 1;
        return ao - bo;
      });
      var show = list.slice(0, 6);
      $('#mes').innerHTML = show.length ? show.map(function (t) {
        return '<a class="tenant" style="text-decoration:none;color:inherit" href="../mes/index.html"><span>' +
          '<b>' + esc(t.title) + '</b> <span class="note">' + esc(t.wc_name || '') + (t.naryad_number ? ' · ' + esc(t.naryad_number) : '') + '</span></span>' +
          '<span class="role"><span class="badge">' + esc(t.status) + '</span>' + (t.operator ? ' ' + esc(t.operator) : '') + '</span></a>';
      }).join('') : '<span class="note">Открытых задач нет.</span>';
    }).catch(function () { $('#mes').innerHTML = '<span class="note">Недоступно.</span>'; });
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
    renderWorkplace(s);
    renderQuick(list);
    renderNotifications(s);
    renderOrders(s);
    renderMes(s);
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
