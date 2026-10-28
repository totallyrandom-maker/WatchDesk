local _,NS=...
local UI={};NS.Window=UI
local frame,anchor,selected,watchPage,resultPage,selectedRow,selectedKey,scaling
watchPage,resultPage=1,1
local WIDTH,HEIGHT,WATCH_ROWS,RESULT_ROWS=840,626,8,9
local function DB()local d=NS.GetSettings();d.watches=d.watches or{};d.window=d.window or{};return d end
local function Tell(text)if NS.Notify then NS.Notify(text)end end
local function Money(c)
 local n=math.max(0,math.floor((tonumber(c)or 0)+.5));local g=math.floor(n/10000);local silver=math.floor(n/100)%100;local copper=n%100
 if g>0 then return string.format("%dg %02ds %02dc",g,silver,copper)elseif silver>0 then return string.format("%ds %02dc",silver,copper)else return copper.."c"end
end
local function InputGold(c)return string.format("%.4f",(tonumber(c)or 0)/10000)end
local function ParseGold(text)
 text=tostring(text or""):match("^%s*(.-)%s*$"):lower():gsub("g$","")
 if not text:match("^%d*%.?%d+$")then return end
 local n=tonumber(text);if not n or n<0 then return end
 local copper=math.floor(n*10000+.5);if copper>2147483647 then return end
 return copper
