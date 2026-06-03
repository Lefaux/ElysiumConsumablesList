local addonName = ...

ElysiumConsumablesListDB = ElysiumConsumablesListDB or {}
ElysiumConsumablesListTemplatesDB = ElysiumConsumablesListTemplatesDB or {}

local DEFAULT_POINT = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 340,
    y = 180,
}

local DEFAULT_CONFIG_POINT = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 580,
    y = 280,
}

local NUM_BAG_SLOTS = 4
local DEFAULT_ROWS = 1
local MAIN_FRAME_WIDTH = 640
local MAIN_BODY_WIDTH = 600
local MAIN_MIN_WIDTH = 620
local MAIN_MIN_HEIGHT = 240
local RESIZE_GRIP_SIZE = 16
local CONFIG_FRAME_WIDTH = 760
local CONFIG_FRAME_HEIGHT = 520
local ROW_HEIGHT = 20
local ROW_PADDING = 6
local MAIN_HEADER_HEIGHT = 16

ElysiumConsumablesListTemplates = ElysiumConsumablesListTemplates or {
    templates = {},
    sharedItems = {},
    order = {},
}

local TEMPLATE_REGISTRY = ElysiumConsumablesListTemplates
local TEMPLATES = TEMPLATE_REGISTRY.templates
local UNIVERSAL_TEMPLATE_ITEMS = TEMPLATE_REGISTRY.sharedItems

local BUILTIN_TEMPLATE_ORDER = {"fury_warrior", "holy_paladin"}

local state = {
    mainFrame = nil,
    mainTitle = nil,
    mainBody = nil,
    mainHeader = nil,
    mainScrollFrame = nil,
    mainScrollChild = nil,
    mainRows = {},
    mainClose = nil,
    mainConfigButton = nil,
    configFrame = nil,
    configScrollFrame = nil,
    configScrollChild = nil,
    configRows = {},
    configAddButton = nil,
    configCloseButton = nil,
    configSaveTemplateButton = nil,
    configShareTemplateButton = nil,
    minimapButton = nil,
    exportFrame = nil,
    exportScrollFrame = nil,
    exportEditBox = nil,
    shareTemplateFrame = nil,
    shareTemplateScrollFrame = nil,
    shareTemplateEditBox = nil,
    mainRefreshQueued = false,
}

local ensureMainFrame
local showMainFrame
local showConfigFrame
local showExportFrame
local getTemplateLabel

local function makeStorageKey()
    local name = UnitName("player") or "unknown"
    local realm = GetRealmName() or "unknown"
    return name .. "@" .. realm
end

local function getDefaultTemplateKey()
    local _, class = UnitClass("player")
    if class == "WARRIOR" then
        return "fury_warrior"
    elseif class == "PALADIN" then
        return "holy_paladin"
    end

    return nil
end

local function ensureRootDB()
    if type(ElysiumConsumablesListDB) ~= "table" then
        ElysiumConsumablesListDB = {}
    end
end

local function ensureTemplateDB()
    if type(ElysiumConsumablesListTemplatesDB) ~= "table" then
        ElysiumConsumablesListTemplatesDB = {}
    end

    ElysiumConsumablesListTemplatesDB.templates = type(ElysiumConsumablesListTemplatesDB.templates) == "table" and ElysiumConsumablesListTemplatesDB.templates or {}
    ElysiumConsumablesListTemplatesDB.order = type(ElysiumConsumablesListTemplatesDB.order) == "table" and ElysiumConsumablesListTemplatesDB.order or {}

    return ElysiumConsumablesListTemplatesDB
end

local function ensurePersonalTemplatesLoaded()
    local db = ensureTemplateDB()

    for key, template in pairs(db.templates) do
        if type(template) == "table" and TEMPLATES[key] == nil then
            TEMPLATES[key] = {
                label = template.label,
                description = template.description,
                items = {},
            }

            for _, item in ipairs(template.items or {}) do
                table.insert(TEMPLATES[key].items, {
                    itemId = item.itemId,
                    itemIds = item.itemIds and {unpack(item.itemIds)} or nil,
                    label = item.label,
                    desiredCount = item.desiredCount or DEFAULT_ROWS,
                    source = item.source,
                    spellId = item.spellId,
                    chargesPerItem = item.chargesPerItem,
                })
            end
        end
    end
end

local function getOrderedTemplateKeys()
    ensurePersonalTemplatesLoaded()

    local keys = {}
    local seen = {}

    local function addKey(key)
        if key and not seen[key] and TEMPLATES[key] then
            seen[key] = true
            table.insert(keys, key)
        end
    end

    for _, key in ipairs(BUILTIN_TEMPLATE_ORDER) do
        addKey(key)
    end

    for _, key in ipairs(ensureTemplateDB().order) do
        addKey(key)
    end

    for key in pairs(TEMPLATES) do
        addKey(key)
    end

    return keys
end

local function sanitizeTemplateKey(text)
    local key = string.lower(tostring(text or ""))
    key = key:gsub("[^%w]+", "_")
    key = key:gsub("^_+", "")
    key = key:gsub("_+$", "")

    if key == "" then
        key = "personal_template"
    end

    if key:match("^%d") then
        key = "template_" .. key
    end

    return "personal_" .. key
end

local function quoteLuaString(text)
    return string.format("%q", tostring(text or ""))
end

local function getPersonalTemplateDisplayName(storage)
    local templateKey = storage and storage.templateKey or nil
    local label = getTemplateLabel(templateKey or "")

    if label == "Custom" then
        return "Personal Template"
    end

    if templateKey and string.sub(templateKey, 1, 9) == "personal_" then
        return label
    end

    return "Personal " .. label
end

local function cloneTemplateItem(item)
    if not item then
        return nil
    end

    return {
        itemId = item.itemId,
        itemIds = item.itemIds and {unpack(item.itemIds)} or nil,
        label = item.label,
        desiredCount = item.desiredCount or DEFAULT_ROWS,
        source = item.source,
        spellId = item.spellId,
        chargesPerItem = item.chargesPerItem,
    }
end

local function cloneTemplateDefinition(definition)
    if type(definition) ~= "table" then
        return nil
    end

    local clone = {
        label = definition.label,
        description = definition.description,
        items = {},
    }

    for _, item in ipairs(definition.items or {}) do
        local clonedItem = cloneTemplateItem(item)
        if clonedItem then
            table.insert(clone.items, clonedItem)
        end
    end

    return clone
end

