local _,NS=...
-- Public edition: manual prices, one-page queries, and explicit transaction clicks.
local E={};NS.Engine=E
local S={open=false,epoch=0,results={},limits={},status="Visit an auctioneer.",page=0}
local ownQuery,ownBid,ownSlot,ownPost=false,false,false,false
local function Now()return GetTime()end
local function Refresh()if NS.Refresh then NS.Refresh()end end
local function Status(text)S.status=text;Refresh();return false,text end
local function ID(value)return tonumber(tostring(value or ""):match("item:(%d+)")or tostring(value or ""):match("^i:(%d+)")or value)end
local function Integer(n,min,max)return type(n)=="number"and n==math.floor(n)and n>=min and n<=max end
local function Key(link)
 local s=type(link)=="string"and link:match("item:([^|]+)");if not s then return end
 local p={};for v in(s..":"):gmatch("([^:]*):")do p[#p+1]=v;if #p==8 then break end end
 while #p<8 do p[#p+1]="0"end;return table.concat(p,":")
end
local function Info(id,link)
 local get=GetItemInfo or(C_Item and C_Item.GetItemInfo);if not get then return end
 local name,canonical=get(link or id);if not name or not canonical then return end
 return{name=name,link=link or canonical,key=Key(link or canonical),itemID=id}
end
local function Limit(id)
 local known=S.limits[id];if known then return known end
 local db=NS.GetSettings and NS.GetSettings()or{}
 for _,w in ipairs(db.watches or{})do if w.itemID==id then return{maxUnitCopper=w.maxUnitCopper or 0,baitUnitCopper=w.baitUnitCopper or 0}end end
 return{maxUnitCopper=0,baitUnitCopper=0}
end
local function ExternalBusy()
 local ah=Auctionator and Auctionator.AH
 local scan=ah and ah.Internals and ah.Internals.scan
 if scan and(scan.scanRunning or scan.waitingOnPage)then return true end
 local queue=ah and ah.Queue and ah.Queue.queue
 if type(queue)=="table"and next(queue)then return true end
 local throttle=ah and ah.Internals and ah.Internals.throttling
 if throttle and type(throttle.AnyWaiting)=="function"then local ok,busy=pcall(throttle.AnyWaiting,throttle);if not ok or busy then return true end end
 return false
end
local function Context()
 local _,_,_,version=GetBuildInfo();if version~=20506 then return "This edition supports TBC Anniversary interface 20506."end
 if NS.CanAct then local ok,why=NS.CanAct();if not ok then return why or "Another auction tool is active."end end
 if ExternalBusy()then return "Another auction search is active. Wait for it to finish."end
 if not S.open or not AuctionFrame or not AuctionFrame:IsShown()then return "Visit an auctioneer first."end
 if InCombatLockdown and InCombatLockdown()then return "Wait until combat ends."end
 if GetCursorInfo and GetCursorInfo()then return "Return the cursor item first."end
 if S.blocked then return "The last response is uncertain. Check auctions/mail and reopen the auctioneer."end
 if S.pending then return "Wait for the auction-house response."end
end
local function Invalidate(text)
 S.epoch=S.epoch+1;S.valid=nil;S.query=nil;S.queue=nil;S.afterPostScanIDs=nil
 if text then S.status=text end;Refresh()
end
local function ReadRow(index)
 local name,_,count,_,_,_,_,_,_,buyout,bid,_,_,owner,full,_,id,complete=GetAuctionItemInfo("list",index)
 local link=GetAuctionItemLink("list",index)
 if not name or not link or not Integer(count,1,10000)or not Integer(buyout,1,2147483647)then return end
 owner=full or owner;if type(owner)~="string"or owner==""then return end
 local me=GetUnitName and GetUnitName("player",true)or UnitName("player")
 if owner==me or owner==UnitName("player")or owner:match("^([^%-]+)")==UnitName("player")or bid==buyout then return end
 return{index=index,count=count,buyout=buyout,unitPrice=buyout/count,owner=owner,link=link,itemID=tonumber(id)or ID(link),key=Key(link)}
end
local function ReadyRow(row)
 local result=S.results[S.itemID]
 if not result or S.query or S.queue or S.pending or not S.valid or S.valid~=result.epoch or result.epoch~=S.epoch or Now()-result.at>15 then return false end
 if S.nativeItemID~=S.itemID or S.nativePage~=result.page then return false end
 local live=ReadRow(row.index)
 return S.results[S.itemID]==result and result.epoch==S.epoch and S.valid==result.epoch
  and live and live.link==row.link and live.key==row.key and live.itemID==row.itemID and live.count==row.count
  and live.buyout==row.buyout and live.owner==row.owner
end
local function Guid(bag,slot)
 if C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot then
  return C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag,slot))
 end
