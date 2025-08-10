const std = @import("std");
const glfw = @import("zglfw");
const gpu = @import("zgpu");
const wgpu = gpu.wgpu;
const math = @import("zmath");
const spline = @import("zspline");
const Vector2I = spline.Vector2I;
const Vector2B = spline.Vector2B;
const Vector2 = spline.Vector2;
const Circle = spline.Circle;
const CubicSpline = spline.CubicSpline;
const Line = spline.Line;

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

    //var state: State = try init(allc, window);
    var state: *State = try .init(allc);
    defer state.deinit(allc);

    state.gfx.height = 144;
    state.gfx.width = 256;

    state.game.pos = .zero;

    const bolt = &state.game.bolt;
    const size: Vector2I = .{ .x = state.gfx.width, .y = state.gfx.height };
    const center: Vector2I = .{ .x = @divTrunc(size.x, 2), .y = @divTrunc(size.y, 2) };
    bolt.head_pos = center.toFloat();
    bolt.head_dirc = 0;
    bolt.head_speed = 120;
    bolt.tail_pos = center.toFloat().sub(.{ .x = 30, .y = 0 });
    bolt.tail_speed = 72;
    bolt.tail_dirc = 0;

    state.render = try .init(allc, window);
    defer state.render.deinit(allc);

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        glfw.pollEvents();
        update(state);
        draw(state);
    }
}

const Vertex = struct {
    position: [3]f32,
    color: [3]f32,
    uv: [2]f32,
};

fn compCursorPos(window: *glfw.Window, dims: Vector2I) Vector2I {
    const texel_size: Vector2B = dims.toDouble();
    const size: [2]c_int = window.getSize();
    const window_size: Vector2B = .init(@floatFromInt(size[0]), @floatFromInt(size[1]));
    const _cursor_pos: [2]f64 = window.getCursorPos();
    const cursor_pos: Vector2B = .init(_cursor_pos[0], _cursor_pos[1]);

    const pos: Vector2I = texel_size.mult(cursor_pos.div(window_size)).trunc().round();
    return pos;
}

var points: [4]Vector2I = [1]Vector2I{.init(0, 0)} ** 4;
var point_count: u3 = 0;
fn addPointToSpline(state: *State) void {
    //const pos: [2]f64 = window.getCursorPos();
    //const int_pos: [2]u16 = .{ @intFromFloat(pos[0]), @intFromFloat(pos[1]) };
    //std.debug.print("({}, {})", .{ int_pos[0], int_pos[1] });
    if (point_count == 4) {
        //std.debug.print("Got 4 points!", .{});
        point_count = 0;
        return;
    }
    points[point_count] = compCursorPos(state.render.window, Vector2I.init(state.gfx.width, state.gfx.height));
    point_count += 1;
}

fn testQuadSpline(state: *State) void {
    const c: spline.QuadSpline = .{
        .p0 = .{ .x = 66, .y = 48 },
        .p1 = .{ .x = 150, .y = 51 },
        .p2 = .{ .x = 122, .y = 77 },
    };
    var buffer: [1024]Vector2I = std.mem.zeroes([1024]Vector2I);
    const _points = c.draw(buffer[0..]);
    const color: Color = .{
        .red = 255,
        .green = 255,
        .blue = 0,
        .a = 0,
    };
    for (_points) |p| {
        if (p.x < 0 or p.y < 0)
            continue;
        if (p.x >= state.gfx.width or p.y >= state.gfx.height)
            continue;
        state.gfx.image[@intCast(p.y * state.gfx.width + p.x)] = color;
    }
}

const Bolt = struct {
    head_pos: Vector2,
    head_dirc: f32,
    head_speed: f32,
    tail_pos: Vector2,
    tail_dirc: f32,
    tail_speed: f32,
};

