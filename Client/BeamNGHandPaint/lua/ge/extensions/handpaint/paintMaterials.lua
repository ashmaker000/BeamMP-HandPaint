local M = {}
local support = require("ge/extensions/handpaint/paintSupport")

function M.resolve(serverId)
  if not MPVehicleGE then return nil, "Waiting for BeamMP." end
  local id = MPVehicleGE.getGameVehicleID(serverId)
  local vehicle = id and id >= 0 and be:getObjectByID(id)
  if not vehicle then return nil, "Waiting for the painted vehicle to spawn." end
  local model = vehicle:getField("JBeam", 0)
  local expected = model .. "_skin_dynamicTextures"
  local data = core_vehicle_manager.getVehicleData(id)
  if data and data.config and support.hasSkin(data.config.partsTree, expected) then return vehicle end

  -- BeamMP may defer the skin edit in its vehicle queue. A stroke can arrive
  -- first; don't report a successful draw against the ordinary body material.
  local vehicles = MPVehicleGE.getVehicles and MPVehicleGE.getVehicles()
  local entry = vehicles and vehicles[serverId]
  if entry and entry.editQueue and MPVehicleGE.applyPlayerQueues and not MPVehicleGE.isOwn(id) then
    local ok, edit = pcall(jsonDecode, entry.editQueue)
    if ok and edit and edit.jbm == model and edit.vcf and support.hasSkin(edit.vcf.partsTree, expected) then
      MPVehicleGE.applyPlayerQueues(tonumber(serverId:match("^(%d+)%-")))
      return nil, "Applying the painted vehicle's queued skin update."
    end
  end
  return nil, "Waiting for the painted vehicle's Dynamic Textures skin."
end

return M
