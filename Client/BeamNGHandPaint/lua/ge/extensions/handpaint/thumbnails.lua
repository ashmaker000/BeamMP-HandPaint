-- A separate render view captures the painted car without moving the player's
-- camera, hiding their UI, or changing graphics settings.
local M={}
local capture
local textures={}
function M.stop()
  if capture then RenderViewManagerInstance:destroyView(capture.view); capture=nil end
end
function M.busy() return capture~=nil end
function M.start(vehicle,path)
  if capture or not RenderViewManagerInstance then return false end
  local view=RenderViewManagerInstance:getOrCreateView('handpaintThumbnail')
  view.luaOwned=true
  view.renderCubemap=false
  view.resolution=Point2I(320,200)
  view.viewPort=RectI(0,0,320,200)
  view.namedTexTargetColor='handpaintThumbnail'
  view.frustum=Frustum.construct(false,math.rad(40),1.6,0.1,2000)
  view.fov=40
  view.renderEditorIcons=false
  local exposure=scenetree.findObject('PostEffectLocalExposureObject')
  view.useManualEV=exposure~=nil
  view.manualEV=exposure and exposure.manualEV or 0
  capture={view=view,vehicle=vehicle:getID(),path=path,frames=0}
  return true
end
function M.update()
  if not capture then return end
  local v=be:getObjectByID(capture.vehicle)
  if not v then M.stop(); return false,'Vehicle disappeared before thumbnail capture.' end
  local box=v:getSpawnWorldOOBB()
  local target=box:getCenter()
  local direction=(box:getAxis(0)*1.4-box:getAxis(1)*1.8+box:getAxis(2)*0.9):normalized()
  local pos=target+direction*(box:getHalfExtents():length()/math.sin(math.rad(20))*1.1)
  local rot=quatFromDir(target-pos,box:getAxis(2))
  local mat=QuatF(rot.x,rot.y,rot.z,rot.w):getMatrix()
  mat:setPosition(pos); capture.view.cameraMatrix=mat
  capture.frames=capture.frames+1
  if capture.frames<6 then return end
  local path=capture.path
  local ok,result=pcall(function() return capture.view:saveToDisk(path) end)
  M.stop(); textures[path]=nil
  if not ok or not result then return false,'Design saved, but thumbnail capture failed.' end
  return true
end
function M.draw(path)
  local im=ui_imgui
  if path and FS:fileExists(path) then
    if not textures[path] then textures[path]=im.ImTextureHandler(path) end
    im.Image(textures[path]:getID(),im.ImVec2(96,60))
  else
    im.Button('No preview##'..tostring(path),im.ImVec2(96,60))
  end
end
return M
