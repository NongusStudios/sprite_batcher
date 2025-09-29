/*
Copyright (c) 2025 NongusStudios

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
package sprite_batcher

import "core:strings"
import "core:fmt"
import "core:os"

import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

Framebuffer :: struct {
    fbo: u32,
    colour_attachment: u32,
    rbo_depth_stencil_attachment: u32,
}

Mesh :: struct {
    vbuf: u32,
    ibuf: u32,
    va:   u32,
}

Texture2D :: struct {
    id: u32,
    dimensions: ivec2,
}

StorageBuffer :: struct {
    id:  u32,
    len: int,
}

/*
 * Creates a shader module 
 * returns 0 if the shader fails to compile, error message printed to stderr
*/
create_shader_module :: proc(src: string, type: u32, tag: string) -> u32 {
    cstr := strings.clone_to_cstring(src); defer delete(cstr)
    
    module := gl.CreateShader(type)
    gl.ShaderSource(module, 1, &cstr, nil)
    gl.CompileShader(module)

    result: i32
    gl.GetShaderiv(module, gl.COMPILE_STATUS, &result)
    if result == 0 {
        log := make([]u8, 1024); defer delete(log)
        gl.GetShaderInfoLog(module, 1024, nil, raw_data(log[:]))
        fmt.eprintf("sprite_batcher -> error: failed to compile shader! tag: %s\n%s", tag, string(log))
        gl.DeleteShader(module)
        return 0
    }

    return module
}

/*
 * Creates a shader program (version string 450 core, prepended to src)
 * returns 0 if creation fails, error message printed to stderr
*/
create_shader :: proc(vert: string, frag: string, tag: string) -> u32 {
    sb: strings.Builder
    strings.builder_init(&sb); defer strings.builder_destroy(&sb)

    vsrc := strings.clone(fmt.sbprintf(&sb, "#version 450 core\n%s", vert)); defer delete(vsrc)
    strings.builder_reset(&sb)
    vtag := strings.clone(fmt.sbprintf(&sb, "%s-vertex", tag)); defer delete(vtag)
    strings.builder_reset(&sb)
    fsrc := strings.clone(fmt.sbprintf(&sb, "#version 450 core\n%s", frag)); defer delete(fsrc)
    strings.builder_reset(&sb)
    ftag := strings.clone(fmt.sbprintf(&sb, "%s-fragment", tag)); defer delete(ftag)

    m_vert := create_shader_module(vsrc, gl.VERTEX_SHADER, vtag); defer gl.DeleteShader(m_vert)
    if m_vert == 0 { return 0 }

    m_frag := create_shader_module(fsrc, gl.FRAGMENT_SHADER, ftag); defer gl.DeleteShader(m_frag)
    if m_frag == 0 { return 0 }

    shader := gl.CreateProgram()
    gl.AttachShader(shader, m_vert)
    gl.AttachShader(shader, m_frag)
    gl.LinkProgram(shader)

    result: i32
    gl.GetProgramiv(shader, gl.LINK_STATUS, &result)
    if result == 0 {
        log := make([]u8, 1024); defer delete(log)
        gl.GetProgramInfoLog(shader, 1024, nil, raw_data(log[:]))
        fmt.eprintf("sprite_batcher -> error: failed to link program! tag: %s\n%s", tag, string(log))
        gl.DeleteProgram(shader)
        return 0
    }

    return shader
}

