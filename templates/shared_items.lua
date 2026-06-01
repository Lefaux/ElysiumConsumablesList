ElysiumConsumablesListTemplates = ElysiumConsumablesListTemplates or {
    templates = {},
    sharedItems = {},
    order = {},
}

local registry = ElysiumConsumablesListTemplates

registry.sharedItems = {
    {itemId = 15138, desiredCount = 1, source = "buy"},
    {itemId = 22754, desiredCount = 1, source = "buy"},
    {itemIds = {21176, 21321, 21218, 21324, 21323}, desiredCount = 1, source = "buy", label = "AQ mount"},
}
