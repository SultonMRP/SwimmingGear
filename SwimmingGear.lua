-- Swimming Gear: auto-equip saved swim items while in water, restore when dry.

local ADDON_NAME = ...

local DEFAULT_DELAY = 2
local TICK = 0.2
local SHORT_CD = 1.6
local MISSING_MSG_GAP = 20

local db
local selectedSlot
local missingWarned = {}
local lastDryStart
local ui = {}

local SLOTS = {
	{ id = 1,  name = "Head",      inv = "HeadSlot" },
	{ id = 2,  name = "Neck",      inv = "NeckSlot" },
	{ id = 3,  name = "Shoulder",  inv = "ShoulderSlot" },
	{ id = 15, name = "Back",      inv = "BackSlot" },
	{ id = 5,  name = "Chest",     inv = "ChestSlot" },
	{ id = 9,  name = "Wrist",     inv = "WristSlot" },
	{ id = 10, name = "Hands",     inv = "HandsSlot" },
	{ id = 6,  name = "Waist",     inv = "WaistSlot" },
	{ id = 7,  name = "Legs",      inv = "LegsSlot" },
	{ id = 8,  name = "Feet",      inv = "FeetSlot" },
	{ id = 11, name = "Finger 1",  inv = "Finger0Slot" },
	{ id = 12, name = "Finger 2",  inv = "Finger1Slot" },
	{ id = 13, name = "Trinket 1", inv = "Trinket0Slot" },
	{ id = 14, name = "Trinket 2", inv = "Trinket1Slot" },
	{ id = 16, name = "Main Hand", inv = "MainHandSlot" },
	{ id = 17, name = "Off Hand",  inv = "SecondaryHandSlot" },
	{ id = 18, name = "Ranged",    inv = "RangedSlot" },
}

local EQUIP_LOCS = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 },
	INVTYPE_RELIC = { 18 },
	INVTYPE_TABARD = { 19 },
}

-- Every armor type the class can wear (not only the "best" type).
-- Cloth=1 Leather=2 Mail=3 Plate=4
local ARMOR_SUB_NAME = {
	[1] = "Cloth",
	[2] = "Leather",
	[3] = "Mail",
	[4] = "Plate",
	Cloth = 1,
	Leather = 2,
	Mail = 3,
	Plate = 4,
}

local CLASS_ARMOR = {
	WARRIOR = { [1] = true, [2] = true, [3] = true, [4] = true },
	PALADIN = { [1] = true, [2] = true, [3] = true, [4] = true },
	DEATHKNIGHT = { [1] = true, [2] = true, [3] = true, [4] = true },
	HUNTER = { [1] = true, [2] = true, [3] = true },
	SHAMAN = { [1] = true, [2] = true, [3] = true },
	EVOKER = { [1] = true, [2] = true, [3] = true },
	ROGUE = { [1] = true, [2] = true },
	DRUID = { [1] = true, [2] = true },
	MONK = { [1] = true, [2] = true },
	DEMONHUNTER = { [1] = true, [2] = true },
	MAGE = { [1] = true },
	PRIEST = { [1] = true },
	WARLOCK = { [1] = true },
}

local SHIELD_CLASSES = {
	WARRIOR = true,
	PALADIN = true,
	SHAMAN = true,
}

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 8,
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function Chat(msg)
	print("|cff33ccffSwimming Gear|r: " .. msg)
end

local function ItemInfo(idOrLink)
	local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not fn then
		return
	end
	return fn(idOrLink)
end

local function ItemInfoInstant(idOrLink)
	local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if not fn then
		return
	end
	return fn(idOrLink)
end

local function IsEquippable(idOrLink)
	local fn = (C_Item and C_Item.IsEquippableItem) or IsEquippableItem
	if not fn then
		return true
	end
	local ok, usable = pcall(fn, idOrLink)
	return ok and usable and true or false
end