local function buildTemplateItemsFromStorage(storage)
    local items = {}

    for _, item in ipairs(storage.items or {}) do
        if item.enabled ~= false then
            local cloned = cloneTemplateItem(item)
            if cloned and (cloned.itemId or (type(cloned.itemIds) == "table" and #cloned.itemIds > 0)) then
                table.insert(items, cloned)
            end
        end
    end

    return items
end

local function savePersonalTemplate(templateLabel, items)
    local db = ensureTemplateDB()
    local key = sanitizeTemplateKey(templateLabel)
    local definition = {
        label = templateLabel,
        description = "Personal consumables template saved from ElysiumConsumablesList.",
        items = {},
    }

    for _, item in ipairs(items or {}) do
        local cloned = cloneTemplateItem(item)
        if cloned then
            table.insert(definition.items, cloned)
        end
    end

    db.templates[key] = cloneTemplateDefinition(definition)

    local found = false
    for _, existingKey in ipairs(db.order) do
        if existingKey == key then
            found = true
            break
        end
    end
    if not found then
        table.insert(db.order, key)
    end

    TEMPLATES[key] = cloneTemplateDefinition(definition)

    return key
end

local function deletePersonalTemplate(templateKey)
    if not templateKey or string.sub(templateKey, 1, 9) ~= "personal_" then
        return false
    end

    local db = ensureTemplateDB()
    db.templates[templateKey] = nil

    if type(db.order) == "table" then
        for index = #db.order, 1, -1 do
            if db.order[index] == templateKey then
                table.remove(db.order, index)
            end
        end
    end

    TEMPLATES[templateKey] = nil
    return true
end

local function ensureCharacterStorage()
    ensureRootDB()
    ensurePersonalTemplatesLoaded()

    local key = makeStorageKey()
    local storage = ElysiumConsumablesListDB[key]
    local isNewStorage = false

    if type(storage) ~= "table" then
        storage = {}
        ElysiumConsumablesListDB[key] = storage
        isNewStorage = true
    end

    local defaultTemplateKey = getDefaultTemplateKey()

    if storage.templateKey == nil then
        storage.templateKey = defaultTemplateKey
    end

    if isNewStorage and storage.templateKey then
        storage.items = cloneTemplateItems(storage.templateKey)
    else
        storage.items = storage.items or {}
    end

    storage.includeBank = storage.includeBank ~= false
    if storage.hideOnCharacter == nil then
        if storage.showCompleted ~= nil then
            storage.hideOnCharacter = not storage.showCompleted
        else
            storage.hideOnCharacter = false
        end
    end
    storage.showCompleted = not storage.hideOnCharacter
    storage.point = storage.point or {
        point = DEFAULT_POINT.point,
        relativePoint = DEFAULT_POINT.relativePoint,
        x = DEFAULT_POINT.x,
        y = DEFAULT_POINT.y,
    }
    storage.configPoint = storage.configPoint or {
        point = DEFAULT_CONFIG_POINT.point,
        relativePoint = DEFAULT_CONFIG_POINT.relativePoint,
        x = DEFAULT_CONFIG_POINT.x,
        y = DEFAULT_CONFIG_POINT.y,
    }
    storage.mainSize = storage.mainSize or {
        width = MAIN_FRAME_WIDTH,
        height = 340,
    }
    if storage.mainVisible == nil then
        storage.mainVisible = true
    end
    storage.minimap = storage.minimap or {
        visible = true,
        position = 225,
        distance = 1,
    }
    storage.bankCounts = type(storage.bankCounts) == "table" and storage.bankCounts or {}

    return storage
end

local function cloneTemplateItems(templateKey)
    ensurePersonalTemplatesLoaded()

    local template = TEMPLATES[templateKey]
    if not template then
        return {}
    end

    local items = {}
    for _, item in ipairs(template.items or {}) do
        local cloned = cloneTemplateItem(item)
        if cloned then
            cloned.enabled = true
            table.insert(items, cloned)
        end
    end

    for _, item in ipairs(UNIVERSAL_TEMPLATE_ITEMS) do
        local cloned = cloneTemplateItem(item)
        if cloned then
            cloned.enabled = true
            table.insert(items, cloned)
        end
    end

    return items
end

local function applyTemplate(templateKey, replaceItems)
    local storage = ensureCharacterStorage()
    storage.templateKey = templateKey

    if replaceItems ~= false then
        storage.items = cloneTemplateItems(templateKey)
    end
end

getTemplateLabel = function(templateKey)
    ensurePersonalTemplatesLoaded()

    local template = TEMPLATES[templateKey]
    if template then
        return template.label
    end

    return "Custom"
end

local function refreshTemplateDropdownText(dropdown)
    if not dropdown then
        return
    end

    local storage = ensureCharacterStorage()
    local templateKey = storage.templateKey or "fury_warrior"
    UIDropDownMenu_SetText(dropdown, getTemplateLabel(templateKey))
end

local function refreshTemplateManagementButtons(frame)
    if not frame then
        return
    end

    local storage = ensureCharacterStorage()
    local templateKey = storage.templateKey or ""
    local isPersonal = string.sub(templateKey, 1, 9) == "personal_"

    if frame.deleteTemplateButton then
        frame.deleteTemplateButton:SetShown(isPersonal)
    end

    if frame.saveTemplateButton then
        frame.saveTemplateButton:SetText(isPersonal and "Update personal template" or "Save as personal template")
    end
end

local function initializeTemplateDropdown(dropdown)
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local storage = ensureCharacterStorage()
        local templateKey = storage.templateKey or "fury_warrior"

        for _, key in ipairs(getOrderedTemplateKeys()) do
            local template = TEMPLATES[key]
            local info = UIDropDownMenu_CreateInfo()
            info.text = template.label
            info.value = key
            info.checked = key == templateKey
            info.func = function(button)
                storage.templateKey = button.value
                refreshTemplateDropdownText(dropdown)
                refreshTemplateManagementButtons(state.configFrame)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UIDropDownMenu_SetWidth(dropdown, 180)
    refreshTemplateDropdownText(dropdown)
end

local function getItemResolvedName(item)
    if not item then
        return "Unknown item"
    end

    local itemIds = item.itemIds
    if type(itemIds) == "table" and #itemIds > 0 then
        local names = {}

        for _, itemId in ipairs(itemIds) do
            local itemName = GetItemInfo(itemId)
            if itemName and itemName ~= "" then
                table.insert(names, itemName)
            else
                table.insert(names, "Item " .. tostring(itemId))
            end
        end

        return table.concat(names, " / ")
    end

    if item.itemId then
        local itemName = GetItemInfo(item.itemId)
        if itemName and itemName ~= "" then
            return itemName
        end

        return "Item " .. tostring(item.itemId)
    end

    return "Unknown item"
end

local function getItemDisplayName(item)
    if not item then
        return "Unknown item"
    end

    if item.label and item.label ~= "" then
        return item.label
    end

    if type(item.itemIds) == "table" and #item.itemIds > 0 then
        local firstName = GetItemInfo(item.itemIds[1])
        if firstName and firstName ~= "" then
            return firstName
        end

        return "Item group"
    end

    if item.itemId and item.itemId > 0 then
        return getItemResolvedName(item)
    end

    return "Unconfigured item"
end

local function getItemSortInfo(item)
    local itemId = item and (item.itemId or (type(item.itemIds) == "table" and item.itemIds[1]))
    local sortName = string.lower(getItemDisplayName(item) or "")

    if not itemId then
        return {
            className = "Miscellaneous",
            subclassName = "Unconfigured",
            sortClass = "zzzz",
            sortSubclass = "zzzz",
            sortName = sortName,
        }
    end

    local _, _, _, _, _, itemClass, itemSubClass = GetItemInfo(itemId)
    return {
        className = itemClass or "Miscellaneous",
        subclassName = itemSubClass or "Other",
        sortClass = string.lower(itemClass or "zzz"),
        sortSubclass = string.lower(itemSubClass or "zzz"),
        sortName = sortName ~= "" and sortName or string.lower("item-" .. tostring(itemId)),
    }
end

local function getContainerNumSlotsCompat(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end

    if GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end

    return 0
end

local function getContainerItemIDCompat(bag, slot)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    end

    if GetContainerItemID then
        return GetContainerItemID(bag, slot)
    end

    return nil
end

local function getContainerItemStackCountCompat(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.stackCount then
            return info.stackCount
        end
    end

    if GetContainerItemInfo then
        local _, count = GetContainerItemInfo(bag, slot)
        if type(count) == "number" and count > 0 then
            return count
        end
    end

    return 1
end

local function isBankAccessible()
    if BankFrame and BankFrame:IsShown() then
        return true
    end

    if type(IsBagSlotUnlocked) == "function" and NUM_BANKBAGSLOTS then
        local bagIndex = NUM_BAG_SLOTS + 1
        local success, unlocked = pcall(IsBagSlotUnlocked, bagIndex)
        if success and unlocked then
            return true
        end
    end

    return false
end

local function countItemInBagRange(itemId, bagStart, bagEnd)
    local total = 0

    for bag = bagStart, bagEnd do
        local slotCount = getContainerNumSlotsCompat(bag)
        for slot = 1, slotCount do
            if getContainerItemIDCompat(bag, slot) == itemId then
                total = total + getContainerItemStackCountCompat(bag, slot)
            end
        end
    end

    return total
end

local function refreshBankCache(storage)
    if not storage or not isBankAccessible() then
        return
    end

    storage.bankCounts = storage.bankCounts or {}

    local uniqueIds = {}
    for _, item in ipairs(storage.items or {}) do
        if type(item.itemIds) == "table" and #item.itemIds > 0 then
            for _, itemId in ipairs(item.itemIds) do
                uniqueIds[itemId] = true
            end
        elseif item.itemId then
            uniqueIds[item.itemId] = true
        end
    end

    for itemId in pairs(uniqueIds) do
        local mainBankCount = countItemInBagRange(itemId, BANK_CONTAINER or -1, BANK_CONTAINER or -1)
        local bagBankCount = countItemInBagRange(itemId, NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + (NUM_BANKBAGSLOTS or 7))
        storage.bankCounts[itemId] = mainBankCount + bagBankCount
    end
end

local function getBankCountForItem(itemId, storage)
    if not itemId then
        return 0
    end

    if isBankAccessible() then
        local mainBankCount = countItemInBagRange(itemId, BANK_CONTAINER or -1, BANK_CONTAINER or -1)
        local bagBankCount = countItemInBagRange(itemId, NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + (NUM_BANKBAGSLOTS or 7))
        return mainBankCount + bagBankCount
    end

    if storage and type(storage.bankCounts) == "table" then
        return tonumber(storage.bankCounts[itemId]) or 0
    end

    return 0
end

local function getSingleItemCounts(itemId, includeUses, includeBank)
    local charCount = countItemInBagRange(itemId, 0, 4)
    local bankCount = 0

    if includeBank then
        bankCount = getBankCountForItem(itemId, ensureCharacterStorage())
    end

    local total = charCount + bankCount

    if includeUses then
        -- Charges are counted as stack quantity in the bag scan, so no special handling here.
    end

    return charCount, bankCount, total, true
end

local function getItemCounts(item, includeBank)
    if not item then
        return 0, 0, 0, false
    end

    local itemIds = type(item.itemIds) == "table" and item.itemIds or nil

    local candidates = {}
    if itemIds and #itemIds > 0 then
        candidates = itemIds
    elseif item.itemId then
        candidates = {item.itemId}
    end

    local storage = ensureCharacterStorage()
    local charCount = 0
    local bankCount = 0

    for _, itemId in ipairs(candidates) do
        charCount = charCount + countItemInBagRange(itemId, 0, 4)
        if includeBank then
            bankCount = bankCount + getBankCountForItem(itemId, storage)
        end
    end

    if item.chargesPerItem then
        charCount = charCount * item.chargesPerItem
        bankCount = bankCount * item.chargesPerItem
    end

    return charCount, bankCount, charCount + bankCount, true
end

local function isItemCraftable(item)
    if not item or item.source ~= "craft" or not item.spellId then
        return false
    end

    local spellId = item.spellId
    local targetName = GetSpellInfo and GetSpellInfo(spellId) or nil

    if type(IsSpellKnown) == "function" then
        local ok, known = pcall(IsSpellKnown, spellId)
        if ok and known then
            return true
        end
    end

    if type(IsPlayerSpell) == "function" then
        local ok, known = pcall(IsPlayerSpell, spellId)
        if ok and known then
            return true
        end
    end

    if targetName and type(GetNumSpellTabs) == "function" and type(GetSpellTabInfo) == "function" and type(GetSpellBookItemName) == "function" then
        local numTabs = GetNumSpellTabs() or 0
        for tab = 1, numTabs do
            local _, _, offset, numSpells = GetSpellTabInfo(tab)
            if offset and numSpells then
                for slot = offset + 1, offset + numSpells do
                    local bookName = GetSpellBookItemName(slot, BOOKTYPE_SPELL)
                    if bookName == targetName then
                        return true
                    end
                    local professionName = GetSpellBookItemName(slot, BOOKTYPE_PROFESSION)
                    if professionName == targetName then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function getItemStateData(item, includeBank)
    local desired = tonumber(item and item.desiredCount) or 0
    local charCount, bankCount, totalCount = getItemCounts(item, includeBank)
    local source = item and item.source or "buy"
    local craftable = isItemCraftable(item)
    local stateKey = "red"
    local stateLabel = "BUY"
    local stateColor = "ff5555"

    if desired > 0 and charCount >= desired then
        stateKey = "green"
        stateLabel = "HAVE"
        stateColor = "33dd55"
    elseif desired > 0 and totalCount >= desired and bankCount > 0 then
        stateKey = "yellow"
        stateLabel = "BANK"
        stateColor = "ffff00"
    elseif desired > 0 and craftable then
        stateKey = "gold"
        stateLabel = "CRAFT"
        stateColor = "ffd700"
    end

    local missing = math.max(desired - totalCount, 0)
    local progressText

    if stateKey == "green" then
        progressText = string.format("%d/%d on char", charCount, desired)
    elseif stateKey == "yellow" then
        progressText = string.format("%d/%d on char, %d in bank", charCount, desired, bankCount)
    elseif stateKey == "gold" then
        progressText = string.format("craft %d", missing)
    else
        progressText = string.format("buy %d", missing)
    end

    local sourceText = "Buy/Loot"
    if source == "craft" and craftable then
        sourceText = "Craft"
    end

    if source == "craft" and not craftable and stateKey ~= "green" and stateKey ~= "yellow" then
        stateKey = "red"
        stateLabel = "BUY"
        stateColor = "ff5555"
        progressText = string.format("buy %d", missing)
    end

    return {
        stateKey = stateKey,
        stateLabel = stateLabel,
        stateColor = stateColor,
        progressText = progressText,
        sourceText = sourceText,
        charCount = charCount,
        bankCount = bankCount,
        totalCount = totalCount,
        desired = desired,
    }
end

local getBagCountForItem

getBagCountForItem = function(itemId, includeBank)
    if not itemId or itemId <= 0 then
        return 0
    end

    local total = countItemInBagRange(itemId, 0, 4)

    if includeBank and isBankAccessible() then
        total = total + countItemInBagRange(itemId, NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + (NUM_BANKBAGSLOTS or 7))
    end

    return total
end

local function ensureMainRows(count)
    local child = state.mainScrollChild
    if not child then
        return
    end

    while #state.mainRows < count do
        local index = #state.mainRows + 1
        local row = CreateFrame("Frame", nil, child)
        row:SetHeight(ROW_HEIGHT)
        row:SetWidth(MAIN_BODY_WIDTH)

        local status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetPoint("LEFT", 4, 0)
        status:SetWidth(48)
        status:SetJustifyH("LEFT")
        row.status = status

        local item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        item:SetPoint("LEFT", status, "RIGHT", 6, 0)
        item:SetWidth(220)
        item:SetJustifyH("LEFT")
        row.item = item

        local progress = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        progress:SetPoint("LEFT", item, "RIGHT", 6, 0)
        progress:SetWidth(160)
        progress:SetJustifyH("LEFT")
        row.progress = progress

        local source = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        source:SetPoint("LEFT", progress, "RIGHT", 6, 0)
        source:SetWidth(80)
        source:SetJustifyH("LEFT")
        row.source = source

        state.mainRows[index] = row
    end
end

local getColorComponents

local function setMainRowValues(row, item, data)
    if not row or not item or not data then
        return
    end

    local r, g, b = getColorComponents(data.stateColor)
    row.status:SetText(data.stateLabel)
    row.status:SetTextColor(r, g, b)
    row.item:SetText(getItemDisplayName(item))
    row.item:SetTextColor(r, g, b)
    row.progress:SetText(data.progressText)
    row.progress:SetTextColor(r, g, b)
    row.source:SetText(data.sourceText)
    row.source:SetTextColor(0.8, 0.8, 0.8)
    row:Show()
end

local function setMainGroupRowValues(row, label)
    if not row then
        return
    end

    row.status:SetText("Group")
    row.status:SetTextColor(0.6, 0.6, 0.6)
    row.item:SetText(label or "")
    row.item:SetTextColor(0.9, 0.9, 0.9)
    row.progress:SetText("")
    row.source:SetText("")
    row:Show()
end

local function escapeAuctionatorText(text)
    return tostring(text or ""):gsub('"', '\\"')
end

local function formatTemplateItemForLua(item)
    local parts = {}

    if type(item.itemIds) == "table" and #item.itemIds > 0 then
        table.insert(parts, "itemIds = {" .. table.concat(item.itemIds, ", ") .. "}")
    elseif item.itemId then
        table.insert(parts, "itemId = " .. tostring(item.itemId))
    end

    if item.desiredCount and item.desiredCount ~= DEFAULT_ROWS then
        table.insert(parts, "desiredCount = " .. tostring(item.desiredCount))
    elseif item.desiredCount then
        table.insert(parts, "desiredCount = " .. tostring(item.desiredCount))
    end

    if item.source then
        table.insert(parts, "source = " .. quoteLuaString(item.source))
    end

    if item.spellId then
        table.insert(parts, "spellId = " .. tostring(item.spellId))
    end

    if item.chargesPerItem then
        table.insert(parts, "chargesPerItem = " .. tostring(item.chargesPerItem))
    end

    if item.label and item.label ~= "" then
        table.insert(parts, "label = " .. quoteLuaString(item.label))
    end

    return "        {" .. table.concat(parts, ", ") .. "},"
end

local function buildTemplateLuaExportText(storage, templateLabel)
    local label = tostring(templateLabel or "Personal Template")
    local key = sanitizeTemplateKey(label)
    local items = buildTemplateItemsFromStorage(storage)
    local lines = {
        "ElysiumConsumablesListTemplates = ElysiumConsumablesListTemplates or {",
        "    templates = {},",
        "    sharedItems = {},",
        "    order = {},",
        "}",
        "",
        "local registry = ElysiumConsumablesListTemplates",
        "",
        "registry.templates." .. key .. " = {",
        "    label = " .. quoteLuaString(label) .. ",",
        "    description = " .. quoteLuaString("Personal consumables template saved from ElysiumConsumablesList.") .. ",",
        "    items = {",
    }

    for _, item in ipairs(items) do
        table.insert(lines, formatTemplateItemForLua(item))
    end

    table.insert(lines, "    },")
    table.insert(lines, "}")

    return table.concat(lines, "\n")
end

local function buildAuctionatorExportText(storage)
    local items = storage.items or {}
    local sortedItems = {}

    for _, item in ipairs(items) do
        if item.enabled ~= false then
            table.insert(sortedItems, item)
        end
    end

    table.sort(sortedItems, function(left, right)
        local leftInfo = getItemSortInfo(left)
        local rightInfo = getItemSortInfo(right)

        if leftInfo.sortClass ~= rightInfo.sortClass then
            return leftInfo.sortClass < rightInfo.sortClass
        end

        if leftInfo.sortSubclass ~= rightInfo.sortSubclass then
            return leftInfo.sortSubclass < rightInfo.sortSubclass
        end

        if leftInfo.sortName ~= rightInfo.sortName then
            return leftInfo.sortName < rightInfo.sortName
        end

        return (tonumber(left.itemId) or 0) < (tonumber(right.itemId) or 0)
    end)

    local missingItems = {}

    for _, item in ipairs(sortedItems) do
        local hasConfiguredItem = (type(item.itemIds) == "table" and #item.itemIds > 0) or (tonumber(item.itemId) and tonumber(item.itemId) > 0)
        if hasConfiguredItem then
            local data = getItemStateData(item, true)
            if data.desired and data.totalCount and data.totalCount < data.desired then
                table.insert(missingItems, getItemDisplayName(item))
            end
        end
    end

    if #missingItems == 0 then
        return "No missing items."
    end

    local parts = {"Consumables to Buy"}
    for _, name in ipairs(missingItems) do
        table.insert(parts, '"' .. escapeAuctionatorText(name) .. '"')
    end

    return table.concat(parts, "^")
end

local function collectMainRows(storage)
    local rows = {}
    local items = storage.items or {}
    local includeBank = true
    local hideOnCharacter = storage.hideOnCharacter == true

    local enabledItems = 0
    local greenItems = 0
    local yellowItems = 0
    local pendingItems = 0
    local sortedItems = {}

    for _, item in ipairs(items) do
        if item.enabled ~= false then
            enabledItems = enabledItems + 1
            table.insert(sortedItems, item)
        end
    end

    table.sort(sortedItems, function(left, right)
        local leftInfo = getItemSortInfo(left)
        local rightInfo = getItemSortInfo(right)

        if leftInfo.sortClass ~= rightInfo.sortClass then
            return leftInfo.sortClass < rightInfo.sortClass
        end

        if leftInfo.sortSubclass ~= rightInfo.sortSubclass then
            return leftInfo.sortSubclass < rightInfo.sortSubclass
        end

        if leftInfo.sortName ~= rightInfo.sortName then
            return leftInfo.sortName < rightInfo.sortName
        end

        return (tonumber(left.itemId) or 0) < (tonumber(right.itemId) or 0)
    end)

    local groupedItems = {}
    local groupOrder = {}

    for _, item in ipairs(sortedItems) do
        local hasConfiguredItem = (type(item.itemIds) == "table" and #item.itemIds > 0) or (tonumber(item.itemId) and tonumber(item.itemId) > 0)
        local data

        if hasConfiguredItem then
            data = getItemStateData(item, includeBank)
        else
            data = {
                stateKey = "red",
                stateLabel = "BUY",
                stateColor = "ff5555",
                progressText = "needs item ID",
                sourceText = "Config",
            }
        end

        if data.stateKey == "green" then
            greenItems = greenItems + 1
        elseif data.stateKey == "yellow" then
            yellowItems = yellowItems + 1
        else
            pendingItems = pendingItems + 1
        end

        local sortInfo = getItemSortInfo(item)
        local groupLabel = sortInfo.className .. " / " .. sortInfo.subclassName
        if not groupedItems[groupLabel] then
            groupedItems[groupLabel] = {}
            table.insert(groupOrder, groupLabel)
        end
        table.insert(groupedItems[groupLabel], {item = item, data = data})
    end

    for _, groupLabel in ipairs(groupOrder) do
        local groupRows = groupedItems[groupLabel]
        local visibleRows = {}
        for _, entry in ipairs(groupRows) do
            if not hideOnCharacter or entry.data.stateKey ~= "green" then
                table.insert(visibleRows, entry)
            end
        end

        if #visibleRows > 0 then
            table.insert(rows, {group = true, label = groupLabel})
            for _, entry in ipairs(visibleRows) do
                table.insert(rows, entry)
            end
        end
    end

    return rows, {
        enabledItems = enabledItems,
        greenItems = greenItems,
        yellowItems = yellowItems,
        pendingItems = pendingItems,
    }
end

getColorComponents = function(colorHex)
    local r = tonumber(colorHex:sub(1, 2), 16) / 255
    local g = tonumber(colorHex:sub(3, 4), 16) / 255
    local b = tonumber(colorHex:sub(5, 6), 16) / 255
    return r, g, b
end

local function buildSummaryText(stats)
    if stats.enabledItems == 0 then
        return "|cffffcc00No consumables configured.|r"
    end

    if stats.pendingItems == 0 and stats.yellowItems == 0 then
        return "|cff33dd55All consumable on character. Well done!|r"
    end

    if stats.pendingItems == 0 and stats.yellowItems > 0 then
        return string.format("|cff33dd55All consumables available.|r |cffffff00%d in bank.|r", stats.yellowItems)
    end

    return string.format("|cff00ff00%d configured|r, |cffffff00%d in bank|r, |cffff5555%d need attention|r", stats.enabledItems, stats.yellowItems, stats.pendingItems)
end

local function layoutMainFrame()
    local frame = state.mainFrame
    local title = state.mainTitle
    local body = state.mainBody
    local header = state.mainHeader
    local scrollFrame = state.mainScrollFrame
    local scrollChild = state.mainScrollChild

    if not frame or not title or not body or not header or not scrollFrame or not scrollChild or not state.mainConfigButton then
        return
    end

    local usableWidth = math.max(MAIN_BODY_WIDTH, frame:GetWidth() - 40)

    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", 14, -12)

    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    body:SetWidth(usableWidth)

    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -8)
    header:SetWidth(usableWidth)

    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 40)
    local scrollWidth = math.max(MAIN_BODY_WIDTH, (frame:GetWidth() or MAIN_BODY_WIDTH) - 44)
    scrollChild:SetWidth(scrollWidth)

    for index, row in ipairs(state.mainRows) do
        row:ClearAllPoints()
        row:SetWidth(scrollWidth)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
    end

    local contentHeight = math.max(ROW_HEIGHT, (state.mainVisibleRowCount or 0) * ROW_HEIGHT)
    scrollChild:SetHeight(contentHeight)
end

local function refreshMainFrame()
    local frame = state.mainFrame
    if not frame or not state.mainBody or not state.mainHeader then
        return
    end

    local storage = ensureCharacterStorage()
    if isBankAccessible() then
        refreshBankCache(storage)
    end
    local rows, stats = collectMainRows(storage)
    state.mainVisibleRowCount = #rows

    state.mainBody:SetText(buildSummaryText(stats))

    ensureMainRows(#rows)
    for index, rowData in ipairs(rows) do
        if rowData.group then
            setMainGroupRowValues(state.mainRows[index], rowData.label)
        else
            setMainRowValues(state.mainRows[index], rowData.item, rowData.data)
        end
    end

    for index = #rows + 1, #state.mainRows do
        state.mainRows[index]:Hide()
    end

    if #rows > 0 then
        state.mainHeader:Show()
        state.mainHeader:SetPoint("TOPLEFT", state.mainBody, "BOTTOMLEFT", 0, -8)
    else
        state.mainHeader:Hide()
    end

    layoutMainFrame()
end

local function shouldQueueMainRefresh()
    return (state.mainFrame and state.mainFrame:IsShown())
        or (state.exportFrame and state.exportFrame:IsShown())
        or (state.configFrame and state.configFrame:IsShown())
end

local function queueMainRefresh()
    if not shouldQueueMainRefresh() or state.mainRefreshQueued then
        return
    end

    state.mainRefreshQueued = true
    C_Timer.After(0.05, function()
        state.mainRefreshQueued = false
        if shouldQueueMainRefresh() then
            refreshMainFrame()
        end
    end)
end

local function getSavedMainPoint(storage)
    local point = storage.point or DEFAULT_POINT
    storage.point = storage.point or {
        point = point.point or DEFAULT_POINT.point,
        relativePoint = point.relativePoint or DEFAULT_POINT.relativePoint,
        x = point.x or DEFAULT_POINT.x,
        y = point.y or DEFAULT_POINT.y,
    }

    return storage.point.point, storage.point.relativePoint, storage.point.x, storage.point.y
end

local function getSavedConfigPoint(storage)
    local point = storage.configPoint or DEFAULT_CONFIG_POINT
    storage.configPoint = storage.configPoint or {
        point = point.point or DEFAULT_CONFIG_POINT.point,
        relativePoint = point.relativePoint or DEFAULT_CONFIG_POINT.relativePoint,
        x = point.x or DEFAULT_CONFIG_POINT.x,
        y = point.y or DEFAULT_CONFIG_POINT.y,
    }

    return storage.configPoint.point, storage.configPoint.relativePoint, storage.configPoint.x, storage.configPoint.y
end

local function saveFramePoint(frame, targetKey)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    local storage = ensureCharacterStorage()
    local record = storage[targetKey] or {}

    record.point = point
    record.relativePoint = relativePoint
    record.x = math.floor((x or 0) + 0.5)
    record.y = math.floor((y or 0) + 0.5)

    storage[targetKey] = record
end

local function saveMainFrameSize(frame)
    local storage = ensureCharacterStorage()
    storage.mainSize = storage.mainSize or {}
    storage.mainSize.width = math.floor((frame:GetWidth() or MAIN_FRAME_WIDTH) + 0.5)
    storage.mainSize.height = math.floor((frame:GetHeight() or 340) + 0.5)
end

local function setMainFrameVisible(visible)
    local storage = ensureCharacterStorage()
    storage.mainVisible = visible and true or false

    local frame = state.mainFrame
    if not frame then
        return
    end

    if visible then
        frame:Show()
    else
        frame:Hide()
    end
end

local function atan2Compat(y, x)
    if type(math.atan2) == "function" then
        return math.atan2(y, x)
    end

    return math.atan(y, x)
end

local function saveMinimapPosition(button)
    local storage = ensureCharacterStorage()
    storage.minimap = storage.minimap or {}

    local mx, my = Minimap:GetCenter()
    local bx, by = button:GetCenter()
    if not mx or not my or not bx or not by then
        return
    end

    local scale = Minimap:GetEffectiveScale()
    local px = bx * scale
    local py = by * scale
    local centerX = mx * scale
    local centerY = my * scale
    local dx = px - centerX
    local dy = py - centerY

    storage.minimap.position = math.deg(atan2Compat(dy, dx)) % 360
    storage.minimap.distance = 1
end

local function updateMinimapButtonPosition()
    local button = state.minimapButton
    if not button then
        return
    end

    local storage = ensureCharacterStorage()
    local minimap = storage.minimap or {}
    local angle = math.rad(minimap.position or 225)
    local distance = minimap.distance or 1
    local radius = (Minimap:GetWidth() / 2) + 5
    local x = math.cos(angle) * radius * distance
    local y = math.sin(angle) * radius * distance

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)

    if minimap.visible ~= false then
        button:Show()
    else
        button:Hide()
    end
end

local function ensureMinimapButton()
    if state.minimapButton then
        return state.minimapButton
    end

    local button = CreateFrame("Button", "Elysium Consumables List", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetClampedToScreen(true)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    icon:SetPoint("TOPLEFT", 7, -6)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Elysium Consumables List")
        GameTooltip:AddLine("Left-click: toggle window", 1, 1, 1)
        GameTooltip:AddLine("Right-click: open config", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            showConfigFrame()
        else
            local frame = state.mainFrame or ensureMainFrame()
            if frame and frame:IsShown() then
                setMainFrameVisible(false)
            else
                showMainFrame()
            end
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self.isDragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local dx = px - mx
            local dy = py - my
            local angle = math.deg(atan2Compat(dy, dx)) % 360
            local storage = ensureCharacterStorage()
            storage.minimap = storage.minimap or {}
            storage.minimap.position = angle
            storage.minimap.distance = 1
            updateMinimapButtonPosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        self.isDragging = false
        saveMinimapPosition(self)
        updateMinimapButtonPosition()
    end)

    state.minimapButton = button
    updateMinimapButtonPosition()
    return button
end

ensureMainFrame = function()
    if state.mainFrame then
        return state.mainFrame
    end

    local storage = ensureCharacterStorage()
    local frame = CreateFrame("Frame", addonName .. "Frame", UIParent, "BackdropTemplate")
    local savedSize = storage.mainSize or {}
    frame:SetSize(savedSize.width or MAIN_FRAME_WIDTH, savedSize.height or 340)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        edgeSize = 16,
    })
    frame:SetBackdropColor(0.07, 0.07, 0.07, 0.95)
    frame:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MAIN_MIN_WIDTH, MAIN_MIN_HEIGHT)
    elseif frame.SetMinResize then
        frame:SetMinResize(MAIN_MIN_WIDTH, MAIN_MIN_HEIGHT)
    end
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveFramePoint(self, "point")
    end)
    frame:SetScript("OnSizeChanged", function(self)
        saveMainFrameSize(self)
        layoutMainFrame()
    end)

    local point, relativePoint, x, y = getSavedMainPoint(storage)
    frame:SetPoint(point, UIParent, relativePoint, x, y)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Consumables List")
    state.mainTitle = title

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetNonSpaceWrap(true)
    body:SetWidth(MAIN_BODY_WIDTH)
    state.mainBody = body

    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(MAIN_HEADER_HEIGHT)
    state.mainHeader = header

    local stateHeader = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stateHeader:SetPoint("LEFT", 6, 0)
    stateHeader:SetWidth(72)
    stateHeader:SetText("State")

    local itemHeader = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemHeader:SetPoint("LEFT", stateHeader, "RIGHT", 8, 0)
    itemHeader:SetWidth(220)
    itemHeader:SetText("Item")

    local progressHeader = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressHeader:SetPoint("LEFT", itemHeader, "RIGHT", 8, 0)
    progressHeader:SetWidth(160)
    progressHeader:SetText("Progress")

    local sourceHeader = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceHeader:SetPoint("LEFT", progressHeader, "RIGHT", 8, 0)
    sourceHeader:SetWidth(80)
    sourceHeader:SetText("Source")

    local scrollFrame = CreateFrame("ScrollFrame", addonName .. "MainScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 40)
    state.mainScrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(MAIN_BODY_WIDTH, ROW_HEIGHT)
    scrollFrame:SetScrollChild(scrollChild)
    state.mainScrollChild = scrollChild

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        setMainFrameVisible(false)
    end)
    state.mainClose = close

    local configButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    configButton:SetSize(92, 22)
    configButton:SetPoint("BOTTOMRIGHT", -12, 10)
    configButton:SetText("Config")
    configButton:SetScript("OnClick", function()
        showConfigFrame()
    end)
    state.mainConfigButton = configButton

    local exportButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportButton:SetSize(108, 22)
    exportButton:SetPoint("BOTTOMLEFT", 12, 10)
    exportButton:SetText("Export to Auctionator")
    exportButton:SetScript("OnClick", function()
        showExportFrame()
    end)
    state.mainExportButton = exportButton

    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(RESIZE_GRIP_SIZE, RESIZE_GRIP_SIZE)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:EnableMouse(true)
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetScript("OnDragStart", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        saveMainFrameSize(frame)
        layoutMainFrame()
    end)
    local gripTexture = resizeGrip:CreateTexture(nil, "ARTWORK")
    gripTexture:SetAllPoints()
    gripTexture:SetTexture("Interface\\CHATFRAME\\UI-ChatIM-SizeGrabber-Up")
    state.mainResizeGrip = resizeGrip

    state.mainFrame = frame
    layoutMainFrame()
    return frame
end

local function ensureExportFrame()
    if state.exportFrame then
        return state.exportFrame
    end

    local frame = CreateFrame("Frame", addonName .. "ExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(620, 360)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        edgeSize = 16,
    })
    frame:SetBackdropColor(0.07, 0.07, 0.07, 0.98)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Copy Missing Items")

    local help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    help:SetJustifyH("LEFT")
    help:SetText("Copy the text below into Auctionator. The text is selected automatically.")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -12)
    box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 18)
    box:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        edgeSize = 12,
    })
    box:SetBackdropColor(0, 0, 0, 0.55)
    box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    local editBox = CreateFrame("EditBox", nil, box)
    editBox:SetPoint("TOPLEFT", 8, -8)
    editBox:SetPoint("BOTTOMRIGHT", -8, 8)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:EnableMouse(true)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontNormalLarge)
    editBox:SetTextColor(1, 1, 0, 1)
    editBox:SetJustifyH("LEFT")
    editBox:SetJustifyV("TOP")
    editBox:SetTextInsets(4, 4, 4, 4)
    editBox:SetText(buildAuctionatorExportText(ensureCharacterStorage()))
    editBox:SetCursorPosition(0)
    editBox:ClearFocus()
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    frame:SetScript("OnShow", function()
        editBox:SetText(buildAuctionatorExportText(ensureCharacterStorage()))
        editBox:SetCursorPosition(0)
        editBox:SetFocus()
    end)

    state.exportFrame = frame
    state.exportEditBox = editBox

    return frame
