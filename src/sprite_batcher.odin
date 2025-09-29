/*
Copyright (c) 2025 NongusStudios

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
package sprite_batcher

import "core:fmt"
import "core:slice"

import "core:math/linalg"
import gl "vendor:OpenGL"

uvec2 :: [2]u32
ivec2 :: [2]i32
bvec2 :: [2]b32
mat4 :: linalg.Matrix4f32
vec2 :: linalg.Vector2f32
vec3 :: linalg.Vector3f32

SB_SPRITE_INIT_SIZE :: 512

TextureFilter :: enum {
    Nearest = gl.NEAREST,
    Linear = gl.LINEAR,
}

Sprite :: struct {
    position:  vec2, // world coords
    size:      vec2, // world coords
    flip:      ivec2, // {flip_h, flip_v} 0 || 1
    rotation:  f32,  // radians
    z_index:   i32,
    region_id: u32,
    _:         f32, // padding
}

AtlasRegionDesc :: struct {
    start: uvec2, // pixel coords
    size: uvec2,  // pixel coords
}

AtlasRegion :: struct {
    norm_start: vec2, // 0 - 1 uv space
    norm_size:  vec2,  // 0 - 1 uv space
}

SpriteAtlas :: struct {
    texture: Texture2D,
    sb_regions: StorageBuffer,
    sb_sprites: StorageBuffer,
    regions: []AtlasRegion,
}

SpriteBatcherDesc :: struct {
    dimensions: ivec2,
    z_index_range: ivec2,
    msaa_samples: i32,
    proc_addr: gl.Set_Proc_Address_Type,
}

/*
 * Initialises the renderer
 * returns true on exit success
*/
init_sprite_batcher :: proc(desc: ^SpriteBatcherDesc) -> bool {
    if !init_state(desc) {
        return false
    }

    return true
}

free_sprite_batcher :: proc() {
    free_state()
}

/*
 * Creates a sprite atlas to draw sprites from.
 * args:
 *   path: filepath to image
 *   partitions: A list of partitions on the atlas that defines the content of a sprite, referenced by index.
 *   gen_mipmaps: Generates mipmaps of the atlas when true (default)
 * returns:
 *  SpriteAtlas
 *  bool, true on success
*/
create_sprite_atlas :: proc(path: string, regions: []AtlasRegionDesc, filter: TextureFilter, gen_mipmaps := true) -> (SpriteAtlas, bool) {
    atlas: SpriteAtlas
    success: bool

    atlas.texture, success = create_texture2d(path, i32(filter), gen_mipmaps)
    if !success {
        return {}, false
    }

    atlas.regions = make([]AtlasRegion, len(regions))
    for i := 0; i < len(regions); i += 1 {
        region := &atlas.regions[i]

        // Pre-calculate normalized regions
        region.norm_start[0] = f32(regions[i].start[0]) / f32(atlas.texture.dimensions[0])
        region.norm_start[1] = f32(regions[i].start[1]) / f32(atlas.texture.dimensions[1])
        region.norm_size[0]  = f32(regions[i].size[0])  / f32(atlas.texture.dimensions[0])
        region.norm_size[1]  = f32(regions[i].size[1])  / f32(atlas.texture.dimensions[1])
    }

    atlas.sb_sprites = create_storage_buffer(size_of(Sprite), SB_SPRITE_INIT_SIZE)
    atlas.sb_regions = create_storage_buffer(size_of(AtlasRegion), len(regions))
    populate_storage_buffer(&atlas.sb_regions, slice.to_bytes(atlas.regions))

    return atlas, true
}

destroy_sprite_atlas :: proc(atlas: ^SpriteAtlas) {
    destroy_texture2d(&atlas.texture)
    gl.DeleteBuffers(1, &atlas.sb_regions.id)
    gl.DeleteBuffers(1, &atlas.sb_sprites.id)
    delete(atlas.regions)
}

// Draws a sprite from atlas
draw_sprite :: proc(atlas: ^SpriteAtlas, sprite: Sprite) {
    gl.UseProgram(state.sprite_shader)
    gl.BindVertexArray(state.quad_mesh.va)
    gl.BindTextureUnit(0, atlas.texture.id)

    model := linalg.identity_matrix(mat4)
    model *= linalg.matrix4_translate(vec3{sprite.position[0], sprite.position[1], 0.0})
    model *= linalg.matrix4_rotate(sprite.rotation, vec3{0, 0, 1})
    model *= linalg.matrix4_scale(vec3{sprite.size[0], sprite.size[1], 0.0})

    gl.UniformMatrix4fv(gl.GetUniformLocation(state.sprite_shader, "u_ortho"), 1, false, linalg.to_ptr(&state.ortho_projection))
    gl.UniformMatrix4fv(gl.GetUniformLocation(state.sprite_shader, "u_model"), 1, false, linalg.to_ptr(&model))

    part := &atlas.regions[sprite.region_id]
    gl.Uniform2i(gl.GetUniformLocation(state.sprite_shader, "u_flip"), sprite.flip[0], sprite.flip[1])
    gl.Uniform2f(gl.GetUniformLocation(state.sprite_shader, "u_norm_start"), part.norm_start[0], part.norm_start[1])
    gl.Uniform2f(gl.GetUniformLocation(state.sprite_shader, "u_norm_size"), part.norm_size[0], part.norm_size[1])

    gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)
}


