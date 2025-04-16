const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Define the common build options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const psql_dep = b.addModule("psql", .{
        .root_source_file = b.path("psql.zig"),
    });
    
    psql_dep.addIncludePath(b.path("pq/include/"));
    // Add the directory for the library files.
    psql_dep.addLibraryPath(b.path("pq/lib/"));

    // Create a static library target for the package.
    // This will compile your psql.zig into a static library.
    const lib = b.addStaticLibrary(.{
        .name = "psql", 
        .root_source_file = b.path("psql.zig"), 
        .target = target,
        .optimize = optimize,
    });

    // Link the PostgreSQL C libraries.
    // Add the directory for header files.
    lib.addIncludePath(b.path("pq/include/"));
    // Add the directory for the library files.
    lib.addLibraryPath(b.path("pq/lib/"));
    // Link the PostgreSQL library.
    lib.linkSystemLibrary("pq");
    b.installArtifact(lib);
    // Optionally add tests. Here we build and link a test executable.
    var main_test = b.addTest(. {
        .root_source_file = b.path("psql-tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Link the static library we created so that tests use the package.
    main_test.linkLibrary(lib);
    main_test.addIncludePath(b.path("pq/include/"));
    // Add the directory for the library files.
    main_test.addLibraryPath(b.path("pq/lib/"));
    // Link the PostgreSQL library.
    main_test.linkSystemLibrary("pq");
    
    const run_test = b.addRunArtifact(main_test);
    
    //Testing the module
    const test_step = b.step("test", "Run PSQL tests");
    test_step.dependOn(&run_test.step);

    // By default, build the static library.
    b.default_step.dependOn(&lib.step);
}