end

local function refreshTemplateShareFrame()
    local frame = state.shareTemplateFrame
    local editBox = state.shareTemplateEditBox
    if not frame or not editBox then
        return
    end

    local storage = ensureCharacterStorage()
    local templateLabel = getPersonalTemplateDisplayName(storage)
    local exportText = buildTemplateLuaExportText(storage, templateLabel)
    editBox:SetText(exportText)
    editBox:SetCursorPosition(0)
    editBox:HighlightText()
    if state.shareTemplateScrollFrame and state.shareTemplateScrollFrame.SetVerticalScroll then
        state.shareTemplateScrollFrame:SetVerticalScroll(0)
    end
end

local function ensureTemplateShareFrame()
    if state.shareTemplateFrame then
        return state.shareTemplateFrame
    end

    local frame = CreateFrame("Frame", addonName .. "TemplateShareFrame", UIParent, "BackdropTemplate")
    frame:SetSize(760, 460)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(110)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        edgeSize = 16,
    })
    frame:SetBackdropColor(0.07, 0.07, 0.07, 0.98)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Share Template with the World")

    local help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    help:SetJustifyH("LEFT")
    help:SetText("Copy this into an comment on curseforge or a new issue ticket on github")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -12)
    box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 18)
    box:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        edgeSize = 12,
    })
    box:SetBackdropColor(0, 0, 0, 0.55)
    box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 4)
    state.shareTemplateScrollFrame = scrollFrame

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetSize(640, 1)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:EnableMouse(true)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontNormalLarge)
    editBox:SetTextColor(1, 1, 0, 1)
    editBox:SetJustifyH("LEFT")
    editBox:SetJustifyV("TOP")
    editBox:SetTextInsets(4, 4, 4, 4)
    editBox:SetWidth(640)
    editBox:ClearFocus()
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    scrollFrame:SetScrollChild(editBox)

    frame:SetScript("OnShow", function()
        refreshTemplateShareFrame()
        editBox:SetFocus()
        editBox:SetCursorPosition(0)
        C_Timer.After(0, function()
            if state.shareTemplateFrame and state.shareTemplateFrame:IsShown() then
                refreshTemplateShareFrame()
                if state.shareTemplateEditBox then
                    state.shareTemplateEditBox:SetFocus()
                    state.shareTemplateEditBox:SetCursorPosition(0)
                end
            end
        end)
    end)

    state.shareTemplateFrame = frame
    state.shareTemplateEditBox = editBox

    return frame