fn drawBolt(state: *State) void {
    var buffer: [1024]Vector2I = std.mem.zeroes([1024]Vector2I);
    const green: Color = .{ .red = 0, .green = 255, .blue = 255, .a = 0 };
    const bolt = &state.game.bolt;
    const head_radius = 5;

    //draw head
    const circle: Circle = .init(bolt.head_pos.round(), head_radius);
    const ps = circle.draw(buffer[0..]);
    drawPoints(state, ps, green);
    const head_dirc = Vector2.init(std.math.cos(bolt.head_dirc), std.math.sin(bolt.head_dirc));
    const tail_dirc = Vector2.init(std.math.cos(bolt.tail_dirc), std.math.sin(bolt.tail_dirc));
    const normal_to_dirc = Vector2.init(head_dirc.y, -head_dirc.x).scale(head_radius);

    //draw tail 1
    const p0 = bolt.head_pos.add(normal_to_dirc);
    const p2 = bolt.tail_pos.sub(tail_dirc.scale(1));
    const q = p2.sub(p0);
    const det = head_dirc.x * q.y - q.x * head_dirc.y;
    const m = if (det > 0) std.math.sqrt(2 * head_radius * det / 3) else if (det < 0) std.math.sqrt(-2 * head_radius * det / 3) else 1;

    const tail_1: CubicSpline = .{
        .p0 = p0.round(),
        .p1 = bolt.head_pos.add(normal_to_dirc).add(head_dirc.scale(-m)).round(),
        .p2 = p2.round(),
        .p3 = bolt.tail_pos.round(),
    };
    const ps_tail_1 = tail_1.draw(buffer[ps.len..]);
    drawPoints(state, ps_tail_1, green);

    //draw tail 2
    const p0_ = bolt.head_pos.add(normal_to_dirc.scale(-1));
    const p2_ = bolt.tail_pos.sub(tail_dirc.scale(1));
    const q_ = p2_.sub(p0_);
    const det_ = head_dirc.x * q_.y - q_.x * head_dirc.y;
    const m_ = if (det_ > 0) std.math.sqrt(2 * det_ * head_radius / 3) else if (det_ < 0) std.math.sqrt(-2 * head_radius * det_ / 3) else 1;

    const tail_2: CubicSpline = .{
        .p0 = p0_.round(),
        .p1 = bolt.head_pos.add(normal_to_dirc.scale(-1)).add(head_dirc.scale(-m_)).round(),
        .p2 = p2_.round(),
        .p3 = bolt.tail_pos.round(),
    };
    const ps_tail_2 = tail_2.draw(buffer[(ps.len + ps_tail_1.len)..]);
    drawPoints(state, ps_tail_2, green);

    //draw dirc
    const dirc: Line = .{
        .p = bolt.head_pos.round(),
        .q = bolt.head_pos.add(head_dirc).round(),
    };
    const ps_dirc = dirc.draw(buffer[(ps.len + ps_tail_1.len + ps_tail_2.len)..]);
    drawPoints(state, ps_dirc, .{ .red = 255, .green = 0, .blue = 0, .a = 0 });
}

fn drawCircle(state: *State) void {
    const size: Vector2I = .{ .x = state.gfx.width, .y = state.gfx.height };
    const midPoint: Vector2I = .{ .x = @divTrunc(size.x, 2), .y = @divTrunc(size.y, 2) };
    const circle: Circle = .init(midPoint, 30);
    var buffer: [1024]Vector2I = std.mem.zeroes([1024]Vector2I);
    const ps = circle.draw(buffer[0..]);
    drawPoints(state, ps, .{ .red = 0, .green = 255, .blue = 0, .a = 0 });
}

fn drawPoints(state: *State, ps: []Vector2I, color: Color) void {
    for (ps) |p| {
        if (p.x < 0 or p.y < 0)
            continue;
        if (p.x >= state.gfx.width or p.y >= state.gfx.height)
            continue;
        const val = p.y * state.gfx.width + p.x; //p[0] * @as(u32, @intCast(state.height)) + p[1];
        state.gfx.image[@intCast(val)] = color;
    }
}

