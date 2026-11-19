local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local Trapper = require("ui/trapper")
local Backend = require("util.sharedbackend")
local Guard = require("util.guard")
local NotifyUtil = require("util.notifyutil")
local T = require("ffi/util").template
local _ = require("gettext")

local PluginUpdater = {}
local checking = false
local offered

function PluginUpdater.checkForUpdates(user_requested)
    if checking then
        return
    end
    checking = true
    Trapper:wrap(Guard.wrap("checking for a KindleFetch release", function()
        local tag, err = Backend.run("update-check")
        checking = false
        if not tag then
            if user_requested then
                NotifyUtil.error(err)
            end
            return
        end
        if tag == "current" then
            if user_requested then
                NotifyUtil.info(_("KindleFetch is up to date"))
            end
            return
        end
        if not tag:match("^v%d+%.%d+%.%d+$") or (tag == offered and not user_requested) then
            return
        end
        offered = tag
        UIManager:show(ConfirmBox:new({
            text = T(_("Install KindleFetch %1 for both modes?"), tag),
            ok_text = _("Update"),
            ok_callback = function()
                Trapper:wrap(Guard.wrap("installing a KindleFetch release", function()
                    local installed, install_error = Backend.run("update", tag)
                    if not installed then
                        NotifyUtil.error(install_error)
                        return
                    end
                    UIManager:askForRestart(T(_("KindleFetch updated to %1. Restart KOReader to load it."), tag))
                end))
            end,
        }))
    end, function(err)
        checking = false
        if user_requested then
            NotifyUtil.error(err)
        end
    end))
end

return PluginUpdater
