/* ============================================================
   3DMP Service · apps/announcements — управление объявлениями (W1).
   Данные: 0116 (app_announcements_all/save/delete, app_announcement_read).
   Баннер на главной читает app_announcements_active (assets/js/hero-ann.js).
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, SB = window.SB;
  var token = null, me = null, rows = [], tenants = [];

  var KINDS = {
    info: { l: 'Информация', c: 'k-info' },
    release: { l: 'Релиз', c: 'k-release' },
    maintenance: { l: 'Плановые тех.работы', c: 'k-maintenance' },
    critical: { l: 'Критично', c: 'k-critical' }
  };

  function esc(v) { return ui.esc(v); }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function msg(t, k) { var e = $('#msg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function cell(l, v) { return '<div class="kpi"><small>' + l + '</small><b>' + v + '</b></div>'; }

  function pad(n) { return ('0' + n).slice(-2); }
  function toLocalInput(iso) {
    if (!iso) return '';
    var d = new Date(iso); if (isNaN(d.getTime())) return '';
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }
  function fromLocalInput(v) {
    if (!v) return null;
    var d = new Date(v);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  function fmtDT(iso) {
    if (!iso) return '—';
    var d = new Date(iso); if (isNaN(d.getTime())) return '—';
    return d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' });
  }
  function statusOf(a) {
    if (!a.active) return { l: 'Скрыто', k: 'off' };
    if (a.reached) return { l: 'Активно', k: 'on' };
    var now = Date.now();
    if (a.starts_at && new Date(a.starts_at).getTime() > now) return { l: 'Запланировано', k: 'wait' };
    return { l: 'Истекло', k: 'off' };
  }

  function renderKpi() {
    var act = rows.filter(function (a) { return a.reached; }).length;
    var plat = rows.filter(function (a) { return a.scope === 'platform'; }).length;
    var reads = rows.reduce(function (s, a) { return s + (a.reads || 0); }, 0);
    $('#kpis').innerHTML = cell('Всего', rows.length) + cell('Активных', act) + cell('Платформенных', plat) + cell('Прочтений', reads);
  }

  function render() {
    renderKpi();
    $('#list').innerHTML = rows.length ? '<div class="tbl-wrap"><table class="tbl"><thead><tr>' +
      '<th>Тип</th><th>Заголовок</th><th>Область</th><th>Период</th><th>Статус</th><th class="num">Прочтений</th><th>Действия</th>' +
      '</tr></thead><tbody>' + rows.map(function (a) {
        var k = KINDS[a.kind] || KINDS.info, st = statusOf(a);
        var period = fmtDT(a.starts_at) + (a.ends_at ? ' — ' + fmtDT(a.ends_at) : '');
        return '<tr><td><span class="an-kind ' + k.c + '">' + esc(k.l) + '</span></td>' +
          '<td><b>' + esc(a.title) + '</b>' + (a.pinned ? ' <span class="note">📌 закреплено</span>' : '') +
            (a.body ? '<div class="note">' + esc(String(a.body).slice(0, 120)) + '</div>' : '') + '</td>' +
          '<td>' + (a.scope === 'platform' ? '<span class="badge">Платформа</span>' : esc(a.tenant_name || 'Организация')) + '</td>' +
          '<td class="muted">' + esc(period) + '</td>' +
          '<td><span class="badge ' + (st.k === 'on' ? 'done' : st.k === 'off' ? 'cancelled' : '') + '">' + esc(st.l) + '</span></td>' +
          '<td class="num">' + (a.reads || 0) + '</td>' +
          '<td style="white-space:nowrap;">' +
            '<button class="act" data-edit="' + a.id + '">Изменить</button>' +
            '<button class="act" data-toggle="' + a.id + '" data-active="' + (!a.active) + '">' + (a.active ? 'Скрыть' : 'Включить') + '</button>' +
            '<button class="act danger" data-del="' + a.id + '">Удалить</button>' +
          '</td></tr>';
      }).join('') + '</tbody></table></div>' : '<span class="note">Объявлений нет. Создайте первое — «＋ Новое объявление».</span>';
    bind();
  }

  function fields(values) {
    var f = [
      { name: 'kind', label: 'Тип', type: 'select', options: Object.keys(KINDS).map(function (k) { return { value: k, label: KINDS[k].l }; }) },
      { name: 'title', label: 'Заголовок', type: 'text', required: true, placeholder: 'Например: Плановые тех.работы 12 октября' },
      { name: 'body', label: 'Текст', type: 'textarea', rows: 4 },
      { name: 'url', label: 'Ссылка (необязательно)', type: 'text', placeholder: 'index.html или apps/…', hint: 'Куда перейти из объявления.' },
      { name: 'starts_at', label: 'Начало', type: 'datetime-local' },
      { name: 'ends_at', label: 'Окончание', type: 'datetime-local' },
      { name: 'pinned', label: 'Закрепить', type: 'checkbox', hint: 'Показывать первым' },
      { name: 'active', label: 'Активно', type: 'checkbox', hint: 'Опубликовано' }
    ];
    if (me && me.role === 'admin') {
      f.push({ name: 'tenant_id', label: 'Область', type: 'select', hint: 'Платформа — для всех организаций.', options: [ { value: '', label: 'Платформа (все организации)' } ].concat(tenants.map(function (t) { return { value: t.id, label: t.name }; })) });
    }
    return f;
  }

  function openForm(a) {
    a = a || {};
    ui.formDialog({
      title: a.id ? 'Объявление' : 'Новое объявление',
      okText: a.id ? 'Сохранить' : 'Опубликовать',
      size: 'lg',
      fields: fields(),
      values: {
        kind: a.kind || 'info',
        title: a.title || '',
        body: a.body || '',
        url: a.url || '',
        starts_at: toLocalInput(a.starts_at) || toLocalInput(new Date().toISOString()),
        ends_at: toLocalInput(a.ends_at),
        pinned: a.pinned ? 'да' : '',
        active: (a.id ? a.active : true) ? 'да' : '',
        tenant_id: a.tenant_id || ''
      }
    }).then(function (v) {
      if (!v) return;
      rpc('app_announcement_save', {
        p_token: token, p_id: a.id || null, p_kind: v.kind, p_title: v.title, p_body: v.body, p_url: v.url,
        p_starts_at: fromLocalInput(v.starts_at), p_ends_at: fromLocalInput(v.ends_at),
        p_active: !!v.active, p_pinned: !!v.pinned,
        p_tenant_id: (me.role === 'admin' ? (v.tenant_id || null) : null)
      }).then(function (r) {
        var x = r && r[0];
        if (!x || !x.ok) { msg(x ? x.message : 'Ошибка', 'err'); return; }
        window.Auth.log(a.id ? 'Изменено объявление' : 'Создано объявление', v.title);
        msg(x.message, 'ok'); load();
      }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
    });
  }

  function load() {
    return rpc('app_announcements_all', { p_token: token }).then(function (r) { rows = r || []; render(); })
      .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
  }

  function bind() {
    ui.qsa('#list [data-edit]').forEach(function (b) {
      b.addEventListener('click', function () { openForm(rows.filter(function (x) { return x.id === b.dataset.edit; })[0]); });
    });
    ui.qsa('#list [data-toggle]').forEach(function (b) {
      b.addEventListener('click', function () {
        var a = rows.filter(function (x) { return x.id === b.dataset.toggle; })[0]; if (!a) return;
        rpc('app_announcement_save', {
          p_token: token, p_id: a.id, p_kind: a.kind, p_title: a.title, p_body: a.body, p_url: a.url,
          p_starts_at: a.starts_at, p_ends_at: a.ends_at, p_active: b.dataset.active === 'true', p_pinned: a.pinned,
          p_tenant_id: a.tenant_id || null
        }).then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); load(); })
          .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
      });
    });
    ui.qsa('#list [data-del]').forEach(function (b) {
      b.addEventListener('click', function () {
        if (!window.confirm('Удалить объявление?')) return;
        rpc('app_announcement_delete', { p_token: token, p_id: b.dataset.del })
          .then(function (r) { var x = r && r[0]; msg(x ? x.message : '', x && x.ok ? 'ok' : 'err'); load(); })
          .catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
      });
    });
  }

  $('#newBtn').addEventListener('click', function () { openForm(null); });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (s.role !== 'admin' && s.role !== 'owner') { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    var pre = (s.role === 'admin')
      ? rpc('app_platform_tenants', { p_token: token }).then(function (t) { tenants = t || []; }).catch(function () {})
      : Promise.resolve();
    pre.then(load);
  });
})();