fn drawSpline(state: *State, out_buffer: []Vector2I) ?[]Vector2I {
    const ps = points[0..point_count];
    for (ps) |p| {
        const val = p.y * state.gfx.width + p.x; //p[0] * @as(u32, @intCast(state.height)) + p[1];
        state.gfx.image[@intCast(val)] = .{ .red = 255, .green = 0, .blue = 0, .a = 0 };
    }

    if (point_count == 4) {
        //std.debug.print("draw spline", .{});
        //var c: spline.CubicSpline = .{
        //    .p0 = points[0],
        //    .p1 = points[1],
        //    .p2 = points[2],
        //    .p3 = points[3],
        //};
        const c: spline.CubicSpline = .{
            .p0 = points[0],
            .p1 = points[1],
            .p2 = points[2],
            .p3 = points[3],
        };
        return c.draw(out_buffer);
    }
    return null;
}

const BaseGraphicsState = struct {
    gfx_cntx: *gpu.GraphicsContext,

    pipeline: gpu.RenderPipelineHandle,
    bind_group: gpu.BindGroupHandle,

    vertex_buffer: gpu.BufferHandle,
    index_buffer: gpu.BufferHandle,

    texture: gpu.TextureHandle,
    texture_view: gpu.TextureViewHandle,
    sampler: gpu.SamplerHandle,

    window: *glfw.Window,

    pub fn init(allc: std.mem.Allocator, window: *glfw.Window) !BaseGraphicsState {
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
                .uv = [2]f32{ 0.0, 1.0 },
            },
            .{
                .position = [3]f32{ 1.0, -1.0, 0.0 },
                .color = [3]f32{ 0.0, 0.0, 1.0 },
                .uv = [2]f32{ 1.0, 1.0 },
            },
            .{
                .position = [3]f32{ 1.0, 1.0, 0.0 },
                .color = [3]f32{ 0.0, 0.0, 1.0 },
                .uv = [2]f32{ 1.0, 0.0 },
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

        const width = 256;
        const height = 144;
        const image: [width * height]Color = [1]Color{.{
            .red = 0,
            .green = 0,
            .blue = 0,
            .a = 0,
        }} ** (width * height);

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
        const texture_view = gfx_cntx.createTextureView(texture, .{
            .format = .rgba8_unorm,
        });

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

        return BaseGraphicsState{
            .gfx_cntx = gfx_cntx,

            .pipeline = pipeline,
            .bind_group = bind_group,

            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,

            .texture = texture,
            .texture_view = texture_view,
            .sampler = sampler,

            //.width = width,
            //.height = height,

            .window = window,
            //.mouse_pressed = false,
            //.image = image,
            //.pos = .zero,
        };
    }

    fn deinit(state: *BaseGraphicsState, allc: std.mem.Allocator) void {
        state.gfx_cntx.destroy(allc);
        state.* = undefined;
    }
};

const ScreenState = struct {
    width: u16,
    height: u16,
    image: [256 * 144]Color,
};

const GameState = struct {
    mouse_pressed: bool,
    pos: Vector2I,
    point_buffer: [1024]Vector2I,
    bolt: Bolt,
    last_time: f64,
    dt: f32,
    dt_phys: f32,
};

const State = struct {
    render: BaseGraphicsState,
    gfx: ScreenState,
    game: GameState,

    fn init(allc: std.mem.Allocator) !*State {
        return allc.create(State);
    }

    fn deinit(state: *State, allc: std.mem.Allocator) void {
        allc.destroy(state);
        state.* = undefined;
    }
};

const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
    a: u8,
};

const getIndexErr = error{
    outOfRange,
};

fn getIndex(pos: Vector2I, size: Vector2I) !u32 {
    if (pos.x < 0 or pos.y < 0)
        return getIndexErr.outOfRange;
    if (pos.x >= size.x or pos.y >= size.y)
        return getIndexErr.outOfRange;
    return @as(u32, @intCast(pos.y)) *
        @as(u32, @intCast(size.x)) +
        @as(u32, @intCast(pos.x));
}

