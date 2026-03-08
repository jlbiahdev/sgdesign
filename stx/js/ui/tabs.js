// ─────────────────────────────────────────────
// TABS
// ─────────────────────────────────────────────
(function ($, STX) {

  window.tabIcon = function (type) {
    if (type === 'ufx') {
      return '<svg class="ti-svg" viewBox="0 0 12 12" fill="none"><rect x="0" y="0" width="12" height="12" rx="1" fill="#217346"/><path d="M3 3L9 9M9 3L3 9" stroke="white" stroke-width="1.6" stroke-linecap="round"/></svg>';
    }
    if (type === 'monitoring') {
      return '<svg class="ti-svg" viewBox="0 0 12 12" fill="currentColor"><rect x="0"  y="7"  width="2.2" height="5"  rx=".4"/><rect x="3.3" y="5"  width="2.2" height="7"  rx=".4"/><rect x="6.6" y="2.5" width="2.2" height="9.5" rx=".4"/><rect x="9.8" y="0"  width="2.2" height="12" rx=".4"/></svg>';
    }
    if (type && type.indexOf('tool') === 0) {
      return '<svg class="ti-svg" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9.5 2.5a2.2 2.2 0 00-3 3L2.7 9.3a.75.75 0 001.1 1l3.8-3.8a2.2 2.2 0 003-3L9.2 4.9 8 3.8l1.5-1.3z"/></svg>';
    }
    // Omen: top half red, bottom half black, white center bar
    return '<svg class="ti-svg" viewBox="0 0 12 12" fill="none"><rect x="0" y="0" width="12" height="6" fill="#dc2626"/><rect x="0" y="6" width="12" height="6" fill="#111"/><rect x="0" y="5.25" width="12" height="1.5" fill="white"/></svg>';
  };

  window.addTab = function (id, label, type) {
    var $t = $(
      '<div class="sidebar-tab" data-job="' + id + '">' +
      '<span class="tab-icon">' + tabIcon(type || id) + '</span>' +
      '<span class="tab-label">' + label + '</span>' +
      '<button class="tab-close" tabindex="-1">×</button>' +
      '</div>'
    );
    $('#sidebarTabs').append($t);
  };

  window.activateTab = function (id) {
    $('.sidebar-tab').removeClass('active');
    $('.sidebar-tab[data-job="' + id + '"]').addClass('active');
    $('.job-view').removeClass('active');
    $('#view-' + id).addClass('active');
  };

  $(function () {
    // Click tab → activate
    $(document).on('click', '.sidebar-tab', function () {
      activateTab($(this).data('job'));
    });

    // Close tab — supprime l'entrée STX associée
    $(document).on('click', '.tab-close', function (e) {
      e.stopPropagation();
      var $tab = $(this).closest('.sidebar-tab');
      var id = $tab.data('job');
      STX.del('job.' + id);
      $tab.remove();
      $('#view-' + id).remove();
      var $rem = $('.sidebar-tab');
      if ($rem.length) activateTab($rem.last().data('job'));
      else $('#emptyState').show();
    });
  });

}(jQuery, window.STX));
