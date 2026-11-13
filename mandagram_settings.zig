//! Typed settings DSL for native plugins. Spec.json() validates and serializes at comptime;
//! the host still owns rendering, generations and portable persistence.
const std = @import("std");

pub const Icon = enum { AlternateEmail, Groups, SmartToy, Notifications, Visibility, Palette, Animation, CheckCircle };
pub const Toggle = struct {
    key: []const u8,
    title: []const u8,
    description: []const u8 = "",
    default: bool = false,
    icon: ?Icon = null,
};
pub const Text = struct {
    key: []const u8,
    title: []const u8,
    description: []const u8 = "",
    default: []const u8 = "",
    multiline: bool = false,
    max_bytes: u16 = 4096,
    legacy_file: ?[]const u8 = null,
};
pub const Option = struct { value: []const u8, label: []const u8, description: []const u8 = "" };
pub const Choice = struct {
    key: []const u8,
    title: []const u8,
    description: []const u8 = "",
    options: []const Option,
    default: ?[]const u8 = null,
};
pub const Slider = struct {
    key: []const u8,
    title: []const u8,
    description: []const u8 = "",
    min: i32 = 0,
    max: i32 = 100,
    step: i32 = 1,
    default: ?i32 = null,
};
pub const Row = union(enum) { toggle: Toggle, checkbox: Toggle, text: Text, select: Choice, radio: Choice, slider: Slider };
pub const Section = struct { header: []const u8 = "", footer: []const u8 = "", rows: []const Row };

