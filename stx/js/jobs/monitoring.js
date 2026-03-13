// Monitoring is a singleton view — registered for tabIcon lookup but opened via special path in openJob.
(function ($, JobRegistry) {

  window.buildMonitoring = function () {
    return (
      '<div class="job-view" id="view-monitoring">' +
      '<div class="monitor-filters">' +
      '<input type="text" class="mf-id f-input-sm"       placeholder="Job Id"       style="width:80px">' +
      '<input type="text" class="mf-name f-input-sm"     placeholder="Job Name"     style="width:180px">' +
      '<input type="text" class="mf-account f-input-sm"  placeholder="Account Name" style="width:140px">' +
      '<input type="text" class="mf-priority f-input-sm" placeholder="Priority"     style="width:100px">' +
      '<label><input type="checkbox" class="mf-fullview"> Full View</label>' +
      '<div class="mf-sep"></div>' +
      '<div class="mf-states">' +
        '<button class="mf-state-btn" data-state="running"   type="button"><span class="state-dot running"></span>Running</button>' +
        '<button class="mf-state-btn" data-state="pending"   type="button"><span class="state-dot pending"></span>Queued</button>' +
        '<button class="mf-state-btn" data-state="done"      type="button"><span class="state-dot done"></span>Finished</button>' +
        '<button class="mf-state-btn" data-state="error"     type="button"><span class="state-dot error"></span>Failed</button>' +
        '<button class="mf-state-btn" data-state="cancelled" type="button"><span class="state-dot cancelled"></span>Canceled</button>' +
      '</div>' +
      '<select class="mf-refresh f-input-sm" title="Auto-refresh" style="width:86px">' +
        '<option value="0">Refresh off</option>' +
        '<option value="5000">5 sec</option>' +
        '<option value="10000">10 sec</option>' +
        '<option value="30000">30 sec</option>' +
        '<option value="60000">1 min</option>' +
      '</select>' +
      '<button class="btn-secondary btn-help-monitoring" type="button" title="Aide Monitoring" style="margin-left:auto">?</button>' +
      '</div>' +
      '<div class="monitor-wrap">' +
      '<table class="monitor-table">' +
      '<thead><tr>' +
      '<th>State</th><th>Id</th><th>Name</th><th>Progress</th><th>GDC</th>' +
      '<th>Priority</th><th>Account Name</th><th>Created</th><th>Submitted</th><th>Last Update</th>' +
      '</tr></thead>' +
      '<tbody id="monitorBody"></tbody>' +
      '</table>' +
      '</div>' +
      '</div>'
    );
  };

  // Register for label/icon lookup — openJob handles the singleton logic separately
  JobRegistry.register({
    type:     'monitoring',
    label:    'Monitoring',
    tabIcon:  'monitoring',
    build:    buildMonitoring,
    validate: null,
    init:     null,
    buildAdv: null,
    help:     null,
  });

}(jQuery, window.JobRegistry));
