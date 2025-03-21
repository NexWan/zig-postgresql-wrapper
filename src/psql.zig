// This file is meant to be used as the main entry point for the project
// All functions and types are defined here

const std = @import("std");
const psqlC = @cImport(@cInclude("libpq-fe.h"));
const allocator = std.heap.page_allocator;

const Errors = error{
    ConnectionFailed,
    QueryFailed,
};

    
    pub const connectionParams = struct {
        host: []const u8,
        port: u16,
        user: []const u8,
        password: []const u8,
        database: []const u8,
    };
    
    const psql = struct {
        connectionString: connectionParams,
        connection: ?*psqlC.PGconn,
    };
    
    // Function that initializes and returns a new psql connection
    pub fn init( connectionString: connectionParams) !psql {
        var conn: ?*psqlC.PGconn = null;
        const port_str = try std.fmt.allocPrint(allocator, "{d}", .{connectionString.port});
        defer allocator.free(port_str);
        const parts = [_][]const u8{
            "dbname=", connectionString.database,
            " user=", connectionString.user,
            " password=", connectionString.password,
            " host=", connectionString.host,
            " port=", port_str,
        };
    
        const connection = try std.mem.join(allocator, "", parts[0..]);
        conn = psqlC.PQconnectdb(connection.ptr);
        if (psqlC.PQstatus(conn) != psqlC.CONNECTION_OK) {
            std.debug.print("Connection to database failed: {s}\n", .{psqlC.PQerrorMessage(conn)});
            psqlC.PQfinish(conn);
            return error.ConnectionFailed;
        }
        std.debug.print("Connection initialized successfully\n", .{});
        return psql{
            .connectionString = connectionString,
            .connection = conn,
        };
    }
    
    pub fn execQuery(self:psql, query:[*c]const u8) !void {
        const result = psqlC.PQexec(self.connection, query);
        if (psqlC.PQresultStatus(result) != psqlC.PGRES_TUPLES_OK) {
            std.debug.print("Query execution failed: {s}\n", .{psqlC.PQerrorMessage(self.connection)});
            psqlC.PQclear(result);
            return Errors.QueryFailed;
        }
        std.debug.print("Query executed successfully\n", .{});
        psqlC.PQclear(result);
    }
    
    pub fn close(self:psql) void {
        psqlC.PQfinish(self.connection);
        std.debug.print("Connection closed successfully\n {any}", .{psqlC.PQstatus(self.connection)});
    }
