local M = {}

-- Flexbody vehicles can be absent from cameraMouseRayCast's scene collision
-- results. Test their oriented bounds, then let the decal renderer hit the body.
function M.pick(maxDistance)
  local ray = getCameraMouseRay()
  if not ray then return nil end
  local origin, direction = vec3(ray.pos), vec3(ray.dir):normalized()
  local closest, distance = nil, maxDistance or 100
  for _, vehicle in ipairs(getAllVehicles()) do
    local box = vehicle:getSpawnWorldOOBB()
    local extents = box:getHalfExtents()
    local entry, exit = intersectsRay_OBB(origin, direction, box:getCenter(),
      box:getAxis(0) * extents.x, box:getAxis(1) * extents.y, box:getAxis(2) * extents.z)
    if entry < math.huge and exit >= 0 then
      local hitDistance = math.max(0, entry)
      if hitDistance < distance then closest, distance = vehicle, hitDistance end
    end
  end
  if not closest then return nil end
  if castRayStatic(origin, direction, distance) + 0.01 < distance then return nil end
  return {object = closest, distance = distance}
end
return M
