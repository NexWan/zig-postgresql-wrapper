//! Main implementation of the pqlib interface

const std = @import("std");
const psqlC = @cImport(@cInclude("libpq-fe.h"));
const allocator = std.heap.page_allocator;

    pub const Errors = error{
        ConnectionFailed,
        QueryFailed,
        InsertionFailed,
        PrimaryKeyDuplicate,
        SelectJoinFailed,
        NotAStruct
    };

    pub const connectionType = enum {
        OK,
        ERROR,
        DISCONNECTED,
        CLOSED
    };

    pub const queryStatus = enum {
        OK,
        FAILED
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
        connectionStatus: connectionType,
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
            .connectionStatus = connectionType.OK
        };
    }

    /// Global function to execute any query on Postgres
    pub fn execQuery(self:psql, query:[*c]const u8) !void {
        const result = psqlC.PQexec(self.connection, query);
        if (psqlC.PQresultStatus(result) != psqlC.PGRES_TUPLES_OK and psqlC.PQresultStatus(result) != psqlC.PGRES_COMMAND_OK) {
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

        return getResult(result);
    }

    const QueryParams = struct {
        paramString: []u8,

        pub fn deinit(self: *QueryParams) void {
            allocator.free(self.paramString);
        }
    };

    /// Function to create a QueryParams object from a tuple of values
    /// This function makes sure that the values are properly formatted and escaped for use in a PostgreSQL query.
    /// Use this function when there is user input involved.
    /// Make sure to deinitialize the QueryParams object after use.
    pub fn QParams(values: anytype) !QueryParams {
        var paramString = std.ArrayList([]const u8).init(allocator);
        defer paramString.deinit();
        var first = true;
        inline for (values) |value| {
            switch (@TypeOf(value)) {
                //Known time int
                i32 => {
                    if (!first) try paramString.append(", ");
                    try paramString.append(std.fmt.allocPrint(allocator, "{d}", .{value}) catch unreachable);
                    first = false;
                    continue;
                },
                //Known time float
                f32 => {
                    if (!first) try paramString.append(", ");
                    try paramString.append(std.fmt.allocPrint(allocator, "{d}", .{value}) catch unreachable);
                    first = false;
                    continue;
                },
                //Known time string
                []const u8 => {
                    if (!first) try paramString.append(", ");
                    try paramString.append(std.fmt.allocPrint(allocator, "\'{s}\'", .{value}) catch unreachable);
                    first = false;
                    continue;
                },
                //If it's an unknown type, it will get checked for string, integer, or float
                else => {
                    const info = @typeInfo(@TypeOf(value));
                    //Check for strings
                    if (info == .pointer and @typeInfo(info.pointer.child) == .array){
                        const array_info = @typeInfo(info.pointer.child).array;
                        const maybe_sentinel = array_info.sentinel();
                        std.debug.print("{any}", .{maybe_sentinel});
                        if(array_info.child == u8 and maybe_sentinel != null){
                            if (!first) try paramString.append(", ");
                            try paramString.append(std.fmt.allocPrint(allocator, "\'{s}\'", .{value}) catch unreachable);
                        }
                    }else {
                        //Check for integer or float
                         switch(info){
                            .comptime_int => {
                                if (!first) try paramString.append(", ");
                                try paramString.append(std.fmt.allocPrint(allocator, "{d}", .{value}) catch unreachable);
                            },
                            .comptime_float => {
                                if (!first) try paramString.append(", ");
                                try paramString.append(std.fmt.allocPrint(allocator, "{d}", .{value}) catch unreachable);
                            },
                            else => std.debug.print("Unsupported type: {any}\n", .{@typeName(@TypeOf(value))})
                        }
                    }
                }
            }
        }
        return QueryParams{.paramString = try std.mem.join(allocator, "", paramString.items)};
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
    pub fn selectJoin(self: psql, mainTable:[]const u8, joinTable:[]const u8, joinValue:[]const u8, columns:?[]const u8) !queryResult {
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
        return getResult(result);
    }

    /// Function to print the result of a query, this can be used for debugging purposes.
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

    /// function to print the result coming from a queryResult struct.
    pub fn printQueryResult(result: queryResult) void {
        for (result.rows.items) |row| {
            std.debug.print("{s}\n", .{row});
        }

        for (result.columns.items) |column| {
            std.debug.print("{s}\n", .{column});
        }
    }

    /// Function to retrieve the result of a query as a queryResult struct.
    /// This is a helper function that retrieves the result of a query as a queryResult struct.
    pub fn getResult(result: ?*psqlC.PGresult) !queryResult {
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

        return queryResult{
            .columns = columns,
            .rows = rows,
        };
    }

    /// Close the connection to the PostgreSQL database.
    pub fn close(self: psql) void {
        psqlC.PQfinish(self.connection);
    }

    pub fn mapTypeToSQL(comptime T: type) []const u8 {
        const ti = @typeInfo(T);
        return switch(ti) {
            .int => "INTEGER",
            .float => "NUMERIC(255)",
            else => "VARCHAR(255)",
        };
    }

    fn stripModuleName(typeName: []const u8) []const u8 {
        var i: isize = @intCast(typeName.len-1);
        while (i >= 0) {
            if (typeName[@intCast(i)] == '.') {
                return typeName[@intCast(i + 1)..];
            }
            i -= 1;
        }
        return typeName;
    }

    /// Function to create tables based on a struct, by default the length of the properties is 255, I'm working on
    /// adding more types and variable sizes
    pub fn createTableFor(comptime T: type, db: psql) !void {
        // Ensure T is a struct.
        const ti = @typeInfo(T);
        switch (ti) {
            .@"struct" => {},
            else => return Errors.NotAStruct,
        }
        // Create a list of string parts.
        var parts = std.ArrayList([]const u8).init(allocator);
        defer parts.deinit();

        try parts.append("CREATE TABLE IF NOT EXISTS ");
        try parts.append(stripModuleName(@typeName(T)));
        try parts.append(" (");

        var first = true;
        inline for (ti.@"struct".fields) |field| {
            if (!first) {
                try parts.append(", ");
            } else {
                first = false;
            }
            // Append field name and its corresponding SQL type.
            try parts.append(field.name);
            try parts.append(" ");
            try parts.append(mapTypeToSQL(field.type));
        }
        try parts.append(");");

        // Join all parts into one query string.
        const query = try std.mem.join(allocator, "", parts.items);
        std.debug.print("Creating table with query: {s}\n", .{query});
        try execQuery(db, query.ptr);
        allocator.free(query);
    }
