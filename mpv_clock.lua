-- system_clock_battery_split.lua
-- 时间每秒刷新，电池每 N 秒刷新（避免 pwsh 延迟）
-- [c] 短暂显示
-- [C] 永久显示 / 隐藏

local mp    = require 'mp'
local utils = require 'mp.utils'

local cfg = {
    format        = "%H:%M",    -- 时间格式
    duration      = 5,          -- 短显持续秒数
    key           = 'c',        -- 短显快捷键
    togglekey     = 'C',        -- 永久显示快捷键
    show_battery  = true,       -- 是否显示电池
    battery_intvl = 60,         -- 电池刷新间隔（秒）
}

local osd_overlay = mp.create_osd_overlay("ass-events")
local last_time   = ""
local is_shown    = false
local osd_timer   = nil
local hide_timer  = nil
local battery     = "..."       -- 当前电量
local bat_timer   = nil

-- 获取电池百分比
local function query_battery()
    if not cfg.show_battery then
        battery = ""
        return
    end
    local res
    if package.config:sub(1,1) == "\\" then
        -- Windows: 用 PowerShell
        res = utils.subprocess({
            args = {
                "powershell", "-NoProfile", "-Command",
                "(Get-CimInstance Win32_Battery).EstimatedChargeRemaining"
            },
            cancellable = false
        })
        if res and res.stdout then
            local perc = res.stdout:match("(%d+)")
            if perc then
                battery = perc .. "%"
                return
            end
        end
    else
        -- Linux / macOS
        res = utils.subprocess({ args = { "acpi", "-b" }, cancellable=false })
        if res and res.stdout then
            local perc = res.stdout:match("(%d?%d?%d)%%")
            if perc then
                battery = perc .. "%"
                return
            end
        end
    end
    battery = "N/A"
end

-- 更新显示
local function update_overlay()
    local now = os.date(cfg.format)
    if now == last_time then return end
    last_time = now

    local ass
    if cfg.show_battery and battery ~= "" then
        ass = string.format([[
{\an9\fs20\bord1\shad0\1c&HFFFFFF&\3c&H000000&}🕒 %s\n🔋 %s
]], now, battery)
    else
        ass = string.format([[
{\an9\fs20\bord1\shad0\1c&HFFFFFF&\3c&H000000&}🕒 %s
]], now)
    end

    osd_overlay.data = ass
    osd_overlay:update()
end

-- 清除显示
local function clear_overlay()
    osd_overlay:remove()
    last_time = ""
end

-- 短暂显示
local function show_once()
    query_battery()
    update_overlay()
    if hide_timer then hide_timer:kill() end
    hide_timer = mp.add_timeout(cfg.duration, clear_overlay)
end

-- 永久切换
local function toggle_clock()
    is_shown = not is_shown
    if is_shown then
        query_battery()
        update_overlay()

        if not osd_timer then
            osd_timer = mp.add_periodic_timer(1, update_overlay)
        else
            osd_timer:resume()
        end

        if cfg.show_battery then
            if not bat_timer then
                bat_timer = mp.add_periodic_timer(cfg.battery_intvl, function()
                    query_battery()
                    update_overlay()
                end)
            else
                bat_timer:resume()
            end
        end
    else
        clear_overlay()
        if osd_timer then osd_timer:stop() end
        if bat_timer then bat_timer:stop() end
    end
end

-- 快捷键绑定
mp.add_key_binding(cfg.key, 'show-clock-once', show_once)
mp.add_key_binding(cfg.togglekey, 'toggle-clock', toggle_clock)
