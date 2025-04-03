// Main file, used only for testing purposes

const c = @cImport(@cInclude("libpq-fe.h"));
const psql = @import("psql.zig");

const connInfo = psql.connectionParams {
    .user = "user",
    .password = "pwd!",
    .host = "localhost",
    .port = 5432,
    .database = "test",
};

const UserTestAuto = struct {
    id: i32,
    name: []const u8,
    age: i32,
};

pub fn exec(conn:  ?*c.PGconn, query: [*c]const u8) !void {
    const result = c.PQexec(conn, query);
    if (c.PQresultStatus(result) != c.PGRES_TUPLES_OK) {
        std.debug.print("Query failed: {s}\n", .{c.PQerrorMessage(conn)});
        c.PQclear(result);
        c.PQfinish(conn);
        return;
    }

    const nfields = c.PQnfields(result);
    const ntuples = c.PQntuples(result);

    // Print column names
    for (0..@intCast(nfields)) |i| {
        std.debug.print("{s}\t", .{c.PQfname(result, @intCast(i))});
    }
    std.debug.print("\n", .{});

    // Print rows
    for (0..@intCast(ntuples)) |i| {
        for (0..@intCast(nfields)) |j| {
            std.debug.print("{s}\t", .{c.PQgetvalue(result, @intCast(i), @intCast(j))});
        }
        std.debug.print("\n", .{});
    }

    c.PQclear(result);

}

pub fn main() void {
    const allocator = std.heap.page_allocator;
    const env = std.process.getEnvMap(allocator);
    std.debug.print("Environment Variables:\n {any}\n", .{env});
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("postgre_zig_lib");

test "Try Connection" {
    std.debug.print("Try Connection\n", .{});
    const conn = try psql.init(connInfo);
    try std.testing.expect(conn.connectionStatus == psql.connectionType.OK);
    psql.close(conn);
}

test "Try Query" {
    std.debug.print("Try Query\n", .{});
    const conn = try psql.init(connInfo);
    const query = "SELECT * FROM users";
    _ = try psql.execQuery(conn, query);
}

test "Try select" {
    
    const conn = try psql.init(connInfo);
    const table = "users";
    var result = try psql.select(conn, table);
    for (result.rows.items) |row| {
        std.debug.print("{s}\n", .{row});
    }
    
    for (result.columns.items) |column| {
        std.debug.print("{s}\n", .{column});
    }
    
    defer result.deinit();
    
    // Assuming I want to get the first row and the first column
    std.debug.print("{s}\n", .{result.rows.items[0][0]});
    psql.close(conn);
}

test "Try insert" {
    const conn = try psql.init(connInfo);
    const table = "tests";
    // This will return an error for duplicate key value
    const values = "2, '4'";
    try std.testing.expectError(psql.Errors.PrimaryKeyDuplicate, psql.insert(conn, table, values));
    psql.close(conn);
}

test "Try inner join" {
    const conn = try psql.init(connInfo);
    const mainTable = "userstest";
    const joinTable = "posts";
    const joinValue = "id";
    const columns = "userstest.id, userstest.name, posts.post";
    const res = try psql.selectJoin(conn, mainTable, joinTable, joinValue, columns);
    psql.printQueryResult(res);
    psql.close(conn);
}

test "Try creation of table" {
    const conn = try psql.init(connInfo);
    try psql.createTableFor(UserTestAuto, conn);
    psql.close(conn);
}