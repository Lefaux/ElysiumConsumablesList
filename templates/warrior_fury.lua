ElysiumConsumablesListTemplates = ElysiumConsumablesListTemplates or {
    templates = {},
    sharedItems = {},
    order = {},
}

local registry = ElysiumConsumablesListTemplates

registry.templates.fury_warrior = {
    label = "Fury Warrior",
    description = "Default raid consumables for a Fury Warrior.",
    items = {
        {itemId = 13510, desiredCount = 2, source = "craft", spellId = 17635},
        {itemId = 20079, desiredCount = 1, source = "buy"},
        {itemId = 9206, desiredCount = 10, source = "craft", spellId = 11472},
        {itemId = 13452, desiredCount = 10, source = "craft", spellId = 17571},
        {itemId = 20452, desiredCount = 20, source = "craft", spellId = 24801},
        {itemId = 18262, desiredCount = 20, source = "craft", spellId = 22757},
        {itemId = 12820, desiredCount = 10, source = "buy"},
        {itemId = 13442, desiredCount = 10, source = "craft", spellId = 17552},
        {itemId = 13457, desiredCount = 5, source = "craft", spellId = 17574},
        {itemId = 13458, desiredCount = 10, source = "craft", spellId = 17576},
        {itemId = 13456, desiredCount = 10, source = "craft", spellId = 17575},
        {itemId = 13459, desiredCount = 10, source = "craft", spellId = 17578},
        {itemId = 10646, desiredCount = 10, source = "craft", spellId = 12760},
        {itemId = 5634, desiredCount = 10, source = "craft", spellId = 6624},
        {itemId = 3387, desiredCount = 10, source = "craft", spellId = 3175},
        {itemId = 13446, desiredCount = 10, source = "craft", spellId = 17556},
        {itemId = 3386, desiredCount = 10, source = "craft", spellId = 3174},
        {itemId = 13455, desiredCount = 10, source = "craft", spellId = 17570},
        {itemId = 3829, desiredCount = 2, source = "craft", spellId = 3454},
        {itemId = 10761, desiredCount = 2, source = "buy"},
        {itemId = 12451, desiredCount = 20, source = "buy"},
    },
}
