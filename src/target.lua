-- The dancing seeds Pepper is supposed to touch.
--
-- Everything is drawn with primitives (no image assets). The seeds are drawn
-- small and roughly life-size, because that is what reads as *food* to a
-- cockatiel. Two things keep them playable at that size:
--
--   * the hit area is HIT_SCALE times the visible art, so shrinking the
--     picture does not shrink the target Pepper has to reach;
--   * the dance amplitude is measured in screen units rather than seed radii,
--     so tiny seeds still dance just as much as big ones did.

local Target = {}
Target.__index = Target

local TAU = math.pi * 2

local HIT_SCALE = 2.4   -- invisible hit radius / visible radius
local DANCE_BOB = 9     -- dance amplitude in design units, NOT seed radii
local DANCE_SWAY = 7

local KIND = {
    millet = {
        size = 0.82,
        colors = { { 1.00, 0.80, 0.24 }, { 1.00, 0.66, 0.16 }, { 0.90, 0.40, 0.30 } },
    },
    canary = {
        size = 0.92,
        colors = { { 0.97, 0.89, 0.48 }, { 0.80, 0.90, 0.48 } },
    },
    safflower = {
        size = 1.00,
        colors = { { 1.00, 0.96, 0.87 }, { 1.00, 0.86, 0.70 } },
    },
    sunflower = {
        size = 1.15,
        colors = { { 0.38, 0.38, 0.44 }, { 0.27, 0.26, 0.32 } },
    },
}

-- Weighted bag: millet and canary seed are the everyday favourites, sunflower
-- is the occasional fatty treat.
local BAG = {
    "millet", "millet", "millet", "millet",
    "canary", "canary", "canary",
    "safflower", "safflower",
    "sunflower",
}

-- Bright seed colours, used for the HUD progress seeds.
Target.PALETTE = {
    { 1.00, 0.80, 0.24 }, { 1.00, 0.66, 0.16 }, { 0.97, 0.89, 0.48 },
    { 0.80, 0.90, 0.48 }, { 1.00, 0.96, 0.87 }, { 0.90, 0.40, 0.30 },
}

local function shade(c, k)
    return { c[1] * k, c[2] * k, c[3] * k }
end

local function lift(c, k)
    return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
end

