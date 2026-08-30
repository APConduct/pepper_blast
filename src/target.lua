-- The dancing snacks Pepper is supposed to touch.
--
-- Everything is drawn with primitives (no image assets) using very saturated
-- colours and hard white outlines, because that is what reads best to a bird
-- looking at a screen from 10cm away.

local Target = {}
Target.__index = Target

local TAU = math.pi * 2

local KINDS = { "berry", "bloom", "flutter", "bubble" }

Target.PALETTE = {
    { 1.00, 0.24, 0.33 }, -- strawberry
    { 1.00, 0.52, 0.10 }, -- carrot
    { 1.00, 0.84, 0.16 }, -- millet
    { 0.40, 0.91, 0.36 }, -- pea
    { 0.18, 0.78, 1.00 }, -- sky
    { 0.72, 0.45, 1.00 }, -- grape
    { 1.00, 0.44, 0.78 }, -- blossom
}

local function shade(c, k)
    return { c[1] * k, c[2] * k, c[3] * k }
end

local function lift(c, k)
    return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
end

function Target.new(world, x, y)
    local self = setmetatable({}, Target)

    self.kind = KINDS[love.math.random(#KINDS)]
    self.color = Target.PALETTE[love.math.random(#Target.PALETTE)]
    self.accent = lift(self.color, 0.72)
    self.dark = shade(self.color, 0.55)

    self.baseRadius = 44 + love.math.random() * 16
    self.radius = self.baseRadius * world.scale
    self.baseSpeed = 55 + love.math.random() * 55

    self.x, self.y = x, y
    self.vx, self.vy = 0, 0
    self.tx, self.ty = x, y

    self.age = 0
    self.phase = love.math.random() * TAU
    self.spin = (love.math.random() < 0.5 and -1 or 1) * (0.15 + love.math.random() * 0.35)
    self.flapRate = 5 + love.math.random() * 3
    self.repathIn = 0

    -- Initialised here too: a target spawned late in an update tick is drawn
    -- before it has ever been updated.
    self.bob, self.sway, self.rot, self.squash = 0, 0, 0, 1
    self.appear = 0

    self:pickWaypoint(world)
    return self
end

function Target:pickWaypoint(world)
    local m = self.radius * 1.1 + 6 * world.scale
    local x = m + love.math.random() * math.max(1, world.w - 2 * m)
    local y = m + love.math.random() * math.max(1, world.h - 2 * m)

    -- When Pepper has wandered off, the snacks gather in the middle of the
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
    self.radius = self.baseRadius * world.scale * (1 + 0.18 * world.calm)

    self.repathIn = self.repathIn - dt
    local dx, dy = self.tx - self.x, self.ty - self.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if self.repathIn <= 0 or dist < self.radius * 0.35 then
        self:pickWaypoint(world)
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

    -- Curiosity: for a moment after a tap, the snacks drift toward wherever
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

    local m = self.radius * 0.9
    if self.x < m then self.x, self.vx = m, math.abs(self.vx) end
    if self.x > world.w - m then self.x, self.vx = world.w - m, -math.abs(self.vx) end
    if self.y < m then self.y, self.vy = m, math.abs(self.vy) end
    if self.y > world.h - m then self.y, self.vy = world.h - m, -math.abs(self.vy) end

    -- The dance: everyone bobs on the same beat, each with its own offset.
    local beat = world.beat * TAU
    self.bob = math.sin(beat + self.phase) * self.radius * 0.17
    self.sway = math.cos(beat * 0.5 + self.phase) * self.radius * 0.13
    self.rot = math.sin(beat * 0.5 + self.phase) * 0.22 + self.spin * self.age * 0.4
    self.squash = 1 + 0.07 * math.sin(beat * 2 + self.phase)
    self.appear = math.min(1, self.age / 0.32)
end

--- Where the target is actually drawn (and therefore where it can be hit).
function Target:pos()
    return self.x + self.sway, self.y + self.bob
end

--- Generous hit area: beaks are not styluses.
function Target:contains(px, py)
    local x, y = self:pos()
    local r = self.radius * 1.3
    local dx, dy = px - x, py - y
    return dx * dx + dy * dy <= r * r
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local function outline(r)
    love.graphics.setLineWidth(math.max(2, r * 0.09))
end

local draw = {}

function draw.berry(self, r)
    love.graphics.setColor(self.dark)
    love.graphics.circle("fill", 0, r * 0.08, r)
    love.graphics.setColor(self.color)
    love.graphics.circle("fill", 0, 0, r * 0.96)

    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.ellipse("fill", -r * 0.34, -r * 0.36, r * 0.26, r * 0.17, 16)

    love.graphics.push()
    love.graphics.translate(r * 0.1, -r * 0.9)
    love.graphics.rotate(-0.5)
    love.graphics.setColor(0.32, 0.82, 0.38)
    love.graphics.ellipse("fill", r * 0.3, 0, r * 0.36, r * 0.15, 14)
    love.graphics.setColor(0.18, 0.6, 0.24)
    outline(r * 0.6)
    love.graphics.ellipse("line", r * 0.3, 0, r * 0.36, r * 0.15, 14)
    love.graphics.pop()

    love.graphics.setColor(1, 1, 1, 0.92)
    outline(r)
    love.graphics.circle("line", 0, 0, r * 0.96)
end

function draw.bloom(self, r)
    local petals = 6
    love.graphics.setColor(self.color)
    for i = 1, petals do
        local a = (i / petals) * TAU
        love.graphics.push()
        love.graphics.rotate(a)
        love.graphics.ellipse("fill", r * 0.56, 0, r * 0.46, r * 0.3, 16)
        love.graphics.pop()
    end

    love.graphics.setColor(1, 1, 1, 0.85)
    outline(r * 0.8)
    for i = 1, petals do
        local a = (i / petals) * TAU
        love.graphics.push()
        love.graphics.rotate(a)
        love.graphics.ellipse("line", r * 0.56, 0, r * 0.46, r * 0.3, 16)
        love.graphics.pop()
    end

    love.graphics.setColor(1, 0.88, 0.25)
    love.graphics.circle("fill", 0, 0, r * 0.44)
    love.graphics.setColor(self.dark)
    for i = 1, 5 do
        local a = (i / 5) * TAU + self.age
        love.graphics.circle("fill", math.cos(a) * r * 0.2, math.sin(a) * r * 0.2, r * 0.06)
    end
    love.graphics.setColor(1, 1, 1, 0.9)
    outline(r)
    love.graphics.circle("line", 0, 0, r * 0.44)
end

function draw.flutter(self, r)
    local flap = math.abs(math.sin(self.age * self.flapRate))
    local spread = 0.35 + flap * 0.55

    for side = -1, 1, 2 do
        love.graphics.push()
        love.graphics.rotate(side * spread)
        love.graphics.setColor(self.color)
        love.graphics.ellipse("fill", side * r * 0.6, -r * 0.1, r * 0.58, r * 0.42, 18)
        love.graphics.setColor(self.accent)
        love.graphics.ellipse("fill", side * r * 0.72, -r * 0.12, r * 0.24, r * 0.18, 14)
        love.graphics.setColor(1, 1, 1, 0.9)
        outline(r * 0.9)
        love.graphics.ellipse("line", side * r * 0.6, -r * 0.1, r * 0.58, r * 0.42, 18)
        love.graphics.pop()
    end

    love.graphics.setColor(self.dark)
    love.graphics.ellipse("fill", 0, 0, r * 0.18, r * 0.5, 14)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.circle("fill", -r * 0.09, -r * 0.36, r * 0.07)
    love.graphics.circle("fill", r * 0.09, -r * 0.36, r * 0.07)

    love.graphics.setColor(self.accent)
    love.graphics.setLineWidth(math.max(1.5, r * 0.05))
    love.graphics.line(-r * 0.08, -r * 0.46, -r * 0.3, -r * 0.78)
    love.graphics.line(r * 0.08, -r * 0.46, r * 0.3, -r * 0.78)
end

function draw.bubble(self, r)
    love.graphics.setColor(self.color)
    love.graphics.circle("fill", 0, 0, r)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.circle("fill", 0, 0, r * 0.68)
    love.graphics.setColor(self.color)
    love.graphics.circle("fill", 0, 0, r * 0.4)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.circle("fill", 0, 0, r * 0.14)

    love.graphics.setColor(self.dark)
    love.graphics.setLineWidth(math.max(2, r * 0.12))
    for i = 1, 8 do
        local a = (i / 8) * TAU + self.age * 0.8
        love.graphics.arc("line", "open", 0, 0, r * 1.12, a, a + 0.24)
    end
end

function Target:draw()
    local x, y = self:pos()
    local r = self.radius

    -- Springy pop-in (back-out easing), then the dance squash-and-stretch.
    local u = self.appear - 1
    local pop = math.max(0.02, 1 + 2.70158 * u * u * u + 1.70158 * u * u)

    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(self.rot)
    love.graphics.scale(pop / self.squash, pop * self.squash)

    -- Soft glow so the shape separates from the background.
    love.graphics.setColor(self.color[1], self.color[2], self.color[3], 0.18)
    love.graphics.circle("fill", 0, 0, r * 1.35)

    ;(draw[self.kind] or draw.berry)(self, r)
    love.graphics.pop()
end

return Target
