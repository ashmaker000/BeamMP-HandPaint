local D=require('ge/extensions/handpaint/design')
local M={root='/settings/handpaint/designs/',recoveryRoot='/settings/handpaint/recovery/'}
local generations={}
local function filename(name)
  if type(name)~='string' or #name<1 or #name>64 or not name:match('^[%w][%w _-]*$') then
    return nil,'Use 1-64 letters, numbers, spaces, hyphens or underscores, starting with a letter or number.'
  end
  return M.root..name..'.json'
end
function M.list()
  local rows={}
  for _,path in ipairs(FS:findFiles(M.root,'*.json',0,true,false) or {}) do
    rows[#rows+1]={path=path,name=path:match('([^/\\]+)%.json$'),thumbnail=path:gsub('%.json$','.png')}
  end
  table.sort(rows,function(a,b) return a.name:lower()<b.name:lower() end)
  return rows
end
function M.save(name,design)
  local path,err=filename(name); if not path then return false,err end
  if not D.valid(design) then return false,'Cannot save an invalid design.' end
  if FS:fileExists(path) then return false,'That name exists. Choose a new name to keep both versions.' end
  FS:directoryCreate(M.root,true)
  local ok,result=pcall(jsonWriteFile,path,design,true)
  if not ok or result~=true then return false,'The design file could not be written.' end
  return true,'Saved '..name
end
function M.thumbnailPath(name)
  local path=filename(name)
  return path and path:gsub('%.json$','.png')
end
local function recoveryKey(key) return type(key)=='string' and #key<=180 and key:match('^[%w_-]+$') end
local function readCheckpoint(path)
  local ok,v=pcall(jsonReadFile,path)
  if ok and type(v)=='table' and D.valid(v.design) and D.number(v.generation,1,1e12)
    and D.number(v.time,0,1e12) then return v end
end
function M.recoveries()
  local latest={}
  for _,path in ipairs(FS:findFiles(M.recoveryRoot,'*.json',0,true,false) or {}) do
    local key=path:match('([^/\\]+)_[ab]%.json$')
    if key and recoveryKey(key) then
      local v=readCheckpoint(path)
      if v and (not latest[key] or v.generation>latest[key].generation) then
        v.key=key; latest[key]=v
      end
    end
  end
  local rows={}
  for _,v in pairs(latest) do rows[#rows+1]=v end
  table.sort(rows,function(a,b) return a.time>b.time end)
  return rows
end
function M.checkpoint(key,design)
  if not recoveryKey(key) or not D.valid(design) then return false end
  FS:directoryCreate(M.recoveryRoot,true)
  local generation=generations[key]
  if not generation then
    generation=0
    for _,slot in ipairs({'a','b'}) do
      local v=readCheckpoint(M.recoveryRoot..key..'_'..slot..'.json')
      if v then generation=math.max(generation,v.generation) end
    end
  end
  generation=generation+1
  local path=M.recoveryRoot..key..(generation%2==1 and '_a.json' or '_b.json')
  local ok,result=pcall(jsonWriteFile,path,{generation=generation,time=os.time(),design=design},true)
  if not ok or result~=true then return false end
  local check=readCheckpoint(path)
  if not check or check.generation~=generation then return false end
  generations[key]=generation
  return true
end
function M.discardRecovery(key)
  if not recoveryKey(key) then return end
  for _,slot in ipairs({'a','b'}) do FS:removeFile(M.recoveryRoot..key..'_'..slot..'.json') end
  generations[key]=nil
end
function M.load(name)
  local path,err=filename(name); if not path then return nil,err end
  local ok,value=pcall(jsonReadFile,path)
  if not ok or not D.valid(value) then return nil,'Invalid or unsupported design file.' end
  return value
end
return M
