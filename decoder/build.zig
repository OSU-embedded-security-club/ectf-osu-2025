const std = @import("std");

pub fn build(b: *std.Build) !void {
    const decoder_step = b.step("decoder", "Build the Decoder");
    b.default_step.dependOn(decoder_step);

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .eabi,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .ofmt = .c,
    });

    const decoder_exe = b.addExecutable(.{
        .root_source_file = b.path("main.zig"),
        .single_threaded = true,
        .target = target,
        .name = "main",
        .optimize = .ReleaseSafe,
        .link_libc = true,
    });

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("lib/main.zig"),
        .target = b.resolveTargetQuery(.{}),
        .link_libc = true,
    });
    const test_step = b.step("test", "Run unit tests");

    const env = try std.process.getEnvMap(b.allocator);

    var options = b.addOptions();
    const secrets = try getSecrets(b.allocator);
    options.addOption(@TypeOf(secrets.subscription_key), "subscription_key", secrets.subscription_key);
    options.addOption(@TypeOf(secrets.public_key), "public_key", secrets.public_key);
    options.addOption([]const u16, "channel_ids", secrets.channel_ids[0..secrets.num_channel_ids]);
    options.addOption(@TypeOf(secrets.flash_at_rest_key), "flash_at_rest_key", secrets.flash_at_rest_key);
    options.addOption(@TypeOf(secrets.metadata_key), "metadata_key", secrets.metadata_key);

    if (env.get("MAXIM_PATH")) |msdk_path| {
        const msdk = b.addTranslateC(.{
            .root_source_file = b.path("msdk_includes.h"),
            .target = target,
            .optimize = .ReleaseSafe,
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
            "/Libraries/MiscDrivers/SRAM",
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
        msdk.defineCMacroRaw("__COMPILER_BARRIER()");
        msdk.defineCMacroRaw("TARGET_REV=0x4131");
        msdk.defineCMacroRaw("LIB_BOARD");
        msdk.defineCMacroRaw("CAMERA_OV7692");

        msdk.defineCMacroRaw("__PROGRAM_START");

        const msdk_module = msdk.createModule();
        decoder_exe.root_module.addImport("msdk", msdk_module);

        decoder_step.dependOn(&msdk.step);
    }

    if (env.get("ED25519_PATH")) |ed25519_path| {
        const ed25519 = b.addTranslateC(.{
            .root_source_file = b.path("ed25519_includes.h"),
            .target = target,
            .optimize = .ReleaseSafe,
            .link_libc = false,
        });

        ed25519.addIncludeDir(ed25519_path);
        ed25519.defineCMacroRaw("ED25519_NO_SEED");
        ed25519.addIncludeDir(try std.fs.path.join(b.allocator, &[_][]const u8{ env.get("GCC_ARM_EMBDEDDED") orelse "/usr/lib", "arm-none-eabi/include" }));

        unit_tests.defineCMacro("ED25519_NO_SEED", null);
        unit_tests.addIncludePath(.{ .cwd_relative = ed25519_path });
        unit_tests.addIncludePath(b.path("."));

        const ed25519_module = ed25519.createModule();
        decoder_exe.root_module.addImport("ed25519", ed25519_module);
        unit_tests.root_module.addImport("ed25519", ed25519_module);

        unit_tests.addCSourceFiles(.{ .root = .{ .cwd_relative = ed25519_path }, .files = &.{
            "src/add_scalar.c",
            "src/fe.c",
            "src/ge.c",
            "src/key_exchange.c",
            "src/keypair.c",
            "src/sc.c",
            "src/seed.c",
            "src/sha512.c",
            "src/sign.c",
            "src/verify.c",
        } });

        decoder_step.dependOn(&ed25519.step);
        test_step.dependOn(&ed25519.step);
    }

    const lib_module = b.createModule(.{
        .root_source_file = b.path("lib/main.zig"),
    });

    decoder_exe.root_module.addOptions("secrets", options);
    decoder_exe.root_module.addImport("lib", lib_module);

    const lib_dir_step = try ZigLibDir.create(b);
    decoder_step.dependOn(&lib_dir_step.step);
    decoder_step.dependOn(&b.addInstallFile(lib_dir_step.getLibPath().path(b, "zig.h"), "../c/src/zig.h").step);

    decoder_step.dependOn(&b.addInstallArtifact(decoder_exe, .{ .dest_dir = .{ .override = .{ .custom = "../c/src" } } }).step);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    const docs = b.addObject(.{
        .name = "main",
        .root_source_file = b.path("lib/main.zig"),
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

    decoder_step.dependOn(&decoder_exe.step);
}

const Secrets = struct {
    subscription_key: [32]u8,
    public_key: [32]u8,
    channel_ids: [8]u16,
    num_channel_ids: u4,
    flash_at_rest_key: [32]u8,
    metadata_key: [32]u8,
};

fn getSecrets(allocator: std.mem.Allocator) !Secrets {
    const env = try std.process.getEnvMap(allocator);
    const secrets_path = env.get("SECRETS") orelse "../secrets/secrets.json";
    const file = try std.fs.cwd().openFile(secrets_path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 8192);
    defer allocator.free(contents);

    const SecretsJson = struct {
        subscription_salt: []const u8,
        public_key: []const u8,
        metadata_key: []const u8,
    };

    const secrets = try std.json.parseFromSlice(SecretsJson, allocator, contents, .{ .ignore_unknown_fields = true });
    defer secrets.deinit();

    const secrets_unstructured = try std.json.parseFromSlice(std.json.Value, allocator, contents, .{});
    defer secrets_unstructured.deinit();
    const seeds = secrets_unstructured.value.object.get("seeds").?;
    var channel_ids: [8]u16 = undefined;
    var num_channel_ids: u4 = 0;
    for (seeds.object.keys(), 0..) |key, i| {
        const channel_id = try std.fmt.parseInt(u16, key, 0);
        channel_ids[i] = channel_id;
    }
    num_channel_ids = @intCast(seeds.object.count());

    const device_id = env.get("DECODER_ID") orelse "0xdeadbeef";
    const device_id_int = try std.fmt.parseInt(u32, device_id, 0);
    const device_subscription_str = try std.fmt.allocPrint(allocator, "{s}{x:0>8}", .{ secrets.value.subscription_salt, device_id_int });
    var device_subscription_key: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(device_subscription_str, &device_subscription_key, .{});

    var public_key: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&public_key, secrets.value.public_key);

    var flash_at_rest_key: [32]u8 = undefined;
    std.crypto.random.bytes(&flash_at_rest_key);

    var metadata_key: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&metadata_key, secrets.value.metadata_key);

    return Secrets{
        .subscription_key = device_subscription_key,
        .public_key = public_key,
        .channel_ids = channel_ids,
        .num_channel_ids = num_channel_ids,
        .flash_at_rest_key = flash_at_rest_key,
        .metadata_key = metadata_key,
    };
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
