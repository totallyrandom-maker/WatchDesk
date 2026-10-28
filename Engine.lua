local _,NS=...
-- Standalone watch workflow: manual prices, full-page scans and explicit transaction clicks.
local E={};NS.Engine=E
local S={open=false,epoch=0,results={},cacheRows=0,cacheEvicted=0,limits={},options={},session={},reserved={},scanID=0,scannedPages=0,cycleCount=0,status="Visit an auctioneer.",page=0}
-- A dispatch authorizes one exact native invocation, including its hook chain.
-- A matching nested call can consume the token first; the second observation is
-- still foreign, so identical reentrant calls cannot share one response witness.
local ownedCalls={}
local function OwnedCall(kind,fn,...)
 local token={n=select("#",...),...}
 while token.n>0 and token[token.n]==nil do token.n=token.n-1 end
 local previous=ownedCalls[kind];ownedCalls[kind]=token
 local ok,why=pcall(fn,...)
 if ownedCalls[kind]==token then ownedCalls[kind]=previous end
 return ok,why,token.used==true
end
local function ConsumeOwned(kind,...)
 local token=ownedCalls[kind]
 if not token or token.used then return false end
 local count=select("#",...);while count>0 and select(count,...)==nil do count=count-1 end
 if token.n~=count then return false end
 for i=1,token.n do if token[i]~=select(i,...)then return false end end
 token.used=true;return true
end
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
local function Options(id)
 local found=S.options[id]
 if not found then local db=NS.GetSettings and NS.GetSettings()or{};for _,w in ipairs(db.watches or{})do if w.itemID==id then found=w;break end end end
 found=found or{}
 return{maxQuantity=found.maxQuantity or 0,maxSpendCopper=found.maxSpendCopper or 0,duration=found.duration or 1,baitQuantity=found.baitQuantity or 1}
end
local function Session(id)return S.session[id]or{quantity=0,spentCopper=0}end
local function Reserved(id)return S.reserved[id]or{quantity=0,spentCopper=0}end
local function CanBuy(row,id)
 local o,t,reserved=Options(id),Session(id),Reserved(id)
 if o.maxQuantity>0 and t.quantity+reserved.quantity+row.count>o.maxQuantity then return "That whole stack exceeds this item's remaining session quantity."end
 if o.maxSpendCopper>0 and row.buyout>o.maxSpendCopper-t.spentCopper-reserved.spentCopper then return "That whole stack exceeds this item's remaining session budget."end
