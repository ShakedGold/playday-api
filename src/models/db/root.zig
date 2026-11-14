const std = @import("std");

const fr = @import("fridge");

pub const Game = @import("game.zig");
pub const GameMetadata = @import("metadata.zig");
pub const LibraryData = @import("library.zig");

const DATABASE_NAME = "playday.db";

pub fn getConnection(allocator: std.mem.Allocator, io: std.Io) !*fr.Session {
    const session = try allocator.create(fr.Session);

    session.* = try fr.Session.open(fr.SQLite3, io, allocator, .{ .filename = DATABASE_NAME });
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

    const table_names = @typeInfo(structType).@"struct".field_names;
    const table_types = @typeInfo(structType).@"struct".field_types;
    inline for (table_names, table_types, 0..) |table_name, table_type, tableIndex| {
        const fieldType = @typeInfo(table_type);

        const field_names = fieldType.@"struct".field_names;
        inline for (field_names, 0..) |field_name, fieldIndex| {
            try sql.writer.print("{s}.{s} AS {s}__{s}", .{ table_name, field_name, table_name, field_name });

            // Printing ',' until the last field
            if (tableIndex + 1 != table_names.len or fieldIndex + 1 != field_names.len) {
                try sql.writer.print(", ", .{});
            }
        }
    }

    // We take the first table in the struct fields as the main table to select from
    try sql.writer.print(" FROM {s}", .{table_names[0]});

    // Print the join statements
    inline for (join_statements) |statement| {
        try sql.writer.print(" JOIN {s} ON {s}", .{ statement[0], statement[1] });
    }

    return sql.toOwnedSlice();
}

fn JoinResultType(comptime structType: type) type {
    const structFieldNames = @typeInfo(structType).@"struct".field_names;
    const structFieldTypes = @typeInfo(structType).@"struct".field_types;

    var field_count: usize = 0;

    inline for (structFieldTypes) |tableType| {
        field_count += @typeInfo(tableType).@"struct".field_names.len;
    }

    var names: [field_count][]const u8 = undefined;
    var types: [field_count]type = undefined;
    var attrs: [field_count]std.builtin.Type.Struct.FieldAttributes = undefined;

    var index: usize = 0;

    inline for (structFieldNames, structFieldTypes) |tableName, tableType| {
        const info = @typeInfo(tableType).@"struct";

        inline for (info.field_names, info.field_types, info.field_attrs) |fieldName, fieldType, fieldAttrs| {
            names[index] = tableName ++ "__" ++ fieldName;
            types[index] = fieldType;

            attrs[index] = .{
                .@"comptime" = false,
                .@"align" = fieldAttrs.@"align",
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
    const info = @typeInfo(ResultType).@"struct";
    inline for (info.field_names, info.field_types) |tableName, tableType| {
        const TableType = tableType;

        inline for (@typeInfo(TableType).@"struct".field_names) |fieldName| {
            const sql_name = comptime tableName ++ "__" ++ fieldName;

            @field(@field(result, tableName), fieldName) =
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
