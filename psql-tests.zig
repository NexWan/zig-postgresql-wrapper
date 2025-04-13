/// Testing file
const psql = @import("psql.zig");
const std = @import("std");

const connInfo = psql.connectionParams {
    .user = "",
    .password = "",
    .host = "",
    .port = 5432,
    .database = "test",
};

// Struct model to create the creation of a table based on this struct
const UserTestAuto = struct {
    id: i32,
    name: []const u8,
    age: i32,
};

test "Parameters" {
    std.debug.print("Parameters\n", .{});
    const id:i32 = 1;
    const name:[]const u8 = "John";
    const age:i32 = 30;
    var params = try psql.QParams(.{id, name, age});
    std.debug.print("{s}", .{params.paramString});
    defer params.deinit();
}

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
    const id:i32 = 2;
    const name = "John Doe";
    var params = try psql.QParams(.{id,name});
    defer params.deinit();
    try std.testing.expectError(psql.Errors.PrimaryKeyDuplicate, psql.insert(conn, table, params.paramString));
    psql.close(conn);
}

test "Try inner join" {
    const conn = try psql.init(connInfo);
    const mainTable = "userstest";
    const joinTable = "posts";
    const joinValue = "id";
    const columns = "userstest.id, userstest.name, posts.post";
    var res = try psql.selectJoin(conn, mainTable, joinTable, joinValue, columns);
    defer res.deinit();
    psql.printQueryResult(res);
    psql.close(conn);
}

test "Try creation of table" {
    const conn = try psql.init(connInfo);
    try psql.createTableFor(UserTestAuto, conn);
    psql.close(conn);
}