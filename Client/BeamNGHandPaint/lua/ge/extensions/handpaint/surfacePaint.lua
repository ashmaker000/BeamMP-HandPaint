-- Per-vehicle native decal projection. Camera matrices are in vehicle space so
-- the same stroke can be replayed after the vehicle moves or on another client.
local M = {}
local renderers = {}

local function matrixFrom(data)
  local result = MatrixF(true)
  for i = 0, 3 do result:setColumn4F(i, Point4F(data[i*4+1], data[i*4+2], data[i*4+3], data[i*4+4])) end
  return result
end

local function matrixData(value)
  local result = {}
  for i = 0, 3 do
    local column = value:getColumn4F(i):toTable()
    for j = 1, 4 do result[#result+1] = column[j] end
  end
  return result
end

local function color(hex, opacity)
  return Point4F(tonumber(hex:sub(2,3),16)/255, tonumber(hex:sub(4,5),16)/255, tonumber(hex:sub(6,7),16)/255, opacity or 1)
end

local function getRenderer(vehicle)
  if not DecalProjection then return nil, "This BeamNG build does not expose decal projection." end
  local id = vehicle:getID()
  local renderer = renderers[id]
  if not renderer then
    local projection = DecalProjection("", Point2I(1024,1024), 1, 0)
    -- The live preview targets are separate from the baked layer stack. Clear
    -- them before combining, as the stock editor does when disabling preview.
    projection:setEnabled(false)
    projection:flushDynamicTextures()
    -- Replay uses the sender's cursor, never this client's live mouse.
    if bit.band(projection:getSettings(), 4) ~= 0 then projection:toggleSetting(4) end
    projection:setShape(vehicle:getDecalProjectionShape())
    projection:clearMaterialIdx()
    local count = 0
    for index, name in pairs(projection:getShapeMaterialNames()) do
      if scenetree.findObject(name .. ".skin.dynamicTextures") then
        projection:addMaterialIdx(index)
        count = count + 1
      end
    end
    if count == 0 then return nil, "This vehicle has no Dynamic Decals body material." end
    renderer = {projection = projection, textures = projection:getTextureSet(), fresh = true}
    renderers[id] = renderer
  end
  local p = renderer.projection
  p:setShape(vehicle:getDecalProjectionShape())
  p:setWorldTransform(vehicle:getRefNodeMatrix())
  p:setTransform(vehicle:getRefNodeMatrix():copy():setPosition(vec3(0,0,0)):inverse())
  p:setMirrorOffset(vehicle:getSpawnLocalAABB():getCenter().x)
  return renderer
end

function M.capture(vehicle, x, y, size, hex, mirror, erase, settings)
  settings = settings or {}
  return {kind = "projected", x = x, y = y, size = size, color = hex, mirror = mirror, erase = erase == true,
    opacity = settings.opacity or 1, rotation = settings.rotation or 0, aspect = settings.aspect or 1, shape = settings.shape or "round",
    camera = matrixData(vehicle:getRefNodeMatrix():fullInverse():mul(getCameraTransform())),
    projection = matrixData(getCameraProjMatrix())}
end

local function configure(renderer, operation)
  local p = renderer.projection
  p.cursorPosition = Point2F(operation.x, operation.y)
  p.decalColor = operation.erase and renderer.base or color(operation.color, operation.opacity)
  p.colorPaletteMapId = 0
  p.decalScale = vec3(operation.size * (operation.aspect or 1), operation.size, operation.size)
  p.decalRotation = math.rad(operation.rotation or 0)
  p.mirrored = operation.mirror == true
  local texture = operation.shape == "soft" and "brush_soft.png" or operation.shape == "square" and "brush_square.png" or "brush.png"
  p:setDecalTexturePath("color", "/art/handpaint/" .. texture)
  p:setDecalTexturePath("alpha", "/art/dynamicDecals/textures/_one.png")
  p.alphaMaskChannel = 3
end

local function bake(renderer, vehicle, operation)
  if operation.kind == "projected" and operation.points then
    local stamp = {}
    for key, value in pairs(operation) do if key ~= "points" then stamp[key] = value end end
    for i, point in ipairs(operation.points) do
      stamp.x, stamp.y = point.x, point.y
      stamp.id = (operation.id or "hp-stroke") .. ":" .. i
      bake(renderer, vehicle, stamp)
    end
    stamp.x, stamp.y, stamp.id = operation.x, operation.y, operation.id
    bake(renderer, vehicle, stamp)
    return
  end
  local p = renderer.projection
  local layer
  if operation.kind == "projected" then
    configure(renderer, operation)
    local camera, projection = matrixFrom(operation.camera), matrixFrom(operation.projection)
    p:setEnabled(true)
    p:projectDynamicDecals(camera, projection)
    layer = p:getDecalData(camera, projection)
    p:setEnabled(false)
    p:flushDynamicTextures()
    layer.type = 0
  elseif operation.kind == "fill" or operation.kind == "clear" then
    layer = {type = 1, blendMode = 1, color = operation.kind == "clear" and renderer.base or color(operation.color), colorPaletteMapId = 0}
  else
    return -- Legacy UV strokes cannot be projected onto a surface.
  end
  renderer.sequence = (renderer.sequence or 0) + 1
  layer.uid = "hp-layer-" .. renderer.sequence
  layer.name, layer.enabled, layer.locked, layer.children = "HandPaint", true, false, {}
  p:bakeLayers({layer}, vehicle:getField("JBeam",0))
end

function M.apply(vehicle, message)
  -- Rebuild history into a fresh target. Native preview/depth state survives
  -- clearBakedTextures on the tested build and can retain the last stamp.
  if message.kind == "snapshot" then renderers[vehicle:getID()] = nil end
  local renderer, err = getRenderer(vehicle)
  if not renderer then return false, err end
  if message.kind == "snapshot" or renderer.fresh then
    renderer.base = message.base and color(message.base) or vehicle.color
    renderer.projection:clearBakedTextures()
    -- Keep the original vehicle colour as a locked foundation. User strokes
    -- are separate layers above it and reset only removes those strokes.
    renderer.projection:bakeLayers({{type = 1, blendMode = 1,
      color = renderer.base, colorPaletteMapId = 0, uid = "hp-base",
      name = "Original vehicle colour", enabled = true, locked = true, children = {}}}, vehicle:getField("JBeam",0))
    renderer.fresh = false
  end
  if message.kind == "snapshot" or message.kind == "append" then
    for _, op in ipairs(message.operations or {}) do bake(renderer, vehicle, op) end
  else
    bake(renderer, vehicle, message.operation)
  end
  -- Native bakeLayers repopulates the live preview even while disabled. Clear
  -- it AFTER baking or the last stamp overlays later fills and doubles opacity.
  renderer.projection:setEnabled(false)
  renderer.projection:flushDynamicTextures()
  renderer.projection:combineTextures(renderer.textures)
  renderer.hover = false
  vehicle:setTextureSet("@DynamicTexture", renderer.textures)
  return true
end

-- Hover uses only the transient projection target: never bake it into history.
function M.preview(vehicle, operation)
  local renderer, err = getRenderer(vehicle)
  if not renderer then return false, err end
  local p = renderer.projection
  p:flushDynamicTextures()
  configure(renderer, operation)
  p:setEnabled(true)
  p:projectDynamicDecals(matrixFrom(operation.camera), matrixFrom(operation.projection))
  p:combineTextures(renderer.textures)
  p:setEnabled(false)
  renderer.hover = true
  vehicle:setTextureSet("@DynamicTexture", renderer.textures)
  return true
end
function M.clearPreview()
  for id, renderer in pairs(renderers) do
    if renderer.hover then
      renderer.projection:setEnabled(false)
      renderer.projection:flushDynamicTextures()
      renderer.projection:combineTextures(renderer.textures)
      renderer.hover = false
    end
  end
end

function M.prepare(vehicle)
  local renderer = renderers[vehicle:getID()]
  if renderer then
    -- Rebind existing textures without recombining unchanged GPU targets.
    vehicle:setTextureSet("@DynamicTexture", renderer.textures)
    return true
  end
  return M.apply(vehicle, {kind = "append", operations = {}})
end

function M.forget(id) renderers[id] = nil end
function M.clear() renderers = {} end
return M
