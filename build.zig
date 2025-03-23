const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    if (comptime !checkVersion())
        @compileError("Please! Update zig toolchain >= 0.14!");

    //const target = std.Target.Query{
    //    .cpu_arch = .x86_64,
    //    .os_tag = .linux,
    //.abi = .gnu,
    //};

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ocispec = b.dependency("ocispec", .{});
    const datetime = b.dependency("datetime", .{});

    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/libcontainer/lib.zig"),
        //.target = b.resolveTargetQuery(target),
        .target = target,
        .optimize = optimize,
    });

    lib_mod.addImport("ocispec", ocispec.module("ocispec"));
    lib_mod.addImport("datetime", datetime.module("datetime"));

    const libcontainer = b.addLibrary(.{
        .linkage = .static,
        .name = "libcontainer",
        .root_module = lib_mod,
    });

    b.installArtifact(libcontainer);

    const exe = b.addExecutable(.{
        .name = "thorcon",
        .root_source_file = b.path("src/main.zig"),
        //.target = b.resolveTargetQuery(target),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();

    const clap = b.dependency("clap", .{});

    exe.root_module.addImport("clap", clap.module("clap"));
    exe.root_module.addImport("libcontainer", lib_mod);
    b.installArtifact(exe);

    // step check formatting
    const fmt_step = b.step("fmt", "Check formatting");

    const fmt = b.addFmt(.{
        .paths = &.{
            "src/",
            "build.zig",
            "build.zig.zon",
        },
        .check = true,
    });

    fmt_step.dependOn(&fmt.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const libcontainer_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/libcontainer/lib.zig"),
        //.target = b.resolveTargetQuery(target),
        .target = target,
        .optimize = optimize,
    });

    const run_libcontainer_unit_tests = b.addRunArtifact(libcontainer_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        //.target = b.resolveTargetQuery(target),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_libcontainer_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    // step generate code cov
    const cov_step = b.step("cov", "Generate code coverage");

    const cov_run = b.addSystemCommand(&.{ "kcov", "--clean", "--include-pattern=src/", ".coverage/" });
    cov_run.addArtifactArg(libcontainer);

    cov_step.dependOn(&cov_run.step);
}

fn checkVersion() bool {
    const builtin = @import("builtin");
    if (!@hasDecl(builtin, "zig_version")) {
        return false;
    }

    const needed_version = std.SemanticVersion.parse("0.14.0") catch unreachable;
    const version = builtin.zig_version;
    const order = version.order(needed_version);
    return order != .lt;
}