/*
 * Creates a framebuffer with a colour and depth stencil attachment.
 * returns a tuple of the framebuffer, and a boolean. Boolean is true when creation is successful
 * errors printed to stderr
*/
create_framebuffer :: proc "contextless" (dimensions: ivec2, samples: i32 = 1) -> (Framebuffer, bool) {
    fb: Framebuffer

    gl.CreateFramebuffers(1, &fb.fbo)

    gl.CreateTextures(gl.TEXTURE_2D_MULTISAMPLE if samples > 1 else gl.TEXTURE_2D, 1, &fb.colour_attachment)
    gl.CreateRenderbuffers(1, &fb.rbo_depth_stencil_attachment)

    if samples > 1 {   
        gl.TextureStorage2DMultisample(fb.colour_attachment, samples, gl.RGBA8, dimensions[0], dimensions[1], true)
        gl.NamedRenderbufferStorageMultisample(fb.rbo_depth_stencil_attachment, samples, gl.DEPTH24_STENCIL8, dimensions[0], dimensions[1])
    } else {
        gl.TextureStorage2D(fb.colour_attachment, 1, gl.RGBA8, dimensions[0], dimensions[1])
        gl.TextureParameteri(fb.colour_attachment, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
        gl.TextureParameteri(fb.colour_attachment, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

        gl.NamedRenderbufferStorage(fb.rbo_depth_stencil_attachment, gl.DEPTH24_STENCIL8, dimensions[0], dimensions[1])
    }

    gl.NamedFramebufferTexture(fb.fbo, gl.COLOR_ATTACHMENT0, fb.colour_attachment, 0)
    gl.NamedFramebufferRenderbuffer(fb.fbo, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, fb.rbo_depth_stencil_attachment)

    if gl.CheckNamedFramebufferStatus(fb.fbo, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
        destroy_framebuffer(&fb)
        return {}, false
    }

    return fb, true
}

resize_framebuffer :: proc "contextless" (fb: ^Framebuffer, dimensions: ivec2) {
    destroy_framebuffer(fb)
    fb^, _ = create_framebuffer(dimensions)
}\

destroy_framebuffer :: proc "contextless" (fb: ^Framebuffer) {
    gl.DeleteRenderbuffers(1, &fb.rbo_depth_stencil_attachment)
    gl.DeleteTextures(1, &fb.colour_attachment)
    gl.DeleteFramebuffers(1, &fb.fbo)
}

VertexAttrib :: struct {
    location: u32,
    size: i32,
    type: u32,
    offset: u32,
}

create_mesh :: proc(vertices: []byte, indices: []u32, stride: i32, attributes: []VertexAttrib) -> Mesh {
    m: Mesh
    // Create objects
    gl.CreateVertexArrays(1, &m.va)

    buffers := [2]u32{}
    gl.CreateBuffers(2, raw_data(buffers[:]))
    m.vbuf = buffers[0]
    m.ibuf = buffers[1]

    gl.NamedBufferStorage(m.vbuf, len(vertices), raw_data(vertices[:]), gl.DYNAMIC_STORAGE_BIT)
    gl.NamedBufferStorage(m.ibuf, len(indices)*size_of(u32),  raw_data(indices[:]),  gl.DYNAMIC_STORAGE_BIT)

    gl.VertexArrayVertexBuffer(m.va, 0, m.vbuf, 0, stride)
    gl.VertexArrayElementBuffer(m.va, m.ibuf)
    
    for attrib in attributes {
        gl.EnableVertexArrayAttrib(m.va, attrib.location)
        gl.VertexArrayAttribFormat(m.va, attrib.location, attrib.size, attrib.type, false, attrib.offset)
        gl.VertexArrayAttribBinding(m.va, attrib.location, 0)
    }

    return m
}

destroy_mesh :: proc(m: ^Mesh) {
    gl.DeleteVertexArrays(1, &m.va)
    gl.DeleteBuffers(1, &m.vbuf)
    gl.DeleteBuffers(1, &m.ibuf)
}

// creates a 2D texture from an image file
create_texture2d :: proc(path: string, filter: i32, gen_mipmaps: bool) -> (Texture2D, bool) {
    // load image to memory
    image_data, success := os.read_entire_file(path); defer delete(image_data)
    if !success {
        fmt.eprintfln("sprite_batcher -> error: failed to load image %s", path)
        return {}, false
    }
    
    w, h, channels: i32                                                                             // desired_channels 4 = STBI_rgb_alpha
    pixel_data := stbi.load_from_memory(raw_data(image_data), i32(len(image_data)), &w, &h, &channels, 4)
    defer stbi.image_free(pixel_data)

    // create OpenGL texture object
    tex: u32
    gl.CreateTextures(gl.TEXTURE_2D, 1, &tex)
    gl.TextureParameteri(tex, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TextureParameteri(tex, gl.TEXTURE_WRAP_T, gl.REPEAT)
    gl.TextureParameteri(tex, gl.TEXTURE_MIN_FILTER, filter)
    gl.TextureParameteri(tex, gl.TEXTURE_MAG_FILTER, filter)

    gl.TextureStorage2D(tex, 1, gl.RGBA8, w, h)
    gl.TextureSubImage2D(tex, 0, 0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, pixel_data)

    if gen_mipmaps {
        gl.GenerateTextureMipmap(tex)
    }

    return Texture2D {
        id = tex,
        dimensions = ivec2{w, h}
    }, true
}

destroy_texture2d :: proc(tex: ^Texture2D) {
    gl.DeleteTextures(1, &tex.id)
}

create_storage_buffer :: proc(elem: int, len: int) -> StorageBuffer {
    sb: StorageBuffer
    gl.CreateBuffers(1, &sb.id)
    gl.NamedBufferData(sb.id, len*elem, nil, gl.DYNAMIC_DRAW)
    sb.len = len*elem
    return sb
}

populate_storage_buffer :: proc(sb: ^StorageBuffer, data: []byte) {
    if sb.len < len(data) {
        gl.NamedBufferData(sb.id, len(data), raw_data(data[:]), gl.DYNAMIC_DRAW)
        sb.len = len(data)
        return
    }
    gl.NamedBufferSubData(sb.id, 0, len(data), raw_data(data[:]))
}