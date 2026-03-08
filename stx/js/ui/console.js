// ─────────────────────────────────────────────
// CONSOLE
// ─────────────────────────────────────────────
(function ($, STX) {

  window.openConsole = function () {
    $('#appLayout').addClass('console-open');
    $('#btnConsole').addClass('active');
  };

  window.closeConsole = function () {
    $('#appLayout').removeClass('console-open');
    $('#btnConsole').removeClass('active');
  };

  window.renderLog = function (ts, msg, type) {
    var cls = type === 'warn' ? 'warn' : type === 'error' ? 'error' : '';
    var $l = $('<div class="c-line ' + cls + '"><span class="ts">[' + ts + ']</span>' + msg + '</div>');
    $('#consoleBody').append($l);
    var b = $('#consoleBody')[0];
    b.scrollTop = b.scrollHeight;
  };

  var MS_48H = 48 * 60 * 60 * 1000;

  window.cLog = function (msg, type) {
    var ts = new Date().toLocaleTimeString('fr-FR');
    renderLog(ts, msg, type);
    var logs = STX.get('console') || [];
    logs.push({ ts: ts, msg: msg, type: type || '' });
    if (logs.length > 200) logs.splice(0, logs.length - 200);
    STX.set('console', logs);
    if (!STX.get('console.meta')) {
      STX.set('console.meta', { savedAt: Date.now() });
    }
  };

  $(function () {
    // Clear console storage si plus vieux que 48h
    var meta = STX.get('console.meta') || {};
    if (!meta.savedAt || (Date.now() - meta.savedAt) > MS_48H) {
      STX.del('console');
      STX.del('console.meta');
    }

    // Restore console au chargement
    var logs = STX.get('console') || [];
    logs.forEach(function (l) { renderLog(l.ts, l.msg, l.type); });

    $('#btnConsole').on('click', function () {
      $('#appLayout').hasClass('console-open') ? closeConsole() : openConsole();
    });
    $('#btnCloseConsole').on('click', closeConsole);
  });

}(jQuery, window.STX));
