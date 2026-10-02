/* ============================================================
   3DMP Service · роутер экранов (window.AppRouter)
   Переключение .screen с историей возврата.
     var screens = AppRouter.create({ onShow(s){}, onBackEmpty(){} });
     screens.go('screen-id'); screens.back();
   ============================================================ */
(function (global) {
  'use strict';

  function qs(sel, root) { return (root || document).querySelector(sel); }
  function qsa(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  function create(options) {
    options = options || {};
    var screens = qsa('.screen');
    var history = [];
    var current = null;

    function activate(name) {
      var target = typeof name === 'string'
        ? qs(name.charAt(0) === '#' || name.charAt(0) === '.' ? name : '#' + name)
        : name;
      if (!target) return;
      screens.forEach(function (s) { s.classList.toggle('active', s === target); });
      var content = qs('.content');
      if (content) content.scrollTop = 0;
      current = target;
      if (typeof options.onShow === 'function') options.onShow(target);
    }

    function go(name, opts) {
      opts = opts || {};
      if (current && opts.push !== false && current.id !== name) history.push(current.id);
      activate(name);
      return current;
    }
    function replace(name) { activate(name); }
    function back() {
      var prev = history.pop();
      if (prev) activate(prev);
      else if (typeof options.onBackEmpty === 'function') options.onBackEmpty();
      return current;
    }
    function is(name) { return !!current && current.id === name; }

    return {
      go: go, replace: replace, back: back, is: is,
      getCurrent: function () { return current; },
      getHistory: function () { return history.slice(); }
    };
  }

  global.AppRouter = { create: create, qs: qs, qsa: qsa };
})(window);
