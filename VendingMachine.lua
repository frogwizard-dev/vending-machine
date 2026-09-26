local ADDON = ...

-- Conjure spells (vanilla ranks), highest rank first.
local WATER_SPELLS = { 10140, 10139, 10138, 6127, 5506, 5505, 5504 }
local FOOD_SPELLS  = { 28612, 10145, 10144, 6129, 990, 597, 587 }

-- Conjured items, best first.
local WATER_ITEMS = { 8079, 8078, 8077, 3772, 2136, 2288, 5350 }
local FOOD_ITEMS  = { 22895, 8076, 8075, 1487, 1114, 1113, 5349 }

local TRADE_SLOTS = 6 -- slot 7 is "will not be traded"
local STEP_DELAY = 0.2
local TAG = "|cff69ccf0VendingMachine|r"

local KINDS = {
    water = { items = WATER_ITEMS, label = "Water" },
    food  = { items = FOOD_ITEMS,  label = "Food" },
}
local ITEM_KIND = {}
for _, id in ipairs(WATER_ITEMS) do ITEM_KIND[id] = "water" end
for _, id in ipairs(FOOD_ITEMS) do ITEM_KIND[id] = "food" end

-- API compat (Classic vs Retail)
local function IsKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) end
    return IsSpellKnown(id)
end

local function SpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture(id)
end

local function ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon(id)
end

local function ItemCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) end
    return GetItemCount(id)
end

local NumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local Pickup = C_Container and C_Container.PickupContainerItem or PickupContainerItem

local function SlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local i = C_Container.GetContainerItemInfo(bag, slot)
        if i then return i.itemID, i.stackCount, i.isLocked end
    else
        local _, count, locked, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
        return id, count, locked
    end
end

local function HighestKnown(list)
    for _, id in ipairs(list) do
        if IsKnown(id) then return id end
    end
end

-- Best tier of item first, then the fullest unlocked stack of it (items already in the trade are locked).
local function FindStack(kind)
    for _, itemID in ipairs(KINDS[kind].items) do
        local bestBag, bestSlot, bestCount
        for bag = 0, NUM_BAG_SLOTS or 4 do
            for slot = 1, NumSlots(bag) or 0 do
                local id, count, locked = SlotInfo(bag, slot)
                if id == itemID and not locked and (not bestCount or count > bestCount) then
                    bestBag, bestSlot, bestCount = bag, slot, count
                end
            end
        end
        if bestBag then return bestBag, bestSlot, itemID end
    end
end

local function BestItem(kind)
    for _, id in ipairs(KINDS[kind].items) do
        if ItemCount(id) > 0 then return id end
    end
end

local function TotalCount(kind)
    local n = 0
    for _, id in ipairs(KINDS[kind].items) do n = n + ItemCount(id) end
    return n
end

local function EmptyTradeSlot()
    for i = 1, TRADE_SLOTS do
        if not GetTradePlayerItemInfo(i) then return i end
    end
end

-- Places one stack into the first empty trade slot. Returns true on success.
local function PlaceStack(kind)
    if CursorHasItem() then return false end
    local tradeSlot = EmptyTradeSlot()
    if not tradeSlot then return false end
    local bag, slot = FindStack(kind)
    if not bag then return false end
    Pickup(bag, slot)
    ClickTradeButton(tradeSlot)
    ClearCursor()
    return true
end

local function CountInTrade()
    local w, f = 0, 0
    for i = 1, TRADE_SLOTS do
        local link = GetTradePlayerItemLink(i)
        local k = link and ITEM_KIND[tonumber(link:match("item:(%d+)"))]
        if k == "water" then w = w + 1 end
        if k == "food" then f = f + 1 end
    end
    return w, f
end

-- Fill remaining slots, keeping water and food as even as possible.
-- One stack per step so the client can lock each bag slot before the next pickup.
local filling = false
local function FillStep()
    if not TradeFrame:IsShown() or not EmptyTradeSlot() then filling = false return end
    local w, f = CountInTrade()
    local first, second = "water", "food"
    if f < w then first, second = "food", "water" end
    if PlaceStack(first) or PlaceStack(second) then
        C_Timer.After(STEP_DELAY, FillStep)
    else
        filling = false
    end
end

local function Fill()
    if filling then return end
    filling = true
    FillStep()
end

-- UI
local SIZE, GAP = 36, 4

