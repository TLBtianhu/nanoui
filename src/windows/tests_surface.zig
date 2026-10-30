const std = @import("std");
const testing = std.testing;
const w = @import("win32.zig");
const ui = @import("../ui/ui.zig");
const App = @import("app.zig").App;

const Page = struct {
    open: bool = false,

    fn view(p: *Page, c: *ui.Context) void {
        const root = ui.div(c).p(20);
        defer root.end();
        const f = ui.motion.frame(c, .{
            .target = .{
                .width = if (p.open) 280 else 180,
                .height = if (p.open) 150 else 96,
                .radius = if (p.open) 24 else 14,
                .background = if (p.open) c.theme.accent else c.theme.surface,
            },
            .press = .{ .scale = 0.96 },
            .transition = .{ .spring = ui.motion.Spring.bouncy },
        });
        const card = ui.div(c).column().p(16).border(c.theme.border).clip().control().motion(f);
        defer card.end();
        if (card.clicked()) p.open = !p.open;
        ui.text(c, if (p.open) "Open" else "Click me", .{ .weight = .semibold });
    }
};

test "a motion click and its animated frames draw through a hidden Windows surface" {
    const gpa = testing.allocator;
    const app = try gpa.create(App);
    app.* = .{
        .gpa = gpa,
        .io = std.Io.Threaded.global_single_threaded.io(),
        .options = .{ .quit_on_last_window_closed = false },
        .flags = .{ .hidden = true },
        .gui = true,
    };
    defer app.destroy();
    var p: Page = .{};
    const win = try app.newWindow(.{
        .title = "hidden motion test",
        .width = 400,
        .height = 300,
        .visible = false,
        .content = .{ .view = .init(&p, Page.view) },
    });
    const s = win.surface.?;
    var at: ui.Point = .{};
    for (s.ctx.nodes.items) |n| switch (n.content) {
        .text => |t| {
            if (std.mem.eql(u8, t.str, "Click me")) at = .{ .x = n.rect.x + n.rect.w / 2, .y = n.rect.y + n.rect.h / 2 };
        },
        else => {},
    };
    try testing.expect(at.x > 0);
    s.ctx.input.mouse = at;
    s.ctx.updateHot();
    s.ctx.pointerDown();
    s.frame();
    s.ctx.pointerUp();
    s.frame();
    try testing.expect(p.open);
    for (0..120) |_| {
        std.Io.sleep(std.Io.Threaded.global_single_threaded.io(), .fromMilliseconds(16), .awake) catch {};
        s.frame();
        s.pixels.draw(gpa, .{
            .instances = s.instances.items,
            .text = &s.text,
            .clear = s.ctx.theme.background,
            .size = s.size,
            .scale = s.scale,
            .textures = s.ctx.textures.items,
        });
    }
}

test "borderless, translucent and tool-window styles, and opacity at run time" {
    const gpa = testing.allocator;
    const app = try gpa.create(App);
    app.* = .{
        .gpa = gpa,
        .io = std.Io.Threaded.global_single_threaded.io(),
        .options = .{ .quit_on_last_window_closed = false },
        .flags = .{ .hidden = true },
        .gui = true,
    };
    defer app.destroy();
    var p: Page = .{};
    const win = try app.newWindow(.{
        .title = "hidden styles test",
        .width = 240,
        .height = 160,
        .visible = false,
        .decorations = false,
        .opacity = 0.5,
        .skip_taskbar = true,
        .content = .{ .view = .init(&p, Page.view) },
    });
    try testing.expectEqual(@as(u32, w.WS_POPUP | w.WS_THICKFRAME), win.style);
    try testing.expectEqual(@as(u32, w.WS_EX_LAYERED | w.WS_EX_TOOLWINDOW), win.ex_style);
    const h = win.hwnd.?;
    const ex: u32 = @intCast(w.GetWindowLongPtrW(h, w.GWL_EXSTYLE));
    try testing.expect(ex & w.WS_EX_LAYERED != 0);
    try testing.expect(ex & w.WS_EX_TOOLWINDOW != 0);
    var alpha: u8 = 0;
    try testing.expect(w.GetLayeredWindowAttributes(h, null, &alpha, null) != 0);
    try testing.expectEqual(@as(u8, 128), alpha);
    // Constant alpha and a flip swap chain don't go together: GDI draws.
    try testing.expect(win.surface.?.no_d3d);

    win.setOpacity(1);
    try testing.expectEqual(@as(f64, 1), win.opacity);
    try testing.expectEqual(@as(u32, w.WS_EX_TOOLWINDOW), win.ex_style);
    const ex_opaque: u32 = @intCast(w.GetWindowLongPtrW(h, w.GWL_EXSTYLE));
    try testing.expect(ex_opaque & w.WS_EX_LAYERED == 0);
    try testing.expect(!win.surface.?.no_d3d);

    win.setOpacity(-1); // clamped to 0: invisible, but still there
    try testing.expectEqual(@as(f64, 0), win.opacity);
    try testing.expect(win.ex_style & w.WS_EX_LAYERED != 0);
    try testing.expect(win.surface.?.no_d3d);
}
