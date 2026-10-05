-- Pepper Blast -- a tap game for Pepper the cockatiel.
-- Runs on desktop (mouse) and iOS (touch).

local Game = require("src.game")

function love.load()
    love.graphics.setDefaultFilter("linear", "linear")
    love.math.setRandomSeed(os.time())

    -- Keep the phone awake while Pepper plays (LOVE 12+; harmless elsewhere).
    pcall(function() love.window.setDisplaySleepEnabled(false) end)

    Game.load()
end

function love.update(dt)
    -- Clamp so a hitch (app resume, window drag) never teleports a target.
    Game.update(math.min(dt, 1 / 20))
end

function love.draw()
    Game.draw()
end

function love.resize(w, h)
    Game.resize(w, h)
end

-- On mobile LOVE emits both touch* and mouse* events for the first finger;
-- `istouch` lets us ignore the synthesised mouse copy.
function love.mousepressed(x, y, _button, istouch)
    if istouch then return end
    Game.press("mouse", x, y)
end

function love.mousereleased(_x, _y, _button, istouch)
    if istouch then return end
    Game.release("mouse")
end

function love.mousemoved(x, y, _dx, _dy, istouch)
    if istouch then return end
    Game.move("mouse", x, y)
end

function love.touchpressed(id, x, y)
    Game.press(id, x, y)
end

function love.touchreleased(id)
    Game.release(id)
end

function love.touchmoved(id, x, y)
    Game.move(id, x, y)
end

function love.keypressed(key)
    Game.keypressed(key)
end

-- iOS can kill a backgrounded app without ever calling love.quit, so the high
-- score is flushed as soon as we lose focus. Touches in flight at that point
-- may never get a release, so they are dropped too.
function love.focus(focused)
    if not focused then
        Game.flush()
        Game.clear_presses()
    end
end

function love.quit()
    Game.flush()
end
