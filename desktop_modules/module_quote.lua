-- module_quote.lua — Simple UI
-- Quote of the Day module: random quote from quotes.lua, with attribution.
-- Split from module_header.lua — clock logic lives in module_clock.lua.

local Blitbuffer    = require("ffi/blitbuffer")
local Device        = require("device")
local Font          = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan  = require("ui/widget/verticalspan")
local Screen        = Device.screen
local _             = require("gettext")

local UI           = require("ui")
local PAD          = UI.PAD
local PAD2         = UI.PAD2
local CLR_TEXT_SUB = UI.CLR_TEXT_SUB

local _CLR_TEXT_QUOTE = Blitbuffer.COLOR_BLACK

-- Pixel constants — computed once at load time.
local QUOTE_FS      = Screen:scaleBySize(11)
local QUOTE_ATTR_FS = Screen:scaleBySize(9)
local QUOTE_GAP     = Screen:scaleBySize(4)
-- Single scaleBySize(11) instead of scaleBySize(9) + scaleBySize(2) —
-- avoids two C calls and potential 1px rounding inconsistency.
local QUOTE_ATTR_H  = Screen:scaleBySize(11)
-- Height: PAD + up to 3 lines of text + gap + attribution line + PAD2
local QUOTE_H       = PAD + QUOTE_FS * 3 + QUOTE_GAP + QUOTE_ATTR_H + PAD2

-- Font faces cached at load time.
local _FACE_QUOTE = Font:getFace("cfont", QUOTE_FS)
local _FACE_ATTR  = Font:getFace("cfont", QUOTE_ATTR_FS)

-- Gap span cached at load time — reused on every build() call.
local _VSPAN_GAP = VerticalSpan:new{ width = QUOTE_GAP }

-- ---------------------------------------------------------------------------
-- Quote engine
-- Quotes are loaded lazily and cached for the process lifetime.
-- The path is resolved at module load time (not inside loadQuotes) so
-- debug.getinfo runs exactly once — it is one of the slower Lua introspection
-- calls and has no business running on every first render.
-- ---------------------------------------------------------------------------

-- Resolved once when the module is first required.
local _qpath = debug.getinfo(1, "S").source:match("^@(.+/)[^/]+$") or "./"

local _quotes_cache = nil
local _last_idx     = nil

local function loadQuotes()
    if _quotes_cache then return _quotes_cache end
    local ok, data = pcall(dofile, _qpath .. "quotes.lua")
    if ok and type(data) == "table" and #data > 0 then
        _quotes_cache = data
    else
        _quotes_cache = {
            { q = "A reader lives a thousand lives before he dies.",                   a = "George R.R. Martin" },
            { q = "So many books, so little time.",                                    a = "Frank Zappa" },
            { q = "I have always imagined that Paradise will be a kind of library.",   a = "Jorge Luis Borges" },
            { q = "Sleep is good, he said, and books are better.",                     a = "George R.R. Martin", b = "A Clash of Kings" },
        }
    end
    return _quotes_cache
end

-- Returns a random quote, never the same as the previous one.
-- Uses a single math.random call (no loop): shift the range by one to skip
-- the last index, then map back — O(1) and deterministic.
local function pickQuote()
    local quotes = loadQuotes()
    local n = #quotes
    if n == 0 then return nil end
    if n == 1 then _last_idx = 1; return quotes[1] end
    -- Pick from [1, n-1]; if the result would equal _last_idx, use n instead.
    local idx = math.random(1, n - 1)
    if _last_idx and idx >= _last_idx then idx = idx + 1 end
    _last_idx = idx
    return quotes[idx]
end

-- ---------------------------------------------------------------------------
-- Widget builder
-- ---------------------------------------------------------------------------

local function buildQuoteWidget(inner_w)
    local q = pickQuote()
    if not q then
        return TextBoxWidget:new{
            text    = _("No quotes found."),
            face    = _FACE_QUOTE,
            fgcolor = CLR_TEXT_SUB,
            width   = inner_w,
        }
    end

    local attribution = "— " .. (q.a or "?")
    if q.b and q.b ~= "" then attribution = attribution .. ",  " .. q.b end

    local vg = VerticalGroup:new{ align = "center" }
    vg[#vg+1] = TextBoxWidget:new{
        text      = "\u{201C}" .. q.q .. "\u{201D}",
        face      = _FACE_QUOTE,
        fgcolor   = _CLR_TEXT_QUOTE,
        width     = inner_w,
        alignment = "center",
    }
    vg[#vg+1] = _VSPAN_GAP
    vg[#vg+1] = TextBoxWidget:new{
        text      = attribution,
        face      = _FACE_ATTR,
        fgcolor   = CLR_TEXT_SUB,
        bold      = true,
        width     = inner_w,
        alignment = "center",
    }
    return vg
end

-- ---------------------------------------------------------------------------
-- Module API
-- ---------------------------------------------------------------------------

local M = {}

M.id          = "quote"
M.name        = _("Quote of the Day")
M.label       = nil   -- no section label above; the quote is self-contained
M.enabled_key = "quote_enabled"
M.default_on  = false  -- opt-in; users enable explicitly

M.getCountLabel = nil

function M.build(w, ctx)
    local inner_w = w - PAD * 2
    return FrameContainer:new{
        bordersize     = 0,
        padding        = PAD,
        padding_bottom = PAD2,
        buildQuoteWidget(inner_w),
    }
end

function M.getHeight(_ctx)
    return QUOTE_H
end

-- No sub-menu needed: the module is simply on/off.
M.getMenuItems = nil

return M