end
local function Watch()return selected and DB().watches[selected]end
local function CheckedIDs()local ids={};for _,w in ipairs(DB().watches)do if w.checked then ids[#ids+1]=w.itemID end end;return ids end
local function Engine()return NS.Engine end
local function Snapshot()local e=Engine();return e and e.Snapshot and e.Snapshot()or{}end
local function Busy(s)return s.scanning or s.pending end
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
 e:SetScript("OnEscapePressed",function(self)self:ClearFocus()end);e:SetScript("OnEnterPressed",function(self)self:ClearFocus()end);return e
end
local function SetEnabled(f,on)f:SetEnabled(on and true or false)end
local function RowKey(r)return r and table.concat({tostring(r.link),tostring(r.owner),tostring(r.count),tostring(r.buyout),tostring(r.index)},"|")end
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
local function SelectedEngine()
 local w=Watch();local e=Engine();if not w or not e then return false end
 if not Run(e.SetItem,w.itemID)then return false end
 return Run(e.SetLimits,w.maxUnitCopper or 0,w.baitUnitCopper or 0)
end
local function SavePrices()
 local w=Watch();if not w then Tell("Select an item first.");return false end
 local maxBuy,bait=ParseGold(frame.maxBuy:GetText()),ParseGold(frame.bait:GetText())
 if not maxBuy or not bait then Tell("Enter prices in gold, such as 2.50. Zero leaves that action off.");return false end
 local e=Engine();if not e or not Run(e.SetItem,w.itemID)or not Run(e.SetLimits,maxBuy,bait)then return false end
 w.maxUnitCopper,w.baitUnitCopper=maxBuy,bait
 return true
end
local function SelectWatch(index)
 if Busy(Snapshot())then Tell("Stop the scan or finish the pending action first.");return end
 selected=index;selectedRow,selectedKey,resultPage=nil,nil,1
 local w=Watch();if w then frame.maxBuy:SetText(InputGold(w.maxUnitCopper));frame.bait:SetText(InputGold(w.baitUnitCopper));SelectedEngine()end
 UI.Refresh()
end
local function AddItem(value)
 if Busy(Snapshot())then Tell("Stop the scan or finish the pending action first.");return false end
 local id=tonumber(value)or tonumber(tostring(value or""):match("item:(%d+)"))
 if not id or id~=id or id<1 or id>10000000 or id~=math.floor(id)then Tell("Enter an item ID or paste an item link.");return false end
 for i,w in ipairs(DB().watches)do if w.itemID==id then SelectWatch(i);return true end end
 local items=DB().watches;if #items>=100 then Tell("The checklist holds up to 100 items.");return false end
 items[#items+1]={itemID=id,checked=true,maxUnitCopper=0,baitUnitCopper=0}
 watchPage=math.ceil(#items/WATCH_ROWS);SelectWatch(#items);frame.item:SetText("");return true
end
local function DropItem()
 local kind,id,link=GetCursorInfo()
 if kind=="item"and AddItem(link or id)then ClearCursor()end
end
local function SelectedScan(page)
 if not SavePrices()then return end
 selectedRow,selectedKey=nil,nil;Run(Engine().Scan,page or 0);UI.Refresh()
end
local function Create()
 if frame then return end
 frame=CreateFrame("Frame","WatchDeskStandaloneWindow",UIParent,"BackdropTemplate")
 UI.frame=frame;frame:Hide();frame:SetSize(WIDTH,HEIGHT);frame:SetFrameStrata("DIALOG");Box(frame)
 frame:SetMovable(true);frame:EnableMouse(true);frame:SetClampedToScreen(false);frame:RegisterForDrag("LeftButton")
 frame:SetScript("OnDragStart",StartMove);frame:SetScript("OnDragStop",FinishMove)
 frame:SetScript("OnHide",function()if scaling then FinishMove()else frame:StopMovingOrSizing()end end)
 anchor=CreateFrame("Frame",nil,UIParent);anchor:SetSize(1,1)
 local d=DB().window;frame:SetScale(math.max(.65,math.min(1.65,tonumber(d.scale)or 1)));Place(d.x,d.y);SavePosition()
 local title=CreateFrame("Frame",nil,frame);title:SetPoint("TOPLEFT",0,0);title:SetPoint("TOPRIGHT",0,0);title:SetHeight(34)
 title:EnableMouse(true);title:RegisterForDrag("LeftButton");title:SetScript("OnDragStart",StartMove);title:SetScript("OnDragStop",FinishMove)
 Label(title,"Watch Desk",16,-9,700,18)
 local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton");close:SetPoint("TOPRIGHT",-2,-2)
 Label(frame,"Set your prices, check items, then scan. Buying and bait posting require your click.",18,-42,804,13)
 frame.item=Edit(frame,22,-76,230);frame.item:SetMaxLetters(512)
 frame.item:SetScript("OnEnterPressed",function(self)AddItem(self:GetText());self:ClearFocus()end)
 frame.item:SetScript("OnReceiveDrag",DropItem)
 frame.item:SetScript("OnMouseDown",function(_,button)if button=="LeftButton"and GetCursorInfo()then DropItem()end end)
 Label(frame,"Item link / ID (or drop a bag item)",18,-59,350,12)
 frame.add=Button(frame,"Add",262,-76,70,function()AddItem(frame.item:GetText())end)
 frame.remove=Button(frame,"Remove",338,-76,74,function()
  if Busy(Snapshot())then return end
  if selected then table.remove(DB().watches,selected);selected=nil;selectedRow,selectedKey=nil,nil;UI.Refresh()end
 end)
 Label(frame,"Max buy / item (gold)",430,-59,170,12);frame.maxBuy=Edit(frame,434,-76,154)
 Label(frame,"Bait / item (gold)",606,-59,150,12);frame.bait=Edit(frame,610,-76,132)
 frame.apply=Button(frame,"Apply",754,-76,66,function()SavePrices();UI.Refresh()end)
 frame.scanChecked=Button(frame,"Scan",18,-116,120,function()
  local e=Engine();if not e or not e.ScanList then return end
  if selected and not SavePrices()then return end
  local ids=CheckedIDs()
  if #ids==0 then Tell("Check at least one item.");return end
  selectedRow,selectedKey=nil,nil;Run(e.ScanList,ids);UI.Refresh()
 end)
 frame.scanSelected=Button(frame,"Scan selected",146,-116,120,function()SelectedScan(0)end)
 frame.stop=Button(frame,"Stop",274,-116,70,function()Run(Engine()and Engine().Stop);selectedRow,selectedKey=nil,nil;UI.Refresh()end)
 Label(frame,"Items",18,-157,70,14)
 frame.all=Button(frame,"All",100,-151,60,function()for _,w in ipairs(DB().watches)do w.checked=true end;UI.Refresh()end)
 frame.none=Button(frame,"None",164,-151,70,function()for _,w in ipairs(DB().watches)do w.checked=false end;UI.Refresh()end)
 frame.watchRows={}
 for i=1,WATCH_ROWS do
  local r=CreateFrame("Button",nil,frame,"BackdropTemplate");r:SetPoint("TOPLEFT",18,-183-(i-1)*30);r:SetSize(230,28);Box(r)
  r.check=CreateFrame("CheckButton",nil,r,"UICheckButtonTemplate");r.check:SetSize(24,24);r.check:SetPoint("LEFT",1,0)
  r.check:SetScript("OnClick",function(self)if r.watchIndex then DB().watches[r.watchIndex].checked=self:GetChecked()and true or false end;UI.Refresh()end)
  r.label=Label(r,"",28,-6,194,13);r.label:SetWordWrap(false)
  r:SetScript("OnClick",function()if r.watchIndex then SelectWatch(r.watchIndex)end end)
  frame.watchRows[i]=r
 end
 frame.watchPrev=Button(frame,"<",18,-438,34,function()watchPage=math.max(1,watchPage-1);UI.Refresh()end)
 frame.watchPages=Label(frame,"",62,-445,126,12)
 frame.watchNext=Button(frame,">",206,-438,34,function()watchPage=watchPage+1;UI.Refresh()end)
 frame.current=Label(frame,"Select an item",282,-156,530,15)
 Label(frame,"Stack",282,-184,55,12);Label(frame,"Each",342,-184,100,12);Label(frame,"Total",452,-184,110,12);Label(frame,"Seller",572,-184,244,12)
 frame.resultRows={}
 for i=1,RESULT_ROWS do
  local r=CreateFrame("Button",nil,frame,"BackdropTemplate");r:SetPoint("TOPLEFT",282,-205-(i-1)*25);r:SetSize(536,24);Box(r)
  r.qty=Label(r,"",4,-5,52,13);r.unit=Label(r,"",64,-5,104,13);r.total=Label(r,"",174,-5,112,13);r.owner=Label(r,"",294,-5,236,13);r.owner:SetWordWrap(false)
  r:SetScript("OnClick",function()if r.resultIndex then selectedRow=r.resultIndex;selectedKey=r.quoteKey;UI.Refresh()end end)
  frame.resultRows[i]=r
 end
 frame.resultPrev=Button(frame,"< rows",282,-438,72,function()resultPage=math.max(1,resultPage-1);UI.Refresh()end)
 frame.resultPages=Label(frame,"",364,-445,190,12)
 frame.resultNext=Button(frame,"rows >",558,-438,72,function()resultPage=resultPage+1;UI.Refresh()end)
 frame.pagePrev=Button(frame,"< AH page",638,-438,86,function()local s=Snapshot();SelectedScan(math.max(0,(s.page or 0)-1))end)
 frame.pageNext=Button(frame,"AH page >",732,-438,86,function()local s=Snapshot();SelectedScan((s.page or 0)+1)end)
 frame.buy=Button(frame,"Buy selected stack",282,-483,180,function()if selectedRow and SavePrices()then Run(Engine().BuySelected,selectedRow);selectedRow,selectedKey=nil,nil;UI.Refresh()end end)
 frame.post=Button(frame,"Bait Scan",476,-483,180,function()
  local w=Watch();if not w or not w.checked then Tell("Check the selected bait item first.");return end
  if SavePrices()then Run(Engine().BaitScan,CheckedIDs());UI.Refresh()end
 end)
 frame.status=Label(frame,"",18,-529,800,14);frame.status:SetHeight(48)
 Label(frame,"Left-drag moves. Shift-drag scales. Escape closes. Prices are per item.",18,-595,800,13)
 local registered=NS.RegisterWindow and NS.RegisterWindow(frame)
 if not registered then UISpecialFrames=UISpecialFrames or{};table.insert(UISpecialFrames,"WatchDeskStandaloneWindow")end
 frame:SetScript("OnShow",function()UI.Refresh()end)
end
function UI.Refresh()
 if not frame or not frame:IsShown()then return end
 local s=Snapshot();local list=DB().watches;local busy=Busy(s);local w=Watch()
 local wp=math.max(1,math.ceil(#list/WATCH_ROWS));watchPage=math.max(1,math.min(wp,watchPage))
 for i,r in ipairs(frame.watchRows)do
  local index=(watchPage-1)*WATCH_ROWS+i;local item=list[index];r.watchIndex=item and index or nil;r:SetShown(item~=nil)
  if item then local name=GetItemInfo(item.itemID)or("Item #"..item.itemID);r.label:SetText(name);r.check:SetChecked(item.checked and true or false);r:SetBackdropBorderColor(index==selected and 1 or .3,index==selected and .8 or .35,index==selected and .2 or .4,1);r:EnableMouse(not busy);SetEnabled(r.check,not busy)end
 end
 frame.watchPages:SetText(watchPage.." / "..wp.."  ("..#list.." items)");SetEnabled(frame.watchPrev,watchPage>1);SetEnabled(frame.watchNext,watchPage<wp)
 frame.current:SetText(w and(GetItemInfo(w.itemID)or("Item #"..w.itemID))or"Select an item")
 local rows=s.rows or{};if selectedRow and RowKey(rows[selectedRow])~=selectedKey then selectedRow,selectedKey=nil,nil end
 local pages=math.max(1,math.ceil(#rows/RESULT_ROWS));resultPage=math.max(1,math.min(pages,resultPage))
 for i,r in ipairs(frame.resultRows)do
  local index=(resultPage-1)*RESULT_ROWS+i;local data=rows[index];r.resultIndex=data and index or nil;r.quoteKey=RowKey(data);r:SetShown(data~=nil)
  if data then r.qty:SetText(tostring(data.count or 0));r.unit:SetText(Money(data.unitPrice));r.total:SetText(Money(data.buyout));r.owner:SetText(data.owner or"Unknown");r:SetBackdropBorderColor(index==selectedRow and 1 or .3,index==selectedRow and .8 or .35,index==selectedRow and .2 or .4,1);r:EnableMouse(not busy)end
 end
 frame.resultPages:SetText(resultPage.." / "..pages.."  | AH page "..((s.page or 0)+1));SetEnabled(frame.resultPrev,resultPage>1);SetEnabled(frame.resultNext,resultPage<pages)
 SetEnabled(frame.pagePrev,w and s.open and not busy and(s.page or 0)>0);SetEnabled(frame.pageNext,w and s.open and not busy and(tonumber(s.total)or 0)>((s.page or 0)+1)*50)
 local any=false;for _,item in ipairs(list)do if item.checked then any=true;break end end
 SetEnabled(frame.scanChecked,any and s.open and not busy);SetEnabled(frame.scanSelected,w and s.open and not busy);SetEnabled(frame.stop,s.scanning or s.pending or s.preparing or s.prepared)
 SetEnabled(frame.add,not busy);SetEnabled(frame.remove,w and not busy);SetEnabled(frame.apply,w and not busy);SetEnabled(frame.all,not busy);SetEnabled(frame.none,not busy)
 frame.maxBuy:EnableMouse(w and not busy and true or false);frame.bait:EnableMouse(w and not busy and true or false)
 local row=selectedRow and rows[selectedRow]
 local eligible=row and w and(tonumber(w.maxUnitCopper)or 0)>0 and(tonumber(row.unitPrice)or math.huge)<=w.maxUnitCopper
 SetEnabled(frame.buy,eligible and s.open and not busy and s.buyReady~=false)
 frame.post:SetText("Bait Scan");SetEnabled(frame.post,w and w.checked and s.open and not busy and(tonumber(w.baitUnitCopper)or 0)>0 and s.postReady~=false)
 frame.status:SetText(s.status or(s.open and"Ready."or"Visit an auctioneer."))
end
function UI.Show()
 Create();if not selected and #DB().watches>0 then SelectWatch(1)end
 frame:Show();UI.Refresh();return frame
end
function UI.Hide()if frame then frame:Hide()end end
function UI.Toggle()if frame and frame:IsShown()then UI.Hide()else UI.Show()end end
NS.Refresh=UI.Refresh
