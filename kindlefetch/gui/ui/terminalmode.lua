local LogUtil = require("util.logutil")
local NotifyUtil = require("util.notifyutil")
local PathUtil = require("util.pathutil")
local PluginLoader = require("pluginloader")
local UIManager = require("ui/uimanager")
local CurlUtil = require("util.curlutil")
local _ = require("gettext")

local TerminalMode = {}

local function makeRunner()
    -- Kindle's user storage does not pass KOReader's executable access check.
    local runner = os.tmpname()
    local file = io.open(runner, "w")
    if not file then return nil end
    local script = PathUtil.getPluginPath() .. "/../bin/kindlefetch.sh"
    local written = file:write('#!/bin/sh\nrm -f -- "$0"\nexec /bin/bash ', CurlUtil.shellQuote(script), "\n")
    local closed = file:close()
    if written and closed and os.execute("chmod 700 " .. CurlUtil.shellQuote(runner)) == 0 then
        return runner
    end
    os.remove(runner)
end

function TerminalMode.open()
    local terminal = PluginLoader:getPluginInstance("terminal")
    if not terminal then
        NotifyUtil.error(_("Enable the Terminal emulator in KOReader’s plugin management."))
        return
    end
    if terminal.is_shell_open then
        NotifyUtil.error(_("Close the existing KOReader terminal session to switch modes."))
        return
    end

    local runner = makeRunner()
    if not runner then
        NotifyUtil.error(_("Could not prepare KindleFetch terminal mode."))
        return
    end
    local shell = G_reader_settings:readSetting("terminal_shell")
    G_reader_settings:saveSetting("terminal_shell", runner)
    local ok, err = pcall(terminal.onTerminalStart, terminal)
    G_reader_settings:saveSetting("terminal_shell", shell)

    local dialog = terminal.input_dialog
    if not ok or not dialog or not UIManager:isWidgetShown(dialog) then
        if terminal.is_shell_open then terminal:killShell() end
        os.remove(runner)
        LogUtil.warn("Could not start terminal mode", err)
        NotifyUtil.error(_("Could not start KindleFetch terminal mode."))
        return
    end

    dialog.title = "KindleFetch · " .. _("Terminal")
    dialog.title_bar:setTitle(dialog.title)
    local buttons = dialog.buttons[1]
    local index = #buttons
    local button = dialog.button_table.buttons_layout[1][index]
    buttons[index].text = _("Touch")
    buttons[index].id = "close"
    buttons[index].callback = function()
        UIManager:close(dialog)
    end
    dialog.button_table.button_by_id.close = button
    button:setText(buttons[index].text, button.width)

    local function checkShell()
        local pidfile = io.open("terminal.pid")
        if pidfile then
            local pid = pidfile:read("*n")
            pidfile:close()
            local stat = pid and io.open("/proc/" .. pid .. "/stat")
            if stat then
                local line = stat:read("*l")
                stat:close()
                if line and line:match("^%d+ %b() Z ") then
                    UIManager:close(dialog)
                    return
                end
            end
        end
        UIManager:scheduleIn(1, checkShell)
    end
    local close = dialog.onCloseWidget
    function dialog:onCloseWidget()
        UIManager:unschedule(checkShell)
        terminal:killShell()
        os.remove(runner)
        close(self)
    end
    UIManager:scheduleIn(1, checkShell)
end

return TerminalMode
