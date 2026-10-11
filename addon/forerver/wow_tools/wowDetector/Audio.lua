-- Save supported CVars before changing any of them. Output devices stay untouched:
-- wowAuto captures each process directly with Windows process loopback.
local Audio = {}
WoWTools.audio = Audio
local profile = {
    Sound_EnableAllSound = "1", Sound_EnableSFX = "1",
    Sound_MasterVolume = "1", Sound_SFXVolume = "1",
    Sound_EnableSoundWhenGameIsInBG = "1",
    Sound_EnableMusic = "0", Sound_MusicVolume = "0",
    Sound_EnableAmbience = "0", Sound_AmbienceVolume = "0",
    Sound_EnableDialog = "0", Sound_DialogVolume = "0",
    Sound_EnableErrorSpeech = "0", Sound_EnablePetSounds = "0",
    Sound_EnableEmoteSounds = "0",
}
local function APIs()
    return C_CVar and C_CVar.GetCVar or GetCVar, C_CVar and C_CVar.SetCVar or SetCVar
end
local function Read(getter, key)
    if not getter then return nil end
    local ok, value = pcall(getter, key)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    if type(value) == "string" or type(value) == "number" then return tostring(value) end
end
function Audio.Restore()
    if type(wowDetectorDB) ~= "table" or type(wowDetectorDB.audioSnapshot) ~= "table" then return true end
    local getter, setter = APIs()
    local snapshot = wowDetectorDB.audioSnapshot
    for key, value in pairs(snapshot) do
        -- Only restore our known settings; never execute arbitrary saved entries.
        if not profile[key] or type(value) ~= "string" then snapshot[key] = nil
        elseif setter and Read(getter, key) ~= nil then
            local ok, result = pcall(setter, key, value)
            if ok and result ~= false then snapshot[key] = nil end
        end
    end
    if next(snapshot) == nil then wowDetectorDB.audioSnapshot = nil; return true end
    return false
end
function Audio.Start()
    if not Audio.Restore() then return false, "原音频设置尚未恢复，未覆盖快照。" end
    local getter, setter = APIs()
    if not getter or not setter then return false, "客户端音频设置接口不可用。" end
    local snapshot = {}
    for key in pairs(profile) do snapshot[key] = Read(getter, key) end
    if next(snapshot) == nil then return false, "客户端未提供可读取的音频设置。" end
    wowDetectorDB.audioSnapshot = snapshot
    for key in pairs(snapshot) do
        local ok, result = pcall(setter, key, profile[key])
        if not ok or result == false then
            Audio.Restore()
            return false, "音频设置失败，已尝试恢复原值。"
        end
    end
    return true
end
