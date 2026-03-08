// ─────────────────────────────────────────────
// MODALS
// ─────────────────────────────────────────────
(function ($) {

  window.openModal = function (id) {
    $('#' + id).addClass('open');
  };

  window.closeModal = function (id) {
    $('#' + id).removeClass('open');
  };

  $(function () {
    $(document).on('click', '[data-close]', function () {
      closeModal($(this).data('close'));
    });
    $('.overlay').on('click', function (e) {
      if ($(e.target).hasClass('overlay')) closeModal($(this).attr('id'));
    });
  });

}(jQuery));
