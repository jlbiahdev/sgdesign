/* ── FETEAD — app.js
   Code commun à toutes les pages
─────────────────────────────────── */

/* ── THEME ── */
const KEY = 'fetead-theme';
function applyTheme(t) {
  document.documentElement.setAttribute('data-theme', t);
  localStorage.setItem(KEY, t);
  document.getElementById('lblDark').style.opacity  = t === 'dark'  ? '1' : '.35';
  document.getElementById('lblLight').style.opacity = t === 'light' ? '1' : '.35';
}
function toggleTheme() {
  applyTheme(document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
}
applyTheme(localStorage.getItem(KEY) || 'dark');
