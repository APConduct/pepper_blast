-- Headless regression test for Pepper Blast.
--
-- Stubs the LOVE API so the whole game can be driven without a window (handy
-- over SSH, on CI, or in a sandbox with no display).
--
--   Run from the project root:  lua tests/headless.lua
--
-- It checks that:
--   * nothing errors across thousands of frames of simulated play,
--   * resizing between phone portrait, phone landscape and desktop is safe,
--   * idle/attract mode, celebrations, mute and the keyboard shortcuts run,
--   * no NaN or clipped values ever reach a colour, transform or audio sample,
--   * the synthesised whistles land in cockatiel range (roughly 0.6-3 kHz).

package.path = "./?.lua;" .. package.path

local RATE = 44100
local failures = {}

local function check(ok, msg)
    if not ok then failures[#failures + 1] = msg end
    return ok
end

--------------------------------------------------------------------------
-- LOVE stubs
--------------------------------------------------------------------------

local fallbackCalls = {}

local function stub(name, tbl)
    return setmetatable(tbl, {
        __index = function(_, k)
            fallbackCalls[name .. "." .. k] = true
            return function() end
        end,
    })
end

local W, H = 900, 620
local soundBuffers = {}
local sampleCount, samplePeak, sampleNaN = 0, 0, false

local love = {}
_G.love = love

love.math = stub("math", {
    random = function(a, b)
        if a and b then return math.random(a, b) end
        if a then return math.random(a) end
        return math.random()
    end,
    setRandomSeed = function(s) math.randomseed(s) end,
})

local function assertFinite(v, what)
    check(type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge,
        what .. " got " .. tostring(v))
end

love.graphics = stub("graphics", {
    getDimensions = function() return W, H end,
    getWidth = function() return W end,
    getHeight = function() return H end,
    isActive = function() return true end,
    newFont = function(size)
        check(type(size) == "number" and size >= 1, "font size " .. tostring(size))
        return {
            getHeight = function() return size * 1.2 end,
            getWidth = function(_, s) return #tostring(s) * size * 0.5 end,
        }
    end,
    newMesh = function(count)
        check(count == 4, "unexpected mesh vertex count")
        return {
            setVertex = function(_, i, ...)
                check(i >= 1 and i <= 4, "mesh vertex index " .. tostring(i))
                for _, v in ipairs({ ... }) do assertFinite(v, "mesh vertex") end
            end,
        }
    end,
    setColor = function(r, g, b, a)
        if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
        for _, v in ipairs({ r, g, b, a or 1 }) do assertFinite(v, "setColor") end
    end,
    setLineWidth = function(w)
        assertFinite(w, "setLineWidth")
        check(w > 0, "setLineWidth must be positive, got " .. tostring(w))
    end,
    circle = function(_, x, y, r)
        assertFinite(x, "circle x") assertFinite(y, "circle y")
        check(r >= 0, "negative circle radius " .. tostring(r))
    end,
    ellipse = function(_, x, y, rx, ry)
        assertFinite(x, "ellipse x") assertFinite(y, "ellipse y")
        assertFinite(rx, "ellipse rx") assertFinite(ry, "ellipse ry")
    end,
    arc = function(_, _, x, y, r) assertFinite(x, "arc x") assertFinite(r, "arc r") end,
    rectangle = function(_, x, y, w, h)
        assertFinite(x, "rect x") assertFinite(w, "rect w") assertFinite(h, "rect h")
    end,
    scale = function(sx, sy)
        assertFinite(sx, "scale x") assertFinite(sy, "scale y")
        check(sx ~= 0 and sy ~= 0, "degenerate scale")
    end,
    translate = function(x, y) assertFinite(x, "translate x") assertFinite(y, "translate y") end,
    rotate = function(a) assertFinite(a, "rotate") end,
})

love.window = stub("window", {
    getSafeArea = function() return 0, 0, W, H end,
    getDPIScale = function() return 1 end,
    getFullscreen = function() return false end,
})

local function source()
    return {
        clone = function() return source() end,
        setPitch = function(_, p) check(p > 0, "bad pitch " .. tostring(p)) end,
        setVolume = function(_, v) check(v >= 0 and v <= 1, "bad volume " .. tostring(v)) end,
        play = function() end,
        stop = function() end,
    }
end

love.audio = stub("audio", {
    newSource = function() return source() end,
    setVolume = function(v) check(v >= 0 and v <= 1, "master volume") end,
    stop = function() end,
})

love.sound = stub("sound", {
    newSoundData = function(frames, rate, bits, channels)
        check(frames > 0, "empty sound")
        check(rate == RATE and bits == 16 and channels == 1, "unexpected sound format")
        local buf = { frames = frames, s = {} }
        soundBuffers[#soundBuffers + 1] = buf
        return {
            setSample = function(_, i, v)
                check(i >= 0 and i < frames, "sample index out of range")
                if v ~= v then sampleNaN = true end
                if math.abs(v) > samplePeak then samplePeak = math.abs(v) end
                sampleCount = sampleCount + 1
                buf.s[i] = v
            end,
        }
    end,
})

local files = {}
love.filesystem = stub("filesystem", {
    getInfo = function(p) return files[p] and { type = "file" } or nil end,
    read = function(p) return files[p] end,
    write = function(p, data) files[p] = data return true end,
})

love.event = stub("event", { quit = function() end })
love.timer = stub("timer", { getTime = function() return os.clock() end })
love.keyboard = stub("keyboard", {})

--------------------------------------------------------------------------
-- Drive the game
--------------------------------------------------------------------------

math.randomseed(20240817)
dofile("main.lua")
love.load()

local frames, touchId = 0, 0

local function step(n, tapsPerFrame)
    for _ = 1, n do
        frames = frames + 1
        for _ = 1, (tapsPerFrame or 0) do
            local x, y = math.random() * W, math.random() * H
            if frames % 3 == 0 then
                touchId = touchId + 1
                love.touchpressed(touchId, x, y)
                love.touchreleased(touchId, x, y)
            else
                love.mousepressed(x, y, 1, false)
                love.mousereleased(x, y, 1, false)
            end
        end
        love.update(1 / 60)
        love.draw()
    end
end

local function resizeTo(w, h)
    W, H = w, h
    love.resize(w, h)
end

step(600, 2)                                  -- ordinary play, many pops + songs
love.touchpressed(90001, W - 8, 8)            -- hidden hold-to-mute corner
step(120, 0)
love.touchreleased(90001, W - 8, 8)
resizeTo(390, 844)  step(300, 2)              -- iPhone portrait
resizeTo(844, 390)  step(300, 2)              -- iPhone landscape
resizeTo(1280, 800) step(200, 2)              -- desktop
step(1800, 0)                                 -- long idle -> attract mode
love.keypressed("m") love.keypressed("m")
love.keypressed("f")
step(60, 1)
love.keypressed("r")
step(60, 1)

check(not sampleNaN, "NaN in synthesised audio")
check(samplePeak > 0.05 and samplePeak <= 1.0, "audio peak out of range: " .. samplePeak)
check(tonumber(files["best.txt"]) and tonumber(files["best.txt"]) > 0,
    "best score was never saved")

--------------------------------------------------------------------------
-- Seed size vs hit size
--
-- Pepper prefers seed-sized targets, but shrinking the art must not shrink
-- what he has to hit. Measure both through the public API.
--------------------------------------------------------------------------

local Target = require("src.target")

local probeWorld = {
    w = 900, h = 620, scale = 620 / 520,
    beat = 0, calm = 0, party = 0, curiosity = 0,
}

local function hitRadiusOf(t)
    -- Largest offset from the centre that still registers as a touch.
    local lo, hi = 0, 4000
    for _ = 1, 40 do
        local mid = (lo + hi) / 2
        if t:contains(t.x + mid, t.y) then lo = mid else hi = mid end
    end
    return lo
 end

local minSeed, maxSeed = math.huge, 0
local minHit, maxHit = math.huge, 0
local kinds = {}
for _ = 1, 600 do
    local t = Target.new(probeWorld, 450, 310)
    kinds[t.kind] = (kinds[t.kind] or 0) + 1
    minSeed = math.min(minSeed, t.radius * 2)
    maxSeed = math.max(maxSeed, t.radius * 2)
    local hit = hitRadiusOf(t) * 2
    minHit = math.min(minHit, hit)
    maxHit = math.max(maxHit, hit)
end

print()
print(string.format("seed diameter  %.0f-%.0f px    hit diameter  %.0f-%.0f px  (at 900x620)",
    minSeed, maxSeed, minHit, maxHit))
local names = {}
for k, v in pairs(kinds) do
    names[#names + 1] = string.format("%s %.0f%%", k, v / 6)
end
table.sort(names)
print("seed mix:      " .. table.concat(names, ", "))

check(maxSeed <= 80, "seeds are no longer seed-sized: " .. math.floor(maxSeed) .. " px")
check(minHit >= 70, "hit area got too small to be fair: " .. math.floor(minHit) .. " px")
check(minHit > maxSeed, "the smallest hit area should still beat the largest seed")

--------------------------------------------------------------------------
-- Whistle frequency sanity check
--------------------------------------------------------------------------

local sounds = { "pop1", "pop2", "pop3", "pop4", "pop5", "pop6", "pop7",
                 "tick", "attract", "song1", "song2", "song3" }

print()
print(string.format("%-8s %8s %8s %9s", "sound", "seconds", "peak", "mean Hz"))
for i, buf in ipairs(soundBuffers) do
    local crossings, first, last, peak = 0, nil, nil, 0
    local prev = buf.s[0] or 0
    for k = 1, buf.frames - 1 do
        local v = buf.s[k] or 0
        if math.abs(v) > peak then peak = math.abs(v) end
        if (prev >= 0) ~= (v >= 0) then
            crossings = crossings + 1
            first = first or k
            last = k
        end
        prev = v
    end
    local span = (first and last) and (last - first) / RATE or 0
    local hz = span > 0 and (crossings - 1) / 2 / span or 0
    print(string.format("%-8s %8.2f %8.3f %9.0f", sounds[i] or ("#" .. i),
        buf.frames / RATE, peak, hz))
    check(hz > 500 and hz < 4000,
        (sounds[i] or i) .. " is outside cockatiel whistle range: " .. math.floor(hz) .. " Hz")
end

--------------------------------------------------------------------------

print()
if #failures == 0 then
    print(string.format("PASS - %d frames, %d audio samples, best score %s",
        frames, sampleCount, tostring(files["best.txt"])))
else
    print(string.format("FAIL - %d problem(s):", #failures))
    for _, f in ipairs(failures) do print("  " .. f) end
    os.exit(1)
end
