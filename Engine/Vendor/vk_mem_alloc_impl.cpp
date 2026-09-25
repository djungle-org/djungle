#define VMA_IMPLEMENTATION
#define VMA_STATIC_VULKAN_FUNCTIONS 0
// vulkan-zig loads vulkan functions dynamically,
// so in the code vulkan-zig dynamically loaded functions are connected with vma
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 1
#include "vk_mem_alloc.h"
