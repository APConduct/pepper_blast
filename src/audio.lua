-- Procedurally synthesised cockatiel whistles.
--
-- Nothing here loads a sound file: every effect is rendered into a SoundData
-- at startup by a small sine-based whistle synth. A real cockatiel whistle is
-- close to a pure tone in the 1-4 kHz range with a fast frequency sweep and a
-- touch of vibrato, which is exactly what `render` produces.

local Audio = {}

local RATE = 44100
local TAU = math.pi * 2

local ease = {}
function ease.linear(u) return u end
function ease.out_quad(u) return 1 - (1 - u) * (1 - u) end
function ease.in_quad(u) return u * u end
function ease.smooth(u) return u * u * (3 - 2 * u) end
function ease.arch(u) return math.sin(u * math.pi) end

-- Smooth attack/release so no segment ever clicks.
local function env_at(t, dur, attack, release)
    local a = attack > 0 and math.min(t / attack, 1) or 1
    local r = release > 0 and math.min((dur - t) / release, 1) or 1
    local e = math.max(0, math.min(a, r))
    return e * e * (3 - 2 * e)
end

-- segments: list of { dur, f0, f1, curve, vib, vibRate, gain, h2, h3, rest }
local function render(segments, gain)
    gain = gain or 0.5

    local total = 0
    for _, s in ipairs(segments) do total = total + s.dur end

    local frames = math.max(1, math.floor(total * RATE + 0.5))
    local data = love.sound.newSoundData(frames, RATE, 16, 1)

    local index, phase = 0, 0
    for _, s in ipairs(segments) do
        local count = math.floor(s.dur * RATE + 0.5)
        for k = 0, count - 1 do
            if index >= frames then break end
            local v = 0
            if not s.rest then
                local t = k / RATE
                local u = count > 1 and k / (count - 1) or 1
                local shape = s.curve or ease.linear
                local f = s.f0 + (s.f1 - s.f0) * shape(u)
                if s.vib and s.vib > 0 then
                    f = f * (1 + s.vib * math.sin(TAU * (s.vibRate or 16) * t))
                end
                phase = phase + TAU * f / RATE
                if phase > TAU then phase = phase - TAU end
                local body = math.sin(phase)
                    + (s.h2 or 0.16) * math.sin(phase * 2)
                    + (s.h3 or 0.05) * math.sin(phase * 3)
                v = body * env_at(t, s.dur, s.attack or 0.010, s.release or 0.045) * (s.gain or 1) * gain
            end
            if v > 1 then v = 1 elseif v < -1 then v = -1 end
            data:setSample(index, v)
            index = index + 1
        end
    end

    return data, total
end

local function bake(segments, gain)
    local data, dur = render(segments, gain)
    return { source = love.audio.newSource(data, "static"), dur = dur }
end

--------------------------------------------------------------------------
-- Sound recipes
--------------------------------------------------------------------------

-- A pentatonic ladder so rapid-fire taps sound like a tune instead of noise.
local LADDER = { 1319, 1568, 1760, 2093, 2349, 2637, 3136 }

local function chirp(f)
    return {
        { dur = 0.085, f0 = f * 0.68, f1 = f, curve = ease.out_quad, vib = 0.015, gain = 0.95, attack = 0.007, release = 0.05 },
        { dur = 0.060, f0 = f, f1 = f * 0.92, curve = ease.smooth, vib = 0.02, gain = 0.55, attack = 0.004, release = 0.055 },
    }
end

local function wolf_whistle(gain)
    return {
        { dur = 0.30, f0 = 1150, f1 = 2900, curve = ease.out_quad, vib = 0.008, gain = gain or 0.9 },
        { dur = 0.05, rest = true },
        { dur = 0.42, f0 = 2900, f1 = 880, curve = ease.in_quad, vib = 0.014, gain = (gain or 0.9) * 0.95, release = 0.12 },
    }
end