pub const Spec = struct {
    sections: []const Section,

    /// Constant, zero-terminated UTF-8 data; no allocator, JNI, hooks or runtime JSON builder.
    pub fn json(comptime self: Spec) [:0]const u8 {
        return comptime blk: {
            @setEvalBranchQuota(2_000_000);
            if (self.validate()) |failure| @compileError("Invalid plugin settings DSL: " ++ @tagName(failure));
            const encoded = encode(self);
            // Match the host's schema length bound conservatively in UTF-8 bytes.
            if (encoded.len > 64_000) @compileError("Invalid plugin settings DSL: schema_too_large");
            const terminated = encoded ++ "\x00";
            break :blk terminated[0..encoded.len :0];
        };
    }

    /// Useful for tools/tests. json() turns any validation failure into a compile error.
    pub fn validate(comptime self: Spec) ?ValidationError {
        comptime var keys: []const []const u8 = &.{};
        inline for (self.sections) |section| {
            if (!validText(section.header, 120, false) or !validText(section.footer, 500, false)) return .invalid_section;
            inline for (section.rows) |row| {
                const field = switch (row) {
                    inline else => |value| value,
                };
                if (!identifier(field.key)) return .invalid_key;
                inline for (keys) |previous| if (std.mem.eql(u8, previous, field.key)) return .duplicate_key;
                keys = keys ++ &[_][]const u8{field.key};
                if (keys.len > 100) return .too_many_fields;
                if (!validText(field.title, 120, true) or !validText(field.description, 500, false)) return .invalid_label;
                switch (row) {
                    .toggle, .checkbox => {},
                    .text => |text| {
                        if (text.max_bytes == 0 or text.max_bytes > 4096 or text.default.len > text.max_bytes or
                            !std.unicode.utf8ValidateSlice(text.default) or std.mem.indexOfScalar(u8, text.default, 0) != null) return .invalid_text;
                        if (text.legacy_file) |filename| {
                            if (filename.len == 0 or filename.len > 64 or std.mem.eql(u8, filename, ".") or std.mem.eql(u8, filename, "..")) return .invalid_legacy_file;
                            for (filename) |char| if (!identifierChar(char) and char != '.') return .invalid_legacy_file;
                        }
                    },
                    .select, .radio => |choice| {
                        if (choice.options.len == 0 or choice.options.len > 50) return .invalid_options;
                        var found_default = choice.default == null;
                        for (choice.options, 0..) |option, index| {
                            if (!validText(option.value, 128, false) or std.mem.indexOfScalar(u8, option.value, 0) != null or !validText(option.label, 120, true) or
                                !validText(option.description, 500, false)) return .invalid_options;
                            for (choice.options[0..index]) |previous| if (std.mem.eql(u8, previous.value, option.value)) return .duplicate_option;
                            if (choice.default) |value| if (std.mem.eql(u8, value, option.value)) {
                                found_default = true;
                            };
                        }
                        if (!found_default) return .invalid_default;
                    },
                    .slider => |slider| {
                        const span = @as(i64, slider.max) - slider.min;
                        if (span <= 0 or slider.step <= 0 or @mod(span, slider.step) != 0 or @divExact(span, slider.step) > 1000) return .invalid_range;
                        const value = slider.default orelse slider.min;
                        if (value < slider.min or value > slider.max or @mod(@as(i64, value) - slider.min, slider.step) != 0) return .invalid_default;
                    },
                }
            }
        }
        return null;
    }

    /// Keys/types are checked at compile time. Values are read live through the existing API.
    pub fn read(comptime self: Spec, api: anytype, plugin_name: [*:0]const u8, comptime key: []const u8, out: []u8) ?[]const u8 {
        const field = comptime self.find(key);
        const capacity = comptime switch (field) {
            .toggle, .checkbox => 6,
            .text => |text| @as(usize, text.max_bytes) + 1,
            .slider => 12,
            .select, .radio => |choice| blk: {
                var size: usize = 1;
                for (choice.options) |option| size = @max(size, option.value.len + 1);
                break :blk size;
            },
        };
        if (out.len < capacity) return null; // Never return a silently truncated value.
        const get = api.get_setting orelse return null;
        const key_z = comptime key ++ "\x00";
        const length = get(plugin_name, key_z, out.ptr, @intCast(capacity));
        if (length < 0 or length >= capacity) return null;
        return out[0..@intCast(length)];
    }

    pub fn boolean(comptime self: Spec, api: anytype, plugin_name: [*:0]const u8, comptime key: []const u8) ?bool {
        comptime switch (self.find(key)) {
            .toggle, .checkbox => {},
            else => @compileError("Settings DSL boolean() requires a toggle or checkbox: " ++ key),
        };
        var buffer: [6]u8 = undefined;
        const value = self.read(api, plugin_name, key, &buffer) orelse return null;
        if (std.mem.eql(u8, value, "true")) return true;
        if (std.mem.eql(u8, value, "false")) return false;
        return null;
    }

    pub fn integer(comptime self: Spec, api: anytype, plugin_name: [*:0]const u8, comptime key: []const u8) ?i32 {
        const slider = comptime switch (self.find(key)) {
            .slider => |value| value,
            else => @compileError("Settings DSL integer() requires a slider: " ++ key),
        };
        var buffer: [12]u8 = undefined;
        const value = std.fmt.parseInt(i32, self.read(api, plugin_name, key, &buffer) orelse return null, 10) catch return null;
        if (value < slider.min or value > slider.max or @mod(@as(i64, value) - slider.min, slider.step) != 0) return null;
        return value;
    }

    fn find(comptime self: Spec, comptime key: []const u8) Row {
        inline for (self.sections) |section| inline for (section.rows) |row| {
            const field = switch (row) {
                inline else => |value| value,
            };
            if (comptime std.mem.eql(u8, field.key, key)) return row;
        };
        @compileError("Unknown settings DSL key: " ++ key);
    }
};

pub const ValidationError = enum {
    invalid_section,
    invalid_key,
    duplicate_key,
    too_many_fields,
    invalid_label,
    invalid_text,
    invalid_legacy_file,
    invalid_options,
    duplicate_option,
    invalid_default,
    invalid_range,
};