end

local function registerSaveTemplatePopup()
    if StaticPopupDialogs["ELYSIUMCONSUMABLESLIST_SAVE_TEMPLATE"] then
        return
    end

    local enteredTemplateName = nil

    StaticPopupDialogs["ELYSIUMCONSUMABLESLIST_SAVE_TEMPLATE"] = {
        text = "Save the current list as a personal template.",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 64,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self, data)
            local defaultName = "Personal Template"
            if type(data) == "table" and data.defaultName and data.defaultName ~= "" then
                defaultName = data.defaultName
            end

            enteredTemplateName = defaultName
            local editBox = _G[self:GetName() .. "EditBox"] or self.editBox
            if editBox then
                editBox:SetText(defaultName)
                editBox:HighlightText()
                editBox:SetFocus()
                editBox:SetScript("OnTextChanged", function(box)
                    enteredTemplateName = strtrim(box:GetText() or "")
                end)
            end
        end,
        OnAccept = function(self, data)
            local name = strtrim(enteredTemplateName or "")
            if name == "" then
                if type(data) == "table" and data.defaultName and data.defaultName ~= "" then
                    name = data.defaultName
                else
                    name = "Personal Template"
                end
            end

            local storage = ensureCharacterStorage()
            local key = savePersonalTemplate(name, buildTemplateItemsFromStorage(storage))
            storage.templateKey = key
            refreshTemplateDropdownText(state.configFrame and state.configFrame.templateDropdown)
            refreshTemplateManagementButtons(state.configFrame)
            refreshConfigFrame()
            refreshMainFrame()
        end,
        OnHide = function(self)
            enteredTemplateName = nil
            local editBox = _G[self:GetName() .. "EditBox"] or self.editBox
            if editBox then
                editBox:SetScript("OnTextChanged", nil)
                editBox:SetText("")
            end
        end,
    }
