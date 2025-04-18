package vma

import vk "vendor:vulkan"

foreign import "external/vma.lib"

import _c "core:c"

AMD_VULKAN_MEMORY_ALLOCATOR_H :: 1
VULKAN_VERSION :: 1003000
DEDICATED_ALLOCATION :: 1
BIND_MEMORY2 :: 1
MEMORY_BUDGET :: 1
BUFFER_DEVICE_ADDRESS :: 1
MEMORY_PRIORITY :: 1
EXTERNAL_MEMORY :: 1
CALL_PRE :: 1
CALL_POST :: 1
NOT_NULL_ :: 1
_ :: 1
STATS_STRING_ENABLED :: 1

Allocator :: ^AllocatorT
Pool :: ^PoolT
Allocation :: ^AllocationT
DefragmentationContext :: ^DefragmentationContextT
VirtualAllocation :: ^VirtualAllocationT
VirtualBlock :: ^VirtualBlockT
PFN_AllocateDeviceMemoryFunction :: proc(
	allocator: Allocator,
	memoryType: u32,
	memory: vk.DeviceMemory,
	size: vk.DeviceSize,
	pUserData: rawptr,
)
PFN_FreeDeviceMemoryFunction :: proc(
	allocator: Allocator,
	memoryType: u32,
	memory: vk.DeviceMemory,
	size: vk.DeviceSize,
	pUserData: rawptr,
)

AllocatorCreateFlags :: distinct bit_set[AllocatorCreateFlagBits;u32]
AllocatorCreateFlagBits :: enum u32 {
	AllocatorCreateExternallySynchronizedBit  = 0,
	AllocatorCreateKhrDedicatedAllocationBit  = 1,
	AllocatorCreateKhrBindMemory2Bit          = 2,
	AllocatorCreateExtMemoryBudgetBit         = 3,
	AllocatorCreateAmdDeviceCoherentMemoryBit = 4,
	AllocatorCreateBufferDeviceAddressBit     = 5,
	AllocatorCreateExtMemoryPriorityBit       = 6,
	MaxEnum                                   = 7,
}

MemoryUsage :: enum i32 {
	UNKNOWN              = 0,
	GPU_ONLY             = 1,
	CPU_ONLY             = 2,
	CPU_TO_GPU           = 3,
	GPU_TO_CPU           = 4,
	CPU_COPY             = 5,
	GPU_LAZILY_ALLOCATED = 6,
	AUTO                 = 7,
	AUTO_PREFER_DEVICE   = 8,
	AUTO_PREFER_HOST     = 9,
}

AllocationCreateFlags :: distinct bit_set[AllocationCreateFlagBits; u32]
AllocationCreateFlagBits :: enum u32 {
	DEDICATED_MEMORY                   = 0,
	NEVER_ALLOCATE                     = 1,
	CREATE_MAPPED                      = 2,
	USER_DATA_COPY_STRING              = 5,
	UPPER_ADDRESS                      = 6,
	DONT_BIND                          = 7,
	WITHIN_BUDGET                      = 8,
	CAN_ALIAS                          = 11,
	HOST_ACCESS_SEQUENTIAL_WRITE       = 10,
	HOST_ACCESS_RANDOM                 = 11,
	HOST_ACCESS_ALLOW_TRANSFER_INSTEAD = 12,
	STRATEGY_MIN_MEMORY                = 16,
	STRATEGY_MIN_TIME                  = 17,
	STRATEGY_MIN_OFFSET                = 18,
	STRATEGY_BEST_FIT                  = STRATEGY_MIN_MEMORY,
	STRATEGY_FIRST_FIT                 = STRATEGY_MIN_TIME,
	STRATEGY_MASK                      = STRATEGY_MIN_MEMORY | STRATEGY_MIN_TIME | STRATEGY_MIN_OFFSET,
}

PoolCreateFlags :: distinct bit_set[PoolCreateFlagBits; u32]
PoolCreateFlagBits :: enum u32 {
	IGNORE_BUFFER_IMAGE_GRANULARITY = 1,
	LINEAR                          = 2,
	ALGORITHM_MASK                  = IGNORE_BUFFER_IMAGE_GRANULARITY | LINEAR,
}