fn physics_update(state: *State) void {
    //bolt update
    const old_head_pos = state.game.bolt.head_pos;
    updateHead(state);
    updateTail(state, old_head_pos);
}

fn updateHead(state: *State) void {
    const bolt = &state.game.bolt;
    const size: Vector2I = .{ .x = state.gfx.width, .y = state.gfx.height };
    const mouse_pos = compCursorPos(state.render.window, size).toFloat();

    const turning_dirc = mouse_pos.sub(bolt.head_pos);
    var turning_angle: f64 = std.math.atan(turning_dirc.y / turning_dirc.x);
    if (turning_dirc.x < 0)
        turning_angle += (if (turning_dirc.y >= 0) std.math.pi else -std.math.pi);

    const current_angle: f64 = bolt.head_dirc;

    var diff_angle = turning_angle - current_angle;
    if (diff_angle >= std.math.pi) {
        diff_angle -= 2 * std.math.pi;
    } else if (diff_angle < -std.math.pi) {
        diff_angle += 2 * std.math.pi;
    }
    const smallness = 0.1 * 2 * std.math.pi;
    const turning_anticlockwise: f64 =
        if (smallness >= (if (diff_angle < 0) -diff_angle else diff_angle)) 0.0 else if (diff_angle >= 0) 1.0 else -1.0;

    const turning_rate = 0.4; //between 0 and 1, how much it can rotate by
    const turning_speed = turning_rate * 2 * std.math.pi;
    const new_angle = current_angle + turning_anticlockwise * turning_speed * state.game.dt_phys;

    bolt.head_dirc = @floatCast(new_angle);
    const head_dirc_vec = Vector2.init(@floatCast(std.math.cos(new_angle)), @floatCast(std.math.sin(new_angle)));
    bolt.head_pos = bolt.head_pos.add(head_dirc_vec.scale(bolt.head_speed * state.game.dt_phys));
}

fn updateTail(state: *State, towards: Vector2) void {
    const bolt = &state.game.bolt;
    const turning_dirc = towards.sub(bolt.tail_pos);
    var turning_angle: f64 = std.math.atan(turning_dirc.y / turning_dirc.x);
    if (turning_dirc.x < 0)
        turning_angle += (if (turning_dirc.y >= 0) std.math.pi else -std.math.pi);

    const current_angle: f64 = bolt.tail_dirc;

    var diff_angle = turning_angle - current_angle;
    if (diff_angle >= std.math.pi) {
        diff_angle -= 2 * std.math.pi;
    } else if (diff_angle < -std.math.pi) {
        diff_angle += 2 * std.math.pi;
    }
    const smallness = 0.1 * 2 * std.math.pi;
    const turning_anticlockwise: f64 =
        if (smallness >= (if (diff_angle < 0) -diff_angle else diff_angle)) 0.0 else if (diff_angle >= 0) 1.0 else -1.0;

    const turning_rate = 0.4; //between 0 and 1, how much it can rotate by
    const turning_speed = turning_rate * 2 * std.math.pi;
    const new_angle = current_angle + turning_anticlockwise * turning_speed * state.game.dt_phys;
    bolt.tail_dirc = @floatCast(new_angle);
    const tail_dirc_vec = Vector2.init(@floatCast(std.math.cos(new_angle)), @floatCast(std.math.sin(new_angle)));
    bolt.tail_pos = bolt.tail_pos.add(tail_dirc_vec.scale(bolt.tail_speed * state.game.dt_phys));
}

