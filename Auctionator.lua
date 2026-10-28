local _,NS=...
-- Optional public search handoff. Auctionator owns its results and purchases.
local A={};NS.Auctionator=A
local searching=false
local function API()
 local addon=_G.Auctionator
 local api=type(addon)=="table"and addon.API
 local v1=type(api)=="table"and api.v1
 if type(v1)~="table"then return end
 if type(v1.MultiSearchExact)=="function"then return v1.MultiSearchExact,true end
 if type(v1.MultiSearch)=="function"then return v1.MultiSearch,false end
end
function A.Available()return API()~=nil end
local function Shown(frame)
 if not frame or type(frame.IsShown)~="function"then return false end
 local ok,shown=pcall(frame.IsShown,frame);return ok and shown and true or false
end
local function State()
 local engine=NS.Engine
 if type(engine)~="table"or type(engine.Snapshot)~="function"or type(engine.Stop)~="function"then
  return nil,"Watch Desk's auction engine is not ready."
 end
 local ok,state=pcall(engine.Snapshot)
 if not ok or type(state)~="table"then return nil,"Watch Desk's auction state is not ready."end
 return state
end
local function Context()
 if not A.Available()then return false,"Auctionator's public search API is unavailable. Enable a compatible Auctionator edition and reload."end
 if InCombatLockdown and InCombatLockdown()then return false,"Leave combat before opening an Auctionator search."end
 if not(Shown(AuctionFrame)or Shown(AuctionHouseFrame))then return false,"Visit an auctioneer first."end
 if GetCursorInfo and GetCursorInfo()or CursorHasItem and CursorHasItem()then return false,"Clear the cursor before opening an Auctionator search."end
 local state,why=State();if not state then return false,why end
 if not state.open then return false,"Visit an auctioneer first."end
 if state.pending then return false,"Wait for the submitted auction action before opening Auctionator."end
 if state.prepared or state.preparing then return false,"Stop the prepared bait action before opening Auctionator."end
 return true,state
end
function A.CanSearch()
 if searching then return false,"An Auctionator search handoff is already in progress."end
 local ok,state=Context();if not ok then return false,state end
 if state.responseAmbiguous then return false,"Reopen the auctioneer to clear the ambiguous auction response before opening Auctionator."end
 -- An active read can be stopped by Search; its late reply must still drain.
 return true
end
local function ItemID(value)
 local id
 if type(value)=="number"then id=value
 elseif type(value)=="string"then
  id=tonumber(value:match("^%s*(%d+)%s*$")or value:match("^i:(%d+)$")or value:match("^item:(%d+):")or value:match("^item:(%d+)$")or value:match("|Hitem:(%d+):"))
 end
 if type(id)=="number"and id==math.floor(id)and id>=1 and id<=10000000 then return id end
end
local function Resolve(value)
 local values
 if type(value)=="table"then
  local count,max=0,0
  for k in pairs(value)do
   if type(k)~="number"or k~=math.floor(k)or k<1 or k>100 then return nil,"Choose a list of at most 100 item IDs or item links."end
   count=count+1;if k>max then max=k end
  end
  if count==0 or count~=max then return nil,"Choose a nonempty list without missing entries."end
  values=value
 else values={value}end
 local ids,seen={},{}
 for i=1,#values do
  local id=ItemID(rawget(values,i))
  if not id then return nil,"Choose valid item IDs or item links for the Auctionator search."end
  if not seen[id]then ids[#ids+1]=id;seen[id]=true end
 end
 if #ids==0 then return nil,"Choose at least one item for the Auctionator search."end
 local get=GetItemInfo or(C_Item and C_Item.GetItemInfo)
 if type(get)~="function"then return nil,"Native item information is unavailable."end
 local terms,names={},{}
 for _,id in ipairs(ids)do
  local ok,name=pcall(get,id)
  if not ok or type(name)~="string"or not name:find("%S")then
   if C_Item and type(C_Item.RequestLoadItemDataByID)=="function"then pcall(C_Item.RequestLoadItemDataByID,id)end
   return nil,"The local item name for ID "..id.." is not ready. Wait a moment, then click Auctionator search again."
  end
  -- Raw localized names only: never pass advanced search syntax or display links.
  if name:find('[;^"%c]')then return nil,"That item name contains unsupported Auctionator search characters."end
  if not names[name]then terms[#terms+1]=name;names[name]=true end
 end
 return terms
end
local function Search(value)
 local ok,state=Context();if not ok then return false,state end
 local terms,why=Resolve(value);if not terms then return false,why end
 -- Item lookups can invoke other addons. Recheck before stopping any work.
 ok,state=Context();if not ok then return false,state end
 if state.responseAmbiguous then return false,"Reopen the auctioneer to clear the ambiguous auction response before opening Auctionator."end
 local stopped=pcall(NS.Engine.Stop)
 if not stopped then return false,"Watch Desk could not stop its scan. Stop it before opening Auctionator."end
 ok,state=Context();if not ok then return false,state end
 if state.responseAmbiguous then return false,"Reopen the auctioneer to clear the ambiguous auction response before opening Auctionator."end
 if state.waitingForResponse then return false,"Watch Desk stopped. Wait for the earlier auction response, then click Auctionator search again. Reopen the auctioneer if it stalls."end
 if state.scanning or state.lookRunning then return false,"Stop Watch Desk's scan before opening Auctionator."end
 local search,exact=API();if not search then return false,"Auctionator's public search API is no longer available."end
 local called=pcall(search,"Watch Desk",terms)
 if not called then return false,"Auctionator could not open the search. Check its status before trying again."end
 return true,"Opened Auctionator's Shopping "..(exact and "exact-name "or "name ").."search for "..#terms.." item(s). Review and purchase there."
end
function A.Search(value)
 if searching then return false,"An Auctionator search handoff is already in progress."end
 searching=true
 local ok,success,why=pcall(Search,value)
 searching=false
 if not ok then return false,"The Auctionator handoff could not finish. Check the auction state before trying again."end
 return success,why
end