end
local function Sell()
 if not GetAuctionSellItemInfo then return end
 local name,_,count,_,_,_,_,_,_,id,guid=GetAuctionSellItemInfo()
 return name,tonumber(id),guid,count
end
local function Prepared()
 local p=S.prepared;if not p then return false end
 local name,id,guid,count=Sell();local info=C_Container and C_Container.GetContainerItemInfo(p.bag,p.slot)
 return name and id==p.itemID and guid==p.guid and count==p.count and info and info.itemID==p.itemID
  and info.isBound==false and info.stackCount==p.count and Key(info.hyperlink)==p.key and Guid(p.bag,p.slot)==p.guid
  and S.item and p.key==S.item.key and p.itemID==S.itemID and p.price==Limit(S.itemID).baitUnitCopper
end
local function OwnCursor(p)
 local kind,id,link=GetCursorInfo()
 local info=C_Container and C_Container.GetContainerItemInfo(p.bag,p.slot)
 return kind=="item"and tonumber(id)==p.itemID and link==p.link and Key(link)==p.key
  and info and info.itemID==p.itemID and info.isLocked==true and info.isBound==false
  and info.stackCount==p.count and Key(info.hyperlink)==p.key and Guid(p.bag,p.slot)==p.guid
end
local function ReturnOwnCursor(p)
 if p and OwnCursor(p)then ClearCursor();return true end
 return false
end
local function ReleasePrepared()
 local p=S.prepared;S.prepared=nil;if not p then return end
 local name,id,guid=Sell()
 if not(InCombatLockdown and InCombatLockdown())and name and id==p.itemID and guid==p.guid and not(GetCursorInfo and GetCursorInfo())then
  ownSlot=true;pcall(ClickAuctionSellItemButton);ownSlot=false
  ReturnOwnCursor(p)
 end
end
function E.SetItem(value)
 local id=ID(value);if not Integer(id,1,10000000)then return Status("Choose an item link or item ID.")end
 if S.pending or S.query or S.queue then return Status("Stop the scan or wait for the current action first.")end
 local requested=type(value)=="string"and value:find("item:")and value or nil
 local nextItem=Info(id,requested);local requestedKey=requested and Key(requested)or(nextItem and nextItem.key)
 if S.itemID~=id or(S.item and requestedKey and S.item.key~=requestedKey)then ReleasePrepared();S.valid=nil end
 S.itemID=id;S.item=nextItem;S.requestedLink=requested
 if not S.item and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id)end
 S.status=S.item and "Ready. Enter prices and scan."or "Waiting for item information.";Refresh();return true
end
function E.SetLimits(maxUnitCopper,baitUnitCopper)
 if not S.itemID then return Status("Choose an item first.")end
 if not Integer(maxUnitCopper,0,2147483647)or not Integer(baitUnitCopper,0,2147483647)then return Status("Enter valid prices in copper.")end
 local old=Limit(S.itemID)
 if S.prepared and old.baitUnitCopper~=baitUnitCopper then ReleasePrepared()end
 S.limits[S.itemID]={maxUnitCopper=maxUnitCopper,baitUnitCopper=baitUnitCopper};Refresh();return true
