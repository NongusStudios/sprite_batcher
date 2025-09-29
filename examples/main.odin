package main

import sb "../src"

import glfw "vendor:glfw"
import "core:fmt"
import "core:math/rand"
import "core:math/linalg"

DIMENSIONS :: sb.ivec2{1600, 900}
Z_INDEX :: sb.ivec2{-1000, 1000}

on_window_resize :: proc "c" (window: glfw.WindowHandle, w, h: i32) {
    sb.set_viewport_dimensions(sb.ivec2{w, h})
    sb.set_projection_dimensions(sb.ivec2{w, h}, Z_INDEX)
}

gen_sprite_data :: proc(sprites: []sb.Sprite) {
    for &sprite in sprites {
        sprite.region_id = u32(rand.int_max(7))

        x := f32(rand.int_max(int(DIMENSIONS[0]-32)) - int(DIMENSIONS[0]+32)/2)
        y := f32(rand.int_max(int(DIMENSIONS[1]-32)) - int(DIMENSIONS[1]+32)/2)
        sprite.position = sb.vec2{x, y}
        //sprite.rotation = linalg.to_radians(f32(rand.int_max(360)))
        sprite.size = sb.vec2{64, 64}
    }
}

main :: proc() {
    using sb

    result: bool
    result = bool(glfw.Init())
    if !result {
        return
    }

    // Context version 4.5 core
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
    glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

    window := glfw.CreateWindow(DIMENSIONS[0], DIMENSIONS[1], "sb", nil, nil)

    if window == nil {
        fmt.eprintln("Failed to create window!")
        return
    }

    glfw.MakeContextCurrent(window)
    glfw.SwapInterval(0)

    result = init_sprite_batcher(&SpriteBatcherDesc{
        dimensions = DIMENSIONS,
        z_index_range = Z_INDEX,
        proc_addr = glfw.gl_set_proc_address,
    }); defer free_sprite_batcher()
    if !result {
        return
    }

    glfw.SetFramebufferSizeCallback(window, on_window_resize)

    regions: [8]AtlasRegionDesc
    for i: u32 = 0; i < 2; i += 1 {
        for j: u32 = 0; j < 4; j += 1 {
            regions[i * 4 + j] = AtlasRegionDesc{
                start = uvec2{j*32, i*32},
                size  = uvec2{32,   32},
            }
        }
    }

    atlas, success := create_sprite_atlas("examples/test_atlas.png", regions[:], TextureFilter.Nearest)
    if !success {
        return
    }

    SPRITE_COUNT :: 100000
    sprites := make([]Sprite, SPRITE_COUNT)
    dirs := make([]vec2, SPRITE_COUNT)
    
    for &dir in dirs {
        dir = vec2{1.0, 1.0}
    }

    gen_sprite_data(sprites[:])

    pressed := false
    last := 0.0
    since_fps:f32 = 0.0
    for !glfw.WindowShouldClose(window) {
        glfw.PollEvents()
        now := glfw.GetTime()
        dt := f32(now - last)
        last = now

        // Display FPS
        since_fps += dt
        if since_fps >= 0.5 {
            fmt.printf("\rFPS: %f", 1.0 / dt)
            since_fps = 0.0
        }

        if glfw.GetKey(window, glfw.KEY_R) == glfw.PRESS && !pressed {
            gen_sprite_data(sprites[:])
            pressed = true
        } else if glfw.GetKey(window, glfw.KEY_R) == glfw.RELEASE { pressed = false }
        
        for i in 0..=SPRITE_COUNT-1 {
            s := &sprites[i]
            s.position[0] += 200.0 * dt * dirs[i][0]
            s.position[1] += 200.0 * dt * dirs[i][1]

            w, h := glfw.GetFramebufferSize(window)
            di := vec2{f32(w), f32(h)}
            if s.position[0] >= di[0]/2.0-s.size[0]/2.0 {
                dirs[i][0] = -1
            } else if s.position[0] <= -di[0]/2.0+s.size[0]/2.0 {
                dirs[i][0] = 1
            }
            if s.position[1] >= di[1]/2.0-s.size[1]/2.0 {
                dirs[i][1] = -1
            } else if s.position[1] <= -di[1]/2.0+s.size[1]/2.0 {
                dirs[i][1] = 1
            }
        }

        start_render_pass()
        draw_sprites(&atlas, sprites[:])
        end_render_pass()
        glfw.SwapBuffers(window)
    }

    glfw.DestroyWindow(window)
    //glfw.Terminate() // This call causes a seg fault on exit, for some reason
}