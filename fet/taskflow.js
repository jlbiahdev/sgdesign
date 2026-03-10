// ── Config ───────────────────────────────────────────────────────
// En dev (Live Server) : pointer vers le host de l'API.
// En prod (servi par l'API elle-même) : utiliser ''.
const API_HOST      = 'http://localhost:5024';   // ← adapter si besoin
const API           = API_HOST + '/taskflow';
const HUB           = API_HOST + '/taskflow/hub';
const POLL_INTERVAL = 30000;

// ── State ────────────────────────────────────────────────────────
let tasks           = [];
let runners         = [];
let currentDetailId = null;

// ── Theme ────────────────────────────────────────────────────────
(function initTheme() {
  const saved = localStorage.getItem('fetead-theme') || 'dark';
  document.documentElement.setAttribute('data-theme', saved);
})();

function toggleTheme() {
  const html = document.documentElement;
  const next = html.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
  html.setAttribute('data-theme', next);
  localStorage.setItem('fetead-theme', next);
}

// ── Navigation ───────────────────────────────────────────────────
function navigate(view, taskId) {
  $('.view').removeClass('active');
  $('.mode-tab').removeClass('active');
  $('#view-' + view).addClass('active');

  // Tab actif
  if (view === 'dashboard' || view === 'submit') {
    $('#tab-' + view).addClass('active');
  }

  if (view === 'detail' && taskId) loadDetail(taskId);

  window.scrollTo(0, 0);
}

// ── Clock ────────────────────────────────────────────────────────
function updateClock() {
  $('#clock').text(new Date().toLocaleTimeString('fr-FR'));
}
setInterval(updateClock, 1000);
updateClock();

// ── Helpers ──────────────────────────────────────────────────────
function fmt(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('fr-FR', {
    day:'2-digit', month:'2-digit', year:'numeric',
    hour:'2-digit', minute:'2-digit', second:'2-digit'
  });
}

function alive(ts) {
  if (!ts) return false;
  return (Date.now() - new Date(ts).getTime()) < 60000;
}

const STATE_COLORS = {
  Submitted : 'var(--yellow)',
  Running   : 'var(--cyan)',
  Finished  : 'var(--green)',
  Failed    : 'var(--orange)',
  Canceled  : 'var(--gray)',
};

function sdot(state) {
  return `<span class="s-wrap s-${state}"><span class="s-dot"></span>${state}</span>`;
}

function typeBadge(type) {
  return `<span class="${type === 'Shell' ? 'badge-shell' : 'badge-dotnet'}">${type}</span>`;
}

function canCancel(state) {
  return state === 'Submitted' || state === 'Running';
}