DefragmentationFlags :: distinct bit_set[DefragmentationFlagBits; u32]
DefragmentationFlagBits :: enum u32 {
	FAST      = 0,
	BALANCED  = 1,
	FULL      = 2,
	EXTENSIVE = 3,
	MASK      = FAST | BALANCED | FULL | EXTENSIVE,
}

DefragmentationMoveOperation :: enum u32 {
	COPY    = 0,
	IGNORE  = 1,
	DESTROY = 2,
}

VirtualBlockCreateFlags :: distinct bit_set[VirtualBlockCreateFlagBits; u32]
VirtualBlockCreateFlagBits :: enum u32 {
	LINEAR = 0,
	MASK   = LINEAR,
}

VirtualAllocationCreateFlags :: distinct bit_set[VirtualAllocationCreateFlagBits; u32]
VirtualAllocationCreateFlagBits :: enum u32 {
	UPPER_ADDRESS = 0,
	MIN_MEMORY    = 1,
	MIN_TIME      = 2,
	MIN_OFFSET    = 3,
	MASK          = UPPER_ADDRESS | MIN_MEMORY | MIN_TIME | MIN_OFFSET,
}

AllocatorT :: struct {}

PoolT :: struct {}

AllocationT :: struct {}

DefragmentationContextT :: struct {}

VirtualAllocationT :: struct {}

VirtualBlockT :: struct {}

DeviceMemoryCallbacks :: struct {
	pfnAllocate: PFN_AllocateDeviceMemoryFunction,
	pfnFree:     PFN_FreeDeviceMemoryFunction,
	pUserData:   rawptr,
}

VulkanFunctions :: struct {
	vkGetInstanceProcAddr:                   vk.ProcGetInstanceProcAddr,
	vkGetDeviceProcAddr:                     vk.ProcGetDeviceProcAddr,
	vkGetPhysicalDeviceProperties:           vk.ProcGetPhysicalDeviceProperties,
	vkGetPhysicalDeviceMemoryProperties:     vk.ProcGetPhysicalDeviceMemoryProperties,
	vkAllocateMemory:                        vk.ProcAllocateMemory,
	vkFreeMemory:                            vk.ProcFreeMemory,
	vkMapMemory:                             vk.ProcMapMemory,
	vkUnmapMemory:                           vk.ProcUnmapMemory,
	vkFlushMappedMemoryRanges:               vk.ProcFlushMappedMemoryRanges,
	vkInvalidateMappedMemoryRanges:          vk.ProcInvalidateMappedMemoryRanges,
	vkBindBufferMemory:                      vk.ProcBindBufferMemory,
	vkBindImageMemory:                       vk.ProcBindImageMemory,
	vkGetBufferMemoryRequirements:           vk.ProcGetBufferMemoryRequirements,
	vkGetImageMemoryRequirements:            vk.ProcGetImageMemoryRequirements,
	vkCreateBuffer:                          vk.ProcCreateBuffer,
	vkDestroyBuffer:                         vk.ProcDestroyBuffer,
	vkCreateImage:                           vk.ProcCreateImage,
	vkDestroyImage:                          vk.ProcDestroyImage,
	vkCmdCopyBuffer:                         vk.ProcCmdCopyBuffer,
	vkGetBufferMemoryRequirements2KHR:       vk.ProcGetBufferMemoryRequirements2KHR,
	vkGetImageMemoryRequirements2KHR:        vk.ProcGetImageMemoryRequirements2KHR,
	vkBindBufferMemory2KHR:                  vk.ProcBindBufferMemory2KHR,
	vkBindImageMemory2KHR:                   vk.ProcBindImageMemory2KHR,
	vkGetPhysicalDeviceMemoryProperties2KHR: vk.ProcGetPhysicalDeviceMemoryProperties2KHR,
	vkGetDeviceBufferMemoryRequirements:     vk.ProcGetDeviceBufferMemoryRequirements,
	vkGetDeviceImageMemoryRequirements:      vk.ProcGetDeviceImageMemoryRequirements,
}

