/* ============================================================
   3DMP Service · assets/js/documents.js  (X9 — общий слой документов)
   Единый просмотр/подпись/маршрут для docs/edo/kedo/service.
   Требует supabase-client.js (window.SB) и сессию (token внутри модулей).
   API: window.AppDocuments.sign(token, entityType, entityId, method, note)
        AppDocuments.signatures(token, entityType, entityId)
        AppDocuments.routes(token, entityType)
        AppDocuments.startRoute(token, entityType, entityId, routeId, title)
        AppDocuments.signDialog(token, entityType, entityId, onDone)
   ============================================================ */
(function (g) {
  'use strict';
  var SB = g.SB;

  function rpc(name, args) {
    return SB.rpc(name, args).then(function (r) { if (r.error) throw new Error(r.error.message); return r.data; });
  }
  var D = {
    sign: function (token, entityType, entityId, method, note) {
      return rpc('app_document_sign', { p_token: token, p_entity_type: entityType, p_entity_id: entityId, p_method: method || 'ПЭП', p_note: note || null });
    },
    signatures: function (token, entityType, entityId) {
      return rpc('app_document_signatures', { p_token: token, p_entity_type: entityType, p_entity_id: entityId });
    },
    routes: function (token, entityType) {
      return rpc('app_document_routes', { p_token: token, p_entity_type: entityType || '' });
    },
    startRoute: function (token, entityType, entityId, routeId, title) {
      return rpc('app_document_route_start', { p_token: token, p_entity_type: entityType, p_entity_id: entityId, p_route_id: routeId, p_title: title || null });
    },
    signDialog: function (token, entityType, entityId, onDone) {
      var ui = g.AppUI; if (!ui) return;
      ui.formDialog({ title: 'Подписать документ', okText: 'Подписать', fields: [
        { name: 'method', label: 'Метод подписи', type: 'select', options: [{ value: 'ПЭП', label: 'ПЭП' }, { value: 'УНЭП', label: 'УНЭП' }, { value: 'УКЭП', label: 'УКЭП' }, { value: 'Госключ', label: 'Госключ' }] },
        { name: 'note', label: 'Примечание', type: 'text' }
      ] }).then(function (v) {
        if (!v) return;
        D.sign(token, entityType, entityId, v.method, v.note).then(function (r) {
          var x = r && r[0]; ui.toast((x && x.message) || '', x && x.ok ? 'ok' : 'err');
          if (x && x.ok && onDone) onDone();
        });
      });
    }
  };
  g.AppDocuments = D;
})(typeof window !== 'undefined' ? window : this);
