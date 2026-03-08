using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace Runner.Server.Endpoints;

public static class TaskFlowDashboardEndpoints
{
    /// <summary>
    /// Sert le dashboard embarqué TaskFlow.
    ///
    /// Usage dans Program.cs :
    ///   app.MapTaskFlowDashboard();                 // → /taskflow/ui
    ///   app.MapTaskFlowDashboard("/mon-dashboard"); // chemin custom
    /// </summary>
    public static IEndpointRouteBuilder MapTaskFlowDashboard(
        this IEndpointRouteBuilder app,
        string path = "/taskflow/ui")
    {
        app.MapGet(path, () => Results.Content(Html, "text/html; charset=utf-8"));
        return app;
    }

    private const string Html = """
        <!DOCTYPE html>
        <html data-theme="dark">
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width,initial-scale=1"/>
        <title>TaskFlow</title>
        <link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Mono:wght@400;500&family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600&display=swap" rel="stylesheet"/>
        <style>
        *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
        :root{--red:#e2001a;--red-dark:#a80013;--red-glow:rgba(226,0,26,.11);--cyan:#0eb8c8;--green:#00c875;--yellow:#f59e0b}
        [data-theme=dark]{--bg:#0a0a0a;--bg-card:#1a1a1a;--bg-input:#111;--bg-border:#272727;--bg-border-hover:#3a3a3a;--text:#f5f5f5;--text-dim:rgba(245,245,245,.48);--text-faint:rgba(245,245,245,.18);--header-bg:rgba(10,10,10,.94);--noise:.026;--row-hover:rgba(255,255,255,.022)}
        [data-theme=light]{--bg:#f3f3f3;--bg-card:#fff;--bg-input:#f8f8f8;--bg-border:#e0e0e0;--bg-border-hover:#bbb;--text:#080808;--text-dim:rgba(8,8,8,.48);--text-faint:rgba(8,8,8,.2);--header-bg:rgba(243,243,243,.96);--noise:.015;--row-hover:rgba(0,0,0,.022)}
        body{font-family:"DM Sans",sans-serif;background:var(--bg);color:var(--text);min-height:100vh}
        body::before{content:"";position:fixed;inset:0;background-image:url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");opacity:var(--noise);pointer-events:none;z-index:0}
        .top-bar{position:fixed;top:0;left:0;right:0;height:3px;background:var(--red);z-index:300}
        header{position:fixed;top:3px;left:0;right:0;height:56px;background:var(--header-bg);backdrop-filter:blur(18px);border-bottom:1px solid var(--bg-border);display:flex;align-items:center;justify-content:space-between;padding:0 24px;z-index:200}
        .h-left{display:flex;align-items:center;gap:16px}
        .logo-title{font-family:"Bebas Neue";font-size:1.4rem;letter-spacing:.14em;color:var(--text);line-height:1}
        .logo-sub{font-family:"DM Mono";font-size:.54rem;color:var(--text-faint);letter-spacing:.1em;text-transform:uppercase;margin-top:1px}
        .h-right{display:flex;align-items:center;gap:14px}
        .sig-status{display:flex;align-items:center;gap:6px}
        .sig-dot{width:7px;height:7px;border-radius:50%;background:var(--text-faint);transition:all .3s}
        .sig-dot.live{background:var(--green);box-shadow:0 0 6px var(--green)}
        .sig-dot.dead{background:var(--red)}
        .sig-lbl{font-family:"DM Mono";font-size:.58rem;color:var(--text-faint);letter-spacing:.07em}
        .h-div{width:1px;height:22px;background:var(--bg-border)}
        .theme-tog{display:flex;align-items:center;gap:7px;cursor:pointer;user-select:none}
        .th-lbl{font-family:"DM Mono";font-size:.58rem;color:var(--text-dim);letter-spacing:.07em}
        .th-track{width:34px;height:18px;background:var(--bg-border);border-radius:9px;position:relative;border:1px solid var(--bg-border-hover)}
        .th-thumb{position:absolute;top:2px;left:2px;width:12px;height:12px;border-radius:50%;background:var(--red);transition:left .2s}
        [data-theme=light] .th-thumb{left:18px}
        main{max-width:1200px;margin:0 auto;padding:78px 24px 50px;position:relative;z-index:1}
        footer{position:fixed;bottom:0;left:0;right:0;height:22px;background:var(--bg-card);border-top:1px solid var(--bg-border);display:flex;align-items:center;justify-content:space-between;padding:0 16px;z-index:100;font-family:"DM Mono";font-size:.54rem;color:var(--text-faint);letter-spacing:.06em}
        .page-hdr{display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:22px}
        .page-title{font-family:"Bebas Neue";font-size:1.6rem;letter-spacing:.1em;color:var(--text);line-height:1}
        .page-sub{font-family:"DM Mono";font-size:.56rem;color:var(--text-faint);letter-spacing:.1em;text-transform:uppercase;margin-top:4px}
        .btn-refresh{background:transparent;color:var(--text-dim);font-family:"DM Mono";font-size:.6rem;letter-spacing:.1em;text-transform:uppercase;display:inline-flex;align-items:center;gap:6px;height:34px;padding:0 14px;border:1px solid var(--bg-border);cursor:pointer;transition:border-color .2s,color .2s;border-radius:1px}
        .btn-refresh:hover{border-color:var(--red);color:var(--text)}
        .stats-row{display:grid;grid-template-columns:repeat(5,1fr);gap:10px;margin-bottom:24px}
        @media(max-width:700px){.stats-row{grid-template-columns:repeat(3,1fr)}}
        .stat-card{background:var(--bg-card);border:1px solid var(--bg-border);padding:14px 16px;border-left:2px solid transparent}
        .stat-card.hv{border-left-color:var(--red)}
        .stat-num{font-family:"Bebas Neue";font-size:2.2rem;line-height:1;color:var(--text)}
        .stat-lbl{font-family:"DM Mono";font-size:.54rem;letter-spacing:.1em;text-transform:uppercase;color:var(--text-faint);display:flex;align-items:center;gap:5px;margin-top:3px}
        .sdot{width:8px;height:8px;border-radius:50%;display:inline-block;flex-shrink:0}
        .sdot.Submitted{background:var(--yellow)}
        .sdot.Running{background:var(--cyan);box-shadow:0 0 5px var(--cyan)}
        .sdot.Finished{background:var(--green)}
        .sdot.Failed{background:var(--red)}
        .sdot.Canceled{background:var(--text-faint)}
        .sc{display:inline-flex;align-items:center;gap:7px}
        .st{font-family:"DM Mono";font-size:.62rem;color:var(--text-dim)}
        .r-card{background:var(--bg-card);border:1px solid var(--bg-border);margin-bottom:24px;overflow:hidden}
        .r-hdr{padding:9px 14px;border-bottom:1px solid var(--bg-border);display:flex;align-items:center;gap:8px;background:var(--red)}
        .r-htitle{font-family:"Bebas Neue";font-size:.88rem;letter-spacing:.12em;color:#fff}
        .r-hcount{font-family:"DM Mono";font-size:.56rem;color:rgba(255,255,255,.6);letter-spacing:.06em;margin-left:auto}
        .r-row{display:flex;align-items:center;gap:10px;padding:9px 14px;border-bottom:1px solid var(--bg-border);transition:background .12s}
        .r-row:last-child{border-bottom:none}
        .r-row:hover{background:var(--row-hover)}
        .r-name{font-family:"DM Mono";font-size:.7rem;color:var(--text)}
        .r-id{font-family:"DM Mono";font-size:.58rem;color:var(--text-faint)}
        .r-time{font-family:"DM Mono";font-size:.58rem;color:var(--text-faint);margin-left:auto}
        .r-empty{padding:14px;font-family:"DM Mono";font-size:.62rem;color:var(--text-faint);letter-spacing:.08em;text-transform:uppercase}
        .t-card{background:var(--bg-card);border:1px solid var(--bg-border);overflow:hidden}
        .t-wrap{overflow-x:auto}
        .t-table{width:100%;border-collapse:collapse}
        .t-table thead{background:var(--red)}
        .t-table th{font-family:"Bebas Neue";color:#fff;padding:9px 12px;letter-spacing:.08em;text-align:left;white-space:nowrap}
        .t-table td{padding:9px 12px;color:var(--text-dim);border-bottom:1px solid var(--bg-border);font-family:"DM Mono";font-size:.68rem}
        .t-table tbody tr:last-child td{border-bottom:none}
        .t-table tbody tr:hover td{background:var(--row-hover)}
        .ci{color:var(--text-faint)!important}
        .ce{color:var(--text)!important}
        .ca{color:var(--text-faint)!important;max-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
        .tpill{display:inline-flex;align-items:center;padding:2px 7px;border:1px solid var(--bg-border);font-family:"DM Mono";font-size:.56rem;letter-spacing:.06em;color:var(--text-dim);border-radius:1px}
        .t-empty{padding:28px 12px;text-align:center;font-family:"DM Mono";font-size:.62rem;letter-spacing:.1em;text-transform:uppercase;color:var(--text-faint)}
        .btn-cancel{width:28px;height:28px;background:transparent;border:1px solid var(--bg-border);color:var(--text-dim);cursor:pointer;display:flex;align-items:center;justify-content:center;border-radius:1px;transition:all .15s}
        .btn-cancel:hover{border-color:var(--red);color:var(--red);background:var(--red-glow)}
        </style>
        </head>
        <body>
        <div class="top-bar"></div>
        <header>
          <div class="h-left">
            <div>
              <div class="logo-title">TaskFlow</div>
              <div class="logo-sub">Embedded Dashboard</div>
            </div>
          </div>
          <div class="h-right">
            <div class="sig-status">
              <span class="sig-dot" id="dot"></span>
              <span class="sig-lbl" id="dotlbl">OFFLINE</span>
            </div>
            <div class="h-div"></div>
            <div class="theme-tog" onclick="toggleTheme()">
              <span class="th-lbl" id="thlbl">DARK</span>
              <div class="th-track"><div class="th-thumb"></div></div>
            </div>
          </div>
        </header>

        <main>
          <div class="page-hdr">
            <div>
              <div class="page-title">Dashboard</div>
              <div class="page-sub" id="total">—</div>
            </div>
            <button class="btn-refresh" onclick="loadData()">↻ Rafraîchir</button>
          </div>

          <div class="stats-row" id="stats"></div>

          <div class="r-card">
            <div class="r-hdr">
              <span class="r-htitle">Runners actifs</span>
              <span class="r-hcount" id="rcnt">0 enregistré</span>
            </div>
            <div id="runners-body"></div>
          </div>

          <div class="t-card">
            <div class="t-wrap">
              <table class="t-table">
                <thead><tr><th>#</th><th>Type</th><th>Commande</th><th>Args</th><th>État</th><th>Créée le</th><th></th></tr></thead>
                <tbody id="tasks-body"></tbody>
              </table>
            </div>
          </div>
        </main>

        <footer>
          <span>TaskFlow Runner · Embedded Dashboard</span>
          <span id="clock"></span>
        </footer>

        <script src="https://cdn.jsdelivr.net/npm/@microsoft/signalr@8.0.7/dist/browser/signalr.min.js"></script>
        <script>
        let tasks = [], runners = [];
        const STATUSES = ['Submitted','Running','Finished','Failed','Canceled'];
        const DOT_CLR  = {Submitted:'#f59e0b',Running:'#0eb8c8',Finished:'#00c875',Failed:'#e2001a',Canceled:'rgba(245,245,245,.18)'};

        /* ── helpers ── */
        function fmt(iso){
          return new Date(iso).toLocaleString('fr-FR',{dateStyle:'short',timeStyle:'medium'});
        }
        function alive(ts){ return (Date.now()-new Date(ts).getTime())/1000 < 60; }
        function sdot(s){ return `<span class="sdot ${s}"></span>`; }
        function scell(s){ return `<span class="sc">${sdot(s)}<span class="st">${s}</span></span>`; }

        /* ── render ── */
        function renderStats(){
          const counts = Object.fromEntries(STATUSES.map(s=>[s, tasks.filter(t=>t.state===s).length]));
          document.getElementById('stats').innerHTML = STATUSES.map(s=>`
            <div class="stat-card ${counts[s]>0?'hv':''}">
              <div class="stat-num">${counts[s]}</div>
              <div class="stat-lbl">${sdot(s)} ${s}</div>
            </div>`).join('');
          document.getElementById('total').textContent =
            tasks.length + ' tâche' + (tasks.length>1?'s':'') + ' au total';
        }

        function renderRunners(){
          document.getElementById('rcnt').textContent =
            runners.length + ' enregistré' + (runners.length>1?'s':'');
          if(!runners.length){
            document.getElementById('runners-body').innerHTML =
              '<div class="r-empty">Aucun runner enregistré</div>';
            return;
          }
          document.getElementById('runners-body').innerHTML = runners.map(r=>`
            <div class="r-row">
              <span class="sdot ${alive(r.lastHeartbeatAt)?'Running':'Failed'}"></span>
              <span class="r-name">${r.friendlyName||r.id}</span>
              <span class="r-id">${r.id}</span>
              <span class="r-time">${fmt(r.lastHeartbeatAt)}</span>
            </div>`).join('');
        }

        function renderTasks(){
          if(!tasks.length){
            document.getElementById('tasks-body').innerHTML =
              '<tr><td colspan="7" class="t-empty">Aucune tâche pour l\'instant</td></tr>';
            return;
          }
          document.getElementById('tasks-body').innerHTML = tasks.map(t=>`
            <tr>
              <td class="ci">#${t.id}</td>
              <td><span class="tpill">${t.commandType}</span></td>
              <td class="ce">${t.exeName}</td>
              <td class="ca">${t.args||'—'}</td>
              <td>${scell(t.state)}</td>
              <td>${fmt(t.createdAt)}</td>
              <td>${(t.state==='Submitted'||t.state==='Running')?`
                <button class="btn-cancel" onclick="cancelTask(${t.id})" title="Annuler">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
                  </svg>
                </button>`:''}
              </td>
            </tr>`).join('');
        }

        function render(){ renderStats(); renderRunners(); renderTasks(); }

        /* ── data ── */
        async function loadData(){
          try {
            [tasks, runners] = await Promise.all([
              fetch('/taskflow/tasks').then(r=>r.json()),
              fetch('/taskflow/runners').then(r=>r.json()),
            ]);
            render();
          } catch(e){ console.error('loadData', e); }
        }

        async function cancelTask(id){
          await fetch('/taskflow/tasks/'+id,{method:'DELETE'});
          await loadData();
        }

        /* ── SignalR ── */
        function setDot(live){
          document.getElementById('dot').className = 'sig-dot '+(live?'live':'dead');
          document.getElementById('dotlbl').textContent = live?'LIVE':'OFFLINE';
        }

        const conn = new signalR.HubConnectionBuilder()
          .withUrl('/taskflow/hub')
          .withAutomaticReconnect()
          .configureLogging(signalR.LogLevel.Warning)
          .build();

        conn.on('TaskStateChanged', evt => {
          tasks = tasks.map(t => t.id===evt.taskId ? {...t, state: evt.state} : t);
          render();
        });
        conn.on('RunnerChanged', () => {
          fetch('/taskflow/runners').then(r=>r.json()).then(data=>{ runners=data; renderRunners(); });
        });
        conn.onreconnected(() => { setDot(true); loadData(); });
        conn.onclose(()    => setDot(false));

        conn.start()
          .then(() => { setDot(true); loadData(); })
          .catch(e => { console.warn('SignalR:', e); loadData(); });

        /* ── fallback polling ── */
        setInterval(loadData, 30000);

        /* ── theme ── */
        function toggleTheme(){
          const t = document.documentElement.dataset.theme==='dark'?'light':'dark';
          document.documentElement.dataset.theme = t;
          localStorage.setItem('tf-theme', t);
          document.getElementById('thlbl').textContent = t.toUpperCase();
        }
        const saved = localStorage.getItem('tf-theme')||'dark';
        document.documentElement.dataset.theme = saved;
        document.getElementById('thlbl').textContent = saved.toUpperCase();

        /* ── clock ── */
        setInterval(()=>{
          document.getElementById('clock').textContent =
            new Date().toLocaleTimeString('fr-FR');
        }, 1000);
        </script>
        </body>
        </html>
        """;
}
