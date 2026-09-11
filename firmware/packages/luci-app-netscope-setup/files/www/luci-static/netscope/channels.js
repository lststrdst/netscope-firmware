/* Subscription content lives only in memory. No credentials in URLs, storage or logs. */
(function(){'use strict';
 const root=document.getElementById('netscope-setup'),panel=document.getElementById('ns-channels');if(!root||!panel)return;
 const $=id=>document.getElementById('ns-ch-'+id);let state=null,working=false,timer;
 const element=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
 const date=epoch=>epoch?new Date(epoch*1000).toLocaleTimeString('ru-RU'):'—';
 const reasons={manual:'Выбран вручную',udp_unavailable:'Две неудачные UDP-проверки',udp_slow:'Устойчиво высокая задержка',manual_probe_failed:'Выбранный узел не прошёл UDP-проверку'};
 async function api(path,data){
  const ctrl=new AbortController(),timeout=setTimeout(()=>ctrl.abort(),25000);
  try{const r=await fetch(root.dataset.api+'/'+path,{method:data?'POST':'GET',credentials:'same-origin',cache:'no-store',signal:ctrl.signal,
   ...(data?{headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({...data,token:root.dataset.token})}:{})});
   if(!(r.headers.get('content-type')||'').includes('json'))throw Error('Войдите в роутер заново');const v=await r.json();if(!r.ok||v.error)throw Error(v.error||'Запрос не выполнен');return v;
  }finally{clearTimeout(timeout);}
 }
 function message(text,error=false){$('message').textContent=text;$('message').classList.toggle('error',error);}
 function render(s){
  state=s;$('mode').textContent=s.mode==='auto'?'Автоматический выбор':'Ручной выбор';
  $('auto').setAttribute('aria-pressed',String(s.mode==='auto'));$('manual').setAttribute('aria-pressed',String(s.mode!=='auto'));
  const active=(s.nodes||[]).find(n=>n.active);$('active').textContent=active?active.label:'Канал не выбран';
  $('health').textContent=!s.enabled?'Маршрут выключен или автозапуск не настроен':s.daemon_alive?'Контроль UDP работает':'Проверки ещё не запущены';
  $('count').textContent=(s.nodes||[]).length+' серверов';$('updated').textContent='Проверено: '+date(s.at);
  $('auto').disabled=working||s.busy||!s.nodes.length;$('manual').disabled=working||s.busy;$('check').disabled=working||s.busy;
  const list=$('nodes');list.replaceChildren();
  for(const node of s.nodes||[]){
   const row=element('div',undefined,'ns-ch-node'+(node.active?' selected':''));
   const name=element('div');name.append(element('strong',node.label),element('span',node.active?'HY2 · активен':'HY2 · резерв','ns-ch-muted'));row.append(name);
   const status=s.checking===node.id?'Проверка…':node.stale?'Нет свежей проверки':node.ok?'UDP доступен':'UDP не отвечает';
   row.append(element('span',status,'ns-ch-status'+(node.ok&&!node.stale?' good':'')));
   const metrics=element('div',undefined,'ns-ch-metrics');metrics.append(element('strong',node.ms==null?'—':node.ms+' мс'),element('span',node.loss==null?'Ещё нет данных':`jitter ${Number(node.jitter||0).toFixed(1)} мс · потери проб ${node.loss}%`,'ns-ch-muted'));row.append(metrics);
   const button=element('button',node.active?'Выбран':'Выбрать');button.type='button';button.disabled=working||s.busy||node.active||!s.enabled;
   button.addEventListener('click',()=>run(async()=>{if(!confirm('Переключить HY2 на «'+node.label+'» и включить ручной режим? Текущий звонок может переподключиться.'))return;
    await api('channel_select',{mode:'manual',id:node.id});message('Проверяю узел и переключаю. Результат появится в истории.');}));row.append(button);list.append(row);
  }
  if(!s.nodes.length)list.append(element('p','Добавьте подписку: здесь появятся её HY2-серверы.','ns-ch-muted'));
  $('history').replaceChildren();
  for(const entry of [...(s.events||[])].reverse().slice(0,8)){
   const name=(s.nodes||[]).find(n=>n.id===entry.id)?.label||'Сервер';$('history').append(element('li',`${date(entry.at)} · ${name} · ${reasons[entry.reason]||entry.reason}${entry.ok?'':' · не выполнено'}`));
  }
  if(!s.events?.length)$('history').append(element('li','Переключений пока не было.'));
  const errors={switch_failed_rolled_back:'Новый канал не заработал. Запрошен откат на предыдущий профиль.',selected_node_unavailable:'Выбранный сервер не ответил по UDP. Текущий профиль сохранён.',enable_voice_autostart_first:'Сначала включите голосовой маршрут и его автозапуск.'};
  if(errors[s.result])message(errors[s.result],true);
 }
 async function refresh(){try{render(await api('pool_status'));}catch(e){message(e.message,true);}finally{clearTimeout(timer);timer=setTimeout(refresh,5000);}}
 async function run(fn){if(working)return;working=true;if(state)render(state);try{await fn();}catch(e){message(e.message,true);}finally{working=false;await refresh();}}
 $('auto').onclick=()=>run(async()=>{await api('channel_select',{mode:'auto'});message('Автовыбор включён. Исправный канал сохраняется, резерв выбирается после повторных сбоев.');});
 $('manual').onclick=()=>run(async()=>{await api('channel_select',{mode:'manual'});message('Ручной режим: автоматически менять сервер не буду.');});
 $('check').onclick=()=>run(async()=>{await api('channel_select',{mode:'check'});message('Проверка всех узлов запрошена.');});
 $('import-form').onsubmit=event=>{event.preventDefault();run(async()=>{
  const value=$('source').value.trim();const url=NetscopeImport.subscription(value);let body=value;
  if(url){message('Загружаю подписку по HTTPS…');body=(await api('subscription',{url})).content;}
  const parsed=NetscopeImport.parse(body),hy2=parsed.nodes.filter(n=>n.kind==='hy2');
  const preview=$('import-preview');preview.replaceChildren();for(const node of parsed.nodes)preview.append(element('li',node.label+' · '+node.kind.toUpperCase()+(node.kind==='hy2'?'':' · отдельный профиль, не группа звонков')));
  if(!hy2.length)throw Error('В подписке нет HY2. Остальные узлы показаны ниже; их можно импортировать через «Новый профиль».');
  if(hy2.length>8)throw Error('В подписке больше 8 HY2. Выберите меньшую подписку для группы звонков.');
  let added=0;for(const node of hy2){message(`Добавляю HY2 ${++added} из ${hy2.length}…`);await api('channel_import',{payload:node.payload,label:node.label});}
  $('source').value='';body='';message(`Добавлено ${hy2.length} HY2. Текущий маршрут не изменён. Нажмите «Проверить» или «Авто».`);
 });};
 refresh();document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh();});
})();