end

local function ensureConfigRows(count)
    local child = state.configScrollChild
    if not child then
        return
    end

    while #state.configRows < count do
        local index = #state.configRows + 1
        local row = CreateFrame("Frame", nil, child)
        row:SetSize(CONFIG_FRAME_WIDTH - 60, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -ROW_HEIGHT - ((index - 1) * ROW_HEIGHT))

        local enabled = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        enabled:SetPoint("LEFT", 6, 0)
        row.enabled = enabled

        local itemId = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        itemId:SetSize(86, 20)
        itemId:SetPoint("LEFT", enabled, "RIGHT", 12, 0)
        itemId:SetAutoFocus(false)
        itemId:SetNumeric(true)
        itemId:SetFontObject(GameFontHighlightSmall)
        itemId:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        row.itemId = itemId

        local itemName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itemName:SetPoint("LEFT", itemId, "RIGHT", 10, 0)
        itemName:SetWidth(220)
        itemName:SetJustifyH("LEFT")
        itemName:SetWordWrap(false)
        itemName:SetNonSpaceWrap(false)
        row.itemName = itemName

        local desired = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        desired:SetSize(70, 20)
        desired:SetPoint("LEFT", itemName, "RIGHT", 10, 0)
        desired:SetAutoFocus(false)
        desired:SetNumeric(true)
        desired:SetFontObject(GameFontHighlightSmall)
        desired:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        row.desired = desired

        local deleteButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        deleteButton:SetSize(60, 20)
        deleteButton:SetPoint("LEFT", desired, "RIGHT", 10, 0)
        deleteButton:SetText("Delete")
        row.deleteButton = deleteButton

        state.configRows[index] = row
    end
