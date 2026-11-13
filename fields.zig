//! Reusable typed sections; plugin authors write Zig values, never escaped JSON.
const kit = @import("mandagram").settings;

pub const switches = kit.Section{ .header = "Переключатели", .rows = &.{
    .{ .toggle = .{ .key = "enabled", .title = "Включить эффект", .description = "Пример включённого переключателя", .default = true, .icon = .Visibility } },
    .{ .toggle = .{ .key = "animations", .title = "Анимации", .description = "Пример выключенного переключателя", .icon = .Animation } },
} };
pub const checkboxes = kit.Section{ .header = "Чекбоксы", .rows = &.{
    .{ .checkbox = .{ .key = "confirm", .title = "Подтверждать действие", .description = "Чекбокс с установленной галочкой", .default = true, .icon = .CheckCircle } },
    .{ .checkbox = .{ .key = "remember", .title = "Запомнить выбор", .description = "Нажмите в любом месте строки", .icon = .CheckCircle } },
} };
pub const text = kit.Section{ .header = "Текст", .rows = &.{
    .{ .text = .{ .key = "caption", .title = "Подпись", .description = "Однострочный текст, до 256 байт UTF-8", .default = "Привет, \"MandaGram\"!", .max_bytes = 256 } },
    .{ .text = .{ .key = "notes", .title = "Заметка", .description = "Многострочный текст с переносами строк", .default = "Первая строка\nВторая строка\\путь", .multiline = true, .max_bytes = 2048 } },
} };
pub const select = kit.Section{ .header = "Режим работы", .rows = &.{
    .{ .select = .{ .key = "mode", .title = "Режим работы", .description = "Выпадающий список с отметкой текущего варианта", .default = "auto", .options = &.{
        .{ .value = "auto", .label = "Автоматически" },
        .{ .value = "compact", .label = "Компактный" },
        .{ .value = "full", .label = "Подробный" },
    } } },
} };
pub const radio = kit.Section{ .header = "Расположение", .rows = &.{
    .{ .radio = .{ .key = "placement", .title = "Расположение", .description = "Один вариант из трёх; нажимается вся строка", .default = "right", .options = &.{
        .{ .value = "left", .label = "Слева", .description = "Перед основным содержимым" },
        .{ .value = "center", .label = "По центру", .description = "В центре карточки" },
        .{ .value = "right", .label = "Справа", .description = "После основного содержимого" },
    } } },
} };
pub const sliders = kit.Section{ .rows = &.{
    .{ .slider = .{ .key = "opacity", .title = "Непрозрачность", .description = "От 10 до 100, шаг 5", .min = 10, .max = 100, .step = 5, .default = 80 } },
    .{ .slider = .{ .key = "offset", .title = "Смещение", .description = "Отрицательные и положительные значения, шаг 2", .min = -20, .max = 20, .step = 2, .default = 0 } },
} };
