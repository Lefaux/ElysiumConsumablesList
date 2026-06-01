ElysiumConsumablesListTemplates = ElysiumConsumablesListTemplates or {
    templates = {},
    sharedItems = {},
    order = {},
}

local registry = ElysiumConsumablesListTemplates

registry.templates.holy_paladin = {
    label = "Holy Paladin",
    description = "Default raid consumables for a Holy Paladin.",
    items = {
        {itemId = 13511, desiredCount = 2, source = "craft", spellId = 17636},
        {itemId = 13444, desiredCount = 15, source = "craft", spellId = 17572},
        {itemId = 13458, desiredCount = 10, source = "craft", spellId = 17576},
        {itemId = 13459, desiredCount = 5, source = "craft", spellId = 17578},
        {itemId = 20007, desiredCount = 5, source = "craft", spellId = 24368},
        {itemId = 13724, desiredCount = 40, source = "buy"},
        {itemId = 13931, desiredCount = 20, source = "buy"},
        {itemId = 20079, desiredCount = 1, source = "buy"},
        {itemId = 20749, desiredCount = 10, source = "buy", chargesPerItem = 5},
        {itemId = 13456, desiredCount = 10, source = "craft", spellId = 17575},
        {itemIds = {12662, 20520}, desiredCount = 10, source = "buy", label = "Dark Runes / Demonic Runes"},
    },
}
