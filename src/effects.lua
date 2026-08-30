-- Confetti, bursts, rings and ripples. Pure primitives, no assets.

local Effects = {}

local TAU = math.pi * 2

local bits = {}      -- burst pieces
local rings = {}     -- expanding hit rings
local ripples = {}   -- "I felt that" feedback on empty taps
local confetti = {}  -- celebration rain
local blobs = {}     -- slow ambient background shapes

function Effects.reset()
    bits, rings, ripples, confetti = {}, {}, {}, {}
    blobs = {}
    for i = 1, 5 do
        blobs[i] = {
            r = 0.18 + love.math.random() * 0.22,
            sp = 0.02 + love.math.random() * 0.05,
            phase = love.math.random() * TAU,
            hue = love.math.random(),
        }
    end
end

-- Sized like husk fragments off a small seed rather than pulped fruit.
function Effects.burst(x, y, color, scale, power)
    power = power or 1
    local count = math.floor(12 * power)
    for _ = 1, count do
        local a = love.math.random() * TAU
        local sp = (100 + love.math.random() * 260) * scale * power
        bits[#bits + 1] = {
            x = x, y = y,
            vx = math.cos(a) * sp,
            vy = math.sin(a) * sp - 60 * scale,
            life = 0, max = 0.5 + love.math.random() * 0.5,
            size = (3.5 + love.math.random() * 5) * scale,
            rot = love.math.random() * TAU,
            spin = (love.math.random() - 0.5) * 16,
            color = color,
            round = love.math.random() < 0.4,
        }
    end
end

function Effects.ring(x, y, color, scale, power)
    rings[#rings + 1] = {
        x = x, y = y, color = color,
        life = 0, max = 0.45,
        from = 8 * scale, to = (52 + 26 * (power or 1)) * scale,
        width = 5 * scale,
    }
end

function Effects.ripple(x, y, scale)
    ripples[#ripples + 1] = {
        x = x, y = y,
        life = 0, max = 0.55,
        to = 90 * scale,
    }
end

function Effects.confettiBurst(w, h, scale, count)
    for _ = 1, count do
        confetti[#confetti + 1] = {
            x = love.math.random() * w,
            y = -love.math.random() * h * 0.6,
            vx = (love.math.random() - 0.5) * 90 * scale,
            vy = (90 + love.math.random() * 170) * scale,
            size = (7 + love.math.random() * 9) * scale,
            rot = love.math.random() * TAU,
            spin = (love.math.random() - 0.5) * 10,
            flip = love.math.random() * TAU,
            flipRate = 4 + love.math.random() * 6,
            hue = love.math.random(),
        }
    end
end

local function hsv(h, s, v)
    h = (h % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end
Effects.hsv = hsv

local function sweep(list, dt)
    for i = #list, 1, -1 do
        local o = list[i]
        o.life = o.life + dt
        if o.life >= o.max then table.remove(list, i) end
    end
end

function Effects.update(dt, w, h, scale)
    for i = #bits, 1, -1 do
        local b = bits[i]
        b.life = b.life + dt
        if b.life >= b.max then
            table.remove(bits, i)
        else
            b.vy = b.vy + 900 * scale * dt
            b.vx = b.vx * (1 - 1.6 * dt)
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt
            b.rot = b.rot + b.spin * dt
        end
    end

    sweep(rings, dt)
    sweep(ripples, dt)

    for i = #confetti, 1, -1 do
        local c = confetti[i]
        c.x = c.x + c.vx * dt
        c.y = c.y + c.vy * dt
        c.vx = c.vx + math.sin(c.y * 0.01 + c.flip) * 30 * scale * dt
        c.rot = c.rot + c.spin * dt
        c.flip = c.flip + c.flipRate * dt
        if c.y > h + 40 * scale then table.remove(confetti, i) end
    end

    for _, b in ipairs(blobs) do
        b.phase = b.phase + b.sp * dt
    end
end

function Effects.drawAmbient(w, h, t)
    for _, b in ipairs(blobs) do
        local x = w * (0.5 + 0.42 * math.cos(b.phase * 1.7))
        local y = h * (0.5 + 0.42 * math.sin(b.phase * 1.3))
        local r, g, bl = hsv(b.hue + t * 0.01, 0.5, 1)
        love.graphics.setColor(r, g, bl, 0.05)
        love.graphics.circle("fill", x, y, math.min(w, h) * b.r)
    end
end

function Effects.drawBehind()
    for _, o in ipairs(ripples) do
        local u = o.life / o.max
        love.graphics.setColor(1, 1, 1, 0.28 * (1 - u))
        love.graphics.setLineWidth(3 + 3 * (1 - u))
        love.graphics.circle("line", o.x, o.y, o.to * u)
    end

    for _, c in ipairs(confetti) do
        local r, g, b = hsv(c.hue, 0.85, 1)
        love.graphics.setColor(r, g, b, 0.9)
        love.graphics.push()
        love.graphics.translate(c.x, c.y)
        love.graphics.rotate(c.rot)
        love.graphics.scale(math.cos(c.flip), 1)
        love.graphics.rectangle("fill", -c.size * 0.5, -c.size * 0.32, c.size, c.size * 0.64, c.size * 0.15)
        love.graphics.pop()
    end
end

function Effects.drawFront()
    for _, o in ipairs(rings) do
        local u = o.life / o.max
        local e = 1 - (1 - u) * (1 - u)
        love.graphics.setColor(o.color[1], o.color[2], o.color[3], 0.75 * (1 - u))
        love.graphics.setLineWidth(o.width * (1 - u * 0.7))
        love.graphics.circle("line", o.x, o.y, o.from + (o.to - o.from) * e)
    end

    for _, b in ipairs(bits) do
        local u = b.life / b.max
        love.graphics.setColor(b.color[1], b.color[2], b.color[3], 1 - u * u)
        love.graphics.push()
        love.graphics.translate(b.x, b.y)
        love.graphics.rotate(b.rot)
        local s = b.size * (1 - u * 0.45)
        if b.round then
            love.graphics.circle("fill", 0, 0, s * 0.55)
        else
            love.graphics.rectangle("fill", -s * 0.5, -s * 0.35, s, s * 0.7, s * 0.2)
        end
        love.graphics.pop()
    end
end


return Effects
