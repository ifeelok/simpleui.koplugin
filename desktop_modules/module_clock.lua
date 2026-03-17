-- module_clock.lua — Simple UI
-- Clock module: clock only, clock + date, or custom text.
-- Split from module_header.lua — quote logic lives in module_quote.lua.

local CenterContainer = require("ui/widget/container/centercontainer")
local datetime        = require("datetime")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local Screen          = Device.screen
local _               = require("gettext")

local UI           = require("ui")
local PAD          = UI.PAD
local PAD2         = UI.PAD2
local CLR_TEXT_SUB = UI.CLR_TEXT_SUB

-- Pixel constants — computed once at load time.
local CLOCK_H       = Screen:scaleBySize(54)
local CLOCK_FS      = Screen:scaleBySize(44)
local CLOCK_DIMEN   = Screen:scaleBySize(50)
local DATE_H        = Screen:scaleBySize(17)
local DATE_GAP      = Screen:scaleBySize(19)
local DATE_FS       = Screen:scaleBySize(11)
local CUSTOM_H      = Screen:scaleBySize(48)
local CUSTOM_FS     = Screen:scaleBySize(38)
local BOT_PAD_EXTRA = Screen:scaleBySize(4)

-- Font faces cached at load time — Font:getFace does a hash lookup on every
-- call; caching avoids the overhead on every build().
local _FACE_CLOCK  = Font:getFace("smallinfofont", CLOCK_FS)
local _FACE_DATE   = Font:getFace("smallinfofont", DATE_FS)
local _FACE_CUSTOM = Font:getFace("smallinfofont", CUSTOM_FS)

-- Precomputed heights — avoids arithmetic on every getHeight() call.
local _H_CLOCK      = CLOCK_H + PAD * 2 + PAD2
local _H_CLOCK_DATE = _H_CLOCK + DATE_H + DATE_GAP
local _H_CUSTOM     = CUSTOM_H + PAD * 2 + PAD2

-- Cached Geom instances for CenterContainer dimens.
-- inner_w depends on the module width passed at build time, so these are
-- keyed by width and rebuilt only when the screen width changes.
-- In practice the module is always full-width so there is only ever one entry.
local _dimen_clock  = Geom:new{ w = 0, h = CLOCK_DIMEN }
local _dimen_date   = Geom:new{ w = 0, h = DATE_H }
local _dimen_custom = Geom:new{ w = 0, h = CUSTOM_H }

-- ---------------------------------------------------------------------------
-- Settings key helpers
-- The module uses pfx.."clock" as the mode key, distinct from the old
-- pfx.."header" key, so both modules can coexist without collision.
-- Modes: "clock" | "clock_date" (default) | "custom"
-- ---------------------------------------------------------------------------

local SETTING_MODE   = "clock"           -- suffix: pfx .. "clock"
local SETTING_CUSTOM = "clock_custom"    -- suffix: pfx .. "clock_custom"
local SETTING_LAST   = "clock_last"      -- suffix: pfx .. "clock_last"
local SETTING_ON     = "clock_enabled"   -- suffix: pfx .. "clock_enabled"

