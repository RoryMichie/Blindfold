-- Harness: the Ctrl+C/Ctrl+S status readouts — reroll cost in the shop,
-- discards in a blind, "not now" elsewhere, and big-number rendering.
local ROOT = arg[1] or "."
local loaded = {}
local function ba_require(name)
    if loaded[name] then return loaded[name] end
    local f = assert(io.open(ROOT .. "/src/" .. name:gsub("%.", "/") .. ".lua", "rb"))
    local code = f:read("*a"); f:close()
    local chunk = assert(load(code, "@" .. name, "t"))
    loaded[name] = true
    loaded[name] = chunk(ba_require) or true
    return loaded[name]
end

local Message = ba_require("ui.message")
local en = ba_require("loc.en")
Message.set_resolver(function(key)
    local node = en
    for part in tostring(key):gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return type(node) == "string" and node or nil
end)

local Status = ba_require("status")
local spoken
Status.say = function(s) spoken = s end

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

_G.G = {
    STAGES = { RUN = 2 }, STAGE = 2,
    STATES = { SELECTING_HAND = 1, SHOP = 5, HAND_PLAYED = 2, DRAW_TO_HAND = 3, PLAY_TAROT = 4, NEW_ROUND = 6 },
    STATE = 5,
    GAME = { current_round = { discards_left = 3, reroll_cost = 5 } },
}

-- In the shop: the discard readout speaks the reroll cost.
spoken = nil
Status.discards()
check(spoken == "$5", "shop: Ctrl+C reads just the cost amount", spoken)

-- In a blind: unchanged discards-remaining readout.
G.STATE = G.STATES.SELECTING_HAND
spoken = nil
Status.discards()
check(spoken and spoken:find("3") and not spoken:find("Reroll"),
    "blind: Ctrl+C reads discards remaining", spoken)

-- Shop but no cost yet (mid-construction): not-now, not a crash.
G.STATE = G.STATES.SHOP
G.GAME.current_round.reroll_cost = nil
spoken = nil
Status.discards()
check(spoken == Message.localized("GAME.NOT_NOW"):resolve(),
    "shop without a cost falls back to not-now", spoken)

-- Outside a run entirely.
G.STAGE = 99
spoken = nil
Status.discards()
check(spoken == Message.localized("GAME.NOT_NOW"):resolve(),
    "outside a run: not-now", spoken)

-- --- Big-number rendering (game number_format parity) ------------------------
-- Stub of the game's number_format: commas, scientific past 1e11; the inf
-- branch hardcodes "naneinf" (what LuaJIT's real one produces in-game; the
-- 5.4 harness would error inside the original's tonumber("inf")).
_G.number_format = function(num)
    if type(num) ~= "number" then return num or "" end
    if num == math.huge then return "naneinf" end
    if num >= 1e11 then
        local fac = math.floor(math.log(num, 10))
        return string.format("%.3f", num / (10 ^ fac)) .. "e" .. fac
    end
    return (string.format("%.0f", num):reverse():gsub("(%d%d%d)", "%1,")
        :gsub(",$", "")):reverse()
end

G.STAGE = 2
G.STATE = G.STATES.SELECTING_HAND
G.GAME.chips = 1e15
G.GAME.blind = { chips = math.huge }
spoken = nil
Status.score()
check(spoken and spoken:find("1.000e15", 1, true) and spoken:find("naneinf", 1, true),
    "score readout: scientific chips vs naneinf goal", spoken)

G.GAME.chips = 1234
G.GAME.blind = { chips = 5000 }
spoken = nil
Status.score()
check(spoken and spoken:find("1,234", 1, true) and spoken:find("5,000", 1, true),
    "score readout: comma grouping like the HUD", spoken)

-- --- Ctrl+B: what is ahead this ante ----------------------------------------
_G.localize = function(arg, cat)
    if type(arg) == "table" and arg.type == "name_text" then
        local names = { tag_foil = "Foil Tag", tag_coupon = "Coupon Tag",
            bl_small = "Small Blind", bl_big = "Big Blind", bl_hook = "The Hook" }
        return names[arg.key] or "ERROR"
    end
    return "ERROR"
end
G.STATE = G.STATES.SHOP
G.P_BLINDS = { bl_hook = { key = "bl_hook", name = "The Hook" } }
G.GAME.round_resets = {
    blind_states = { Small = "Upcoming", Big = "Upcoming", Boss = "Upcoming" },
    blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
    blind_tags = { Small = "tag_foil", Big = "tag_coupon" },
}
spoken = nil
Status.blinds()
check(spoken == "Small Blind: Foil Tag, Big Blind: Coupon Tag, Boss: The Hook",
    "fresh ante: both tags then the boss", spoken)

G.GAME.round_resets.blind_states.Small = "Skipped"
G.GAME.round_resets.blind_states.Big = "Select"
spoken = nil
Status.blinds()
check(spoken == "Big Blind: Coupon Tag, Boss: The Hook",
    "skipped small drops out; current big keeps its tag", spoken)

G.GAME.round_resets.blind_states.Big = "Defeated"
spoken = nil
Status.blinds()
check(spoken == "Boss: The Hook", "only the boss left", spoken)

G.GAME.round_resets.blind_states.Boss = "Defeated"
spoken = nil
Status.blinds()
check(spoken == Message.localized("GAME.NOT_NOW"):resolve(),
    "everything decided: not-now", spoken)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