local function EquipByName(idOrLink, slot)
	local fn = (C_Item and C_Item.EquipItemByName) or EquipItemByName
	if not fn then
		return
	end
	fn(idOrLink, slot)
end

local function BagSlotCount()
	return NUM_BAG_SLOTS or 4
end

local function ContainerNumSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	end
	if GetContainerNumSlots then
		return GetContainerNumSlots(bag) or 0
	end
	return 0
end

local function ContainerItemID(bag, slot)
	if C_Container and C_Container.GetContainerItemID then
		return C_Container.GetContainerItemID(bag, slot)
	end
	local link
	if C_Container and C_Container.GetContainerItemLink then
		link = C_Container.GetContainerItemLink(bag, slot)
	elseif GetContainerItemLink then
		link = GetContainerItemLink(bag, slot)
	end
	if link then
		return tonumber(link:match("item:(%d+)"))
	end
end

local function ContainerItemLink(bag, slot)
	if C_Container and C_Container.GetContainerItemLink then
		return C_Container.GetContainerItemLink(bag, slot)
	end
	if GetContainerItemLink then
		return GetContainerItemLink(bag, slot)
	end
end

local function ItemIDFromLink(link)
	if not link then
		return
	end
	return tonumber(link:match("item:(%d+)"))
end

local function SlotFitsLoc(slot, loc)
	local list = loc and EQUIP_LOCS[loc]
	if not list then
		return false
	end
	for i = 1, #list do
		if list[i] == slot then
			return true
		end
	end
	return false
end

local function InWater()
	if IsSubmerged and IsSubmerged() then
		return true
	end
	if IsSwimming and IsSwimming() then
		return true
	end
	return false
end

local function InCombat()
	if InCombatLockdown and InCombatLockdown() then
		return true
	end
	return UnitAffectingCombat and UnitAffectingCombat("player")
end

local function RemainingCD(start, duration, enable)
	if enable == 0 or enable == false then
		return 0
	end
	duration = tonumber(duration) or 0
	start = tonumber(start) or 0
	if duration <= SHORT_CD or start <= 0 then
		return 0
	end
	local left = start + duration - GetTime()
	if left < 0.2 then
		return 0
	end
	return left
end

local function ItemCooldownLeft(itemID)
	if not itemID then
		return 0
	end
	local start, duration, enable
	if C_Container and C_Container.GetItemCooldown then
		start, duration, enable = C_Container.GetItemCooldown(itemID)
	elseif C_Item and C_Item.GetItemCooldown then
		start, duration, enable = C_Item.GetItemCooldown(itemID)
	elseif GetItemCooldown then
		start, duration, enable = GetItemCooldown(itemID)
	end
	return RemainingCD(start, duration, enable)
end

local function EquippedCooldownLeft(slot)
	if not GetInventoryItemCooldown then
		return 0
	end
	local start, duration, enable = GetInventoryItemCooldown("player", slot)
	return RemainingCD(start, duration, enable)
end

local function SlotOnCooldown(slot, itemID)
	if EquippedCooldownLeft(slot) > 0 then
		return true
	end
	if ItemCooldownLeft(itemID) > 0 then
		return true
	end
	return false
end

local function DelaySeconds()
	local n = db and tonumber(db.delay)
	if not n or n < 0 then
		return DEFAULT_DELAY
	end
	return n
end

local function EnsureDB()
	if type(SwimmingGearDB) ~= "table" then
		SwimmingGearDB = {}
	end
	db = SwimmingGearDB
	if type(db.slots) ~= "table" then
		db.slots = {}
	end
	if type(db.originals) ~= "table" then
		db.originals = {}
	end
	if db.delay == nil then
		db.delay = DEFAULT_DELAY
	end
	if db.enabled == nil then
		db.enabled = false
	end
	if type(db.minimapIcon) ~= "table" then
		db.minimapIcon = {}
	end
	if db.minimap and db.minimap.angle and db.minimapIcon.minimapPos == nil then
		db.minimapIcon.minimapPos = db.minimap.angle
	end
	if db.minimapIcon.hide == nil then
		db.minimapIcon.hide = false
	end
