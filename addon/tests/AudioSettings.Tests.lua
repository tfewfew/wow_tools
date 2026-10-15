-- Lua 5.1. Run each flavor in its own simulated client; no real CVars are changed.
local root = TEST_ROOT or "."
for _, flavor in ipairs({ "titan", "forerver" }) do
    local values = {
        Sound_EnableAllSound="0", Sound_EnableSFX="0", Sound_MasterVolume="0.37", Sound_SFXVolume="0.23",
        Sound_EnableSoundWhenGameIsInBG="0", Sound_EnableMusic="1", Sound_MusicVolume="0.71",
        Sound_EnableAmbience="1", Sound_AmbienceVolume="0.49", Sound_EnableDialog="1",
        Sound_DialogVolume="0.62", Sound_EnableErrorSpeech="1", Sound_EnablePetSounds="1",
        Sound_EnableEmoteSounds="1", Sound_OutputDriverIndex="7",
    }
    local original, writes, dead, failKey = {}, 0, false, nil
    for key, value in pairs(values) do original[key] = value end
    local function widget()
        local object = {scripts={}, shown=true}
        function object:SetScript(event, fn) self.scripts[event] = fn end
        function object:CreateTexture() return widget() end
        function object:CreateFontString() return widget() end
        function object:GetEffectiveScale() return 1 end
        function object:GetPoint() return "LEFT", nil, "CENTER", -20, 0 end
        function object:IsShown() return self.shown end
        function object:Show() self.shown = true end
        function object:Hide() self.shown = false end
        return setmetatable(object, {__index=function() return function() end end})
    end
    local panel
    function CreateFrame(_, name)
        local frame = widget()
        if name == "wowDetectorPanel" then panel = frame end
        return frame
    end
    UIParent = widget()
    DEFAULT_CHAT_FRAME = {AddMessage=function() end}
    SlashCmdList, wowDetectorDB = {}, nil
    function UnitIsDeadOrGhost() return dead end
    local ghost=false
    UnitIsDead=UnitIsDeadOrGhost
    function UnitIsGhost() return ghost end
    function GetPhysicalScreenSize() return 1920, 1080 end
    function GetInventoryItemLink() return nil end
    function UnitChannelInfo() return nil end
    function UnitCastingInfo() return nil end
    function GetContainerNumSlots(bag) return bag == 0 and 16 or 0 end
    function GetContainerNumFreeSlots() return 10, 0 end
    C_Item, ItemLocation, Enum, C_Container = nil, nil, nil, nil
    C_CVar = {
        GetCVar=function(key) return values[key] end,
        SetCVar=function(key, value)
            writes = writes + 1
            if key == failKey then error("mock CVar failure") end
            assert(values[key] ~= nil, "Wrote an unsupported CVar")
            values[key] = value
        end,
    }
    local addon = root .. "/addon/" .. flavor .. "/wow_tools/"
    dofile(addon .. "Init.lua")
    if flavor == "forerver" then dofile(addon .. "Compatibility.lua") end
    dofile(addon .. "wowDetector/Audio.lua")
    dofile(addon .. "wowDetector/wowDetector.lua")
    local function event(name) panel.scripts.OnEvent(panel, name, "wow_tools") end
    local function unchanged(expected)
        for key, value in pairs(expected) do assert(values[key] == value, flavor .. ": not restored: " .. key) end
    end
    event("ADDON_LOADED")
    assert(writes == 0 and wowDetectorDB.audioSnapshot == nil, "Loading a disabled addon changed audio")
    SlashCmdList.WOWDETECTOR("on")
    assert(values.Sound_EnableAllSound == "1" and values.Sound_EnableSFX == "1"
        and values.Sound_MasterVolume == "1" and values.Sound_SFXVolume == "1"
        and values.Sound_EnableSoundWhenGameIsInBG == "1", "Fishing audio was not enabled")
    assert(values.Sound_EnableMusic == "0" and values.Sound_EnableAmbience == "0"
        and values.Sound_EnableDialog == "0" and values.Sound_OutputDriverIndex == "7", "Wrong muted channels/device changed")
    for key, value in pairs(wowDetectorDB.audioSnapshot) do assert(original[key] == value, "Snapshot captured modified audio") end
    -- Repeat activation must neither overwrite the initial snapshot nor reapply the profile.
    local saved = wowDetectorDB.audioSnapshot
    values.Sound_SFXVolume = "0.55"
    local before = writes
    SlashCmdList.WOWDETECTOR("on")
    assert(saved == wowDetectorDB.audioSnapshot and saved.Sound_SFXVolume == "0.23"
        and writes == before and values.Sound_SFXVolume == "0.55", "Repeated on replaced snapshot")
    SlashCmdList.WOWDETECTOR("hide")
    assert(wowDetectorDB.audioSnapshot == saved, "Hide stopped the audio profile")
    SlashCmdList.WOWDETECTOR("off")
    unchanged(original)
    assert(wowDetectorDB.audioSnapshot == nil, "Successful restore kept a stale snapshot")
    values.Sound_MasterVolume = "0.19"; original.Sound_MasterVolume = "0.19"
    WoWTools.modules.wowDetector.Show()
    assert(wowDetectorDB.audioSnapshot.Sound_MasterVolume == "0.19", "Next cycle ignored new user audio values")
    WoWTools.modules.wowDetector.Toggle()
    unchanged(original)
    assert(not panel:IsShown() and wowDetectorDB.audioSnapshot == nil, "Closing panel did not restore audio")
    SlashCmdList.WOWDETECTOR("on"); dead = true; event("PLAYER_DEAD")
    unchanged(original)
    assert(wowDetectorDB.audioSnapshot == nil and not wowDetectorDB.locked, "Death did not restore audio")
    dead = false
    SlashCmdList.WOWDETECTOR("on"); event("PLAYER_LOGOUT")
    unchanged(original)
    assert(wowDetectorDB.audioSnapshot == nil and not WoWTools.modules.wowDetector.IsEnabled(),
        "Logout/reload did not stop fishing and restore audio")
    -- Recover an old saved snapshot before defaulting to disabled on addon load.
    values.Sound_MasterVolume = "1"
    wowDetectorDB.audioSnapshot = {Sound_MasterVolume="0.19", ArbitraryCVar="evil"}
    event("ADDON_LOADED")
    unchanged(original)
    assert(wowDetectorDB.audioSnapshot == nil, "Stale saved snapshot was not recovered")
    -- Failed writes restore other values and retain the one failed restore for retry.
    failKey = "Sound_SFXVolume"
    assert(not WoWTools.audio.Start(), "CVar failure was not reported")
    unchanged(original)
    local pending = wowDetectorDB.audioSnapshot
    assert(pending and pending.Sound_SFXVolume == original.Sound_SFXVolume, "Failed restore lost its original value")
    assert(not WoWTools.audio.Start() and wowDetectorDB.audioSnapshot == pending, "Failed restore was overwritten by another start")
    failKey = nil
    assert(WoWTools.audio.Restore() and wowDetectorDB.audioSnapshot == nil, "Recovery did not retry the failed setting")
    -- Unknown CVars are skipped, and Titan's legacy API fallback remains supported.
    values.Sound_DialogVolume = nil
    local api = C_CVar
    C_CVar = nil; GetCVar = api.GetCVar; SetCVar = api.SetCVar
    assert(WoWTools.audio.Start() and wowDetectorDB.audioSnapshot.Sound_DialogVolume == nil, "Unsupported CVar was written")
    assert(WoWTools.audio.Restore(), "Legacy CVar API could not restore audio")
    GetCVar, SetCVar = nil, nil
    print("PASS: " .. flavor .. " audio snapshot/profile, repeated on, hide/off/panel close, death, logout/reload, stale snapshot recovery, write failure/retry, unsupported CVars and legacy API.")
end
