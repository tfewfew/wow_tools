WoWTools.prr.RegisterSource(function(...)
-- skill_planner.lua -- the cheapest way to level a profession from one skill to
-- another with the recipes of the base and the auction prices.
--
-- A recipe gives a point for sure while it is orange (learn skill .. yellow),
-- and with a chance while it is yellow (yellow .. green, green halfway to gray):
--   chance = (gray - skill) / (gray - yellow)
-- Yellow recipes count only when the player opts in. Every skill level is
-- independent: the recipe with the lowest cost per point is taken for it, a
-- forced recipe -- whenever it can give the point. Levels in a row with the
-- same recipe make one step of the plan.
--
-- A recipe counts with its reagent cost at auction prices (CraftPlanner), or
-- the price the player set for this plan; without either it is left out.
-- Recipes without a known learn skill or skill-up range are left out too: the
-- base does not guess them. Banned recipes (PRRDB.settings.planner.banned) are
-- never used. A pattern to buy (plan.recipePrice) is weighed on the whole
-- plan: see SkillPlanner.Plan.
--
-- Two algorithms (plan.algorithm):
--   standard -- every craft at its reagent cost, as above;
--   smart -- the items the steps of the plan craft are kept: a later step
--     takes its reagents from them first (40 Bolts of Linen Cloth made for
--     points are not bought again for the shirts after them). Those reagents
--     cost nothing more (their reagents are paid already), so a recipe made
--     of them is cheap -- even when they have no auction price. Only the
--     steps of the plan count: a reagent no step before makes is to buy
--     (Reagents to buy), not crafted on the side, not "made before".

local ADDON, ns = ...
ns.Dataflows = ns.Dataflows or {}

local CraftPlanner = ns.Dataflows.CraftPlanner

local SkillPlanner = {}
ns.Dataflows.SkillPlanner = SkillPlanner

function SkillPlanner.IsBanned(spellID)
    return ns.db.settings.planner.banned[spellID] == true
end

function SkillPlanner.SetBanned(spellID, isBanned)
    ns.db.settings.planner.banned[spellID] = isBanned or nil
end

-- The banned recipes of a profession.
function SkillPlanner.BannedRecipes(profession)
    local list = {}
    for _, recipe in ipairs(CraftPlanner.Recipes(profession)) do
        if SkillPlanner.IsBanned(recipe.spellID) then
            table.insert(list, recipe)
        end
    end
    return list
end

-- The green threshold: halfway between yellow and gray, as the server counts it.
function SkillPlanner.Green(recipe)
    return math.floor((recipe.yellow + recipe.gray) / 2)
end

SkillPlanner.YELLOW_CHANCE_AUTO = 0   -- the chance of a yellow craft by the formula of the game
-- auto: a hidden margin against bad luck -- a step with yellow crafts makes
-- a few more (and takes their reagents): up to `upTo` yellow crafts -- `extra`
local AUTO_YELLOW_MARGINS = {
    { upTo = 4, extra = 1 },
    { upTo = 10, extra = 2 },
}
local AUTO_YELLOW_MARGIN_MAX = 3

local function IsAutoChance(yellowChance)
    return yellowChance == nil or yellowChance == SkillPlanner.YELLOW_CHANCE_AUTO
end

-- auto: the extra crafts of a step with yellowCrafts of them.
function SkillPlanner.AutoYellowMargin(yellowCrafts)
    if yellowCrafts <= 0 then return 0 end
    for _, margin in ipairs(AUTO_YELLOW_MARGINS) do
        if yellowCrafts <= margin.upTo then return margin.extra end
    end
    return AUTO_YELLOW_MARGIN_MAX
end

-- The chance of a point from one craft at a skill: 1 while orange, less while
-- yellow (only with includeYellow, up to green): yellowChance percent set by
-- the player, or by the formula (YELLOW_CHANCE_AUTO, nil); nil -- no point or not known.
function SkillPlanner.Chance(recipe, skill, includeYellow, yellowChance)
    local isKnown = recipe.skill and recipe.yellow and recipe.gray and recipe.gray > recipe.yellow
    if not isKnown or skill < recipe.skill then
        return nil
    end
    if skill < recipe.yellow then
        return 1
    end
    local isYellow = includeYellow and skill < SkillPlanner.Green(recipe)
    if not isYellow then
        return nil
    end
    if not IsAutoChance(yellowChance) then
        return yellowChance / 100
    end
    return (recipe.gray - skill) / (recipe.gray - recipe.yellow)
end

-- The cost of one craft: the price set for the plan, else the reagents at
-- auction prices; nil -- a reagent has no price.
local function CraftCost(recipe, prices)
    if prices[recipe.spellID] then
        return prices[recipe.spellID]
    end
    local evaluation = CraftPlanner.Evaluate(recipe)
    if evaluation.missing > 0 then
        return nil
    end
    return evaluation.cost
end

-- smart: { prices -- of the plan, stock -- the items made so far }.
local function NewSmart(plan)
    return { prices = plan.prices, stock = {} }
end

-- smart: the cost of crafts of a recipe with the items made so far (stock)
-- used first, the rest at auction prices; nil -- one of the rest has no price.
local function CostWithStock(recipe, crafts, stock, smart)
    if smart.prices[recipe.spellID] then
        return smart.prices[recipe.spellID] * crafts
    end
    local cost = 0
    for _, reagent in ipairs(recipe.reagents) do
        local uncovered = math.max(0, reagent[2] * crafts - (stock[reagent[1]] or 0))
        if uncovered > 0 then
            local price = ns.Dataflows.AuctionPrices.Get(reagent[1])
            if not price then return nil end
            cost = cost + price * uncovered
        end
    end
    return cost
end

-- smart: crafts of a recipe take their reagents from the stock and put
-- what they make into it.
local function UseStock(recipe, crafts, stock)
    for _, reagent in ipairs(recipe.reagents) do
        local itemID = reagent[1]
        local taken = math.min(stock[itemID] or 0, reagent[2] * crafts)
        stock[itemID] = (stock[itemID] or 0) - taken
    end
    if recipe.item then
        stock[recipe.item] = (stock[recipe.item] or 0) + (recipe.count or 1) * crafts
    end
end

-- The recipe for one skill level: { recipe, chance, cost } or nil. smart --
-- with the items made so far (smart.stock), nil -- standard.
local function BestForLevel(candidates, skill, plan, smart)
    local best = nil
    local bestCostPerPoint = nil
    for _, candidate in ipairs(candidates) do
        local chance = SkillPlanner.Chance(candidate.recipe, skill, plan.includeYellow, plan.yellowChance)
        local isForced = plan.forced[candidate.recipe.spellID] == true
        -- the cost of one point: 1 / chance crafts
        local costPerPoint = nil
        if chance and chance > 0 then
            if smart then
                costPerPoint = CostWithStock(candidate.recipe, 1 / chance, smart.stock, smart)
            elseif candidate.cost then
                costPerPoint = candidate.cost / chance
            end
            if not costPerPoint and isForced then
                costPerPoint = 0
            end
        end
        if costPerPoint then
            local isBetter = best == nil
                or (isForced and not best.isForced)
                or (isForced == best.isForced and costPerPoint < bestCostPerPoint)
            if isBetter then
                best = { recipe = candidate.recipe, chance = chance, cost = candidate.cost, isForced = isForced }
                bestCostPerPoint = costPerPoint
            end
        end
    end
    return best
end

-- Crafts of a step to make on its yellow points: the average rounded up;
-- auto chance -- with the hidden margin (SkillPlanner.AutoYellowMargin).
local function YellowCrafts(step)
    local crafts = math.ceil(step.crafts - step.orangePoints - 0.0001)
    if step.isAutoChance then
        crafts = crafts + SkillPlanner.AutoYellowMargin(crafts)
    end
    return crafts
end

-- Crafts of a step to make: one per orange point, the yellow ones on average
-- rounded up.
function SkillPlanner.StepCrafts(step)
    return step.orangePoints + YellowCrafts(step)
end

-- smart: the steps in their order with the crafts to make (StepCrafts): what
-- a step takes from the items the steps before it make (fromPlan), what is
-- left to get -- bought, even when the profession could make it: only the
-- crafts of the plan count, nothing made before it or on the side (toGet),
-- its cost -- of what is bought (or the price set for it); hasNoPrice -- an
-- item to buy has no price.
local function CountWithStock(steps, smart)
    local stock = {}
    for _, step in ipairs(steps) do
        local recipe = step.recipe
        local crafts = SkillPlanner.StepCrafts(step)
        step.fromPlan = {}
        step.toGet = {}
        local cost = 0
        local isMissing = false
        for _, reagent in ipairs(recipe.reagents) do
            local itemID = reagent[1]
            local need = reagent[2] * crafts
            local taken = math.min(stock[itemID] or 0, need)
            stock[itemID] = (stock[itemID] or 0) - taken
            step.fromPlan[itemID] = taken
            if need > taken then
                step.toGet[itemID] = need - taken
                local price = ns.Dataflows.AuctionPrices.Get(itemID)
                if price then
                    cost = cost + price * (need - taken)
                else
                    isMissing = true
                end
            end
        end
        if recipe.item then
            stock[recipe.item] = (stock[recipe.item] or 0) + (recipe.count or 1) * crafts
        end
        if smart.prices[recipe.spellID] then
            cost = smart.prices[recipe.spellID] * crafts
            isMissing = false
        end
        step.hasNoPrice = isMissing
        step.craftCost = crafts > 0 and cost / crafts or 0
    end
end

-- The recipe chosen for every level: { { skill, recipe, chance, cost, isForced } },
-- and the first skill no recipe levels (nil -- none).
local function ChoosePicks(plan, candidates, smart)
    local picks = {}
    for skill = plan.from, plan.to - 1 do
        local best = BestForLevel(candidates, skill, plan, smart)
        if not best then
            return picks, skill
        end
        best.skill = skill
        table.insert(picks, best)
        if smart then
            UseStock(best.recipe, 1 / best.chance, smart.stock)
        end
    end
    return picks, nil
end

-- smart: the plan from the first skill, cut at plan.from -- the same plan
-- for every skill on the way (planned from the skill itself, the cheapest
-- point there is often one more craft of what the step before made, and the
-- plan changes with every point). Stuck before plan.from: from plan.from.
local ANCHOR_SKILL = 1

local function ChooseAnchoredPicks(plan, candidates, smart)
    local anchored = setmetatable({ from = ANCHOR_SKILL }, { __index = plan })
    local picks, stuckAt = ChoosePicks(anchored, candidates, smart)
    if stuckAt and stuckAt < plan.from then
        smart.stock = {}
        return ChoosePicks(plan, candidates, smart)
    end
    return picks, stuckAt
end

-- The picks from a skill on (the anchored plan cut at plan.from).
local function CutPicks(picks, from)
    local cut = {}
    for _, pick in ipairs(picks) do
        if pick.skill >= from then
            table.insert(cut, pick)
        end
    end
    return cut
end

local function IsOrangeAt(recipe, skill)
    return skill >= recipe.skill and skill < recipe.yellow
end

-- smart: a run of orange levels often goes a bolt, a shirt of it, a bolt...;
-- the same crafts in blocks (all the bolts, then the shirts) -- each recipe
-- of a run in the order it first comes, when every craft stays orange at its
-- new level. The crafts that make an item come before the ones that use it.
local function GroupPicks(picks)
    local grouped = {}
    local index = 1
    while index <= #picks do
        if picks[index].chance < 1 then
            table.insert(grouped, picks[index])
            index = index + 1
        else
            local run = {}
            while index <= #picks and picks[index].chance >= 1 do
                table.insert(run, picks[index])
                index = index + 1
            end
            local order = {}
            local byRecipe = {}
            for _, pick in ipairs(run) do
                if not byRecipe[pick.recipe] then
                    byRecipe[pick.recipe] = {}
                    table.insert(order, pick.recipe)
                end
                table.insert(byRecipe[pick.recipe], pick)
            end
            local sorted = {}
            for _, recipe in ipairs(order) do
                for _, pick in ipairs(byRecipe[recipe]) do
                    table.insert(sorted, pick)
                end
            end
            local isValid = true
            for position, pick in ipairs(sorted) do
                if not IsOrangeAt(pick.recipe, run[position].skill) then
                    isValid = false
                    break
                end
            end
            for position, pick in ipairs(isValid and sorted or run) do
                local moved = {}
                for key, value in pairs(pick) do
                    moved[key] = value
                end
                moved.skill = run[position].skill
                table.insert(grouped, moved)
            end
        end
    end
    return grouped
end

-- The plan from the picks: levels in a row with the same recipe make a step;
-- the sums count the crafts to make (StepCrafts: the average rounded up),
-- the same as the reagents of the plan.
local function BuildResult(picks, plan, stuckAt, smart)
    local result = { steps = {}, totalCost = 0, totalCrafts = 0, extraCrafts = 0, extraCost = 0, stuckAt = stuckAt }
    local step = nil
    for _, best in ipairs(picks) do
        local isSameStep = step ~= nil and step.recipe == best.recipe
        if not isSameStep then
            step = {
                recipe = best.recipe,
                from = best.skill,
                crafts = 0,
                craftCost = best.cost or 0,
                orangePoints = 0,
                yellowPoints = 0,
                isForced = best.isForced,
                hasCustomPrice = plan.prices[best.recipe.spellID] ~= nil,
                hasNoPrice = best.cost == nil,
                isAutoChance = IsAutoChance(plan.yellowChance),
            }
            table.insert(result.steps, step)
        end
        step.to = best.skill + 1
        step.crafts = step.crafts + 1 / best.chance
        if best.chance >= 1 then
            step.orangePoints = step.orangePoints + 1
        else
            step.yellowPoints = step.yellowPoints + 1
        end
    end

    if smart then
        CountWithStock(result.steps, smart)
    end
    result.unpricedSteps = 0
    for _, planned in ipairs(result.steps) do
        local crafts = SkillPlanner.StepCrafts(planned)
        local points = planned.to - planned.from
        planned.cost = planned.craftCost * crafts
        planned.extraCrafts = crafts - points
        planned.extraCost = planned.craftCost * planned.extraCrafts
        result.totalCrafts = result.totalCrafts + crafts
        result.totalCost = result.totalCost + planned.cost
        result.extraCrafts = result.extraCrafts + planned.extraCrafts
        result.extraCost = result.extraCost + planned.extraCost
        if planned.hasNoPrice then
            result.unpricedSteps = result.unpricedSteps + 1
        end
    end
    return result
end

-- One plan without the recipes of skipped (spellID -> true).
local function PlanWithout(plan, skipped)
    local isSmart = plan.algorithm == "smart"
    -- smart: a recipe without a price may get its reagents from the plan
    local candidates = {}
    for _, recipe in ipairs(CraftPlanner.Recipes(plan.profession)) do
        local isForced = plan.forced[recipe.spellID] == true
        -- plan.isRecipeAvailable(recipe) -- the recipes the player can get (where
        -- they come from: a setting of the plan tab); a forced one is always used
        local isAvailable = isForced or not plan.isRecipeAvailable or plan.isRecipeAvailable(recipe)
        local isUsable = isAvailable and not SkillPlanner.IsBanned(recipe.spellID) and not skipped[recipe.spellID]
        local cost = CraftCost(recipe, plan.prices)
        if isUsable and (cost or isForced or isSmart) then
            table.insert(candidates, { recipe = recipe, cost = cost })
        end
    end
    local smart = nil
    if isSmart then
        smart = NewSmart(plan)
    end
    local picks, stuckAt = nil, nil
    if isSmart and plan.from > ANCHOR_SKILL then
        picks, stuckAt = ChooseAnchoredPicks(plan, candidates, smart)
    else
        picks, stuckAt = ChoosePicks(plan, candidates, smart)
    end
    if not isSmart then
        return BuildResult(picks, plan, stuckAt, smart)
    end
    -- the crafts in blocks, when that costs no more -- weighed on the whole
    -- (anchored) plan, then cut at plan.from: the same choice at every skill
    local groupedPicks = GroupPicks(picks)
    local whole = BuildResult(picks, plan, stuckAt, smart)
    local wholeGrouped = BuildResult(groupedPicks, plan, stuckAt, smart)
    local isNoWorse = wholeGrouped.unpricedSteps <= whole.unpricedSteps and wholeGrouped.totalCost <= whole.totalCost
    if isNoWorse then
        picks = groupedPicks
    end
    return BuildResult(CutPicks(picks, plan.from), plan, stuckAt, smart)
end

-- The recipes of a plan to buy first (plan.recipePrice(recipe) -- the price
-- of its pattern, nil -- nothing to buy or no price), each once, the dearest
-- first; the total with their prices.
local function Purchases(plan, result)
    local list = {}
    local seen = {}
    local total = result.totalCost
    for _, step in ipairs(result.steps) do
        local recipe = step.recipe
        local price = not seen[recipe.spellID] and plan.recipePrice(recipe)
        seen[recipe.spellID] = true
        if price then
            total = total + price
            table.insert(list, { recipe = recipe, price = price })
        end
    end
    table.sort(list, function(a, b) return a.price > b.price end)
    return list, total
end

-- How far a plan gets: the stuck skill, or the end.
local function Reach(plan, result)
    return result.stuckAt or plan.to
end

-- The plan. The choice of every level weighs the cost of the crafts only, so
-- a recipe whose pattern is to buy wins even when the pattern costs more than
-- it saves: every such recipe of the plan (plan.recipePrice), the dearest
-- first, is tried away -- the plan without it is kept when it gets as far, has
-- no more steps without a price and costs less with the patterns. A recipe
-- the new plan takes instead is tried too; each once, a forced one never.
function SkillPlanner.Plan(plan)
    local skipped = {}
    local result = PlanWithout(plan, skipped)
    if not plan.recipePrice then return result end
    local tried = {}
    while true do
        local purchases, total = Purchases(plan, result)
        local isChanged = false
        for _, purchase in ipairs(purchases) do
            local spellID = purchase.recipe.spellID
            if not tried[spellID] and not plan.forced[spellID] then
                tried[spellID] = true
                skipped[spellID] = true
                local without = PlanWithout(plan, skipped)
                local _, totalWithout = Purchases(plan, without)
                local isBetter = Reach(plan, without) >= Reach(plan, result)
                    and without.unpricedSteps <= result.unpricedSteps and totalWithout < total
                if isBetter then
                    result = without
                    isChanged = true
                    break
                end
                skipped[spellID] = nil
            end
        end
        if not isChanged then return result end
    end
end

-- Every reagent of a plan: { itemID, count, orangeCount, yellowCount, crafted,
-- price } -- count for the crafts of all its steps (StepCrafts): orangeCount for
-- sure (the orange points), yellowCount on average (the yellow ones); smart --
-- without what the plan crafts itself (crafted, taken from the sure part
-- first), a reagent the plan makes all of is not in the list; price per item
-- at the auction (nil -- none); the most needed first.
function SkillPlanner.Reagents(result)
    local counts = {}
    local order = {}
    for _, step in ipairs(result.steps) do
        local yellowCrafts = YellowCrafts(step)
        local function Add(itemID, orange, yellow, crafted)
            if not counts[itemID] then
                counts[itemID] = { orange = 0, yellow = 0, crafted = 0 }
                table.insert(order, itemID)
            end
            counts[itemID].orange = counts[itemID].orange + orange
            counts[itemID].yellow = counts[itemID].yellow + yellow
            counts[itemID].crafted = counts[itemID].crafted + crafted
        end
        if step.toGet then
            -- smart: what is bought, the sure part by the share of the orange crafts
            local crafts = math.max(SkillPlanner.StepCrafts(step), 1)
            for _, reagent in ipairs(step.recipe.reagents) do
                Add(reagent[1], 0, 0, step.fromPlan[reagent[1]] or 0)
            end
            local itemIDs = {}
            for itemID in pairs(step.toGet) do
                table.insert(itemIDs, itemID)
            end
            table.sort(itemIDs)
            for _, itemID in ipairs(itemIDs) do
                local amount = step.toGet[itemID]
                local orange = math.floor(amount * step.orangePoints / crafts + 0.5)
                Add(itemID, orange, amount - orange, 0)
            end
        else
            for _, reagent in ipairs(step.recipe.reagents) do
                Add(reagent[1], reagent[2] * step.orangePoints, reagent[2] * yellowCrafts, 0)
            end
        end
    end
    local list = {}
    for _, itemID in ipairs(order) do
        local count = counts[itemID]
        local total = count.orange + count.yellow
        if total > 0 then
            table.insert(list, {
                itemID = itemID,
                count = total,
                orangeCount = count.orange,
                yellowCount = count.yellow,
                crafted = count.crafted,
                price = ns.Dataflows.AuctionPrices.Get(itemID),
            })
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.itemID < b.itemID
    end)
    return list
end
end)
