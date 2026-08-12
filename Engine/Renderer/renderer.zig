const std = @import("std");

const c = @cImport({
    @cInclude("SDL3/SDL_vulkan.h");
});

const vk = @import("Vulkan");
const delque = @import("DeletionQueue");
const win = @import("Window");
const log = @import("Logging");

pub const RendererError = error{
    SdlLoadVulkanLibraryFailed,
    SdlGetInstanceProcAddrFailed,
    SdlGetInstanceExtensionsFailed,
    InvalidPropertyType,
    LayerNotSupported,
    ExtensionNotSupported,
    FailedToGetInstanceProcAddr,
};

pub const api_version = vk.API_VERSION_1_4;

const vulkan_debug: bool = switch (@import("builtin").mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

const required_layers =
    if (vulkan_debug) [1][*:0]const u8{"VK_LAYER_KHRONOS_validation"} else [0][*:0]const u8{};

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
fn findStructFieldTrue(comptime StructType: type, packed_struct: StructType) ?[:0]const u8 {
    inline for (@typeInfo(StructType).@"struct".fields) |field| {
        if (field.type == bool and @field(packed_struct, field.name)) {
            return field.name;
        }
    }

    return null;
}

/// PropertyType must be vk.LayerProperties or vk.ExtensionProperties
fn allSupported(required: []const [*:0]const u8, comptime PropertyType: type, properties: []const PropertyType) !bool {
    for (required) |req| {
        var found = false;
        for (properties) |prop| {
            const available =
                if (PropertyType == vk.LayerProperties) prop.layer_name else if (PropertyType == vk.ExtensionProperties) prop.extension_name else return RendererError.InvalidPropertyType;

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

const Instance = struct {
    vk_instance: vk.Instance,
    vk_debug_messenger: ?vk.DebugUtilsMessengerEXT,
    fns: vk.InstanceWrapper,

    pub fn deinit(self: *@This()) void {
        self.fns.destroyInstance(self.vk_instance, null);
    }

    pub fn deinitDebugMessenger(self: *@This()) void {
        if (vulkan_debug) self.fns.destroyDebugUtilsMessengerEXT(self.vk_instance, self.vk_debug_messenger.?, null);
    }
};

pub const Renderer = struct {
    allocator: std.mem.Allocator,

    _deletion_queue: delque.DeletionQueue,

    _window: *win.Window,

    _instance: Instance,

    pub fn init(self: *@This(), gpa: std.mem.Allocator, window: *win.Window, comptime app_name: [:0]const u8) !void {
        self.allocator = gpa;
        self._window = window;
        self._deletion_queue = try delque.DeletionQueue.initCapacity(self.allocator, 1); // capacity of 1 for the vulkan instance

        if (!c.SDL_Vulkan_LoadLibrary(null)) { // sdl will find vulkan library, if not sdl get vk instance proc addr wil fail
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return RendererError.SdlLoadVulkanLibraryFailed;
        }

        const get_instance_proc_addr = c.SDL_Vulkan_GetVkGetInstanceProcAddr() orelse {
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return RendererError.SdlGetInstanceProcAddrFailed;
        };

        const pfn: vk.PfnGetInstanceProcAddr = @ptrCast(get_instance_proc_addr);
        const base_fns = vk.BaseWrapper.load(pfn);

        try self.createInstance(base_fns, app_name);
        if (vulkan_debug) try self.createDebugMessenger();
    }

    pub fn deinit(self: *@This()) void {
        self._deletion_queue.deinit(self.allocator); // deinits all the items in the queue
    }

    fn createInstance(self: *@This(), base_fns: vk.BaseWrapper, comptime app_name: [:0]const u8) !void {
        const app_info = vk.ApplicationInfo{
            .api_version = api_version.toU32(),
            .engine_version = 1,
            .application_version = 1,
            .p_application_name = app_name,
            .p_engine_name = "Zig Vulkan Engine",
        };

        var layer_count: u32 = 0;
        _ = try base_fns.enumerateInstanceLayerProperties(&layer_count, null);
        var layer_props = try std.ArrayList(vk.LayerProperties).initCapacity(self.allocator, layer_count);
        defer layer_props.deinit(self.allocator);
        layer_props.items.len = layer_count;
        _ = try base_fns.enumerateInstanceLayerProperties(&layer_count, layer_props.items.ptr);

        if (!try allSupported(&required_layers, vk.LayerProperties, layer_props.items)) {
            return RendererError.LayerNotSupported;
        }

        log.debug(@src(), "Found all required layers", .{});

        var sdl_ext_count: u32 = 0;
        const sdl_extensions = c.SDL_Vulkan_GetInstanceExtensions(&sdl_ext_count) orelse {
            log.err(@src(), "{s}", .{c.SDL_GetError()});
            return RendererError.SdlGetInstanceExtensionsFailed;
        };

        var required_extensions = try cArrayToArrayList(self.allocator, [*c]const u8, [*:0]const u8, sdl_extensions, sdl_ext_count);
        defer required_extensions.deinit(self.allocator);

        if (vulkan_debug) {
            try required_extensions.append(self.allocator, vk.extensions.ext_debug_utils.name);
        }

        var ext_count: u32 = 0;
        _ = try base_fns.enumerateInstanceExtensionProperties(null, &ext_count, null);
        var ext_props = try std.ArrayList(vk.ExtensionProperties).initCapacity(self.allocator, ext_count);
        defer ext_props.deinit(self.allocator);
        ext_props.items.len = ext_count;
        _ = try base_fns.enumerateInstanceExtensionProperties(null, &ext_count, ext_props.items.ptr);

        if (!try allSupported(required_extensions.items, vk.ExtensionProperties, ext_props.items)) {
            return RendererError.ExtensionNotSupported;
        }

        log.debug(@src(), "Found all required extensions", .{});

        const instance_info = vk.InstanceCreateInfo{
            .p_application_info = &app_info,
            .enabled_layer_count = required_layers.len,
            .pp_enabled_layer_names = &required_layers,
            .enabled_extension_count = @intCast(required_extensions.items.len),
            .pp_enabled_extension_names = required_extensions.items.ptr,
        };

        const vk_instance = try base_fns.createInstance(&instance_info, null);

        self._instance = Instance{
            .vk_instance = vk_instance,
            .vk_debug_messenger = null, // initialized later
            .fns = vk.InstanceWrapper.load(vk_instance, base_fns.dispatch.vkGetInstanceProcAddr orelse {
                return RendererError.FailedToGetInstanceProcAddr;
            }),
        };

        try self._deletion_queue.push(self.allocator, Instance, &self._instance, &Instance.deinit);
    }

    fn debugCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(vk.vulkan_call_conv) vk.Bool32 {
        const msg_type_str = findStructFieldTrue(vk.DebugUtilsMessageTypeFlagsEXT, msg_type).?;

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

        self._instance.vk_debug_messenger = try self._instance.fns.createDebugUtilsMessengerEXT(self._instance.vk_instance, &debug_messenger_info, null);

        try self._deletion_queue.push(self.allocator, Instance, &self._instance, &Instance.deinitDebugMessenger);
    }
};