fn identifierChar(char: u8) bool {
    return std.ascii.isAlphanumeric(char) or char == '_' or char == '-';
}
fn identifier(text: []const u8) bool {
    if (text.len == 0 or text.len > 64) return false;
    for (text) |char| if (!identifierChar(char)) return false;
    return true;
}
fn validText(text: []const u8, max_units: usize, nonblank: bool) bool {
    const view = std.unicode.Utf8View.init(text) catch return false;
    var iterator = view.iterator();
    var visible = !nonblank;
    var units: usize = 0;
    while (iterator.nextCodepoint()) |codepoint| {
        units += if (codepoint > 0xffff) @as(usize, 2) else 1;
        const whitespace = switch (codepoint) {
            9...13, 0x1c...0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000 => true,
            else => false,
        };
        if (!whitespace) visible = true;
    }
    return units <= max_units and visible;
}
fn quoted(comptime text: []const u8) []const u8 {
    comptime var result: []const u8 = "\"";
    inline for (text) |char| {
        result = result ++ switch (char) {
            '"' => "\\\"",
            '\\' => "\\\\",
            0...8, 11, 14...31 => std.fmt.comptimePrint("\\u00{x:0>2}", .{char}),
            '\t' => "\\t",
            '\n' => "\\n",
            '\r' => "\\r",
            12 => "\\f",
            else => &[_]u8{char},
        };
    }
    return result ++ "\"";
}
fn property(comptime key: []const u8, comptime value: []const u8) []const u8 {
    return "," ++ quoted(key) ++ ":" ++ quoted(value);
}
fn booleanString(comptime value: bool) []const u8 {
    return if (value) "true" else "false";
}
fn number(comptime value: anytype) []const u8 {
    return std.fmt.comptimePrint("{d}", .{value});
}
fn encode(comptime spec: Spec) []const u8 {
    comptime var result: []const u8 = "[";
    comptime var first = true;
    inline for (spec.sections) |section| inline for (section.rows) |row| {
        const field = switch (row) {
            inline else => |value| value,
        };
        if (!first) result = result ++ ",";
        first = false;
        const kind = switch (row) {
            .toggle => "switch",
            inline else => @tagName(row),
        };
        result = result ++ "{\"key\":" ++ quoted(field.key) ++ property("title", field.title) ++ property("type", kind) ++ property("description", field.description);
        if (section.header.len > 0) result = result ++ property("section", section.header);
        if (section.footer.len > 0) result = result ++ property("sectionFooter", section.footer);
        switch (row) {
            .toggle, .checkbox => |toggle| result = result ++ property("default", booleanString(toggle.default)) ++ property("icon", if (toggle.icon) |icon| @tagName(icon) else ""),
            .text => |text| {
                result = result ++ property("default", text.default) ++ property("multiline", booleanString(text.multiline)) ++ property("maxBytes", number(text.max_bytes));
                if (text.legacy_file) |filename| result = result ++ property("legacyFile", filename);
            },
            .slider => |slider| result = result ++ property("default", number(slider.default orelse slider.min)) ++ property("min", number(slider.min)) ++ property("max", number(slider.max)) ++ property("step", number(slider.step)),
            .select, .radio => |choice| {
                result = result ++ property("default", choice.default orelse choice.options[0].value) ++ ",\"options\":[";
                inline for (choice.options, 0..) |option, index| {
                    if (index != 0) result = result ++ ",";
                    result = result ++ "{\"value\":" ++ quoted(option.value) ++ property("label", option.label) ++ property("description", option.description) ++ "}";
                }
                result = result ++ "]";
            },
        }
        result = result ++ "}";
    };
    return result ++ "]";
}

test "schema escapes real text and preserves typed defaults and presentation" {
    const spec = Spec{ .sections = &.{.{ .header = "Секция", .footer = "Подсказка", .rows = &.{
        .{ .toggle = .{ .key = "enabled", .title = "Включить", .default = true, .icon = .Groups } },
        .{ .text = .{ .key = "caption", .title = "Текст", .default = "Строка\n\"кавычки\"\\путь\t🦔" } },
        .{ .slider = .{ .key = "offset", .title = "Смещение", .min = -20, .max = 20, .step = 2 } },
    } }} };
    const json = spec.json();
    try std.testing.expect(std.mem.indexOf(u8, json, "Строка\\n\\\"кавычки\\\"\\\\путь\\t🦔") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"default\":\"true\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"min\":\"-20\"") != null);
    try std.testing.expectEqual(@as(u8, 0), json[json.len]);
}

