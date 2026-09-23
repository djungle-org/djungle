const std = @import("std");

const c_util = @import("C");
const c = c_util.c;

const sdlCheck = c_util.sdlCheck;
const sdlCheckBool = c_util.sdlCheckBool;

const vk = @import("Vulkan");
const win = @import("Window");
const dq = @import("DeletionQueue");
const log = @import("Logging");

const TextureFormat = @import("textures.zig").TextureFormat;

const Instance = vk.InstanceProxy;

pub const Vulkan = struct {
    pub const Error = error{
        InvalidPropertyType,
        SdlLoadVulkanLibraryFailed,
        SdlGetVulkanInstanceProcAddrFailed,
        LayerNotSupported,
        SdlGetVulkanInstanceExtensionsFailed,
        ExtensionNotSupported,
        FailedToGetInstanceProcAddr,
        SdlVulkanCreateSurfaceFailed,
    };

    pub const api_version = vk.API_VERSION_1_4;

    allocator: std.mem.Allocator,

    window: *win.Window,

    deletion_queue: dq.DeletionQueue,

    instance_wrapper: vk.InstanceWrapper,
    instance: Instance,

    debug_messenger: ?vk.DebugUtilsMessengerEXT = null,

    surface: vk.SurfaceKHR,

    /// PropertyType must be vk.LayerProperties or vk.ExtensionProperties
    fn allSupported(required: []const [*:0]const u8, comptime PropertyType: type, properties: []const PropertyType) !bool {
        for (required) |req| {
            var found = false;
            for (properties) |prop| {
                const available = blk: {
                    if (PropertyType == vk.LayerProperties) {
                        break :blk prop.layer_name;
                    } else if (PropertyType == vk.ExtensionProperties) {
                        break :blk prop.extension_name;
                    } else {
                        return Error.InvalidPropertyType;
                    }
                };

                if (std.mem.eql(u8, std.mem.span(req), std.mem.sliceTo(&available, 0))) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                return false;
            }
        }

        return true;
    }

    /// c_array must have c_array_len valid elements
    fn cArrayToArrayList(gpa: std.mem.Allocator, comptime CType: type, comptime ZType: type, c_array: [*c]const CType, c_array_len: u32) !std.ArrayList(ZType) {
        var array_list = try std.ArrayList(ZType).initCapacity(gpa, c_array_len);
        array_list.items.len = c_array_len;

        var i: u32 = 0;
        while (i < c_array_len) : (i += 1) {
            array_list.items[i] = @ptrCast(c_array[i]);
        }

        return array_list;
    }

    /// used for finding bits that are true within packed structs
    /// ex: vk.DebugUtilsMessageTypeFlagsEXT has many bools, so this function is for finding the one that is true
    fn findPackedStructFieldTrue(comptime StructType: type, packed_struct: StructType) ?[:0]const u8 {
        inline for (@typeInfo(StructType).@"struct".fields) |field| {
            if (field.type == bool and @field(packed_struct, field.name)) {
                return field.name;
            }
        }

        return null;
    }

    /// caller owns the returned memory
    fn enumerateVulkanThing(self: *@This(), comptime T: type, comptime vk_enumerate_fn: anytype, extra_args: anytype) !std.ArrayList(T) {
        var count: u32 = 0;
        // discarding fine because vulkan-zig converts vk results into zig errors
        _ = try @call(.auto, vk_enumerate_fn, extra_args ++ .{ &count, null });
        var array_list = try std.ArrayList(T).initCapacity(self.allocator, count);
        array_list.items.len = count;
        _ = try @call(.auto, vk_enumerate_fn, extra_args ++ .{ &count, array_list.items.ptr });

        return array_list;
    }

    fn createInstance(self: *@This(), base_wrapper: vk.BaseWrapper, debug: bool, app_name: [:0]const u8) !void {
        const app_info = vk.ApplicationInfo{
            .api_version = api_version.toU32(),
            .engine_version = 1,
            .application_version = 1,
            .p_application_name = app_name,
            .p_engine_name = "Djungle",
        };

        var layer_props = try self.enumerateVulkanThing(
            vk.LayerProperties,
            vk.BaseWrapper.enumerateInstanceLayerProperties,
            .{base_wrapper},
        );
        defer layer_props.deinit(self.allocator);

        var required_layers = std.ArrayList([*:0]const u8).empty;
        defer required_layers.deinit(self.allocator);
        if (debug) try required_layers.append(self.allocator, "VK_LAYER_KHRONOS_validation");

        if (!try allSupported(required_layers.items, vk.LayerProperties, layer_props.items)) {
            return Error.LayerNotSupported;
        }

        log.debug(@src(), "Found all required layers", .{});

        var sdl_ext_count: u32 = 0;
        const sdl_extensions = try sdlCheck(
            @src(),
            [*c]const [*c]const u8,
            c.SDL_Vulkan_GetInstanceExtensions(&sdl_ext_count),
            Error.SdlGetVulkanInstanceExtensionsFailed,
        );

        var required_extensions = try cArrayToArrayList(
            self.allocator,
            [*c]const u8,
            [*:0]const u8,
            sdl_extensions,
            sdl_ext_count,
        );
        defer required_extensions.deinit(self.allocator);

        if (debug) {
            try required_extensions.append(self.allocator, vk.extensions.ext_debug_utils.name);
        }

        var ext_props = try self.enumerateVulkanThing(
            vk.ExtensionProperties,
            vk.BaseWrapper.enumerateInstanceExtensionProperties,
            .{ base_wrapper, null },
        );
        defer ext_props.deinit(self.allocator);

        if (!try allSupported(required_extensions.items, vk.ExtensionProperties, ext_props.items)) {
            return Error.ExtensionNotSupported;
        }

        log.debug(@src(), "Found all required extensions", .{});

        const instance_info = vk.InstanceCreateInfo{
            .p_application_info = &app_info,
            .enabled_layer_count = @intCast(required_layers.items.len),
            .pp_enabled_layer_names = required_layers.items.ptr,
            .enabled_extension_count = @intCast(required_extensions.items.len),
            .pp_enabled_extension_names = required_extensions.items.ptr,
        };

        const instance_handle = try base_wrapper.createInstance(&instance_info, null);
        self.instance_wrapper = vk.InstanceWrapper.load(
            instance_handle,
            base_wrapper.dispatch.vkGetInstanceProcAddr.?,
        );

        self.instance = Instance.init(instance_handle, &self.instance_wrapper);

        try self.deletion_queue.push(self.allocator, Instance.destroyInstance, .{ self.instance, null });
    }

    fn debugCallback(
        severity: vk.DebugUtilsMessageSeverityFlagsEXT,
        msg_type: vk.DebugUtilsMessageTypeFlagsEXT,
        callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
        _: ?*anyopaque,
    ) callconv(vk.vulkan_call_conv) vk.Bool32 {
        const msg_type_str = findPackedStructFieldTrue(vk.DebugUtilsMessageTypeFlagsEXT, msg_type).?;

        if (severity.error_bit_ext) {
            log.err(@src(), "(Validation layer) type: {s}\nmsg: {s}", .{ msg_type_str, callback_data.?.p_message.? });
        } else if (severity.warning_bit_ext) {
            log.warn(@src(), "(Validation layer) type: {s}\nmsg: {s}", .{ msg_type_str, callback_data.?.p_message.? });
        }

        return vk.Bool32.false;
    }

    fn createDebugMessenger(self: *@This()) !void {
        const debug_messenger_info = vk.DebugUtilsMessengerCreateInfoEXT{
            .message_severity = .{ .warning_bit_ext = true, .error_bit_ext = true },
            .message_type = .{ .general_bit_ext = true, .performance_bit_ext = true, .validation_bit_ext = true },
            .pfn_user_callback = &debugCallback,
        };

        self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(
            &debug_messenger_info,
            null,
        );

        try self.deletion_queue.push(self.allocator, Instance.destroyDebugUtilsMessengerEXT, .{ self.instance, self.debug_messenger.?, null });
    }

    fn createSurface(self: *@This()) !void {
        var c_vk_surface: c.VkSurfaceKHR = undefined;

        try sdlCheckBool(
            @src(),
            c.SDL_Vulkan_CreateSurface(
                self.window.sdl_window,
                @ptrFromInt(@intFromEnum(self.instance.handle)),
                null,
                &c_vk_surface,
            ),
            Error.SdlVulkanCreateSurfaceFailed,
        );

        self.surface = @enumFromInt(@intFromPtr(c_vk_surface));

        try self.deletion_queue.push(self.allocator, Instance.destroySurfaceKHR, .{ self.instance, self.surface, null });
    }

    // fn choosePhysicalDevice(self: *@This()) !void {
    //     self.instance.enumeratePhysicalDevices()
    // }

    pub fn init(self: *@This(), gpa: std.mem.Allocator, debug_mode: bool, window: *win.Window, app_name: [:0]const u8) !void {
        self.allocator = gpa;
        self.deletion_queue = try .initCapacity(self.allocator, 1);

        self.window = window;

        try sdlCheckBool(@src(), c.SDL_Vulkan_LoadLibrary(null), Error.SdlLoadVulkanLibraryFailed);

        const get_instance_proc_addr = try sdlCheck(
            @src(),
            *const fn () callconv(.c) void,
            c.SDL_Vulkan_GetVkGetInstanceProcAddr(),
            Error.SdlGetVulkanInstanceProcAddrFailed,
        );

        const pfn: vk.PfnGetInstanceProcAddr = @ptrCast(get_instance_proc_addr);
        const base_wrapper = vk.BaseWrapper.load(pfn);

        try self.createInstance(base_wrapper, debug_mode, app_name);
        if (debug_mode) try self.createDebugMessenger();

        try self.createSurface();
    }

    pub fn deinit(self: *@This()) void {
        self.deletion_queue.deinit(self.allocator);
    }

    pub fn getSwapchainFormat(self: *@This(), window: *const win.Window) !TextureFormat {
        return try TextureFormat.fromSdl(c.SDL_GetGPUSwapchainTextureFormat(self.sdl_gpu_device, window.sdl_window));
    }
};
