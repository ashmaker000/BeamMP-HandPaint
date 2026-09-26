local M={dependencies={'ui_imgui'}}
local im=ui_imgui
local ffi=require('ffi')
local D=require('ge/extensions/handpaint/design')
local paint=require('ge/extensions/handpaint/surfacePaint')
local support=require('ge/extensions/handpaint/paintSupport')
local materials=require('ge/extensions/handpaint/paintMaterials')
local picker=require('ge/extensions/handpaint/vehiclePicker')
local smoothing=require('ge/extensions/handpaint/strokeSmoothing')
local library=require('ge/extensions/handpaint/library')
local thumbnails=require('ge/extensions/handpaint/thumbnails')
local cars,dirty,incoming,pendingStrokes={},{},{},{}
local ready,wasMP,registered=false,nil,false
local outgoing,preparing,preview,selected
local stroke,strokeCounter,historyPending=nil,0,nil
local autosaveClock,connectionAge,pendingAge=0,0,0
local session=tostring(os.time())..'_'..tostring(math.floor(os.clock()*1000000))
local recoveryWork,recoveryRows,pendingDraft={},{},{}
local fitChanged,fitClock=false,0
local recoveryMessage='Autosave ready'
local serverCompatible=true
local visible,enabled=true,false
local status='Select Start painting to prepare your vehicle.'
local cooldown,retry,hello,uploadClock=0,0,0,0
local previous,sequence=nil,0
local name=im.ArrayChar(65,'My design')
local rgb=im.ArrayFloat(3); rgb[0],rgb[1],rgb[2]=0.2,0.55,0.9
local size,opacity,aspect,rotation=im.FloatPtr(0.25),im.FloatPtr(1),im.FloatPtr(1),im.FloatPtr(0)
local mirror=im.BoolPtr(false)
local scale,dx,dy,dz=im.FloatPtr(1),im.FloatPtr(0),im.FloatPtr(0),im.FloatPtr(0)
local shape,erase='round',false
local rows={}
local page,selectedName='paint',nil
local search=im.ArrayChar(65,'')
local accent=im.ImVec4(0.30,0.78,0.98,1)
local palette={'#ffffff','#171d29','#f44e62','#ffae42','#f5df65','#52d99a','#338ce6','#ae83ed'}
local function hint(text)
  if im.IsItemHovered() then im.SetTooltip(text) end
end
local function action(label,width,active)
  if active then
    im.PushStyleColor2(im.Col_Button,im.ImVec4(0.08,0.36,0.49,1))
    im.PushStyleColor2(im.Col_ButtonHovered,im.ImVec4(0.10,0.45,0.60,1))
    im.PushStyleColor2(im.Col_ButtonActive,im.ImVec4(0.07,0.29,0.41,1))
  end
  local pressed=im.Button(label,im.ImVec2(width,32))
  if active then im.PopStyleColor(3) end
  return pressed
end
local function slider(label,key,value,lo,hi,format,width)
  im.Text(label); im.SetNextItemWidth(width or -1)
  return im.SliderFloat('##'..key,value,lo,hi,format)
end
local function multiplayer() return MPCoreNetwork and MPCoreNetwork.isMPSession() or false end
local function own()
  local vehicle=be:getPlayerVehicle(0); if not vehicle then return end
  if multiplayer() then
    if not MPVehicleGE or not MPVehicleGE.isOwn(vehicle:getID()) then return end
    local id=MPVehicleGE.getServerVehicleID(vehicle:getID())
    if not id or not id:match('^%d+%-%d+$') then return end
    return vehicle,id
  end
  return vehicle,'local:'..vehicle:getID()
end
local function send(event,value) TriggerServerEvent('HP_'..event,jsonEncode(value or {})) end
local function hex(r,g,b)
  local function byte(v) return math.floor(math.max(0,math.min(1,v))*255+0.5) end
  return string.format('#%02x%02x%02x',byte(r),byte(g),byte(b))
end
local function bounds(vehicle)
  local c=vehicle:getSpawnLocalAABB():getCenter()
  local h=vehicle:getSpawnWorldOOBB():getHalfExtents()
  return {center={c.x,c.y,c.z},half={h.x,h.y,h.z}}
