/*
Copyright (c) 2025 NongusStudios

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
package sprite_batcher

PRESENT_SHADER_VERT :: `
layout(location = 0) in vec2 attr_pos;
layout(location = 1) in vec2 attr_uv;
out vec2 uv;

void main() {
    gl_Position = vec4(attr_pos*2.0, 0.0, 1.0);
    uv = attr_uv;
}
`
PRESENT_SHADER_FRAG :: `
in vec2 uv;
uniform sampler2D u_frame;

out vec4 out_colour;

void main() {
    out_colour = texture(u_frame, uv);
}
`

SPRITE_SHADER_VERT :: `
layout(location = 0) in vec2 attr_pos;
layout(location = 1) in vec2 attr_uv;

out vec2 v_uv;

uniform mat4 u_ortho;
uniform mat4 u_model;

void main() {
    gl_Position = u_ortho * u_model * vec4(attr_pos, 0.0, 1.0);
    v_uv = attr_uv;
}
`

SPRITE_SHADER_FRAG :: `
in vec2 v_uv;
out vec4 out_colour;

uniform sampler2D u_atlas;

uniform ivec2 u_flip;
uniform vec2 u_norm_start;
uniform vec2 u_norm_size;

vec2 get_uv() {
    vec2 processed_uv = v_uv;
    if(u_flip.x == 1) processed_uv.x = 1.0 - v_uv.x;
    if(u_flip.y == 1) processed_uv.y = 1.0 - v_uv.y;

    return u_norm_start + processed_uv * u_norm_size;
}

void main() {
    out_colour = texture(u_atlas, get_uv());
}
`

SPRITE_INSTANCED_SHADER_VERT :: `
layout(location = 0) in vec2 attr_pos;
layout(location = 1) in vec2 attr_uv;

out vec2 v_uv;
out flat ivec2 v_flip;
out flat uint v_region_id;

uniform mat4 u_ortho;

struct Sprite {
    vec2 position;
    vec2 size;
    ivec2 flip;
    float rotation;
    int z_index;
    uint region_id;
};

layout(std430, binding = 0) readonly buffer layout_sprite {
    Sprite sb_sprites[];
};

mat4 translate(mat4 model, vec3 pos){
    mat4 translate_mat = mat4(
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        pos.x, pos.y, pos.z, 1.0
    );
    return model * translate_mat;
}
mat4 rotate(mat4 model, float rot){
    mat4 rot_mat = mat4(
        cos(rot), -sin(rot), 0.0, 0.0,
        sin(rot),  cos(rot), 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    );
    return model * rot_mat;
}
mat4 scale(mat4 model, vec2 scale){
    mat4 scale_mat = mat4(
        scale.x, 0.0, 0.0, 0.0,
        0.0, scale.y, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
    );
    return model * scale_mat;
}

void main() {
    Sprite sprite = sb_sprites[gl_InstanceID];

    mat4 model = mat4(1.0);
    model = translate(model, vec3(sprite.position, float(sprite.z_index)));
    model = rotate(model, sprite.rotation);
    model = scale(model, sprite.size);

    gl_Position = u_ortho * model * vec4(attr_pos, 0.0, 1.0);
    v_uv = attr_uv;
    v_flip = sprite.flip;
    v_region_id = sprite.region_id;
}
`
SPRITE_INSTANCED_SHADER_FRAG :: `
in vec2 v_uv;
in flat ivec2 v_flip;
in flat uint  v_region_id;
out vec4 out_colour;

uniform sampler2D u_atlas;

struct Region {
    vec2 norm_start;
    vec2 norm_size;
};

layout(std430, binding = 1) readonly buffer layout_regions {
    Region u_regions[];
};

vec2 get_uv() {
    vec2 processed_uv = v_uv;
    if(v_flip.x == 1) processed_uv.x = 1.0 - v_uv.x;
    if(v_flip.y == 1) processed_uv.y = 1.0 - v_uv.y;

    Region region = u_regions[v_region_id];

    return region.norm_start + processed_uv * region.norm_size;
}

void main() {
    out_colour = texture(u_atlas, get_uv());
}
`