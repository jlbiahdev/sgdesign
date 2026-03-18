let parsed=null;
const inBody=document.getElementById('inBody');
const inArea=document.getElementById('inArea');
const outArea=document.getElementById('outArea');

function setHasContent(val){inBody.classList.toggle('has-content',val);}
function clearIn(){inArea.value='';setHasContent(false);parsed=null;setStatus('inDot','inTxt','','En attente d\'entrée');setStatus('outDot','outTxt','','En attente');outArea.value='';}
function handleDrop(e){e.preventDefault();const f=e.dataTransfer.files[0];if(f)readFile(f);}
function readFile(f){const r=new FileReader();r.onload=e=>{inArea.value=e.target.result;validate();};r.readAsText(f);}
async function pasteIn(){try{inArea.value=await navigator.clipboard.readText();validate();}catch{}}
function setStatus(dot,txt,state,msg){document.getElementById(dot).className='sdot'+( state?' '+state:'');document.getElementById(txt).textContent=msg;}
function validate(){
  const v=inArea.value.trim();
  setHasContent(!!v);
  if(!v){parsed=null;setStatus('inDot','inTxt','','En attente d\'entrée');outArea.value='';setStatus('outDot','outTxt','','En attente');return;}
  try{parsed=JSON.parse(v);setStatus('inDot','inTxt','ok','JSON valide — '+v.length+' car.');convert();}
  catch(e){parsed=null;setStatus('inDot','inTxt','err','JSON invalide : '+e.message);outArea.value='';setStatus('outDot','outTxt','','En attente');}
}
function transformKeys(obj){
  if(Array.isArray(obj))return obj.map(transformKeys);
  if(obj&&typeof obj==='object'){const r={};for(const[k,v]of Object.entries(obj)){if(['x:Key','x:Type','xmlns','x:Name'].some(p=>k.startsWith(p)))continue;const nk=k.charAt(0).toLowerCase()+k.slice(1).replace(/[_-]([a-z])/g,(_,c)=>c.toUpperCase());r[nk]=transformKeys(v);}return r;}
  return obj;
}
function convert(){
  if(!parsed)return;
  const out=JSON.stringify({_meta:{convertedAt:new Date().toISOString(),source:'WPF',target:'Web',version:'1.0'},data:transformKeys(parsed)},null,2);
  outArea.value=out;
  setStatus('outDot','outTxt','ok','Conversion réussie — '+out.length+' car.');
}
function copyOut(){if(outArea.value)navigator.clipboard.writeText(outArea.value);}
function dlOut(){if(!outArea.value)return;const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([outArea.value],{type:'application/json'}));a.download='converted_web.json';a.click();}

// Paste global (Ctrl+V) — fonctionne toujours, drop zone ou non
document.addEventListener('paste', function(e) {
  if (document.activeElement === outArea) return;
  const text = e.clipboardData.getData('text');
  if (text) { inArea.value = text; validate(); }
});
