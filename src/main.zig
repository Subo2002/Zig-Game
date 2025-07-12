const std = @import("std");
const glfw = @import("zglfw");
const gpu = @import("zgpu");
const wgpu = gpu.wgpu;
const math = @import("zmath");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("Zig_Game_lib");

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    const window = try glfw.createWindow(1600, 1000, "Test Window", null);
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    const page = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page);
    const allc = arena.allocator();
    defer arena.deinit();

    var state: BaseState = try init(allc, window);
    state.window = window;
    defer deinit(allc, &state);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        glfw.pollEvents();
        update(&state);
        draw(&state);
    }
}

const Vertex = struct {
    position: [3]f32,
    color: [3]f32,
    uv: [2]f32,
};

fn compCursorPos(window: *glfw.Window, dims: @Vector(2, u16)) @Vector(2, u16) {
    const texel_size: @Vector(2, f64) = @floatFromInt(dims);
    const window_size: @Vector(2, f64) = @floatFromInt(@as(@Vector(2, c_int), window.getSize()));

    const pos: @Vector(2, u16) = @intFromFloat(texel_size * (window.getCursorPos() / window_size));
    std.debug.print("({}, {})", .{ pos[0], pos[1] });
    return pos;
}

var points: [4]@Vector(2, u16) = [1]@Vector(2, u16){.{ 0, 0 }} ** 4; //@Vector(2, u16) = [1]@Vector(2, u16){.{ 0, 0 }} ** 4;
var point_count: u3 = 0;
fn addPointToSpline(state: *BaseState) void {
    //const pos: [2]f64 = window.getCursorPos();
    //const int_pos: [2]u16 = .{ @intFromFloat(pos[0]), @intFromFloat(pos[1]) };
    //std.debug.print("({}, {})", .{ int_pos[0], int_pos[1] });
    points[point_count] = compCursorPos(state.window, .{ state.width, state.height });
    point_count += 1;
    if (point_count == 4) {
        //std.debug.print("Got 4 points!", .{});
        point_count = 0;
    }
}

fn drawSpline(state: *BaseState) void {
    const ps = points[0..point_count];
    for (ps) |p| {
        const val: u32 = p[0] * @as(u32, @intCast(state.height)) + p[1]; //p[0] * @as(u32, @intCast(state.height)) + p[1];
        state.image[val] = .{ .red = 255, .green = 0, .blue = 0, .a = 0 };
    }

    if (point_count == 4) {
        std.debug.print("draw spline", .{});
    }
}

const BaseState = struct {
    gfx_cntx: *gpu.GraphicsContext,

    pipeline: gpu.RenderPipelineHandle,
    bind_group: gpu.BindGroupHandle,

    vertex_buffer: gpu.BufferHandle,
    index_buffer: gpu.BufferHandle,

    texture: gpu.TextureHandle,
    texture_view: gpu.TextureViewHandle,
    sampler: gpu.SamplerHandle,

    width: u16,
    height: u16,

    window: *glfw.Window,

    mouse_pressed: bool,

    image: [512 * 288]Color,
    pos: @Vector(2, u16),
};

const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
    a: u8,
};