// Batches n sprites with one draw call from atlas
draw_sprites :: proc(atlas: ^SpriteAtlas, sprites: []Sprite) {
    gl.UseProgram(state.sprite_instanced_shader)
    gl.BindVertexArray(state.quad_mesh.va)
    gl.BindTextureUnit(0, atlas.texture.id)

    populate_storage_buffer(&atlas.sb_sprites, slice.to_bytes(sprites))
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, atlas.sb_sprites.id)
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 1, atlas.sb_regions.id)

    gl.UniformMatrix4fv(gl.GetUniformLocation(state.sprite_instanced_shader, "u_ortho"), 1, false, linalg.to_ptr(&state.ortho_projection))

    instance_count := i32(len(sprites))
    gl.DrawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil, instance_count)
}

// GFX - State
GFXState :: struct {
    sprite_shader: u32,
    sprite_instanced_shader: u32,
    present_shader: u32,
    quad_mesh: Mesh,
    main_frame: Framebuffer,

    ortho_projection: mat4,
}

// gfx state
@(private="file")
state: GFXState

init_state :: proc(desc: ^SpriteBatcherDesc) -> bool {
    // Initialise OpenGL, viewport and projection
    gl.load_up_to(4, 5, desc.proc_addr)
    gl.Viewport(0, 0, desc.dimensions[0], desc.dimensions[1])
    set_projection_dimensions(desc.dimensions, desc.z_index_range)

    // Enable face culling
    gl.Enable(gl.CULL_FACE)
    gl.CullFace(gl.BACK)
    gl.FrontFace(gl.CCW)

    // Enable multisampling
    if desc.msaa_samples > 1 {
        gl.Enable(gl.MULTISAMPLE)
    }

    // Create main framebuffer
    result: bool
    state.main_frame, result = create_framebuffer(desc.dimensions, desc.msaa_samples)
    if !result {
        fmt.eprintln("sprite_batcher -> error: failed to create main framebuffer")
        return false
    }

    // Create meshes
    quad_vertices := []f32{
    // origin (0, 0)
    //  x,   y    uvx  uvy
       -0.5,-0.5, 0.0, 0.0, // [0] top left
        0.5,-0.5, 1.0, 0.0, // [1] top right
        0.5, 0.5, 1.0, 1.0, // [2] bottom right
       -0.5, 0.5, 0.0, 1.0, // [3] bottom left
    }

    quad_indices := []u32{
        0, 1, 2, // triangle 1
        0, 2, 3, // triangle 2
    }

    vertex_attributes := []VertexAttrib{
        VertexAttrib{ // Position loc[0]
            location = 0,
            size = 2,
            type = gl.FLOAT,
            offset = 0,
        },
        VertexAttrib{ // UV loc[1]
            location = 1,
            size = 2,
            type = gl.FLOAT,
            offset = size_of(f32)*2,
        },
    }

    state.quad_mesh = create_mesh(slice.to_bytes(quad_vertices), quad_indices, size_of(f32)*4, vertex_attributes)

    // Create shaders
    state.present_shader = create_shader(PRESENT_SHADER_VERT, PRESENT_SHADER_FRAG, "present");
    if state.present_shader == 0 { return false }

    state.sprite_shader = create_shader(SPRITE_SHADER_VERT, SPRITE_SHADER_FRAG, "sprite")
    if state.sprite_shader == 0 { return false }

    state.sprite_instanced_shader = create_shader(SPRITE_INSTANCED_SHADER_VERT, SPRITE_INSTANCED_SHADER_FRAG, "sprite_instanced")
    if state.sprite_instanced_shader == 0 { return false }

    return true
}

free_state :: proc() {
    gl.DeleteProgram(state.sprite_shader)
    gl.DeleteProgram(state.present_shader)
    destroy_mesh(&state.quad_mesh)
    destroy_framebuffer(&state.main_frame)
}

set_viewport_dimensions :: proc "contextless" (dimensions: ivec2) {
    resize_framebuffer(&state.main_frame, dimensions)
    gl.Viewport(0, 0, dimensions[0], dimensions[1])
}

set_projection_dimensions :: proc "contextless" (dimensions: ivec2, z_index_range: ivec2) {
    // origin (0, 0) +up -down
    di := vec2{f32(dimensions[0]), f32(dimensions[1])}
    state.ortho_projection = linalg.matrix_ortho3d_f32(-di[0]/2.0, di[0]/2.0, -di[1]/2.0, di[1]/2.0, f32(z_index_range[0]), f32(z_index_range[1]))
}

start_render_pass :: proc() {
    gl.BindFramebuffer(gl.FRAMEBUFFER, state.main_frame.fbo)
    gl.ClearColor(0.44, 0.44, 0.44, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
    gl.Enable(gl.DEPTH_TEST)
}

end_render_pass :: proc() {
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    gl.ClearColor(0.0, 0.0, 0.0, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT)
    gl.Disable(gl.DEPTH_TEST)

    gl.UseProgram(state.present_shader)
    gl.BindVertexArray(state.quad_mesh.va)
    gl.BindTextureUnit(0, state.main_frame.colour_attachment)
    gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)
}