end

local function IsEnabled()
	return db and db.enabled == true
end

local function SavedSlot(slot)
	return db and db.slots and db.slots[slot]
end

local function EquippedID(slot)
	if GetInventoryItemID then
		local id = GetInventoryItemID("player", slot)
		if id then
			return id
		end
	end
	return ItemIDFromLink(GetInventoryItemLink and GetInventoryItemLink("player", slot))
end

local function IsWearing(itemID)
	if not itemID then
		return false
	end
	for slot = 1, 19 do
		if EquippedID(slot) == itemID then
			return true
		end
	end
	return false
end

local function FindItemInBags(itemID)
	if not itemID then
		return
	end
	for bag = 0, BagSlotCount() do
		for slot = 1, ContainerNumSlots(bag) do
			if ContainerItemID(bag, slot) == itemID then
				return bag, slot, ContainerItemLink(bag, slot)
			end
		end
	end
end

local function ItemName(itemID, fallback)
	if fallback and fallback ~= "" then
		return fallback
	end
	local name = ItemInfo(itemID)
	return name or ("item " .. tostring(itemID))
end

local function WarnMissing(itemID, name)
	local now = GetTime()
	local last = missingWarned[itemID]
	if last and (now - last) < MISSING_MSG_GAP then
		return
	end
	missingWarned[itemID] = now
	Chat('item: "' .. ItemName(itemID, name) .. '" is not available')
end

local function RememberOriginal(slot)
	if db.originals[slot] then
		return
	end
	local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
	local id = EquippedID(slot)
	if not id then
		db.originals[slot] = { empty = true }
		return
	end
	db.originals[slot] = { id = id, link = link }
end

local function EquipID(itemID, slot, link)
	if CursorHasItem and CursorHasItem() then
		return false
	end
	if link then
		EquipByName(link, slot)
	else
		EquipByName(itemID, slot)
	end
	return EquippedID(slot) == itemID
end

local function UnequipSlot(slot)
	if not PickupInventoryItem then
		return
	end
	PickupInventoryItem(slot)
	if CursorHasItem and CursorHasItem() and PutItemInBackpack then
		PutItemInBackpack()
	end
	if CursorHasItem and CursorHasItem() and ClearCursor then
		ClearCursor()
	end
end

local function IsTwoHand(itemID, link)
	local loc
	if link or itemID then
		loc = select(9, ItemInfo(link or itemID))
	end
	if not loc and itemID then
		loc = select(4, ItemInfoInstant(itemID))
	end
	return loc == "INVTYPE_2HWEAPON"
end

local function ApplySwimGear()
	if InCombat() or UnitIsDeadOrGhost("player") then
		return
	end
	if SpellIsTargeting and SpellIsTargeting() then
		return
	end
	for i = 1, #SLOTS do
		local slot = SLOTS[i].id
		local saved = SavedSlot(slot)
		if saved and saved.id then
			if EquippedID(slot) ~= saved.id then
				RememberOriginal(slot)
				if IsTwoHand(saved.id) and slot == 16 then
					RememberOriginal(17)
				end
				if SlotOnCooldown(slot, saved.id) then
					-- wait until the worn or swim item CD is done
				elseif FindItemInBags(saved.id) then
					EquipID(saved.id, slot)
				else
					WarnMissing(saved.id, saved.name)
				end
			end
		end
	end
end

