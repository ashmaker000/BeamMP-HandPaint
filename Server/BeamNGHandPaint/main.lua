local D = require('lua/design')
local cars, uploads, rates, lastHello = {}, {}, {}, {}
local clock, sequence = 0, 0
local function send(player,event,data) MP.TriggerClientEvent(player,event,Util.JsonEncode(data)) end
local function errorTo(player,message) send(player,'HP_Error',{message=message}) end
local function decode(raw)
  if type(raw)~='string' or #raw>16384 then return nil end
  local ok,v=pcall(Util.JsonDecode,raw); return ok and type(v)=='table' and v or nil
end
local function owned(player,id)
  if type(id)~='string' then return false end
  local owner,vid=id:match('^(%d+)%-(%d+)$')
  if tonumber(owner)~=tonumber(player) then return false end
  local vehicles=MP.GetPlayerVehicles(tonumber(player)) or {}
  return vehicles[tonumber(vid)]~=nil or vehicles[vid]~=nil
end
local function permitted(player,raw)
  player=tonumber(player)
  local rate=rates[player] or {count=0,second=clock}
  if clock-rate.second>=1 then rate={count=0,second=clock} end
  rate.count=rate.count+1; rates[player]=rate
  if rate.count>90 then return nil end
  local v=decode(raw)
  if not v or not owned(player,v.vehicle) then return nil end
  return v
end
local function snapshot(player,id)
  local entry=cars[id]; if not entry then return end
  sequence=sequence+1
  local ops=entry.design.operations
  for first=1,math.max(1,#ops),D.chunkSize do
    local chunk={}; for i=first,math.min(#ops,first+D.chunkSize-1) do chunk[#chunk+1]=ops[i] end
    send(player,'HP_Snapshot',{vehicle=id,token=sequence,revision=entry.revision,
      meta=D.metadata(entry.design),first=first,total=#ops,operations=chunk})
  end
end
function HP_hello(player)
  player=tonumber(player)
  if lastHello[player] and clock-lastHello[player]<5 then return end
  lastHello[player]=clock
  send(player,'HP_Ready',{version=D.version,strokeHistory=true})
  for id in pairs(cars) do snapshot(player,id) end
end
function HP_begin(player,raw)
  local v=permitted(player,raw); if not v then return end
  if not D.meta(v.meta) or not D.number(v.total,0,D.maxOperations) or v.total%1~=0
    or type(v.token)~='string' or #v.token>64 then errorTo(player,'Invalid design header.'); return end
  local current=cars[v.vehicle]
  if (current and current.revision or 0)~=v.revision then
    errorTo(player,'Design changed; wait for synchronization and retry.'); snapshot(player,v.vehicle); return
  end
  uploads[v.vehicle]={player=tonumber(player),token=v.token,design=D.metadata(v.meta),total=v.total,operations={},time=clock,revision=v.revision}
end
function HP_chunk(player,raw)
  local v=permitted(player,raw); if not v then return end
  local u=uploads[v.vehicle]
  if not u or u.token~=v.token then return end
  if not D.operations(v.operations) or #v.operations>D.chunkSize or v.first~=#u.operations+1
    or #u.operations+#v.operations>u.total then
    uploads[v.vehicle]=nil; errorTo(player,'Invalid or out-of-order design chunk.'); return
  end
  for _,op in ipairs(v.operations) do u.operations[#u.operations+1]=D.cleanOperation(op) end
  u.time=clock
end
function HP_commit(player,raw)
  local v=permitted(player,raw); if not v then return end
  local u=uploads[v.vehicle]
  if not u or u.token~=v.token then errorTo(player,'Upload expired; retry applying the design.'); return end
  uploads[v.vehicle]=nil
  if #u.operations~=u.total or (cars[v.vehicle] and cars[v.vehicle].revision or 0)~=u.revision then
    errorTo(player,'Incomplete or stale upload; existing paint was kept.'); return
  end
  u.design.operations=u.operations
  cars[v.vehicle]={design=u.design,redo={},revision=u.revision+1}
  snapshot(-1,v.vehicle)
end
function HP_append(player,raw)
  local v=permitted(player,raw); if not v then return end
  local entry=cars[v.vehicle]
  if not entry or uploads[v.vehicle] then errorTo(player,'Finish applying a design before painting.'); return end
  if not D.operation(v.operation) then errorTo(player,'Invalid brush stroke.'); return end
  if #entry.design.operations>=D.maxOperations then errorTo(player,'Design limit reached (3000 operations).'); return end
  local op=D.cleanOperation(v.operation)
  entry.design.operations[#entry.design.operations+1]=op; entry.redo={}; entry.revision=entry.revision+1
  send(-1,'HP_Append',{vehicle=v.vehicle,revision=entry.revision,operation=op})
end
function HP_history(player,raw)
  local v=permitted(player,raw); if not v then return end
  local entry=cars[v.vehicle]; if not entry or uploads[v.vehicle] then return end
  if v.revision~=entry.revision then snapshot(player,v.vehicle); return end
  if D.history(entry,v.action) then snapshot(-1,v.vehicle) else snapshot(player,v.vehicle) end
end
function HP_deleted(player,vehicle)
  local id=tostring(player)..'-'..tostring(vehicle)
  cars[id]=nil; uploads[id]=nil; send(-1,'HP_Removed',{vehicle=id})
end
function HP_disconnect(player)
  player=tonumber(player)
  for id in pairs(cars) do if tonumber(id:match('^(%d+)%-'))==player then HP_deleted(player,id:match('%-(%d+)$')) end end
  for id,u in pairs(uploads) do if u.player==player then uploads[id]=nil end end
  rates[player]=nil; lastHello[player]=nil
end
function HP_edited(player,vehicle,raw)
  if type(raw)~='string' then return end
  local start=raw:find('{',1,true); if not start then return end
  local ok,v=pcall(Util.JsonDecode,raw:sub(start)); if not ok or type(v)~='table' then return end
  local id=tostring(player)..'-'..tostring(vehicle)
  if cars[id] and v.jbm and cars[id].design.model~=v.jbm then HP_deleted(player,vehicle) end
end
function HP_tick()
  clock=clock+1
  for id,u in pairs(uploads) do
    if clock-u.time>30 then uploads[id]=nil; errorTo(u.player,'Design upload timed out; existing paint was kept.') end
  end
end
function HP_init()
  for _,name in ipairs({'hello','begin','chunk','commit','append','history'}) do MP.RegisterEvent('HP_'..name,'HP_'..name) end
  MP.RegisterEvent('onVehicleDeleted','HP_deleted')
  MP.RegisterEvent('onVehicleEdited','HP_edited')
  MP.RegisterEvent('onPlayerDisconnect','HP_disconnect')
  MP.RegisterEvent('HP_tick','HP_tick'); MP.CreateEventTimer('HP_tick',1000)
  print('BeamNG HandPaint server loaded')
end
MP.RegisterEvent('onInit','HP_init')
