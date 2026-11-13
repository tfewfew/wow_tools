local BFC = LibStub("AceAddon-3.0"):GetAddon("WoWToolsBigFootChannel")
local L = LibStub("AceLocale-3.0"):GetLocale("WoWToolsBigFootChannel")
local optGetter, optSetter
do
    function optGetter(info)
        local key = info[#info]
        return BFC.db.profile[key]
    end
    function optSetter(info, value)
        local key = info[#info]
        BFC.db.profile[key] = value
        BFC:Refresh()
    end
end
local options, moduleOptions = nil, {}
local function getOptions()
    if not options then
        options = {
            type = "group",
            name = "bigfoot_channel",
            childGroups = "tab",
            args = {
                general = {
                    order = 1,
                    type = "group",
                    name = L.BFChat,
                    get = optGetter,
                    set = optSetter,
                    args = {
                        intro = {
                            order = 1,
                            type = "description",
                            name = L["BFChat provides you convient tools like copy text, name highlight and timestamps"],
                        },
                        enablecopy = {
                            order = 2,
                            type = "toggle",
                            name = L["Enable copy text"],
                            width = "full",
                        },
                        enableOldChatFrameStyle = {
                            order = 3,
                            type = "toggle",
                            name = L["Enable Old style Style"],
                            width = "full",
                        },
                        timestampheader = { order = 4, type = "header", name = L["Timestamp setting"] },
                        enabletimestamp = {
                            order = 5,
                            type = "toggle",
                            name = L["Enable timestamp"],
                            width = "full",
                            get = function()
                                if C_CVar.GetCVar("showTimestamps") == "none" then
                                    return false
                                else
                                    return true
                                end
                            end,
                            set = function(...)
                                local _, flag = ...
                                if flag then
                                    C_CVar.SetCVar("showTimestamps", "%I:%M %p")
                                    CHAT_TIMESTAMP_FORMAT = "%I:%M %p"
                                else
                                    C_CVar.SetCVar("showTimestamps", "none")
                                    CHAT_TIMESTAMP_FORMAT = nil
                                end
                            end,
                        },
                        classheader = { order = 12, type = "header", name = L["Class setting"] },
                        enableclasscolor = {
                            order = 13,
                            type = "toggle",
                            name = L["Enable Class Color"],
                            width = "full",
                            set = function(...)
                                local _, flag = ...
                                if flag then
                                    BFC:MaskSystemColoring(true)
                                else
                                    BFC:MaskSystemColoring(false)
                                end
                                BFC.db.profile.enableclasscolor = flag
                            end,
                            get = function()
                                return BFC.db.profile.enableclasscolor
                            end,
                        },
                        channelheader = { order = 14, type = "header", name = L["Channel setting"] },
                        useshortname = {
                            order = 18,
                            name = L["Use short channel names"],
                            type = "toggle",
                            width = "full",
                        },
                        enablechatchannelmove = {
                            order = 20,
                            type = "toggle",
                            name = L["Enable channel buttons move"],
                        },
                    },
                },
            },
        }
        for k, v in pairs(moduleOptions) do
            options.args[k] = (type(v) == "function") and v() or v
            local order = { CHATFRAME = 2, ICONFRAME = 3, Profiles = 6 }
            options.args[k].order = order[k]
        end
        options.args.filters = WoWTools.bigfootChannel.filterOptions
        options.args.world = {
            type = "group",
            name = "世界频道",
            order = 4,
            args = {
                autoJoin = {
                    type = "toggle",
                    name = "登录后自动加入大脚世界频道",
                    order = 1,
                    width = "full",
                    get = function()
                        return WoWTools.bigfootChannel.GetSettings().autoJoinWorld
                    end,
                    set = function(_, value)
                        WoWTools.bigfootChannel.GetSettings().autoJoinWorld = value
                        if value then
                            WoWTools.bigfootChannel.StartWorldChannel()
                        else
                            WoWTools.bigfootChannel.StopWorldChannel()
                        end
                    end,
                },
                mute = {
                    type = "toggle",
                    name = "屏蔽大脚世界频道",
                    order = 2,
                    width = "full",
                    get = function()
                        return not not BFC.db.profile.mute
                    end,
                    set = function(_, value)
                        BFC.db.profile.mute = value
                        BFChannel_RefreshMuteButton()
                    end,
                },
                join = {
                    type = "execute",
                    name = "重新加入",
                    order = 3,
                    func = function()
                        WoWTools.bigfootChannel.StartWorldChannel()
                    end,
                },
                status = {
                    type = "description",
                    order = 4,
                    name = function()
                        return WoWTools.bigfootChannel.WorldChannelStatus()
                    end,
                },
            },
        }
    end
    return options
end
function BFC:ShowOptions()
    WoWTools.modules.bigfoot_channel.Show()
end
function BFC:SetupOptions()
    self.optionsFrames = {}
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("WoWToolsBigFootChannel", getOptions)
    LibStub("AceConfigDialog-3.0"):SetDefaultSize("WoWToolsBigFootChannel", 760, 600)
    self:RegisterModuleOptions("Profiles", LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db), "Profiles")
    self:Refresh()
end
function BFC:RegisterModuleOptions(name, optionTbl, displayName)
    local order = { CHATFRAME = 2, ICONFRAME = 3, Profiles = 6 }
    if type(optionTbl) == "table" then
        optionTbl.order = order[name]
    end
    moduleOptions[name] = optionTbl
end
