WoWTools.raynnaBestiary.RegisterSource(function(...)
local _, Addon = ...
local T = Addon.Text
local relations = { reagent = "Reagent for", crafted = "Crafted by", taught = "Teaches" }

function Addon.CreateRecipeView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 10, -112)
    view:SetPoint("TOPRIGHT", -10, -112)
    view:EnableMouseWheel(true)
    local rows, entries, offset, itemID = {}, {}, 0, nil
    local tooltipOwner, tooltipStrata, tooltipLevel

    local function Label(host, text, x, y, width)
        local label = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", x, y)
        label:SetWidth(width)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(text)
        return label
    end
    Label(view, T("Recipe"), 22, 0, 220)
    Label(view, T("Profession"), 246, 0, 90)
    Label(view, T("Quantity"), 344, 0, 42)
    view.empty = Label(view, "", 0, -24, 380)
    view.empty:SetWordWrap(true)

    local function HideTooltip()
        if tooltipOwner and GameTooltip:GetOwner() == tooltipOwner then
            GameTooltip:Hide()
            GameTooltip:SetFrameStrata(tooltipStrata)
            GameTooltip:SetFrameLevel(tooltipLevel)
        end
        tooltipOwner = nil
    end

    local scrollbar
    local function Render()
        offset = math.max(0, math.min(offset, math.max(0, #entries - 7)))
        local prr = WoWTools.prr
        for index, row in ipairs(rows) do
            local entry = entries[index + offset]
            row.entry = entry
            row:SetShown(entry ~= nil)
            if entry then
                local recipe = entry.recipe
                local name = prr.Dataflows.ItemNames.RecipeName(recipe)
                    or prr.GameData.SpellName(recipe.spellID) or recipe.name or T("Recipe %d", recipe.spellID)
                row.name:SetText(name)
                row.relation:SetText(T(relations[entry.kind]))
                row.profession:SetText(Addon.ProfessionName(recipe.profession,
                    prr.GameData.ProfessionName(recipe.profession or 0)))
                row.quantity:SetText(entry.quantity and ("×" .. entry.quantity) or "—")
                local icon = recipe.item and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(recipe.item)
                row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Note_01")
            end
        end
        scrollbar:Update(#entries, 7, offset, math.max(1, math.min(7, #entries)) * 36)
    end

    for index = 1, 7 do
        local row = CreateFrame("Frame", nil, view)
        row:SetPoint("TOPLEFT", 0, -22 - (index - 1) * 36)
        row:SetSize(386, 36)
        row:EnableMouse(true)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", 0, -3)
        row.icon:SetSize(18, 18)
        row.name = Label(row, "", 22, -3, 220)
        row.relation = Label(row, "", 22, -20, 220)
        row.relation:SetTextColor(unpack(Addon.Theme.muted))
        row.profession = Label(row, "", 246, -3, 90)
        row.quantity = Label(row, "", 344, -3, 42)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            HideTooltip()
            tooltipOwner, tooltipStrata, tooltipLevel = self, GameTooltip:GetFrameStrata(), GameTooltip:GetFrameLevel()
            local recipe = self.entry.recipe
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("spell:" .. recipe.spellID)
            GameTooltip:AddLine(T(relations[self.entry.kind]), 1, 0.82, 0.18)
            if self.entry.quantity then
                GameTooltip:AddLine(T(self.entry.kind == "reagent" and "Required per craft" or "Produced per craft")
                    .. " ×" .. self.entry.quantity, 0.8, 0.8, 0.8)
            end
            if recipe.skill then GameTooltip:AddLine(T("Required skill %s", recipe.skill), 0.8, 0.8, 0.8) end
            GameTooltip:SetFrameStrata("TOOLTIP")
            GameTooltip:SetFrameLevel(parent:GetFrameLevel() + 20)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", HideTooltip)
        rows[index] = row
    end
    scrollbar = Addon.Scrollbar(view, function(value)
        HideTooltip()
        offset = value
        Render()
    end)
    scrollbar:SetPoint("TOPRIGHT", 7, -22)
    function view:Scroll(delta)
        HideTooltip()
        offset = offset - delta
        Render()
    end
    view:SetScript("OnMouseWheel", function(self, delta) self:Scroll(delta) end)
    view:SetScript("OnHide", HideTooltip)

    function view:Refresh(selectedItemID)
        if itemID ~= selectedItemID then offset = 0 end
        itemID = selectedItemID
        local prr = WoWTools.prr
        local found = prr and prr.GetItemRecipes and prr.GetItemRecipes(itemID)
        if found ~= entries then HideTooltip() end
        entries = found or {}
        self.empty:SetText(T(found and "No associated recipes in PRR."
            or "Enable Recipe Uses in Third-party Addons to view recipes."))
        self.empty:SetShown(#entries == 0)
        self:SetHeight(24 + math.max(1, math.min(7, #entries)) * 36)
        Render()
        return #entries
    end
    view:Hide()
    return view
end
end)
