$(function(){

  const API = '';  // même origine — URL relatives

  /* ── SUBNAV ── */
  $('.snb').on('click',function(){
    $('.snb').removeClass('active');
    $(this).addClass('active');
    $('.view').removeClass('active');
    $('#view-'+$(this).data('view')).addClass('active');
  });

  /* ── OVERLAYS ── */
  $('#btnOpenRos').on('click',()=>{ populateRosSelects(); $('#mRos').addClass('open'); });
  $('#btnOpenHost').on('click',()=>{ resetHost(); $('#mHost').addClass('open'); });
  $('#btnOpenCfg').on('click', ()=>{ resetCfg();  $('#mCfg').addClass('open');  });
  $('[data-close]').on('click',function(){ $('#'+$(this).data('close')).removeClass('open'); });
  $('.overlay').on('click',function(e){ if(e.target===this) $(this).removeClass('open'); });

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

  /* ── HOST MODAL ── */
  initTags('ipWrap','ipInput','ipErr',validIP);

  $('#hostSubnet').on('input', function(){
    $(this).removeClass('is-invalid is-valid');
    $('#subnetErr').removeClass('show');
  });

  function resetHost(){
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

    const payload = {
      name: nom,
      description: $('#hostDesc').val().trim(),
      ipAddresses: ips.join(','),
      subnet: sn,
      environment: env,
      type: parseInt(typ)
    };

    $.ajax({ url: API+'/api/ros/Host', method:'POST', contentType:'application/json', data: JSON.stringify(payload) })
      .done(function(id){
        hostsData.push(Object.assign({ id }, payload));
        renderHosts();
        updateKpis();
        $('#mHost').removeClass('open');
      })
      .fail(function(){ alert('Erreur lors de la création du host.'); });
  });

  /* ── CONFIG MODAL ── */
  initTags('portWrap','portInput','portErr',validPort);
  initTags('plageWrap','plageInput','plageErr',validRange);

  function resetCfg(){
    $('#cfgNom,#cfgDesc').val('').removeClass('is-invalid');
    $('#portWrap,#plageWrap').find('.tag').remove();
    $('#portWrap,#plageWrap').removeClass('wrap-invalid');
    $('#portErr,#plageErr').removeClass('show');
    $('#cfgNet,#cfgApp').val([]).removeClass('is-invalid');
  }

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

    const payload = {
      name: nom,
      description: $('#cfgDesc').val().trim(),
      ports: ports.join(','),
      networkProtocol: nets.join(','),
      applicativeProtocols: apps.join(','),
      bands: plages.join(',')
    };

    $.ajax({ url: API+'/api/ros/Config', method:'POST', contentType:'application/json', data: JSON.stringify(payload) })
      .done(function(id){
        cfgsData.push(Object.assign({ id }, payload));
        renderConfigs();
        updateKpis();
        $('#mCfg').removeClass('open');
      })
      .fail(function(){ alert('Erreur lors de la création de la config.'); });
  });

  /* ── ROS MODAL ── */
  $('#saveRos').on('click',function(){
    const nom=$('#rosNom').val().trim();
    const desc=$('#rosDesc').val().trim();
    const date=$('#rosDate').val();
    if(!nom){ $('#rosNom').addClass('is-invalid'); return; } else $('#rosNom').removeClass('is-invalid');
    if(!date){ $('#rosDate').addClass('is-invalid'); return; } else $('#rosDate').removeClass('is-invalid');

    const [year,month,day]=date.split('-').map(Number);
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

    const payload = {
      infosRos: { name:nom, description:desc, creationDateYear:year, creationDateMonth:month, creationDateDay:day },
      mapping: mapping
    };

    $.ajax({ url: API+'/api/Ros', method:'POST', contentType:'application/json', data: JSON.stringify(payload) })
      .done(function(){
        loadRos();
        $('#mRos').removeClass('open');
        $('#rosNom,#rosDesc').val('');
        $('#rosDate').val('');
      })
      .fail(function(){ alert('Erreur lors de la création de la ROS.'); });
  });

  /* ── STATIC TEMPLATE ── */
  const ACT=`
    <button class="icon-btn" title="Editer"><svg viewBox="0 0 24 24"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg></button>
    <button class="icon-btn del js-del" title="Supprimer"><svg viewBox="0 0 24 24"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></button>`;

  const ACT_ROS=`
    <button class="icon-btn" title="Editer"><svg viewBox="0 0 24 24"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg></button>
    <button class="icon-btn js-csv" title="Exporter CSV"><svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg></button>
    <button class="icon-btn del js-del" title="Supprimer"><svg viewBox="0 0 24 24"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></button>`;

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
  function loadHosts(){
    return $.get(API+'/api/ros/Host')
      .done(function(data){ hostsData=data; renderHosts(); updateKpis(); })
      .fail(function(){ $('#hostsBody').html('<tr><td colspan="7" style="text-align:center;color:var(--red)">Erreur de chargement</td></tr>'); });
  }

  function loadConfigs(){
    return $.get(API+'/api/ros/Config')
      .done(function(data){ cfgsData=data; renderConfigs(); updateKpis(); })
      .fail(function(){ $('#cfgsBody').html('<tr><td colspan="7" style="text-align:center;color:var(--red)">Erreur de chargement</td></tr>'); });
  }

  function loadRos(){
    return $.get(API+'/api/Ros')
      .done(function(data){ rosData=data; renderRos(); updateKpis(); })
      .fail(function(){ $('#rosBody').html('<tr><td colspan="5" style="text-align:center;color:var(--red)">Erreur de chargement</td></tr>'); });
  }

  $.when(loadHosts(), loadConfigs(), loadRos()).done(function(){
    populateRosSelects();
    $.get(API+'/api/ros/DashBoard').done(function(dash){
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

    $.ajax({ url:API+url, method:'DELETE' })
      .done(function(){
        if(tbodyId==='hostsBody'){ hostsData=hostsData.filter(function(h){ return h.id!==id; }); renderHosts(); }
        if(tbodyId==='cfgsBody'){ cfgsData=cfgsData.filter(function(c){ return c.id!==id; }); renderConfigs(); }
        if(tbodyId==='rosBody'){ rosData=rosData.filter(function(r){ return r.id!==id; }); renderRos(); }
        updateKpis();
      })
      .fail(function(){ alert('Erreur lors de la suppression.'); });
  });

  /* ── EXPORT CSV ── */
  $(document).on('click','.js-csv',function(){
    const id=$(this).closest('tr').data('id');
    window.open(API+'/api/Ros/csv?rosId='+id);
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
