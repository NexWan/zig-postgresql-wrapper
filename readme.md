# Zig PostgreSQL Wrapper
This is a pretty basic wrapper for PostgreSQL in Zig.
It utilizes the libpq library written in C. it provides a simple interface for interacting with PostgreSQL databases.

## NOTE
This project contains the whole PQlib so you can just clone the repo and build it, you don't need to install it separately.

I haven't used it with docker yet, it works well with local installation of PostgreSQL.

## Features (so far)
- Connection management
- Query execution
- Result handling
- Error handling
- Insert, select and inner join queries
- Parameterized queries

## Example of use 
- Initialization
```zig
const psql = @import("psql");
// Create a connection info struct
const connInfo = psql.connectionParams {
    .user = "",
    .password = "",
    .host = "",
    .port = 0,
    .database = "",
};
// This will return you a psql struct, it will create a pointer to the connection struct, that way it can be used for all the other functions without needing it to be passed around, just reference to the variable you have created.
var conn = try psql.init(connInfo);
// Remember to close the connection when you're done using it.
conn.close();
```
- Query execution:  
With this wrapper you can create any query you want.
There are specific functions for insert, select and inner join queries, but if you need more complex queries, you can use the `psql.query` function.
```Zig
var conn = try psql.init(connInfo);
const query = "SELECT * FROM users";
_ = try conn.execQuery(query);
conn.close();
```
At the moment, this function will not return any result, it will just print whether the execution was successful or not.

- Insert:  
```zig
var conn = try psql.init(connInfo);
const table = "tests";
// This will return an error for duplicate key value
const values = "2, '4'";
_ = try conn.insert(table, values);
conn.close();
```
This function like the `psql.execQuery` will return whether the insertion was successful or not.

- Select:  
You can use the `psql.select` function to select data from a table. It will return a list of rows and columns.
```zig
var conn = try psql.init(connInfo);
const table = "users";
var result = try conn.select(table);
```
To access the data, you can iterate over the result.
```zig
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
```
You will need to deinitialize the result after you're done with it.

- Select inner join:  
You can use the select inner join function in case you need to join two tables.
```zig
const conn = try psql.init(connInfo);
const mainTable = "userstest";
const joinTable = "posts";
const joinValue = "id";
const columns = "userstest.id, userstest.name, posts.post";
var res = try conn.selectJoin(mainTable, joinTable, joinValue, columns);
defer res.deinit();
psql.printQueryResult(res);
conn.close();
```

- Creation of tables (With structs):  
I wanted to recreate the way some code-first database approach create their tables with structs. This is a pretty raw implementation, but it's a good starting point.
```zig
// Struct model to create the creation of a table based on this struct
const UserTestAuto = struct {
    id: i32,
    name: []const u8,
    age: i32,
};

var conn = try psql.init(connInfo);
try psql.createTableFor(UserTestAuto, conn);
conn.close();
```
This will create a table named `userstest` with columns `id`, `name`, and `age`.
At the moment the table is created without any constraints or indexes. Nor defined any primary key or foreign key constraints. I will be looking into adding those features in the future.

- Parameterized queries:   
If you have noticed, the insert query I used for this example is passed as a string, there is no verification of the query. This is a security risk and should be avoided in production code. Use parameterized queries instead.
```zig
    const id:i32 = 1;
    const name:[]const u8 = "John";
    const age:i32 = 30;
    var params = try psql.QParams(.{id, name, age});
    std.debug.print("{s}", .{params.paramString});
    defer params.deinit();
```
You can specify the data type for each parameter before passing it to the function, this is for helping the compiler to check the types and avoid errors.
This will return a string representation of the parameters.
The past code will return the following string:
`"1,John,30"`   
Otherwise you can send in data types without specifying the data type, it will try to guess the type using Zig built in functions.
```Zig
    const id = 1;
    const name = "John";
    const money = 100.2;
    var params = try psql.QParams(.{id, name, money});
    std.debug.print("{s}\n", .{params.paramString});
    defer params.deinit();
```
   
This will return the following string:
`"1,John,100.2"`   
This also helps to escape SQL Injection attempts!, for example using the following code: 
```zig
const name = "'; DROP TABLE users; --";
var params = try psql.QParams(.{name});
std.debug.print("{s}\n", .{params.paramString});
defer params.deinit();
```

This will return the following string:
`'''; DROP TABLE users; --'`   


# Installation   
Right now this project only works on Mac OS (ARM Versions) since it uses the libpq interfaces compiled on mac.
I'll be working on expanding the libs to support other platforms, but you can always clone the project and just 
modify the "pq" library with your own platform. It should work just fine.

```bash
zig fetch --save https://github.com/NexWan/zig-postgresql-wrapper/archive/refs/tags/v0.0.1-alpha.3.tar.gz
```

This will add to an existing project's dependencies this library.
You can verify this on your project's build.zig.zon file.   
(Make sure to verify the tags to make sure you are using the latest version)

```zig
    .dependencies = .{
        .psql = .{
            .url = "https://github.com/NexWan/zig-postgresql-wrapper/archive/refs/tags/v0.0.1-alpha.3.tar.gz",
            .hash = "psql-0.0.1-NdZkuuM16ADpA6fHiFfMwb6jFjd_lqKd9SM7aA3zLzg9",
        },
    },
```    
Now in your build.zig just add the following code: (Before b.installArtifact(exe))
```zig
const psql = b.dependency("psql", .{
    .target = target,
    .optimize = optimize,
    
});

exe.root_module.addImport("psql", psql.module("psql"));
exe.addIncludePath(psql.path("pq/include"));
exe.addLibraryPath(psql.path("pq/lib"));
exe.linkLibrary(psql.artifact("psql"));
```