local M = {}
function M.connect(previous, current, width, height)
  if not previous then return current end
  for _, key in ipairs({'size','color','mirror','erase','opacity','rotation','aspect','shape'}) do
    if previous[key] ~= current[key] then return current end
  end
  for _, key in ipairs({'camera','projection'}) do
    for i = 1, 16 do
      if math.abs(previous[key][i] - current[key][i]) > 0.0001 then return current end
    end
  end
  local dx, dy = current.x - previous.x, current.y - previous.y
  -- Do not bridge a large pointer jump or a camera/brush change.
  if math.abs(dx) + math.abs(dy) > 0.15 then return current end
  local steps = math.min(4, math.ceil(math.sqrt((dx*width)^2 + (dy*height)^2) / 4))
  if steps > 1 then
    current.points = {}
    for i = 1, steps - 1 do
      current.points[#current.points+1] = {x=previous.x+dx*i/steps, y=previous.y+dy*i/steps}
    end
  end
  return current
end
return M
