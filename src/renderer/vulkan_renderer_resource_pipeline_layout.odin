package renderer


//---------------------------------------------------------------------------//

import "core:hash"
import "core:log"
import "core:mem"

import vk "vendor:vulkan"

import "../common"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	NUM_DESCRIPTOR_SET_LAYOUTS :: 3

	//---------------------------------------------------------------------------//

	@(private)
	BackendPipelineLayoutResource :: struct {
		descriptor_set_layouts:       []vk.DescriptorSetLayout,
		descriptor_set_layout_hashes: []u32,
		vk_pipeline_layout:           vk.PipelineLayout,
	}


	//---------------------------------------------------------------------------//

	@(private = "file")
	DescriptorSetLayoutCacheEntry :: struct {
		ref_count:             u16,
		descriptor_set_layout: vk.DescriptorSetLayout,
	}
	//---------------------------------------------------------------------------//

	@(private = "file")
	INTERNAL: struct {
		descriptor_set_layout_cache: map[u32]DescriptorSetLayoutCacheEntry,
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_pipeline_layouts :: proc() {

		// Init the cache
		INTERNAL.descriptor_set_layout_cache = make(
			map[u32]DescriptorSetLayoutCacheEntry,
			1024,
			G_RENDERER_ALLOCATORS.main_allocator,
		)

		// Create an empty descriptor set layout when descriptor sets are skipped
		create_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = 0,
		}
		assert(
			vk.CreateDescriptorSetLayout(
				G_RENDERER.device,
				&create_info,
				nil,
				&G_RENDERER.empty_descriptor_set_layout,
			) ==
			.SUCCESS,
		)
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_pipeline_layout :: proc(
		p_ref: PipelineLayoutRef,
		p_pipeline_layout: ^PipelineLayoutResource,
	) -> (
		res: bool,
	) {

		// @TODO support for compute shaders

		vert_shader := get_shader(p_pipeline_layout.desc.vert_shader_ref)
		frag_shader := get_shader(p_pipeline_layout.desc.frag_shader_ref)

		// Determine the number of distinct descriptor sets used across stages
		num_descriptor_sets_used := 0
		for descriptor_set in vert_shader.vk_descriptor_sets {
			num_descriptor_sets_used += 1
		}

		for descriptor_set in frag_shader.vk_descriptor_sets {
			is_duplicate := false
			for vert_descriptor_set in vert_shader.vk_descriptor_sets {
				if descriptor_set.set == vert_descriptor_set.set {
					is_duplicate = true
					break
				}
			}
			if is_duplicate == false {
				num_descriptor_sets_used += 1
			}
		}

		p_pipeline_layout.descriptor_set_layouts = make(
			[]vk.DescriptorSetLayout,
			num_descriptor_sets_used,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		p_pipeline_layout.descriptor_set_layout_hashes = make(
			[]u32,
			num_descriptor_sets_used,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)

		defer if res == false {
			delete(
				p_pipeline_layout.descriptor_set_layouts,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
			delete(
				p_pipeline_layout.descriptor_set_layout_hashes,
				G_RENDERER_ALLOCATORS.resource_allocator,
			)
		}

		bindings_per_set := make(
			map[u8][dynamic]vk.DescriptorSetLayoutBinding,
			num_descriptor_sets_used,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer {
			for set, bindings in bindings_per_set {
				delete(bindings)
			}
			delete(bindings_per_set)
		}

		texture_name_by_slot := make(map[u32]common.Name, 32, G_RENDERER_ALLOCATORS.temp_allocator)
		defer delete(texture_name_by_slot)

		// Gather vertex shader descriptor info
		for descriptor_set in &vert_shader.vk_descriptor_sets {

			set_number := descriptor_set.set
			if (set_number in bindings_per_set) == false {
				bindings_per_set[set_number] = make(
					[dynamic]vk.DescriptorSetLayoutBinding,
					G_RENDERER_ALLOCATORS.temp_allocator,
				)
			}

			set_bindings := &bindings_per_set[set_number]

			for descriptor in descriptor_set.descriptors {
				layout_binding := vk.DescriptorSetLayoutBinding {
					binding = descriptor.binding,
					descriptorCount = descriptor.count,
					descriptorType = descriptor.type,
					stageFlags = {.VERTEX},
					pImmutableSamplers = raw_data(VK_BINDLESS.immutable_samplers),
				}
				if descriptor.type == .SAMPLED_IMAGE || descriptor.type == .STORAGE_IMAGE {
					// Add a texture slot so we can later resolve name -> slot
					texture_name_by_slot[descriptor.binding] = descriptor.name
				}
				append(set_bindings, layout_binding)
			}

		}

		// Gather fragment shader descriptor info
		for descriptor_set in frag_shader.vk_descriptor_sets {

			set_number := descriptor_set.set
			if (set_number in bindings_per_set) == false {
				bindings_per_set[set_number] = make(
					[dynamic]vk.DescriptorSetLayoutBinding,
					G_RENDERER_ALLOCATORS.temp_allocator,
				)
			}

			set_bindings := &bindings_per_set[set_number]

			for descriptor in descriptor_set.descriptors {
				// Check if the vertex shader already added it, and if so, simply add the fragment stage
				already_used_by_vertex := false
				for existing_binding in set_bindings {
					if existing_binding.binding == descriptor.binding {
						existing_binding.stageFlags += {.FRAGMENT}
						assert(existing_binding.descriptorType == descriptor.type)
						already_used_by_vertex = true
						break
					}
				}

				if already_used_by_vertex {
					continue
				}

				layout_binding := vk.DescriptorSetLayoutBinding {
					binding = descriptor.binding,
					descriptorCount = descriptor.count,
					descriptorType = descriptor.type,
					stageFlags = {.FRAGMENT},
				}
				if descriptor.type == .SAMPLED_IMAGE || descriptor.type == .STORAGE_IMAGE {
					// Add a texture slot so we can later resolve name -> slot
					texture_name_by_slot[descriptor.binding] = descriptor.name
				}
				append(set_bindings, layout_binding)
			}
		}


		// Create the descriptor set layouts

		descriptor_set_layouts := make(
			[]vk.DescriptorSetLayout,
			NUM_DESCRIPTOR_SET_LAYOUTS,
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		descriptor_set_layouts[0] = G_RENDERER.empty_descriptor_set_layout
		descriptor_set_layouts[1] = G_RENDERER.empty_descriptor_set_layout
		descriptor_set_layouts[2] = G_RENDERER.empty_descriptor_set_layout

		uses_bindless_array :=
			.UsesBindlessArray in vert_shader.flags || .UsesBindlessArray in frag_shader.flags
		if uses_bindless_array {
			descriptor_set_layouts[2] = VK_BINDLESS.bindless_descriptor_set_layout
		}

		defer delete(descriptor_set_layouts, G_RENDERER_ALLOCATORS.temp_allocator)

		// Create the descriptor set layouts or get from cache
		{
			descriptor_set_layout_idx := 0
			for set, descriptor_set_bindings in bindings_per_set {

				// Get descriptor set layout from cache or create a new one
				hash := calculate_descriptor_layout_hash(descriptor_set_bindings)
				p_pipeline_layout.descriptor_set_layout_hashes[descriptor_set_layout_idx] = hash

				if hash in INTERNAL.descriptor_set_layout_cache {
					// Grab the descriptor set layout and increment ref count
					cache_entry := &INTERNAL.descriptor_set_layout_cache[hash]
					cache_entry.ref_count += 1
					p_pipeline_layout.descriptor_set_layouts[descriptor_set_layout_idx] =
						cache_entry.descriptor_set_layout
					descriptor_set_layouts[set] = cache_entry.descriptor_set_layout
				} else {
					create_info := vk.DescriptorSetLayoutCreateInfo {
						sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
						bindingCount = u32(len(descriptor_set_bindings)),
						pBindings    = raw_data(descriptor_set_bindings),
					}

					if vk.CreateDescriptorSetLayout(
						   G_RENDERER.device,
						   &create_info,
						   nil,
						   &descriptor_set_layouts[set],
					   ) !=
					   .SUCCESS {
						log.warn("Failed to create descriptor set layout")
						return false
					}
					// Add entry to the cache
					INTERNAL.descriptor_set_layout_cache[hash] = {
						ref_count             = 1,
						descriptor_set_layout = descriptor_set_layouts[set],
					}

					p_pipeline_layout.descriptor_set_layouts[descriptor_set_layout_idx] =
						descriptor_set_layouts[set]

				}

				descriptor_set_layout_idx += 1
			}
		}
		// Create pipeline layout
		{
			create_info := vk.PipelineLayoutCreateInfo {
				sType          = .PIPELINE_LAYOUT_CREATE_INFO,
				pSetLayouts    = raw_data(descriptor_set_layouts),
				setLayoutCount = u32(len(descriptor_set_layouts)),
			}

			if vk.CreatePipelineLayout(
				   G_RENDERER.device,
				   &create_info,
				   nil,
				   &p_pipeline_layout.vk_pipeline_layout,
			   ) !=
			   .SUCCESS {
				log.warn("Failed to create pipeline layout")
				return false
			}
		}

		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_pipeline_layout :: proc(p_pipeline_layout: ^PipelineLayoutResource) {
		for hash in p_pipeline_layout.descriptor_set_layout_hashes {
			cache_entry := &INTERNAL.descriptor_set_layout_cache[hash]
			cache_entry.ref_count -= 1
			if cache_entry.ref_count == 0 {
				vk.DestroyDescriptorSetLayout(
					G_RENDERER.device,
					cache_entry.descriptor_set_layout,
					nil,
				)
				delete_key(&INTERNAL.descriptor_set_layout_cache, hash)
			}
		}
		delete(p_pipeline_layout.descriptor_set_layouts, G_RENDERER_ALLOCATORS.resource_allocator)
		delete(
			p_pipeline_layout.descriptor_set_layout_hashes,
			G_RENDERER_ALLOCATORS.resource_allocator,
		)
		vk.DestroyPipelineLayout(G_RENDERER.device, p_pipeline_layout.vk_pipeline_layout, nil)

	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	DescriptorLayoutBindingHashEntry :: struct {
		type:  u32,
		slot:  u32,
		count: u32,
	}

	//---------------------------------------------------------------------------//

	@(private = "file")
	calculate_descriptor_layout_hash :: proc(
		p_layout_bindings: [dynamic]vk.DescriptorSetLayoutBinding,
	) -> u32 {
		hash_entries := make(
			[]DescriptorLayoutBindingHashEntry,
			len(p_layout_bindings),
			G_RENDERER_ALLOCATORS.temp_allocator,
		)
		defer delete(hash_entries, G_RENDERER_ALLOCATORS.temp_allocator)

		entry_idx := 0
		for binding in p_layout_bindings {

			hash_entries[entry_idx].slot = binding.binding
			hash_entries[entry_idx].count = binding.descriptorCount

			if binding.descriptorType == .SAMPLED_IMAGE {
				hash_entries[entry_idx].type = 0

			} else if binding.descriptorType == .STORAGE_IMAGE {
				hash_entries[entry_idx].type = 1
			} else if binding.descriptorType == .UNIFORM_BUFFER {
				hash_entries[entry_idx].type = 2
			} else if binding.descriptorType == .UNIFORM_BUFFER_DYNAMIC {
				hash_entries[entry_idx].type = 3
			} else if binding.descriptorType == .STORAGE_BUFFER {
				hash_entries[entry_idx].type = 4
			} else if binding.descriptorType == .STORAGE_BUFFER_DYNAMIC {
				hash_entries[entry_idx].type = 5
			} else {
				assert(false, "Unsupported descriptor type")
			}

			entry_idx += 1
		}
		return hash.adler32(mem.slice_to_bytes(hash_entries))
	}
}
