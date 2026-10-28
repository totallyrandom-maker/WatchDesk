local _,NS=...
local UI={};NS.Window=UI
local frame,anchor,selected,watchPage,resultPage,selectedRow,selectedKey,scaling
local drafts,watchQuery,checkedOnly,sortMode,watchCategory={},"",false,"saved",nil
local viewMode,findCategory,findResults,findPage,reviewPage="offers",nil,{},1,1
local findQuery=""
local lastReviewToken
local reviewCache,reviewFingerprint,reviewObserved={},nil,0
local MAX_REVIEW=2000
watchPage,resultPage=1,1
local WIDTH,HEIGHT,WATCH_ROWS,RESULT_ROWS=1040,886,8,9
local CATEGORIES={{nil,"All categories"},{7,"Trade goods"},{0,"Consumables"},{5,"Reagents"},{9,"Recipes"},{2,"Weapons"},{4,"Armor"},{1,"Bags"},{3,"Gems"},{15,"Miscellaneous"},{12,"Quest items"}}
local SORTS={{"saved","Saved order"},{"name","Name A–Z"},{"id","Item ID"},{"checked","Checked first"}}
local function DB()local d=NS.GetSettings();d.watches=d.watches or{};d.window=d.window or{};return d end
local function Tell(text)if NS.Notify then NS.Notify(text)end end
local function Money(c)
 local n=math.max(0,math.floor((tonumber(c)or 0)+.5));local g=math.floor(n/10000);local silver=math.floor(n/100)%100;local copper=n%100
 if g>0 then return string.format("%dg %02ds %02dc",g,silver,copper)elseif silver>0 then return string.format("%ds %02dc",silver,copper)else return copper.."c"end
