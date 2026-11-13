const std = @import("std");
const mg = @import("mandagram");

pub const Config = struct { id: [:0]const u8, name: [:0]const u8, description: [:0]const u8, spec: mg.settings.Spec };

/// Example-only export boilerplate. Actual declarations are ordinary kit.Spec/Section values.
pub fn exportPlugin(comptime config: Config) void {
    const Implementation = struct {
        const metadata_value = mg.PluginMetadata{
            .name = config.name.ptr,
            .version = "1.0.0",
            .author = "MandaGram Examples",
            .description = config.description.ptr,
        };
        const schema = config.spec.json();
        var api: ?*const mg.PluginApi = null;

        fn metadata() callconv(.c) *const mg.PluginMetadata {
            return &metadata_value;
        }
        fn settings() callconv(.c) [*:0]const u8 {
            return schema.ptr;
        }
        fn init(host: *const mg.PluginApi) callconv(.c) bool {
            var buffer: [4097]u8 = undefined;
            inline for (config.spec.sections) |section| inline for (section.rows) |row| {
                const field = switch (row) {
                    inline else => |value| value,
                };
                _ = config.spec.read(host, config.id.ptr, field.key, &buffer) orelse return false;
                switch (row) {
                    .toggle, .checkbox => {
                        _ = config.spec.boolean(host, config.id.ptr, field.key) orelse return false;
                    },
                    .slider => {
                        _ = config.spec.integer(host, config.id.ptr, field.key) orelse return false;
                    },
                    else => {},
                }
            };
            api = host;
            return true;
        }
        // Test-only diagnostic export: every read goes to the host, with no settings cache.
        fn readSetting(key: ?[*:0]const u8, output: ?[*]u8, capacity: u32) callconv(.c) i32 {
            const host = api orelse return -1;
            const name = std.mem.span(key orelse return -1);
            const out = output orelse return -1;
            inline for (config.spec.sections) |section| inline for (section.rows) |row| {
                const field = switch (row) {
                    inline else => |value| value,
                };
                if (std.mem.eql(u8, name, field.key)) {
                    const value = config.spec.read(host, config.id.ptr, field.key, out[0..capacity]) orelse return -1;
                    return @intCast(value.len);
                }
            };
            return -1;
        }
    };
    @export(&Implementation.metadata, .{ .name = "mandagram_plugin_metadata" });
    @export(&Implementation.settings, .{ .name = "mandagram_plugin_settings" });
    @export(&Implementation.init, .{ .name = "mandagram_plugin_init" });
    @export(&Implementation.readSetting, .{ .name = "mandagram_demo_read_setting" });
}
