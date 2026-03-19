$(function(){

  /* ── TEMPLATES ACTIONS ── */
  const ACT=`
    <button class="icon-btn js-edit" title="Editer"><svg viewBox="0 0 24 24"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg></button>
    <button class="icon-btn del js-del" title="Supprimer"><svg viewBox="0 0 24 24"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></button>`;

  const ACT_ROS=`
    <button class="icon-btn js-edit" title="Editer"><svg viewBox="0 0 24 24"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg></button>
    <button class="icon-btn js-detail" title="Afficher le détail"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="1"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="3" y1="15" x2="21" y2="15"/><line x1="9" y1="9" x2="9" y2="21"/></svg></button>
    <button class="icon-btn js-csv" title="Télécharger CSV"><svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg></button>
    <button class="icon-btn del js-del" title="Supprimer"><svg viewBox="0 0 24 24"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></button>`;

  /* ── SUBNAV ── */
  $('.snb').on('click',function(){
    $('.snb').removeClass('active');
    $(this).addClass('active');
    $('.view').removeClass('active');
    $('#view-'+$(this).data('view')).addClass('active');
  });

  /* ── OVERLAYS ── */
  $('#btnOpenRos').on('click',function(){ resetRosModal(); populateRosSelects(); $('#mRos').addClass('open'); });
  $('#btnOpenHost').on('click',function(){ resetHost(); $('#mHost').addClass('open'); });
  $('#btnOpenCfg').on('click',function(){ resetCfg(); $('#mCfg').addClass('open'); });

  $('[data-close]').on('click',function(){
    const id=$(this).data('close');
    closeModal(id);
  });
  $('.overlay').on('click',function(e){
    if(e.target===this) closeModal($(this).attr('id'));
  });

  function closeModal(id){
    $('#'+id).removeClass('open');
    if(id==='mHost'){ editingHostId=null; $('#mHost .modal-title').text('Creer un Host'); $('#saveHost').text('Creer'); }
    if(id==='mCfg') { editingCfgId=null;  $('#mCfg .modal-title').text('Creer une Config'); $('#saveCfg').text('Enregistrer'); }
    if(id==='mRos') { resetRosModal(); }
  }

  /* ── VALIDATORS ── */
  const RE_IP   = /^((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)$/;
  const RE_CIDR = /^((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\/(3[0-2]|[12]?\d)$/;

  function validIP(v)   { return RE_IP.test(v.trim()); }
  function validCIDR(v) { v=v.trim(); return !v||RE_CIDR.test(v); }
  function validPort(v) { v=v.trim(); return /^\d+$/.test(v) && +v>=1 && +v<=65535; }
  function validRange(v){
    v=v.trim();
    if(validPort(v)) return true;
    const m=v.match(/^(\d+)-(\d+)$/);
    return m && +m[1]>=1 && +m[2]<=65535 && +m[1]<=+m[2];
  }

  /* ── TAG-INPUT ENGINE ── */
  function initTags(wrapId, inputId, errId, validator){
    const $w=$('#'+wrapId), $i=$('#'+inputId), $e=$('#'+errId);
    $w.on('click',()=>$i.trigger('focus'));
    $i.on('keydown',function(e){
      const v=$(this).val().replace(/,$/,'').trim();
      if(e.key==='Enter'||e.key===','){
        e.preventDefault();
        if(!v) return;
        if(validator(v)){
          insertTag($w,$i,v,true);
          $w.removeClass('wrap-invalid'); $e.removeClass('show');
        } else {
          $w.addClass('wrap-invalid'); $e.addClass('show');
          $(this).css('color','#e06060');
          setTimeout(()=>$(this).css('color',''),600);
        }
        $(this).val('');
      } else if(e.key==='Backspace'&&!$(this).val()){
        $w.find('.tag').last().remove();
      } else {
        $w.removeClass('wrap-invalid'); $e.removeClass('show');
      }
    });
  }

  function insertTag($wrap,$inp,val,ok){
    const cls=ok?'valid':'invalid';
    const $t=$('<span class="tag '+cls+'">'+val+'<button type="button" title="Supprimer">x</button></span>');
    $t.find('button').on('click',()=>$t.remove());
    $t.insertBefore($inp);
  }

  function getValidTags(wrapId){
    return $('#'+wrapId).find('.tag.valid').map(function(){
      return $(this).clone().find('button').remove().end().text().trim();
    }).get();
  }

  /* ── CUSTOM SELECT HELPER ── */
  function setCustomSelect(selectId, value){
    const $opt=$('#'+selectId+' .cs-option[data-value="'+value+'"]');
    if(!$opt.length) return;
    $('#'+selectId+' .cs-value').text($opt.text()).addClass('selected');
    $('#'+selectId+' .cs-option').removeClass('active');
    $opt.addClass('active');
    $('#'+selectId+' input[type=hidden]').val(value);
    $('#'+selectId+' .cs-trigger').removeClass('is-invalid');
  }

  /* ── HOST MODAL ── */
  initTags('ipWrap','ipInput','ipErr',validIP);

  $('#hostSubnet').on('input',function(){
    $(this).removeClass('is-invalid is-valid');
    $('#subnetErr').removeClass('show');
  });

  function resetHost(){
    editingHostId=null;
    $('#mHost .modal-title').text('Creer un Host');
    $('#saveHost').text('Creer');
    $('#hostNom,#hostDesc').val('').removeClass('is-invalid is-valid');
    $('#hostSubnet').val('').removeClass('is-invalid is-valid');
    $('#subnetErr').removeClass('show');
    $('#hostEnv,#hostType').val('').removeClass('is-invalid');
    $('#ipWrap').find('.tag').remove();
    $('#ipWrap').removeClass('wrap-invalid'); $('#ipErr').removeClass('show');
    $('#envSelect .cs-value').text('-- Selectionner --').removeClass('selected');
    $('#envSelect .cs-option').removeClass('active');
    $('#envSelect input[type=hidden]').val('');
    $('#envSelect .cs-trigger').removeClass('is-invalid open');
    $('#typeSelect .cs-value').text('-- Selectionner --').removeClass('selected');
    $('#typeSelect .cs-option').removeClass('active');
    $('#typeSelect input[type=hidden]').val('');
    $('#typeSelect .cs-trigger').removeClass('is-invalid open');
    $('#envErr,#typeErr').removeClass('show');
  }

  let editingHostId=null;

  $('#saveHost').on('click',function(){
    let ok=true;
    const nom=$('#hostNom').val().trim();
    if(!nom){ $('#hostNom').addClass('is-invalid'); ok=false; } else $('#hostNom').removeClass('is-invalid');
    const ips=getValidTags('ipWrap');
    if(!ips.length){ $('#ipWrap').addClass('wrap-invalid'); $('#ipErr').addClass('show'); ok=false; }
    const sn=$('#hostSubnet').val().trim();
    if(sn&&!validCIDR(sn)){ $('#hostSubnet').addClass('is-invalid'); $('#subnetErr').addClass('show'); ok=false; }
    else { $('#hostSubnet').removeClass('is-invalid'); $('#subnetErr').removeClass('show'); }
    const env=$('#hostEnv').val();
    if(!env){ $('#envSelect .cs-trigger').addClass('is-invalid'); $('#envErr').addClass('show'); ok=false; }
    else { $('#envSelect .cs-trigger').removeClass('is-invalid'); $('#envErr').removeClass('show'); }
    const typ=$('#hostType').val();
    if(!typ){ $('#typeSelect .cs-trigger').addClass('is-invalid'); $('#typeErr').addClass('show'); ok=false; }
    else { $('#typeSelect .cs-trigger').removeClass('is-invalid'); $('#typeErr').removeClass('show'); }
    if(!ok) return;

    const payload={
      name: nom,
      description: $('#hostDesc').val().trim(),
      ipAddresses: ips.join(','),
      subnet: sn,
      environment: env,
      type: parseInt(typ)
    };

    if(editingHostId!==null){
      $.ajax({ url:API_BASE + '/api/ros/Host/'+editingHostId, method:'PUT', contentType:'application/json', data:JSON.stringify(payload) })
        .done(function(){
          const idx=hostsData.findIndex(function(h){ return h.id==editingHostId; });
          if(idx!==-1) hostsData[idx]=Object.assign({},hostsData[idx],payload);
          renderHosts();
          closeModal('mHost');
        })
        .fail(function(){ alert('Erreur lors de la modification du host.'); });
    } else {
      $.ajax({ url:API_BASE + '/api/ros/Host', method:'POST', contentType:'application/json', data:JSON.stringify(payload) })
        .done(function(id){
          hostsData.push(Object.assign({ id },payload));
          renderHosts();
          updateKpis();
          closeModal('mHost');
        })
        .fail(function(){ alert('Erreur lors de la création du host.'); });
    }
  });

  /* ── CONFIG MODAL ── */
  initTags('portWrap','portInput','portErr',validPort);
  initTags('plageWrap','plageInput','plageErr',validRange);

  function resetCfg(){
    editingCfgId=null;
    $('#mCfg .modal-title').text('Creer une Config');
    $('#saveCfg').text('Enregistrer');
    $('#cfgNom,#cfgDesc').val('').removeClass('is-invalid');
    $('#portWrap,#plageWrap').find('.tag').remove();
    $('#portWrap,#plageWrap').removeClass('wrap-invalid');
    $('#portErr,#plageErr').removeClass('show');
    $('#cfgNet,#cfgApp').val([]).removeClass('is-invalid');
  }

  let editingCfgId=null;

  $('#saveCfg').on('click',function(){
    let ok=true;
    const nom=$('#cfgNom').val().trim();
    if(!nom){ $('#cfgNom').addClass('is-invalid'); ok=false; } else $('#cfgNom').removeClass('is-invalid');
    const ports=getValidTags('portWrap');
    if(!ports.length){ $('#portWrap').addClass('wrap-invalid'); $('#portErr').addClass('show'); ok=false; }
    const plages=getValidTags('plageWrap');
    if(!plages.length){ $('#plageWrap').addClass('wrap-invalid'); $('#plageErr').addClass('show'); ok=false; }
    const nets=$('#cfgNet').val();
    if(!nets||!nets.length){ $('#cfgNet').addClass('is-invalid'); ok=false; } else $('#cfgNet').removeClass('is-invalid');
    const apps=$('#cfgApp').val();
    if(!apps||!apps.length){ $('#cfgApp').addClass('is-invalid'); ok=false; } else $('#cfgApp').removeClass('is-invalid');
    if(!ok) return;

    const payload={
      name: nom,
      description: $('#cfgDesc').val().trim(),
      ports: ports.join(','),
      networkProtocol: nets.join(','),
      applicativeProtocols: apps.join(','),
      bands: plages.join(',')
    };

    if(editingCfgId!==null){
      $.ajax({ url:API_BASE + '/api/ros/Config/'+editingCfgId, method:'PUT', contentType:'application/json', data:JSON.stringify(payload) })
        .done(function(){
          const idx=cfgsData.findIndex(function(c){ return c.id==editingCfgId; });
          if(idx!==-1) cfgsData[idx]=Object.assign({},cfgsData[idx],payload);
          renderConfigs();
          closeModal('mCfg');
        })
        .fail(function(){ alert('Erreur lors de la modification de la config.'); });
    } else {
      $.ajax({ url:API_BASE + '/api/ros/Config', method:'POST', contentType:'application/json', data:JSON.stringify(payload) })
        .done(function(id){
          cfgsData.push(Object.assign({ id },payload));
          renderConfigs();
          updateKpis();
          closeModal('mCfg');
        })
        .fail(function(){ alert('Erreur lors de la création de la config.'); });
    }
  });

  /* ── ROS MODAL ── */
  let editingRosId=null;

  function resetRosModal(){
    editingRosId=null;
    $('#mRos .modal-title').text('Creer une ROS');
    $('#saveRos').text('Creer');
    $('#rosNom,#rosDesc').val('').removeClass('is-invalid');
    $('#rosDate').val('').removeClass('is-invalid');
    $('#selSrc,#selTgt,#selCfg').closest('.fg').show();
  }

  $('#saveRos').on('click',function(){
    const nom=$('#rosNom').val().trim();
    const desc=$('#rosDesc').val().trim();
    const date=$('#rosDate').val();
    if(!nom){ $('#rosNom').addClass('is-invalid'); return; } else $('#rosNom').removeClass('is-invalid');
    if(!date){ $('#rosDate').addClass('is-invalid'); return; } else $('#rosDate').removeClass('is-invalid');

    const [year,month,day]=date.split('-').map(Number);

    if(editingRosId!==null){
      const payload={ id:editingRosId, name:nom, description:desc, creationDateYear:year, creationDateMonth:month, creationDateDay:day };
      $.ajax({ url:API_BASE + '/api/Ros/'+editingRosId, method:'PUT', contentType:'application/json', data:JSON.stringify(payload) })
        .done(function(){
          const idx=rosData.findIndex(function(r){ return r.id==editingRosId; });
          if(idx!==-1) rosData[idx]=Object.assign({},rosData[idx],payload);
          renderRos();
          closeModal('mRos');
        })
        .fail(function(){ alert('Erreur lors de la modification de la ROS.'); });
    } else {
      const srcIds=$('#selSrc').val()||[];
      const tgtIds=$('#selTgt').val()||[];
      const cfgIds=$('#selCfg').val()||[];

      const mapping=[];
      srcIds.forEach(function(src){
        tgtIds.forEach(function(tgt){
          cfgIds.forEach(function(cfg){
            mapping.push({ sourceId:parseInt(src), targetId:parseInt(tgt), configId:parseInt(cfg) });
          });
        });
      });

      const payload={ infosRos:{ name:nom, description:desc, creationDateYear:year, creationDateMonth:month, creationDateDay:day }, mapping:mapping };
      $.ajax({ url:API_BASE + '/api/Ros', method:'POST', contentType:'application/json', data:JSON.stringify(payload) })
        .done(function(){
          loadRos();
          closeModal('mRos');
        })
        .fail(function(){ alert('Erreur lors de la création de la ROS.'); });
    }
  });

  /* ── EDIT ── */
  $(document).on('click','.js-edit',function(){
    const $tr=$(this).closest('tr');
    const id=$tr.data('id');
    const tbodyId=$tr.closest('tbody').attr('id');

    if(tbodyId==='hostsBody'){
      const h=hostsData.find(function(x){ return x.id==id; });
      if(!h) return;
      resetHost();
      editingHostId=id;
      $('#mHost .modal-title').text('Modifier un Host');
      $('#saveHost').text('Enregistrer');
      $('#hostNom').val(h.name);
      $('#hostDesc').val(h.description||'');
      $('#hostSubnet').val(h.subnet||'');
      const $w=$('#ipWrap'), $i=$('#ipInput');
      (h.ipAddresses||'').split(',').filter(Boolean).forEach(function(ip){ insertTag($w,$i,ip.trim(),true); });
      setCustomSelect('envSelect', h.environment);
      setCustomSelect('typeSelect', String(h.type));
      $('#mHost').addClass('open');
    }
    else if(tbodyId==='cfgsBody'){
      const c=cfgsData.find(function(x){ return x.id==id; });
      if(!c) return;
      resetCfg();
      editingCfgId=id;
      $('#mCfg .modal-title').text('Modifier une Config');
      $('#saveCfg').text('Enregistrer');
      $('#cfgNom').val(c.name);
      $('#cfgDesc').val(c.description||'');
      const $pw=$('#portWrap'), $pi=$('#portInput');
      (c.ports||'').split(',').filter(Boolean).forEach(function(p){ insertTag($pw,$pi,p.trim(),true); });
      const $lw=$('#plageWrap'), $li=$('#plageInput');
      (c.bands||'').split(',').filter(Boolean).forEach(function(b){ insertTag($lw,$li,b.trim(),true); });
      if(c.networkProtocol) $('#cfgNet').val(c.networkProtocol.split(',').map(function(s){ return s.trim(); }));
      if(c.applicativeProtocols) $('#cfgApp').val(c.applicativeProtocols.split(',').map(function(s){ return s.trim(); }));
      $('#mCfg').addClass('open');
    }
    else if(tbodyId==='rosBody'){
      const r=rosData.find(function(x){ return x.id==id; });
      if(!r) return;
      resetRosModal();
      editingRosId=id;
      $('#mRos .modal-title').text('Modifier une ROS');
      $('#saveRos').text('Enregistrer');
      $('#rosNom').val(r.name);
      $('#rosDesc').val(r.description||'');
      const d=r.creationDateYear+'-'+String(r.creationDateMonth).padStart(2,'0')+'-'+String(r.creationDateDay).padStart(2,'0');
      $('#rosDate').val(d);
      $('#selSrc,#selTgt,#selCfg').closest('.fg').hide();
      $('#mRos').addClass('open');
    }
  });

  /* ── STATE ── */
  let hostsData=[], cfgsData=[], rosData=[];

  /* ── RENDER ── */
  function renderHosts(){
    if(!hostsData.length){
      $('#hostsBody').html('<tr><td colspan="7" style="text-align:center;color:var(--text-faint)">Aucun host</td></tr>');
      return;
    }
    $('#hostsBody').html(hostsData.map(function(h){
      const ips=(h.ipAddresses||'').split(',').filter(Boolean);
      const isDev=h.environment==='Development';
      return `<tr data-id="${h.id}">
        <td class="bold" style="font-family:'DM Mono',monospace;font-size:.67rem">${h.name}</td>
        <td>${h.description||'&mdash;'}</td>
        <td>${ips.map(function(ip){ return '<span class="ip-tag">'+ip.trim()+'</span>'; }).join('')}</td>
        <td>${h.subnet?'<span class="sn-tag">'+h.subnet+'</span>':'&mdash;'}</td>
        <td><span class="badge${isDev?' dev':''}">${h.environment}</span></td>
        <td class="mono">${h.type}</td>
        <td><div class="actions-cell">${ACT}</div></td>
      </tr>`;
    }).join(''));
  }

  function renderConfigs(){
    if(!cfgsData.length){
      $('#cfgsBody').html('<tr><td colspan="7" style="text-align:center;color:var(--text-faint)">Aucune config</td></tr>');
      return;
    }
    $('#cfgsBody').html(cfgsData.map(function(c){
      const nets=(c.networkProtocol||'').split(',').filter(Boolean);
      return `<tr data-id="${c.id}">
        <td class="bold">${c.name}</td>
        <td style="font-size:.73rem">${c.description||'&mdash;'}</td>
        <td class="small">${c.ports||'&mdash;'}</td>
        <td>${nets.map(function(n){ return '<span class="pill">'+n.trim()+'</span>'; }).join(' ')}</td>
        <td class="mono" style="font-size:.67rem">${c.applicativeProtocols||'&mdash;'}</td>
        <td class="small">${c.bands||'&mdash;'}</td>
        <td><div class="actions-cell">${ACT}</div></td>
      </tr>`;
    }).join(''));
  }

  function renderRos(){
    if(!rosData.length){
      $('#rosBody').html('<tr><td colspan="5" style="text-align:center;color:var(--text-faint)">Aucune ROS</td></tr>');
      return;
    }
    $('#rosBody').html(rosData.map(function(r){
      const d=String(r.creationDateDay).padStart(2,'0')+'/'+String(r.creationDateMonth).padStart(2,'0')+'/'+r.creationDateYear;
      return `<tr data-id="${r.id}">
        <td class="bold">${r.name}</td>
        <td class="mono">${r.description||'&mdash;'}</td>
        <td class="mono">${d}</td>
        <td><span style="font-family:'DM Mono',monospace;color:var(--red);font-size:.9rem;font-weight:600">&mdash;</span></td>
        <td><div class="actions-cell">${ACT_ROS}</div></td>
      </tr>`;
    }).join(''));
  }

  function populateRosSelects(){
    if(hostsData.length){
      const opts=hostsData.map(function(h){ return '<option value="'+h.id+'">'+h.name+'</option>'; }).join('');
      $('#selSrc,#selTgt').html(opts);
    }
    if(cfgsData.length){
      const opts=cfgsData.map(function(c){ return '<option value="'+c.id+'">'+c.name+'</option>'; }).join('');
      $('#selCfg').html(opts);
    }
  }

  function updateKpis(){
    $('.kpi-v').eq(0).text(rosData.length);
    $('.kpi-v').eq(1).text(hostsData.length);
    $('.kpi-v').eq(2).text(cfgsData.length);
  }

  /* ── LOAD ── */
  function toArray(data){ return Array.isArray(data) ? data : []; }

  function loadHosts(){
    return $.get(API_BASE + '/api/ros/Host')
      .done(function(data){ hostsData=toArray(data); renderHosts(); updateKpis(); })
      .fail(function(){ $('#hostsBody').html('<tr><td colspan="7" style="text-align:center;color:var(--red)">Erreur de chargement</td></tr>'); });
  }

  function loadConfigs(){
    return $.get(API_BASE + '/api/ros/Config')
      .done(function(data){ cfgsData=toArray(data); renderConfigs(); updateKpis(); })
      .fail(function(){ $('#cfgsBody').html('<tr><td colspan="7" style="text-align:center;color:var(--red)">Erreur de chargement</td></tr>'); });
  }

  function loadRos(){
    return $.get(API_BASE + '/api/Ros')
      .done(function(data){ rosData=toArray(data); renderRos(); updateKpis(); })
      .fail(function(){ $('#rosBody').html('<tr><td colspan="5" style="text-align:center;color:var(--red)">Erreur de chargement</td></tr>'); });
  }

  $.when(loadHosts(), loadConfigs(), loadRos()).done(function(){
    populateRosSelects();
    $.get(API_BASE + '/api/ros/DashBoard').done(function(dash){
      if(dash && dash.routesCount !== undefined) $('.kpi-v').eq(3).text(dash.routesCount);
    });
  });

  /* ── DELETE ── */
  $(document).on('click','.js-del',function(){
    const $tr=$(this).closest('tr');
    const id=$tr.data('id');
    const tbodyId=$tr.closest('tbody').attr('id');

    let url='';
    if(tbodyId==='hostsBody') url='/api/ros/Host/'+id;
    else if(tbodyId==='cfgsBody') url='/api/ros/Config/'+id;
    else if(tbodyId==='rosBody') url='/api/Ros/'+id;

    if(!url||!id){ $tr.remove(); return; }

    $.ajax({ url:API_BASE + url, method:'DELETE' })
      .done(function(){
        if(tbodyId==='hostsBody'){ hostsData=hostsData.filter(function(h){ return h.id!==id; }); renderHosts(); }
        if(tbodyId==='cfgsBody'){ cfgsData=cfgsData.filter(function(c){ return c.id!==id; }); renderConfigs(); }
        if(tbodyId==='rosBody'){ rosData=rosData.filter(function(r){ return r.id!==id; }); renderRos(); }
        updateKpis();
      })
      .fail(function(){ alert('Erreur lors de la suppression.'); });
  });

  /* ── ROS EXPAND ── */
  /* ── ROS DETAIL ── */
  const ROUTE_COLS=[
    {h:'#',                    f:'row'},
    {h:'IRT Src',              f:'srcIrt'},
    {h:'Zone Src',             f:'srcZone'},
    {h:'Env Src',              f:'srcEnvironment'},
    {h:'Hostname Src',         f:'srcHostname',   cls:'col-host'},
    {h:'Real IP Src',          f:'srcRealIp'},
    {h:'Nat IP Src',           f:'srcNatIp'},
    {h:'IRT Dst',              f:'destIrt'},
    {h:'Zone Dst',             f:'destZone'},
    {h:'Env Dst',              f:'destEnvironment'},
    {h:'Hostname Dst',         f:'destHostname',  cls:'col-host'},
    {h:'Real IP Dst',          f:'destRealIp'},
    {h:'Nat IP Dst',           f:'destNatIp'},
    {h:'Port',                 f:'port'},
    {h:'Network Protocol',     f:'networkProtocol1'},
    {h:'Applicative Protocol', f:'applicativeProtocol'}
  ];

  $(document).on('click','.js-detail',function(){
    const $btn=$(this);
    const $tr=$btn.closest('tr');
    const id=$tr.data('id');
    const $existing=$('#rosBody tr.ros-detail[data-for="'+id+'"]');
    const $wrap=$tr.closest('.tbl-wrap');
    if($existing.length){ $existing.remove(); $tr.removeClass('ros-row-open'); $btn.removeClass('active'); $wrap.removeClass('detail-open'); return; }
    $('#rosBody tr.ros-detail').remove();
    $('#rosBody tr.ros-row-open').removeClass('ros-row-open');
    $('#rosBody .js-detail').removeClass('active');
    $tr.addClass('ros-row-open');
    $btn.addClass('active');
    $wrap.addClass('detail-open');
    const $detail=$('<tr class="ros-detail" data-for="'+id+'"><td colspan="5"><div class="ros-detail-inner"><span class="ros-detail-empty">Chargement...</span></div></td></tr>');
    $detail.insertAfter($tr);
    fetch(API_BASE+'/api/Ros/csv?rosId='+id)
      .then(function(r){ return r.json(); })
      .then(function(data){
        const arr=Array.isArray(data)?data:[];
        const $inner=$detail.find('.ros-detail-inner');
        if(!arr.length){ $inner.html('<span class="ros-detail-empty">Aucune route</span>'); return; }
        $tr.find('td').eq(3).html('<span style="font-family:\'DM Mono\',monospace;color:var(--red);font-size:.9rem;font-weight:600">'+arr.length+'</span>');
        $inner.html(
          '<span class="ros-detail-label">Routes ('+arr.length+')</span>'+
          '<table class="ros-detail-table"><thead><tr>'+
            ROUTE_COLS.map(function(c){ return '<th>'+c.h+'</th>'; }).join('')+
          '</tr></thead><tbody>'+
            arr.map(function(r){
              return '<tr>'+ROUTE_COLS.map(function(c){
                const v=r[c.f];
                const disp=(v!==null&&v!==undefined&&v!=='')?v:'&mdash;';
                const cls=c.cls?' class="'+c.cls+'"':'';
                const tip=(c.cls&&v)?(' title="'+String(v).replace(/"/g,'&quot;')+'"'):'';
                return '<td'+cls+tip+'>'+disp+'</td>';
              }).join('')+'</tr>';
            }).join('')+
          '</tbody></table>'
        );
      })
      .catch(function(){
        $detail.find('.ros-detail-inner').html('<span class="ros-detail-empty" style="color:var(--red)">Erreur de chargement</span>');
      });
  });

  /* ── EXPORT CSV ── */
  $(document).on('click','.js-csv',function(){
    const id=$(this).closest('tr').data('id');
    const nom=$(this).closest('tr').find('td').first().text().trim()||('ros-'+id);
    fetch(API_BASE+'/api/Ros/csv?rosId='+id)
      .then(function(r){ return r.json(); })
      .then(function(data){
        const arr=Array.isArray(data)?data:[];
        if(!arr.length) return;
        const sep=';';
        const headers=ROUTE_COLS.map(function(c){ return c.h; }).join(sep);
        const lines=arr.map(function(r){
          return ROUTE_COLS.map(function(c){
            const v=r[c.f];
            return (v!==null&&v!==undefined&&v!=='')?String(v):'';
          }).join(sep);
        });
        const csv='\uFEFF'+headers+'\n'+lines.join('\n');
        const blob=new Blob([csv],{type:'text/csv;charset=utf-8;'});
        const url=URL.createObjectURL(blob);
        const $a=$('<a>').attr('href',url).attr('download',nom+'.csv').appendTo('body');
        $a[0].click();
        $a.remove();
        setTimeout(function(){ URL.revokeObjectURL(url); },1000);
      });
  });

  /* ── CUSTOM SELECT ── */
  $(document).on('click', '.cs-trigger', function(e) {
    e.stopPropagation();
    const $wrap = $(this).closest('.custom-select');
    const isOpen = $(this).hasClass('open');
    $('.cs-trigger').removeClass('open');
    $('.cs-dropdown').removeClass('open');
    if (!isOpen) {
      $(this).addClass('open');
      $wrap.find('.cs-dropdown').addClass('open');
    }
  });

  $(document).on('click', '.cs-option', function(e) {
    e.stopPropagation();
    const $wrap = $(this).closest('.custom-select');
    const val   = $(this).data('value');
    const label = $(this).text();
    $wrap.find('.cs-value').text(label).addClass('selected');
    $wrap.find('.cs-option').removeClass('active');
    $(this).addClass('active');
    $wrap.find('input[type=hidden]').val(val);
    $wrap.find('.cs-trigger').removeClass('open is-invalid');
    $wrap.find('.cs-dropdown').removeClass('open');
    $wrap.next('.field-err').removeClass('show');
  });

  $(document).on('click', function() {
    $('.cs-trigger').removeClass('open');
    $('.cs-dropdown').removeClass('open');
  });

});
