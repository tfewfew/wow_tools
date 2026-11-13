local portraits = {
    sourceVersion = "1.0.9",
    sourceCommit = "cbf2cd5b71f3e32b075af2001d7c726e41850240",
}
WoWTools.foreverFaces = portraits
WoWTools.modules.forever_faces = portraits

function portraits.GetSettings()
    if type(wowDetectorDB) ~= "table" then wowDetectorDB = {} end
    if type(wowDetectorDB.foreverFaces) ~= "table" then wowDetectorDB.foreverFaces = {} end
    local settings = wowDetectorDB.foreverFaces
    if type(settings.db) ~= "table" then settings.db = {} end
    return settings
end

function portraits.Show() WoWTools.settings.Open("forever_faces") end
function portraits.Hide() WoWTools.settings.HideGroup("forever_faces") end
function portraits.IsShown() return WoWTools.settings.IsGroupShown("forever_faces") end
function portraits.Toggle() WoWTools.settings.Toggle("forever_faces") end

WoWTools.thirdParty.Register("forever_faces", "3D 头像", portraits.Show)
