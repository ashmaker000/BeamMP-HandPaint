local M = {}
local jbeamIO = require('jbeam/io')
function M.skinName(vehicle) return vehicle:getField('JBeam',0) .. '_skin_dynamicTextures' end
function M.hasSkin(node, name)
  if not node then return false end
  if node.id == 'paint_design' and node.chosenPartName == name then return true end
  for _, child in pairs(node.children or {}) do if M.hasSkin(child,name) then return true end end
  return false
end
local function hasSlot(node)
  if not node then return false end
  if node.id == 'paint_design' then return true end
  for _, child in pairs(node.children or {}) do if hasSlot(child) then return true end end
  return false
end
function M.check(vehicle)
  local data = core_vehicle_manager.getVehicleData(vehicle:getID())
  if not data or not data.config or not data.ioCtx then return false, 'Waiting for vehicle parts to load.' end
  local model = vehicle:getField('JBeam',0)
  if not hasSlot(data.config.partsTree) then return false, model .. ': this configuration has no paint-design slot.' end
  local parts = jbeamIO.getAvailableParts(data.ioCtx)
  if not parts or not parts[M.skinName(vehicle)] then
    return false, model .. ': no enabled Dynamic Textures skin. This vehicle needs a paint-material adapter.'
  end
  return true
end
return M