pub fn init(allc: std.mem.Allocator, window: *glfw.Window) !BaseState {
    const gfx_cntx = try gpu.GraphicsContext.create(
        allc,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&glfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&glfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&glfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&glfw.getX11Display),
            .fn_getX11Window = @ptrCast(&glfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&glfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&glfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&glfw.getCocoaWindow),
        },
        .{},
    );
    errdefer gfx_cntx.destroy(allc);

    //create bind group layout for rendering
    const bind_group_layout = gfx_cntx.createBindGroupLayout(&.{
        gpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, true, 0),
        gpu.textureEntry(1, .{ .fragment = true }, .float, .tvdim_2d, false),
        gpu.samplerEntry(2, .{ .fragment = true }, .filtering),
    });
    defer gfx_cntx.releaseResource(bind_group_layout);

    const pipeline_layout = gfx_cntx.createPipelineLayout(&.{bind_group_layout});
    defer gfx_cntx.releaseResource(pipeline_layout);

    const pipeline = pipeline: {
        const vs_module = gpu.createWgslShaderModule(gfx_cntx.device, @embedFile("vertex.wgsl"), "vs");
        defer vs_module.release();

        const fs_module = gpu.createWgslShaderModule(gfx_cntx.device, @embedFile("fragment.wgsl"), "fs");
        defer fs_module.release();

        const color_targets = [_]wgpu.ColorTargetState{.{
            .format = gpu.GraphicsContext.swapchain_format,
        }};

        const vertex_attributes = [_]wgpu.VertexAttribute{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "color"), .shader_location = 1 },
            .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 2 },
        };

        const vertex_buffers = [_]wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        }};

        const pipeline_descriptor = wgpu.RenderPipelineDescriptor{ .vertex = wgpu.VertexState{
            .module = vs_module,
            .entry_point = "main",
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        }, .primitive = wgpu.PrimitiveState{
            .front_face = .ccw,
            .cull_mode = .none,
            .topology = .triangle_list,
        }, .depth_stencil = null, .fragment = &wgpu.FragmentState{
            .module = fs_module,
            .entry_point = "main",
            .target_count = color_targets.len,
            .targets = &color_targets,
        } };

        break :pipeline gfx_cntx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
    };

    //create vertex buffer
    const vertex_buffer = gfx_cntx.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = 4 * @sizeOf(Vertex),
    });
    const vertex_data = [_]Vertex{
        .{
            .position = [3]f32{ -1.0, 1.0, 0.0 },
            .color = [3]f32{ 1.0, 0.0, 0.0 },
            .uv = [2]f32{ 0.0, 0.0 },
        },
        .{
            .position = [3]f32{ -1.0, -1.0, 0.0 },
            .color = [3]f32{ 0.0, 1.0, 0.0 },
            .uv = [2]f32{ 1.0, 0.0 },
        },
        .{
            .position = [3]f32{ 1.0, -1.0, 0.0 },
            .color = [3]f32{ 0.0, 0.0, 1.0 },
            .uv = [2]f32{ 1.0, 1.0 },
        },
        .{
            .position = [3]f32{ 1.0, 1.0, 0.0 },
            .color = [3]f32{ 0.0, 0.0, 1.0 },
            .uv = [2]f32{ 0.0, 1.0 },
        },
    };
    gfx_cntx.queue.writeBuffer(gfx_cntx.lookupResource(vertex_buffer).?, 0, Vertex, vertex_data[0..]);

    //create index buffer
    const index_buffer = gfx_cntx.createBuffer(.{
        .usage = .{ .copy_dst = true, .index = true },
        .size = 6 * @sizeOf(u32),
    });
    const index_data = [_]u32{
        0, 1, 2,
        0, 2, 3,
    };
    gfx_cntx.queue.writeBuffer(gfx_cntx.lookupResource(index_buffer).?, 0, u32, index_data[0..]);

    const width = 512;
    const height = 288;
    const image: [width * height]Color = [1]Color{.{ .red = 0, .green = 0, .blue = 0, .a = 0 }} ** (width * height);

    //create texture
    const texture = gfx_cntx.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .size = .{
            .width = width,
            .height = height,
            .depth_or_array_layers = 1,
        },
        .format = gpu.imageInfoToTextureFormat(
            4,
            1,
            false,
        ),
        .mip_level_count = 1,
    });
    const texture_view = gfx_cntx.createTextureView(texture, .{});

    gfx_cntx.queue.writeTexture(
        .{ .texture = gfx_cntx.lookupResource(texture).? },
        .{ .bytes_per_row = width * @sizeOf(Color), .rows_per_image = height },
        .{ .width = width, .height = height },
        Color,
        image[0..],
    );

    const sampler = gfx_cntx.createSampler(.{
        .mag_filter = .nearest,
        .min_filter = .nearest,
    });

    const bind_group = gfx_cntx.createBindGroup(bind_group_layout, &.{
        .{ .binding = 0, .buffer_handle = gfx_cntx.uniforms.buffer, .offset = 0, .size = 512 },
        .{ .binding = 1, .texture_view_handle = texture_view },
        .{ .binding = 2, .sampler_handle = sampler },
    });

    return BaseState{
        .gfx_cntx = gfx_cntx,

        .pipeline = pipeline,
        .bind_group = bind_group,

        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,

        .texture = texture,
        .texture_view = texture_view,
        .sampler = sampler,

        .width = width,
        .height = height,

        .window = undefined,
        .mouse_pressed = false,
        .image = image,
        .pos = .{ 0, 0 },
    };
}