local function warble(notes, noteDur, gapDur)
    local out = {}
    for _, f in ipairs(notes) do
        out[#out + 1] = { dur = noteDur, f0 = f * 0.86, f1 = f, curve = ease.out_quad, vib = 0.025, vibRate = 22, gain = 0.85 }
        out[#out + 1] = { dur = gapDur, rest = true }
    end
    return out
end

local function concat(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, seg in ipairs(list) do out[#out + 1] = seg end
    end
    return out
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

local bank = { pops = {}, songs = {} }
local muted = false
local songRotation = 0

function Audio.load()
    love.audio.setVolume(0.75)

    for i, f in ipairs(LADDER) do
        bank.pops[i] = bake(chirp(f), 0.42)
    end

    -- Soft "you touched the glass" acknowledgement for a miss.
    bank.tick = bake({
        { dur = 0.05, f0 = 760, f1 = 620, curve = ease.smooth, gain = 1, h2 = 0.05, h3 = 0, attack = 0.006, release = 0.04 },
    }, 0.10)

    -- Contact call: the "where did everybody go?" whistle cockatiels use.
    bank.attract = bake(concat(
        { { dur = 0.18, f0 = 1500, f1 = 2400, curve = ease.out_quad, vib = 0.02, gain = 0.8 },
          { dur = 0.08, rest = true },
          { dur = 0.22, f0 = 2400, f1 = 1700, curve = ease.smooth, vib = 0.03, gain = 0.7 } }
    ), 0.26)

    -- Milestone songs, rotated so the reward never gets stale.
    bank.songs[1] = bake(concat(
        warble({ 2093, 2349, 2637, 2093, 2637, 3136 }, 0.10, 0.045),
        { { dur = 0.09, rest = true } },
        wolf_whistle(0.95)
    ), 0.44)

    bank.songs[2] = bake(concat(
        warble({ 1760, 2093, 1760, 2349, 2093, 2637, 2349, 3136 }, 0.085, 0.035),
        { { dur = 0.10, rest = true },
          { dur = 0.55, f0 = 2100, f1 = 3000, curve = ease.arch, vib = 0.05, vibRate = 12, gain = 0.9, release = 0.16 } }
    ), 0.44)

    bank.songs[3] = bake(concat(
        { { dur = 0.36, f0 = 1400, f1 = 2800, curve = ease.out_quad, vib = 0.03, vibRate = 14, gain = 0.9 },
          { dur = 0.06, rest = true } },
        warble({ 2637, 2349, 2637, 3136, 2637, 2349, 2093 }, 0.09, 0.03),
        { { dur = 0.06, rest = true } },
        wolf_whistle(0.9)
    ), 0.44)
end

local function play(entry, pitch, volume)
    if muted or not entry then return 0 end
    pitch = pitch or 1
    local s = entry.source:clone()
    s:setPitch(pitch)
    s:setVolume(volume or 1)
    s:play()
    return entry.dur / pitch
end

--- Pop a target. `step` climbs the pentatonic ladder with the combo.
function Audio.pop(step)
    local i = ((step - 1) % #bank.pops) + 1
    local octave = math.floor((step - 1) / #bank.pops) % 2 == 1 and 1.5 or 1
    return play(bank.pops[i], octave * (0.99 + love.math.random() * 0.02), 1)
end

function Audio.tick()
    return play(bank.tick, 0.95 + love.math.random() * 0.1, 1)
end

function Audio.attract()
    return play(bank.attract, 0.98 + love.math.random() * 0.05, 1)
end

function Audio.song()
    songRotation = (songRotation % #bank.songs) + 1
    return play(bank.songs[songRotation], 1, 1)
end

function Audio.is_muted() return muted end

function Audio.set_muted(value)
    muted = value and true or false
    if muted then love.audio.stop() end
    return muted
end

function Audio.toggle_mute()
    return Audio.set_muted(not muted)
end

return Audio