AllocatorCreateInfo :: struct {
	flags:                          AllocatorCreateFlags,
	physicalDevice:                 vk.PhysicalDevice,
	device:                         vk.Device,
	preferredLargeHeapBlockSize:    vk.DeviceSize,
	pAllocationCallbacks:           ^vk.AllocationCallbacks,
	pDeviceMemoryCallbacks:         ^DeviceMemoryCallbacks,
	pHeapSizeLimit:                 ^vk.DeviceSize,
	pVulkanFunctions:               ^VulkanFunctions,
	instance:                       vk.Instance,
	vulkanApiVersion:               u32,
	pTypeExternalMemoryHandleTypes: ^vk.ExternalMemoryHandleTypeFlagsKHR,
}

AllocatorInfo :: struct {
	instance:       vk.Instance,
	physicalDevice: vk.PhysicalDevice,
	device:         vk.Device,
}

Statistics :: struct {
	blockCount:      u32,
	allocationCount: u32,
	blockBytes:      vk.DeviceSize,
	allocationBytes: vk.DeviceSize,
}

DetailedStatistics :: struct {
	statistics:         Statistics,
	unusedRangeCount:   u32,
	allocationSizeMin:  vk.DeviceSize,
	allocationSizeMax:  vk.DeviceSize,
	unusedRangeSizeMin: vk.DeviceSize,
	unusedRangeSizeMax: vk.DeviceSize,
}

TotalStatistics :: struct {
	memoryType: [vk.MAX_MEMORY_TYPES]DetailedStatistics,
	memoryHeap: [vk.MAX_MEMORY_HEAPS]DetailedStatistics,
	total:      DetailedStatistics,
}

Budget :: struct {
	statistics: Statistics,
	usage:      vk.DeviceSize,
	budget:     vk.DeviceSize,
}

AllocationCreateInfo :: struct {
	flags:          AllocationCreateFlags,
	usage:          MemoryUsage,
	requiredFlags:  vk.MemoryPropertyFlags,
	preferredFlags: vk.MemoryPropertyFlags,
	memoryTypeBits: u32,
	pool:           Pool,
	pUserData:      rawptr,
	priority:       _c.float,
}

PoolCreateInfo :: struct {
	memoryTypeIndex:        u32,
	flags:                  PoolCreateFlags,
	blockSize:              vk.DeviceSize,
	minBlockCount:          _c.size_t,
	maxBlockCount:          _c.size_t,
	priority:               _c.float,
	minAllocationAlignment: vk.DeviceSize,
	pMemoryAllocateNext:    rawptr,
}

AllocationInfo :: struct {
	memoryType:   u32,
	deviceMemory: vk.DeviceMemory,
	offset:       vk.DeviceSize,
	size:         vk.DeviceSize,
	pMappedData:  rawptr,
	pUserData:    rawptr,
	pName:        cstring,
}

DefragmentationInfo :: struct {
	flags:                 DefragmentationFlags,
	pool:                  Pool,
	maxBytesPerPass:       vk.DeviceSize,
	maxAllocationsPerPass: u32,
}

DefragmentationMove :: struct {
	operation:        DefragmentationMoveOperation,
	srcAllocation:    Allocation,
	dstTmpAllocation: Allocation,
}

DefragmentationPassMoveInfo :: struct {
	moveCount: u32,
	pMoves:    ^DefragmentationMove,
}

DefragmentationStats :: struct {
	bytesMoved:              vk.DeviceSize,
	bytesFreed:              vk.DeviceSize,
	allocationsMoved:        u32,
	deviceMemoryBlocksFreed: u32,
}

VirtualBlockCreateInfo :: struct {
	size:                 vk.DeviceSize,
	flags:                VirtualBlockCreateFlags,
	pAllocationCallbacks: ^vk.AllocationCallbacks,
}

VirtualAllocationCreateInfo :: struct {
	size:      vk.DeviceSize,
	alignment: vk.DeviceSize,
	flags:     VirtualAllocationCreateFlags,
	pUserData: rawptr,
}