end

local function trimText(value)
    if not value then
        return nil
    end

    value = strtrim(value)
    if value == "" then
        return nil
    end

    return value
end

local function parseNumber(value)
    local numeric = tonumber(trimText(value or ""))
    if not numeric then
        return nil
    end

    return math.floor(numeric + 0.5)
end

local function setConfigRowValues(row, item, index)
    row.index = index
    row.item = item

    row:Show()

    row.enabled:SetChecked(item.enabled ~= false)
    row.enabled:SetScript("OnClick", function(self)
        item.enabled = self:GetChecked() and true or false
        refreshMainFrame()
    end)

    local primaryItemId = item.itemId
    if not primaryItemId and type(item.itemIds) == "table" and #item.itemIds > 0 then
        primaryItemId = item.itemIds[1]
    end

    row.itemId:SetText(primaryItemId and tostring(primaryItemId) or "")
    row.itemId:SetCursorPosition(0)
    row.itemId:SetScript("OnEnterPressed", function(self)
        item.itemId = parseNumber(self:GetText())
        item.itemIds = nil
        self:SetText(item.itemId and tostring(item.itemId) or "")
        self:ClearFocus()
        refreshConfigFrame()
        refreshMainFrame()
    end)
    row.itemId:SetScript("OnEditFocusLost", function(self)
        item.itemId = parseNumber(self:GetText())
        item.itemIds = nil
        self:SetText(item.itemId and tostring(item.itemId) or "")
        refreshConfigFrame()
        refreshMainFrame()
    end)

    row.itemName:SetText(getItemResolvedName(item))

    row.desired:SetText(item.desiredCount and tostring(item.desiredCount) or "")
    row.desired:SetCursorPosition(0)
    row.desired:SetScript("OnEnterPressed", function(self)
        item.desiredCount = parseNumber(self:GetText()) or 0
        self:SetText(item.desiredCount > 0 and tostring(item.desiredCount) or "")
        self:ClearFocus()
        refreshMainFrame()
    end)
    row.desired:SetScript("OnEditFocusLost", function(self)
        item.desiredCount = parseNumber(self:GetText()) or 0
        self:SetText(item.desiredCount > 0 and tostring(item.desiredCount) or "")
        refreshMainFrame()
    end)

    row.deleteButton:SetScript("OnClick", function()
        local storage = ensureCharacterStorage()
        table.remove(storage.items, index)
        refreshConfigFrame()
        refreshMainFrame()
    end)