local function RestoreSlot(slot)
	local orig = db.originals[slot]
	if not orig then
		return true
	end
	local current = EquippedID(slot)
	if orig.empty then
		if not current then
			db.originals[slot] = nil
			return true
		end
		if SlotOnCooldown(slot, current) then
			return false
		end
		UnequipSlot(slot)
		if not EquippedID(slot) then
			db.originals[slot] = nil
			return true
		end
		return false
	end
	if not orig.id then
		db.originals[slot] = nil
		return true
	end
	if current == orig.id then
		db.originals[slot] = nil
		return true
	end
	if SlotOnCooldown(slot, orig.id) then
		return false
	end
	if FindItemInBags(orig.id) then
		EquipID(orig.id, slot, orig.link)
		if EquippedID(slot) == orig.id then
			db.originals[slot] = nil
			return true
		end
		return false
	end
	WarnMissing(orig.id, orig.name)
	return false
end

local function RestoreLandGear()
	if InCombat() or UnitIsDeadOrGhost("player") then
		return
	end
	if SpellIsTargeting and SpellIsTargeting() then
		return
	end
	local anyLeft
	for i = 1, #SLOTS do
		if not RestoreSlot(SLOTS[i].id) then
			anyLeft = true
		end
	end
	for slot in pairs(db.originals) do
		if not RestoreSlot(slot) then
			anyLeft = true
		end
	end
	return not anyLeft
end

local function HasOriginals()
	return db and db.originals and next(db.originals) ~= nil
end

local elapsedAcc = 0
local function OnTick(self, elapsed)
	elapsedAcc = elapsedAcc + elapsed
	if elapsedAcc < TICK then
		return
	end
	elapsedAcc = 0
	if not db then
		return
	end
	if not IsEnabled() then
		lastDryStart = nil
		if HasOriginals() then
			RestoreLandGear()
		end
		return
	end

	local wet = InWater()
	if wet then
		lastDryStart = nil
		ApplySwimGear()
		return
	end

	if not HasOriginals() then
		lastDryStart = nil
		return
	end

	local now = GetTime()
	if not lastDryStart then
		lastDryStart = now
	end
	if (now - lastDryStart) >= DelaySeconds() then
		RestoreLandGear()
	end
end

local function SlotTexture(info)
	if GetInventorySlotInfo then
		local _, tex = GetInventorySlotInfo(info.inv)
		if tex then
			return tex
		end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function PlayerClass()
	local _, class = UnitClass("player")
	return class
end

local function ArmorSubId(subclassID, subName)
	if subclassID and ARMOR_SUB_NAME[subclassID] then
		return subclassID
	end
	if type(subName) == "string" then
		return ARMOR_SUB_NAME[subName]
	end
end

local function ClassCanWearArmor(subclassID, subName)
	local class = PlayerClass()
	local allowed = class and CLASS_ARMOR[class]
	local subId = ArmorSubId(subclassID, subName)
	if not subId then
		return true
	end
	if not allowed then
		return true
	end
	return allowed[subId] == true
end

local function ClassCanWearShield()
	local class = PlayerClass()
	return class and SHIELD_CLASSES[class] == true
end

local function CanWearInSlot(slot, itemID, link)
	if not itemID then
		return false
	end
	local name, itemLink, _, _, reqLevel, className, subName, _, loc, _, _, classID, subclassID = ItemInfo(link or itemID)
	if not loc then
		-- GetItemInfoInstant: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
		local _, instantType, instantSub, instantLoc, _, instantClass, instantSubId = ItemInfoInstant(itemID)
		loc = loc or instantLoc
		className = className or instantType
		subName = subName or instantSub
		classID = classID or instantClass
		subclassID = subclassID or instantSubId
	end
	if reqLevel and UnitLevel("player") < reqLevel then
		return false
	end
	if not SlotFitsLoc(slot, loc) then
		return false
	end

	-- Armor: include every type this class can wear (hunter cloth+leather+mail, etc).
	-- Do not use IsEquippableItem here; some clients only treat the "best" type as equippable.
	if classID == 4 or className == "Armor" then
		if loc == "INVTYPE_CLOAK" or loc == "INVTYPE_NECK" or loc == "INVTYPE_FINGER" or loc == "INVTYPE_TRINKET" or loc == "INVTYPE_HOLDABLE" or loc == "INVTYPE_BODY" or loc == "INVTYPE_TABARD" then
			return true, name, itemLink or link
		end
		if loc == "INVTYPE_SHIELD" or subclassID == 6 or subName == "Shields" or subName == "Shield" then
			if not ClassCanWearShield() then
				return false
			end
			return true, name, itemLink or link
		end
		local subId = ArmorSubId(subclassID, subName)
		if subId then
			if not ClassCanWearArmor(subclassID, subName) then
				return false
			end
			return true, name, itemLink or link
		end
		return true, name, itemLink or link
	end

	if not IsEquippable(link or itemID) then
		return false
	end
	return true, name, itemLink or link
