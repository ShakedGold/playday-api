const std = @import("std");

const fr = @import("fridge");

pub const Game = @import("game.zig");
pub const GameMetadata = @import("metadata.zig");
pub const LibraryData = @import("library.zig");

const DATABASE_NAME = "playday.db";

pub fn getConnection(allocator: std.mem.Allocator, io: std.Io) !*fr.Session {
    const session = try allocator.create(fr.Session);

    session.* = try fr.Session.open(fr.SQLite3, allocator, io, .{ .filename = DATABASE_NAME });
    return session;
}

pub fn deinit(session: *fr.Session, allocator: std.mem.Allocator) void {
    session.deinit();

    allocator.destroy(session);
}

/// returns the sql query based on the join_statements, user owns the memory
fn sqlQuery(allocator: std.mem.Allocator, structType: type, join_statements: anytype) ![]u8 {
    var sql: std.Io.Writer.Allocating = .init(allocator);
    defer sql.deinit();

    try sql.writer.print("SELECT ", .{});

    const tables = @typeInfo(structType).@"struct".fields;
    inline for (tables, 0..) |table, tableIndex| {
        const fieldType = @typeInfo(table.type);

        const fields = fieldType.@"struct".fields;
        inline for (fields, 0..) |tableField, fieldIndex| {
            try sql.writer.print("{s}.{s} AS {s}__{s}", .{ table.name, tableField.name, table.name, tableField.name });

            // Printing ',' until the last field
            if (tableIndex + 1 != tables.len or fieldIndex + 1 != fields.len) {
                try sql.writer.print(", ", .{});
            }
        }
    }

    // We take the first table in the struct fields as the main table to select from
    try sql.writer.print(" FROM {s}", .{tables[0].name});

    // Print the join statements
    inline for (join_statements) |statement| {
        try sql.writer.print(" JOIN {s} ON {s}", .{ statement[0], statement[1] });
    }

    return sql.toOwnedSlice();
}

fn JoinResultType(comptime structType: type) type {
    const structFields = @typeInfo(structType).@"struct".fields;

    var field_count: usize = 0;

    inline for (structFields) |table| {
        field_count += @typeInfo(table.type).@"struct".fields.len;
    }

    var names: [field_count][]const u8 = undefined;
    var types: [field_count]type = undefined;
    var attrs: [field_count]std.builtin.Type.StructField.Attributes = undefined;

    var index: usize = 0;

    inline for (structFields) |table| {
        inline for (@typeInfo(table.type).@"struct".fields) |field| {
            names[index] = table.name ++ "__" ++ field.name;
            types[index] = field.type;

            attrs[index] = .{
                .@"comptime" = false,
                .@"align" = field.alignment,
                .default_value_ptr = null,
            };

            index += 1;
        }
    }

    return @Struct(.auto, null, &names, &types, &attrs);
}

fn mapSqlResult(
    comptime ResultType: type,
    result: *ResultType,
    sqlResult: anytype,
) void {
    inline for (@typeInfo(ResultType).@"struct".fields) |table| {
        const TableType = table.type;

        inline for (@typeInfo(TableType).@"struct".fields) |field| {
            const sql_name = comptime table.name ++ "__" ++ field.name;

            @field(@field(result, table.name), field.name) =
                @field(sqlResult, sql_name);
        }
    }
}

/// Returns the sql join result on the type given in `structType` by using `join_statements`. the caller owns the memory
pub fn join(
    connection: *fr.Session,
    allocator: std.mem.Allocator,
    structType: type,
    join_statements: anytype,
) ![]structType {
    const query = try sqlQuery(allocator, structType, join_statements);
    defer allocator.free(query);

    const sqlResults = try connection
        .raw(query, .{})
        .fetchAll(JoinResultType(structType));

    const results = try allocator.alloc(structType, sqlResults.len);

    for (sqlResults, 0..) |sqlResult, index| {
        mapSqlResult(structType, &results[index], sqlResult);
    }

    return results;
}