fn update(state: *State) void {
    //time
    const new_time = glfw.getTime();
    state.game.dt = @floatCast(new_time - state.game.last_time);
    state.game.last_time = new_time;
    state.game.dt_phys = state.game.dt; //+= state.game.dt;
    //if (state.game.dt_phys >= 0.016666) {
    physics_update(state);
    //    state.game.dt_phys = 0;
    //}
    //input
    processInput(state);

    //clear screen
    @memset(&state.gfx.image, .{ .red = 0, .green = 0, .blue = 0, .a = 0 });

    //draw the little moving blue dot
    state.game.pos.x += 1;
    if (state.game.pos.x == state.gfx.width)
        state.game.pos.x = 0;
    const size: Vector2I = .{ .x = state.gfx.width, .y = state.gfx.height };
    const index: u32 = getIndex(state.game.pos, size) catch {
        std.debug.print("oof ({}, {}) \n", .{ state.game.pos.x, state.game.pos.y });
        return;
    };
    state.gfx.image[@intCast(index)] = .{
        .red = 0,
        .green = 0,
        .blue = 255,
        .a = 0,
    };

    //bolt drawer
    drawBolt(state);

    //spline drawer
    const limit = 1024;
    const ps = drawSpline(state, state.game.point_buffer[0..limit]) orelse return;
    const color: Color = .{ .red = 0, .green = 0, .blue = 255, .a = 0 };
    for (ps) |p| {
        if (p.x < 0 or p.y < 0)
            continue;
        if (p.x >= state.gfx.width or p.y >= state.gfx.height)
            continue;
        state.gfx.image[@intCast(p.y * state.gfx.width + p.x)] = color;
    }
    //testQuadSpline(state);
    //drawCircle(state);
}

fn processInput(state: *State) void {
    const mouse_action = state.render.window.getMouseButton(glfw.MouseButton.left);
    if (mouse_action == .press and !state.game.mouse_pressed) {
        state.game.mouse_pressed = true;
        addPointToSpline(state);
    } else if (mouse_action != .press and state.game.mouse_pressed)
        state.game.mouse_pressed = false;
}

fn draw(state: *State) void {
    const gfx_cntx = state.render.gfx_cntx;

    const back_buffer_view = gfx_cntx.swapchain.getCurrentTextureView();
    defer back_buffer_view.release();

    const _window_size = state.render.window.getSize();
    const window_size: Vector2 = .init(@floatFromInt(_window_size[0]), @floatFromInt(_window_size[1]));
    const ratio = 9.0 / 16.0;
    //should flip to prioritizing the y, more normal that way around
    var canvas_size: Vector2 = .init(window_size.x, ratio * window_size.x);
    //y too big if keep the x
    if (canvas_size.y > window_size.y) {
        canvas_size.x = window_size.y / ratio;
        canvas_size.y = window_size.y;
    }

    const scale = canvas_size.div(window_size);

    const view: math.Mat = .{
        .{ scale.x, 0, 0, 0 },
        .{ 0, scale.y, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };

    const commands = commands: {
        const encoder = gfx_cntx.device.createCommandEncoder(null);
        defer encoder.release();
        pass: {
            const vb_info = gfx_cntx.lookupResourceInfo(state.render.vertex_buffer) orelse break :pass;
            const ib_info = gfx_cntx.lookupResourceInfo(state.render.index_buffer) orelse break :pass;
            const pipeline = gfx_cntx.lookupResource(state.render.pipeline) orelse break :pass;
            const bind_group = gfx_cntx.lookupResource(state.render.bind_group) orelse break :pass;

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
                .{ .texture = gfx_cntx.lookupResource(state.render.texture).? },
                .{ .bytes_per_row = state.gfx.width * @sizeOf(Color), .rows_per_image = state.gfx.height },
                .{ .width = state.gfx.width, .height = state.gfx.height },
                Color,
                state.gfx.image[0..],
            );

            // Draw
            {
                const mem = gfx_cntx.uniformsAllocate(math.Mat, 1);
                mem.slice[0] = math.transpose(view);

                pass.setBindGroup(0, bind_group, &.{mem.offset});
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

    //swaps frame buffers
    if (gfx_cntx.present() == .swap_chain_resized) {}
}
