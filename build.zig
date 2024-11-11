const std = @import("std");

pub fn build(b: *std.Build) !void {
    const step = b.step("application-processor", "Build the application processor");
    b.default_step.dependOn(step);

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .abi = .eabi,
        .os_tag = .freestanding,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .ofmt = .c,
    });

    const msdk = b.addTranslateC(.{
        .root_source_file = b.path("msdk_includes.h"),
        .target = target,
        .optimize = .ReleaseSafe,
        .link_libc = false,
    });

    const env = try std.process.getEnvMap(b.allocator);

    const msdk_path = env.get("MAXIM_PATH").?;
    const include_paths = [_][]const u8{
        "/Libraries/Boards/MAX78000/FTHR_RevA/Include",
        "/Libraries/MiscDrivers",
        "/Libraries/MiscDrivers/Camera",
        "/Libraries/MiscDrivers/Display",
        "/Libraries/MiscDrivers/LED",
        "/Libraries/MiscDrivers/PushButton",
        "/Libraries/MiscDrivers/PMIC",
        "/Libraries/MiscDrivers/Touchscreen",
        "/Libraries/MiscDrivers/CODEC",
        "/Libraries/PeriphDrivers/Include/MAX78000/",
        "/Libraries/PeriphDrivers/Source/ADC",
        "/Libraries/PeriphDrivers/Source/AES",
        "/Libraries/PeriphDrivers/Source/CAMERAIF",
        "/Libraries/PeriphDrivers/Source/CRC",
        "/Libraries/PeriphDrivers/Source/DMA",
        "/Libraries/PeriphDrivers/Source/FLC",
        "/Libraries/PeriphDrivers/Source/GPIO",
        "/Libraries/PeriphDrivers/Source/I2C",
        "/Libraries/PeriphDrivers/Source/I2S",
        "/Libraries/PeriphDrivers/Source/ICC",
        "/Libraries/PeriphDrivers/Source/LP",
        "/Libraries/PeriphDrivers/Source/LPCMP",
        "/Libraries/PeriphDrivers/Source/OWM",
        "/Libraries/PeriphDrivers/Source/PT",
        "/Libraries/PeriphDrivers/Source/RTC",
        "/Libraries/PeriphDrivers/Source/SEMA",
        "/Libraries/PeriphDrivers/Source/SPI",
        "/Libraries/PeriphDrivers/Source/TRNG",
        "/Libraries/PeriphDrivers/Source/TMR",
        "/Libraries/PeriphDrivers/Source/UART",
        "/Libraries/PeriphDrivers/Source/WDT",
        "/Libraries/PeriphDrivers/Source/WUT",
        "/Libraries/CMSIS/Device/Maxim/MAX78000/Include",
        "/Libraries/CMSIS/5.9.0/Core/Include",
    };
    for (include_paths) |include_path| {
        msdk.addIncludeDir(try std.fs.path.join(b.allocator, &[_][]const u8{ msdk_path, include_path }));
    }

    const gcc_arm_embedded_path = env.get("GCC_ARM_EMBDEDDED").?;
    const global_include_paths = [_][]const u8{
        "lib/gcc/arm-none-eabi/12.3.1/include",
        "lib/gcc/arm-none-eabi/12.3.1/include-fixed",
        "arm-none-eabi/include",
    };
    for (global_include_paths) |global_include_path| {
        msdk.addIncludeDir(try std.fs.path.join(b.allocator, &[_][]const u8{ gcc_arm_embedded_path, global_include_path }));
    }

    msdk.defineCMacroRaw("TARGET=MAX78000");
    msdk.defineCMacroRaw("TARGET_REV=0x4131");
    msdk.defineCMacroRaw("LIB_BOARD");
    msdk.defineCMacroRaw("CAMERA_OV7692");

    msdk.defineCMacroRaw("__PROGRAM_START");

    const exe = b.addExecutable(.{
        .root_source_file = b.path("application_processor/main.zig"),
        .single_threaded = true,
        .target = target,
        .name = "main",
    });

    exe.root_module.addImport("msdk", msdk.createModule());

    exe.addIncludePath(b.path("application_processor/inc"));

    const lib_dir_step = try ZigLibDir.create(b);
    step.dependOn(&lib_dir_step.step);
    step.dependOn(&b.addInstallFile(lib_dir_step.getLibPath().path(b, "zig.h"), "../application_processor/c/src/zig.h").step);

    step.dependOn(&b.addInstallFile(msdk.getOutput(), "msdk.zig").step);

    step.dependOn(&b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = "../application_processor/c/src" } } }).step);

    step.dependOn(&exe.step);
    step.dependOn(&msdk.step);
}

const ZigLibDir = struct {
    step: std.Build.Step,
    lib_dir: std.Build.GeneratedFile,

    pub fn create(owner: *std.Build) !*ZigLibDir {
        const self = try owner.allocator.create(ZigLibDir);
        const name = "zig lib dir";
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = name,
                .owner = owner,
                .makeFn = make,
            }),
            .lib_dir = .{ .step = &self.step },
        };
        return self;
    }

    const ZigEnv = struct {
        lib_dir: []const u8,
    };

    fn make(step: *std.Build.Step, prog_node: std.Progress.Node) !void {
        _ = prog_node;

        const b = step.owner;
        const self: *ZigLibDir = @fieldParentPtr("step", step);

        const zig_env_args: [2][]const u8 = .{ b.graph.zig_exe, "env" };
        var out_code: u8 = undefined;
        const zig_env = try b.runAllowFail(&zig_env_args, &out_code, .Ignore);

        const parsed_str = try std.json.parseFromSlice(ZigEnv, b.allocator, zig_env, .{ .ignore_unknown_fields = true });
        defer parsed_str.deinit();

        self.lib_dir.path = parsed_str.value.lib_dir;
    }

    pub fn getLibPath(self: *ZigLibDir) std.Build.LazyPath {
        return .{ .generated = .{ .file = &self.lib_dir } };
    }
};
