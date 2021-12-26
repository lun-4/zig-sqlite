const std = @import("std");
const sqlite = @import("sqlite");

pub export fn main() callconv(.C) void {
    zigMain() catch unreachable;
}

pub fn zigMain() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == false);
    const allocator = gpa.allocator();

    // Read the data from stdin
    const stdin = std.io.getStdIn();
    const data = try stdin.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    var db = try sqlite.Db.init(.{
        .mode = .Memory,
        .open_flags = .{
            .write = true,
            .create = true,
        },
    });
    defer db.deinit();

    try db.exec("CREATE TABLE test(id integer primary key, name text, data blob)", .{}, .{});

    // Use it as a full query first

    db.execDynamic(data, .{}, .{}) catch |err| switch (err) {
        error.SQLiteError => return,
        error.ExecReturnedData => return,
        else => return err,
    };

    // Use it as a bind parameter in an insert

    var name = sqlite.Text{ .data = "Fuzzing" };
    var data_blob = sqlite.Blob{ .data = data };

    db.execDynamic(
        "INSERT INTO test(name, data) VALUES($name, $date)",
        .{},
        .{
            .name = name,
            .data = data_blob,
        },
    ) catch |err| switch (err) {
        error.SQLiteError => return,
        else => return err,
    };

    // Then read it back

    const read_data = db.oneDynamicAlloc(
        []const u8,
        allocator,
        "SELECT data FROM test WHERE name = $name",
        .{},
        .{
            .name = name,
        },
    ) catch |err| switch (err) {
        error.SQLiteError => return,
        else => return err,
    };

    if (read_data) |rd| {
        defer allocator.free(rd);

        if (!std.mem.eql(u8, data, rd)) {
            return error.DataReadNotEqual;
        }
    } else {
        return error.NoDataRead;
    }
}
