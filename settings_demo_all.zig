const demo = @import("demo.zig");
const fields = @import("fields.zig");

comptime {
    demo.exportPlugin(.{
        .id = "settings_demo_all",
        .name = "Тест: все настройки",
        .description = "Все шесть типов полей: переключатели, галочки, текст, список, радиокнопки и ползунки. Zig DSL.",
        .spec = .{ .sections = &.{ fields.switches, fields.checkboxes, fields.text, fields.select, fields.radio, fields.sliders } },
    });
}