end

local function CollectItems(slot)
	local seen = {}
	local list = {}

	local function add(itemID, link)
		if not itemID or seen[itemID] then
			return
		end
		local ok, name, itemLink = CanWearInSlot(slot, itemID, link)
		if not ok then
			return
		end
		seen[itemID] = true
		local texture = select(10, ItemInfo(itemLink or itemID)) or select(5, ItemInfoInstant(itemID))
		list[#list + 1] = {
			id = itemID,
			name = name or ("item " .. itemID),
			link = itemLink or link,
			texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
			equipped = IsWearing(itemID),
		}
	end

	for bag = 0, BagSlotCount() do
		for bagSlot = 1, ContainerNumSlots(bag) do
			add(ContainerItemID(bag, bagSlot), ContainerItemLink(bag, bagSlot))
		end
	end
	add(EquippedID(slot), GetInventoryItemLink and GetInventoryItemLink("player", slot))

	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

local function SetBackdropColor(frame, r, g, b, a)
	if frame.SetBackdropColor then
		frame:SetBackdropColor(r, g, b, a)
	end
end

local function ApplyBackdrop(frame, r, g, b, a)
	if frame.SetBackdrop then
		frame:SetBackdrop(BACKDROP)
		frame:SetBackdropColor(r, g, b, a)
		frame:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
	end
end

local function RefreshSlotButtons()
	if not ui.slotButtons then
		return
	end
	for i = 1, #ui.slotButtons do
		local btn = ui.slotButtons[i]
		local saved = SavedSlot(btn.slotId)
		local selected = selectedSlot == btn.slotId
		if selected then
			SetBackdropColor(btn, 0.35, 0.28, 0.08, 0.95)
			btn:SetBackdropBorderColor(1, 0.82, 0, 1)
		else
			SetBackdropColor(btn, 0.08, 0.08, 0.1, 0.95)
			btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
		end
		if saved and saved.id then
			local tex = select(10, ItemInfo(saved.id)) or select(5, ItemInfoInstant(saved.id))
			btn.icon:SetTexture(tex or SlotTexture(SLOTS[i]))
			btn.label:SetText(btn.slotName .. "\n|cffaaaaaa" .. (saved.name or "?") .. "|r")
		else
			btn.icon:SetTexture(SlotTexture(SLOTS[i]))
			btn.label:SetText(btn.slotName)
		end
	end
end

local function ClearItemButtons()
	if not ui.itemButtons then
		return
	end
	for i = 1, #ui.itemButtons do
		ui.itemButtons[i]:Hide()
	end
end