end
local function Summarize(rows,pages,complete)
 local s={stacks=#rows,quantity=0,eligibleStacks=0,eligibleQuantity=0,pages=pages,complete=complete and true or false}
 for _,r in ipairs(rows)do
  s.quantity=s.quantity+r.count;s.lowUnitCopper=not s.lowUnitCopper and r.unitPrice or math.min(s.lowUnitCopper,r.unitPrice);s.highUnitCopper=not s.highUnitCopper and r.unitPrice or math.max(s.highUnitCopper,r.unitPrice)
  if r.eligible then s.eligibleStacks=s.eligibleStacks+1;s.eligibleQuantity=s.eligibleQuantity+r.count end
 end;return s
end
local function ExternalBusy()
 local ah=Auctionator and Auctionator.AH
 local scan=ah and ah.Internals and ah.Internals.scan
 -- AbortQuery leaves waitingOnPage set in Auctionator; scanRunning owns its lifetime.
 if scan and scan.scanRunning then return true end
 local queue=ah and ah.Queue and ah.Queue.queue
 if type(queue)=="table"and next(queue)then return true end
 local throttle=ah and ah.Internals and ah.Internals.throttling
 if throttle and type(throttle.AnyWaiting)=="function"then local ok,busy=pcall(throttle.AnyWaiting,throttle);if not ok or busy then return true end end
 return false
end
local function Context()
 if next(ownedCalls)then return "Wait for the current auction action to finish."end
 local _,_,_,version=GetBuildInfo();if version~=20506 then return "This edition supports TBC Anniversary interface 20506."end
 if NS.CanAct then local ok,why=NS.CanAct();if not ok then return why or "Another auction tool is active."end end
 if ExternalBusy()then return "Another auction search is active. Wait for it to finish."end
 if not S.open or not AuctionFrame or not AuctionFrame:IsShown()then return "Visit an auctioneer first."end
 if InCombatLockdown and InCombatLockdown()then return "Wait until combat ends."end
 if GetCursorInfo and GetCursorInfo()then return "Return the cursor item first."end
 if S.nativeRequest then
  if S.responseAmbiguous then return "Overlapping auction searches have untagged replies. Reopen the auctioneer before using WD."end
  return "Waiting for the earlier auction search response. It will be discarded if stopped; reopen the auctioneer if it stalls."
 end
 if S.blocked then return "The last response is uncertain. Check auctions/mail and reopen the auctioneer."end
 if S.pending then return "Wait for the auction-house response."end
end
local function CancelNativeRead()
 if S.nativeRequest then S.nativeRequest.discard=true end
end
local function Invalidate(text)
 CancelNativeRead()
 S.epoch=S.epoch+1;S.valid=nil;S.query=nil;S.queue=nil;S.afterPostScanIDs=nil;S.afterPostScanOptions=nil;S.review=nil;S.reviewedIndex=nil
 if S.look then S.lookPaused=true;S.lookRunning=false;S.nextCycleAt=nil end
 if text then S.status=text end;Refresh()
end
local function ReadRow(index)
 local name,_,count,_,_,_,_,_,_,buyout,bid,_,_,owner,full,_,id,complete=GetAuctionItemInfo("list",index)
 local link=GetAuctionItemLink("list",index)
 if not name or not link or complete==false then return nil,"incomplete"end
 if not Integer(count,1,10000)or not Integer(buyout,1,2147483647)then return end
 owner=full or owner;if type(owner)~="string"or owner==""then return end
 local me=GetUnitName and GetUnitName("player",true)or UnitName("player")
 if owner==me or owner==UnitName("player")or owner:match("^([^%-]+)")==UnitName("player")or bid==buyout then return end
 return{index=index,count=count,buyout=buyout,unitPrice=buyout/count,owner=owner,link=link,itemID=tonumber(id)or ID(link),key=Key(link)}
end
local function NativeRowsComplete()
 local shown=GetNumAuctionItems("list")
 if not Integer(shown,0,50)then return false end
 for i=1,shown do
  local name,_,count,_,_,_,_,_,_,_,_,_,_,owner,full,_,_,complete=GetAuctionItemInfo("list",i)
  if not name or not Integer(count,1,10000)or not(owner or full)or complete==false or not GetAuctionItemLink("list",i)then return false end
 end
 return true
end
local function DrainNativeRead()
 local request=S.nativeRequest
 if not request or S.responseAmbiguous or not NativeRowsComplete()or S.nativeRequest~=request or S.responseAmbiguous then return end
 S.nativeRequest=nil;S.valid=nil
 S.status="Earlier auction response discarded. You can Scan or Resume Look now."
end
local function TrimResults(activeID)
 local count=0;for _,entry in pairs(S.results)do count=count+#entry.rows end
 while count>20000 do
  local oldestID,oldest
  for id,entry in pairs(S.results)do
   if id~=activeID and id~=S.itemID and(not oldest or entry.at<oldest.at or entry.at==oldest.at and id<oldestID)then oldestID,oldest=id,entry end
  end
  if not oldest then break end
  count=count-#oldest.rows;S.results[oldestID]=nil;S.cacheEvicted=S.cacheEvicted+1
 end
 S.cacheRows=count
end
local function ReadyRow(row)
 local result=S.results[S.itemID]
 if not result or S.nativeRequest or S.query or S.queue or S.lookRunning or S.pending or not S.valid or S.valid~=result.epoch or result.epoch~=S.epoch or Now()-result.at>15 then return false end
 if S.nativeItemID~=S.itemID or S.nativePage~=result.page or row.page~=S.nativePage then return false end
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
  and p.quantity==Options(S.itemID).baitQuantity and p.duration==Options(S.itemID).duration
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
  OwnedCall("slot",ClickAuctionSellItemButton)
  ReturnOwnCursor(p)
 end
end
function E.SetItem(value)
 local id=ID(value);if not Integer(id,1,10000000)then return Status("Choose an item link or item ID.")end
 if S.pending or S.query or S.queue or S.lookRunning or S.nativeRequest then return Status("Pause or stop scanning, or wait for the earlier search response first.")end
 local requested=type(value)=="string"and value:find("item:")and value or nil
 local nextItem=Info(id,requested);local requestedKey=requested and Key(requested)or(nextItem and nextItem.key)
 if S.itemID~=id or(S.item and requestedKey and S.item.key~=requestedKey)then ReleasePrepared();S.valid=nil end
 S.itemID=id;S.item=nextItem;S.requestedLink=requested;S.reviewedIndex=nil
 if not S.item and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id)end
 S.status=S.item and "Ready. Enter prices and scan."or "Waiting for item information.";Refresh();return true
