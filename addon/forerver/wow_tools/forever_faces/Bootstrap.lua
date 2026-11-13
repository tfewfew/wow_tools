local portraits = {
    sourceVersion = "1.0.9",
    sourceCommit = "cbf2cd5b71f3e32b075af2001d7c726e41850240",
}
WoWTools.foreverFaces = portraits

function portraits.GetSettings()
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.foreverFaces) ~= "table" then wowDetectorDB.foreverFaces = {} end
    local settings = wowDetectorDB.foreverFaces
    if type(settings.db) ~= "table" then settings.db = {} end
    return settings
end

WoWTools.thirdParty.Register("forever_faces", "3D 头像", function() portraits.ToggleWindow() end)
