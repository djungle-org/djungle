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
const Device = vk.DeviceProxy;
const Queue = vk.QueueProxy;

pub const Vulkan = struct {
    pub const Error = error{
        InvalidPropertyType,
        SdlLoadVulkanLibraryFailed,
        SdlGetVulkanInstanceProcAddrFailed,
        LayerNotSupported,
        SdlGetVulkanInstanceExtensionsFailed,
        ExtensionNotSupported,
        SdlVulkanCreateSurfaceFailed,
        FailedToFindSupportedGPU,
        FailedToFindMatchingSwapchainSurfaceFormat,
        SdlWaitEventFailed,
        FailedToCreateVmaAllocator,
    };

    pub const api_version = vk.API_VERSION_1_3;

    pub const required_extensions = [_][:0]const u8{
        vk.extensions.khr_swapchain.name,
    };

    allocator: std.mem.Allocator,

    window: *win.Window,

    event: *c.SDL_Event,

    deletion_queue: dq.DeletionQueue,

    instance_wrapper: vk.InstanceWrapper,
    instance: Instance,

    debug_messenger: ?vk.DebugUtilsMessengerEXT,

    surface: vk.SurfaceKHR,

    physical_device: vk.PhysicalDevice,
    gfx_queue_family_idx: u32,

    device_wrapper: vk.DeviceWrapper,
    device: Device,

    vma_allocator: c.VmaAllocator,

    queue: Queue,

    swapchain_extent: vk.Extent2D,
    swapchain_surface_format: vk.SurfaceFormatKHR,
    swapchain: vk.SwapchainKHR,
    swapchain_images: []vk.Image,
    swapchain_image_views: std.ArrayList(vk.ImageView),

    /// PropertyType must be vk.LayerProperties or vk.ExtensionProperties
    fn allSupported(required: []const [:0]const u8, comptime PropertyType: type, properties: []const PropertyType) !bool {
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

                if (std.mem.eql(u8, req, std.mem.sliceTo(&available, 0))) {
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

    /// caller owns returned memory
    fn sliceOfStringsToSliceOfManyItemPtr(allocator: std.mem.Allocator, strings: []const [:0]const u8) ![][*:0]const u8 {
        const manyItemPtrs = try allocator.alloc([*:0]const u8, strings.len);
        for (strings, 0..) |string, i| manyItemPtrs[i] = string.ptr;

        return manyItemPtrs;
    }

    fn createInstance(self: *@This(), base_wrapper: vk.BaseWrapper, debug: bool, app_name: [:0]const u8) !void {
        const app_info = vk.ApplicationInfo{
            .api_version = api_version.toU32(),
            .engine_version = 1,
            .application_version = 1,
            .p_application_name = app_name,
            .p_engine_name = "Djungle",
        };

        const layer_props = try base_wrapper.enumerateInstanceLayerPropertiesAlloc(self.allocator);
        defer self.allocator.free(layer_props);

        var required_layers = std.ArrayList([:0]const u8).empty;
        defer required_layers.deinit(self.allocator);
        if (debug) try required_layers.append(self.allocator, "VK_LAYER_KHRONOS_validation");

        if (!try allSupported(required_layers.items, vk.LayerProperties, layer_props)) {
            return Error.LayerNotSupported;
        }

        log.debug(@src(), "Found all required layers", .{});

        var sdl_ext_count: u32 = undefined;
        const sdl_extensions: []const [*c]const u8 = (try sdlCheck(
            @src(),
            [*]const [*c]const u8,
            c.SDL_Vulkan_GetInstanceExtensions(&sdl_ext_count),
            Error.SdlGetVulkanInstanceExtensionsFailed,
        ))[0..sdl_ext_count];

        var required_instance_extensions = try self.allocator.alloc(
            [:0]const u8,
            if (debug) sdl_extensions.len + 1 else sdl_extensions.len,
        );
        defer self.allocator.free(required_instance_extensions);

        for (sdl_extensions, 0..) |c_ext_name, i|
            required_instance_extensions[i] = std.mem.span(c_ext_name);

        if (debug)
            required_instance_extensions[required_instance_extensions.len - 1] = vk.extensions.ext_debug_utils.name;

        const ext_props = try base_wrapper.enumerateInstanceExtensionPropertiesAlloc(null, self.allocator);
        defer self.allocator.free(ext_props);

        if (!try allSupported(required_instance_extensions, vk.ExtensionProperties, ext_props)) {
            return Error.ExtensionNotSupported;
        }

        log.debug(@src(), "Found all required extensions", .{});

        const layer_name_ptrs = try sliceOfStringsToSliceOfManyItemPtr(self.allocator, required_layers.items);
        defer self.allocator.free(layer_name_ptrs);

        const ext_name_ptrs = try sliceOfStringsToSliceOfManyItemPtr(self.allocator, required_instance_extensions);
        defer self.allocator.free(ext_name_ptrs);

        const instance_info = vk.InstanceCreateInfo{
            .p_application_info = &app_info,
            .enabled_layer_count = @intCast(layer_name_ptrs.len),
            .pp_enabled_layer_names = layer_name_ptrs.ptr,
            .enabled_extension_count = @intCast(ext_name_ptrs.len),
            .pp_enabled_extension_names = ext_name_ptrs.ptr,
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

    fn isPhysicalDeviceSuitable(self: *@This(), physical_device: *const vk.PhysicalDevice) !struct { bool, u32 } {
        const supports_targeted_api_version: bool =
            self.instance.getPhysicalDeviceProperties(physical_device.*).api_version >= api_version.toU32();

        const queue_families_props = try self.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(
            physical_device.*,
            self.allocator,
        );
        defer self.allocator.free(queue_families_props);

        var supports_graphics_and_surfaces: bool = false;
        var gfx_queue_family_idx: u32 = 0;
        for (queue_families_props, 0..) |queue_family_props, i| {
            const surface_support = .true == try self.instance.getPhysicalDeviceSurfaceSupportKHR(
                physical_device.*,
                @intCast(i),
                self.surface,
            );

            if (queue_family_props.queue_flags.contains(.{ .graphics_bit = true }) and surface_support) {
                supports_graphics_and_surfaces = true;
                gfx_queue_family_idx = @intCast(i);
                break;
            }
        }

        const device_extensions_props = try self.instance.enumerateDeviceExtensionPropertiesAlloc(
            physical_device.*,
            null,
            self.allocator,
        );
        defer self.allocator.free(device_extensions_props);

        const supports_required_extensions = try allSupported(
            &required_extensions,
            vk.ExtensionProperties,
            device_extensions_props,
        );

        var vulkan11features = vk.PhysicalDeviceVulkan11Features{};
        var vulkan12features = vk.PhysicalDeviceVulkan12Features{
            .p_next = &vulkan11features,
        };
        var vulkan13features = vk.PhysicalDeviceVulkan13Features{
            .p_next = &vulkan12features,
        };
        var extended_dynamic_state_features_ext = vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT{
            .p_next = &vulkan13features,
        };
        var features = vk.PhysicalDeviceFeatures2{
            .features = .{},
            .p_next = &extended_dynamic_state_features_ext,
        };

        self.instance.getPhysicalDeviceFeatures2(physical_device.*, &features);

        const supports_required_features =
            vulkan11features.shader_draw_parameters == .true and
            vulkan12features.buffer_device_address == .true and
            vulkan13features.synchronization_2 == .true and
            vulkan13features.dynamic_rendering == .true and
            extended_dynamic_state_features_ext.extended_dynamic_state == .true;

        return .{
            supports_targeted_api_version and supports_graphics_and_surfaces and supports_required_extensions and supports_required_features,
            gfx_queue_family_idx,
        };
    }

    fn choosePhysicalDevice(self: *@This()) !void {
        const physical_devices = try self.instance.enumeratePhysicalDevicesAlloc(self.allocator);
        defer self.allocator.free(physical_devices);

        for (physical_devices) |physical_device| {
            const suitable, const gfx_queue_family_idx = try self.isPhysicalDeviceSuitable(&physical_device);
            if (suitable) {
                self.physical_device = physical_device;
                self.gfx_queue_family_idx = gfx_queue_family_idx;
                return;
            }
        }

        return Error.FailedToFindSupportedGPU;
    }

    fn createLogicalDevice(self: *@This()) !void {
        var vulkan11features = vk.PhysicalDeviceVulkan11Features{
            .shader_draw_parameters = .true,
        };
        var vulkan12features = vk.PhysicalDeviceVulkan12Features{
            .p_next = &vulkan11features,
            .buffer_device_address = .true,
        };
        var vulkan13features = vk.PhysicalDeviceVulkan13Features{
            .p_next = &vulkan12features,
            .synchronization_2 = .true,
            .dynamic_rendering = .true,
        };
        var extended_dynamic_state_features_ext = vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT{
            .p_next = &vulkan13features,
            .extended_dynamic_state = .true,
        };
        var features = vk.PhysicalDeviceFeatures2{
            .p_next = &extended_dynamic_state_features_ext,
            .features = .{ .sampler_anisotropy = .true },
        };

        const queue_priority: f32 = 0.5; // priority for scheduling command buffer execution, needed even if there is one queue
        const queue_create_info = vk.DeviceQueueCreateInfo{
            .queue_family_index = self.gfx_queue_family_idx,
            .queue_count = 1,
            .p_queue_priorities = &.{queue_priority},
        };

        const ext_name_ptrs = try sliceOfStringsToSliceOfManyItemPtr(self.allocator, &required_extensions);
        defer self.allocator.free(ext_name_ptrs);

        const device_create_info = vk.DeviceCreateInfo{
            .p_next = &features,
            .queue_create_info_count = 1,
            .p_queue_create_infos = &.{queue_create_info},
            .enabled_extension_count = @intCast(ext_name_ptrs.len),
            .pp_enabled_extension_names = ext_name_ptrs.ptr,
        };

        const device_handle = try self.instance.createDevice(self.physical_device, &device_create_info, null);
        self.device_wrapper = vk.DeviceWrapper.load(device_handle, self.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);

        self.device = Device.init(device_handle, &self.device_wrapper);

        try self.deletion_queue.push(self.allocator, Device.destroyDevice, .{ self.device, null });

        const queue_handle = self.device.getDeviceQueue(self.gfx_queue_family_idx, 0);
        self.queue = Queue.init(queue_handle, self.device.wrapper);
    }

    fn initVMA(self: *@This(), base_wrapper: vk.BaseWrapper) !void {
        const vma_funcs = c.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = @ptrCast(base_wrapper.dispatch.vkGetInstanceProcAddr),
            .vkGetDeviceProcAddr = @ptrCast(self.instance.wrapper.dispatch.vkGetDeviceProcAddr),
        };

        const vma_alloc_create_info = c.VmaAllocatorCreateInfo{
            .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
            .physicalDevice = @ptrFromInt(@intFromEnum(self.physical_device)),
            .device = @ptrFromInt(@intFromEnum(self.device.handle)),
            .pVulkanFunctions = &vma_funcs,
            .instance = @ptrFromInt(@intFromEnum(self.instance.handle)),
            .vulkanApiVersion = api_version.toU32(),
        };

        const result = c.vmaCreateAllocator(&vma_alloc_create_info, &self.vma_allocator);
        if (result != c.VK_SUCCESS)
            return Error.FailedToCreateVmaAllocator;

        try self.deletion_queue.push(self.allocator, c.vmaDestroyAllocator, .{self.vma_allocator});
    }

    fn chooseSwapchainSurfaceFormat(formats: []const vk.SurfaceFormatKHR) !vk.SurfaceFormatKHR {
        for (formats) |format| {
            if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr)
                return format;
        }

        return Error.FailedToFindMatchingSwapchainSurfaceFormat;
    }

    fn chooseSwapchainPresentMode(present_modes: []const vk.PresentModeKHR) !vk.PresentModeKHR {
        // fifo - image taken from front of swapchain every time display refreshes
        // mailbox - like fifo, but when swapchain is full, old images are replaced with new ones
        // which allows for displaying images as fast as possible

        var found_fifo = false;
        for (present_modes) |mode| {
            if (mode == .fifo_khr)
                found_fifo = true;

            if (mode == .mailbox_khr)
                return mode;
        }

        std.debug.assert(found_fifo);

        return .fifo_khr;
    }

    fn chooseSwapchainExtent(self: *@This(), capabilities: *const vk.SurfaceCapabilitiesKHR) vk.Extent2D {
        if (capabilities.current_extent.width != std.math.maxInt(u32))
            return capabilities.current_extent;

        return .{
            .width = std.math.clamp(
                self.window.width,
                capabilities.min_image_extent.width,
                capabilities.max_image_extent.width,
            ),
            .height = std.math.clamp(
                self.window.height,
                capabilities.min_image_extent.height,
                capabilities.max_image_extent.height,
            ),
        };
    }

    fn chooseSwapcainMinImageCount(capabilities: *const vk.SurfaceCapabilitiesKHR) u32 {
        var min_img_count = @max(3, capabilities.min_image_count);

        if (capabilities.max_image_count > 0 and capabilities.max_image_count < min_img_count)
            min_img_count = capabilities.max_image_count;

        return min_img_count;
    }

    fn createImageView(self: *@This(), image: *const vk.Image, format: vk.Format) !vk.ImageView {
        const create_info = vk.ImageViewCreateInfo{
            .image = image.*,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .r, .g = .g, .b = .b, .a = .a },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        return try self.device.createImageView(&create_info, null);
    }

    fn createImageViews(self: *@This()) !void {
        std.debug.assert(self.swapchain_image_views.items.len == 0);

        for (self.swapchain_images) |image| {
            try self.swapchain_image_views.append(
                self.allocator,
                try self.createImageView(&image, self.swapchain_surface_format.format),
            );

            try self.deletion_queue.push(self.allocator, Device.destroyImageView, .{ self.device, self.swapchain_image_views.getLast(), null });
        }
    }

    fn createSwapchain(self: *@This()) !void {
        const surface_capabilities = try self.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(self.physical_device, self.surface);
        self.swapchain_extent = self.chooseSwapchainExtent(&surface_capabilities);
        const min_img_count = chooseSwapcainMinImageCount(&surface_capabilities);

        const available_formats = try self.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(
            self.physical_device,
            self.surface,
            self.allocator,
        );
        defer self.allocator.free(available_formats);

        self.swapchain_surface_format = try chooseSwapchainSurfaceFormat(available_formats);

        const available_present_modes = try self.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
            self.physical_device,
            self.surface,
            self.allocator,
        );
        defer self.allocator.free(available_present_modes);

        const present_mode = try chooseSwapchainPresentMode(available_present_modes);

        const create_info = vk.SwapchainCreateInfoKHR{
            .surface = self.surface,
            .min_image_count = min_img_count,
            .image_format = self.swapchain_surface_format.format,
            .image_color_space = self.swapchain_surface_format.color_space,
            .image_extent = self.swapchain_extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true },
            .image_sharing_mode = .exclusive,
            .pre_transform = surface_capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = .true,
            .old_swapchain = self.swapchain,
        };

        self.swapchain = try self.device.createSwapchainKHR(&create_info, null);

        self.swapchain_images = try self.device.getSwapchainImagesAllocKHR(self.swapchain, self.allocator);

        try self.deletion_queue.push(self.allocator, Device.destroySwapchainKHR, .{ self.device, self.swapchain, null });
        try self.deletion_queue.push(self.allocator, std.mem.Allocator.free, .{ self.allocator, self.swapchain_images });
    }

    fn clearSwapchain(self: *@This()) void {
        self.swapchain_image_views.clearRetainingCapacity();
    }

    fn recreateSwapchain(self: *@This()) !void {
        while (self.window.width == 0 or self.window.height == 0) {
            try sdlCheckBool(
                @src(),
                c.SDL_WaitEvent(&self.event),
                Error.SdlWaitEventFailed,
            );
        }

        self.device.deviceWaitIdle();

        self.clearSwapchain();

        try self.createSwapchain();
        try self.createImageViews();
    }

    pub fn init(self: *@This(), gpa: std.mem.Allocator, debug_mode: bool, window: *win.Window, app_name: [:0]const u8) !void {
        self.allocator = gpa;
        self.deletion_queue = try .initCapacity(self.allocator, 1);

        self.window = window;

        self.debug_messenger = null;
        self.swapchain_image_views = .empty;
        self.swapchain = .null_handle;

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
        try self.choosePhysicalDevice();
        try self.createLogicalDevice();
        try self.initVMA(base_wrapper);
        try self.createSwapchain();
        try self.createImageViews();
    }

    pub fn deinit(self: *@This()) void {
        self.swapchain_image_views.deinit(self.allocator);

        self.deletion_queue.deinit(self.allocator);
    }

    pub fn getSwapchainFormat(self: *@This(), window: *const win.Window) !TextureFormat {
        return try TextureFormat.fromSdl(c.SDL_GetGPUSwapchainTextureFormat(self.sdl_gpu_device, window.sdl_window));
    }
};
