/* ============================================================
   3DMP · Общий роутер экранов прототипа
   Простое переключение `.screen` с историей возврата.
   Использование:
     const screen = AppRouter.create({ onShow(screen) {} });
     screen.go('screen2');
     screen.back();
   ============================================================ */

(function (global) {
  'use strict';

  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  function create(options) {
    options = options || {};
    var screens = $$('.screen');
    var history = [];
    var current = null;

    function activate(name) {
      var target = typeof name === 'string' ? $(name.charAt(0) === '#' || name.charAt(0) === '.' ? name : '#' + name) : name;
      if (!target) return;
      screens.forEach(function (s) { s.classList.toggle('active', s === target); });
      var content = $('.content');
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
    return { go: go, replace: replace, back: back, is: is, getCurrent: function () { return current; }, getHistory: function () { return history.slice(); } };
  }

  global.AppRouter = { create: create, $: $, $$: $$ };
})(window);
