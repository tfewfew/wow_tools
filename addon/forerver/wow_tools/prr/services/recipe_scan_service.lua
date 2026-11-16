WoWTools.prr.RegisterSource(function(...)
-- recipe_scan_service.lua -- reads recipes from the client itself:
-- C_TradeSkillUI.GetRecipeSchematic(spell id) gives the created item and the
-- reagents of any recipe, learned or not. Results go to ns.db.scanned and from
-- there, by scripts/build_database.py, into the base of the addon.
--
-- A scan walks a list of spell ids (or a range) a portion per tick:
-- events/ticker.lua calls Step while a scan is running.

local ADDON, ns = ...
ns.Services = ns.Services or {}

local Config = ns.Config
local Text = ns.Localization.Text

local RecipeScan = {}
ns.Services.RecipeScan = RecipeScan

local scan = nil   -- { spellIDs or first/last, position, found, quiet }

local function IsAvailable()
    return C_TradeSkillUI ~= nil and C_TradeSkillUI.GetRecipeSchematic ~= nil
end

-- Base profession of a recipe: on clients with expansion skill lines the
-- recipe belongs to a child line, the parent is the profession itself.
local function ReadProfession(spellID)
    if not C_TradeSkillUI.GetProfessionInfoByRecipeID then
        return nil
    end
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoByRecipeID, spellID)
    if not ok or type(info) ~= "table" then
        return nil
    end
    local profession = info.parentProfessionID
    if not profession or profession == 0 then
        profession = info.professionID
    end
    if profession and profession > 0 then
        return profession
    end
    return nil
end

-- { item, profession, count, reagents = { itemID, count, ... } } or nil if the spell is not a recipe.
function RecipeScan.ReadRecipe(spellID)
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, spellID, false)
    if not ok or type(schematic) ~= "table" then
        return nil
    end

    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents and slot.reagents[1]
        local isRequiredItem = reagent and reagent.itemID and slot.required ~= false
            and (slot.quantityRequired or 0) > 0
        if isRequiredItem then
            table.insert(reagents, reagent.itemID)
            table.insert(reagents, slot.quantityRequired)
        end
    end

    local item = schematic.outputItemID
    if item == 0 then
        item = nil
    end
    local isRecipe = #reagents > 0 or item ~= nil
    if not isRecipe then
        return nil
    end

    return {
        item = item,
        profession = ReadProfession(spellID),
        count = schematic.quantityMin or 1,
        reagents = reagents,
    }
end

-- options: spellIDs -- list to read, or ranges -- { { first, last }, ... } of spell
-- ids to look for recipes the base does not know; quiet -- no chat messages.
function RecipeScan.Start(options)
    if not IsAvailable() then
        ns.Utilities.Print(Text("scan.unavailable"))
        return
    end
    scan = {
        spellIDs = options.spellIDs,
        ranges = options.ranges,
        rangeIndex = 1,
        nextSpellID = nil,
        position = 1,
        found = 0,
        nextReportPercent = Config.SCAN_REPORT_PERCENT,
        quiet = options.quiet,
    }
    if scan.spellIDs then
        scan.total = #scan.spellIDs
    else
        scan.total = 0
        for _, range in ipairs(scan.ranges) do
            scan.total = scan.total + range[2] - range[1] + 1
        end
        scan.nextSpellID = scan.ranges[1][1]
    end
    if not scan.quiet then
        ns.Utilities.Print(Text("scan.started", scan.total))
    end
end

function RecipeScan.IsRunning()
    return scan ~= nil
end

local function Finish()
    local finished = scan
    scan = nil
    ns.Dataflows.RecipeIndex.Invalidate()
    local shouldReport = not finished.quiet or finished.found > 0
    if shouldReport then
        ns.Utilities.Print(Text("scan.finished", finished.found, finished.total))
    end
end

function RecipeScan.Stop()
    if scan then
        scan.quiet = false
        Finish()
    end
end

-- The spell id at the current position: from the list, or the next one of the ranges.
local function TakeSpellID()
    if scan.spellIDs then
        return scan.spellIDs[scan.position]
    end
    local spellID = scan.nextSpellID
    local range = scan.ranges[scan.rangeIndex]
    if spellID < range[2] then
        scan.nextSpellID = spellID + 1
    else
        scan.rangeIndex = scan.rangeIndex + 1
        local nextRange = scan.ranges[scan.rangeIndex]
        if nextRange then
            scan.nextSpellID = nextRange[1]
        end
    end
    return spellID
end

local function ReportProgress()
    if scan.quiet then return end
    local percent = math.floor((scan.position - 1) * 100 / scan.total)
    if percent >= scan.nextReportPercent then
        ns.Utilities.Print(Text("scan.progress", percent, scan.found))
        scan.nextReportPercent = percent - percent % Config.SCAN_REPORT_PERCENT + Config.SCAN_REPORT_PERCENT
    end
end

function RecipeScan.Step()
    if not scan then return end

    local stepEnd = math.min(scan.position + Config.SCAN_SPELLS_PER_TICK - 1, scan.total)
    while scan.position <= stepEnd do
        local spellID = TakeSpellID()
        local recipe = RecipeScan.ReadRecipe(spellID)
        -- a range scan keeps recipes of a profession and the recipes of the base
        local shouldKeep = recipe and (scan.spellIDs or recipe.profession
            or ns.Database.Recipes[spellID])
        if shouldKeep then
            ns.db.scanned[spellID] = recipe
            scan.found = scan.found + 1
        end
        scan.position = scan.position + 1
    end

    ReportProgress()
    if scan.position > scan.total then
        Finish()
    end
end
end)