end
function E.SetLimits(maxUnitCopper,baitUnitCopper)
 if S.pending or S.query or S.queue or S.lookRunning or S.nativeRequest then return Status("Pause or stop scanning before editing prices.")end
 if not S.itemID then return Status("Choose an item first.")end
 if not Integer(maxUnitCopper,0,2147483647)or not Integer(baitUnitCopper,0,2147483647)then return Status("Enter valid prices in copper.")end
 local old=Limit(S.itemID)
 if S.prepared and old.baitUnitCopper~=baitUnitCopper then ReleasePrepared()end
 S.limits[S.itemID]={maxUnitCopper=maxUnitCopper,baitUnitCopper=baitUnitCopper};Refresh();return true
end
function E.SetWatchOptions(options)
 if not S.itemID then return Status("Choose an item first.")end
 if S.pending or S.query or S.queue or S.lookRunning or S.nativeRequest then return Status("Pause or stop scanning before editing limits.")end
 if type(options)~="table"then return Status("Enter valid watch limits.")end
 local old=Options(S.itemID);local next={}
 for _,key in ipairs({"maxQuantity","maxSpendCopper","duration","baitQuantity"})do next[key]=options[key]==nil and old[key]or options[key]end
 if not Integer(next.maxQuantity,0,10000000)or not Integer(next.maxSpendCopper,0,2147483647)or not Integer(next.duration,1,3)or not Integer(next.baitQuantity,1,10000)then return Status("Use whole-number quantities, valid gold, a 12/24/48-hour duration and a positive bait stack.")end
 if S.prepared and(next.duration~=old.duration or next.baitQuantity~=old.baitQuantity)then ReleasePrepared()end
 S.options[S.itemID]=next;Refresh();return true
end
function E.ResetSession()
 if S.pending or S.query or S.queue or S.lookRunning or S.nativeRequest then return Status("Pause or stop scanning and wait for the pending action first.")end
 S.session={};S.reserved={};Refresh();return true
end
local function QueryItem(id,page)
 local reason=Context();if reason then return Status(reason)end
 if not CanSendAuctionQuery()then return false,"Auction house is throttled."end
 local item=id==S.itemID and S.item or Info(id);if not item then
  if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id)end
  return Status("Waiting for item information. The scan will continue when it loads.")
 end
 S.epoch=S.epoch+1;S.valid=nil
 local q={item=item,page=page,epoch=S.epoch,at=Now(),scanID=S.scanID,allPages=S.scanAll};S.query=q;S.nativeRequest=q;S.reviewedIndex=nil;S.status="Scanning "..item.name.." — page "..(page+1).."…"
 local ok,_,observed=OwnedCall("query",QueryAuctionItems,item.name,nil,nil,page,nil,nil,false,true)
 if not ok or not observed then
  CancelNativeRead();S.query=nil;S.queue=nil;S.responseAmbiguous=true
  return Status("The auction query could not be confirmed. Reopen the auctioneer to clear its uncertain response.")
 end
 Refresh();return true
end
function E.Scan(page)
 if S.lookRunning then return Status("Pause Look before a manual scan.")end
 local reason=Context();if reason then return Status(reason)end
 if S.query or S.queue then return Status("A scan is already running.")end
 if S.prepared then return Status("Finish or release the prepared bait first.")end
 if not S.itemID then return Status("Choose an item first.")end
 page=page or 0;if not Integer(page,0,100000)then return false end
 S.scanID=S.scanID+1;S.scanAll=false;S.scannedPages=0;S.scanPartial=false;S.review=nil
 return QueryItem(S.itemID,page)
