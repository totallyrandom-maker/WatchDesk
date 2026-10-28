local _,NS=...
-- Window ownership only. Native movement, controls, key bindings and ordinary
-- CloseAllWindows callers retain their own behavior.
local W={version=1};NS.Windows=W
local roots=setmetatable({}, {__mode="k"})
local serial,installed,closing,nativeToggle=0,false,false,nil
local ranks={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
local function Read(frame,key)
 if not frame or type(frame[key])~="function"then return end
 local ok,value=pcall(frame[key],frame);if ok then return value end
end
local function Forbidden(frame)
 return not frame or type(frame.IsForbidden)=="function"and Read(frame,"IsForbidden")~=false
end
local function Visible(frame)
 if Forbidden(frame)or Read(frame,"IsShown")~=true then return false end
 if type(frame.IsVisible)=="function"then return Read(frame,"IsVisible")==true end
 local parent=frame
 for _=1,64 do
  if not parent then return true end
  if Forbidden(parent)or Read(parent,"IsShown")~=true then return false end
  if type(parent.GetParent)~="function"then return true end
  local nextParent=Read(parent,"GetParent");if nextParent==parent then return false end;parent=nextParent
 end
 return false
end
local function Safe(frame)
 return not Forbidden(frame)and type(frame.Hide)=="function"
  and(type(frame.IsProtected)~="function"or Read(frame,"IsProtected")==false)
end
local function Hook(frame,key,fn)
 if type(frame.HookScript)~="function"then return false end
 if type(frame.HasScript)=="function"then local ok,has=pcall(frame.HasScript,frame,key);if not ok or not has then return false end end
 frame:HookScript(key,fn);return true
end
local coordinator,coordinatorKey
local function Compatible(peer)
 return type(peer)=="table"and peer~=W and type(rawget(peer,"Register"))=="function"and type(rawget(peer,"CloseOne"))=="function"
end
local function Coordinator()
 if coordinatorKey and rawget(_G,coordinatorKey)==coordinator and Compatible(coordinator)then return coordinator end
 coordinator,coordinatorKey=nil,nil
end
local function DiscoverCoordinator()
 if Coordinator()then return end
 -- Optional shared ordering is a capability, not an addon dependency. Cache
 -- discovery at lifecycle boundaries; mouse/key handlers never scan globals.
 local chosenKey,chosen
 for key,peer in pairs(_G)do
  if type(key)=="string"and key:sub(-12)=="WindowEscape"and Compatible(peer)and(not chosenKey or key<chosenKey)then
   chosenKey,chosen=key,peer
  end
 end
 coordinator,coordinatorKey=chosen,chosenKey
end
DiscoverCoordinator()
local function Adopt(entry)
 local peer=Coordinator();if not peer or entry.peer==peer then return end
 -- Registration may be refused during combat. Retry at the next lifecycle event.
 local ok,accepted=pcall(peer.Register,peer,entry.frame,{owned=true,close=entry.close,refresh=entry.refresh})
 if ok and accepted then entry.peer=peer elseif not ok then W.lastCompatibilityError=tostring(accepted):sub(1,300)end
end
local function Open(entry)
 serial=serial+1;entry.at=serial
end
function W:Focus(frame)
 for _=1,64 do
  if Forbidden(frame)then return false end
  local entry=roots[frame]
  if entry and Visible(frame)then
   Open(entry);Adopt(entry)
   local peer=Coordinator();if peer and entry.peer==peer and type(peer.Focus)=="function"then
    local ok,err=pcall(peer.Focus,peer,frame);if not ok then W.lastCompatibilityError=tostring(err):sub(1,300)end
   end
   return true
  end
  frame=Read(frame,"GetParent")
 end
 return false
end
function W:Top()
 local chosen
 for frame,entry in pairs(roots)do
  if entry.at and Safe(frame)and Visible(frame)then
   local strata=ranks[Read(frame,"GetFrameStrata")]or 0
   local level=Read(frame,"GetFrameLevel")or 0
   if not chosen or strata>chosen.strata or strata==chosen.strata and(level>chosen.level or level==chosen.level and entry.at>chosen.at)then
    chosen={frame=frame,strata=strata,level=level,at=entry.at}
   end
  end
 end
 return chosen and chosen.frame
end
function W:CloseFrame(frame)
 local entry=roots[frame]
 if not entry or not Safe(frame)or not Visible(frame)then return false end
 -- These roots have no protected controls; their close callbacks own any action
 -- cancellation. A failed callback must never fall through to a second close.
 if entry.close then entry.close()else frame:Hide()end
 return true
end
function W:CloseOne()
 local peer=Coordinator()
 if peer then
  for _,entry in pairs(roots)do Adopt(entry)end
  local before={}
  for frame in pairs(roots)do if Visible(frame)then before[frame]=true end end
  local peerTop=type(peer.Top)=="function"and peer:Top()
  if peerTop and Visible(peerTop)then before[peerTop]=true end
  if peer:CloseOne()then return true end
  -- Respect a foreign close callback which hid a root but returned false.
  for frame in pairs(before)do if not Visible(frame)then return true end end
 end
 return self:CloseFrame(self:Top())
end
function W:Register(frame,options)
 options=options or{}
 if not Safe(frame)or type(frame.HookScript)~="function"then return false end
 local entry=roots[frame]
 if entry then
  if type(options.close)=="function"then entry.close=options.close end
  if type(options.refresh)=="function"then entry.refresh=options.refresh end
  entry.peer=nil;Adopt(entry);return true
 end
 entry={frame=frame,close=type(options.close)=="function"and options.close or nil,refresh=type(options.refresh)=="function"and options.refresh or nil}
 roots[frame]=entry
 Hook(frame,"OnShow",function()Open(entry);Adopt(entry)end)
 Hook(frame,"OnHide",function()if Read(frame,"IsShown")~=true then entry.at=nil end end)
 Hook(frame,"OnMouseDown",function()W:Focus(frame)end)
 local name=Read(frame,"GetName")
 -- Keep explicit native close-all behavior. Only the qualified Escape call is
 -- intercepted below; this list is never used as the one-window dispatcher.
 if type(name)=="string"and name~=""and _G[name]==frame and type(UISpecialFrames)=="table"then
  local found=false;for _,value in pairs(UISpecialFrames)do if value==name then found=true;break end end
  if not found then UISpecialFrames[#UISpecialFrames+1]=name end
 end
 if Visible(frame)then Open(entry)end
 Adopt(entry);W:Install();return true
end
function W.IsNativeEscCaller(stack)
 if type(stack)~="string"or #stack>16384 then return false end
 local peer=Coordinator()
 for line in stack:gmatch("[^\r\n]+")do
  local normalized=line:gsub("\\","/")
  local own=normalized:find("/WatchDesk/Windows.lua",1,true)
  local bridge=peer and type(peer.IsNativeEscCaller)=="function"and normalized:find("/WindowEscape.lua",1,true)
  if not own and not bridge and not line:match("^%s*%[C%]")and not line:match("^%s*stack traceback:")then
   local source=line:match("^%s*(.-):%d+:")
   if not source then return false end
   source=source:gsub("\\","/")
   local named=line:find("in function 'ToggleGameMenu'",1,true)or line:find("in function "..string.char(96).."ToggleGameMenu'",1,true)
   return named~=nil and source:find("Blizzard_UIParent/TBC/UIParent.lua",1,true)~=nil
  end
 end
 return false
end
local function NativeEscCall()
 if type(debugstack)~="function"or type(nativeToggle)~="function"or ToggleGameMenu~=nativeToggle then return false end
 if type(GetBuildInfo)~="function"then return false end
 local buildOK,_,_,_,interface=pcall(GetBuildInfo);if not buildOK or interface~=20506 then return false end
 local ok,stack=pcall(debugstack,2,16,0)
 return ok and W.IsNativeEscCaller(stack)or false
end
function W:Install()
 if installed then return true end
 if type(CloseAllWindows)~="function"or type(ToggleGameMenu)~="function"then return false end
 local previous=CloseAllWindows;nativeToggle=ToggleGameMenu
 CloseAllWindows=function(...)
  if not closing and select("#",...)==0 and NativeEscCall()then
   closing=true;local ok,handled=pcall(W.CloseOne,W);closing=false
   if not ok then W.lastError=tostring(handled):sub(1,300);error(handled,0)end
   if handled then return true end
  end
  return previous(...)
 end
 installed=true;return true
end
function NS.RegisterWindow(frame,options)return W:Register(frame,options)end
function NS.FocusWindow(frame)return W:Focus(frame)end
function NS.CloseWindow(frame)return W:CloseFrame(frame)end
function NS.CloseOneWindow()return W:CloseOne()end
local events=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","PLAYER_LOGIN","PLAYER_REGEN_ENABLED","GLOBAL_MOUSE_DOWN"})do events:RegisterEvent(event)end
events:SetScript("OnEvent",function(_,event)
 if event=="GLOBAL_MOUSE_DOWN"then
  local focus
  if type(GetMouseFoci)=="function"then local ok,foci=pcall(GetMouseFoci);if ok and type(foci)=="table"then focus=foci[1]end
  elseif type(GetMouseFocus)=="function"then local ok,value=pcall(GetMouseFocus);if ok then focus=value end end
  W:Focus(focus)
 else
  DiscoverCoordinator();W:Install();for _,entry in pairs(roots)do Adopt(entry)end
 end
end)
W:Install()
