/// Testing file
const psqlMethods = @import("psql.zig");
const psql = @import("psql.zig").psql;
const std = @import("std");

const connInfo = psql.connectionParams {
    .user = "postgres",
    .password = "***REMOVED***",
    .host = "localhost",
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
    std.debug.print("{s}\n", .{params.paramString});
    defer params.deinit();
}

test "Unknown type paramters" {
    const id = 1;
    const name = "John";
    const money = 100.2;
    var params = try psql.QParams(.{id, name, money});
    std.debug.print("{s}\n", .{params.paramString});
    defer params.deinit();
}

test "Sql Injection" {
    const name = "'; DROP TABLE users; --";
    var params = try psql.QParams(.{name});
    std.debug.print("{s}\n", .{params.paramString});
    defer params.deinit();
}

test "Try Connection" {
    std.debug.print("Try Connection\n", .{});
    var conn = try psql.init(connInfo);
    try std.testing.expect(conn.connectionStatus == psql.connectionType.OK);
    conn.close();
}

test "Try Query" {
    std.debug.print("Try Query\n", .{});
    var conn = try psql.init(connInfo);
    const query = "SELECT * FROM users";
    _ = try conn.execQuery(query);
    conn.close();
}

test "Try select" {
    var conn = try psql.init(connInfo);
    const table = "users";
    var result = try conn.select(table);
    for (result.rows.items) |row| {
        std.debug.print("{s}\n", .{row});
    }
    
    for (result.columns.items) |column| {
        std.debug.print("{s}\n", .{column});
    }
    
    defer result.deinit();
    
    // Assuming I want to get the first row and the first column
    std.debug.print("{s}\n", .{result.rows.items[0][0]});
    conn.close();
}

test "Try insert" {
    var conn = try psql.init(connInfo);
    const table = "tests";
    // This will return an error for duplicate key value
    const id:i32 = 2;
    const name = "John Doe";
    var params = try psql.QParams(.{id,name});
    defer params.deinit();
    try std.testing.expectError(psql.Errors.PrimaryKeyDuplicate, conn.insert(table, params.paramString));
    conn.close();
}

test "Try inner join" {
    var conn = try psql.init(connInfo);
    const mainTable = "userstest";
    const joinTable = "posts";
    const joinValue = "id";
    const columns = "userstest.id, userstest.name, posts.post";
    var res = try conn.selectJoin(mainTable, joinTable, joinValue, columns);
    defer res.deinit();
    conn.printQueryResult(res);
    conn.close();
}

test "Try creation of table" {
    var conn = try psql.init(connInfo);
    try conn.createTableFor(UserTestAuto);
    conn.close();
}