function Target.new(world, x, y)
    local self = setmetatable({}, Target)

    self.kind = BAG[love.math.random(#BAG)]
    local spec = KIND[self.kind]

    self.color = spec.colors[love.math.random(#spec.colors)]
    self.accent = lift(self.color, 0.7)
    self.halo = lift(self.color, 0.45)
    self.dark = shade(self.color, 0.5)

    self.baseRadius = (17 + love.math.random() * 8) * spec.size
    self.radius = self.baseRadius * world.scale
    self.baseSpeed = 45 + love.math.random() * 50

    self.x, self.y = x, y
    self.vx, self.vy = 0, 0
    self.tx, self.ty = x, y

    self.age = 0
    self.phase = love.math.random() * TAU
    self.spin = (love.math.random() < 0.5 and -1 or 1) * (0.2 + love.math.random() * 0.5)
    self.tilt = love.math.random() * TAU
    self.repathIn = 0

    -- Initialised here too: a seed spawned late in an update tick is drawn
    -- before it has ever been updated.
    self.bob, self.sway, self.rot, self.squash = 0, 0, self.tilt, 1
    self.appear = 0

    self:pick_waypoint(world)
    return self
end

function Target:pick_waypoint(world)
    local m = self.radius * 1.1 + (DANCE_BOB + 6) * world.scale
    local x = m + love.math.random() * math.max(1, world.w - 2 * m)
    local y = m + love.math.random() * math.max(1, world.h - 2 * m)

    -- When Pepper has wandered off, the seeds gather in the middle of the
    -- screen where they are easiest to notice.
    if world.calm > 0 then
        local k = world.calm * 0.65
        x = x + (world.w * 0.5 - x) * k
        y = y + (world.h * 0.5 - y) * k
    end

    self.tx, self.ty = x, y
    self.repathIn = 1.0 + love.math.random() * 1.8
    if world.party > 0 then self.repathIn = self.repathIn * 0.5 end
end

function Target:update(dt, world)
    self.age = self.age + dt
    -- Seeds swell a little in attract mode so they are easier to spot.
    self.radius = self.baseRadius * world.scale * (1 + 0.35 * world.calm)

    self.repathIn = self.repathIn - dt
    local dx, dy = self.tx - self.x, self.ty - self.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if self.repathIn <= 0 or dist < self.radius * 0.6 then
        self:pick_waypoint(world)
        dx, dy = self.tx - self.x, self.ty - self.y
        dist = math.sqrt(dx * dx + dy * dy)
    end

    local speed = self.baseSpeed * world.scale
        * (1 - 0.55 * world.calm)
        * (world.party > 0 and 1.35 or 1)

    if dist > 1 then
        local k = 1 - math.exp(-3.2 * dt)
        self.vx = self.vx + (dx / dist * speed - self.vx) * k
        self.vy = self.vy + (dy / dist * speed - self.vy) * k
    end

    -- Curiosity: for a moment after a tap, the seeds drift toward wherever
    -- Pepper touched. It quietly turns near-misses into hits.
    if world.curiosity > 0 and world.tapX then
        local cx, cy = world.tapX - self.x, world.tapY - self.y
        local cd = math.sqrt(cx * cx + cy * cy)
        if cd > 1 then
            local pull = world.curiosity * 55 * world.scale * dt
            self.vx = self.vx + cx / cd * pull
            self.vy = self.vy + cy / cd * pull
        end
    end

    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt

    -- Margin covers the dance offset as well, so a seed never bobs off-screen.
    local m = self.radius + (DANCE_BOB + 2) * world.scale
    if self.x < m then self.x, self.vx = m, math.abs(self.vx) end
    if self.x > world.w - m then self.x, self.vx = world.w - m, -math.abs(self.vx) end
    if self.y < m then self.y, self.vy = m, math.abs(self.vy) end
    if self.y > world.h - m then self.y, self.vy = world.h - m, -math.abs(self.vy) end

    -- The dance: everyone bobs on the same beat, each with its own offset.
    local beat = world.beat * TAU
    self.bob = math.sin(beat + self.phase) * DANCE_BOB * world.scale
    self.sway = math.cos(beat * 0.5 + self.phase) * DANCE_SWAY * world.scale
    self.rot = self.tilt + math.sin(beat * 0.5 + self.phase) * 0.3 + self.spin * self.age * 0.4
    self.squash = 1 + 0.05 * math.sin(beat * 2 + self.phase)
    self.appear = math.min(1, self.age / 0.32)
end

--- Where the seed is actually drawn (and therefore where it can be hit).
function Target:pos()
    return self.x + self.sway, self.y + self.bob
end

--- Generous hit area: beaks are not styluses, and these seeds are tiny.
function Target:contains(px, py)
    local x, y = self:pos()
    local r = self.radius * HIT_SCALE
    local dx, dy = px - x, py - y
    return dx * dx + dy * dy <= r * r
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local function outline(r)
    love.graphics.setLineWidth(math.max(1.5, r * 0.11))
end

local function shine(r)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.ellipse("fill", -r * 0.26, -r * 0.34, r * 0.19, r * 0.12, 12)
end

--- Seed silhouettes. `p` blunts the ends, `sharp` narrows the waist,
--- `topBias` widens the top for teardrop/cone shapes.
local function seed_shape(rx, ry, p, sharp, topBias)
    local n = 28
    local pts = {}
    for i = 0, n - 1 do
        local t = i / n * TAU
        local y = -math.cos(t)
        local k = (1 - math.abs(y) ^ p) ^ sharp
        local bias = 1 + topBias * (-y)
        pts[#pts + 1] = (math.sin(t) >= 0 and 1 or -1) * rx * k * bias
        pts[#pts + 1] = y * ry
    end
    return pts
end

local STRIPES = { -0.34, 0, 0.34 }

local draw = {}

function draw.millet(self, r)
    love.graphics.setColor(self.dark)
    love.graphics.circle("fill", 0, r * 0.1, r)
    love.graphics.setColor(self.color)
    love.graphics.circle("fill", 0, 0, r * 0.94)

    shine(r)

    love.graphics.setColor(self.accent)
    love.graphics.ellipse("fill", 0, r * 0.56, r * 0.2, r * 0.13, 10)

    love.graphics.setColor(1, 1, 1, 0.9)
    outline(r)
    love.graphics.circle("line", 0, 0, r * 0.94)
end

function draw.sunflower(self, r)
    local pts = seed_shape(r * 0.62, r * 0.95, 3, 0.55, 0.12)

    love.graphics.push()
    love.graphics.translate(0, r * 0.07)
    love.graphics.setColor(self.dark)
    love.graphics.polygon("fill", pts)
    love.graphics.pop()

    love.graphics.setColor(self.color)
    love.graphics.polygon("fill", pts)

    -- The lengthwise pale stripes that make a sunflower seed recognisable.
    love.graphics.setColor(0.95, 0.93, 0.86, 0.8)
    for _, ox in ipairs(STRIPES) do
        local h = ox == 0 and 0.58 or 0.4
        love.graphics.ellipse("fill", r * 0.62 * ox, 0, r * 0.055, r * h, 10)
    end

    shine(r)
    love.graphics.setColor(1, 1, 1, 0.92)
    outline(r)
    love.graphics.polygon("line", pts)
end

function draw.safflower(self, r)
    local pts = seed_shape(r * 0.56, r * 1.0, 4, 0.5, 0.28)

    love.graphics.push()
    love.graphics.translate(0, r * 0.07)
    love.graphics.setColor(self.dark)
    love.graphics.polygon("fill", pts)
    love.graphics.pop()

    love.graphics.setColor(self.color)
    love.graphics.polygon("fill", pts)

    love.graphics.setColor(shade(self.color, 0.8))
    love.graphics.setLineWidth(math.max(1, r * 0.07))
    love.graphics.line(0, -r * 0.6, 0, r * 0.8)

    shine(r)
    love.graphics.setColor(1, 1, 1, 0.92)
    outline(r)
    love.graphics.polygon("line", pts)
end

function draw.canary(self, r)
    local pts = seed_shape(r * 0.46, r * 1.05, 2, 0.8, 0)

    love.graphics.push()
    love.graphics.translate(0, r * 0.06)
    love.graphics.setColor(self.dark)
    love.graphics.polygon("fill", pts)
    love.graphics.pop()

    love.graphics.setColor(self.color)
    love.graphics.polygon("fill", pts)

    love.graphics.setColor(shade(self.color, 0.72))
    love.graphics.setLineWidth(math.max(1, r * 0.08))
    love.graphics.line(0, -r * 0.62, 0, r * 0.62)

    shine(r)
    love.graphics.setColor(1, 1, 1, 0.92)
    outline(r)
    love.graphics.polygon("line", pts)
end

function Target:draw()
    local x, y = self:pos()
    local r = self.radius

    -- Springy pop-in (back-out easing), then the dance squash-and-stretch.
    local u = self.appear - 1
    local pop = math.max(0.02, 1 + 2.70158 * u * u * u + 1.70158 * u * u)

    -- Pale halo, drawn unrotated: at this size it is doing real work making a
    -- small seed noticeable, especially the dark sunflower ones.
    love.graphics.setColor(self.halo[1], self.halo[2], self.halo[3], 0.16 * pop)
    love.graphics.circle("fill", x, y, r * pop * 1.9)

    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(self.rot)
    love.graphics.scale(pop / self.squash, pop * self.squash)

    ;(draw[self.kind] or draw.millet)(self, r)

    love.graphics.pop()
end

return Target