fn deinit(allc: std.mem.Allocator, state: *BaseState) void {
    state.gfx_cntx.destroy(allc);
    state.* = undefined;
}

fn update(state: *BaseState) void {
    processInput(state);

    state.image[state.pos[1] * state.height + state.pos[0]] = .{ .red = 0, .green = 0, .blue = 0, .a = 0 };
    state.pos += .{ 1, 0 };
    if (state.pos[0] == 256)
        state.pos[0] = 0;
    state.image[state.pos[1] * state.height + state.pos[0]] = .{ .red = 0, .green = 0, .blue = 255, .a = 0 };
    //@memset(&state.image, .{ .red = 0, .green = 0, .blue = 0, .a = 0 });
    //drawSpline(state);
}

fn processInput(state: *BaseState) void {
    const mouse_action = state.window.getMouseButton(glfw.MouseButton.left);
    if (mouse_action == .press and !state.mouse_pressed) {
        state.mouse_pressed = true;
        addPointToSpline(state);
    } else if (mouse_action != .press and state.mouse_pressed)
        state.mouse_pressed = false;
}

fn draw(state: *BaseState) void {
    const gfx_cntx = state.gfx_cntx;

    const back_buffer_view = gfx_cntx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const commands = commands: {
        const encoder = gfx_cntx.device.createCommandEncoder(null);
        defer encoder.release();
        pass: {
            const vb_info = gfx_cntx.lookupResourceInfo(state.vertex_buffer) orelse break :pass;
            const ib_info = gfx_cntx.lookupResourceInfo(state.index_buffer) orelse break :pass;
            const pipeline = gfx_cntx.lookupResource(state.pipeline) orelse break :pass;
            const bind_group = gfx_cntx.lookupResource(state.bind_group) orelse break :pass;

            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .clear,
                .store_op = .store,
            }};
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
                .depth_stencil_attachment = null,
            };
            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }

            pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
            pass.setIndexBuffer(ib_info.gpuobj.?, .uint32, 0, ib_info.size);

            pass.setPipeline(pipeline);

            gfx_cntx.queue.writeTexture(
                .{ .texture = gfx_cntx.lookupResource(state.texture).? },
                .{ .bytes_per_row = state.width * @sizeOf(Color), .rows_per_image = state.height },
                .{ .width = state.width, .height = state.height },
                Color,
                state.image[0..],
            );

            // Draw
            {
                pass.setBindGroup(0, bind_group, &.{0});
                pass.drawIndexed(6, 2, 0, 0, 0);
            }
        }
        {
            const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                .view = back_buffer_view,
                .load_op = .load,
                .store_op = .store,
            }};
            const render_pass_info = wgpu.RenderPassDescriptor{
                .color_attachment_count = color_attachments.len,
                .color_attachments = &color_attachments,
            };
            const pass = encoder.beginRenderPass(render_pass_info);
            defer {
                pass.end();
                pass.release();
            }
        }

        break :commands encoder.finish(null);
    };
    defer commands.release();

    gfx_cntx.submit(&.{commands});

    if (gfx_cntx.present() == .swap_chain_resized) {}
}
