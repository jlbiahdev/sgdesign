(function ($, JobRegistry) {

  function _build(id) {
    return (
      '<div class="job-view" id="view-' + id + '">' +
      '<div class="form-header">' +
      '<div>' +
      '<div class="form-title">New UFX Job</div>' +
      '<div class="form-title-sub">Universal Format Exchange</div>' +
      '</div>' +
      '<div class="form-actions-col">' +
      '<div class="form-actions-row">' +
      '<button class="btn-secondary btn-help-job" type="button" title="How to use">?</button>' +
      '<button class="btn-submit btn-submit-job">Submit</button>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '<div class="form-grid">' +
      '<div class="fg-lbl">Name:</div>' +
      '<div class="fg-ctrl"><input type="text" class="field-name" name="jobName" placeholder="Nom du job UFX"></div>' +
      '<div class="fg-lbl">Path:</div>' +
      '<div class="fg-ctrl">' +
      '<div class="f-row">' +
      '<input type="text" name="path" style="flex:1;min-width:0" placeholder="\\\\srv\\styx\\recette\\...">' +
      '<button class="btn-secondary btn-browse btn-browse-ufx" type="button">Browse</button>' +
      '<label style="display:flex;align-items:center;gap:6px;font-family:\'DM Mono\';font-size:.65rem;color:var(--text-dim);cursor:pointer;white-space:nowrap">' +
      '<input type="checkbox" name="isFolder"> Is Folder' +
      '</label>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '</div>'
    );
  }

  function _validate($v, name) {
    var errs = [];
    var path = ($v.find('[name="path"]').val() || '').trim();
    if (!path) errs.push(name + ' : you have to provide a path');
    return errs;
  }

  JobRegistry.register({
    type:     'ufx',
    label:    'UFX Job',
    tabIcon:  'ufx',
    build:    _build,
    validate: _validate,
    init:     null,
    buildAdv: null,
    help: {
      synopsis: 'Reporting réglementaire au format UFX — Universal Format Exchange.',
      fields: [
        ['Path',      'Chemin réseau UNC complet vers le fichier ou dossier UFX à traiter.'],
        ['Is Folder', 'Cochez cette option pour que le Browse ne liste que les dossiers (aucun fichier).'],
      ],
    },
  });

}(jQuery, window.JobRegistry));
