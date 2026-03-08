(function ($, JobRegistry) {

  function _build(id) {
    return (
      '<div class="job-view" id="view-' + id + '">' +
      '<div class="form-header">' +
      '<div>' +
      '<div class="form-title">New Custom Input Job</div>' +
      '<div class="form-title-sub">Input to Custom transformation</div>' +
      '</div>' +
      '<div class="form-actions-col">' +
      '<div class="form-actions-row">' +
      '<button class="btn-secondary btn-help-job" type="button" title="How to use">?</button>' +
      '<button class="btn-submit btn-submit-job">Submit</button>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '<div class="form-grid">' +
      '<div class="fg-lbl">Input to Custom:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<input type="text" name="inputsFolder" style="flex:1;min-width:0" placeholder="\\\\srv\\styx\\...">' +
      '<button class="btn-secondary btn-browse btn-browse-folder" type="button">Browse</button>' +
      '</div>' +
      '</div>' +
      '<div class="fg-lbl">Custom Actions:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<input type="text" name="actionsFolder" style="flex:1;min-width:0" placeholder="\\\\srv\\styx\\...">' +
      '<button class="btn-secondary btn-browse btn-browse-folder" type="button">Browse</button>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '</div>'
    );
  }

  function _validate($v, name) {
    var errs = [];
    var actions = ($v.find('[name="actionsFolder"]').val() || '').trim();
    var inputs  = ($v.find('[name="inputsFolder"]').val() || '').trim();
    if (!actions) errs.push(name + ' : you must select an action folder');
    if (!inputs)  errs.push(name + ' : you must select an inputs folder');
    return errs;
  }

  JobRegistry.register({
    type:     'custominput',
    label:    'Custom Input',
    tabIcon:  'tool',
    build:    _build,
    validate: _validate,
    init:     null,
    buildAdv: null,
    help: {
      synopsis: 'Applique des scripts d\'actions personnalisées sur un dossier d\'inputs.',
      fields: [
        ['Input to Custom', 'Chemin réseau UNC vers le dossier contenant les fichiers d\'entrée à transformer.'],
        ['Custom Actions',  'Chemin réseau UNC vers le dossier contenant les scripts d\'actions à appliquer aux inputs.'],
      ],
    },
  });

}(jQuery, window.JobRegistry));
