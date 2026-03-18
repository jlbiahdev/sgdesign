$(function(){

  /* ── SUBNAV ── */
  $('.snb').on('click',function(){
    $('.snb').removeClass('active');
    $(this).addClass('active');
    $('.view').removeClass('active');
    $('#view-'+$(this).data('view')).addClass('active');
  });

  /* ── OVERLAYS ── */
  $('#btnOpenRos').on('click',()=>$('#mRos').addClass('open'));
  $('#btnOpenHost').on('click',()=>{ resetHost(); $('#mHost').addClass('open'); });
  $('#btnOpenCfg').on('click', ()=>{ resetCfg();  $('#mCfg').addClass('open');  });
  $('[data-close]').on('click',function(){ $('#'+$(this).data('close')).removeClass('open'); });
  $('.overlay').on('click',function(e){ if(e.target===this) $(this).removeClass('open'); });
  $(document).on('click','.js-del',function(){ $(this).closest('tr').remove(); });

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

  // Subnet: clear error state while typing, validate only on save
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
    $('#subnetErr').removeClass('show');
    // reset custom selects
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
    // Nom
    const nom=$('#hostNom').val().trim();
    if(!nom){ $('#hostNom').addClass('is-invalid'); ok=false; } else $('#hostNom').removeClass('is-invalid');
    // IPs
    const ips=getValidTags('ipWrap');
    if(!ips.length){ $('#ipWrap').addClass('wrap-invalid'); $('#ipErr').addClass('show'); ok=false; }
    // Subnet
    const sn=$('#hostSubnet').val().trim();
    if(sn&&!validCIDR(sn)){ $('#hostSubnet').addClass('is-invalid'); $('#subnetErr').addClass('show'); ok=false; }
    else { $('#hostSubnet').removeClass('is-invalid'); $('#subnetErr').removeClass('show'); }
    // Env
    const env=$('#hostEnv').val();
    if(!env){ $('#envSelect .cs-trigger').addClass('is-invalid'); $('#envErr').addClass('show'); ok=false; }
    else { $('#envSelect .cs-trigger').removeClass('is-invalid'); $('#envErr').removeClass('show'); }
    // Type
    const typ=$('#hostType').val();
    if(!typ){ $('#typeSelect .cs-trigger').addClass('is-invalid'); $('#typeErr').addClass('show'); ok=false; }
    else { $('#typeSelect .cs-trigger').removeClass('is-invalid'); $('#typeErr').removeClass('show'); }
    if(!ok) return;

    const desc=$('#hostDesc').val().trim();
    $('#hostsBody').append(`<tr>
      <td class="bold" style="font-family:'DM Mono',monospace;font-size:.67rem">${nom}</td>
      <td>${desc||'&mdash;'}</td>
      <td>${ips.map(ip=>'<span class="ip-tag">'+ip+'</span>').join('')}</td>
      <td>${sn?'<span class="sn-tag">'+sn+'</span>':'&mdash;'}</td>
      <td><span class="badge${env==='Development'?' dev':''}">${env}</span></td>
      <td class="mono">${typ}</td>
      <td><div class="actions-cell">${ACT}</div></td>
    </tr>`);
    $('#mHost').removeClass('open');
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

    const desc=$('#cfgDesc').val().trim();
    $('#cfgsBody').append(`<tr>
      <td class="bold">${nom}</td>
      <td style="font-size:.73rem">${desc||'&mdash;'}</td>
      <td class="small">${ports.join(', ')}</td>
      <td>${nets.map(n=>'<span class="pill">'+n+'</span>').join(' ')}</td>
      <td class="mono" style="font-size:.67rem">${apps.join(', ')}</td>
      <td class="small">${plages.join(', ')}</td>
      <td><div class="actions-cell">${ACT}</div></td>
    </tr>`);
    $('#mCfg').removeClass('open');
  });

  /* ── STATIC DATA ── */
  const ACT=`
    <button class="icon-btn" title="Editer"><svg viewBox="0 0 24 24"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg></button>
    <button class="icon-btn del js-del" title="Supprimer"><svg viewBox="0 0 24 24"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg></button>`;

  const hosts=[
    {n:'assuprdhpe01.fr.world.socgen',d:'HPE Headnode 1',ips:['184.122.82.130'],sn:'',e:'Production',t:'1'},
    {n:'assuprdhpe02.fr.world.socgen',d:'HPE Headnode 2',ips:['184.122.86.249'],sn:'',e:'Production',t:'1'},
    {n:'assuprdlen01.fr.world.socgen',d:'LENOVO Headnode 1',ips:['184.123.7.54'],sn:'',e:'Production',t:'1'},
    {n:'assuprdlen02.fr.world.socgen',d:'LENOVO Headnode 2',ips:['184.123.7.86'],sn:'',e:'Production',t:'1'},
    {n:'cvspardc2asu101-data.fr.world.socgen',d:'Stockage 1',ips:['184.122.5.22','184.122.5.60','184.122.5.43'],sn:'',e:'Production',t:'1'},
    {n:'cvspardc2asu102-data.fr.world.socgen',d:'Stockage 2',ips:['184.122.5.58','184.122.5.54','184.122.5.12'],sn:'',e:'Production',t:'1'},
    {n:'cvspar1noasu101-data.fr.world.socgen',d:'Archive 1',ips:['184.123.19.195','184.123.19.169'],sn:'',e:'Production',t:'1'},
    {n:'cvspar1noasu102-data.fr.world.socgen',d:'Archive 2',ips:['184.123.19.33','184.123.19.181'],sn:'',e:'Production',t:'1'},
    {n:'vp1dysx000dev.compute.eu-fr-paris.cloud.socgen',d:'VCS DEV',ips:['171.72.42.214'],sn:'184.122.130.0/21',e:'Development',t:'2'},
  ];
  $('#hostsBody').html(hosts.map(h=>`<tr>
    <td class="bold" style="font-family:'DM Mono',monospace;font-size:.67rem">${h.n}</td>
    <td>${h.d}</td>
    <td>${h.ips.map(ip=>'<span class="ip-tag">'+ip+'</span>').join('')}</td>
    <td>${h.sn?'<span class="sn-tag">'+h.sn+'</span>':'&mdash;'}</td>
    <td><span class="badge${h.e==='Development'?' dev':''}">${h.e}</span></td>
    <td class="mono">${h.t}</td>
    <td><div class="actions-cell">${ACT}</div></td>
  </tr>`).join(''));

  const cfgs=[
    {n:'HPC',d:'',p:'59999,443,9090,59901,59910,49152,65535',net:'TCP',app:'RDP,TELNET,HTTP,HTTPS',pl:'59999,443,9090,59901-59910,49152-65535'},
    {n:'SMB',d:'File access',p:'445',net:'TCP',app:'HTTP',pl:'&mdash;'},
    {n:'VM TCP',d:'Ports TCP VM',p:'80,139,443,445,1856,2049,3343,3389,5974,5985,5999,7997,8677,9053,9087,9090,9794,20482',net:'TCP',app:'TELNET,RDP',pl:'5022-5026,5800-5802,5969-5999,6729-6730,9090-9096,9100-9163'},
    {n:'VM TCP/UDP',d:'Ports TCP/UDP VM',p:'111,1947',net:'TCP,UDP',app:'TELNET,RDP',pl:'137-138,9892-9894'},
    {n:'VM UDP',d:'Ports UDP VM',p:'635,2048',net:'UDP',app:'HTTP,HTTPS,TELNET,RDP',pl:'&mdash;'},
  ];
  $('#cfgsBody').html(cfgs.map(c=>`<tr>
    <td class="bold">${c.n}</td>
    <td style="font-size:.73rem">${c.d||'&mdash;'}</td>
    <td class="small">${c.p}</td>
    <td><span class="pill">${c.net}</span></td>
    <td class="mono" style="font-size:.67rem">${c.app}</td>
    <td class="small">${c.pl}</td>
    <td><div class="actions-cell">${ACT}</div></td>
  </tr>`).join(''));

  /* ── CUSTOM SELECT ── */
  $(document).on('click', '.cs-trigger', function(e) {
    e.stopPropagation();
    const $wrap = $(this).closest('.custom-select');
    const isOpen = $(this).hasClass('open');
    // close all others
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
    // clear error
    $wrap.next('.field-err').removeClass('show');
  });

  $(document).on('click', function() {
    $('.cs-trigger').removeClass('open');
    $('.cs-dropdown').removeClass('open');
  });

  // Reset custom selects in resetHost
  const _origResetHost = resetHost;
  // patch resetHost to also reset custom selects
  window._resetCustomSelects = function() {
    $('#envSelect .cs-value').text('-- Selectionner --').removeClass('selected');
    $('#envSelect .cs-option').removeClass('active');
    $('#envSelect input').val('');
    $('#envSelect .cs-trigger').removeClass('is-invalid open');
    $('#typeSelect .cs-value').text('-- Selectionner --').removeClass('selected');
    $('#typeSelect .cs-option').removeClass('active');
    $('#typeSelect input').val('');
    $('#typeSelect .cs-trigger').removeClass('is-invalid open');
    $('#envErr,#typeErr').removeClass('show');
  };

});
