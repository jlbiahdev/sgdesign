// ─────────────────────────────────────────────
// THEME & API MODE
// ─────────────────────────────────────────────
(function ($, STX, API) {
  var THEME_KEY = 'styx-theme';

  window.applyTheme = function (t) {
    $('html').attr('data-theme', t);
    localStorage.setItem(THEME_KEY, t);
    $('#lblDark').css('opacity', t === 'dark' ? 1 : .3);
    $('#lblLight').css('opacity', t === 'light' ? 1 : .3);
    $('#prefDark').toggleClass('active', t === 'dark');
    $('#prefLight').toggleClass('active', t === 'light');
  };

  window._applyApiMode = function (mode) {
    API.setMode(mode);
    STX.merge('settings', { apiMode: mode });
    $('#prefApiFake').toggleClass('active', mode === 'fake');
    $('#prefApiReal').toggleClass('active', mode === 'real');
    $('#apiRealSettings').toggle(mode === 'real');
  };

  $(function () {
    applyTheme(localStorage.getItem(THEME_KEY) || 'dark');

    $('#themeToggle').on('click', function () {
      applyTheme($('html').attr('data-theme') === 'dark' ? 'light' : 'dark');
    });
    // Delegated: ces boutons vivent dans le side panel (injecté dynamiquement)
    $(document).on('click', '#prefDark',    function () { applyTheme('dark'); });
    $(document).on('click', '#prefLight',   function () { applyTheme('light'); });
    $(document).on('click', '#prefApiFake', function () { _applyApiMode('fake'); });
    $(document).on('click', '#prefApiReal', function () { _applyApiMode('real'); });
  });
}(jQuery, window.STX, window.API));
