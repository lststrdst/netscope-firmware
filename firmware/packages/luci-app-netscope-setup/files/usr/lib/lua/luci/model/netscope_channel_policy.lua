-- Pure policy: no I/O, credentials, routes or wall-clock assumptions.
local M={}
function M.sample(previous,ok,latency,now)
    local p=previous or {};local history=p.history or {};history[#history+1]={ok=ok,ms=latency,at=now}
    while #history>20 do table.remove(history,1) end
    local loss,jitter,last,count=0,0,nil,0
    for _,v in ipairs(history)do if not v.ok then loss=loss+1 elseif v.ms then
        if last then jitter=jitter+math.abs(v.ms-last);count=count+1 end;last=v.ms
    end end
    return {ok=ok,ms=latency,at=now,failures=ok and 0 or (p.failures or 0)+1,
        successes=ok and (p.successes or 0)+1 or 0,slow=ok and latency and latency>250 and (p.slow or 0)+1 or 0,
        quarantine=not ok and now+120 or p.quarantine or 0,history=history,
        loss=math.floor(loss/#history*100+.5),jitter=count>0 and math.floor(jitter/count*10+.5)/10 or 0}
end
function M.choose(nodes,metrics,active,mode,last_switch,now)
    if mode~='auto' then return nil,'manual' end
    local current=metrics[active] or {};local best,bm
    for _,node in ipairs(nodes)do local m=metrics[node.id]
        if node.id~=active and m and m.ok and m.ms and now-m.at<=120 and now>=(m.quarantine or 0) and (m.successes or 0)>=2 then
            if not bm or m.ms<bm.ms then best,bm=node.id,m end
        end
    end
    if not best then return nil,'no_verified_reserve' end
    -- Cooldown prevents flapping, but must not pin traffic to a failed node.
    if (current.failures or 0)>=2 then return best,'udp_unavailable' end
    if now-(last_switch or 0)>=300 and (current.slow or 0)>=3 and bm.ms<current.ms*.7 then return best,'udp_slow' end
    return nil,'stable'
end
return M
