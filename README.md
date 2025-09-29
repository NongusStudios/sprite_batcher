# Sprite Batcher

Simple performant OpenGL sprite batcher written in odin, for drawing many sprites. I made this as a generic starting point for my OpenGL projects.

## Usage

This renderer uses texture atlases to draw multiple different sprites with a single draw call.

1. Initialise the renderer with `init_sprite_batcher`
2. Create a `SpriteAtlas` with `create_sprite_atlas` (`defer destroy_sprite_atlas`).
    - Provide a filepath to the atlas.
    - Define each sprite within the atlas by providing an array of `SpriteRegionDesc`. Each region is defined by a start point and a size in pixels.
3. Call `start_render_pass`
4. Use `draw_sprite` to draw a single sprite or `draw_sprites` to draw a batch. Position and display data is provided by the `Sprite` structure.
    - `region_id` is the index of a defined `SpriteRegion` on the atlas.
5. Call `end_render_pass` to present the main framebuffer to the default one.

See the [example](examples/main.odin) for more detail.

## License

This package is under the [MIT License](LICENSE).
