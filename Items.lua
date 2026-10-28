local _,NS=...
-- Local identity search only. This module has no starter watches, prices or bait ideas.
local I={};NS.Items=I
local pages,clock={},0
local function ID(v)
 local s=tostring(v or "");local n=tonumber(s:match("item:(%d+)")or s:match("^%s*(%d+)%s*$"))
 return n and n==math.floor(n)and n>0 and n<=10000000 and n or nil
end
local function Decode(page)
 local c=pages[page];clock=clock+1
 if c then c.used=clock;return c.rows end
 local rows={};local data=NS.ItemData;local raw=data and data.pages[page]
 if raw then for line in raw:gmatch("[^\n]+")do
  local id,quality,classID,name=line:match("^(%d+)\t(%d+)\t(%d+)\t(.+)$")
  if id then id=tonumber(id);rows[id]={itemID=id,quality=tonumber(quality),classID=tonumber(classID),name=name}end
 end end
 local n,oldest,age=0,nil,math.huge
 for key,item in pairs(pages)do n=n+1;if item.used<age then oldest,age=key,item.used end end
 if n>=12 then pages[oldest]=nil end
 pages[page]={rows=rows,used=clock};return rows
end
local function Native(id)
 local get=GetItemInfo or(C_Item and C_Item.GetItemInfo)
 if type(get)~="function"then return end
 local ok,name,link,quality,level,required,kind,subkind,stack,equip,icon,_,classID=pcall(get,id)
 if ok and type(name)=="string"and name~=""then
  return {itemID=id,name=name,link=link,quality=quality,classID=classID,icon=icon,stackSize=stack}
 end
end
function I.Get(value)
 local id=ID(value);if not id then return end
 local native=Native(id);local row=Decode(math.floor(id/256))[id]
 if not row then return native or {itemID=id,name="Item #"..id}end
 if native then native.classID=native.classID or row.classID;return native end
 return {itemID=id,name=row.name,classID=row.classID,quality=row.quality,historical=true}
end
function I.Search(value,limit,category)
 local query=tostring(value or ""):match("^%s*(.-)%s*$"):lower()
 limit=tonumber(limit)
 if not limit or limit~=limit or limit==math.huge or limit==-math.huge then limit=100 end
 limit=math.max(1,math.min(200,math.floor(limit)))
 local id=ID(query)
 if id then local row=I.Get(id);return row and(not category or row.classID==category)and{row}or{}end
 if #query<2 and category==nil then return{}end
 local tokens={};for token in query:gmatch("%S+")do tokens[#tokens+1]=token end
 local out,seen={},{}
 local function Add(row,alreadyMatched)
  if #out>=limit or seen[row.itemID]or category and row.classID~=category then return end
  local name=row.name:lower()
  if not alreadyMatched then for _,token in ipairs(tokens)do if not name:find(token,1,true)then return end end end
  seen[row.itemID]=true;out[#out+1]=row
 end
 -- Known watches use current localized native names even when the historic English name differs.
 local settings=NS.GetSettings and NS.GetSettings()
 for _,watch in ipairs(settings and settings.watches or{})do local row=I.Get(watch.itemID);if row then Add(row)end end
 local data=NS.ItemData
 local keys={};for page in pairs(data and data.pages or{})do keys[#keys+1]=page end;table.sort(keys)
 for _,page in ipairs(keys)do
  local raw=data.pages[page]
  for line in raw:gmatch("[^\n]+")do
   local itemID,quality,classID,name=line:match("^(%d+)\t(%d+)\t(%d+)\t(.+)$")
   if itemID then
    local row={itemID=tonumber(itemID),name=name,quality=tonumber(quality),classID=tonumber(classID),historical=true}
    -- Avoid native cache lookups for every catalogue row: only matching English identities need one.
    local match=true;for _,token in ipairs(tokens)do if not name:lower():find(token,1,true)then match=false;break end end
    if match then Add(I.Get(row.itemID)or row,true)end
   end
   if #out>=limit then break end
  end
  if #out>=limit then break end
 end
 table.sort(out,function(a,b)local x,y=a.name:lower(),b.name:lower();if x==y then return a.itemID<b.itemID end;return x<y end)
 return out
end
function I.Stock(value)
 local id=ID(value);if not id then return{available=false}end
 local C=C_Container;local slots=C and C.GetContainerNumSlots or GetContainerNumSlots
 local info=C and C.GetContainerItemInfo or GetContainerItemInfo
 local itemID=C and C.GetContainerItemID or GetContainerItemID
 if type(slots)~="function"or type(info)~="function"or type(itemID)~="function"then return{available=false}end
 local bags=0
 for bag=0,NUM_BAG_SLOTS or 4 do
  local ok,n=pcall(slots,bag);if not ok or type(n)~="number"or n<0 or n>1000 then return{available=false}end
  for slot=1,n do
   local found,item=pcall(itemID,bag,slot)
   if not found then return{available=false}end
   if item==id then
    local good,record,count=pcall(info,bag,slot)
    count=good and(type(record)=="table"and record.stackCount or count)
    if type(count)~="number"or count<0 then return{available=false}end
    bags=bags+count
   end
  end
 end
 return{available=true,bags=bags,total=bags,scope="Carried bags only"}
end
-- Compatibility slot for UI callers: no market-price feeds or recommendations are bundled.
function I.Prices()return{available=false}end