end
local function blank(vehicle)
  local c=vehicle.color
  return {version=D.version,model=vehicle:getField('JBeam',0),bounds=bounds(vehicle),base=hex(c.x,c.y,c.z),operations={}}
end
local function hasSkin(vehicle)
  local data=core_vehicle_manager.getVehicleData(vehicle:getID())
  return data and data.config and support.hasSkin(data.config.partsTree,support.skinName(vehicle))
end
local function render(vehicle,design)
  local ok,result,err=pcall(paint.apply,vehicle,{kind='snapshot',base=design.base,operations=design.operations})
  if not ok or not result then status='Paint: '..tostring(ok and err or result); return false end
  return true
end
local function resolve(id)
  if id:sub(1,6)=='local:' then
    local v=be:getObjectByID(tonumber(id:sub(7)))
    if v and hasSkin(v) then return v end
    return nil,'Waiting for Dynamic Textures skin.'
  end
  return materials.resolve(id)
end
local function remember(id)
  local entry=cars[id]
  if not entry then return end
  local key=session..'_'..id:gsub('[^%w_-]','_')..'_'..entry.design.model
  recoveryWork[key]={design=entry.design,pending=pendingDraft[id]}
end
local function checkpoint(preserveDraft)
  for key,work in pairs(recoveryWork) do
    local design=D.copy(work.design)
    for _,op in ipairs(work.pending or {}) do
      if #design.operations<D.maxOperations then design.operations[#design.operations+1]=D.copy(op) end
    end
    local destination=preserveDraft and work.pending and #work.pending>0 and key..'_unsynced' or key
    if library.checkpoint(destination,design) then
      recoveryWork[key]=nil; recoveryMessage='Autosaved '..os.date('%H:%M:%S')
    else recoveryMessage='Autosave failed; save a named design.' end
  end
end
local function preservePending()
  for id,ops in pairs(pendingDraft) do if #ops>0 then remember(id) end end
  checkpoint(true)
end
local function finishStroke()
  if stroke then checkpoint() end
  stroke=nil; previous=nil
end
local function syncStatus(id)
  if not multiplayer() then return 'Single-player' end
  if not serverCompatible then return 'Unavailable: update server plugin' end
  if not ready then return connectionAge>=12 and 'Unavailable: server not responding' or 'Connecting to HandPaint...' end
  if outgoing or incoming[id] or historyPending or (pendingStrokes[id] or 0)>0 then return 'Syncing...' end
  return cars[id] and 'Synced with server' or 'Server ready'