test "invalid schemas are rejected before serialization" {
    try std.testing.expectEqual(ValidationError.duplicate_key, (Spec{ .sections = &.{.{ .rows = &.{
        .{ .toggle = .{ .key = "x", .title = "X" } }, .{ .text = .{ .key = "x", .title = "X" } },
    } }} }).validate().?);
    try std.testing.expectEqual(ValidationError.invalid_range, (Spec{ .sections = &.{.{ .rows = &.{
        .{ .slider = .{ .key = "x", .title = "X", .step = 0 } },
    } }} }).validate().?);
    try std.testing.expectEqual(ValidationError.invalid_default, (Spec{ .sections = &.{.{ .rows = &.{
        .{ .radio = .{ .key = "x", .title = "X", .options = &.{.{ .value = "a", .label = "A" }}, .default = "missing" } },
    } }} }).validate().?);
    try std.testing.expectEqual(ValidationError.invalid_legacy_file, (Spec{ .sections = &.{.{ .rows = &.{
        .{ .text = .{ .key = "x", .title = "X", .legacy_file = "../secret" } },
    } }} }).validate().?);
    try std.testing.expectEqual(ValidationError.invalid_range, (Spec{ .sections = &.{.{ .rows = &.{
        .{ .slider = .{ .key = "x", .title = "X", .min = -2147483648, .max = 2147483647 } },
    } }} }).validate().?);
}

test "typed reads fetch live host values and reject truncation and wrong values" {
    const Host = struct {
        var value: [:0]const u8 = "true";
        fn get(_: [*:0]const u8, _: [*:0]const u8, out: [*]u8, capacity: u32) callconv(.c) i32 {
            if (value.len >= capacity) return -1;
            @memcpy(out[0..value.len], value);
            out[value.len] = 0;
            return @intCast(value.len);
        }
    };
    const Api = struct { get_setting: ?*const fn ([*:0]const u8, [*:0]const u8, [*]u8, u32) callconv(.c) i32 };
    const api = Api{ .get_setting = Host.get };
    const spec = Spec{ .sections = &.{.{ .rows = &.{
        .{ .checkbox = .{ .key = "enabled", .title = "Enabled" } },
        .{ .slider = .{ .key = "offset", .title = "Offset", .min = -20, .max = 20, .step = 2 } },
        .{ .text = .{ .key = "caption", .title = "Caption", .max_bytes = 16 } },
    } }} };
    Host.value = "true";
    try std.testing.expectEqual(true, spec.boolean(api, "demo", "enabled").?);
    Host.value = "false";
    try std.testing.expectEqual(false, spec.boolean(api, "demo", "enabled").?);
    Host.value = "yes";
    try std.testing.expectEqual(null, spec.boolean(api, "demo", "enabled"));
    Host.value = "-14";
    try std.testing.expectEqual(@as(i32, -14), spec.integer(api, "demo", "offset").?);
    Host.value = "-13";
    try std.testing.expectEqual(null, spec.integer(api, "demo", "offset"));
    var too_small: [16]u8 = undefined;
    try std.testing.expectEqual(null, spec.read(api, "demo", "caption", &too_small));
    Host.value = "Новый";
    var buffer: [17]u8 = undefined;
    try std.testing.expectEqualStrings(Host.value, spec.read(api, "demo", "caption", &buffer).?);
    try std.testing.expectEqual(null, spec.boolean(Api{ .get_setting = null }, "demo", "enabled"));
}

test "limits match host UTF-16 labels, option identity and field defaults" {
    try std.testing.expectEqual(ValidationError.invalid_key, (Spec{ .sections = &.{.{ .rows = &.{
        .{ .toggle = .{ .key = "../escape", .title = "X" } },
    } }} }).validate().?);
    try std.testing.expectEqual(ValidationError.invalid_label, (Spec{ .sections = &.{.{ .rows = &.{
        .{ .toggle = .{ .key = "x", .title = "\u{a0}" } },
    } }} }).validate().?);
    try std.testing.expectEqual(ValidationError.duplicate_option, (Spec{ .sections = &.{.{ .rows = &.{
        .{ .radio = .{ .key = "x", .title = "X", .options = &.{ .{ .value = "a", .label = "A" }, .{ .value = "a", .label = "Again" } } } },
    } }} }).validate().?);
    try std.testing.expectEqual(ValidationError.invalid_text, (Spec{ .sections = &.{.{ .rows = &.{
        .{ .text = .{ .key = "x", .title = "X", .max_bytes = 2, .default = "ёж" } },
    } }} }).validate().?);
    const title = comptime blk: {
        var result: []const u8 = "";
        for (0..120) |_| result = result ++ "я";
        break :blk result;
    };
    const unicode = Spec{ .sections = &.{.{ .rows = &.{.{ .text = .{ .key = "x", .title = title } }} }} };
    try std.testing.expectEqual(null, unicode.validate());
    try std.testing.expectEqualStrings("[]", (Spec{ .sections = &.{} }).json());
}
