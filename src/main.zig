const c = @cImport(@cInclude("libpq-fe.h"));

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
    const conninfo = "dbname=dbname user=user password=pwd host=localhost port=5432";
    var conn = c.PQconnectdb(conninfo);
    if (c.PQstatus(conn) != c.CONNECTION_OK) {
        std.debug.print("Connection to database failed: {s}\n", .{c.PQerrorMessage(conn)});
        c.PQfinish(conn);
        return;
    }
    std.debug.print("Connected to database successfully.\n", .{});
    const query = "SELECT * FROM users";
    _ = try exec(conn,query);
    c.PQfinish(conn);
    conn = null;
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("postgre_zig_lib");