end
local function replace(id,design)
  if outgoing then status='Wait for the current upload.'; return end
  if not D.valid(design) then status='Invalid design.'; return end
  if multiplayer() then
    if not ready then status='Waiting for the HandPaint server plugin.'; return end
    sequence=sequence+1
    outgoing={vehicle=id,design=D.copy(design),token=tostring(sequence),first=1,age=0,revision=cars[id] and cars[id].revision or 0}
    send('begin',{vehicle=id,token=outgoing.token,meta=D.metadata(design),total=#design.operations,revision=outgoing.revision})
    status='Uploading design...'
  else
    cars[id]={design=D.copy(design),revision=(cars[id] and cars[id].revision or 0)+1,redo={}}
    dirty[id]=true; preview=nil; remember(id); status='Design applied.'
  end
end
local function setup(vehicle,id,design,asPreview)
  local ok,reason=support.check(vehicle)
  if not ok then status=reason; enabled=false; return end
  local success,result,err=pcall(paint.prepare,vehicle)
  if not success or not result then status=tostring(success and err or result); enabled=false; return end
  preparing={vehicle=id,gameId=vehicle:getID(),design=design,asPreview=asPreview,
    original=asPreview and D.copy(cars[id] and cars[id].design or blank(vehicle)) or nil,
    model=vehicle:getField('JBeam',0),age=0}
  if not hasSkin(vehicle) then core_vehicle_partmgmt.setSkin('dynamicTextures') end
  status='Preparing Dynamic Textures skin...'
end
local function append(id,op)
  if historyPending or thumbnails.busy() or not cars[id] or not D.operation(op) then return end
  if #cars[id].design.operations+(pendingStrokes[id] or 0)>=D.maxOperations then status='Design limit reached. Save your design.'; return end
  if multiplayer() then
    pendingStrokes[id]=(pendingStrokes[id] or 0)+1
    pendingDraft[id]=pendingDraft[id] or {}; pendingDraft[id][#pendingDraft[id]+1]=D.copy(op)
    remember(id)
    send('append',{vehicle=id,operation=op})
  else
    local entry=cars[id]; entry.design.operations[#entry.design.operations+1]=op; entry.redo={}; entry.revision=entry.revision+1
    local v=resolve(id)
    if v and not dirty[id] then
      local ok,result=pcall(paint.apply,v,{kind='append',operations={op}})
      if not ok or not result then dirty[id]=true end
    else dirty[id]=true end
    remember(id)
  end
end
local function history(id,action)
  if preview or preparing or outgoing or historyPending or thumbnails.busy() then return end
  finishStroke(); paint.clearPreview()
  if (pendingStrokes[id] or 0)>0 then status='Waiting for brush synchronization.'; return end
  local entry=cars[id]; if not entry then return end
  if multiplayer() then
    if not ready then return end
    historyPending=id
    send('history',{vehicle=id,action=action,revision=entry.revision}); return
  end
  if D.history(entry,action) then dirty[id]=true; remember(id); checkpoint() end
end
local function decode(raw)
  if type(raw)~='string' or #raw>16384 then return end
  local ok,v=pcall(jsonDecode,raw); if ok and type(v)=='table' then return v end
end
local function validId(id) return type(id)=='string' and id:match('^%d+%-%d+$') end
local function snapshot(raw)
  local v=decode(raw)
  if not v or not validId(v.vehicle) or not D.meta(v.meta) or not D.operations(v.operations)
    or #v.operations>D.chunkSize or not D.number(v.total,0,D.maxOperations) or v.total%1~=0
    or not D.number(v.revision,1,1e12) or not D.number(v.token,1,1e12) then return end
  pendingAge=0
  local current=cars[v.vehicle]
  if current and current.revision>v.revision then return end
  if v.first==1 then incoming[v.vehicle]={token=v.token,revision=v.revision,design=D.metadata(v.meta),total=v.total,operations={}} end
  local s=incoming[v.vehicle]
  if not s or s.token~=v.token or s.revision~=v.revision or s.total~=v.total or v.first~=#s.operations+1 then return end
  for _,op in ipairs(v.operations) do s.operations[#s.operations+1]=D.cleanOperation(op) end
  if #s.operations>s.total then incoming[v.vehicle]=nil; return end
  if #s.operations==s.total then
    s.design.operations=s.operations
    cars[v.vehicle]={design=s.design,revision=s.revision,redo={}}
    incoming[v.vehicle]=nil; dirty[v.vehicle]=true; pendingStrokes[v.vehicle]=nil; pendingDraft[v.vehicle]=nil
    if historyPending==v.vehicle then historyPending=nil end
    local _,ownerId=own(); if ownerId==v.vehicle then remember(v.vehicle); checkpoint() end
    if outgoing and outgoing.vehicle==v.vehicle and outgoing.waiting and s.revision>outgoing.revision then
      outgoing=nil; preview=nil; status='Design synchronized.'
    end
  end
end
local function onAppend(raw)
  local v=decode(raw); if not v or not validId(v.vehicle) or not D.operation(v.operation) then return end
  local entry=cars[v.vehicle]
  if not entry or v.revision~=entry.revision+1 then hello=0; ready=false; return end
  entry.design.operations[#entry.design.operations+1]=v.operation; entry.revision=v.revision
  if (pendingStrokes[v.vehicle] or 0)>0 then
    pendingAge=0
    pendingStrokes[v.vehicle]=pendingStrokes[v.vehicle]-1
    if pendingDraft[v.vehicle] then table.remove(pendingDraft[v.vehicle],1) end
    remember(v.vehicle)
  end
  local vehicle=resolve(v.vehicle)
  if vehicle and not dirty[v.vehicle] and not (preview and preview.vehicle==v.vehicle) then
    local ok,result=pcall(paint.apply,vehicle,{kind='append',operations={v.operation}})
    if not ok or not result then dirty[v.vehicle]=true end
  else dirty[v.vehicle]=true end
end
local function register()
  if registered or not AddEventHandler then return end
  registered=true
  AddEventHandler('HP_Ready',function(raw)
    local v=decode(raw); serverCompatible=v and v.version==D.version and v.strokeHistory==true or false
    ready=serverCompatible; connectionAge=0
  end)
  AddEventHandler('HP_Snapshot',snapshot)
  AddEventHandler('HP_Append',onAppend)
  AddEventHandler('HP_Error',function(raw)
    local v=decode(raw); status=v and tostring(v.message) or 'Server rejected paint operation.'
    preservePending(); outgoing=nil; pendingStrokes={}; pendingDraft={}; historyPending=nil; ready=false; hello=0
  end)
  AddEventHandler('HP_Removed',function(raw)
    local v=decode(raw); if not v or not validId(v.vehicle) then return end
    local vehicle=resolve(v.vehicle)
    if vehicle then paint.forget(vehicle:getID()); render(vehicle,blank(vehicle)) end
    cars[v.vehicle]=nil; dirty[v.vehicle]=nil; incoming[v.vehicle]=nil; pendingStrokes[v.vehicle]=nil
    if preview and preview.vehicle==v.vehicle then preview=nil end
    if outgoing and outgoing.vehicle==v.vehicle then outgoing=nil end
  end)
end
local function previewDesign(vehicle,id)
  if not selected then return end
  local result,err=D.transfer(selected,vehicle:getField('JBeam',0),bounds(vehicle),scale[0],{dx[0],dy[0],dz[0]})
  if not result then status=err; return end
  if preview and preview.vehicle==id then
    if render(vehicle,result) then preview.design=result; fitChanged=false; status='Preview updated.' end
  else setup(vehicle,id,result,true) end
end
local function savePanel(id)
  local entry=cars[id]; if not entry or preview then return end
  im.Spacing(); im.Separator(); im.Spacing()
  im.TextColored(accent,'SAVE YOUR DESIGN')
  im.SetNextItemWidth(im.GetContentRegionAvail().x-120); im.InputText('##designName',name)
  hint('Give each saved version a new name. Existing files are kept.')
  im.SameLine()
  if action('Save design',112,false) then
    if thumbnails.busy() or historyPending or dirty[id] or (pendingStrokes[id] or 0)>0 or incoming[id] then status='Wait for synchronization before saving.'
    else
      finishStroke(); paint.clearPreview()
      local savedName=ffi.string(name)
      local ok,message=library.save(savedName,entry.design)
      status=message; rows=library.list()
      if ok then
        local vehicle=resolve(id)
        if vehicle then thumbnails.start(vehicle,library.thumbnailPath(savedName)) end
      end
    end
  end
end
local function paintPanel(vehicle,id,width)
  if preview then
    im.TextWrapped('Finish or cancel the preview above before painting.')
    return
  end
  local brushLabel=enabled and 'Pause painting' or (cars[id] and 'Resume painting' or 'Start painting')
  if action(brushLabel,-1,true) then
    enabled=not enabled
    if enabled then setup(vehicle,id,cars[id] and cars[id].design or blank(vehicle),false) end
  end
  if not cars[id] then
    im.TextWrapped('Paint directly on this vehicle, or open Designs to load a saved design.')
    return
  end
  im.TextWrapped(enabled and 'Drag on your car to paint. Orbit to reach other sides.' or 'Painting paused. Click Resume painting above to continue your design.')
  im.Spacing(); im.Separator(); im.Spacing()
  im.TextColored(accent,'COLOUR')
  im.SetNextItemWidth(-1)
  if im.ColorEdit3('##paintColour',rgb,im.flags(im.ColorEditFlags_DisplayHex,im.ColorEditFlags_PickerHueWheel)) then erase=false end
  hint('Enter a HEX colour or click the colour square to open the picker.')
  local swatchWidth=(width-7*8)/8
  for i,value in ipairs(palette) do
    if im.ColorButton('Swatch '..value,im.ImVec4(tonumber(value:sub(2,3),16)/255,
      tonumber(value:sub(4,5),16)/255,tonumber(value:sub(6,7),16)/255,1),0,im.ImVec2(swatchWidth,24)) then
      rgb[0],rgb[1],rgb[2]=tonumber(value:sub(2,3),16)/255,tonumber(value:sub(4,5),16)/255,tonumber(value:sub(6,7),16)/255
      erase=false
    end
    hint(value)
    if i<#palette then im.SameLine() end
  end
  im.Spacing(); im.TextColored(accent,'BRUSH')
  local third=(width-16)/3
  for i,s in ipairs({'round','soft','square'}) do
    local label=s:sub(1,1):upper()..s:sub(2)
    if action(label..'##shape',third,shape==s) then shape=s end
    if i<3 then im.SameLine() end
  end
  im.BeginGroup(); slider('Size','brushSize',size,0.03,1.5,'%.2f m',(width-8)/2); im.EndGroup()
  im.SameLine()
  im.BeginGroup(); slider('Opacity','brushOpacity',opacity,0.05,1,'%.2f',(width-8)/2); im.EndGroup()
  if action(erase and 'Eraser ON' or 'Eraser',(width-8)/2,erase) then erase=not erase end
  hint('Paint with the saved base colour. Select a colour to return to the brush.')
  im.SameLine(); im.Checkbox('Mirror brush',mirror)
  if im.CollapsingHeader1('Advanced brush settings') then
    slider('Width ratio','brushWidth',aspect,0.25,4,'%.2fx')
    slider('Rotation','brushRotation',rotation,0,360,'%.0f deg')
  end
  im.Spacing(); im.Separator(); im.Spacing()
  if action('Undo',third,false) then history(id,'undo') end
  hint('Ctrl+Z: undo the whole brush drag.')
  im.SameLine(); if action('Redo',third,false) then history(id,'redo') end
  hint('Ctrl+Y: redo the whole brush drag.')
  im.SameLine(); if action('Fill',third,false) then append(id,{kind='fill',color=hex(rgb[0],rgb[1],rgb[2])}) end
  if im.CollapsingHeader1('Canvas options') then
    im.TextDisabled(tostring(#cars[id].design.operations)..' / '..D.maxOperations..' paint operations')
    if im.Button('Clear strokes') then history(id,'reset') end
    hint('Remove the active paint history and restore the saved base colour. Saved designs are kept.')
  end
  savePanel(id)
end
local function designsPanel(vehicle,id,width)
  im.TextColored(accent,'SAVED DESIGNS')
  im.Text('Search by name'); im.SetNextItemWidth(-1); im.InputText('##searchDesigns',search)
  hint('Filter designs by name. Clear this field to show everything.')
  local filter=ffi.string(search):lower()
  local matches={}
  for _,row in ipairs(rows) do
    if row.name:lower():find(filter,1,true) then matches[#matches+1]=row end
  end
  -- A bounded browser prevents a large library from stretching the panel.
  local height=math.max(76,math.min(220,#matches*76+12))
  if im.BeginChild1('##designLibrary',im.ImVec2(0,height),true) then
    if #matches==0 then im.TextWrapped(#rows==0 and 'No saved designs yet. Paint a car, then save it with a name.' or 'No designs match your search.') end
    for _,row in ipairs(matches) do
      thumbnails.draw(row.thumbnail); im.SameLine(); im.BeginGroup()
      if action(row.name..'##load',-1,selectedName==row.name) then
        local design,err=library.load(row.name)
        if design then
          selected,selectedName=design,row.name
          scale[0],dx[0],dy[0],dz[0]=1,0,0,0
          if preview then fitChanged=true; fitClock=0 end
          status='Selected '..row.name..'.'
        else status=err end
      end
      hint(row.name)
      im.EndGroup(); im.Spacing()
    end
  end
  im.EndChild()
  if im.Button('Refresh library') then rows=library.list(); recoveryRows=library.recoveries() end
  im.SameLine(); im.TextDisabled(tostring(#matches)..' of '..#rows..' designs')
  if #recoveryRows>0 and im.CollapsingHeader1('Recover unfinished designs ('..#recoveryRows..')') then
    for _,row in ipairs(recoveryRows) do
      im.Text(row.design.model..' - '..os.date('%d %b %H:%M',row.time))
      if im.Button('Recover##'..row.key) then
        selected=D.copy(row.design); selectedName='Recovered '..row.design.model
        scale[0],dx[0],dy[0],dz[0]=1,0,0,0
        enabled=false; previewDesign(vehicle,id)
      end
      im.SameLine()
      if im.Button('Discard##'..row.key) then library.discardRecovery(row.key); recoveryRows=library.recoveries() end
    end
  end
  if selected then
    im.Spacing(); im.Separator(); im.Spacing()
    im.TextWrapped(selectedName or 'Selected design')
    im.TextDisabled('Source vehicle: '..selected.model)
    if im.CollapsingHeader1('Adjust fit and placement') then
      local changed=false
      changed=slider('Scale','designScale',scale,0.1,3,'%.2fx') or changed
      changed=slider('Left / right','designX',dx,-5,5,'%.2f m') or changed
      changed=slider('Front / back','designY',dy,-10,10,'%.2f m') or changed
      changed=slider('Up / down','designZ',dz,-5,5,'%.2f m') or changed
      if im.Button('Reset fit') then scale[0],dx[0],dy[0],dz[0]=1,0,0,0; changed=true end
      if changed then fitChanged=true; fitClock=0.15 end
      im.TextWrapped('Preview updates as you adjust. Different body shapes may need touch-ups.')
    end
    if action('Preview on this vehicle',-1,true) then
      if (pendingStrokes[id] or 0)>0 then status='Wait for synchronization before transferring.'
      else enabled=false; previewDesign(vehicle,id) end
    end
    hint('Preview locally before applying. The saved original is kept unchanged.')
  end
  savePanel(id)
end
local function window()
  if not visible or not own() then return end
  im.PushStyleVar2(im.StyleVar_WindowPadding,im.ImVec2(14,12))
  im.PushStyleVar2(im.StyleVar_FramePadding,im.ImVec2(8,5))
  im.PushStyleVar2(im.StyleVar_ItemSpacing,im.ImVec2(8,7))
  im.PushStyleColor2(im.Col_WindowBg,im.ImVec4(0.075,0.09,0.12,0.98))
  im.PushStyleColor2(im.Col_Text,im.ImVec4(0.93,0.95,0.98,1))
  im.PushStyleColor2(im.Col_TextDisabled,im.ImVec4(0.61,0.67,0.75,1))
  -- Override the old stored 680px height; expand only for visible controls.
  im.SetNextWindowSize(im.ImVec2(420,0),im.Cond_Always)
  im.SetNextWindowSizeConstraints(im.ImVec2(420,0),im.ImVec2(420,math.max(300,im.GetIO().DisplaySize.y-40)))
  local opened=im.Begin('HandPaint',nil,im.WindowFlags_AlwaysAutoResize)
  if opened then
    local width=im.GetContentRegionAvail().x
    local vehicle,id=own()
    im.TextColored(accent,'HANDPAINT')
    im.SameLine(); im.TextDisabled('Alt+H')
    im.TextColored(accent,syncStatus(id))
    if vehicle then im.TextDisabled('Vehicle: '..vehicle:getField('JBeam',0)) end
    im.Spacing()
    if action('Paint##page',(width-8)/2,page=='paint') then page='paint' end
    im.SameLine()
    if action('Designs##page',(width-8)/2,page=='designs') then page='designs'; enabled=false; checkpoint(); rows=library.list(); recoveryRows=library.recoveries() end
    im.Spacing(); im.Separator(); im.Spacing()
    if not vehicle then im.TextWrapped('Spawn or switch to a vehicle you own.')
    elseif multiplayer() and not ready then im.TextWrapped(serverCompatible and 'Waiting for the HandPaint server plugin.' or 'Install the updated HandPaint server plugin to use grouped undo and synchronization.')
    elseif preparing or outgoing or thumbnails.busy() then
      im.TextWrapped('Preparing your design...')
      if outgoing then im.Text(string.format('%d / %d operations uploaded',math.min(outgoing.first-1,#outgoing.design.operations),#outgoing.design.operations)) end
    else
      if preview then
        im.TextColored(accent,'LOCAL PREVIEW')
        im.TextWrapped('Inspect the car, then apply or cancel.')
        if action(multiplayer() and 'Apply and synchronize' or 'Apply design',(width-8)/2,true) then
          if fitChanged then previewDesign(vehicle,id) end
          if not fitChanged then replace(id,preview.design) end
        end
        im.SameLine()
        if action('Cancel preview',(width-8)/2,false) and preview then
          if render(vehicle,preview.original or (cars[id] and cars[id].design) or blank(vehicle)) then
            preview=nil; dirty[id]=nil; fitChanged=false; status='Preview cancelled.'
          end
        end
        im.Spacing(); im.Separator(); im.Spacing()
      end
      if page=='paint' then paintPanel(vehicle,id,width) else designsPanel(vehicle,id,width) end
    end
    im.Spacing(); im.Separator()
    im.TextWrapped(status)
    im.TextDisabled(recoveryMessage)
  end
  im.End(); im.PopStyleColor(3); im.PopStyleVar(3)
end
local function brush(dt)
  cooldown=math.max(0,cooldown-dt)
  local down=im.IsMouseDown(0)
  if not down then finishStroke() end
  if not visible or not enabled or preview or preparing or outgoing or historyPending or thumbnails.busy()
    or (multiplayer() and not ready) or im.GetIO().WantCaptureMouse then
    paint.clearPreview(); finishStroke(); return
  end
  local vehicle,id=own()
  if not vehicle or not cars[id] or dirty[id] or not hasSkin(vehicle) then paint.clearPreview(); previous=nil; return end
  local hit=picker.pick(100)
  if not hit or hit.object:getID()~=vehicle:getID() then paint.clearPreview(); previous=nil; return end
  local mouse,display=im.GetMousePos(),im.GetIO().DisplaySize
  if display.x<=0 or display.y<=0 then return end
  local op=paint.capture(vehicle,mouse.x/display.x,mouse.y/display.y,size[0],hex(rgb[0],rgb[1],rgb[2]),mirror[0],erase,
    {opacity=opacity[0],rotation=rotation[0],aspect=aspect[0],shape=shape})
  if not down then
    local ok,result,err=pcall(paint.preview,vehicle,op)
    if not ok or not result then status='Brush preview: '..tostring(ok and err or result) end
    return
  end
  paint.clearPreview()
  if cooldown>0 then return end
  if previous and previous.vehicle==id and math.abs(mouse.x-previous.x)+math.abs(mouse.y-previous.y)<2 then return end
  if not stroke or stroke.vehicle~=id then
    finishStroke(); strokeCounter=strokeCounter+1
    stroke={vehicle=id,id=session..'_'..strokeCounter}
  end
  op.stroke=stroke.id
  smoothing.connect(previous and previous.vehicle==id and previous.operation or nil,op,display.x,display.y)
  append(id,op); previous={vehicle=id,x=mouse.x,y=mouse.y,operation=op}; cooldown=1/30
end
function M.onUpdate(dt)
  dt=dt or 0; register()
  local thumbOK,thumbError=thumbnails.update()
  if thumbOK==false then status=thumbError end
  autosaveClock=autosaveClock+dt
  if autosaveClock>=5 then checkpoint(); autosaveClock=0 end
  local mp=multiplayer()
  if wasMP~=mp then
    preservePending(); finishStroke(); historyPending=nil; pendingDraft={}
    cars,dirty,incoming,pendingStrokes={},{},{},{}; paint.clear()
    connectionAge=0; pendingAge=0; serverCompatible=true
    outgoing,preview,preparing=nil,nil,nil; ready=false; wasMP=mp; hello=0; enabled=false
  end
  connectionAge=connectionAge+dt
  local _,ownerId=own()
  if preview and preview.vehicle~=ownerId then
    local oldVehicle=resolve(preview.vehicle)
    if oldVehicle then render(oldVehicle,preview.original) end
    preview=nil; fitChanged=false
  end
  local pending=historyPending~=nil or (ownerId and incoming[ownerId]~=nil)
  for _,count in pairs(pendingStrokes) do if count>0 then pending=true end end
  pendingAge=pending and pendingAge+dt or 0
  if mp and pendingAge>12 then
    preservePending(); ready=false; hello=0; historyPending=nil; pendingStrokes={}; pendingDraft={}; incoming={}; pendingAge=0
    status='Synchronization timed out. Local recovery checkpoint kept.'
  end
  fitClock=math.max(0,fitClock-dt)
  if fitChanged and preview and fitClock<=0 then
    local vehicle,id=own()
    if vehicle and id==preview.vehicle then previewDesign(vehicle,id) end
  end
  hello=hello-dt
  if mp and not ready and hello<=0 and registered then send('hello'); hello=6 end
  if outgoing then
    outgoing.age=outgoing.age+dt; uploadClock=uploadClock-dt
    if outgoing.age>90 then outgoing=nil; status='Upload timed out; retry when the server is ready.'
    elseif not outgoing.waiting and uploadClock<=0 then
      uploadClock=0.05
      if outgoing.first>#outgoing.design.operations then
        outgoing.waiting=true; send('commit',{vehicle=outgoing.vehicle,token=outgoing.token})
      else
        local ops={}
        for i=outgoing.first,math.min(#outgoing.design.operations,outgoing.first+D.chunkSize-1) do ops[#ops+1]=outgoing.design.operations[i] end
        local packet={vehicle=outgoing.vehicle,token=outgoing.token,first=outgoing.first,operations=ops}
        outgoing.first=outgoing.first+#ops
        send('chunk',packet)
      end
    end
  end
  if preparing then
    preparing.age=preparing.age+dt
    local vehicle,id=own()
    if not vehicle or id~=preparing.vehicle or vehicle:getField('JBeam',0)~=preparing.model then
      preparing=nil; status='Vehicle changed during setup. Use the painting button on the Paint tab to continue.'
    elseif hasSkin(vehicle) then
      local work=preparing; preparing=nil
      if work.asPreview then
        if render(vehicle,work.design) then preview=work; dirty[id]=nil; fitChanged=false; status='Preview ready.' end
      elseif cars[id] then dirty[id]=true; status='Brush ready. Drag on your vehicle to paint.'
      else replace(id,work.design) end
    elseif preparing.age>15 then preparing=nil; status='Paint skin did not become ready. Retry setup.' end
  end
  retry=retry-dt
  if retry<=0 then
    retry=0.5
    for id in pairs(dirty) do
      if not (preview and preview.vehicle==id) then
        local vehicle,err=resolve(id)
        if vehicle and cars[id] and vehicle:getField('JBeam',0)==cars[id].design.model then
          if render(vehicle,cars[id].design) then dirty[id]=nil end
        elseif err then status=err end
      end
    end
  end
  window(); brush(dt)
end
function M.onVehicleSpawned(id)
  paint.forget(id)
  local vehicle=be:getObjectByID(id)
  if vehicle and hasSkin(vehicle) then pcall(paint.prepare,vehicle) end
  for key,entry in pairs(cars) do
    local gameId=key:sub(1,6)=='local:' and tonumber(key:sub(7)) or (MPVehicleGE and MPVehicleGE.getGameVehicleID(key))
    if gameId==id then
      if vehicle and vehicle:getField('JBeam',0)~=entry.design.model then cars[key]=nil; dirty[key]=nil
      else dirty[key]=true end
    end
  end
  finishStroke()
  if preview and preview.gameId==id then preview=nil; fitChanged=false end
end
function M.onClientEndMission()
  preservePending(); finishStroke(); thumbnails.stop(); historyPending=nil; pendingDraft={}
  cars,dirty,incoming,pendingStrokes={},{},{},{}; outgoing,preparing,preview=nil,nil,nil
  paint.clear(); ready=false; enabled=false; hello=0
end
function M.onSerialize()
  checkpoint()
  return {cars=not multiplayer() and D.copy(cars) or {},visible=visible,enabled=enabled}
end
function M.onDeserialized(data)
  if type(data)~='table' or multiplayer() then return end
  wasMP=false
  for id,entry in pairs(data.cars or {}) do
    if type(id)=='string' and id:match('^local:%d+$') and type(entry)=='table' and D.valid(entry.design) then
      cars[id]={design=D.copy(entry.design),revision=1,redo={}}; dirty[id]=true; remember(id)
    end
  end
  visible=data.visible~=false; enabled=data.enabled==true
end
function M.onExtensionLoaded() rows=library.list(); recoveryRows=library.recoveries(); register() end
function M.onExtensionUnloaded() preservePending(); thumbnails.stop(); paint.clearPreview(); paint.clear() end
function M.toggle()
  if not own() then return end
  visible=not visible; finishStroke(); paint.clearPreview()
end
function M.undo()
  if visible and not (editor and editor.active) and not im.GetIO().WantTextInput then local _,id=own(); if id then history(id,'undo') end end
end
function M.redo()
  if visible and not (editor and editor.active) and not im.GetIO().WantTextInput then local _,id=own(); if id then history(id,'redo') end end
end
return M