end

function ensureConfigFrame()
    if state.configFrame then
        return state.configFrame
    end

    local frame = CreateFrame("Frame", addonName .. "ConfigFrame", UIParent, "BackdropTemplate")
    frame:SetSize(CONFIG_FRAME_WIDTH, CONFIG_FRAME_HEIGHT)
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        edgeSize = 16,
    })
    frame:SetBackdropColor(0.07, 0.07, 0.07, 0.98)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveFramePoint(self, "configPoint")
    end)

    local storage = ensureCharacterStorage()
    local point, relativePoint, x, y = getSavedConfigPoint(storage)
    frame:SetPoint(point, UIParent, relativePoint, x, y)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Consumables Config")

    local help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    help:SetJustifyH("LEFT")
    help:SetText("Edit the shopping list below. Use item IDs for reliable tracking.")

    local templateLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    templateLabel:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -12)
    templateLabel:SetText("Template")

    local templateDropdown = CreateFrame("Frame", addonName .. "TemplateDropdown", frame, "UIDropDownMenuTemplate")
    templateDropdown:SetPoint("LEFT", templateLabel, "RIGHT", 8, -4)
    templateDropdown:SetWidth(220)
    frame.templateDropdown = templateDropdown
    initializeTemplateDropdown(templateDropdown)

    local loadTemplateButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    loadTemplateButton:SetSize(110, 22)
    loadTemplateButton:SetPoint("LEFT", templateDropdown, "RIGHT", 8, -2)
    loadTemplateButton:SetText("Load Template")
    loadTemplateButton:SetScript("OnClick", function()
        local storage = ensureCharacterStorage()
        local templateKey = storage.templateKey or "fury_warrior"
        applyTemplate(templateKey, true)
        refreshConfigFrame()
        refreshMainFrame()
    end)
    frame.loadTemplateButton = loadTemplateButton

    local addButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addButton:SetSize(90, 22)
    addButton:SetPoint("TOPRIGHT", -106, -10)
    addButton:SetText("Add Row")
    addButton:SetScript("OnClick", function()
        local storage = ensureCharacterStorage()
        table.insert(storage.items, {
            enabled = true,
            itemId = nil,
            desiredCount = DEFAULT_ROWS,
        })
        refreshConfigFrame()
        refreshMainFrame()
    end)
    frame.addButton = addButton

    local saveTemplateButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveTemplateButton:SetSize(184, 22)
    saveTemplateButton:SetPoint("BOTTOMLEFT", 14, 40)
    saveTemplateButton:SetText("Save as personal template")
    saveTemplateButton:SetScript("OnClick", function()
        registerSaveTemplatePopup()
        local storage = ensureCharacterStorage()
        local defaultName = getPersonalTemplateDisplayName(storage)
        StaticPopup_Show("ELYSIUMCONSUMABLESLIST_SAVE_TEMPLATE", nil, nil, {
            defaultName = defaultName,
        })
    end)
    frame.saveTemplateButton = saveTemplateButton
    state.configSaveTemplateButton = saveTemplateButton

    local deleteTemplateButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deleteTemplateButton:SetSize(164, 22)
    deleteTemplateButton:SetPoint("LEFT", saveTemplateButton, "RIGHT", 8, 0)
    deleteTemplateButton:SetText("Delete personal template")
    deleteTemplateButton:SetScript("OnClick", function()
        local storage = ensureCharacterStorage()
        local templateKey = storage.templateKey or ""
        if string.sub(templateKey, 1, 9) ~= "personal_" then
            return
        end

        if deletePersonalTemplate(templateKey) then
            local fallbackKey = getDefaultTemplateKey() or "fury_warrior"
            storage.templateKey = fallbackKey
            applyTemplate(fallbackKey, true)
            refreshTemplateDropdownText(frame.templateDropdown)
            refreshTemplateManagementButtons(frame)
            refreshConfigFrame()
            refreshMainFrame()
        end
    end)
    frame.deleteTemplateButton = deleteTemplateButton

    local shareTemplateButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    shareTemplateButton:SetSize(218, 22)
    shareTemplateButton:SetPoint("LEFT", deleteTemplateButton, "RIGHT", 8, 0)
    shareTemplateButton:SetText("Share template with the world")
    shareTemplateButton:SetScript("OnClick", function()
        local popup = ensureTemplateShareFrame()
        refreshTemplateShareFrame()
        popup:Show()
        popup:Raise()
    end)
    frame.shareTemplateButton = shareTemplateButton
    state.configShareTemplateButton = shareTemplateButton

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetSize(20, 20)
    closeButton:SetPoint("TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    state.configCloseButton = closeButton

    local scrollFrame = CreateFrame("ScrollFrame", addonName .. "ConfigScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -110)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 48)
    state.configScrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(CONFIG_FRAME_WIDTH - 60, 20)
    scrollFrame:SetScrollChild(scrollChild)
    state.configScrollChild = scrollChild

    local headerRow = CreateFrame("Frame", nil, frame)
    headerRow:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 8)
    headerRow:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -18, 8)
    headerRow:SetHeight(16)

    local enabledHeader = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    enabledHeader:SetPoint("LEFT", 6, 0)
    enabledHeader:SetText("Enabled")

    local labelHeader = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelHeader:SetPoint("LEFT", 146, 0)
    labelHeader:SetText("Item name")

    local itemIdHeader = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemIdHeader:SetPoint("LEFT", 50, 0)
    itemIdHeader:SetText("Item ID")

    local countHeader = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countHeader:SetPoint("LEFT", 376, 0)
    countHeader:SetText("Minimum required")

    local actionHeader = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    actionHeader:SetPoint("LEFT", 456, 0)
    actionHeader:SetText("Action")

    local hideOnCharacter = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    hideOnCharacter:SetPoint("BOTTOMLEFT", 14, 14)
    hideOnCharacter:SetScript("OnClick", function(self)
        local storage = ensureCharacterStorage()
        storage.hideOnCharacter = self:GetChecked() and true or false
        storage.showCompleted = not storage.hideOnCharacter
        refreshMainFrame()
    end)
    frame.hideOnCharacter = hideOnCharacter

    local hideLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideLabel:SetPoint("LEFT", hideOnCharacter, "RIGHT", 6, 0)
    hideLabel:SetText("Hide items if on character")

    frame:SetScript("OnShow", function()
        refreshConfigFrame()
    end)

    frame:Hide()

    state.configFrame = frame

    if InterfaceOptions_AddCategory then
        frame.name = "Consumables List"
        InterfaceOptions_AddCategory(frame)
    end

    return frame