local function RefreshItemList()
	if not ui.itemContent then
		return
	end
	ClearItemButtons()
	ui.itemButtons = ui.itemButtons or {}

	if not selectedSlot then
		ui.emptyText:SetText("Select a slot on the left.")
		ui.emptyText:Show()
		ui.itemContent:SetHeight(20)
		return
	end

	local items = CollectItems(selectedSlot)
	if #items == 0 then
		ui.emptyText:SetText("No wearable items for this slot in your bags.")
		ui.emptyText:Show()
		ui.itemContent:SetHeight(20)
		return
	end
	ui.emptyText:Hide()

	local saved = SavedSlot(selectedSlot)
	local height = 0
	for i = 1, #items do
		local item = items[i]
		local btn = ui.itemButtons[i]
		if not btn then
			btn = CreateFrame("Button", nil, ui.itemContent, "BackdropTemplate")
			btn:SetSize(280, 28)
			ApplyBackdrop(btn, 0.07, 0.07, 0.09, 0.95)
			btn.icon = btn:CreateTexture(nil, "ARTWORK")
			btn.icon:SetSize(22, 22)
			btn.icon:SetPoint("LEFT", 4, 0)
			btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
			btn.label:SetPoint("RIGHT", -6, 0)
			btn.label:SetJustifyH("LEFT")
			btn:SetScript("OnEnter", function(self)
				if self.link then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetHyperlink(self.link)
					GameTooltip:Show()
				end
			end)
			btn:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			btn:SetScript("OnClick", function(self)
				if not selectedSlot then
					return
				end
				db.slots[selectedSlot] = { id = self.itemID, name = self.itemName }
				Chat("saved " .. self.itemName .. " for " .. (ui.slotNameById[selectedSlot] or "slot"))
				RefreshSlotButtons()
				RefreshItemList()
			end)
			ui.itemButtons[i] = btn
		end
		btn:SetParent(ui.itemContent)
		btn:SetPoint("TOPLEFT", 0, -((i - 1) * 30))
		btn:Show()
		btn.itemID = item.id
		btn.itemName = item.name
		btn.link = item.link
		btn.icon:SetTexture(item.texture)
		if item.equipped then
			btn.label:SetText(item.name .. " (Equiped)")
		else
			btn.label:SetText(item.name)
		end
		if saved and saved.id == item.id then
			btn:SetBackdropBorderColor(0.2, 0.85, 0.35, 1)
			SetBackdropColor(btn, 0.08, 0.22, 0.1, 0.95)
		else
			btn:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
			SetBackdropColor(btn, 0.07, 0.07, 0.09, 0.95)
		end
		height = i * 30
	end
	ui.itemContent:SetHeight(math.max(height, 1))
end

local function RefreshStatus()
	if not ui.statusFS then
		return
	end
	if IsEnabled() then
		ui.statusFS:SetText("|cff66ff66ON|r  (left-click minimap to turn off)")
	else
		ui.statusFS:SetText("|cffff6666OFF|r  (left-click minimap to turn on)")
	end
end

