// ── Config ───────────────────────────────────────────────────────
// En dev (Live Server) : pointer vers le host de l'API.
// En prod (servi par le Scheduler lui-même) : laisser vide.
const API_HOST      = '';
const API           = API_HOST + '/dashboard/status';
const POLL_INTERVAL = 5000;

// ── Theme ────────────────────────────────────────────────────────
(function initTheme() {
  const saved = localStorage.getItem('hpclite-theme') || 'dark';
  document.documentElement.setAttribute('data-theme', saved);
})();

function toggleTheme() {
  const html = document.documentElement;
  const next = html.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
  html.setAttribute('data-theme', next);
  localStorage.setItem('hpclite-theme', next);
}

// ── Clock ────────────────────────────────────────────────────────
function updateClock() {
  document.getElementById('clock').textContent = new Date().toLocaleTimeString('fr-FR');
}
setInterval(updateClock, 1000);
updateClock();

// ── Helpers ──────────────────────────────────────────────────────
function fmt(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('fr-FR', {
    day:'2-digit', month:'2-digit',
    hour:'2-digit', minute:'2-digit', second:'2-digit'
  });
}

function esc(str) {
  if (str == null) return '';
  return String(str)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── Connection status ────────────────────────────────────────────
function setConnStatus(status) {
  const dot   = document.getElementById('conn-dot');
  const label = document.getElementById('conn-label');
  dot.className = 'conn-dot ' + status;
  const labels = { live:'En direct', offline:'Déconnecté', reconnecting:'Reconnexion…' };
  label.textContent = labels[status] || '—';
}

// ── Load ─────────────────────────────────────────────────────────
async function loadAll() {
  try {
    const resp = await fetch(API);
    if (!resp.ok) throw new Error(resp.status);
    const data = await resp.json();
    setConnStatus('live');
    render(data);
  } catch {
    setConnStatus('offline');
  }
}

// ── Render ───────────────────────────────────────────────────────
function render(data) {
  const schedulers   = data.schedulers   || [];
  const runners      = data.runners      || [];
  const queuedIds    = data.queued_model_job_ids || [];

  renderStats(runners, queuedIds);
  renderSchedulers(schedulers);
  renderRunners(runners);
  renderQueue(queuedIds);

  const total = runners.length;
  document.getElementById('total-label').textContent =
    total + ' runner' + (total !== 1 ? 's' : '');
}

function renderStats(runners, queuedIds) {
  const counts = { idle:0, active:0, dead:0 };
  runners.forEach(r => { if (counts[r.status] !== undefined) counts[r.status]++; });
  document.getElementById('stat-idle').textContent   = counts.idle;
  document.getElementById('stat-active').textContent = counts.active;
  document.getElementById('stat-dead').textContent   = counts.dead;
  document.getElementById('stat-queued').textContent = queuedIds.length;
}

function renderSchedulers(schedulers) {
  const el = document.getElementById('schedulers-list');
  document.getElementById('schedulers-count').textContent = schedulers.length;

  if (!schedulers.length) {
    el.innerHTML = '<div class="empty-row">Aucun scheduler en DB</div>';
    return;
  }

  el.innerHTML = schedulers.map(s => `
    <div class="scheduler-row">
      <div class="s-dot ${esc(s.status)}"></div>
      <div class="scheduler-info">
        <div class="scheduler-name">${esc(s.name)}</div>
        <div class="scheduler-host">${esc(s.host)}</div>
      </div>
      <div class="scheduler-hb">${fmt(s.heartbeat)}</div>
    </div>
  `).join('');
}

function renderRunners(runners) {
  const tbody = document.getElementById('runners-tbody');
  document.getElementById('runners-count').textContent = runners.length;

  if (!runners.length) {
    tbody.innerHTML = '<tr class="loading-row"><td colspan="5">Aucun runner en DB</td></tr>';
    return;
  }

  tbody.innerHTML = runners.map(r => {
    const statusBadge = `<span class="status-badge status-${esc(r.status)}">`
      + `<span class="r-dot ${esc(r.status)}"></span>${esc(r.status)}</span>`;

    const jobCell = r.modelJobId
      ? `<span class="td-mono" style="color:var(--cyan)">#${r.modelJobId}</span>`
      : `<span class="td-faint">—</span>`;

    const aliveInfo = r.status !== 'idle' && r.isAlive === false
      ? `<span style="color:var(--red);font-size:10px"> ⚠ stale</span>`
      : '';

    return `<tr>
      <td class="td-mono">${esc(r.name)}</td>
      <td class="td-dim">${esc(r.host)}</td>
      <td>${statusBadge}</td>
      <td>${jobCell}</td>
      <td class="td-faint">${fmt(r.heartbeat)}${aliveInfo}</td>
    </tr>`;
  }).join('');
}

function renderQueue(queuedIds) {
  const el = document.getElementById('queue-list');
  document.getElementById('queue-count').textContent = queuedIds.length;

  if (!queuedIds.length) {
    el.innerHTML = '<div class="empty-row">Aucun job en attente</div>';
    return;
  }

  el.innerHTML = queuedIds.map(id =>
    `<div class="queue-row">
      <span class="queue-id">model_job #${id}</span>
      <span style="font-size:11px;color:var(--yellow)">en attente</span>
    </div>`
  ).join('');
}

// ── Init ─────────────────────────────────────────────────────────
setConnStatus('reconnecting');
loadAll();
setInterval(loadAll, POLL_INTERVAL);