end
local function QueryItem(id,page)
 local reason=Context();if reason then return Status(reason)end
 if not CanSendAuctionQuery()then return false,"Auction house is throttled."end
 local item=id==S.itemID and S.item or Info(id);if not item then return Status("Item information is not ready. Try again.")end
 S.epoch=S.epoch+1;S.valid=nil
 local q={item=item,page=page,epoch=S.epoch,at=Now()};S.query=q;S.status="Scanning "..item.name.."…"
 ownQuery=true
 local ok=pcall(QueryAuctionItems,item.name,nil,nil,page,nil,nil,false,true)
 ownQuery=false
 if not ok then S.query=nil;S.queue=nil;return Status("The auction query could not be sent.")end
 Refresh();return true
end
function E.Scan(page)
 local reason=Context();if reason then return Status(reason)end
 if S.query or S.queue then return Status("A scan is already running.")end
 if S.prepared then return Status("Finish or release the prepared bait first.")end
 if not S.itemID then return Status("Choose an item first.")end
 page=page or 0;if not Integer(page,0,100000)then return false end
 return QueryItem(S.itemID,page)
end
function E.ScanList(ids)
 local reason=Context();if reason then return Status(reason)end
 if S.query or S.queue or S.prepared then return Status("Finish the current scan or bait preparation first.")end
 if type(ids)~="table"then return false end
 local queue,seen={},{}
 for _,id in ipairs(ids)do id=ID(id);if Integer(id,1,10000000)and not seen[id]then seen[id]=true;queue[#queue+1]=id end end
 if #queue==0 then return Status("Check at least one item.")end
 if #queue>100 then return Status("Scan at most 100 checked items at once.")end
 S.queue=queue;S.queueAt=Now();S.queueDeadline=Now()+15;S.status="Scanning checked items…";Refresh();return true
end
function E.Stop()
 S.query=nil;S.queue=nil;S.valid=nil;S.afterPostScanIDs=nil;ReleasePrepared()
 return Status(S.pending and "Waiting for the submitted auction action."or "Stopped. Nothing else will be bought or posted.")
end
local function Results()
 local q=S.query;if not q or q.epoch~=S.epoch then return end
 local shown,total=GetNumAuctionItems("list");local rows={}
 for i=1,shown do
  local _,_,_,_,_,_,_,_,_,_,_,_,_,owner,full=GetAuctionItemInfo("list",i)
  if not owner and not full then return end
  local row=ReadRow(i)
  if row and row.itemID==q.item.itemID and row.key==q.item.key then
   row.page=q.page;row.eligible=Limit(row.itemID).maxUnitCopper>0 and row.buyout<=Limit(row.itemID).maxUnitCopper*row.count
   rows[#rows+1]=row
  end
 end
 table.sort(rows,function(a,b)if a.unitPrice==b.unitPrice then return a.index<b.index end;return a.unitPrice<b.unitPrice end)
 -- Native row reads may reenter another addon's search hooks. Publish only
 -- if this is still the exact query whose response we started processing.
 if S.query~=q or q.epoch~=S.epoch then return end
 S.results[q.item.itemID]={rows=rows,page=q.page,total=total or shown,at=Now(),epoch=q.epoch};S.valid=q.epoch
 S.nativeItemID=q.item.itemID;S.nativePage=q.page;S.query=nil
 S.status=q.item.name..": "..#rows.." buyout stacks on page "..(q.page+1).."."
 if S.queue then S.queueAt=Now()+.25;S.queueDeadline=Now()+15 end;Refresh()
end
function E.BuySelected(index)
 local reason=Context();if reason then return Status(reason)end
 local result=S.results[S.itemID];local row=result and result.rows[tonumber(index)]
 if not row then return Status("Select a result first.")end
 local selected=S.itemID;local epoch=S.epoch
 local cap=Limit(S.itemID).maxUnitCopper
 if cap<=0 then return Status("Enter a maximum unit buy price first.")end
 if row.buyout>cap*row.count then return Status("That whole stack exceeds your maximum unit price.")end
 if row.buyout>GetMoney()then return Status("Not enough gold for that whole stack.")end
 if not ReadyRow(row)then return Status("Scan this item again before buying.")end
 if not CanSendAuctionQuery()then return Status("Auction house is throttled. Wait and click again.")end
 local money=GetMoney();local finalReason=Context()
 if finalReason then return Status(finalReason)end
 if S.itemID~=selected or S.epoch~=epoch or S.valid~=result.epoch or S.results[selected]~=result
  or result.rows[tonumber(index)]~=row or Now()-result.at>15 or S.query or S.queue or S.pending
  or Limit(selected).maxUnitCopper~=cap or row.buyout>money then return Status("The auction state changed. Scan again before buying.")end
 S.valid=nil;S.pending={kind="buy",at=Now()};S.status="Purchase submitted; awaiting the server."
 ownBid=true;local ok=pcall(PlaceAuctionBid,"list",row.index,row.buyout);ownBid=false
 if not ok then S.pending=nil;S.blocked=true;return Status("Purchase call failed. Check auctions/mail and reopen the auctioneer.")end
 Refresh();return true
end
function E.PostBait()
 local reason=Context();if reason then return Status(reason)end
 if S.query or S.queue then return Status("Stop the scan first.")end
 if not S.itemID or not S.item then return Status("Choose an item first.")end
 local price=Limit(S.itemID).baitUnitCopper
 if price<=0 then return Status("Enter a bait unit price first.")end
 if not C_Container or not C_Container.GetContainerItemInfo or not C_Container.PickupContainerItem or not ClickAuctionSellItemButton or not PostAuction then return Status("Native selling APIs are unavailable.")end
 if not S.prepared then
  if Sell()then return Status("Clear the auction selling slot first.")end
  for bag=0,NUM_BAG_SLOTS or 4 do
   for slot=1,C_Container.GetContainerNumSlots(bag)do
    local info=C_Container.GetContainerItemInfo(bag,slot);local guid=info and Guid(bag,slot)
    if info and info.itemID==S.itemID and info.isBound==false and info.isLocked==false
     and type(guid)=="string"and guid~=""and Integer(info.stackCount,1,10000)and Key(info.hyperlink)and Key(info.hyperlink)==S.item.key then
     local intent={bag=bag,slot=slot,itemID=S.itemID,guid=guid,key=Key(info.hyperlink),link=info.hyperlink,count=info.stackCount,price=price}
     S.prepared=intent;ownSlot=true
     local ok=pcall(C_Container.PickupContainerItem,bag,slot)
     if not ok or not OwnCursor(intent)or Sell()then ownSlot=false;ReturnOwnCursor(intent);S.prepared=nil;return Status("The cursor or selling slot changed. Nothing was posted.")end
     ok=pcall(ClickAuctionSellItemButton);ownSlot=false
     if not ok then ReturnOwnCursor(intent);ReleasePrepared();return Status("The bag item could not be prepared.")end
     if GetCursorInfo()then ReturnOwnCursor(intent);S.prepared=nil;return Status("The cursor changed during preparation. Nothing was posted.")end
     if not Prepared()then
      if Sell()then S.prepared=nil;return Status("The native selling item changed. Nothing was posted.")end
      return Status("Waiting for the native selling slot. Click again when ready.")
     end
     return Status("Bait loaded. Review its price, then click Post 1 bait.")
    end
   end
  end
  return Status("No unlocked, unbound matching bag item with a native GUID was found.")
 end
 if not Prepared()then ReleasePrepared();return Status("The prepared item or price changed. Load the bait again.")end
 local prepared=S.prepared;local selected=S.itemID;local epoch=S.epoch
 local ok,deposit=pcall(GetAuctionDeposit,1,price,price,1,1)
 if not ok or not Integer(deposit,0,2147483647)then return Status("The native deposit is not available yet. Click again when ready.")end
 local money=GetMoney();local stillPrepared=Prepared();local finalReason=Context()
 if finalReason then return Status(finalReason)end
 if deposit>money then return Status("Not enough gold for the auction deposit.")end
 if not stillPrepared or S.prepared~=prepared or S.itemID~=selected or S.epoch~=epoch or S.pending or S.query or S.queue
  or Limit(selected).baitUnitCopper~=price then return Status("The prepared item or auction state changed. Nothing was posted.")end
 S.valid=nil;S.pending={kind="post",at=Now()};S.prepared=nil;S.status="Posting one bait for 12 hours; awaiting the server."
 ownPost=true;local success=pcall(PostAuction,price,price,1,1,1,true);ownPost=false
 if not success then S.pending=nil;S.blocked=true;return Status("Post call failed. Check Auctions and reopen the auctioneer.")end
 S.prepared=nil;Refresh();return true
end
function E.BaitScan(ids)
 if type(ids)~="table"then return Status("Check at least one item before Bait + Scan.")end
 local checked,seen={},{}
 for _,value in ipairs(ids)do
  local id=ID(value)
  if not Integer(id,1,10000000)then return Status("The checked item list changed. Check it and try again.")end
  if not seen[id]then checked[#checked+1]=id;seen[id]=true end
 end
 if #checked==0 or #checked>100 then return Status("Check between 1 and 100 items before Bait + Scan.")end
 if not seen[S.itemID]then return Status("Check the selected bait item before Bait + Scan.")end
 local reason=Context();if reason then return Status(reason)end
 if S.query or S.queue then return Status("Stop the current scan before Bait + Scan.")end
 -- This short-lived continuation permits only a read-only scan after the
 -- server acknowledges the explicitly clicked single-item post.
 local wasReady=Prepared()
 if S.prepared and not wasReady then return Status("Waiting for the native selling slot. Click Bait Scan again when ready.")end
 S.afterPostScanIDs=checked
 local posted=E.PostBait()
 if not posted and not wasReady and not S.pending and Prepared()then posted=E.PostBait()end
 if not posted then
  S.afterPostScanIDs=nil
  if S.prepared and not Prepared()then return Status("Waiting for the native selling slot. Click Bait + Scan again when ready.")end
 end
 return posted
end
function E.Snapshot()
 local item=S.item or(S.itemID and Info(S.itemID,S.requestedLink));if item then S.item=item end
 local r=S.results[S.itemID]or{};local limits=Limit(S.itemID)
 return{itemID=S.itemID,itemLink=item and item.link,itemName=item and item.name,rows=r.rows or{},resultsByItem=S.results,status=S.status,
  open=S.open,scanning=S.query~=nil or S.queue~=nil,pending=S.pending~=nil,page=r.page or 0,total=r.total or 0,
  prepared=Prepared()and true or false,preparing=S.prepared~=nil and not Prepared(),postReady=(not S.prepared or Prepared())and S.open and not S.blocked and not S.pending and not S.query and not S.queue and limits.baitUnitCopper>0,
  buyReady=S.open and not S.blocked and not S.pending and not S.query and not S.queue and S.valid==r.epoch and r.epoch==S.epoch and S.nativeItemID==S.itemID and r.at and Now()-r.at<=15 and true or false,
  maxUnitCopper=limits.maxUnitCopper,baitUnitCopper=limits.baitUnitCopper,currentPageItemID=S.nativeItemID}
end
local frame=CreateFrame("Frame")
for _,event in ipairs({"AUCTION_HOUSE_SHOW","AUCTION_HOUSE_CLOSED","AUCTION_ITEM_LIST_UPDATE","NEW_AUCTION_UPDATE","CHAT_MSG_SYSTEM","UI_ERROR_MESSAGE","GET_ITEM_INFO_RECEIVED"})do frame:RegisterEvent(event)end
frame:SetScript("OnEvent",function(_,event,a,b)
 if event=="AUCTION_HOUSE_SHOW"then S.open=true;S.blocked=nil;S.pending=nil;S.status="Choose an item, enter prices, and scan."
 elseif event=="AUCTION_HOUSE_CLOSED"then S.open=false;S.query=nil;S.queue=nil;S.valid=nil;S.prepared=nil;S.afterPostScanIDs=nil;S.status="Visit an auctioneer."
 elseif event=="AUCTION_ITEM_LIST_UPDATE"then if S.query then Results()else S.valid=nil end
 elseif event=="CHAT_MSG_SYSTEM"and S.pending then
  if(S.pending.kind=="buy"and a==ERR_AUCTION_BID_PLACED)or(S.pending.kind=="post"and a==ERR_AUCTION_STARTED)then
   local kind=S.pending.kind;local scanIDs=kind=="post"and S.afterPostScanIDs or nil
   S.pending=nil;S.valid=nil;S.afterPostScanIDs=nil;S.status=kind=="buy"and "Purchase accepted. Scan again for another stack."or "One bait posted."
   if scanIDs then E.ScanList(scanIDs)end
  end
 elseif event=="UI_ERROR_MESSAGE"and S.pending then S.blocked=true;S.pending=nil;S.afterPostScanIDs=nil;S.status=tostring(b or a or "Auction action failed.").." Check auctions/mail and reopen the auctioneer."
 end
 Refresh()
end)
local elapsed=0
frame:SetScript("OnUpdate",function(_,delta)
 elapsed=elapsed+delta;if elapsed<.25 then return end;elapsed=0
 if S.valid then local r=S.results[S.nativeItemID];if not r or Now()-r.at>15 then S.valid=nil;Refresh()end end
 if S.pending and Now()-S.pending.at>10 and not S.blocked then S.blocked=true;S.afterPostScanIDs=nil;S.status="Unconfirmed auction response. Check auctions/mail and reopen the auctioneer.";Refresh()end
 if S.query and Now()-S.query.at>12 then S.query=nil;S.queue=nil;S.valid=nil;Status("Scan timed out. Click Scan to try again.")end
 if S.queue and not S.query and not S.pending and Now()>=(S.queueAt or 0)then
  if #S.queue==0 then S.queue=nil;Status("Checked-item scan complete. Select an item to review.")
  elseif Now()>(S.queueDeadline or 0)then S.queue=nil;Status("Stopped while waiting for the auction house.")
  elseif CanSendAuctionQuery()then local id=table.remove(S.queue,1);local ok=QueryItem(id,0);if not ok then S.queue=nil end end
 end
end)
if hooksecurefunc and type(QueryAuctionItems)=="function"and type(SortAuctionSetSort)=="function"and type(PlaceAuctionBid)=="function"and type(PostAuction)=="function"and type(ClickAuctionSellItemButton)=="function"then
 hooksecurefunc("QueryAuctionItems",function(name,minLevel,maxLevel,page,usable,quality,getAll,exact,filters)
  local q=S.query;local ours=ownQuery and q and name==q.item.name and minLevel==nil and maxLevel==nil and page==q.page
   and usable==nil and quality==nil and getAll==false and exact==true and filters==nil
  if not ours then Invalidate("Another auction search took control. Scan again when it finishes.")end
 end)
 hooksecurefunc("SortAuctionSetSort",function(kind)if kind=="list"then Invalidate("Auction results were sorted. Scan again before buying.")end end)
 hooksecurefunc("PlaceAuctionBid",function()if not ownBid then Invalidate("Another auction action changed the results.")end end)
 hooksecurefunc("PostAuction",function()if not ownPost then S.prepared=nil;S.blocked=true;Invalidate("Another auction was posted. Check Auctions and reopen the auctioneer.")end end)
 hooksecurefunc("ClickAuctionSellItemButton",function()if not ownSlot then S.prepared=nil end end)
 for _,name in ipairs({"SortAuctionClearSort","SortAuctionApplySort"})do
  if type(_G[name])=="function"then hooksecurefunc(name,function(kind)if kind=="list"then Invalidate("Auction results were sorted. Scan again before buying.")end end)end
 end
end