VirtualAllocationInfo :: struct {
	offset:    vk.DeviceSize,
	size:      vk.DeviceSize,
	pUserData: rawptr,
}


create_vulkan_functions :: proc() -> VulkanFunctions {
	return {
		vkGetInstanceProcAddr = vk.GetInstanceProcAddr,
		vkGetDeviceProcAddr = vk.GetDeviceProcAddr,
		vkAllocateMemory = vk.AllocateMemory,
		vkBindBufferMemory = vk.BindBufferMemory,
		vkBindBufferMemory2KHR = vk.BindBufferMemory2,
		vkBindImageMemory = vk.BindImageMemory,
		vkBindImageMemory2KHR = vk.BindImageMemory2,
		vkCmdCopyBuffer = vk.CmdCopyBuffer,
		vkCreateBuffer = vk.CreateBuffer,
		vkCreateImage = vk.CreateImage,
		vkDestroyBuffer = vk.DestroyBuffer,
		vkDestroyImage = vk.DestroyImage,
		vkFlushMappedMemoryRanges = vk.FlushMappedMemoryRanges,
		vkFreeMemory = vk.FreeMemory,
		vkGetBufferMemoryRequirements = vk.GetBufferMemoryRequirements,
		vkGetBufferMemoryRequirements2KHR = vk.GetBufferMemoryRequirements2,
		vkGetImageMemoryRequirements = vk.GetImageMemoryRequirements,
		vkGetImageMemoryRequirements2KHR = vk.GetImageMemoryRequirements2,
		vkGetPhysicalDeviceMemoryProperties = vk.GetPhysicalDeviceMemoryProperties,
		vkGetPhysicalDeviceMemoryProperties2KHR = vk.GetPhysicalDeviceMemoryProperties2,
		vkGetPhysicalDeviceProperties = vk.GetPhysicalDeviceProperties,
		vkInvalidateMappedMemoryRanges = vk.InvalidateMappedMemoryRanges,
		vkMapMemory = vk.MapMemory,
		vkUnmapMemory = vk.UnmapMemory,
	}
}

