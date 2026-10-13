/* ============================================================
   3DMP Service · apps/config — A8 конфигуратор спец-технологий. Данные: 0085.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB;
  var token = null, groups = [], options = [], curGroup = '', selected = {};

  function esc(v) { return ui.esc(v); }
  function msg(id, t, k) { var e = $(id); e.className = 'msg show ' + (k || 'info'); e.textContent = t; if (!t) e.className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }
  function money(v) { return (v == null ? 0 : Number(v)).toLocaleString('ru-RU') + ' ₽'; }

  function loadGroups() {
    return rpc('app_config_groups', { p_token: token }).then(function (r) {
      groups = r || [];
      $('#groups').innerHTML = groups.length ? groups.map(function (g) {
        return '<div class="ocard" data-g="' + esc(g.group_name) + '" style="cursor:pointer;"><b>' + esc(g.group_name) + '</b>' +
          '<span class="note" style="margin-left:auto;">' + g.options + ' опций</span></div>';
      }).join('') : '<span class="note">Опций нет.</span>';
      $$('#groups [data-g]').forEach(function (b) { b.addEventListener('click', function () { openGroup(b.dataset.g); }); });
      if (!curGroup && groups.length) openGroup(groups[0].group_name);
    });
  }

  function openGroup(g) {
    curGroup = g; $('#gTitle').textContent = '· ' + g;
    return rpc('app_config_options_list', { p_token: token, p_group: g }).then(function (r) {
      options = (r || []).filter(function (o) { return o.active; });
      renderOptions();
    });
  }

  function renderOptions() {
    $('#options').innerHTML = options.length ? options.map(function (o) {
      var chk = selected[o.id] ? ' checked' : '';
      return '<label class="opt"><input type="checkbox" data-opt="' + o.id + '"' + chk + '>' +
        '<span>' + esc(o.name) + (o.note ? ' <span class="note">(' + esc(o.note) + ')</span>' : '') + '</span>' +
        '<span class="num">+' + money(o.price_delta) + '</span></label>';
    }).join('') : '<span class="note">В группе нет опций.</span>';
    $$('#options [data-opt]').forEach(function (c) { c.addEventListener('change', function () {
      if (this.checked) selected[this.dataset.opt] = true; else delete selected[this.dataset.opt];
      recalc();
    }); });
    recalc();
  }

  function recalc() {
    var ids = Object.keys(selected);
    $('#cCnt').textContent = ids.length;
    if (!ids.length) { $('#cTotal').textContent = money(0); return; }
    rpc('app_config_estimate', { p_token: token, p_ids: ids }).then(function (r) {
      var x = (r && r[0]) || {};
      $('#cTotal').textContent = money(x.total);
    }).catch(function () { $('#cTotal').textContent = money(0); });
  }

  $('#cReset').addEventListener('click', function () { selected = {}; renderOptions(); });
  function loadPresets() {
    return rpc('app_config_preset_list', { p_token: token }).then(function (rows) {
      rows = rows || [];
      $('#presets').innerHTML = rows.length ? rows.map(function (p) {
        return '<div class="opt" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;"><b>' + esc(p.name) + '</b><span class="note">опций ' + p.cnt + ' · ' + money(p.total) + '</span>' +
          '<span style="margin-left:auto;display:flex;gap:6px;"><button class="act" data-load="' + p.id + '">Загрузить</button><button class="act" data-q="' + p.id + '">КП</button><button class="act" data-del="' + p.id + '">✕</button></span></div>';
      }).join('') : '<span class="note">Шаблонов нет.</span>';
      $$('#presets [data-load]').forEach(function (b) { b.addEventListener('click', function () {
        var p = rows.filter(function (x) { return x.id === b.dataset.load; })[0]; if (!p) return;
        selected = {}; (p.options || []).forEach(function (id) { selected[String(id)] = true; });
        renderOptions(); msg('#pHMsg', 'Шаблон загружен в выбор', 'ok');
      }); });
      $$('#presets [data-q]').forEach(function (b) { b.addEventListener('click', function () {
        rpc('app_config_preset_quote', { p_token: token, p_id: b.dataset.q }).then(function (r) { var x = r && r[0]; msg('#pHMsg', x ? (x.message + ': ' + x.number + ' — ' + money(x.total)) : 'Ошибка', x && x.ok ? 'ok' : 'err'); });
      }); });
      $$('#presets [data-del]').forEach(function (b) { b.addEventListener('click', function () { rpc('app_config_preset_delete', { p_token: token, p_id: b.dataset.del }).then(function () { loadPresets(); }); }); });
    });
  }
  $('#presSave').addEventListener('click', function () {
    var ids = Object.keys(selected);
    if (!ids.length) { msg('#pHMsg', 'Выберите опции', 'err'); return; }
    ui.formDialog({ title: 'Сохранить как шаблон', okText: 'Сохранить', fields: [{ name: 'name', label: 'Название', required: true, value: 'Конфигурация ' + new Date().toISOString().slice(0, 10) }] }).then(function (v) {
      if (!v) return;
      rpc('app_config_preset_save', { p_token: token, p_id: null, p_name: v.name, p_options: ids, p_total: null, p_note: null })
        .then(function (r) { var x = r && r[0]; msg('#pHMsg', (x && x.message) || 'Готово', x && x.ok ? 'ok' : 'err'); loadPresets(); })
        .catch(function (e) { msg('#pHMsg', 'Ошибка: ' + e.message, 'err'); });
    });
  });
  $('#phBtn').addEventListener('click', function () {
    rpc('app_config_price_history_list', { p_token: token, p_option_id: null }).then(function (rows) {
      rows = rows || [];
      $('#phist').innerHTML = rows.length ? '<table class="mini"><thead><tr><th>Опция</th><th class="num">Было</th><th class="num">Стало</th><th>Кто</th><th>Когда</th></tr></thead><tbody>' +
        rows.map(function (h) { return '<tr><td>' + esc(h.option_name || '') + '</td><td class="num">' + money(h.old_price) + '</td><td class="num"><b>' + money(h.new_price) + '</b></td><td>' + esc(h.by_login || '') + '</td><td class="muted">' + new Date(h.at).toLocaleString('ru-RU') + '</td></tr>'; }).join('') + '</tbody></table>'
        : '<span class="note">Изменений цен нет.</span>';
    }).catch(function (e) { $('#phist').innerHTML = '<span class="note">Ошибка: ' + e.message + '</span>'; });
  });
  $('#fSave').addEventListener('click', function () {
    rpc('app_config_option_save', { p_token: token, p_id: null, p_group: $('#fGroup').value, p_name: $('#fName').value, p_price_delta: parseFloat($('#fPrice').value) || 0, p_note: null, p_active: true })
      .then(function (r) { var x = r && r[0]; msg('#fMsg', x ? x.message : 'Ошибка', x ? 'ok' : 'err'); $('#fName').value = ''; return loadGroups(); })
      .catch(function (e) { msg('#fMsg', 'Ошибка: ' + e.message, 'err'); });
  });
  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '') + ' · ' + (window.Auth.roleLabel(s.role) || s.role);
    if (!SB) { msg('#fMsg', 'Supabase не подключён.', 'err'); return; }
    loadGroups();
    loadPresets();
  });
})();
