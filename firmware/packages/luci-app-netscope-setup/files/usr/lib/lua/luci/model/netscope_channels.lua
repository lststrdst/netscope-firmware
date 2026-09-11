-- Private HY2 server pool. All HTTP responses are explicit secret-free projections.
local M={}
local C=require'luci.model.netscope_setup_runtime'
local fs,n,j=require'nixio.fs',require'nixio',require'luci.jsonc'
M.ROOT=C.ROOT..'/config/voice/hy2-pool';M.RUN='/tmp/netscope-channels'
local function read(path,fallback)
    if not C.safe(path) then return fallback end
    local value=j.parse(C.read(path,65536) or '');return type(value)=='table' and value or fallback
end
function M.pool()
    local pool=read(M.ROOT..'/pool.json',{version=1,nodes={}});local out={version=1,nodes={}};local seen={}
    for _,v in ipairs(type(pool.nodes)=='table' and pool.nodes or {})do
        if #out.nodes<8 and C.valid_id(v.id) and not seen[v.id] then
            seen[v.id]=true;out.nodes[#out.nodes+1]={id=v.id,label=tostring(v.label or 'HY2'):gsub('%c',''):sub(1,100)}
        end
    end;return out
end
function M.settings()local v=read(M.ROOT..'/settings.json',{});return {mode=v.mode=='auto' and 'auto' or 'manual'}end
function M.enabled()return not fs.access('/tmp/netscope-voice-boot/user-paused') and (C.read(C.ROOT..'/config/voice/autostart.conf') or ''):match('enabled=1\n')~=nil end
function M.selected()
    local conf='\n'..(C.read(C.ROOT..'/config/voice/autostart.conf',512) or '')
    local id=conf:match('\nprofile=([^\n]+)')
    return C.valid_id(id) and id or nil
end
function M.live()
    local ok,out=C.exec({'/usr/libexec/netscope-vpn-profile','status','hy2'},4)
    return ok and j.parse(out) or {}
end
function M.status()
    local s=read(M.RUN..'/status.json',{});local live=M.live() or {};local out={nodes={},mode=M.settings().mode,active=live.active and live.id or nil,
        enabled=M.enabled(),at=s.at,checking=s.checking,events=s.events or {},last_switch=s.last_switch,
        result=s.result,busy=fs.access(M.RUN..'/request.json') or fs.access(M.RUN..'/processing.json') or s.result=='switching' or false}
    for _,v in ipairs(M.pool().nodes)do local m=(s.metrics or {})[v.id] or {}
        out.nodes[#out.nodes+1]={id=v.id,label=v.label,kind='hy2',active=out.active==v.id,ok=m.ok,ms=m.ms,at=m.at,
            loss=m.loss,jitter=m.jitter,failures=m.failures or 0,stale=not m.at or os.time()-m.at>120}
    end
    out.daemon_alive=s.at and os.time()-s.at<180 or false
    return out
end
function M.request(mode,id)
    assert(mode=='auto' or mode=='manual' or mode=='check','Неизвестный режим')
    assert(fs.access('/etc/init.d/netscope-channels'),'Диспетчер каналов не установлен')
    assert(C.storage().mounted,'Подключите USB-накопитель')
    if id and id~='' then local found=false;for _,v in ipairs(M.pool().nodes)do if v.id==id then found=true end end;assert(found,'Узел не найден') end
    C.mkdir(M.RUN);assert(not fs.access(M.RUN..'/request.json') and not fs.access(M.RUN..'/processing.json'),'Предыдущая команда ещё выполняется')
    C.atomic(M.RUN..'/request.json',{mode=mode,id=id,at=os.time()})
    local enabled=C.exec({'/etc/init.d/netscope-channels','enable'},3)
    local started=C.exec({'/etc/init.d/netscope-channels','running'},3)
    if not started then started=C.exec({'/etc/init.d/netscope-channels','start'},5) end
    if not enabled or not started then fs.unlink(M.RUN..'/request.json');error('Не удалось запустить диспетчер каналов') end
    return {queued=true}
end
function M.add(id,label)
    assert(C.storage().mounted,'Подключите USB-накопитель');assert(C.valid_id(id),'Неверный профиль')
    local path=C.ROOT..'/config/setup/'..id..'/hysteria.yaml'
    assert(C.safe(path) and fs.lstat(path,'type')=='reg','HY2-профиль недоступен')
    local p=M.pool();for _,v in ipairs(p.nodes)do if v.id==id then return {added=true,id=id} end end
    local value=C.read(path,16000)
    for _,v in ipairs(p.nodes)do if C.read(C.ROOT..'/config/setup/'..v.id..'/hysteria.yaml',16000)==value then return {added=true,id=v.id,duplicate=true}end end
    assert(#p.nodes<8,'В группе максимум 8 HY2-серверов')
    assert(type(label)=='string' and #label>0 and #label<=100 and not label:find('%c'),'Некорректное имя')
    p.nodes[#p.nodes+1]={id=id,label=label};C.mkdir(M.ROOT);C.atomic(M.ROOT..'/pool.json',p)
    return {added=true,id=id}
end
function M.import(payload,label)
    assert(type(payload)=='string' and #payload<=12000,'Некорректный профиль')
    local draft=require('luci.model.netscope_setup').prepare({kind='hy2',hy2_uri=payload})
    local ok,result=pcall(M.add,draft.id,label)
    if not ok or result.duplicate then pcall(require('luci.model.netscope_setup').delete,draft.id) end
    if not ok then error(result) end
    return result
end
function M.probe_config(id)
    assert(C.valid_id(id),'Invalid profile')
    local path=C.ROOT..'/config/setup/'..id..'/hysteria.yaml'
    assert(C.safe(path) and fs.lstat(path,'type')=='reg','Profile missing')
    local yaml=assert(C.read(path,16000));local prefix=assert(yaml:match('^(.-)\nlazy: true\n'),'Unsupported profile format')
    -- Only the wizard-generated connection prefix is reused. Never copy TUN/routes.
    assert(not prefix:find('\ntun:') and not prefix:find('\nsocks5:') and not prefix:find('\nhttp:'),'Unexpected listener')
    local out=M.RUN..'/probe.yaml';local f=assert(io.open(out,'wb'));assert(f:write(prefix..'\nlazy: true\nsocks5:\n  listen: 127.0.0.1:2289\n  disableUDP: false\n'));f:close();assert(fs.chmod(out,'600'));return out
end
M.read=read
return M