function esc(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── API ──────────────────────────────────────────────────────────
async function apiFetch(method, path, body) {
  const opts = { method, headers: {} };
  if (body) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const r = await fetch(API + path, opts);
  if (!r.ok) throw new Error(r.status + ' ' + r.statusText);
  if (r.status === 204) return null;
  return r.json();
}

// ── Load ─────────────────────────────────────────────────────────
function loadAll() {
  return Promise.all([
    apiFetch('GET', '/tasks').then(data => { tasks = data || []; renderTasks(); updateStats(); }),
    apiFetch('GET', '/runners').then(data => { runners = data || []; renderRunners(); }),
  ]);
}

// ── Stats ────────────────────────────────────────────────────────
function updateStats() {
  const counts = { Submitted:0, Running:0, Finished:0, Failed:0, Canceled:0 };
  tasks.forEach(t => { if (counts[t.state] !== undefined) counts[t.state]++; });
  Object.keys(counts).forEach(s => $('#stat-' + s).text(counts[s]));
  $('#total-label').text(tasks.length + ' tâche' + (tasks.length !== 1 ? 's' : ''));
}

// ── Runners ──────────────────────────────────────────────────────
function renderRunners() {
  $('#runners-count').text(runners.length);
  if (!runners.length) {
    $('#runners-list').html('<div class="empty-row">Aucun runner actif</div>');
    return;
  }
  const html = runners.map(r => {
    const ok = alive(r.lastHeartbeatAt);
    return `<div class="runner-row">
      <div class="runner-dot ${ok ? 'alive' : 'dead'}"></div>
      <div class="runner-info">
        <div class="runner-name">${esc(r.friendlyName || r.id)}</div>
        <div class="runner-id">${esc(r.id)}</div>
      </div>
      <div class="runner-hb">${fmt(r.lastHeartbeatAt)}</div>
    </div>`;
  }).join('');
  $('#runners-list').html(html);
}

// ── Tasks table ──────────────────────────────────────────────────
function renderTasks() {
  if (!tasks.length) {
    $('#tasks-tbody').html('<tr class="loading-row"><td colspan="7">Aucune tâche</td></tr>');
    return;
  }
  const sorted = [...tasks].sort((a, b) => b.id - a.id);
  const html = sorted.map(t => `
    <tr data-id="${t.id}" onclick="navigate('detail', ${t.id})">
      <td class="td-id">#${t.id}</td>
      <td class="td-type">${typeBadge(t.commandType)}</td>
      <td class="td-cmd">${esc(t.exeName)}</td>
      <td class="td-args">${esc(t.args || '—')}</td>
      <td>${sdot(t.state)}</td>
      <td class="td-date">${fmt(t.createdAt)}</td>
      <td class="td-actions" onclick="event.stopPropagation()">
        ${canCancel(t.state)
          ? `<button class="btn-table-cancel" onclick="cancelTask(${t.id})">✕</button>`
          : ''}
      </td>
    </tr>`).join('');
  $('#tasks-tbody').html(html);
}

// ── Cancel ───────────────────────────────────────────────────────
function cancelTask(id) {
  if (!confirm(`Annuler la tâche #${id} ?`)) return;
  apiFetch('DELETE', `/tasks/${id}`)
    .then(() => loadAll())
    .catch(e => alert('Erreur : ' + e.message));
}

function cancelCurrentTask() {
  if (currentDetailId) cancelTask(currentDetailId);
}

// ── Detail ───────────────────────────────────────────────────────
function loadDetail(id) {
  currentDetailId = id;
  $('#detail-id').text('#' + id);
  $('#detail-status, #detail-externalId, #detail-type, #detail-exe, #detail-args, #detail-created').text('…');
  $('#detail-cancel-btn').hide();
  $('#timeline-body').html('<div class="empty-row">Chargement…</div>');

  Promise.all([
    apiFetch('GET', `/tasks/${id}`),
    apiFetch('GET', `/tasks/${id}/history`),
  ]).then(([task, history]) => {
    renderDetailTask(task);
    renderTimeline(history);
  }).catch(e => {
    $('#timeline-body').html(`<div class="empty-row" style="color:var(--red)">${e.message}</div>`);
  });
}

function renderDetailTask(task) {
  if (!task) return;
  $('#detail-status').html(sdot(task.state));
  $('#detail-externalId').text(task.externalId ?? '—');
  $('#detail-type').html(typeBadge(task.commandType));
  $('#detail-exe').text(task.exeName ?? '—');
  $('#detail-args').text(task.args || '—');
  $('#detail-created').text(fmt(task.createdAt));
  $('#detail-cancel-btn').toggle(canCancel(task.state));
}

function renderTimeline(history) {
  if (!history || !history.length) {
    $('#timeline-body').html('<div class="empty-row">Aucun historique</div>');
    return;
  }
  const sorted = [...history].sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
  const html = sorted.map(h => {
    const color = STATE_COLORS[h.name] || 'var(--gray)';
    return `<div class="timeline-entry">
      <div class="tl-dot-wrap">
        <div class="tl-dot" style="background:${color};border-color:${color}"></div>
      </div>
      <div class="tl-body">
        <div class="tl-head">
          ${sdot(h.name)}
          <span class="tl-date">${fmt(h.createdAt)}</span>
        </div>
        ${h.serverId ? `<div class="tl-meta">Runner : ${esc(h.serverId)}</div>` : ''}
        ${h.reason   ? `<div class="tl-reason">${esc(h.reason)}</div>`         : ''}
      </div>
    </div>`;
  }).join('');
  $('#timeline-body').html(html);
}

// ── Submit ───────────────────────────────────────────────────────
function updateFormHints() {
  const type = $('#f-commandType').val();
  if (type === 'DotNet') {
    $('#f-exeName-label').text('Nom du handler');
    $('#f-exeName-hint').text('Nom exact de la propriété Name de votre ITaskHandler.');
    $('#f-args-label').text('Arguments JSON');
    $('#f-args-hint').text('Données JSON passées à ExecuteAsync(args).');
  } else {
    $('#f-exeName-label').text('Exécutable');
    $('#f-exeName-hint').text("Nom de l'exécutable ou du binaire à lancer.");
    $('#f-args-label').text('Arguments');
    $('#f-args-hint').text("Arguments passés à l'exécutable.");
  }
}

function submitTask() {
  const externalId  = parseInt($('#f-externalId').val(), 10);
  const commandType = $('#f-commandType').val();
  const exeName     = $('#f-exeName').val().trim();
  const args        = $('#f-args').val().trim() || null;

  if (!exeName) { showResult('error', 'Le champ "exécutable" est requis.'); return; }

  const payload = { externalId: isNaN(externalId) ? 0 : externalId, commandType, exeName, args };
  $('#btn-submit').prop('disabled', true).text('…');

  apiFetch('POST', '/tasks', payload)
    .then(data => {
      showResult('success', `Tâche #${data.id} soumise avec succès.`);
      $('#f-exeName, #f-args').val('');
      setTimeout(() => navigate('detail', data.id), 800);
    })
    .catch(e => showResult('error', 'Erreur : ' + e.message))
    .finally(() => $('#btn-submit').prop('disabled', false).text('➤ Soumettre'));
}

function showResult(type, msg) {
  const $r = $('#submit-result');
  $r.removeClass('success error').addClass(type).text(msg).show();
  setTimeout(() => $r.fadeOut(400), 4000);
}

// ── SignalR ──────────────────────────────────────────────────────
function setConnStatus(status) {
  const dot = $('#conn-dot'), label = $('#conn-label');
  dot.removeClass('live offline reconnecting');
  switch (status) {
    case 'live':         dot.addClass('live');         label.text('En direct');    break;
    case 'offline':      dot.addClass('offline');      label.text('Déconnecté');   break;
    case 'reconnecting': dot.addClass('reconnecting'); label.text('Reconnexion…'); break;
    default: label.text('—');
  }
}

function initSignalR() {
  const conn = new signalR.HubConnectionBuilder()
    .withUrl(HUB)
    .withAutomaticReconnect([2000, 5000, 10000, 30000])
    .configureLogging(signalR.LogLevel.Warning)
    .build();

  conn.on('TaskStateChanged', event => {
    const idx = tasks.findIndex(t => t.id === event.taskId);
    if (idx >= 0) { tasks[idx].state = event.state; renderTasks(); updateStats(); }
    else { loadAll(); }
    if (currentDetailId === event.taskId && $('#view-detail').hasClass('active')) {
      loadDetail(event.taskId);
    }
  });

  conn.on('RunnerChanged', () => {
    apiFetch('GET', '/runners').then(data => { runners = data || []; renderRunners(); });
  });

  conn.onreconnected(()  => { setConnStatus('live');         loadAll(); });
  conn.onreconnecting(() =>   setConnStatus('reconnecting'));
  conn.onclose(()        =>   setConnStatus('offline'));

  conn.start()
    .then(()  => { setConnStatus('live');    loadAll(); })
    .catch(() => { setConnStatus('offline'); loadAll(); });

  return conn;
}

// ── Init ─────────────────────────────────────────────────────────
$(function () {
  updateFormHints();
  initSignalR();
  setInterval(loadAll, POLL_INTERVAL);
});