@(default_calling_convention = "c")
foreign vma {

	@(link_name = "vkGetInstanceProcAddr")
	vkGetInstanceProcAddr: vk.ProcGetInstanceProcAddr

	@(link_name = "vkGetDeviceProcAddr")
	vkGetDeviceProcAddr: vk.ProcGetDeviceProcAddr

	@(link_name = "vkGetPhysicalDeviceProperties")
	vkGetPhysicalDeviceProperties: vk.ProcGetPhysicalDeviceProperties

	@(link_name = "vkGetPhysicalDeviceMemoryProperties")
	vkGetPhysicalDeviceMemoryProperties: vk.ProcGetPhysicalDeviceMemoryProperties

	@(link_name = "vkAllocateMemory")
	vkAllocateMemory: vk.ProcAllocateMemory

	@(link_name = "vkFreeMemory")
	vkFreeMemory: vk.ProcFreeMemory

	@(link_name = "vkMapMemory")
	vkMapMemory: vk.ProcMapMemory

	@(link_name = "vkUnmapMemory")
	vkUnmapMemory: vk.ProcUnmapMemory

	@(link_name = "vkFlushMappedMemoryRanges")
	vkFlushMappedMemoryRanges: vk.ProcFlushMappedMemoryRanges

	@(link_name = "vkInvalidateMappedMemoryRanges")
	vkInvalidateMappedMemoryRanges: vk.ProcInvalidateMappedMemoryRanges

	@(link_name = "vkBindBufferMemory")
	vkBindBufferMemory: vk.ProcBindBufferMemory

	@(link_name = "vkBindImageMemory")
	vkBindImageMemory: vk.ProcBindImageMemory

	@(link_name = "vkGetBufferMemoryRequirements")
	vkGetBufferMemoryRequirements: vk.ProcGetBufferMemoryRequirements

	@(link_name = "vkGetImageMemoryRequirements")
	vkGetImageMemoryRequirements: vk.ProcGetImageMemoryRequirements

	@(link_name = "vkCreateBuffer")
	vkCreateBuffer: vk.ProcCreateBuffer

	@(link_name = "vkDestroyBuffer")
	vkDestroyBuffer: vk.ProcDestroyBuffer

	@(link_name = "vkCreateImage")
	vkCreateImage: vk.ProcCreateImage

	@(link_name = "vkDestroyImage")
	vkDestroyImage: vk.ProcDestroyImage

	@(link_name = "vkCmdCopyBuffer")
	vkCmdCopyBuffer: vk.ProcCmdCopyBuffer

	@(link_name = "vkGetBufferMemoryRequirements2")
	vkGetBufferMemoryRequirements2: vk.ProcGetBufferMemoryRequirements2

	@(link_name = "vkGetImageMemoryRequirements2")
	vkGetImageMemoryRequirements2: vk.ProcGetImageMemoryRequirements2

	@(link_name = "vkBindBufferMemory2")
	vkBindBufferMemory2: vk.ProcBindBufferMemory2

	@(link_name = "vkBindImageMemory2")
	vkBindImageMemory2: vk.ProcBindImageMemory2

	@(link_name = "vkGetPhysicalDeviceMemoryProperties2")
	vkGetPhysicalDeviceMemoryProperties2: vk.ProcGetPhysicalDeviceMemoryProperties2

	@(link_name = "vmaCreateAllocator")
	create_allocator :: proc(
		pCreateInfo: ^AllocatorCreateInfo,
		pAllocator: ^Allocator,
	) -> vk.Result ---

	@(link_name = "vmaDestroyAllocator")
	destroy_allocator :: proc(allocator: Allocator) ---

	@(link_name = "vmaGetAllocatorInfo")
	get_allocator_info :: proc(allocator: Allocator, pAllocatorInfo: ^AllocatorInfo) ---

	@(link_name = "vmaGetPhysicalDeviceProperties")
	get_physical_device_properties :: proc(
		allocator: Allocator,
		ppPhysicalDeviceProperties: ^^vk.PhysicalDeviceProperties,
	) ---

	@(link_name = "vmaGetMemoryProperties")
	get_memory_properties :: proc(
		allocator: Allocator,
		ppPhysicalDeviceMemoryProperties: ^^vk.PhysicalDeviceMemoryProperties,
	) ---

	@(link_name = "vmaGetMemoryTypeProperties")
	get_memory_type_properties :: proc(
		allocator: Allocator,
		memoryTypeIndex: u32,
		pFlags: ^vk.MemoryPropertyFlags,
	) ---

	@(link_name = "vmaSetCurrentFrameIndex")
	set_current_frame_index :: proc(allocator: Allocator, frameIndex: u32) ---

	@(link_name = "vmaCalculateStatistics")
	calculate_statistics :: proc(allocator: Allocator, pStats: ^TotalStatistics) ---

	@(link_name = "vmaGetHeapBudgets")
	get_heap_budgets :: proc(allocator: Allocator, pBudgets: ^Budget) ---

	@(link_name = "vmaFindMemoryTypeIndex")
	find_memory_type_index :: proc(
		allocator: Allocator,
		memoryTypeBits: u32,
		pAllocationCreateInfo: ^AllocationCreateInfo,
		pMemoryTypeIndex: ^u32,
	) -> vk.Result ---

	@(link_name = "vmaFindMemoryTypeIndexForBufferInfo")
	find_memory_type_index_for_buffer_info :: proc(
		allocator: Allocator,
		pBufferCreateInfo: ^vk.BufferCreateInfo,
		pAllocationCreateInfo: ^AllocationCreateInfo,
		pMemoryTypeIndex: ^u32,
	) -> vk.Result ---

	@(link_name = "vmaFindMemoryTypeIndexForImageInfo")
	find_memory_type_index_for_image_info :: proc(
		allocator: Allocator,
		pImageCreateInfo: ^vk.ImageCreateInfo,
		pAllocationCreateInfo: ^AllocationCreateInfo,
		pMemoryTypeIndex: ^u32,
	) -> vk.Result ---

	@(link_name = "vmaCreatePool")
	create_pool :: proc(
		allocator: Allocator,
		pCreateInfo: ^PoolCreateInfo,
		pPool: ^Pool,
	) -> vk.Result ---

	@(link_name = "vmaDestroyPool")
	destroy_pool :: proc(allocator: Allocator, pool: Pool) ---

	@(link_name = "vmaGetPoolStatistics")
	get_pool_statistics :: proc(
		allocator: Allocator,
		pool: Pool,
		pPoolStats: ^Statistics,
	) ---

	@(link_name = "vmaCalculatePoolStatistics")
	calculate_pool_statistics :: proc(
		allocator: Allocator,
		pool: Pool,
		pPoolStats: ^DetailedStatistics,
	) ---

	@(link_name = "vmaCheckPoolCorruption")
	check_pool_corruption :: proc(allocator: Allocator, pool: Pool) -> vk.Result ---

	@(link_name = "vmaGetPoolName")
	get_pool_name :: proc(allocator: Allocator, pool: Pool, ppName: ^cstring) ---

	@(link_name = "vmaSetPoolName")
	set_pool_name :: proc(allocator: Allocator, pool: Pool, pName: cstring) ---

	@(link_name = "vmaAllocateMemory")
	allocate_memory :: proc(
		allocator: Allocator,
		memoryRequirements: ^vk.MemoryRequirements,
		pCreateInfo: ^AllocationCreateInfo,
		pAllocation: ^Allocation,
		pAllocationInfo: ^AllocationInfo,
	) -> vk.Result ---

	@(link_name = "vmaAllocateMemoryPages")
	allocate_memory_pages :: proc(
		allocator: Allocator,
		memoryRequirements: ^vk.MemoryRequirements,
		pCreateInfo: ^AllocationCreateInfo,
		allocationCount: _c.size_t,
		pAllocations: ^Allocation,
		pAllocationInfo: ^AllocationInfo,
	) -> vk.Result ---

	@(link_name = "vmaAllocateMemoryForBuffer")
	allocate_memory_for_buffer :: proc(
		allocator: Allocator,
		buffer: vk.Buffer,
		pCreateInfo: ^AllocationCreateInfo,
		pAllocation: ^Allocation,
		pAllocationInfo: ^AllocationInfo,
	) -> vk.Result ---

	@(link_name = "vmaAllocateMemoryForImage")
	allocate_memory_for_image :: proc(
		allocator: Allocator,
		image: vk.Image,
		pCreateInfo: ^AllocationCreateInfo,
		pAllocation: ^Allocation,
		pAllocationInfo: ^AllocationInfo,
	) -> vk.Result ---

	@(link_name = "vmaFreeMemory")
	free_memory :: proc(allocator: Allocator, allocation: Allocation) ---

	@(link_name = "vmaFreeMemoryPages")
	free_memory_pages :: proc(
		allocator: Allocator,
		allocationCount: _c.size_t,
		pAllocations: ^Allocation,
	) ---

	@(link_name = "vmaGetAllocationInfo")
	get_allocation_info :: proc(
		allocator: Allocator,
		allocation: Allocation,
		pAllocationInfo: ^AllocationInfo,
	) ---

	@(link_name = "vmaSetAllocationUserData")
	set_allocation_user_data :: proc(
		allocator: Allocator,
		allocation: Allocation,
		pUserData: rawptr,
	) ---

	@(link_name = "vmaSetAllocationName")
	set_allocation_name :: proc(
		allocator: Allocator,
		allocation: Allocation,
		pName: cstring,
	) ---

	@(link_name = "vmaGetAllocationMemoryProperties")
	get_allocation_memory_properties :: proc(
		allocator: Allocator,
		allocation: Allocation,
		pFlags: ^vk.MemoryPropertyFlags,
	) ---

	@(link_name = "vmaMapMemory")
	map_memory :: proc(
		allocator: Allocator,
		allocation: Allocation,
		ppData: ^rawptr,
	) -> vk.Result ---

	@(link_name = "vmaUnmapMemory")
	unmap_memory :: proc(allocator: Allocator, allocation: Allocation) ---

	@(link_name = "vmaFlushAllocation")
	flush_allocation :: proc(
		allocator: Allocator,
		allocation: Allocation,
		offset: vk.DeviceSize,
		size: vk.DeviceSize,
	) -> vk.Result ---

	@(link_name = "vmaInvalidateAllocation")
	invalidate_allocation :: proc(
		allocator: Allocator,
		allocation: Allocation,
		offset: vk.DeviceSize,
		size: vk.DeviceSize,
	) -> vk.Result ---

	@(link_name = "vmaFlushAllocations")
	flush_allocations :: proc(
		allocator: Allocator,
		allocationCount: u32,
		allocations: ^Allocation,
		offsets: ^vk.DeviceSize,
		sizes: ^vk.DeviceSize,
	) -> vk.Result ---

	@(link_name = "vmaInvalidateAllocations")
	invalidate_allocations :: proc(
		allocator: Allocator,
		allocationCount: u32,
		allocations: ^Allocation,
		offsets: ^vk.DeviceSize,
		sizes: ^vk.DeviceSize,
	) -> vk.Result ---

	@(link_name = "vmaCheckCorruption")
	check_corruption :: proc(allocator: Allocator, memoryTypeBits: u32) -> vk.Result ---

	@(link_name = "vmaBeginDefragmentation")
	begin_defragmentation :: proc(
		allocator: Allocator,
		pInfo: ^DefragmentationInfo,
		pContext: ^DefragmentationContext,
	) -> vk.Result ---

	@(link_name = "vmaEndDefragmentation")
	end_defragmentation :: proc(
		allocator: Allocator,
		_context: DefragmentationContext,
		pStats: ^DefragmentationStats,
	) ---

	@(link_name = "vmaBeginDefragmentationPass")
	begin_defragmentation_pass :: proc(
		allocator: Allocator,
		_context: DefragmentationContext,
		pPassInfo: ^DefragmentationPassMoveInfo,
	) -> vk.Result ---

	@(link_name = "vmaEndDefragmentationPass")
	end_defragmentation_pass :: proc(
		allocator: Allocator,
		_context: DefragmentationContext,
		pPassInfo: ^DefragmentationPassMoveInfo,
	) -> vk.Result ---

	@(link_name = "vmaBindBufferMemory")
	bind_buffer_memory :: proc(
		allocator: Allocator,
		allocation: Allocation,
		buffer: vk.Buffer,
	) -> vk.Result ---

	@(link_name = "vmaBindBufferMemory2")
	bind_buffer_memory2 :: proc(
		allocator: Allocator,
		allocation: Allocation,
		allocationLocalOffset: vk.DeviceSize,
		buffer: vk.Buffer,
		pNext: rawptr,
	) -> vk.Result ---

	@(link_name = "vmaBindImageMemory")
	bind_image_memory :: proc(
		allocator: Allocator,
		allocation: Allocation,
		image: vk.Image,
	) -> vk.Result ---

	@(link_name = "vmaBindImageMemory2")
	bind_image_memory2 :: proc(
		allocator: Allocator,
		allocation: Allocation,
		allocationLocalOffset: vk.DeviceSize,
		image: vk.Image,
		pNext: rawptr,
	) -> vk.Result ---

	@(link_name = "vmaCreateBuffer")
	create_buffer :: proc(
		allocator: Allocator,
		pBufferCreateInfo: ^vk.BufferCreateInfo,
		pAllocationCreateInfo: ^AllocationCreateInfo,
		pBuffer: ^vk.Buffer,
		pAllocation: ^Allocation,
		pAllocationInfo: ^AllocationInfo,
	) -> vk.Result ---

	@(link_name = "vmaCreateBufferWithAlignment")
	create_buffer_with_alignment :: proc(
		allocator: Allocator,
		pBufferCreateInfo: ^vk.BufferCreateInfo,
		pAllocationCreateInfo: ^AllocationCreateInfo,
		minAlignment: vk.DeviceSize,
		pBuffer: ^vk.Buffer,
		pAllocation: ^Allocation,
		pAllocationInfo: ^AllocationInfo,
	) -> vk.Result ---

	@(link_name = "vmaCreateAliasingBuffer")
	create_aliasing_buffer :: proc(
		allocator: Allocator,
		allocation: Allocation,
		pBufferCreateInfo: ^vk.BufferCreateInfo,
		pBuffer: ^vk.Buffer,
	) -> vk.Result ---

	@(link_name = "vmaDestroyBuffer")
	destroy_buffer :: proc(
		allocator: Allocator,
		buffer: vk.Buffer,
		allocation: Allocation,
	) ---

	@(link_name = "vmaCreateImage")
	create_image :: proc(
		allocator: Allocator,
		pImageCreateInfo: ^vk.ImageCreateInfo,
		pAllocationCreateInfo: ^AllocationCreateInfo,
		pImage: ^vk.Image,
		pAllocation: ^Allocation,
		pAllocationInfo: ^AllocationInfo,
	) -> vk.Result ---

	@(link_name = "vmaCreateAliasingImage")
	create_aliasing_image :: proc(
		allocator: Allocator,
		allocation: Allocation,
		pImageCreateInfo: ^vk.ImageCreateInfo,
		pImage: ^vk.Image,
	) -> vk.Result ---

	@(link_name = "vmaDestroyImage")
	destroy_image :: proc(allocator: Allocator, image: vk.Image, allocation: Allocation) ---

	@(link_name = "vmaCreateVirtualBlock")
	create_virtual_block :: proc(
		pCreateInfo: ^VirtualBlockCreateInfo,
		pVirtualBlock: ^VirtualBlock,
	) -> vk.Result ---

	@(link_name = "vmaDestroyVirtualBlock")
	destroy_virtual_block :: proc(virtualBlock: VirtualBlock) ---

	@(link_name = "vmaIsVirtualBlockEmpty")
	is_virtual_block_empty :: proc(virtualBlock: VirtualBlock) -> bool ---

	@(link_name = "vmaGetVirtualAllocationInfo")
	get_virtual_allocation_info :: proc(
		virtualBlock: VirtualBlock,
		allocation: VirtualAllocation,
		pVirtualAllocInfo: ^VirtualAllocationInfo,
	) ---

	@(link_name = "vmaVirtualAllocate")
	virtual_allocate :: proc(
		virtualBlock: VirtualBlock,
		pCreateInfo: ^VirtualAllocationCreateInfo,
		pAllocation: ^VirtualAllocation,
		pOffset: ^vk.DeviceSize,
	) -> vk.Result ---

	@(link_name = "vmaVirtualFree")
	virtual_free :: proc(virtualBlock: VirtualBlock, allocation: VirtualAllocation) ---

	@(link_name = "vmaClearVirtualBlock")
	clear_virtual_block :: proc(virtualBlock: VirtualBlock) ---

	@(link_name = "vmaSetVirtualAllocationUserData")
	set_virtual_allocation_user_data :: proc(
		virtualBlock: VirtualBlock,
		allocation: VirtualAllocation,
		pUserData: rawptr,
	) ---

	@(link_name = "vmaGetVirtualBlockStatistics")
	get_virtual_block_statistics :: proc(virtualBlock: VirtualBlock, pStats: ^Statistics) ---

	@(link_name = "vmaCalculateVirtualBlockStatistics")
	calculate_virtual_block_statistics :: proc(
		virtualBlock: VirtualBlock,
		pStats: ^DetailedStatistics,
	) ---

	@(link_name = "vmaBuildVirtualBlockStatsString")
	build_virtual_block_stats_string :: proc(
		virtualBlock: VirtualBlock,
		ppStatsString: ^cstring,
		detailedMap: bool,
	) ---

	@(link_name = "vmaFreeVirtualBlockStatsString")
	free_virtual_block_stats_string :: proc(
		virtualBlock: VirtualBlock,
		pStatsString: cstring,
	) ---

	@(link_name = "vmaBuildStatsString")
	build_stats_string :: proc(
		allocator: Allocator,
		ppStatsString: ^cstring,
		detailedMap: bool,
	) ---

	@(link_name = "vmaFreeStatsString")
	free_stats_string :: proc(allocator: Allocator, pStatsString: cstring) ---
}