local function DigitsOnly(text)
	text = text or ""
	local out = {}
	local dot
	for i = 1, #text do
		local ch = text:sub(i, i)
		if ch:match("%d") then
			out[#out + 1] = ch
		elseif ch == "." and not dot then
			dot = true
			out[#out + 1] = ch
		end
	end
	return table.concat(out)
end

local function CreateUI()
	if ui.frame then
		return
	end

	local frame = CreateFrame("Frame", "SwimmingGearFrame", UIParent, "BackdropTemplate")
	frame:SetSize(520, 470)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	ApplyBackdrop(frame, 0.05, 0.05, 0.07, 0.96)
	tinsert(UISpecialFrames, "SwimmingGearFrame")
	ui.frame = frame

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -12)
	title:SetText("Swimming Gear")

	local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("TOP", title, "BOTTOM", 0, -2)
	ui.statusFS = status

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	local help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", 14, -48)
	help:SetPoint("TOPRIGHT", -14, -48)
	help:SetJustifyH("LEFT")
	help:SetText("Off by default. Minimap fish: left-click on/off, right-click this window. Pick a slot, then a bag item. Worn in water (out of combat). Original gear returns after the delay.")

	local left = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	left:SetPoint("TOPLEFT", 12, -84)
	left:SetPoint("BOTTOMLEFT", 12, 52)
	left:SetWidth(188)
	ApplyBackdrop(left, 0.03, 0.03, 0.04, 0.9)
	ui.left = left

	local right = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
	right:SetPoint("BOTTOMRIGHT", -12, 52)
	ApplyBackdrop(right, 0.03, 0.03, 0.04, 0.9)

	local slotScroll = CreateFrame("ScrollFrame", "SwimmingGearSlotScroll", left, "UIPanelScrollFrameTemplate")
	slotScroll:SetPoint("TOPLEFT", 6, -6)
	slotScroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local slotContent = CreateFrame("Frame", nil, slotScroll)
	slotContent:SetSize(150, 1)
	slotScroll:SetScrollChild(slotContent)

	ui.slotButtons = {}
	ui.slotNameById = {}
	for i = 1, #SLOTS do
		local info = SLOTS[i]
		ui.slotNameById[info.id] = info.name
		local btn = CreateFrame("Button", nil, slotContent, "BackdropTemplate")
		btn:SetSize(148, 28)
		btn:SetPoint("TOPLEFT", 0, -((i - 1) * 30))
		ApplyBackdrop(btn, 0.08, 0.08, 0.1, 0.95)
		btn.slotId = info.id
		btn.slotName = info.name
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetSize(22, 22)
		btn.icon:SetPoint("LEFT", 4, 0)
		btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		btn.icon:SetTexture(SlotTexture(info))
		btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
		btn.label:SetPoint("RIGHT", -4, 0)
		btn.label:SetJustifyH("LEFT")
		btn.label:SetText(info.name)
		btn:SetScript("OnClick", function(self)
			selectedSlot = self.slotId
			RefreshSlotButtons()
			RefreshItemList()
		end)
		ui.slotButtons[i] = btn
	end
	slotContent:SetHeight(#SLOTS * 30)

	local itemScroll = CreateFrame("ScrollFrame", "SwimmingGearItemScroll", right, "UIPanelScrollFrameTemplate")
	itemScroll:SetPoint("TOPLEFT", 6, -6)
	itemScroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local itemContent = CreateFrame("Frame", nil, itemScroll)
	itemContent:SetSize(280, 1)
	itemScroll:SetScrollChild(itemContent)
	ui.itemContent = itemContent

	ui.emptyText = itemContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ui.emptyText:SetPoint("TOPLEFT", 4, -8)
	ui.emptyText:SetPoint("TOPRIGHT", -4, -8)
	ui.emptyText:SetJustifyH("LEFT")
	ui.emptyText:SetText("Select a slot on the left.")

	local delayLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	delayLabel:SetPoint("BOTTOMLEFT", 16, 18)
	delayLabel:SetText("Re-Equipe delay")

	local delayBox = CreateFrame("EditBox", "SwimmingGearDelayBox", frame, "InputBoxTemplate")
	delayBox:SetSize(54, 20)
	delayBox:SetPoint("LEFT", delayLabel, "RIGHT", 10, 0)
	delayBox:SetAutoFocus(false)
	delayBox:SetMaxLetters(6)
	delayBox:SetNumeric(false)
	delayBox:SetScript("OnTextChanged", function(self, userInput)
		if not userInput then
			return
		end
		local cleaned = DigitsOnly(self:GetText())
		if cleaned ~= self:GetText() then
			self:SetText(cleaned)
		end
	end)
	delayBox:SetScript("OnEnterPressed", function(self)
		local n = tonumber(DigitsOnly(self:GetText()))
		if not n then
			n = DEFAULT_DELAY
		end
		db.delay = n
		self:SetText(tostring(n))
		self:ClearFocus()
	end)
	delayBox:SetScript("OnEditFocusLost", function(self)
		local n = tonumber(DigitsOnly(self:GetText()))
		if not n then
			n = db.delay or DEFAULT_DELAY
		end
		db.delay = n
		self:SetText(tostring(n))
	end)
	ui.delayBox = delayBox

	local delayHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	delayHint:SetPoint("LEFT", delayBox, "RIGHT", 8, 0)
	delayHint:SetText("seconds out of water before original gear")

	local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clear:SetSize(90, 22)
	clear:SetPoint("BOTTOMRIGHT", -14, 14)
	clear:SetText("Clear slot")
	clear:SetScript("OnClick", function()
		if not selectedSlot then
			Chat("select a slot first")
			return
		end
		db.slots[selectedSlot] = nil
		if not InCombat() then
			RestoreSlot(selectedSlot)
		end
		Chat("cleared " .. (ui.slotNameById[selectedSlot] or "slot"))
		RefreshSlotButtons()
		RefreshItemList()
	end)

	frame:SetScript("OnShow", function()
		if ui.delayBox then
			ui.delayBox:SetText(tostring(DelaySeconds()))
		end
		RefreshStatus()
		RefreshSlotButtons()
		RefreshItemList()
	end)
end

local function ToggleUI()
	CreateUI()
	if ui.frame:IsShown() then
		ui.frame:Hide()
	else
		ui.frame:Show()
	end
end

local ldbPlugin

local function UpdateMinimapLook()
	if not ldbPlugin then
		return
	end
	if IsEnabled() then
		ldbPlugin.iconR, ldbPlugin.iconG, ldbPlugin.iconB = 1, 1, 1
	else
		ldbPlugin.iconR, ldbPlugin.iconG, ldbPlugin.iconB = 0.55, 0.55, 0.55
	end
end

local function ToggleEnabled()
	EnsureDB()
	db.enabled = not IsEnabled()
	if IsEnabled() then
		Chat("on")
		if InWater() then
			ApplySwimGear()
		end
	else
		Chat("off")
		if HasOriginals() and not InCombat() then
			RestoreLandGear()
		end
	end
	UpdateMinimapLook()
	RefreshStatus()
end

local function SetupMinimapIcon()
	if ldbPlugin then
		return
	end
	EnsureDB()
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	local icon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not ldb or not icon then
		return
	end
	ldbPlugin = ldb:NewDataObject("SwimmingGear", {
		type = "launcher",
		label = "Swimming Gear",
		icon = "Interface\\Icons\\INV_Misc_Fish_02",
		OnClick = function(_, button)
			if button == "RightButton" then
				EnsureDB()
				CreateUI()
				ui.frame:Show()
				return
			end
			if button == "LeftButton" then
				ToggleEnabled()
			end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine("|cff33ccffSwimming Gear|r")
			tt:AddLine(IsEnabled() and "Currently: ON" or "Currently: OFF", 0.8, 0.8, 0.8)
			tt:AddLine("Left-click: on/off", 0.2, 1, 0.2)
			tt:AddLine("Right-click: config", 0.2, 1, 0.2)
		end,
	})
	icon:Register("SwimmingGear", ldbPlugin, db.minimapIcon)
	UpdateMinimapLook()
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("BAG_UPDATE_DELAYED")
driver:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
driver:RegisterEvent("GET_ITEM_INFO_RECEIVED")
driver:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		EnsureDB()
		driver:SetScript("OnUpdate", OnTick)
		SetupMinimapIcon()
	elseif event == "PLAYER_ENTERING_WORLD" then
		EnsureDB()
		SetupMinimapIcon()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if not IsEnabled() then
			if HasOriginals() then
				RestoreLandGear()
			end
			return
		end
		if InWater() then
			ApplySwimGear()
		elseif HasOriginals() then
			lastDryStart = lastDryStart or GetTime()
		end
	elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "GET_ITEM_INFO_RECEIVED" then
		if ui.frame and ui.frame:IsShown() then
			RefreshSlotButtons()
			RefreshItemList()
		end
	end
end)

SLASH_SWIMMINGGEAR1 = "/swimg"
SLASH_SWIMMINGGEAR2 = "/swimgear"
SlashCmdList.SWIMMINGGEAR = function()
	EnsureDB()
	ToggleUI()
end
