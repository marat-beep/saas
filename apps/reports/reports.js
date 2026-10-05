/* ============================================================
   3DMP Service · apps/reports — отчёты и экспорт
   Движок: assets/js/export.js (AppExport). Данные — существующие RPC.
   Роли: admin/owner/manager.
   ============================================================ */
(function () {
  'use strict';
  var ui = window.AppUI, $ = ui.qs, $$ = ui.qsa, SB = window.SB, EX = window.AppExport;
  var token = null, me = null, cur = null, rows = [], cols = [];
  function esc(v) { return ui.esc(v); }
  function day(v) { return v ? String(v).slice(0, 10) : ''; }
  function msg(t, k) { var e = $('#msg'); e.className = 'msg show ' + (k || 'info'); e.textContent = t; }
  function clearMsg() { $('#msg').className = 'msg'; }
  function rpc(n, a) { return SB.rpc(n, a).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; }); }

  var DATASETS = {
    orders: {
      name: 'Заявки', load: function () { return rpc('app_order_list', { p_token: token }); },
      cols: [{ key: 'number', label: 'Номер' }, { key: 'title', label: 'Тема' }, { key: 'customer', label: 'Заказчик' },
             { key: 'source', label: 'Источник' }, { key: 'status', label: 'Статус' }, { key: 'priority', label: 'Приоритет' },
             { key: 'created_at', label: 'Создана', value: function (r) { return day(r.created_at); } }]
    },
    naryads: {
      name: 'Наряды', load: function () { return rpc('app_naryad_list', { p_token: token }); },
      cols: [{ key: 'number', label: 'Наряд' }, { key: 'title', label: 'Название' }, { key: 'wc_name', label: 'Центр' },
             { key: 'assignee', label: 'Исполнитель' }, { key: 'status', label: 'Статус' },
             { key: 'plan_hours', label: 'План, ч', num: true }, { key: 'fact_hours', label: 'Факт, ч', num: true }]
    },
    tenders: {
      name: 'Закупки', load: function () { return rpc('app_tender_list_full', { p_token: token }); },
      cols: [{ key: 'title', label: 'Закупка' }, { key: 'category', label: 'Категория' }, { key: 'customer', label: 'Заказчик' },
             { key: 'deadline', label: 'Срок', value: function (r) { return day(r.deadline); } },
             { key: 'status', label: 'Статус' }, { key: 'bids_count', label: 'КП', num: true }]
    },
    materials: {
      name: 'Склад', load: function () { return rpc('app_material_list', { p_token: token }); },
      cols: [{ key: 'code', label: 'Код' }, { key: 'name', label: 'Материал' }, { key: 'unit', label: 'Ед.' },
             { key: 'qty', label: 'Остаток', num: true }, { key: 'min_qty', label: 'Минимум', num: true },
             { key: 'price', label: 'Цена, ₽', num: true }]
    },
    passports: {
      name: 'Паспорта', load: function () { return rpc('app_passport_list', { p_token: token }); },
      cols: [{ key: 'number', label: 'Номер' }, { key: 'product', label: 'Изделие' }, { key: 'order_number', label: 'Заявка' },
             { key: 'created_at', label: 'Создан', value: function (r) { return day(r.created_at); } }]
    }
  };

  function fillDs() {
    $('#ds').innerHTML = Object.keys(DATASETS).map(function (k) { return '<option value="' + k + '">' + DATASETS[k].name + '</option>'; }).join('');
  }
  function reportHtml() {
    return EX.reportDocument({
      brand: (me && me.tenant_name) || '3DMP Service',
      title: $('#title').value.trim() || (cur && cur.name) || 'Отчёт',
      subtitle: me && me.tenant_name ? me.tenant_name : '',
      meta: [{ k: 'Организация', v: (me && me.tenant_name) || '—' }, { k: 'Период', v: $('#period').value.trim() || '—' },
             { k: 'Дата', v: day(new Date().toISOString()) }, { k: 'Строк', v: rows.length }],
      sections: [{ title: (cur && cur.name) || 'Данные', columns: cols, rows: rows }],
      footer: 'Сформировано в 3DMP Service · ' + new Date().toLocaleString('ru-RU')
    });
  }
  function refreshPreview() { $('#preview').innerHTML = reportHtml(); }

  function loadCurrent() {
    clearMsg(); $('#preview').innerHTML = '<span class="note">Загрузка…</span>';
    cur = DATASETS[$('#ds').value]; cols = cur.cols;
    return cur.load().then(function (d) {
      rows = d || [];
      $('#info').textContent = 'Записей: ' + rows.length;
      refreshPreview();
    }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); $('#preview').innerHTML = ''; });
  }

  $('#ds').addEventListener('change', loadCurrent);
  $('#title').addEventListener('input', refreshPreview);
  $('#period').addEventListener('input', refreshPreview);

  $$('[data-fmt]').forEach(function (b) {
    b.addEventListener('click', function () {
      if (!cur || !rows.length) { msg('Нет данных для выгрузки.', 'err'); return; }
      var base = (($('#title').value.trim() || cur.name) + '_' + day(new Date().toISOString())).replace(/[^\wа-яА-ЯёЁ\-]+/g, '_').slice(0, 50);
      var fmt = b.dataset.fmt, ok = true;
      if (fmt === 'csv') ok = EX.exportCsv(base, cols, rows);
      else if (fmt === 'json') ok = EX.exportJson(base, rows);
      else if (fmt === 'doc') ok = EX.exportDoc(base, $('#title').value.trim() || cur.name, reportHtml());
      else if (fmt === 'pdf') ok = EX.exportPdf($('#title').value.trim() || cur.name, reportHtml());
      if (ok) { window.Auth.log('Экспорт ' + fmt.toUpperCase(), cur.name); ui.toast('Выгрузка ' + fmt.toUpperCase() + ' сформирована'); }
    });
  });

  function kpiReport() {
    return rpc('app_economics', { p_token: token }).then(function (r) {
      var e = (r && r[0]) || {};
      var M = function (v) { return (Number(v) || 0).toLocaleString('ru-RU'); };
      return Promise.all([
        rpc('app_order_list', { p_token: token }).catch(function () { return []; }),
        rpc('app_naryad_list', { p_token: token }).catch(function () { return []; })
      ]).then(function (rr) {
        return EX.reportDocument({
          brand: (me && me.tenant_name) || '3DMP Service',
          title: 'Сводный отчёт', subtitle: (me && me.tenant_name) || '',
          meta: [{ k: 'Дата', v: day(new Date().toISOString()) }],
          kpis: [{ label: 'Заявок', value: M(e.orders_total) }, { label: 'В работе', value: M(e.orders_open) },
                 { label: 'Брак (открыто)', value: M(e.defects_open) }, { label: 'План-часов', value: M(e.plan_hours) },
                 { label: 'Факт-часов', value: M(e.fact_hours) }, { label: 'Ниже минимума', value: M(e.low_stock) }],
          sections: [
            { title: 'Заявки', columns: [{ key: 'number', label: 'Номер' }, { key: 'title', label: 'Тема' }, { key: 'status', label: 'Статус' }], rows: rr[0] || [] },
            { title: 'Наряды', columns: [{ key: 'number', label: 'Наряд' }, { key: 'title', label: 'Название' }, { key: 'status', label: 'Статус' }, { key: 'plan_hours', label: 'План, ч', num: true }, { key: 'fact_hours', label: 'Факт, ч', num: true }], rows: rr[1] || [] }
          ],
          footer: 'Сформировано в 3DMP Service · ' + new Date().toLocaleString('ru-RU')
        });
      });
    });
  }
  $$('[data-kpi]').forEach(function (b) {
    b.addEventListener('click', function () {
      kpiReport().then(function (html) {
        var ok = (b.dataset.kpi === 'doc') ? EX.exportDoc('svodny_otchet_' + day(new Date().toISOString()), 'Сводный отчёт', html) : EX.exportPdf('Сводный отчёт', html);
        if (ok) window.Auth.log('Сводный отчёт', b.dataset.kpi.toUpperCase());
      }).catch(function (e) { msg('Ошибка: ' + e.message, 'err'); });
    });
  });

  $('#logout').addEventListener('click', function () { window.Auth.logout(); location.href = '../../index.html'; });

  window.Auth.guard('../auth/index.html').then(function (s) {
    if (!s) return;
    if (!window.Auth.isStaff(s.role)) { location.href = '../dashboard/index.html'; return; }
    me = s; token = s.token;
    $('#who').textContent = s.login + (s.full_name ? ' · ' + s.full_name : '');
    if (!SB) { msg('Supabase не подключён.', 'err'); return; }
    fillDs(); loadCurrent();
  });
})();
