-- Forever 1.60.1 (70338): checked against Blizzard's matching exported UI/API source.
-- Restricted/failed reads remain unknown; do not infer missing enchants from them.
local Compat = {}
WoWTools.compat = Compat

local function Readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function ReadCast(getter, spellIndex)
    if not getter then return nil, nil, false end
    local values = { pcall(getter, "player") }
    if not values[1] then return nil, nil, false end
    local name, spellID = values[2], values[spellIndex + 1]
    if not Readable(name) or not Readable(spellID) then return nil, nil, false end
    return name, spellID, true
end

function Compat.GetChannelInfo()
    return ReadCast(UnitChannelInfo, 8)
end

function Compat.GetFishingState()
    local name, spellID, readable = Compat.GetChannelInfo()
    if not readable then return nil end
    -- A fishing cast is not ready until its channel has begun.
    if not name then return false end
    if spellID == 7620 then return true end
    if C_Spell and C_Spell.GetSpellName then
        local ok, fishingName = pcall(C_Spell.GetSpellName, 7620)
        if ok and Readable(fishingName) and fishingName then return name == fishingName end
    end
    return false
end

function Compat.GetInteractState()
    if type(UnitGUID) ~= "function" or type(UnitIsInteractable) ~= "function" then return "unknown" end
    -- GameObjects need not pass UnitExists; use the current interaction soft target.
    local ok, guid = pcall(UnitGUID, "softinteract")
    if not ok or not Readable(guid) then return "unknown" end
    if guid == nil or guid == "" then return "missing" end
    if type(guid) ~= "string" then return "unknown" end
    local readable, interactable = pcall(UnitIsInteractable, "softinteract")
    if not readable or not Readable(interactable) or type(interactable) ~= "boolean" then
        return "unknown", guid
    end
    return interactable and "present" or "missing", guid
end

function Compat.GetLureState()
    if UnitIsDeadOrGhost("player") then return "unknown", "角色死亡" end
    if not C_Item or not C_Item.GetItemID or not C_Item.GetItemInfoInstant
        or not C_Item.GetWeaponEnchantInfo or not ItemLocation
        or not Enum or not Enum.WeaponSlot or not Enum.ItemEnchantType then
        return "unknown", "鱼竿附魔接口不可用"
    end
    local mainHand, temporary = Enum.WeaponSlot.MainHand, Enum.ItemEnchantType.Temporary
    if mainHand == nil or temporary == nil then return "unknown", "附魔类型接口不可用" end
    local ok, itemID = pcall(function()
        return C_Item.GetItemID(ItemLocation:CreateFromEquipmentSlot(16))
    end)
    if not ok or not Readable(itemID) or not itemID then return "unknown", "未读取到主手物品" end
    local info = { pcall(C_Item.GetItemInfoInstant, itemID) }
    local classID, subclassID = info[7], info[8]
    if not info[1] or not Readable(classID) or not Readable(subclassID)
        or classID ~= 2 or subclassID ~= 20 then return "unknown", "主手不是可识别的鱼竿" end
    local enchantOK, enchants = pcall(C_Item.GetWeaponEnchantInfo, mainHand)
    if not enchantOK or not Readable(enchants) or type(enchants) ~= "table" then
        return "unknown", "未读取到临时附魔列表"
    end
    local unknown = false
    for _, enchant in pairs(enchants) do
        if not Readable(enchant) or type(enchant) ~= "table" or not Readable(enchant.enchantType)
            or type(enchant.enchantType) ~= "number" then
            unknown = true
        elseif enchant.enchantType == temporary then
            if not Readable(enchant.hasEnchant) or type(enchant.hasEnchant) ~= "boolean" then
                unknown = true
            elseif enchant.hasEnchant then
                if not Readable(enchant.timeLeft) or type(enchant.timeLeft) ~= "number" then
                    unknown = true
                elseif enchant.timeLeft > 0 then
                    return "present", "鱼竿临时附魔有效"
                end
            end
        end
    end
    if unknown then return "unknown", "临时附魔数据不可读" end
    return "missing", "没有有效鱼饵临时附魔"
end
