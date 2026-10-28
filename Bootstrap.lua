local ADDON,NS=...
NS.version="0.2.1"
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
    local function Whole(v,low,high,fallback)return Number(v)and v==math.floor(v)and v>=low and v<=high and v or fallback end
    settings.watches[#settings.watches+1]={itemID=id,checked=entry.checked==true,maxUnitCopper=Price(entry.maxUnitCopper),baitUnitCopper=Price(entry.baitUnitCopper),
     maxQuantity=Whole(entry.maxQuantity,0,1000000000,0),maxSpendCopper=Price(entry.maxSpendCopper),duration=Whole(entry.duration,1,3,1),baitQuantity=Whole(entry.baitQuantity,1,10000,1)}
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
 local cached=type(hash_SlashCmdList)=="table"and(hash_SlashCmdList["/WD"]or hash_SlashCmdList["/wd"])
 local owner=cached and cached~=Open and "cached command"or nil
 for key,handler in pairs(SlashCmdList)do
  if owner then break end
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

-- Only visible Blizzard item cards: leave scanner tooltips and other addons' rows alone.
-- A second line in the name region keeps native row indexes, colors and scripts intact.
local itemTips=setmetatable({}, {__mode="k"})
local function ItemTooltipID(tip)
 if not tip or tip.IsForbidden and tip:IsForbidden() or not tip.GetItem or not tip.GetName then return end
 if tip.IsShown and not tip:IsShown()then return end
 local _,link=tip:GetItem()
 local id=type(link)=="string"and tonumber(link:match("item:(%d+)"))
 if not id or id<1 or id>10000000 then return end
 local name=tip:GetName()
 local title=name and _G[name.."TextLeft1"]
 if not title or not title.GetText or not title.SetText then return end
 local text=title:GetText()
 if type(text)~="string"or text==""then return end
 local label="\n|cff9fa7b3Item ID: "..id.."|r"
 if text:find(label,1,true)then return end
 -- Remove only our exact annotation if the native card was reused for another item.
 text=text:gsub("\n|cff9fa7b3Item ID: %d+|r","")
 local first,rest=text:match("^([^\n]*)(.*)$")
 title:SetText(first..label..rest)
 -- Refresh native dimensions only for a card already visible; never unhide a tip.
 if tip.IsShown and tip:IsShown()and tip.Show then tip:Show()end
end
local function SafeItemTooltipID(tip)
 local ok,err=pcall(ItemTooltipID,tip)
 if not ok then NS.itemTooltipError=tostring(err):sub(1,300)end
end
local function InstallItemTooltips()
 for _,name in ipairs({"GameTooltip","ItemRefTooltip","ShoppingTooltip1","ShoppingTooltip2","ItemRefShoppingTooltip1","ItemRefShoppingTooltip2"})do
  local tip=_G[name]
  if tip and not itemTips[tip]and tip.HasScript and tip.HookScript
   and not(tip.IsForbidden and tip:IsForbidden())then
   if tip:HasScript("OnTooltipSetItem")then tip:HookScript("OnTooltipSetItem",SafeItemTooltipID)end
   if tip:HasScript("OnShow")then tip:HookScript("OnShow",SafeItemTooltipID)end
   itemTips[tip]=true
  end
 end
end
local tooltipEvents=CreateFrame("Frame")
tooltipEvents:RegisterEvent("PLAYER_LOGIN");tooltipEvents:RegisterEvent("ADDON_LOADED")
tooltipEvents:SetScript("OnEvent",InstallItemTooltips)
InstallItemTooltips()