end

function refreshConfigFrame()
    local frame = state.configFrame
    if not frame then
        return
    end

    local storage = ensureCharacterStorage()
    refreshTemplateDropdownText(frame.templateDropdown)
    refreshTemplateManagementButtons(frame)
    frame.hideOnCharacter:SetChecked(storage.hideOnCharacter == true)
    local items = storage.items or {}
    ensureConfigRows(math.max(#items, 1))

    for index, row in ipairs(state.configRows) do
        if index <= #items then
            setConfigRowValues(row, items[index], index)
        else
            row:Hide()
        end
    end

    state.configScrollChild:SetHeight(math.max(60, (#items + 1) * ROW_HEIGHT))
    state.configScrollFrame:SetVerticalScroll(0)
end

showMainFrame = function()
    local frame = ensureMainFrame()
    refreshMainFrame()
    setMainFrameVisible(true)
end

showExportFrame = function()
    local frame = ensureExportFrame()
    frame:Show()
    frame:Raise()
end

local function hideMainFrame()
    setMainFrameVisible(false)
end

showConfigFrame = function()
    local frame = ensureConfigFrame()
    refreshConfigFrame()

    if InterfaceOptionsFrame and InterfaceOptionsFrame_Show and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_Show()
        InterfaceOptionsFrame_OpenToCategory(frame)
    else
        frame:Show()
    end
end

local function handleSlashCommand(msg)
    local command = strtrim(string.lower(msg or ""))

    if command == "hide" then
        hideMainFrame()
        return
    end

    if command == "config" or command == "options" then
        showConfigFrame()
        return
    end

    if command == "show" then
        showMainFrame()
        return
    end

    if command == "toggle" or command == "" then
        local frame = ensureMainFrame()
        if frame:IsShown() then
            hideMainFrame()
        else
            showMainFrame()
        end
        return
    end

    print("|cff00ff00ElysiumConsumablesList|r commands: /consumables, /consumables show, /consumables hide, /consumables config")
end

SLASH_ELYSIUMCONSUMABLESLIST1 = "/consumables"
SLASH_ELYSIUMCONSUMABLESLIST2 = "/consumableslist"
SLASH_ELYSIUMCONSUMABLESLIST3 = "/elyconsumables"
SlashCmdList["ELYSIUMCONSUMABLESLIST"] = handleSlashCommand

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            ensureRootDB()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        ensureCharacterStorage()
        ensureMinimapButton()
        ensureMainFrame()
        ensureConfigFrame()
        if state.configFrame then
            state.configFrame:Hide()
        end
        refreshMainFrame()
        if ensureCharacterStorage().mainVisible == true then
            setMainFrameVisible(true)
        else
            setMainFrameVisible(false)
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        refreshMainFrame()
        return
    end

    if event == "BAG_UPDATE_DELAYED" or event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED" or event == "PLAYERBANKSLOTS_CHANGED" then
        if event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
            local storage = ensureCharacterStorage()
            refreshBankCache(storage)
        end
        queueMainRefresh()
        return
    end

    if event == "GET_ITEM_INFO_RECEIVED" then
        refreshConfigFrame()
        refreshMainFrame()
    end
end)