end
local function InputGold(c)return string.format("%.4f",(tonumber(c)or 0)/10000)end
local function ParseGold(text)
 text=tostring(text or""):match("^%s*(.-)%s*$"):lower():gsub("%s+","")
 if text:match("^%d*%.?%d+$")then
  local n=tonumber(text);local c=n and math.floor(n*10000+.5);return c and c<=2147483647 and c or nil
 end
 local amount,position=0,1
 for digits,unit,stop in text:gmatch("(%d*%.?%d+)([gsc])()")do
  if text:sub(position,stop-#digits-2)~=""then return end
  local n=tonumber(digits);if not n then return end
  amount=amount+n*(unit=="g"and 10000 or unit=="s"and 100 or 1);position=stop
 end
 if position==1 or position<=#text then return end
 amount=math.floor(amount+.5);return amount<=2147483647 and amount or nil
end
local function Whole(text,min,max)
 local s=tostring(text or""):match("^%s*(.-)%s*$");local n=tonumber(s)
 return s:match("^%d+$")and n and n>=min and n<=max and n==math.floor(n)and n or nil
end
local function Watch()return selected and DB().watches[selected]end
local function Engine()return NS.Engine end
local function Snapshot()local e=Engine();return e and e.Snapshot and e.Snapshot()or{}end
local function Busy(s)return s.scanning or s.pending or s.lookRunning or s.waitingForResponse or s.responseAmbiguous end
local function Run(fn,...)
 if type(fn)~="function"then Tell("Watch Desk is not ready.");return false end
 local ok,a,b=pcall(fn,...);if not ok then Tell("Action stopped: "..tostring(a));return false end
 if a==false and type(b)=="string"then Tell(b)end
 return a~=false
end
local function Label(parent,text,x,y,width,size)
 local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
 f:SetPoint("TOPLEFT",x,y);f:SetWidth(width);f:SetFont(STANDARD_TEXT_FONT or"Fonts\\FRIZQT__.TTF",size or 14,"")
 f:SetJustifyH("LEFT");f:SetJustifyV("TOP");f:SetText(text or"");return f
end
local function Box(f)
 f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
 f:SetBackdropColor(.025,.03,.04,1);f:SetBackdropBorderColor(.3,.35,.4,1)
end
local function Button(parent,text,x,y,w,fn)
 local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate");b:SetPoint("TOPLEFT",x,y);b:SetSize(w,25);b:SetText(text);b:SetScript("OnClick",fn);return b
end
local function Edit(parent,x,y,w)
 local e=CreateFrame("EditBox",nil,parent,"InputBoxTemplate");e:SetPoint("TOPLEFT",x,y);e:SetSize(w,25);e:SetAutoFocus(false)
 e:SetScript("OnEscapePressed",function(self)self:ClearFocus();if NS.CloseOneWindow then NS.CloseOneWindow()elseif frame then UI.Hide()end end);e:SetScript("OnEnterPressed",function(self)self:ClearFocus()end);return e
end
local function CheckBox(parent,text,x,y,fn)
 local c=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate");c:SetPoint("TOPLEFT",x,y);c:SetSize(24,24)
 c.caption=Label(c,text,26,-5,180,12);c:SetScript("OnClick",fn);return c
end
local function Dropdown(parent,label,x,y,width,choices,getValue,setValue)
 local button=Button(parent,label,x,y,width,function()end)
 local menu=CreateFrame("Frame",nil,parent,"BackdropTemplate");menu:SetPoint("TOPLEFT",x,y-28);menu:SetSize(math.max(width,216),#choices*24+12);Box(menu);menu:EnableMouse(true)
 if menu.SetFrameLevel and parent.GetFrameLevel then menu:SetFrameLevel(parent:GetFrameLevel()+20)end
 button.menu=menu;menu.options={};menu:Hide();parent.dropdowns=parent.dropdowns or{};parent.dropdowns[#parent.dropdowns+1]=menu
 local function Close()menu:Hide()end
 for i,choice in ipairs(choices)do
  local row=Button(menu,choice[2],6,-6-(i-1)*24,math.max(width,216)-12,function()setValue(choice[1]);Close();UI.Refresh()end)
  row.value=choice[1];row.labelText=choice[2];menu.options[i]=row
 end
 if NS.RegisterWindow then NS.RegisterWindow(menu,{close=Close})end
 button:SetScript("OnClick",function()
  if menu:IsShown()then Close();return end
  for _,other in ipairs(parent.dropdowns)do other:Hide()end
  menu:Show();if NS.FocusWindow then NS.FocusWindow(menu)end
 end)
 button:SetScript("OnHide",Close)
 menu:SetScript("OnShow",function()
  local value=getValue();for _,row in ipairs(menu.options)do row:SetText((row.value==value and "✓ "or"  ")..row.labelText)end
  if NS.RegisterWindow then NS.RegisterWindow(menu,{close=Close})end
 end)
 return button
end
local function SetEnabled(f,on)if f then f:SetEnabled(on and true or false)end end
local function RowKey(r)return r and table.concat({tostring(r.link),tostring(r.owner),tostring(r.count),tostring(r.buyout),tostring(r.index),tostring(r.page or 0)},"|")end
local function ItemInfo(id)
 local data=NS.Items and NS.Items.Get and NS.Items.Get(id)or{}
 local name,link,quality,_,_,_,_,_,_,icon,classID
 if GetItemInfo then name,link,quality,_,_,_,_,_,_,icon,_,classID=GetItemInfo(id)end
 return {itemID=id,name=name or data.name or("Item #"..id),link=link or data.link,icon=icon or data.icon,quality=quality or data.quality,classID=classID or data.classID}
end
local function Age(at)
 if not at or not GetTime then return "age ?"end
 local n=math.max(0,math.floor(GetTime()-at));return n<60 and(n.."s ago")or(math.floor(n/60).."m ago")
end
local function HideTip(self)if GameTooltip and(not GameTooltip.IsOwned or GameTooltip:IsOwned(self))then GameTooltip:Hide()end end
local function ItemTip(self,id,extra,exactLink)
 if not GameTooltip or not id then return end
 local data=ItemInfo(id);GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
 local link=type(exactLink)=="string"and tonumber(exactLink:match("item:(%d+)"))==tonumber(id)and exactLink or data.link or("item:"..id)
 local ok=false;if GameTooltip.SetHyperlink then ok=pcall(GameTooltip.SetHyperlink,GameTooltip,link)end
 if not ok then GameTooltip:ClearLines();GameTooltip:AddLine(data.name,1,1,1);GameTooltip:AddLine("Item ID: "..id,.7,.8,.9)end
 if extra then GameTooltip:AddLine(extra,.8,.9,1,true)end;GameTooltip:Show()
end
local function SelectedTipData(snapshot)
 local w=Watch();local s=snapshot or Snapshot();local id=w and w.itemID or s.itemID
 local link=id and s.itemID==id and s.itemLink or nil
 return id,link,id and(tostring(id)..":"..tostring(link or""))or nil
end
local function SelectedItemTip(self,snapshot)
 local id,link,key=SelectedTipData(snapshot);self.wdItemTipKey=key
 if not id then HideTip(self);return false end
 ItemTip(self,id,nil,link);return true
end
local function RefreshSelectedItemTip(snapshot)
 if not frame or not frame.drop or not GameTooltip then return end
 local owned=GameTooltip.GetOwner and GameTooltip:GetOwner()==frame.drop or GameTooltip.IsOwned and GameTooltip:IsOwned(frame.drop)
 if not owned or(GameTooltip.IsShown and not GameTooltip:IsShown())then return end
 local _,_,key=SelectedTipData(snapshot)
 if frame.drop.wdItemTipKey~=key then SelectedItemTip(frame.drop,snapshot)end
end
local function SimpleTip(control,text)
 control:SetScript("OnEnter",function(self)if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:ClearLines();GameTooltip:AddLine(text,.8,.9,1,true);GameTooltip:Show()end end)
 control:SetScript("OnLeave",HideTip)
end
local function Icon(parent,x,y,size)
 if not parent.CreateTexture then return end
 local t=parent:CreateTexture(nil,"ARTWORK");t:SetPoint("TOPLEFT",x,y);t:SetSize(size,size);return t
end
local function CategoryText(id)for _,v in ipairs(CATEGORIES)do if v[1]==id then return v[2]end end;return "All types"end
local function NextCategory(id)for i,v in ipairs(CATEGORIES)do if v[1]==id then return CATEGORIES[i%#CATEGORIES+1][1]end end end
local function FilteredWatches()
 local out={};local q=watchQuery:lower();local queryID=tonumber(q:match("item:(%d+)")or q)
 for i,w in ipairs(DB().watches)do
  local d=ItemInfo(w.itemID)
  if(not checkedOnly or w.checked)and(not watchCategory or d.classID==watchCategory)
   and(q==""or queryID==w.itemID or d.name:lower():find(q,1,true)or tostring(w.itemID):find(q,1,true))then out[#out+1]={index=i,watch=w,info=d}end
 end
 if sortMode~="saved"then table.sort(out,function(a,b)
  if sortMode=="id"then return a.watch.itemID<b.watch.itemID end
  if sortMode=="checked"and not not a.watch.checked~=not not b.watch.checked then return a.watch.checked and true or false end
  local an,bn=a.info.name:lower(),b.info.name:lower();return an==bn and a.watch.itemID<b.watch.itemID or an<bn
 end)end
 return out
end
local function CheckedIDs()local ids={};for _,w in ipairs(DB().watches)do if w.checked then ids[#ids+1]=w.itemID end end;return ids end
local function Place(x,y)
 local scale=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
 local width=frame:GetWidth()*scale
 local sw,sh=UIParent:GetWidth(),UIParent:GetHeight()
 x=math.max(64-width,math.min(sw-64,tonumber(x)or(sw-width)/2))
 y=math.max(40,math.min(sh+12,tonumber(y)or(sh+frame:GetHeight()*scale)/2))
 anchor:ClearAllPoints();anchor:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x,y)
 frame:ClearAllPoints();frame:SetPoint("TOPLEFT",anchor,"TOPLEFT",0,0)
 return x,y
end
local function SavePosition()
 local ratio=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
 local x,y=Place(frame:GetLeft()*ratio,frame:GetTop()*ratio)
 local d=DB().window;d.x,d.y,d.scale=x,y,frame:GetScale()
end
local function FinishMove()
 if not frame then return end
 frame:StopMovingOrSizing();scaling=nil;frame:SetScript("OnUpdate",nil);SavePosition()
end
local function StartMove()
 if InCombatLockdown and InCombatLockdown()then return end
 if IsShiftKeyDown and IsShiftKeyDown()then
  local x,y=GetCursorPosition();scaling={x=x,y=y,scale=frame:GetScale()}
  frame:SetScript("OnUpdate",function()
   if not scaling then return end
   if IsMouseButtonDown and not IsMouseButtonDown("LeftButton")then FinishMove();return end
   local cx,cy=GetCursorPosition();frame:SetScale(math.max(.65,math.min(1.65,scaling.scale+(cx-scaling.x-cy+scaling.y)/700)))
   local d=DB().window;Place(d.x,d.y)
  end)
 else frame:StartMoving()end
end
local EDIT_KEYS={"maxBuy","bait","quantity","spending","baitQuantity"}
local function CaptureDraft()
 local w=Watch();if not w or not frame then return end
 local d={duration=frame.durationValue or w.duration or 1};for _,key in ipairs(EDIT_KEYS)do if frame[key]then d[key]=frame[key]:GetText()end end;drafts[w.itemID]=d
end
local function LoadDraft()
 local w=Watch();if not w then return end
 local d=drafts[w.itemID]or{maxBuy=InputGold(w.maxUnitCopper),bait=InputGold(w.baitUnitCopper),quantity=tostring(w.maxQuantity or 0),spending=InputGold(w.maxSpendCopper),baitQuantity=tostring(w.baitQuantity or 1),duration=w.duration or 1}
 for _,key in ipairs(EDIT_KEYS)do if frame[key]then frame[key]:SetText(d[key]or"0")end end
 frame.durationValue=d.duration or 1
end
local function SelectedEngine()
 local w=Watch();local e=Engine();if not w or not e then return false end
 if not Run(e.SetItem,w.itemID)or not Run(e.SetLimits,w.maxUnitCopper or 0,w.baitUnitCopper or 0)then return false end
 if e.SetWatchOptions then return Run(e.SetWatchOptions,{maxQuantity=w.maxQuantity or 0,maxSpendCopper=w.maxSpendCopper or 0,duration=w.duration or 1,baitQuantity=w.baitQuantity or 1})end
 return true
end
local function SavePrices()
 local w=Watch();if not w then Tell("Select an item first.");return false end
 local maxBuy,bait=ParseGold(frame.maxBuy:GetText()),ParseGold(frame.bait:GetText())
 local quantity,spend,baitQuantity=Whole(frame.quantity:GetText(),0,1000000),ParseGold(frame.spending:GetText()),Whole(frame.baitQuantity:GetText(),1,1000)
 if not maxBuy or not bait or not quantity or not spend or not baitQuantity then Tell("Enter valid prices and whole quantities. Prices: 2.50 gold or 1g20s. Zero turns a limit off.");return false end
 local options={maxQuantity=quantity,maxSpendCopper=spend,baitQuantity=baitQuantity,duration=frame.durationValue or 1}
 local e=Engine();if not e or not Run(e.SetItem,w.itemID)or not Run(e.SetLimits,maxBuy,bait)then return false end
 if e.SetWatchOptions and not Run(e.SetWatchOptions,options)then return false end
 w.maxUnitCopper,w.baitUnitCopper=maxBuy,bait;for k,v in pairs(options)do w[k]=v end;drafts[w.itemID]=nil
 return true
end
local function SelectWatch(index)
 if Busy(Snapshot())then Tell("Stop the scan or finish the pending action first.");return false end
 CaptureDraft();selected=index;selectedRow,selectedKey,resultPage=nil,nil,1;lastReviewToken=nil
 local w=Watch();if w then LoadDraft();SelectedEngine()end
 UI.Refresh();return w~=nil
end
local function FindItems(query)
 findQuery=tostring(query or findQuery or"");query=findQuery
 if frame and frame.findSearch and frame.findSearch:GetText()~=findQuery then frame.findSearch:SetText(findQuery)end
 findResults={};findPage=1
 if tostring(query or""):match("^%s*$")and not findCategory then viewMode="items";UI.Refresh();return findResults end
 if NS.Items and NS.Items.Search then
  local ok,result=pcall(NS.Items.Search,query,100,findCategory);if ok and type(result)=="table"then findResults=result end
 else
  local q=tostring(query or""):lower();for _,v in ipairs(FilteredWatches())do if v.info.name:lower():find(q,1,true)or tostring(v.watch.itemID)==q then findResults[#findResults+1]=v.info end end
 end
 viewMode="items";UI.Refresh();return findResults
end
local function RevealWatch(id)
 watchQuery="";checkedOnly=false;watchCategory=nil;if frame.filter then frame.filter:SetText("")end
 for position,v in ipairs(FilteredWatches())do if v.watch.itemID==id then watchPage=math.ceil(position/WATCH_ROWS);break end end
end
local function AddItem(value)
 if Busy(Snapshot())then Tell("Stop the scan or finish the pending action first.");return false end
 local id=tonumber(value)or tonumber(tostring(value or""):match("item:(%d+)"))
 if not id and type(value)=="string"and value:match("%S")then
  local matches=FindItems(value);local exact
  for _,v in ipairs(matches)do if v.name and v.name:lower()==value:lower()then exact=v.itemID;break end end
  id=exact or(#matches==1 and matches[1].itemID)
  if not id then Tell(#matches>0 and"Choose an item from Find Items to add it."or"No matching item found. Try its ID or Shift-click its link.");return false end
 end
 if not id or id~=id or id<1 or id>10000000 or id~=math.floor(id)then Tell("Enter an item ID, item name, or paste an item link.");return false end
 for i,w in ipairs(DB().watches)do if w.itemID==id then RevealWatch(id);SelectWatch(i);viewMode="offers";UI.Refresh();return true end end
 local items=DB().watches;if #items>=100 then Tell("The checklist holds up to 100 items.");return false end
 items[#items+1]={itemID=id,checked=true,maxUnitCopper=0,baitUnitCopper=0,maxQuantity=0,maxSpendCopper=0,duration=1,baitQuantity=1}
 RevealWatch(id);SelectWatch(#items);frame.item:SetText("");viewMode="offers";UI.Refresh();return true
end
-- Route Shift-links only to the focused item field. An open Watch Desk never
-- takes chat/mail links or another addon's item clicks; keep their return path.
local itemLinkHooks={}
local function ShiftItemLink()
 return IsShiftKeyDown and IsShiftKeyDown()
  and not(IsAltKeyDown and IsAltKeyDown())and not(IsControlKeyDown and IsControlKeyDown())
end
local function ReceiveItemLink(link)
 if type(link)~="string"or not(link:find("|Hitem:",1,true)or link:match("^item:%d+"))then return false end
 if not ShiftItemLink()or not frame or not frame:IsShown()or not frame.item:HasFocus()
  or(InCombatLockdown and InCombatLockdown())or Busy(Snapshot())then return false end
 if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()~=frame.item then return false end
 return AddItem(link)
end
local function InstallItemLinkHooks()
 local function Wrap(object,key)
  if not object or type(object[key])~="function"or object[key]==itemLinkHooks[key]then return end
  local previous=object[key]
  local wrapper=function(link,...)
   if ReceiveItemLink(link)then return true end
   return previous(link,...)
  end
  object[key]=wrapper;itemLinkHooks[key]=wrapper
 end
 Wrap(_G,"ChatEdit_InsertLink")
 Wrap(ChatFrameUtil,"InsertLink")
 Wrap(_G,"HandleModifiedItemClick")
 if type(SetItemRef)=="function"and SetItemRef~=itemLinkHooks.SetItemRef then
  local previous=SetItemRef
  local wrapper=function(link,text,button,...)
   if not button or button=="LeftButton"then
    local id=type(link)=="string"and link:match("^item:(%d+)")
    local textID=type(text)=="string"and text:match("item:(%d+)")
    if ReceiveItemLink(id and id==textID and text or link)then return true end
   end
   return previous(link,text,button,...)
  end
  SetItemRef=wrapper;itemLinkHooks.SetItemRef=wrapper
 end
end
local function DropItem()
 local kind,id,link=GetCursorInfo()
 if kind=="item"and AddItem(link or id)then ClearCursor();return true end
 return false
end
local function SelectedScan(page)
 if not SavePrices()then return end
 selectedRow,selectedKey=nil,nil;viewMode="offers";Run(Engine().Scan,page or 0);UI.Refresh()
end
local function ScanChecked(repeatMode)
 local e=Engine();if not e then return end
 if selected and not SavePrices()then return end
 local ids=CheckedIDs();if #ids==0 then Tell("Check at least one item.");return end
 local interval=Whole(frame.interval:GetText(),5,300);if repeatMode and not interval then Tell("Repeat delay must be a whole number from 5 to 300 seconds.");return end
 selectedRow,selectedKey=nil,nil;viewMode="offers"
 if repeatMode then Run(e.StartLook,ids,{allPages=frame.allPages:GetChecked()and true or false,interval=interval})
 else Run(e.ScanList,ids,{allPages=frame.allPages:GetChecked()and true or false})end
 UI.Refresh()
end
local function ReviewEntries(s)
 local sources,signature,total={},{},0
 for id,result in pairs(s.resultsByItem or{})do
  local count=#(result.rows or{});total=total+count
  sources[#sources+1]={itemID=id,result=result}
  signature[#signature+1]=table.concat({id,tostring(result.at),count,tostring(result.rows)},":")
 end
 table.sort(signature);local fingerprint=table.concat(signature,"|")
 if fingerprint==reviewFingerprint then return reviewCache,reviewObserved end
 table.sort(sources,function(a,b)if(a.result.at or 0)~=(b.result.at or 0)then return(a.result.at or 0)>(b.result.at or 0)end;return a.itemID<b.itemID end)
 local entries={}
 for _,source in ipairs(sources)do
  for index,row in ipairs(source.result.rows or{})do
   if #entries>=MAX_REVIEW then break end
   entries[#entries+1]={itemID=source.itemID,index=index,row=row,at=row.observedAt or source.result.at}
  end
  if #entries>=MAX_REVIEW then break end
 end
 table.sort(entries,function(a,b)if(a.at or 0)~=(b.at or 0)then return(a.at or 0)>(b.at or 0)end;if a.itemID~=b.itemID then return a.itemID<b.itemID end;return a.index<b.index end)
 reviewCache,reviewFingerprint,reviewObserved=entries,fingerprint,total
 return entries,total
end
local function Recheck(index,id)
 if Busy(Snapshot())then return end
 if id then
  local found;for i,w in ipairs(DB().watches)do if w.itemID==id then found=i;break end end
  if not found then Tell("That item is no longer in saved watches. Add it again before rechecking.");return false end
  if not SelectWatch(found)then return false end
 end
 if not SavePrices()then return end
 viewMode="offers";selectedRow,selectedKey=nil,nil;lastReviewToken=nil
 Run(Engine()and Engine().RecheckSelected,index);UI.Refresh()
end
local function StockLine(id)
 if not id then return "Select an item. Your checklist starts empty; choose every item and price yourself."end
 if NS.Items and NS.Items.Stock then
  local ok,s=pcall(NS.Items.Stock,id);if ok and type(s)=="table"then
   local text="Carried bags: "..(s.available==false and"not observed"or tostring(s.bags or"?"))
   if s.bank~=nil then text=text.."  | Bank: "..s.bank end
   if s.mail~=nil then text=text.."  | Mail: "..s.mail end
   if s.auctions~=nil then text=text.."  | AH: "..s.auctions end
   if s.total~=nil then text=text.."  | Tracked total: "..s.total end
   return text
  end
 end
 if GetItemCount then local ok,count=pcall(GetItemCount,id,false);if ok then return "Bags: "..tostring(count).."  | Other storage is unknown."end end
 return "Your stock: not observed. Item counts never change your saved buy price."
end
local function AuctionatorState(snapshot)
 local adapter=NS.Auctionator
 if type(adapter)~="table"or type(adapter.Available)~="function"or type(adapter.CanSearch)~="function"or type(adapter.Search)~="function"then return false,false,"Auctionator Shopping is not available."end
 local ok,available=pcall(adapter.Available)
 if not ok or not available then return false,false,"Auctionator Shopping is not available."end
 local s=snapshot or Snapshot()
 if not s.open then return true,false,"Visit an auctioneer first.",adapter end
 if s.preparing or s.prepared then return true,false,"Finish or release the prepared bait before opening another search.",adapter end
 if s.responseAmbiguous then return true,false,"Reopen the auctioneer before opening Auctionator.",adapter end
 if s.waitingForResponse then return true,false,"Wait for the earlier auction response before opening Auctionator.",adapter end
 if s.lookRunning then return true,false,"Pause or Stop Watch Desk scanning before opening Auctionator.",adapter end
 if Busy(s)then return true,false,"Wait for the current auction response or stop the scan first.",adapter end
 local ready,canSearch,reason=pcall(adapter.CanSearch)
 if not ready then return true,false,"Auctionator Shopping is not ready.",adapter end
 return true,canSearch==true,reason,adapter
end
local function HandoffAuctionator(checked)
 CaptureDraft()
 local s=Snapshot();local _,ready,reason,adapter=AuctionatorState(s)
 if not ready then Tell(reason or"Auctionator Shopping is not ready.");return false end
 local value
 if checked then
  value=CheckedIDs();if #value==0 then Tell("Check at least one item first.");return false end
 else
  local w=Watch();if not w then Tell("Select a watch first.");return false end
  value=w.itemID
  if s.itemID==w.itemID and type(s.itemLink)=="string"and tonumber(s.itemLink:match("item:(%d+)"))==w.itemID then value=s.itemLink end
 end
 local ok,accepted,message=pcall(adapter.Search,value)
 if not ok then Tell("Auctionator could not open the search. Check its status before trying again.");return false end
 if accepted~=true then Tell(message or"Auctionator Shopping is not ready.");UI.Refresh();return false end
 Tell((type(message)=="string"and message or"Opened Auctionator Shopping.").." Use /watchdesk to return.")
 UI.Hide();return true
end
local function AuctionatorHandoffTip(self)
 if not GameTooltip then return end
 GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:ClearLines()
 GameTooltip:AddLine("Auctionator Shopping",1,1,1)
 GameTooltip:AddLine("Open the native Shopping search for "..(self.wdAuctionatorScope or"these items")..". Watch Desk yields its own searches. Watch Desk closes after a successful handoff; reopen it with /watchdesk. This never buys or posts, and it does not queue an automatic search for later.",.8,.9,1,true)
 local _,ready,reason=AuctionatorState(Snapshot())
 reason=not ready and reason or self.wdAuctionatorReason
 if reason then GameTooltip:AddLine(reason,1,.8,.4,true)end
 GameTooltip:Show()
end
local Build={HandoffAuctionator=HandoffAuctionator,AuctionatorHandoffTip=AuctionatorHandoffTip,AddItem=AddItem,Age=Age,Box=Box,Busy=Busy,Button=Button,CaptureDraft=CaptureDraft,CheckBox=CheckBox,CheckedIDs=CheckedIDs,DB=DB,DropItem=DropItem,Dropdown=Dropdown,Edit=Edit,Engine=Engine,FilteredWatches=FilteredWatches,FindItems=FindItems,FinishMove=FinishMove,HideTip=HideTip,Icon=Icon,InstallItemLinkHooks=InstallItemLinkHooks,ItemTip=ItemTip,Label=Label,Money=Money,Place=Place,Recheck=Recheck,Run=Run,SavePosition=SavePosition,SavePrices=SavePrices,ScanChecked=ScanChecked,SelectWatch=SelectWatch,SelectedItemTip=SelectedItemTip,SelectedScan=SelectedScan,SimpleTip=SimpleTip,Snapshot=Snapshot,StartMove=StartMove,Tell=Tell,Watch=Watch}
local function Create()
 if frame then return end
 frame=CreateFrame("Frame","WatchDeskStandaloneWindow",UIParent,"BackdropTemplate")
 UI.frame=frame;frame:Hide();frame:SetSize(WIDTH,HEIGHT);frame:SetFrameStrata("DIALOG");Build.Box(frame)
 frame:SetMovable(true);frame:EnableMouse(true);frame:SetClampedToScreen(false);frame:RegisterForDrag("LeftButton")
 frame:SetScript("OnDragStart",Build.StartMove);frame:SetScript("OnDragStop",Build.FinishMove)
 frame:SetScript("OnHide",function()
  if scaling then Build.FinishMove()else frame:StopMovingOrSizing()end
  for _,key in ipairs({"item","filter","findSearch","maxBuy","bait","quantity","spending","baitQuantity","interval"})do if frame[key]then frame[key]:ClearFocus()end end
  for _,menu in ipairs(frame.dropdowns or{})do menu:Hide()end
  Build.CaptureDraft();local e=Build.Engine();if e and e.Stop then e.Stop()end
 end)
 anchor=CreateFrame("Frame",nil,UIParent);anchor:SetSize(1,1)
 local d=Build.DB().window;local fit=math.min(1,(UIParent:GetWidth()-48)/WIDTH,(UIParent:GetHeight()-48)/HEIGHT)
 frame:SetScale(math.max(.65,math.min(1.65,tonumber(d.scale)or fit)));Build.Place(d.x,d.y);Build.SavePosition()
 local title=CreateFrame("Frame",nil,frame);title:SetPoint("TOPLEFT",0,0);title:SetPoint("TOPRIGHT",0,0);title:SetHeight(34)
 title:EnableMouse(true);title:RegisterForDrag("LeftButton");title:SetScript("OnDragStart",Build.StartMove);title:SetScript("OnDragStop",Build.FinishMove)
 Build.Label(title,"Watch Desk",16,-9,950,18)
 local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton");close:SetPoint("TOPRIGHT",-2,-2);close:SetScript("OnClick",function()UI.Hide()end);frame.close=close
 Build.Label(frame,"Your watches, your prices. Scan and review offers; every purchase and bait post needs your click.",18,-42,1004,13)
 Build.Label(frame,"Item ID / link / name",62,-65,470,12)
 frame.drop=CreateFrame("Button",nil,frame,"BackdropTemplate");frame.drop:SetPoint("TOPLEFT",18,-82);frame.drop:SetSize(34,34);Build.Box(frame.drop)
 frame.itemIcon=Build.Icon(frame.drop,2,-2,30);frame.drop:SetScript("OnReceiveDrag",Build.DropItem)
 frame.drop:SetScript("OnClick",function()if not Build.DropItem()and frame.item.SetFocus then frame.item:SetFocus()end end)
 frame.drop:SetScript("OnEnter",function(self)Build.SelectedItemTip(self)end);frame.drop:SetScript("OnLeave",Build.HideTip)
 frame.item=Build.Edit(frame,66,-85,264);frame.item:SetMaxLetters(512)
 frame.item:SetScript("OnEnterPressed",function(self)Build.AddItem(self:GetText());self:ClearFocus()end)
 frame.item:SetScript("OnReceiveDrag",Build.DropItem)
 frame.item:SetScript("OnEditFocusGained",function()Build.InstallItemLinkHooks()end)
 frame.item:SetScript("OnMouseDown",function(_,button)if button=="LeftButton"and GetCursorInfo()then Build.DropItem()end end)
 frame.add=Build.Button(frame,"Add",342,-85,70,function()Build.AddItem(frame.item:GetText())end)
 frame.find=Build.Button(frame,"Find item",420,-85,90,function()Build.FindItems(frame.item:GetText())end)
 frame.remove=Build.Button(frame,"Remove",518,-85,82,function()
  if Build.Busy(Build.Snapshot())then return end
  if selected then local id=Build.Watch().itemID;table.remove(Build.DB().watches,selected);drafts[id]=nil;selected=nil;selectedRow,selectedKey=nil,nil;UI.Refresh()end
 end)
 Build.Label(frame,"Max buy / item",618,-65,166,12);frame.maxBuy=Build.Edit(frame,622,-85,158)
 Build.Label(frame,"Bait list / item",796,-65,150,12);frame.bait=Build.Edit(frame,800,-85,134)
 frame.apply=Build.Button(frame,"Save",948,-85,76,function()Build.SavePrices();UI.Refresh()end)
 Build.Label(frame,"Units / session (0 = off)",18,-124,190,12);frame.quantity=Build.Edit(frame,22,-145,126)
 Build.Label(frame,"Gold / session (0 = off)",166,-124,190,12);frame.spending=Build.Edit(frame,170,-145,154)
 Build.Label(frame,"Bait stack",344,-124,100,12);frame.baitQuantity=Build.Edit(frame,348,-145,84)
 Build.Label(frame,"Post duration",452,-124,140,12);frame.durationValue=1
 frame.duration=Build.Button(frame,"12 hours",452,-145,126,function()Build.CaptureDraft();frame.durationValue=(frame.durationValue or 1)%3+1;UI.Refresh()end)
 Build.Label(frame,"Repeat delay (seconds)",618,-124,190,12);frame.interval=Build.Edit(frame,622,-145,106);frame.interval:SetText("10")
 frame.allPages=Build.CheckBox(frame,"All AH pages",750,-145,function()end);frame.allPages:SetChecked(false)
 Build.SimpleTip(frame.maxBuy,"Maximum price for one item. Enter 2.50 for gold, or 1g20s / 75s / 25c. Zero disables buying.")
 Build.SimpleTip(frame.bait,"Your exact list price for each bait item. No suggested or preloaded price. Zero disables bait posting.")
 Build.SimpleTip(frame.quantity,"Maximum items bought during this login for this watch. Whole stacks must fit. Zero leaves the cap off.")
 Build.SimpleTip(frame.spending,"Maximum gold spent during this login for this watch. Stop and Start keep this total; Reset session clears it.")
 Build.SimpleTip(frame.baitQuantity,"Number of items in your explicitly posted bait stack. The engine validates stock, stack size, price and deposit before posting.")
 frame.scanChecked=Build.Button(frame,"Scan checked",18,-187,126,function()Build.ScanChecked(false)end)
 frame.scanSelected=Build.Button(frame,"Scan selected",152,-187,126,function()Build.SelectedScan(0)end)
 frame.scanAll=Build.Button(frame,"All pages: selected",286,-187,154,function()if Build.SavePrices()then viewMode="offers";Build.Run(Build.Engine()and Build.Engine().ScanAll);UI.Refresh()end end)
 frame.look=Build.Button(frame,"Repeat scan",448,-187,126,function()Build.ScanChecked(true)end)
 frame.pause=Build.Button(frame,"Pause",582,-187,90,function()local s=Build.Snapshot();Build.Run(Build.Engine()and(s.lookPaused and Build.Engine().ResumeLook or Build.Engine().PauseLook));UI.Refresh()end)
 frame.stop=Build.Button(frame,"Stop",680,-187,70,function()Build.Run(Build.Engine()and Build.Engine().Stop);selectedRow,selectedKey=nil,nil;UI.Refresh()end)
 frame.auctionatorSelected=Build.Button(frame,"Auctionator selected",758,-187,128,function()Build.HandoffAuctionator(false)end)
 frame.auctionatorChecked=Build.Button(frame,"Auctionator checked",894,-187,130,function()Build.HandoffAuctionator(true)end)
 frame.auctionatorSelected.wdAuctionatorScope="the selected item";frame.auctionatorChecked.wdAuctionatorScope="all checked watches"
 for _,control in ipairs({frame.auctionatorSelected,frame.auctionatorChecked})do control:SetScript("OnEnter",Build.AuctionatorHandoffTip);control:SetScript("OnLeave",Build.HideTip)end
 Build.SimpleTip(frame.look,"Repeat read-only scans of checked items after the entered delay. It never buys, posts, or replaces bait. Stop or close Watch Desk to end it.")
 Build.Label(frame,"Saved watches",18,-232,190,15)
 frame.filter=Build.Edit(frame,22,-256,176);frame.filter:SetScript("OnTextChanged",function(self)watchQuery=self:GetText();watchPage=1;UI.Refresh()end)
 frame.checkedOnly=Build.CheckBox(frame,"Checked only",208,-256,function(self)checkedOnly=self:GetChecked()and true or false;watchPage=1;UI.Refresh()end)
 frame.watchCategory=Build.Dropdown(frame,"All categories",18,-287,174,CATEGORIES,function()return watchCategory end,function(value)watchCategory=value;watchPage=1 end)
 frame.sort=Build.Dropdown(frame,"Saved order",200,-287,118,SORTS,function()return sortMode end,function(value)sortMode=value;watchPage=1 end)
 frame.watchRows={}
 for i=1,WATCH_ROWS do
  local r=CreateFrame("Button",nil,frame,"BackdropTemplate");r:SetPoint("TOPLEFT",18,-325-(i-1)*35);r:SetSize(300,32);Build.Box(r)
  r.check=CreateFrame("CheckButton",nil,r,"UICheckButtonTemplate");r.check:SetSize(24,24);r.check:SetPoint("LEFT",1,0)
  r.check:SetScript("OnClick",function(self)if not Build.Busy(Build.Snapshot())and r.watchIndex then Build.DB().watches[r.watchIndex].checked=self:GetChecked()and true or false end;UI.Refresh()end)
  r.icon=Build.Icon(r,29,-4,24);r.label=Build.Label(r,"",61,-3,232,12);r.label:SetHeight(29);r.label:SetWordWrap(false)
  r:SetScript("OnClick",function()if r.watchIndex then Build.SelectWatch(r.watchIndex);viewMode="offers";UI.Refresh()end end)
  r:SetScript("OnEnter",function(self)local w=self.watchIndex and Build.DB().watches[self.watchIndex];if w then Build.ItemTip(self,w.itemID,"Max buy: "..Build.Money(w.maxUnitCopper).." / item\nBait: "..Build.Money(w.baitUnitCopper).." / item\nClick to edit or review its scanned offers.")end end);r:SetScript("OnLeave",Build.HideTip)
  frame.watchRows[i]=r
 end
 frame.watchPrev=Build.Button(frame,"<",18,-615,34,function()watchPage=math.max(1,watchPage-1);UI.Refresh()end)
 frame.watchPages=Build.Label(frame,"",62,-622,210,12)
 frame.watchNext=Build.Button(frame,">",284,-615,34,function()watchPage=watchPage+1;UI.Refresh()end)
 frame.all=Build.Button(frame,"Check shown",18,-651,146,function()if Build.Busy(Build.Snapshot())then return end;for _,v in ipairs(Build.FilteredWatches())do v.watch.checked=true end;UI.Refresh()end)
 frame.none=Build.Button(frame,"Uncheck shown",172,-651,146,function()if Build.Busy(Build.Snapshot())then return end;for _,v in ipairs(Build.FilteredWatches())do v.watch.checked=false end;UI.Refresh()end)
 Build.SimpleTip(frame.all,"Checks every saved watch matching the current search and item type, across all list pages.")
 Build.SimpleTip(frame.none,"Unchecks every saved watch matching the current search and item type, across all list pages.")
 frame.offersTab=Build.Button(frame,"Live / scanned offers",344,-232,166,function()viewMode="offers";UI.Refresh()end)
 frame.findTab=Build.Button(frame,"Find items",518,-232,116,function()Build.FindItems(frame.findSearch and frame.findSearch:GetText()or findQuery)end)
 frame.review=Build.Button(frame,"Review scans",642,-232,146,function()viewMode="review";UI.Refresh()end)
 frame.findCategory=Build.Dropdown(frame,"All categories",796,-232,228,CATEGORIES,function()return findCategory end,function(value)findCategory=value;Build.FindItems(frame.findSearch:GetText())end)
 frame.current=Build.Label(frame,"Select an item",344,-269,676,15);frame.current:SetHeight(19);frame.current:SetWordWrap(false)
 frame.stock=Build.Label(frame,"",344,-294,676,12);frame.stock:SetHeight(18);frame.stock:SetWordWrap(false)
 frame.findSearchLabel=Build.Label(frame,"Search item names or IDs",344,-292,676,12)
 frame.findSearch=Build.Edit(frame,350,-313,542);frame.findSearch:SetMaxLetters(512);frame.findSearch:SetText(findQuery)
 frame.findSearch:SetScript("OnEnterPressed",function(self)Build.FindItems(self:GetText());self:ClearFocus()end)
 frame.findSearch:SetScript("OnHide",function(self)self:ClearFocus()end)
 frame.findSearchButton=Build.Button(frame,"Search",908,-312,116,function()Build.FindItems(frame.findSearch:GetText())end)
 frame.columns={Build.Label(frame,"Qty",348,-324,50,12),Build.Label(frame,"Each",404,-324,110,12),Build.Label(frame,"Stack total",522,-324,112,12),Build.Label(frame,"Seller",640,-324,220,12),Build.Label(frame,"Observed",886,-324,76,12),Build.Label(frame,"Page",964,-324,58,12)}
 frame.resultRows={};frame.findRows={};frame.reviewRows={}
 for i=1,RESULT_ROWS do
  local y=-346-(i-1)*29
  local r=CreateFrame("Button",nil,frame,"BackdropTemplate");r:SetPoint("TOPLEFT",344,y);r:SetSize(680,27);Build.Box(r)
  r.qty=Build.Label(r,"",4,-7,50,12);r.unit=Build.Label(r,"",60,-7,110,12);r.total=Build.Label(r,"",178,-7,112,12);r.owner=Build.Label(r,"",296,-7,240,12);r.owner:SetWordWrap(false)
  r.age=Build.Label(r,"",542,-7,76,11);r.page=Build.Label(r,"",620,-7,54,12)
  r:SetScript("OnClick",function()if r.resultIndex then selectedRow=r.resultIndex;selectedKey=r.quoteKey;UI.Refresh()end end)
  r:SetScript("OnEnter",function(self)local row=self.resultIndex and(Build.Snapshot().rows or{})[self.resultIndex];if row then Build.ItemTip(self,row.itemID or(Build.Watch()and Build.Watch().itemID),"Stack: "..row.count.." for "..Build.Money(row.buyout).."\nPer item: "..Build.Money(row.unitPrice).."\nSeller: "..tostring(row.owner).."\n"..Build.Age(row.observedAt).." · AH page "..((row.page or 0)+1).."\nRecheck old observations before buying.")end end);r:SetScript("OnLeave",Build.HideTip)
  frame.resultRows[i]=r
  local function CatalogRow()
   local row=CreateFrame("Button",nil,frame,"BackdropTemplate");row:SetPoint("TOPLEFT",344,y);row:SetSize(680,27);Build.Box(row);row.icon=Build.Icon(row,4,-3,21);row.label=Build.Label(row,"",34,-6,640,12);row.label:SetWordWrap(false);row:Hide();row:SetScript("OnLeave",Build.HideTip);return row
  end
  local f=CatalogRow();f:SetScript("OnClick",function(self)if self.itemID then Build.AddItem(self.itemID)end end);f:SetScript("OnEnter",function(self)Build.ItemTip(self,self.itemID,"Click to add this item. Buying and bait prices start at zero.")end);frame.findRows[i]=f
  local v=CatalogRow();v:SetScript("OnClick",function(self)if self.entry then Build.Recheck(self.entry.index,self.entry.itemID)end end);v:SetScript("OnEnter",function(self)if self.entry then Build.ItemTip(self,self.entry.itemID,"Remembered scan observation. Click for a fresh check; this click never buys.")end end);frame.reviewRows[i]=v
 end
 frame.resultPrev=Build.Button(frame,"< rows",344,-615,74,function()if viewMode=="items"then findPage=math.max(1,findPage-1)elseif viewMode=="review"then reviewPage=math.max(1,reviewPage-1)else resultPage=math.max(1,resultPage-1)end;UI.Refresh()end)
 frame.resultPages=Build.Label(frame,"",428,-622,230,12)
 frame.resultNext=Build.Button(frame,"rows >",666,-615,74,function()if viewMode=="items"then findPage=findPage+1 elseif viewMode=="review"then reviewPage=reviewPage+1 else resultPage=resultPage+1 end;UI.Refresh()end)
 frame.pagePrev=Build.Button(frame,"< AH page",758,-615,126,function()local s=Build.Snapshot();Build.SelectedScan(math.max(0,(s.page or 0)-1))end)
 frame.pageNext=Build.Button(frame,"AH page >",892,-615,132,function()local s=Build.Snapshot();Build.SelectedScan((s.page or 0)+1)end)
 frame.buy=Build.Button(frame,"Buy selected stack",344,-655,180,function()if selectedRow and Build.SavePrices()then Build.Run(Build.Engine().BuySelected,selectedRow);selectedRow,selectedKey=nil,nil;UI.Refresh()end end)
 frame.recheck=Build.Button(frame,"Recheck offer",532,-655,128,function()if selectedRow then Build.Recheck(selectedRow)end end)
 frame.post=Build.Button(frame,"Bait Scan",668,-655,148,function()
  local w=Build.Watch();if not w or not w.checked then Build.Tell("Check the selected bait item first.");return end
  if Build.SavePrices()then Build.Run(Build.Engine().BaitScan,Build.CheckedIDs(),{allPages=frame.allPages:GetChecked()and true or false});viewMode="offers";UI.Refresh()end
 end)
 frame.reset=Build.Button(frame,"Reset session",824,-655,200,function()Build.Run(Build.Engine()and Build.Engine().ResetSession);UI.Refresh()end)
 frame.session=Build.Label(frame,"",18,-699,1004,13);frame.session:SetHeight(20)
 frame.status=Build.Label(frame,"",18,-728,1004,14);frame.status:SetHeight(34)
 Build.Label(frame,"Add items (use the Item ID / link / name box above):",18,-774,1004,14)
 Build.Label(frame,"Drag an owned bag item into the box. WD catches it; your item stays in your bags.\nType the Item ID shown under the item name in its tooltip, then press Enter.\nOr click the box, then Shift-click an item. Search a name with Find item; click a result to add it.",18,-798,1004,13):SetHeight(55)
 Build.Label(frame,"Left-drag moves. Shift-drag scales. Escape or X closes and stops scanning. Prices without g/s/c are gold.",18,-860,1004,13)
 local registered=NS.RegisterWindow and NS.RegisterWindow(frame,{close=UI.Hide})
 if not registered then UISpecialFrames=UISpecialFrames or{};table.insert(UISpecialFrames,"WatchDeskStandaloneWindow")end
 frame:SetScript("OnShow",function()Build.InstallItemLinkHooks();if NS.RegisterWindow then NS.RegisterWindow(frame,{close=UI.Hide})end;if NS.FocusWindow then NS.FocusWindow(frame)end;UI.Refresh()end)
 local ticker=CreateFrame("Frame",nil,frame);local elapsed=0
 ticker:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+(dt or 0);if elapsed>=.5 then elapsed=0;if frame:IsShown()then UI.Refresh()end end end)
end
function UI.Refresh()
 if not frame or not frame:IsShown()then return end
 local s=Snapshot();local list=DB().watches;local busy=Busy(s);local w=Watch();local filtered=FilteredWatches()
 local wp=math.max(1,math.ceil(#filtered/WATCH_ROWS));watchPage=math.max(1,math.min(wp,watchPage))
 for i,r in ipairs(frame.watchRows)do
  local entry=filtered[(watchPage-1)*WATCH_ROWS+i];local item=entry and entry.watch;r.watchIndex=entry and entry.index or nil;r:SetShown(item~=nil)
  if item then local data=entry.info;r.label:SetText(data.name.."\n|cff9aabbcID "..item.itemID.."|r");if r.icon then r.icon:SetTexture(data.icon or"Interface\\Icons\\INV_Misc_QuestionMark")end;r.check:SetChecked(item.checked and true or false);r:SetBackdropBorderColor(entry.index==selected and 1 or .3,entry.index==selected and .8 or .35,entry.index==selected and .2 or .4,1);r:EnableMouse(not busy);SetEnabled(r.check,not busy)end
 end
 local checked=0;for _,item in ipairs(list)do if item.checked then checked=checked+1 end end
 frame.watchPages:SetText(watchPage.." / "..wp.." · "..#filtered.." / "..#list.." watches");SetEnabled(frame.watchPrev,watchPage>1);SetEnabled(frame.watchNext,watchPage<wp)
 frame.checkedOnly:SetChecked(checkedOnly);frame.checkedOnly.caption:SetText("Checked ("..checked..")");frame.watchCategory:SetText(CategoryText(watchCategory).." ▾");frame.findCategory:SetText(CategoryText(findCategory).." ▾");frame.findCategory:SetShown(viewMode=="items")
 frame.sort:SetText((sortMode=="name"and"Name A–Z"or sortMode=="id"and"Item ID"or sortMode=="checked"and"Checked first"or"Saved order").." ▾")
 frame.duration:SetText(({"12 hours","24 hours","48 hours"})[frame.durationValue or 1]);frame.pause:SetText(s.lookPaused and"Resume"or"Pause")
 local info=w and ItemInfo(w.itemID);if frame.itemIcon then frame.itemIcon:SetTexture(info and info.icon or"Interface\\Icons\\INV_Misc_QuestionMark")end
 RefreshSelectedItemTip(s)
 frame.current:SetText(viewMode=="items"and(#findResults>0 and("Find items: "..#findResults..(#findResults>=100 and" shown · refine your search for more"or" matches · click one to add"))or"Find items: enter a name / ID below, or choose a category")or viewMode=="review"and"Review scanned offers · click for a fresh AH check"or(info and(info.name.."  |  Item ID "..w.itemID)or"Select or add an item"))
 frame.findSearchLabel:SetShown(viewMode=="items");frame.findSearch:SetShown(viewMode=="items");frame.findSearchButton:SetShown(viewMode=="items");frame.stock:SetShown(viewMode~="items")
 frame.stock:SetText(viewMode=="items"and"Identity catalogue only. Every new watch starts with zero prices; no bait is suggested."or viewMode=="review"and"Earlier observations can change. Rechecking never buys an item."or StockLine(w and w.itemID))
 local rows=s.rows or{};local result=(s.resultsByItem or{})[s.itemID]or{}
 local token=s.reviewedIndex and(tostring(s.itemID)..":"..tostring(s.reviewedIndex)..":"..tostring(result.at))
 if token and token~=lastReviewToken then lastReviewToken=token;selectedRow=s.reviewedIndex;selectedKey=RowKey(rows[selectedRow]);resultPage=math.ceil(selectedRow/RESULT_ROWS)end
 if selectedRow and RowKey(rows[selectedRow])~=selectedKey then selectedRow,selectedKey=nil,nil end
 local review,reviewTotal=ReviewEntries(s);frame.review:SetText("Review scans ("..#review..")")
 if viewMode=="review"and reviewTotal>#review then frame.current:SetText("Review scans: "..#review.." shown / "..reviewTotal.." observed rows");frame.stock:SetText("Tray shows up to "..MAX_REVIEW.." rows from the latest scans. Select a saved watch to page all its results.")end
 local source=viewMode=="items"and findResults or viewMode=="review"and review or rows
 local pages=math.max(1,math.ceil(#source/RESULT_ROWS));local page=viewMode=="items"and findPage or viewMode=="review"and reviewPage or resultPage;page=math.max(1,math.min(pages,page))
 if viewMode=="items"then findPage=page elseif viewMode=="review"then reviewPage=page else resultPage=page end
 for _,col in ipairs(frame.columns)do col:SetShown(viewMode=="offers")end
 for i,r in ipairs(frame.resultRows)do
  local index=(page-1)*RESULT_ROWS+i;local data=rows[index];local live=viewMode=="offers"and data~=nil;r.resultIndex=live and index or nil;r.quoteKey=RowKey(data);r:SetShown(live)
  if live then r.qty:SetText(tostring(data.count or 0));r.unit:SetText(Money(data.unitPrice));r.total:SetText(Money(data.buyout));r.owner:SetText(data.owner or"Unknown");r.age:SetText(Age(data.observedAt or result.at));r.page:SetText(tostring((data.page or s.page or 0)+1));r:SetBackdropBorderColor(index==selectedRow and 1 or .3,index==selectedRow and .8 or .35,index==selectedRow and .2 or .4,1);r:EnableMouse(not busy)end
  local f=frame.findRows[i];local found=viewMode=="items"and findResults[index];f.itemID=found and found.itemID or nil;f:SetShown(found~=nil and found~=false)
  if found then local item=ItemInfo(found.itemID);f.label:SetText(item.name.."  |  ID "..found.itemID.."  |  Add to watches");if f.icon then f.icon:SetTexture(item.icon or"Interface\\Icons\\INV_Misc_QuestionMark")end;f:EnableMouse(not busy)end
  local v=frame.reviewRows[i];local remembered=viewMode=="review"and review[index];v.entry=remembered or nil;v:SetShown(remembered~=nil and remembered~=false)
  if remembered then local item=ItemInfo(remembered.itemID);local row=remembered.row;v.label:SetText(item.name.." · "..row.count.."x · "..Money(row.unitPrice).." each · "..Age(remembered.at));if v.icon then v.icon:SetTexture(item.icon or"Interface\\Icons\\INV_Misc_QuestionMark")end;v:EnableMouse(not busy)end
 end
 frame.resultPages:SetText(page.." / "..pages.." · "..#source..(viewMode=="offers"and(" stacks | AH "..((s.page or 0)+1))or" entries"));SetEnabled(frame.resultPrev,page>1);SetEnabled(frame.resultNext,page<pages)
 SetEnabled(frame.pagePrev,viewMode=="offers"and w and s.open and not busy and(s.page or 0)>0);SetEnabled(frame.pageNext,viewMode=="offers"and w and s.open and not busy and(tonumber(s.total)or 0)>((s.page or 0)+1)*50)
 SetEnabled(frame.scanChecked,checked>0 and s.open and not busy);SetEnabled(frame.scanSelected,w and s.open and not busy);SetEnabled(frame.scanAll,w and s.open and not busy and Engine()and Engine().ScanAll)
 SetEnabled(frame.look,checked>0 and s.open and not busy and Engine()and Engine().StartLook);SetEnabled(frame.pause,s.lookRunning or(s.lookPaused and not s.waitingForResponse and not s.responseAmbiguous));SetEnabled(frame.stop,s.scanning or s.pending or s.preparing or s.prepared or s.lookRunning or s.lookPaused or s.waitingForResponse)
 local nativeAvailable,nativeReady,nativeReason=AuctionatorState(s)
 frame.auctionatorSelected:SetShown(nativeAvailable);frame.auctionatorChecked:SetShown(nativeAvailable)
 frame.auctionatorSelected.wdAuctionatorReason=nativeReason or(not w and"Select a watch first."or nil)
 frame.auctionatorChecked.wdAuctionatorReason=nativeReason or(checked==0 and"Check at least one item first."or nil)
 SetEnabled(frame.auctionatorSelected,nativeReady and w);SetEnabled(frame.auctionatorChecked,nativeReady and checked>0)
 SetEnabled(frame.add,not busy);SetEnabled(frame.find,not busy);SetEnabled(frame.remove,w and not busy);SetEnabled(frame.apply,w and not busy);SetEnabled(frame.all,not busy);SetEnabled(frame.none,not busy)
 for _,key in ipairs(EDIT_KEYS)do frame[key]:EnableMouse(w and not busy and true or false)end;SetEnabled(frame.duration,w and not busy)
 local row=selectedRow and rows[selectedRow];local eligible=row and w and(tonumber(w.maxUnitCopper)or 0)>0 and(tonumber(row.unitPrice)or math.huge)<=w.maxUnitCopper
 SetEnabled(frame.buy,viewMode=="offers"and eligible and row.eligible~=false and(row.page or s.page or 0)==(s.page or 0)and s.open and not busy and s.buyReady~=false)
 SetEnabled(frame.recheck,viewMode=="offers"and row and s.open and not busy and Engine()and Engine().RecheckSelected)
 frame.post:SetText("Bait Scan");SetEnabled(frame.post,w and w.checked and s.open and not busy and(tonumber(w.baitUnitCopper)or 0)>0 and s.postReady~=false)
 SetEnabled(frame.reset,not busy and Engine()and Engine().ResetSession)
 local totals=s.sessionTotals or{};local summary=s.summary or result.summary or{}
 frame.session:SetText("Checked: "..checked.."  |  Session: "..(totals.quantity or s.boughtQuantity or 0).." bought / "..Money(totals.spentCopper or s.spentCopper).." spent"..(summary.stacks and("  |  Selected scan: "..summary.stacks.." stacks / "..(summary.quantity or 0).." units / "..(summary.pages or 1).." pages"..(summary.complete==false and" · partial"or""))or"")..(s.lookRunning and("  |  Repeat active"..(s.nextCycleIn and(" · next "..math.ceil(s.nextCycleIn).."s")or""))or s.lookPaused and"  |  Repeat paused"or""))
 local reserved=(s.reservedQuantity or 0)>0 or(s.reservedCopper or 0)>0
 if reserved then frame.session:SetText(frame.session:GetText().."  |  Unconfirmed: "..(s.reservedQuantity or 0).." items / "..Money(s.reservedCopper).." reserved")end
 frame.status:SetText((s.status or(s.open and"Ready."or"Visit an auctioneer."))..(reserved and" Check purchases/mail before Reset session clears unconfirmed holds."or""))
end
function UI.Show()
 Create();if not selected and #DB().watches>0 then SelectWatch(1)end
 frame:Show();UI.Refresh();return frame
end
function UI.Hide()if frame then frame:Hide()end end
function UI.Toggle()if frame and frame:IsShown()then UI.Hide()else UI.Show()end end
NS.Refresh=UI.Refresh
