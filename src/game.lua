-- Pepper Blast
--
-- Design rules (this is a game for a cockatiel, not a human):
--   * No losing, no timers, no penalties. Every touch does something nice.
--   * Seeds are drawn small (Pepper's preference) but their hit areas are
--     much larger than the art, so aiming stays forgiving.
--   * The reward is sound: pops climb a scale, milestones play a full song.
--   * Nothing important is behind a menu, because Pepper cannot use menus.

local Audio = require("src.audio")
local Target = require("src.target")
local Effects = require("src.effects")

local Game = {}

local REWARD_EVERY = 10     -- pops per cockatiel song
local PARTY_TIME = 5.0      -- seconds of celebration
local IDLE_AFTER = 14       -- seconds before the game starts calling Pepper back
local COMBO_WINDOW = 2.4
local BASE_TARGETS = 5      -- seeds are small, so scatter more of them
local MAX_TARGETS = 9
local HOLD_TO_MUTE = 1.1    -- birds tap, they do not hold: safe hidden control

local SAVE_FILE = "best.txt"
local TAU = math.pi * 2

local G
local bgMesh
local fonts = {}

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function loadBest()
    if love.filesystem.getInfo(SAVE_FILE) then
        local raw = love.filesystem.read(SAVE_FILE)
        local n = tonumber(raw or "")
        if n then return math.max(0, math.floor(n)) end
    end
    return 0
end

local function saveBest(n)
    pcall(love.filesystem.write, SAVE_FILE, tostring(n))
end

local function safeArea()
    local gw, gh = love.graphics.getDimensions()
    local ok, x, y, w, h = pcall(love.window.getSafeArea)
    if ok and type(x) == "number" and w and h and w > 0 and h > 0 then
        local s = love.window.getDPIScale and love.window.getDPIScale() or 1
        x, y, w, h = x * s, y * s, w * s, h * s
        if w <= gw + 1 and h <= gh + 1 then
            return x, y, w, h
        end
    end
    return 0, 0, gw, gh
end

local function lerp(a, b, t) return a + (b - a) * t end

--------------------------------------------------------------------------
-- Spawning
--------------------------------------------------------------------------

local function spawnPoint()
    -- Best-of-six sampling keeps the seeds from piling up on each other.
    local bestX, bestY, bestScore = G.w * 0.5, G.h * 0.5, -1
    local m = 55 * G.scale
    for _ = 1, 6 do
        local x = m + love.math.random() * math.max(1, G.w - 2 * m)
        local y = m + love.math.random() * math.max(1, G.h - 2 * m)
        local nearest = math.huge
        for _, t in ipairs(G.targets) do
            local tx, ty = t:pos()
            local d = (tx - x) ^ 2 + (ty - y) ^ 2
            if d < nearest then nearest = d end
        end
        if nearest > bestScore then bestX, bestY, bestScore = x, y, nearest end
    end
    return bestX, bestY
end

local function spawn()
    local x, y = spawnPoint()
    G.targets[#G.targets + 1] = Target.new(G.world, x, y)
end

local function desiredCount()
    local n = BASE_TARGETS + math.floor(G.score / 14)
    n = math.min(n, MAX_TARGETS)
    if G.party > 0 then n = n + 4 end
    return n
end

--------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------

function Game.load()
    Audio.load()

    G = {
        targets = {},
        score = 0,
        best = loadBest(),
        combo = 0,
        comboTimer = 0,
        party = 0,
        partyGlow = 0,
        songsPlayed = 0,
        time = 0,
        idle = 0,
        attractIn = 0,
        spawnIn = 0,
        intro = 1,
        flash = 0,
        shake = 0,
        presses = {},
        muteFeedback = 0,
        world = {
            w = 1, h = 1, scale = 1, beat = 0,
            calm = 0, party = 0, curiosity = 0,
            tapX = nil, tapY = nil,
            targets = nil,
        },
    }
    G.world.targets = G.targets

    bgMesh = love.graphics.newMesh(4, "fan", "stream")

    Game.resize(love.graphics.getDimensions())
    Effects.reset()

    for _ = 1, BASE_TARGETS do spawn() end
end

function Game.resize(w, h)
    if not G then return end

    local oldW, oldH = G.w or w, G.h or h
    G.w, G.h = w, h
    G.scale = math.max(0.5, math.min(w, h) / 520)

    G.world.w, G.world.h, G.world.scale = w, h, G.scale

    fonts.huge = love.graphics.newFont(math.floor(64 * G.scale))
    fonts.big = love.graphics.newFont(math.floor(38 * G.scale))
    fonts.small = love.graphics.newFont(math.floor(16 * G.scale))

    if oldW > 0 and oldH > 0 and (oldW ~= w or oldH ~= h) then
        local sx, sy = w / oldW, h / oldH
        for _, t in ipairs(G.targets) do
            t.x, t.y = t.x * sx, t.y * sy
            t.tx, t.ty = t.tx * sx, t.ty * sy
        end
    end
end

--------------------------------------------------------------------------
-- Rewards
--------------------------------------------------------------------------

local function celebrate()
    G.party = PARTY_TIME
    G.songsPlayed = G.songsPlayed + 1
    G.flash = 1
    G.shake = 1
    Audio.song()
    Effects.confettiBurst(G.w, G.h, G.scale, 90)
end

local function popTarget(index)
    local t = table.remove(G.targets, index)
    local x, y = t:pos()

    G.score = G.score + 1
    G.combo = G.combo + 1
    G.comboTimer = COMBO_WINDOW
    G.idle = 0
    G.attractIn = 0
    G.intro = math.max(0, G.intro - 0.34)
    G.flash = math.max(G.flash, 0.35)

    if G.score > G.best then
        G.best = G.score
        saveBest(G.best)
    end

    local power = 1 + math.min(G.combo, 8) * 0.08
    Effects.burst(x, y, t.color, G.scale, power)
    Effects.ring(x, y, t.color, G.scale, power)
    Audio.pop(G.combo)

    if G.score % REWARD_EVERY == 0 then
        celebrate()
    end

    G.spawnIn = math.max(G.spawnIn, 0.18)
end

--------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------

local function inMuteCorner(x, y)
    local sx, sy, sw, _sh = safeArea()
    local size = 64 * G.scale
    return x >= sx + sw - size and y <= sy + size
end

function Game.press(id, x, y)
    if not G then return end

    G.presses[id] = { x = x, y = y, held = 0, corner = inMuteCorner(x, y) }

    G.world.tapX, G.world.tapY = x, y
    G.world.curiosity = 1
    Effects.ripple(x, y, G.scale)

    -- Nearest overlapping target wins. This matters more now that the hit
    -- areas are much wider than the seeds and routinely overlap.
    local hitIndex, hitDist
    for i, t in ipairs(G.targets) do
        if t:contains(x, y) then
            local tx, ty = t:pos()
            local d = (tx - x) ^ 2 + (ty - y) ^ 2
            if not hitDist or d < hitDist then
                hitIndex, hitDist = i, d
            end
        end
    end

    if hitIndex then
        popTarget(hitIndex)
    else
        Audio.tick()
        G.idle = math.max(0, G.idle - 4)
    end
end

function Game.release(id)
    if G then G.presses[id] = nil end
end

function Game.keypressed(key)
    if not G then return end
    if key == "escape" then
        love.event.quit()
    elseif key == "m" then
        Audio.toggleMute()
        G.muteFeedback = 1.4
    elseif key == "f" then
        local full = love.window.getFullscreen()
        love.window.setFullscreen(not full, "desktop")
    elseif key == "r" then
        G.score, G.combo, G.party = 0, 0, 0
    end
end

--------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------

function Game.update(dt)
    if not G then return end

    G.time = G.time + dt
    G.world.beat = G.time * 0.85       -- ~51 bpm sway; calm, not frantic

    G.idle = G.idle + dt
    G.world.calm = math.max(0, math.min(1, (G.idle - IDLE_AFTER) / 5))

    if G.comboTimer > 0 then
        G.comboTimer = G.comboTimer - dt
        if G.comboTimer <= 0 then G.combo = 0 end
    end

    if G.party > 0 then
        G.party = math.max(0, G.party - dt)
        if G.party > 0 and love.math.random() < dt * 6 then
            Effects.confettiBurst(G.w, G.h, G.scale, 6)
        end
    end
    G.world.party = G.party
    G.partyGlow = lerp(G.partyGlow, G.party > 0 and 1 or 0, 1 - math.exp(-4 * dt))

    G.flash = math.max(0, G.flash - dt * 2.2)
    G.shake = math.max(0, G.shake - dt * 1.8)
    G.muteFeedback = math.max(0, G.muteFeedback - dt)
    G.world.curiosity = math.max(0, G.world.curiosity - dt * 0.7)

    -- Hidden hold-to-mute in the top-right corner.
    for _, p in pairs(G.presses) do
        if p.corner and not p.done then
            p.held = p.held + dt
            if p.held >= HOLD_TO_MUTE then
                p.done = true
                Audio.toggleMute()
                G.muteFeedback = 1.6
            end
        end
    end

    for _, t in ipairs(G.targets) do
        t:update(dt, G.world)
    end

    G.spawnIn = G.spawnIn - dt
    if G.spawnIn <= 0 and #G.targets < desiredCount() then
        spawn()
        G.spawnIn = 0.25
    end
    -- Party is over: retire the extras with a little puff instead of a
    -- seed blinking out of existence in front of Pepper.
    while #G.targets > desiredCount() + 2 do
        local t = table.remove(G.targets)
        local x, y = t:pos()
        Effects.burst(x, y, t.color, G.scale, 0.5)
    end

    -- Attract mode: soft contact calls when nobody is playing.
    if G.world.calm >= 1 then
        G.attractIn = G.attractIn - dt
        if G.attractIn <= 0 then
            Audio.attract()
            G.attractIn = 7 + love.math.random() * 4
        end
    end

    Effects.update(dt, G.w, G.h, G.scale)
end

--------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------

local function drawBackground()
    local glow = G.partyGlow
    local pulse = 0.5 + 0.5 * math.sin(G.time * 3)

    local topR, topG, topB = 0.05, 0.10, 0.20
    local botR, botG, botB = 0.07, 0.24, 0.30

    if glow > 0.01 then
        local r1, g1, b1 = Effects.hsv(G.time * 0.35, 0.75, 0.55 + 0.15 * pulse)
        local r2, g2, b2 = Effects.hsv(G.time * 0.35 + 0.35, 0.8, 0.4 + 0.15 * pulse)
        topR, topG, topB = lerp(topR, r1, glow), lerp(topG, g1, glow), lerp(topB, b1, glow)
        botR, botG, botB = lerp(botR, r2, glow), lerp(botG, g2, glow), lerp(botB, b2, glow)
    end

    bgMesh:setVertex(1, 0, 0, 0, 0, topR, topG, topB, 1)
    bgMesh:setVertex(2, 1, 0, 1, 0, topR, topG, topB, 1)
    bgMesh:setVertex(3, 1, 1, 1, 1, botR, botG, botB, 1)
    bgMesh:setVertex(4, 0, 1, 0, 1, botR, botG, botB, 1)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bgMesh, 0, 0, 0, G.w, G.h)

    Effects.drawAmbient(G.w, G.h, G.time)
end

local function drawSeed(x, y, r, filled, color)
    if filled then
        love.graphics.setColor(color)
        love.graphics.ellipse("fill", x, y, r, r * 1.25, 12)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.setLineWidth(math.max(1.5, r * 0.3))
        love.graphics.ellipse("line", x, y, r, r * 1.25, 12)
    else
        love.graphics.setColor(1, 1, 1, 0.22)
        love.graphics.setLineWidth(math.max(1.5, r * 0.3))
        love.graphics.ellipse("line", x, y, r, r * 1.25, 12)
    end
end

local function drawHud()
    local sx, sy, sw, sh = safeArea()
    local pad = 16 * G.scale

    -- Progress toward the next song, drawn as a row of seeds so it means
    -- something visually even to a bird.
    local done = G.score % REWARD_EVERY
    if G.party > 0 then done = REWARD_EVERY end
    local r = 7 * G.scale
    local gap = r * 3.4
    local total = (REWARD_EVERY - 1) * gap
    local x0 = sx + sw * 0.5 - total * 0.5
    local y0 = sy + pad + r * 1.4
    for i = 1, REWARD_EVERY do
        local filled = i <= done
        local bounce = 0
        if filled then
            bounce = math.sin(G.time * 6 + i * 0.5) * r * 0.25
        end
        local color = Target.PALETTE[((i - 1) % #Target.PALETTE) + 1]
        drawSeed(x0 + (i - 1) * gap, y0 + bounce, r, filled, color)
    end

    -- Score for Joey.
    love.graphics.setFont(fonts.big)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print(tostring(G.score), sx + pad, sy + pad * 0.6)

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.print("best " .. G.best, sx + pad, sy + pad * 0.6 + fonts.big:getHeight() * 0.95)

    if G.combo >= 3 then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(1, 0.9, 0.3, math.min(1, G.comboTimer))
        love.graphics.printf("x" .. G.combo, sx, sy + pad, sw - pad, "right")
    end

    if G.muteFeedback > 0 then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(1, 1, 1, math.min(1, G.muteFeedback))
        love.graphics.printf(Audio.isMuted() and "sound off" or "sound on",
            sx, sy + sh - pad - fonts.small:getHeight(), sw - pad, "right")
    end
end

local function drawIntro()
    if G.intro <= 0.01 then return end
    local a = G.intro
    local sx, sy, sw, sh = safeArea()

    love.graphics.setColor(0, 0, 0, 0.35 * a)
    love.graphics.rectangle("fill", 0, 0, G.w, G.h)

    local cy = sy + sh * 0.42
    love.graphics.setFont(fonts.huge)
    local wobble = math.sin(G.time * 2) * 6 * G.scale
    love.graphics.setColor(1, 0.85, 0.25, a)
    love.graphics.printf("PEPPER BLAST", sx, cy + wobble, sw, "center")

    love.graphics.setFont(fonts.small)
    love.graphics.setColor(1, 1, 1, 0.8 * a)
    love.graphics.printf("touch the dancing seeds",
        sx, cy + fonts.huge:getHeight() * 1.05, sw, "center")
    love.graphics.printf("hold the top-right corner for sound on/off",
        sx, sy + sh - fonts.small:getHeight() * 2.2, sw, "center")
end

function Game.draw()
    if not G then return end

    love.graphics.push()
    if G.shake > 0 then
        local k = G.shake * G.shake * 8 * G.scale
        love.graphics.translate(
            (love.math.random() - 0.5) * k,
            (love.math.random() - 0.5) * k)
    end

    drawBackground()
    Effects.drawBehind()

    for _, t in ipairs(G.targets) do
        t:draw()
    end

    Effects.drawFront()

    -- "Come play!" halo during attract mode.
    if G.world.calm > 0.05 then
        local a = G.world.calm * (0.12 + 0.08 * math.sin(G.time * 2))
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.setLineWidth(6 * G.scale)
        love.graphics.circle("line", G.w * 0.5, G.h * 0.5,
            math.min(G.w, G.h) * (0.3 + 0.05 * math.sin(G.time * 2)))
    end

    love.graphics.pop()

    if G.flash > 0 then
        love.graphics.setColor(1, 1, 1, G.flash * 0.35)
        love.graphics.rectangle("fill", 0, 0, G.w, G.h)
    end

    drawHud()
    drawIntro()

    love.graphics.setColor(1, 1, 1, 1)
end

return Game
