function love.conf(t)
    t.identity = "pepper_blast"
    t.version = "11.4"
    t.console = false

    t.window.title = "Pepper Blast"
    t.window.width = 900
    t.window.height = 620
    t.window.minwidth = 320
    t.window.minheight = 320
    t.window.resizable = true
    t.window.highdpi = true
    t.window.vsync = 1

    -- Trim modules we do not use so the iOS build starts faster.
    t.modules.physics = false
    t.modules.joystick = false
    t.modules.video = false
end
