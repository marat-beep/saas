/* ============================================================
   3DMP · Сквозная тема (светлая / тёмная)
   Применяется на всех страницах. Значение хранится в localStorage.
   Кнопка: плавающая (справа снизу) + любые [data-theme-toggle].
   Программно: window.toggleTheme() / window.setTheme('dark'|'light').
   ============================================================ */
(function () {
  'use strict';
  var KEY = '3dmp:theme';
  var KEY_FONT = '3dmp:fontScale';

  function currentTheme() {
    return document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
  }
  function apply(t) {
    document.documentElement.setAttribute('data-theme', t);
    document.documentElement.classList.toggle('dark', t === 'dark');
    document.documentElement.style.colorScheme = t;
    try { localStorage.setItem(KEY, t); } catch (e) {}
    var b = document.getElementById('themeFab');
    if (b) b.textContent = t === 'dark' ? '☀️' : '🌙';
    document.querySelectorAll('[data-theme-toggle]').forEach(function (el) {
      el.textContent = el.dataset.themeToggle === 'label'
        ? (t === 'dark' ? '☀️ Светлая тема' : '🌙 Тёмная тема')
        : (t === 'dark' ? '☀️' : '🌙');
    });
  }
  function setTheme(t) { apply(t === 'dark' ? 'dark' : 'light'); }
  function toggleTheme() { apply(currentTheme() === 'dark' ? 'light' : 'dark'); return currentTheme(); }

  // ---------- Размер шрифта (масштаб всей системы) ----------
  function applyFont(scale) {
    scale = Math.max(80, Math.min(150, parseInt(scale, 10) || 100));
    document.documentElement.style.fontSize = scale + '%';
    try { localStorage.setItem(KEY_FONT, String(scale)); } catch (e) {}
    document.querySelectorAll('[data-font-scale]').forEach(function (el) { el.textContent = scale + '%'; });
    return scale;
  }
  function getFontScale() { var v = 100; try { v = parseInt(localStorage.getItem(KEY_FONT), 10) || 100; } catch (e) {} return v; }
  function setFontScale(s) { return applyFont(s); }

  // Применить сохранённую тему как можно раньше
  var saved = 'light';
  try { saved = localStorage.getItem(KEY) || 'light'; } catch (e) {}
  apply(saved);

  function injectCss() {
    if (document.getElementById('themeStyle')) return;
    var s = document.createElement('style');
    s.id = 'themeStyle';
    s.textContent = '.th-fab{position:fixed;right:16px;bottom:74px;z-index:9997;width:46px;height:46px;border-radius:50%;'
      + 'border:1px solid rgba(255,255,255,.25);background:#0f172a;color:#fff;font-size:1.1rem;cursor:pointer;'
      + 'box-shadow:0 8px 22px rgba(0,0,0,.35);display:flex;align-items:center;justify-content:center;}'
      + '.th-fab:hover{transform:translateY(-2px);}';
    document.head.appendChild(s);
  }

  function makeFab() {
    if (document.getElementById('themeFab')) return;
    var b = document.createElement('button');
    b.id = 'themeFab';
    b.className = 'th-fab';
    b.type = 'button';
    b.title = 'Светлая / тёмная тема';
    b.textContent = currentTheme() === 'dark' ? '☀️' : '🌙';
    b.addEventListener('click', function () { toggleTheme(); });
    document.body.appendChild(b);
  }

  function bind() {
    document.querySelectorAll('[data-theme-toggle]').forEach(function (el) {
      el.addEventListener('click', function (e) { e.preventDefault(); toggleTheme(); });
    });
  }

  window.setTheme = setTheme;
  window.toggleTheme = toggleTheme;
  window.setFontScale = setFontScale;
  window.getFontScale = getFontScale;

  function start() { injectCss(); makeFab(); bind(); apply(currentTheme()); applyFont(getFontScale()); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
