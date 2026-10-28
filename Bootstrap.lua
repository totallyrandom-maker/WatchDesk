local ADDON,NS=...
NS.version="0.1.0"
local settings
local function Number(v)return type(v)=="number"and v==v and math.abs(v)<math.huge end
function NS.GetSettings()
 if settings then return settings end
 local old=type(WatchDeskDB)=="table"and WatchDeskDB or{}
 settings={watches={},window={}}
 if type(old.watches)=="table"then
  local seen={}
  for _,entry in ipairs(old.watches)do
   local id=type(entry)=="table"and tonumber(entry.itemID)
   if Number(id)and id>0 and id<=10000000 and id==math.floor(id)and not seen[id]and #settings.watches<100 then
    seen[id]=true
    local function Price(v)return Number(v)and math.max(0,math.min(100000000000,math.floor(v+.5)))or 0 end
    settings.watches[#settings.watches+1]={itemID=id,checked=entry.checked==true,maxUnitCopper=Price(entry.maxUnitCopper),baitUnitCopper=Price(entry.baitUnitCopper)}
   end
  end
 end
 if type(old.window)=="table"then
  for _,key in ipairs({"x","y"})do if Number(old.window[key])then settings.window[key]=old.window[key]end end
  if Number(old.window.scale)then settings.window.scale=math.max(.6,math.min(1.6,old.window.scale))end
 end
 WatchDeskDB=settings
 return settings
end
function NS.Notify(message)
 if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage("|cff70d5d5Watch Desk:|r "..tostring(message))end
end
function NS.CanAct()return not(InCombatLockdown and InCombatLockdown())end
local function Open()
 if NS.Window and NS.Window.Toggle then NS.Window.Toggle()end
end
local function ClaimCommands()
 SlashCmdList.WATCHDESK=Open
 SLASH_WATCHDESK1="/watchdesk"
 local owner
 for key,handler in pairs(SlashCmdList)do
  if key~="WATCHDESK"and type(handler)=="function"then
   for index=1,20 do
    local alias=_G["SLASH_"..key..index]
    if not alias then break end
    if string.lower(alias)=="/wd"then owner=key;break end
   end
  end
  if owner then break end
 end
 if owner then
  SLASH_WATCHDESK2=nil
  NS.Notify("/wd is already in use. Open Watch Desk with /watchdesk.")
 else SLASH_WATCHDESK2="/wd"end
end
local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent",function()NS.GetSettings();ClaimCommands()end)