local function getMode(pfx)
    return G_reader_settings:readSetting(pfx .. SETTING_MODE) or "clock_date"
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function build(w, mode, pfx, vspan_pool)
    local inner_w = w - PAD * 2

    -- Update cached dimens to match current inner_w — mutating is cheaper
    -- than allocating a new Geom on every render.
    _dimen_clock.w  = inner_w
    _dimen_date.w   = inner_w
    _dimen_custom.w = inner_w

    local vg = VerticalGroup:new{ align = "center" }

    if mode == "clock" or mode == "clock_date" then
        vg[#vg+1] = CenterContainer:new{
            dimen = _dimen_clock,
            TextWidget:new{
                text = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")),
                face = _FACE_CLOCK,
                bold = true,
            },
        }
        if mode == "clock_date" then
            -- Reuse pool span when available to reduce allocations.
            if vspan_pool then
                if not vspan_pool[DATE_GAP] then
                    vspan_pool[DATE_GAP] = VerticalSpan:new{ width = DATE_GAP }
                end
                vg[#vg+1] = vspan_pool[DATE_GAP]
            else
                vg[#vg+1] = VerticalSpan:new{ width = DATE_GAP }
            end
            vg[#vg+1] = CenterContainer:new{
                dimen = _dimen_date,
                TextWidget:new{
                    text    = os.date("%A, %d %B"),
                    face    = _FACE_DATE,
                    fgcolor = CLR_TEXT_SUB,
                },
            }
        end

    elseif mode == "custom" then
        local custom = G_reader_settings:readSetting(pfx .. SETTING_CUSTOM) or "KOReader"
        vg[#vg+1] = CenterContainer:new{
            dimen = _dimen_custom,
            TextWidget:new{
                text  = custom,
                face  = _FACE_CUSTOM,
                bold  = true,
                width = w - PAD * 4,
            },
        }
    end

    return FrameContainer:new{
        bordersize     = 0,
        padding        = PAD,
        padding_bottom = PAD2 + BOT_PAD_EXTRA,
        vg,
    }
end

-- ---------------------------------------------------------------------------
-- Module API
-- ---------------------------------------------------------------------------

local M = {}

M.id          = "clock"
M.name        = _("Clock")
M.label       = nil
M.default_on  = true

function M.isEnabled(pfx)
    local v = G_reader_settings:readSetting(pfx .. SETTING_ON)
    if v ~= nil then return v == true end
    return true
end

function M.setEnabled(pfx, on)
    G_reader_settings:saveSetting(pfx .. SETTING_ON, on)
    if on then
        local cur = G_reader_settings:readSetting(pfx .. SETTING_MODE)
        if cur == nil then
            local last = G_reader_settings:readSetting(pfx .. SETTING_LAST) or "clock_date"
            G_reader_settings:saveSetting(pfx .. SETTING_MODE, last)
        end
    else
        local cur = getMode(pfx)
        G_reader_settings:saveSetting(pfx .. SETTING_LAST, cur)
    end
end

M.getCountLabel = nil

function M.build(w, ctx)
    local mode = getMode(ctx.pfx)
    return build(w, mode, ctx.pfx, ctx.vspan_pool)
end

function M.getHeight(ctx)
    local mode = getMode(ctx.pfx)
    if mode == "clock_date" then return _H_CLOCK_DATE end
    if mode == "custom"     then return _H_CUSTOM      end
    return _H_CLOCK
end

function M.getMenuItems(ctx_menu)
    local pfx        = ctx_menu.pfx
    local _UIManager = ctx_menu.UIManager
    local refresh    = ctx_menu.refresh
    local MAX_LBL    = ctx_menu.MAX_LABEL_LEN or 48
    local _lc        = ctx_menu._

    local PRESETS = {
        { key = "clock",      label = _lc("Clock") },
        { key = "clock_date", label = _lc("Clock") .. " + " .. _lc("Date") },
    }

    local items = {}
    for _, p in ipairs(PRESETS) do
        local _key = p.key
        local _lbl = p.label
        items[#items+1] = {
            text         = _lbl,
            radio        = true,
            checked_func = function() return getMode(pfx) == _key end,
            callback     = function()
                G_reader_settings:saveSetting(pfx .. SETTING_MODE, _key)
                G_reader_settings:saveSetting(pfx .. SETTING_ON,   true)
                refresh()
            end,
        }
    end

    items[#items+1] = {
        text_func = function()
            local custom = G_reader_settings:readSetting(pfx .. SETTING_CUSTOM) or ""
            if getMode(pfx) == "custom" and custom ~= "" then
                return _lc("Custom Text") .. "  (" .. custom .. ")"
            end
            return _lc("Custom Text")
        end,
        radio          = true,
        checked_func   = function() return getMode(pfx) == "custom" end,
        keep_menu_open = true,
        callback = function()
            local InputDialog = require("ui/widget/inputdialog")
            local dlg
            dlg = InputDialog:new{
                title      = _lc("Header Text"),
                input      = G_reader_settings:readSetting(pfx .. SETTING_CUSTOM) or "",
                input_hint = _lc("e.g. My Library"),
                buttons = {{ {
                    text     = _lc("Cancel"),
                    callback = function() _UIManager:close(dlg) end,
                }, {
                    text             = _lc("OK"),
                    is_enter_default = true,
                    callback = function()
                        local clean = dlg:getInputText():match("^%s*(.-)%s*$")
                        _UIManager:close(dlg)
                        if clean == "" then return end
                        if #clean > MAX_LBL then clean = clean:sub(1, MAX_LBL) end
                        G_reader_settings:saveSetting(pfx .. SETTING_CUSTOM, clean)
                        G_reader_settings:saveSetting(pfx .. SETTING_MODE,   "custom")
                        G_reader_settings:saveSetting(pfx .. SETTING_ON,     true)
                        refresh()
                    end,
                } }},
            }
            _UIManager:show(dlg)
            pcall(dlg.onShowKeyboard, dlg)
        end,
    }
    return items
end

return M