end
function E.ScanList(ids,options)
 if S.lookRunning then return Status("Pause Look before starting another scan.")end
 local reason=Context();if reason then return Status(reason)end
 if S.query or S.queue or S.prepared then return Status("Finish the current scan or bait preparation first.")end
 if type(ids)~="table"then return false end
 local queue,seen={},{}
 for _,id in ipairs(ids)do id=ID(id);if Integer(id,1,10000000)and not seen[id]then seen[id]=true;queue[#queue+1]=id end end
 if #queue==0 then return Status("Check at least one item.")end
 if #queue>100 then return Status("Scan at most 100 checked items at once.")end
 S.scanID=S.scanID+1;S.scanAll=type(options)=="table"and options.allPages==true or false;S.scannedPages=0;S.scanPartial=false;S.review=nil;S.reviewedIndex=nil
 S.queue=queue;S.queueAt=Now();S.queueDeadline=Now()+15;S.status="Scanning checked items…";Refresh();return true
end
function E.ScanAll()
 if not S.itemID then return Status("Choose an item first.")end
 return E.ScanList({S.itemID},{allPages=true})
end
function E.StartLook(ids,options)
 options=options or{};local interval=tonumber(options.interval)or 5
 if not Integer(interval,5,300)then return Status("Look interval must be 5 to 300 whole seconds.")end
 if S.lookRunning then return Status("Look is already running.")end
 local accepted=E.ScanList(ids,{allPages=options.allPages~=false});if not accepted then return false end
 local copied={};for _,id in ipairs(S.queue)do copied[#copied+1]=id end
 S.look={ids=copied,allPages=options.allPages~=false,interval=interval};S.lookRunning=true;S.lookPaused=false;S.nextCycleAt=nil;S.cycleCount=0;Refresh();return true
end
function E.PauseLook()
 if not S.look then return Status("No Look cycle to pause.")end
 CancelNativeRead();S.lookRunning=false;S.lookPaused=true;S.nextCycleAt=nil;S.query=nil;S.queue=nil;S.valid=nil;S.review=nil
 return Status("Look paused. Review items or Resume Look when ready.")
end
function E.ResumeLook()
 if not S.look or not S.lookPaused then return Status("No paused Look cycle to resume.")end
 local look=S.look;local cycles=S.cycleCount;local accepted=E.StartLook(look.ids,{allPages=look.allPages,interval=look.interval});if accepted then S.cycleCount=cycles end;return accepted
end
function E.RecheckSelected(index)
 if S.lookRunning then return Status("Pause Look before checking a stack.")end
 local result=S.results[S.itemID];local row=result and result.rows[tonumber(index)];if not row then return Status("Select a result first.")end
 local reason=Context();if reason then return Status(reason)end
 if S.query or S.queue or S.prepared then return Status("Finish or stop the current action first.")end
 S.scanID=S.scanID+1;S.scanAll=false;S.scannedPages=0;S.review={itemID=row.itemID,key=row.key,count=row.count,buyout=row.buyout,owner=row.owner,page=row.page,link=row.link}
 local ok,why=QueryItem(S.itemID,row.page);if not ok then S.review=nil end;return ok,why
end
function E.Stop()
 CancelNativeRead()
 S.look=nil;S.lookRunning=false;S.lookPaused=false;S.nextCycleAt=nil;S.review=nil;S.reviewedIndex=nil
 S.query=nil;S.queue=nil;S.valid=nil;S.afterPostScanIDs=nil;S.afterPostScanOptions=nil;ReleasePrepared()
 return Status(S.pending and "Waiting for the submitted auction action."or(S.nativeRequest and "Stopped. Waiting to discard the earlier auction response; reopen the auctioneer if it stalls."or "Stopped. Nothing else will be bought or posted."))
end
local function Results()
 local q=S.query;if not q or q.epoch~=S.epoch or S.nativeRequest~=q or q.discard or S.responseAmbiguous then return end
 local shown,total=GetNumAuctionItems("list");local rows={}
 for i=1,shown do
  local _,_,_,_,_,_,_,_,_,_,_,_,_,owner,full=GetAuctionItemInfo("list",i)
  if not owner and not full then return end
  local row,why=ReadRow(i)
  if why=="incomplete"then return end
  if row and row.itemID==q.item.itemID and row.key==q.item.key then
   row.page=q.page;row.observedAt=Now();row.eligible=Limit(row.itemID).maxUnitCopper>0 and row.unitPrice<=Limit(row.itemID).maxUnitCopper and not CanBuy(row,row.itemID)
   rows[#rows+1]=row
  end
 end
 table.sort(rows,function(a,b)if a.unitPrice==b.unitPrice then return a.index<b.index end;return a.unitPrice<b.unitPrice end)
 -- Native row reads may reenter another addon's search hooks. Publish only
 -- if this is still the exact query whose response we started processing.
 if S.query~=q or q.epoch~=S.epoch or S.nativeRequest~=q or q.discard or S.responseAmbiguous then return end
 local prior=S.results[q.item.itemID];local pages=1
 if q.allPages and q.page>0 and prior and prior.scanID==q.scanID then
  pages=(prior.summary and prior.summary.pages or 0)+1;for _,r in ipairs(prior.rows)do rows[#rows+1]=r end
  table.sort(rows,function(a,b)if a.unitPrice==b.unitPrice then if a.page==b.page then return a.index<b.index end;return a.page<b.page end;return a.unitPrice<b.unitPrice end)
 end
 local more=q.allPages and (q.page+1)*50<(tonumber(total)or shown);local capped=more and q.page>=199
 local complete=(q.page==0 and (tonumber(total)or shown)<=50)or(q.allPages and not more)
 S.results[q.item.itemID]={rows=rows,page=q.page,total=total or shown,at=Now(),epoch=q.epoch,scanID=q.scanID,summary=Summarize(rows,pages,complete)};S.valid=q.epoch
 S.nativeItemID=q.item.itemID;S.nativePage=q.page;S.query=nil;S.nativeRequest=nil;S.scannedPages=S.scannedPages+1
 TrimResults(q.item.itemID)
 S.status=q.item.name..": "..#rows.." buyout stacks across "..pages.." scanned page(s)."
 if more and not capped and S.queue then table.insert(S.queue,1,{id=q.item.itemID,page=q.page+1})end
 if capped then S.scanPartial=true;S.status="Stopped this item at 200 pages; displayed results are partial."end
 if S.review then
  local wanted=S.review;S.review=nil;S.reviewedIndex=nil
  for i,r in ipairs(rows)do if r.itemID==wanted.itemID and r.link==wanted.link and r.key==wanted.key and r.count==wanted.count and r.buyout==wanted.buyout and r.owner==wanted.owner and r.page==wanted.page then S.reviewedIndex=i;break end end
  S.status=S.reviewedIndex and "Stack rechecked. Review quantity and total, then click Buy."or "That exact stack is gone or changed. Review the new results."
 end
 if S.queue then S.queueAt=Now()+.25;S.queueDeadline=Now()+15 end;Refresh()
end
function E.BuySelected(index)
 local reason=Context();if reason then return Status(reason)end
 local result=S.results[S.itemID];local row=result and result.rows[tonumber(index)]
 if not row then return Status("Select a result first.")end
 local selected=S.itemID;local epoch=S.epoch
 local cap=Limit(S.itemID).maxUnitCopper
 if cap<=0 then return Status("Enter a maximum unit buy price first.")end
 if row.unitPrice>cap then return Status("That whole stack exceeds your maximum unit price.")end
 local limitReason=CanBuy(row,S.itemID);if limitReason then return Status(limitReason)end
 if row.buyout>GetMoney()then return Status("Not enough gold for that whole stack.")end
 if not ReadyRow(row)then return Status("Scan this item again before buying.")end
 if not CanSendAuctionQuery()then return Status("Auction house is throttled. Wait and click again.")end
 local money=GetMoney();local finalReason=Context()
 if finalReason then return Status(finalReason)end
 if S.itemID~=selected or S.epoch~=epoch or S.valid~=result.epoch or S.results[selected]~=result
  or result.rows[tonumber(index)]~=row or Now()-result.at>15 or S.query or S.queue or S.pending
  or Limit(selected).maxUnitCopper~=cap or row.buyout>money or CanBuy(row,selected)then return Status("The auction state changed. Scan again before buying.")end
 local reserved=Reserved(selected);S.reserved[selected]={quantity=reserved.quantity+row.count,spentCopper=reserved.spentCopper+row.buyout*1.0}
 S.valid=nil;local pending={kind="buy",at=Now(),itemID=selected,quantity=row.count,total=row.buyout,dispatching=true};S.pending=pending;S.status="Purchase submitted; awaiting the server."
 local ok,_,observed=OwnedCall("bid",PlaceAuctionBid,"list",row.index,row.buyout)
 if S.pending==pending then
  pending.dispatching=false
  if not observed then pending.ambiguous=true;S.blocked=true;S.status="Purchase ownership is uncertain. Check auctions/mail and reopen the auctioneer."end
 end
 if not ok then S.pending=nil;S.blocked=true;return Status("Purchase call failed. Check auctions/mail and reopen the auctioneer.")end
 Refresh();return true
end
function E.PostBait()
 if S.lookRunning then return Status("Pause Look before posting bait.")end
 local reason=Context();if reason then return Status(reason)end
 if S.query or S.queue then return Status("Stop the scan first.")end
 if not S.itemID or not S.item then return Status("Choose an item first.")end
 local price=Limit(S.itemID).baitUnitCopper
 local options=Options(S.itemID);local quantity,duration=options.baitQuantity,options.duration
 local get=GetItemInfo or(C_Item and C_Item.GetItemInfo);local maximum=get and select(8,get(S.item.link))
 if type(maximum)=="number"and quantity>maximum then return Status("The bait quantity exceeds this item's maximum stack size.")end
 if price>math.floor(2147483647/quantity)then return Status("The bait stack total exceeds the native auction price limit.")end
 if price<=0 then return Status("Enter a bait unit price first.")end
 if not C_Container or not C_Container.GetContainerItemInfo or not C_Container.PickupContainerItem or not ClickAuctionSellItemButton or not PostAuction then return Status("Native selling APIs are unavailable.")end
 if not S.prepared then
  if Sell()then return Status("Clear the auction selling slot first.")end
  for bag=0,NUM_BAG_SLOTS or 4 do
   for slot=1,C_Container.GetContainerNumSlots(bag)do
    local info=C_Container.GetContainerItemInfo(bag,slot);local guid=info and Guid(bag,slot)
    if info and info.itemID==S.itemID and info.isBound==false and info.isLocked==false
     and type(guid)=="string"and guid~=""and Integer(info.stackCount,quantity,10000)and Key(info.hyperlink)and Key(info.hyperlink)==S.item.key then
     local intent={bag=bag,slot=slot,itemID=S.itemID,guid=guid,key=Key(info.hyperlink),link=info.hyperlink,count=info.stackCount,price=price,quantity=quantity,duration=duration}
     S.prepared=intent
     local ok=pcall(C_Container.PickupContainerItem,bag,slot)
     if not ok or S.prepared~=intent or not OwnCursor(intent)or Sell()then ReturnOwnCursor(intent);S.prepared=nil;return Status("The cursor or selling slot changed. Nothing was posted.")end
     ok=OwnedCall("slot",ClickAuctionSellItemButton)
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
 local totalPrice=price*quantity
 local ok,deposit=pcall(GetAuctionDeposit,duration,totalPrice,totalPrice,quantity,1)
 if not ok or not Integer(deposit,0,2147483647)then return Status("The native deposit is not available yet. Click again when ready.")end
 local money=GetMoney();local stillPrepared=Prepared();local finalReason=Context()
 if finalReason then return Status(finalReason)end
 if deposit>money then return Status("Not enough gold for the auction deposit.")end
 if not stillPrepared or S.prepared~=prepared or S.itemID~=selected or S.epoch~=epoch or S.pending or S.query or S.queue
  or Limit(selected).baitUnitCopper~=price or Options(selected).baitQuantity~=quantity or Options(selected).duration~=duration then return Status("The prepared item or auction state changed. Nothing was posted.")end
 S.valid=nil;local pending={kind="post",at=Now(),itemID=selected,quantity=quantity,dispatching=true};S.pending=pending;S.prepared=nil;S.status="Posting one bait stack ("..quantity..") for "..({12,24,48})[duration].." hours; awaiting the server."
 local success,_,observed=OwnedCall("post",PostAuction,totalPrice,totalPrice,duration,quantity,1,true)
 if S.pending==pending then
  pending.dispatching=false
  if not observed then pending.ambiguous=true;S.blocked=true;S.status="Posting ownership is uncertain. Check Auctions and reopen the auctioneer."end
 end
 if not success then S.pending=nil;S.blocked=true;return Status("Post call failed. Check Auctions and reopen the auctioneer.")end
 S.prepared=nil;Refresh();return true
end
function E.BaitScan(ids,options)
 if S.lookRunning then return Status("Pause Look before Bait Scan.")end
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
 S.afterPostScanIDs=checked;S.afterPostScanOptions={allPages=type(options)=="table"and options.allPages==true or false}
 local posted=E.PostBait()
 if not posted and not wasReady and not S.pending and Prepared()then posted=E.PostBait()end
 if not posted then
  S.afterPostScanIDs=nil;S.afterPostScanOptions=nil
  if S.prepared and not Prepared()then return Status("Waiting for the native selling slot. Click Bait + Scan again when ready.")end
 end
 return posted
end
function E.Snapshot()
 local item=S.item or(S.itemID and Info(S.itemID,S.requestedLink));if item then S.item=item end
 local r=S.results[S.itemID]or{};local limits=Limit(S.itemID);local options=Options(S.itemID);local session=Session(S.itemID);local reserved=Reserved(S.itemID)
 for _,row in ipairs(r.rows or{})do row.eligible=limits.maxUnitCopper>0 and row.unitPrice<=limits.maxUnitCopper and not CanBuy(row,S.itemID)end
 if r.summary then r.summary=Summarize(r.rows,r.summary.pages,r.summary.complete)end
 local totals={quantity=0,spentCopper=0};for _,entry in pairs(S.session)do totals.quantity=totals.quantity+entry.quantity;totals.spentCopper=totals.spentCopper+entry.spentCopper end
 return{itemID=S.itemID,itemLink=item and item.link,itemName=item and item.name,rows=r.rows or{},resultsByItem=S.results,status=S.status,summary=r.summary,
  open=S.open,scanning=S.query~=nil or S.queue~=nil,pending=S.pending~=nil,waitingForResponse=S.nativeRequest~=nil,responseAmbiguous=S.responseAmbiguous==true,cacheRows=S.cacheRows,cacheEvicted=S.cacheEvicted,page=r.page or 0,total=r.total or 0,
  prepared=Prepared()and true or false,preparing=S.prepared~=nil and not Prepared(),postReady=(not S.prepared or Prepared())and S.open and not S.blocked and not S.pending and not S.nativeRequest and not S.query and not S.queue and not S.lookRunning and limits.baitUnitCopper>0,
  buyReady=S.open and not S.blocked and not S.pending and not S.nativeRequest and not S.query and not S.queue and not S.lookRunning and S.valid==r.epoch and r.epoch==S.epoch and S.nativeItemID==S.itemID and r.at and Now()-r.at<=15 and true or false,
  maxUnitCopper=limits.maxUnitCopper,baitUnitCopper=limits.baitUnitCopper,currentPageItemID=S.nativeItemID,
  maxQuantity=options.maxQuantity,maxSpendCopper=options.maxSpendCopper,duration=options.duration,baitQuantity=options.baitQuantity,boughtQuantity=session.quantity,spentCopper=session.spentCopper,reservedQuantity=reserved.quantity,reservedCopper=reserved.spentCopper,sessionTotals=totals,
  lookRunning=S.lookRunning==true,lookPaused=S.lookPaused==true,nextCycleIn=S.nextCycleAt and math.max(0,S.nextCycleAt-Now())or nil,cycleCount=S.cycleCount,scanAll=S.scanAll==true,scanPartial=S.scanPartial==true,scannedPages=S.scannedPages,queueRemaining=S.queue and #S.queue or 0,reviewedIndex=S.reviewedIndex}
end
local frame=CreateFrame("Frame")
for _,event in ipairs({"AUCTION_HOUSE_SHOW","AUCTION_HOUSE_CLOSED","AUCTION_ITEM_LIST_UPDATE","NEW_AUCTION_UPDATE","CHAT_MSG_SYSTEM","UI_ERROR_MESSAGE","GET_ITEM_INFO_RECEIVED"})do frame:RegisterEvent(event)end
frame:SetScript("OnEvent",function(_,event,a,b)
 if event=="AUCTION_HOUSE_SHOW"then S.nativeRequest=nil;S.responseAmbiguous=nil;S.open=true;S.blocked=nil;S.pending=nil;S.status="Choose an item, enter prices, and scan."
 elseif event=="AUCTION_HOUSE_CLOSED"then S.nativeRequest=nil;S.responseAmbiguous=nil;S.open=false;S.query=nil;S.queue=nil;S.valid=nil;S.prepared=nil;S.afterPostScanIDs=nil;S.afterPostScanOptions=nil;S.lookRunning=false;S.lookPaused=S.look~=nil;S.nextCycleAt=nil;S.review=nil;S.reviewedIndex=nil;S.status="Visit an auctioneer."
 elseif event=="AUCTION_ITEM_LIST_UPDATE"then
  if S.query and S.nativeRequest==S.query and not S.query.discard and not S.responseAmbiguous then Results()
  elseif S.nativeRequest then DrainNativeRead()else S.valid=nil end
 elseif event=="CHAT_MSG_SYSTEM"and S.pending and not S.pending.ambiguous and not S.pending.dispatching then
  if(S.pending.kind=="buy"and a==ERR_AUCTION_BID_PLACED)or(S.pending.kind=="post"and a==ERR_AUCTION_STARTED)then
   local pending=S.pending;local kind=pending.kind;local scanIDs=kind=="post"and S.afterPostScanIDs or nil;local scanOptions=S.afterPostScanOptions
   if kind=="buy"then
    local entry=Session(pending.itemID);S.session[pending.itemID]={quantity=entry.quantity+pending.quantity,spentCopper=entry.spentCopper+pending.total*1.0}
    local held=Reserved(pending.itemID);S.reserved[pending.itemID]={quantity=math.max(0,held.quantity-pending.quantity),spentCopper=math.max(0,held.spentCopper-pending.total)}
   end
   S.pending=nil;S.valid=nil;S.afterPostScanIDs=nil;S.afterPostScanOptions=nil;S.status=kind=="buy"and "Purchase accepted. Scan again for another stack."or "One bait posted."
   if scanIDs then E.ScanList(scanIDs,scanOptions)end
  end
 elseif event=="UI_ERROR_MESSAGE"and S.pending then S.blocked=true;S.pending=nil;S.afterPostScanIDs=nil;S.afterPostScanOptions=nil;S.status=tostring(b or a or "Auction action failed.").." Check auctions/mail and reopen the auctioneer."
 end
 Refresh()
end)
local elapsed=0
frame:SetScript("OnUpdate",function(_,delta)
 elapsed=elapsed+delta;if elapsed<.25 then return end;elapsed=0
 if S.valid then local r=S.results[S.nativeItemID];if not r or Now()-r.at>15 then S.valid=nil;Refresh()end end
 if S.pending and Now()-S.pending.at>10 and not S.blocked then S.blocked=true;S.afterPostScanIDs=nil;S.afterPostScanOptions=nil;S.status="Unconfirmed auction response. Check auctions/mail and reopen the auctioneer.";Refresh()end
 if S.query and Now()-S.query.at>12 then Invalidate("Scan timed out. Waiting to discard its late response; reopen the auctioneer if it stalls.")end
 if S.queue and not S.query and not S.pending and Now()>=(S.queueAt or 0)then
  if #S.queue==0 then
   S.queue=nil
   if S.lookRunning and S.look then S.cycleCount=S.cycleCount+1;S.nextCycleAt=Now()+S.look.interval;Status("Look cycle "..S.cycleCount.." complete. Pause Look to review and buy.")
   else Status(S.scanPartial and "Scan reached the 200-page item limit. Results are partial; review each item."or "Checked-item scan complete. Select an item to review; recheck old pages before buying.")end
  elseif Now()>(S.queueDeadline or 0)then Invalidate("Stopped while waiting for the auction house. Resume Look or scan again.")
  elseif CanSendAuctionQuery()then
   local job=table.remove(S.queue,1);local id,page=type(job)=="table"and job.id or job,type(job)=="table"and job.page or 0
   local ok,why=QueryItem(id,page)
   if not ok then
    if why=="Waiting for item information. The scan will continue when it loads."and S.queue then table.insert(S.queue,1,job);S.queueAt=Now()+.5
    else Invalidate(S.status)end
   end
  end
 end
 if S.lookRunning and S.look and S.nextCycleAt and Now()>=S.nextCycleAt and not S.query and not S.queue and not S.pending then
  local look=S.look;S.nextCycleAt=nil;S.lookRunning=false
  local accepted=E.ScanList(look.ids,{allPages=look.allPages})
  if accepted then S.lookRunning=true;S.lookPaused=false else Invalidate(S.status)end
 end
end)
if hooksecurefunc and type(QueryAuctionItems)=="function"and type(SortAuctionSetSort)=="function"and type(PlaceAuctionBid)=="function"and type(PostAuction)=="function"and type(ClickAuctionSellItemButton)=="function"then
 hooksecurefunc("QueryAuctionItems",function(...)
  if not ConsumeOwned("query",...)then
   local overlap=S.nativeRequest~=nil
   if overlap then S.responseAmbiguous=true;S.nativeRequest.discard=true
   else S.nativeRequest={external=true,discard=true,at=Now()}end
   Invalidate(overlap and "Overlapping auction searches have untagged replies. Reopen the auctioneer before using WD."or "Another auction search took control. Waiting for its response before WD can scan.")
  end
 end)
 hooksecurefunc("SortAuctionSetSort",function(kind)if kind=="list"then Invalidate("Auction results were sorted. Scan again before buying.")end end)
 hooksecurefunc("PlaceAuctionBid",function(...)if not ConsumeOwned("bid",...)then
  if S.pending then S.pending.ambiguous=true;S.blocked=true end
  Invalidate(S.pending and "Overlapping auction actions make the response uncertain. Check auctions/mail and reopen the auctioneer."or "Another auction action changed the results.")
 end end)
 hooksecurefunc("PostAuction",function(...)if not ConsumeOwned("post",...)then S.prepared=nil;S.blocked=true;if S.pending then S.pending.ambiguous=true end;Invalidate("Another auction was posted. Check Auctions and reopen the auctioneer.")end end)
 hooksecurefunc("ClickAuctionSellItemButton",function(...)if not ConsumeOwned("slot",...)then S.prepared=nil end end)
 for _,name in ipairs({"SortAuctionClearSort","SortAuctionApplySort"})do
  if type(_G[name])=="function"then hooksecurefunc(name,function(kind)if kind=="list"then Invalidate("Auction results were sorted. Scan again before buying.")end end)end
 end
end
