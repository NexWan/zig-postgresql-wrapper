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
const conn = try psql.init(connInfo);
// This will return you a psql struct, you will use this for the rest of the functions
// After using the connection, make sure to close it
psql.close(conn);
```
- Query execution:  
With this wrapper you can create any query you want.
There are specific functions for insert, select and inner join queries, but if you need more complex queries, you can use the `psql.query` function.
```Zig
const conn = try psql.init(connInfo);
const query = "SELECT * FROM users";
_ = try psql.execQuery(conn, query);
```
At the moment, this function will not return any result, it will just print whether the execution was successful or not.

- Insert:  
```zig
const conn = try psql.init(connInfo);
const table = "tests";
// This will return an error for duplicate key value
const values = "2, '4'";
_ = try psql.insert(conn, table, values);
```
This function like the `psql.execQuery` will return whether the insertion was successful or not.

- Select:  
You can use the `psql.select` function to select data from a table. It will return a list of rows and columns.
```zig
const conn = try psql.init(connInfo);
const table = "users";
var result = try psql.select(conn, table);
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
psql.close(conn);
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
    var res = try psql.selectJoin(conn, mainTable, joinTable, joinValue, columns);
    defer res.deinit();
    psql.printQueryResult(res);
    psql.close(conn);
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

const conn = try psql.init(connInfo);
try psql.createTableFor(UserTestAuto, conn);
psql.close(conn);
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