local frame = CreateFrame("Frame", "VendingMachineFrame", UIParent, "BackdropTemplate")
frame:SetSize(SIZE * 2 + GAP * 3, SIZE * 2 + 22 + GAP * 4)
frame:SetFrameStrata("HIGH")
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0, 0, 0, 0.8)
frame:Hide()

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.spellID then
        GameTooltip:SetSpellByID(self.spellID)
    elseif self.itemID then
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:AddLine("Click: put one stack in the trade window", 0, 1, 0)
    elseif self.tip then
        GameTooltip:SetText(self.tip)
    end
    GameTooltip:Show()
end

local function StyleButton(b)
    b:SetSize(SIZE, SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetScript("OnEnter", Tooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
end

local function ConjureButton(name)
    local b = CreateFrame("Button", name, frame, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    StyleButton(b)
    return b
end

local function PlaceButton(kind)
    local b = CreateFrame("Button", nil, frame)
    b:RegisterForClicks("LeftButtonUp")
    StyleButton(b)
    b.kind = kind
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnClick", function(self)
        if not PlaceStack(self.kind) then
            print(TAG .. ": no " .. KINDS[self.kind].label:lower() .. " to place or trade window is full.")
        end
    end)
    return b
end

local conjureWater = ConjureButton("VendingMachineConjureWater")
local conjureFood = ConjureButton("VendingMachineConjureFood")
local placeWater = PlaceButton("water")
local placeFood = PlaceButton("food")

local fill = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
fill:SetHeight(22)
fill:SetText("Fill")
fill.tip = "Fill the trade window, half water / half food"
fill:SetScript("OnEnter", Tooltip)
fill:SetScript("OnLeave", GameTooltip_Hide)
fill:SetScript("OnClick", Fill)

conjureWater:SetPoint("TOPLEFT", GAP, -GAP)
conjureFood:SetPoint("LEFT", conjureWater, "RIGHT", GAP, 0)
placeWater:SetPoint("TOPLEFT", conjureWater, "BOTTOMLEFT", 0, -GAP)
placeFood:SetPoint("LEFT", placeWater, "RIGHT", GAP, 0)
fill:SetPoint("TOPLEFT", placeWater, "BOTTOMLEFT", 0, -GAP)
fill:SetPoint("RIGHT", placeFood, "RIGHT")

local function SetConjure(b, spellID)
    b.spellID = spellID
    b:SetAttribute("type", spellID and "spell" or nil)
    b:SetAttribute("spell", spellID)
    b.icon:SetTexture(spellID and SpellTexture(spellID) or 134400) -- question mark
    b.icon:SetDesaturated(not spellID)
    b.tip = "No conjure spell known"
end

-- Secure attributes: only touch out of combat.
local pending = false
local function UpdateSpells()
    if InCombatLockdown() then pending = true return end
    pending = false
    SetConjure(conjureWater, HighestKnown(WATER_SPELLS))
    SetConjure(conjureFood, HighestKnown(FOOD_SPELLS))
end

local function UpdateCounts()
    for _, b in ipairs({ placeWater, placeFood }) do
        local id = BestItem(b.kind)
        b.itemID = id
        b.tip = "No conjured " .. KINDS[b.kind].label:lower() .. " in bags"
        b.icon:SetTexture(id and ItemIcon(id) or SpellTexture(b.kind == "water" and conjureWater.spellID or conjureFood.spellID) or 134400)
        b.icon:SetDesaturated(not id)
        b.count:SetText(TotalCount(b.kind))
    end
end

local function ShowFrame()
    if InCombatLockdown() then return end
    UpdateSpells()
    UpdateCounts()
    local s = TradeFrame:GetEffectiveScale() / frame:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", TradeFrame:GetRight() * s + 2, TradeFrame:GetTop() * s - 20)
    frame:Show()
end

local hidePending = false
local function HideFrame()
    filling = false
    if InCombatLockdown() then hidePending = true return end
    frame:Hide()
end

-- Events
local ev = CreateFrame("Frame")
ev:RegisterEvent("TRADE_SHOW")
ev:RegisterEvent("TRADE_CLOSED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SHOW" then
        ShowFrame()
    elseif event == "TRADE_CLOSED" then
        HideFrame()
    elseif event == "BAG_UPDATE_DELAYED" then
        if frame:IsShown() then UpdateCounts() end
    elseif event == "SPELLS_CHANGED" then
        UpdateSpells()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then UpdateSpells() end
        if hidePending then hidePending = false; frame:SetShown(TradeFrame:IsShown()) end
    end
end)
