//! Main implementation of the pqlib interface

const std = @import("std");
const psqlC = @cImport(@cInclude("libpq-fe.h"));
const allocator = std.heap.page_allocator;

    const Errors = error{
        ConnectionFailed,
        QueryFailed,
        InsertionFailed,
        PrimaryKeyDuplicate, 
        SelectJoinFailed
    };
    
    /// Struct that holds the result of a PostgreSQL query.
    /// It is pretty important to free the memory allocated once the queryResult is no longer needed.
    const queryResult = struct {
        rows: std.ArrayList([][]const u8),
        columns: std.ArrayList([]const u8),
        
        /// Deinitializes the queryResult struct.
        /// It is important to free the memory allocated for the columns and rows.
        /// Otherwise, memory leaks may occur.
        pub fn deinit (self: *queryResult) void {
            for(self.columns.items) |column| {
                allocator.free(column);
            }
            self.columns.deinit();
            for(self.rows.items) |row| {
                for(row) |cell| {
                    allocator.free(cell);
                }
            }
            self.rows.deinit();
        }
    };

    /// Struct that holds the connection parameters for a PostgreSQL database.
    pub const connectionParams = struct {
        host: []const u8,
        port: u16,
        user: []const u8,
        password: []const u8,
        database: []const u8,
    };

    /// Struct that holds the connection information for a PostgreSQL database.
    const psql = struct {
        /// String containing the connection parameters for a PostgreSQL database.
        connectionString: connectionParams,
        /// Pointer to the PostgreSQL connection instance. You shall send this pointer to the PostgreSQL functions.
        connection: ?*psqlC.PGconn,
    };

    /// Function that initializes and returns a new psql connection.
    /// Receives a connectionParams struct and returns a psql struct.
    /// psql struct contains the connectionParams and the connection instance
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
        allocator.free(connection);
        return psql{
            .connectionString = connectionString,
            .connection = conn,
        };
    }

    /// Global function to execute any query on Postgres
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

    /// Global function to execute a SELECT query on Postgres, it will return a list of rows
    pub fn select(self:psql, table:[*c]const u8) !queryResult {
        const query = try std.fmt.allocPrint(allocator, "SELECT * FROM {s}", .{table});
        const c_query = query.ptr;
        defer allocator.free(query);
        const result = psqlC.PQexec(self.connection, c_query);
        if(psqlC.PQresultStatus(result) != psqlC.PGRES_TUPLES_OK) {
            std.debug.print("Query execution failed: {s}\n", .{psqlC.PQerrorMessage(self.connection)});
            psqlC.PQclear(result);
            return Errors.QueryFailed;
        }
        std.debug.print("Query executed successfully\n", .{});
        const nFields = psqlC.PQnfields(result);
        const nRows = psqlC.PQntuples(result);
        var rows = std.ArrayList([][]const u8).init(allocator);
        var columns = std.ArrayList([]const u8).init(allocator);
        
        for (0..@intCast(nFields)) |i| {
            const name = psqlC.PQfname(result, @intCast(i));
            columns.append(try std.fmt.allocPrint(allocator, "{s}", .{name})) catch unreachable;
        }
        for (0..@intCast(nRows)) |i| {
            var row = std.ArrayList([]const u8).init(allocator);
            for (0..@intCast(nFields)) |j| {
                const value = psqlC.PQgetvalue(result, @intCast(i), @intCast(j));
                const valStr = try std.fmt.allocPrint(allocator, "{s}", .{value});
                row.append(valStr) catch unreachable;
            }
            rows.append(row.items) catch unreachable;
        }
        psqlC.PQclear(result);
        return queryResult{.columns = columns, .rows = rows};
    }
    
    /// Inserts a new row into the specified table.
    /// The values should be formatted as the following: "\'{value}\'"
    pub fn insert(self:psql, table:[] const u8, values: []const u8) !void {
        const query = try std.fmt.allocPrint(allocator, "INSERT INTO {s} VALUES ({s})", .{table, values});
        const result = psqlC.PQexec(self.connection, query.ptr);
        allocator.free(query);
        if(psqlC.PQresultStatus(result) != psqlC.PGRES_COMMAND_OK) {
            const errorCode = try std.fmt.allocPrint(allocator, "{s}", .{psqlC.PQresultErrorField(result, psqlC.PG_DIAG_SQLSTATE)});
            defer allocator.free(errorCode);
            std.debug.print("Insertion failed: {s}\n", .{psqlC.PQerrorMessage(self.connection)});
            if (std.mem.eql(u8, errorCode, "23505")) {
                std.debug.print("Duplicate key error\n", .{});
                return Errors.PrimaryKeyDuplicate;
            }
            psqlC.PQclear(result);
            return Errors.InsertionFailed;
        }
        std.debug.print("Insertion executed successfully\n", .{});
        psqlC.PQclear(result);
    }
    
    /// Selects data from multiple tables using a INNER JOIN query.
    /// Columns is an optional string of column names to select. If null, all columns are selected.
    /// Columns format: "column1, column2, column3"
    /// Join value is the value you want to use to join the tables. {example: mainTable.{joinValue} = joinTable.{joinValue}}
    pub fn selectJoin(self: psql, mainTable:[]const u8, joinTable:[]const u8, joinValue:[]const u8, columns:?[]const u8) !void {
        const query = try std.fmt.allocPrint(allocator, 
            "SELECT {s} FROM {s} INNER JOIN {s} ON {s}.{s} = {s}.{s}", 
            .{columns orelse "*", mainTable, joinTable, mainTable, joinValue, joinTable, joinValue}
        );
        const query_c = query.ptr;
        const result = psqlC.PQexec(self.connection, query_c);
        allocator.free(query);
        if(psqlC.PQresultStatus(result) != psqlC.PGRES_TUPLES_OK) {
            std.debug.print("SelectJoin failed: {s}\n", .{psqlC.PQerrorMessage(self.connection)});
            psqlC.PQclear(result);
            return Errors.SelectJoinFailed;
        }
        std.debug.print("SelectJoin executed successfully\n", .{});
        printResult(result);
        psqlC.PQclear(result);
    }
    
    pub fn printResult(result: ?*psqlC.struct_pg_result) void {
        const rows = psqlC.PQntuples(result);
        const columns = psqlC.PQnfields(result);
        
        std.debug.print("Result set:\n", .{});
        for (0..@intCast(rows)) |row| {
            for (0..@intCast(columns)) |column| {
                const value = psqlC.PQgetvalue(result, @intCast(row), @intCast(column));
                std.debug.print("{s} ", .{value});
            }
            std.debug.print("\n", .{});
        }
    }
    
    /// Close the connection to the PostgreSQL database.
    pub fn close(self: psql) void {
        psqlC.PQfinish(self.connection);
    }
