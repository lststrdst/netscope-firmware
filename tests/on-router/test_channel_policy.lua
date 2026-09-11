local P=dofile(arg[1] or '/usr/lib/lua/luci/model/netscope_channel_policy.lua')
local count=0
local function eq(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b));count=count+1 end
local nodes={{id='a'},{id='b'},{id='c'}}
local m={a={ok=false,failures=2},b={ok=true,ms=70,at=1000,successes=2},c={ok=true,ms=30,at=1000,successes=1}}
eq(P.choose(nodes,m,'a','auto',999,1000),'b')
eq(P.choose(nodes,m,'a','manual',0,1000),nil)
m.b.at=800;eq(P.choose(nodes,m,'a','auto',0,1000),nil)
m.b.at=1000;m.b.quarantine=1100;eq(P.choose(nodes,m,'a','auto',0,1000),nil)
m.b.quarantine=0;m.a={ok=true,ms=400,slow=3,failures=0}
eq(P.choose(nodes,m,'a','auto',950,1000),nil)
eq(P.choose(nodes,m,'a','auto',600,1000),'b')
m.a.ms=90;eq(P.choose(nodes,m,'a','auto',600,1000),nil)
local s=P.sample(nil,false,nil,1000);eq(s.failures,1);eq(s.loss,100)
s=P.sample(s,true,40,1030);eq(s.failures,0);eq(s.successes,1);eq(s.loss,50);eq(s.quarantine,1120)
s=P.sample(s,true,60,1060);eq(s.jitter,20)
for i=1,50 do s=P.sample(s,true,25,1060+i)end;eq(#s.history,20);eq(s.loss,0)
print('channel policy: '..count..' assertions passed')
