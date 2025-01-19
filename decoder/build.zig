const std = @import("std");

pub fn build(b: *std.Build) !void {
    const decoderStep = b.step("decoder", "Build the Decoder");
    b.default_step.dependOn(decoderStep);

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .abi = .eabi,
        .os_tag = .freestanding,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .ofmt = .c,
    });

    const decoderExe = b.addExecutable(.{
        .root_source_file = b.path("main.zig"),
        .single_threaded = true,
        .target = target,
        .name = "main",
        .link_libc = true,
    });

    const env = try std.process.getEnvMap(b.allocator);

    var options = b.addOptions();
    const subscriptionkey = try getSubscriptionKey(b.allocator);
    options.addOption(@TypeOf(subscriptionkey), "subscriptionKey", subscriptionkey);

    if (env.get("MAXIM_PATH")) |msdk_path| {
        const msdk = b.addTranslateC(.{
            .root_source_file = b.path("msdk_includes.h"),
            .target = target,
            .optimize = .ReleaseSafe,
            .link_libc = false,
        });

        const include_paths = [_][]const u8{
            "/Libraries/Boards/MAX78000/FTHR_RevA/Include",
            "/Libraries/MiscDrivers",
            "/Libraries/MiscDrivers/Camera",
            "/Libraries/MiscDrivers/Display",
            "/Libraries/MiscDrivers/Display/fonts",
            "/Libraries/MiscDrivers/LED",
            "/Libraries/MiscDrivers/PushButton",
            "/Libraries/MiscDrivers/PMIC",
            "/Libraries/MiscDrivers/Touchscreen",
            "/Libraries/MiscDrivers/CODEC",
            "/Libraries/PeriphDrivers/Include/MAX78000",
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

        msdk.addIncludeDir(try std.fs.path.join(b.allocator, &[_][]const u8{ env.get("GCC_ARM_EMBDEDDED") orelse "/usr/lib", "arm-none-eabi/include" }));

        msdk.defineCMacroRaw("TARGET=MAX78000");
        msdk.defineCMacroRaw("TARGET_REV=0x4131");
        msdk.defineCMacroRaw("LIB_BOARD");
        msdk.defineCMacroRaw("CAMERA_OV7692");

        msdk.defineCMacroRaw("__PROGRAM_START");

        const msdkModule = msdk.createModule();
        decoderExe.root_module.addImport("msdk", msdkModule);

        // decoderStep.dependOn(&b.addInstallFile(msdk.getOutput(), "msdk.zig").step);
        decoderStep.dependOn(&msdk.step);
    }

    const sharedModule = b.createModule(.{
        .root_source_file = b.path("shared/main.zig"),
    });

    decoderExe.root_module.addOptions("secrets", options);
    decoderExe.root_module.addImport("shared", sharedModule);

    const lib_dir_step = try ZigLibDir.create(b);
    decoderStep.dependOn(&lib_dir_step.step);
    decoderStep.dependOn(&b.addInstallFile(lib_dir_step.getLibPath().path(b, "zig.h"), "../c/src/zig.h").step);

    decoderStep.dependOn(&b.addInstallArtifact(decoderExe, .{ .dest_dir = .{ .override = .{ .custom = "../c/src" } } }).step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("shared/main.zig"),
        .target = b.resolveTargetQuery(.{}),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const docs = b.addObject(.{
        .name = "main",
        .root_source_file = b.path("shared/main.zig"),
        .target = target,
        .optimize = .Debug,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .{ .custom = ".." },
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);

    decoderStep.dependOn(&decoderExe.step);
}

fn getSubscriptionKey(allocator: std.mem.Allocator) ![32]u8 {
    const env = try std.process.getEnvMap(allocator);
    const secrets_path = env.get("SECRETS") orelse "../secrets/secrets.json";
    const file = try std.fs.cwd().openFile(secrets_path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 8192);
    defer allocator.free(contents);

    const Secrets = struct {
        subscription_key: []const u8,
    };

    const secrets = try std.json.parseFromSlice(Secrets, allocator, contents, .{ .ignore_unknown_fields = true });
    defer secrets.deinit();

    const deviceId = env.get("DECODER_ID") orelse "0xdeadbeef";
    const deviceIdInt = try std.fmt.parseInt(u32, deviceId, 0);
    const deviceSubscriptionStr = try std.fmt.allocPrint(allocator, "{s}{x:0>8}", .{ secrets.value.subscription_key, deviceIdInt });
    var deviceSubscriptionKey: [32]u8 = undefined;
    std.debug.print("{s}\n", .{deviceSubscriptionStr});
    std.crypto.hash.Blake3.hash(deviceSubscriptionStr, &deviceSubscriptionKey, .{});

    return deviceSubscriptionKey;
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
