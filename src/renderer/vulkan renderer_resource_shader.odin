
package renderer

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	import "core:c/libc"
	import "core:strings"
	import "core:log"
	import "core:fmt"
	import "core:os"
	import "core:hash"
	import vk "vendor:vulkan"

	import "../common"
	import "../third_party/spirv_reflect"

	//---------------------------------------------------------------------------//

	VulkanShaderDescriptorSet :: struct {
		set:         u8,
		descriptors: []VulkanShaderDescriptor,
	}

	//---------------------------------------------------------------------------//

	VulkanShaderDescriptor :: struct {
		name:    common.Name,
		binding: u32,
		count:   u32,
		type:    vk.DescriptorType,
	}

	//---------------------------------------------------------------------------//

	FragmentOutput :: struct {
		location: u32,
	}


	//---------------------------------------------------------------------------//

	@(private)
	BackendShaderResource :: struct {
		vk_module:          vk.ShaderModule,
		vk_descriptor_sets: []VulkanShaderDescriptorSet,
	}

	//---------------------------------------------------------------------------//


	@(private = "file")
	INTERNAL: struct {}

	//---------------------------------------------------------------------------//

	@(private)
	backend_init_shaders :: proc() -> bool {
		return true
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_deinit_shaders :: proc() {
	}

	//---------------------------------------------------------------------------//

	@(private)
	backend_create_shader :: proc(
		p_ref: ShaderRef,
		p_shader: ^ShaderResource,
	) -> (
		create_result: bool,
	) {


		// Determine compile target
		compile_target: string
		switch p_shader.desc.type {
		case .VERTEX:
			compile_target = "vs_6_7"

		case .FRAGMENT:
			compile_target = "ps_6_7"

		case .COMPUTE:
			compile_target = "cs_6_7"
		}

		shader_path := p_shader.desc.file_path
		shader_src_path := fmt.aprintf("app_data/renderer/assets/shaders/%s", shader_path)
		shader_bin_path := fmt.aprintf("app_data/renderer/assets/shaders/bin/%s.sprv", shader_path)

		// Compile the shader
		{
			// Add defines for macros
			shader_defines := ""
			shader_defines_log := ""
			for feature in p_shader.desc.features {
				shader_defines = fmt.aprintf("%s -D %s", shader_defines, feature)
				shader_defines_log = fmt.aprintf("%s\n%s\n", shader_defines_log, feature)
			}

			log.infof("Compiling shader %s with features %s\n", shader_path, shader_defines_log)

			// @TODO replace with a single command when 
			// https://github.com/microsoft/DirectXShaderCompiler/issues/4496 is fixed
			compile_cmd := fmt.aprintf(
				"dxc -spirv -fspv-target-env=vulkan1.3 -HV 2021 -T %s -Fo %s %s %s",
				compile_target,
				shader_bin_path,
				shader_src_path,
				shader_defines,
			)

			if res := libc.system(strings.clone_to_cstring(compile_cmd)); res != 0 {
				log.warnf("Failed to compile shader %s: error code %d", shader_path, res)
				return false
			}
		}

		// Use reflection data to gather information about the shader 
		// that will be later used to create the pipeline layouts
		{
			//@TODO Uncomment when compiling and generating reflection data in one command works
			// reflect_data, ok := os.read_entire_file(shader_reflect_path)
			reflect_data, ok := os.read_entire_file(shader_bin_path)
			if ok == false {
				log.warnf("Failed to read reflection data for shader %s", shader_path)
				return false
			}
			p_shader.hash = hash.adler32(reflect_data)

			shader_module: spirv_reflect.ShaderModule
			if res := spirv_reflect.create_shader_module(
				len(reflect_data),
				raw_data(reflect_data),
				&shader_module,
			); res != .Success {
				log.warnf("Failed to create reflection data for shader %s: %s", shader_path, res)
				return false
			}

			// @TODO remove when https://github.com/microsoft/DirectXShaderCompiler/issues/4496 is fixed
			strip_reflect_info_cmd := fmt.aprintf(
				"spirv-opt --strip-nonsemantic %s -o %s",
				shader_bin_path,
				shader_bin_path,
			)

			if res := libc.system(strings.clone_to_cstring(strip_reflect_info_cmd)); res != 0 {
				log.warnf("Failed to strip reflection info %s: error code %d", shader_path, res)
				return false
			}

			defer spirv_reflect.destroy_shader_module(&shader_module)

			num_descriptor_sets: u32 = 0
			spirv_reflect.enumerate_descriptor_sets(&shader_module, &num_descriptor_sets, nil)

			descriptor_sets := make(
				[]^spirv_reflect.DescriptorSet,
				num_descriptor_sets,
				G_RENDERER_ALLOCATORS.temp_allocator,
			)
			defer delete(descriptor_sets, G_RENDERER_ALLOCATORS.temp_allocator)

			spirv_reflect.enumerate_descriptor_sets(
				&shader_module,
				&num_descriptor_sets,
				raw_data(descriptor_sets),
			)

			// Skip set 0 which contains the bindless array and immutable samplers
			// This is created in the vulkan_renderer_resource_image.odin file
			for descriptor_set in descriptor_sets {
				if descriptor_set.set == 2 {
					p_shader.flags += {.UsesBindlessArray}
					num_descriptor_sets -= 1
					break
				}
			}

			// Determine how many descriptors there are for each sets
			{
				p_shader.vk_descriptor_sets = make(
					[]VulkanShaderDescriptorSet,
					num_descriptor_sets,
					G_RENDERER_ALLOCATORS.resource_allocator,
				)

				for i in 0 ..< num_descriptor_sets {
					// Fill set info and create the descriptors array
					descriptor_set := descriptor_sets[i]
					binding_count := descriptor_set.binding_count

					p_shader.vk_descriptor_sets[i].set = u8(descriptor_set.set)
					p_shader.vk_descriptor_sets[i].descriptors = make(
						[]VulkanShaderDescriptor,
						binding_count,
						G_RENDERER_ALLOCATORS.resource_allocator,
					)

					// Fill descriptors info
					for j in 0 ..< descriptor_set.binding_count {
						descriptor := &p_shader.vk_descriptor_sets[i].descriptors[j]

						// Skip already added samplers
						if descriptor_set.bindings[j].descriptor_type == .Sampler {
							continue
						}

						descriptor.binding = descriptor_set.bindings[j].binding
						descriptor.name = common.create_name(
							string(descriptor_set.bindings[j].name),
						)
						descriptor.count = descriptor_set.bindings[j].count

						#partial switch descriptor_set.bindings[j].descriptor_type {
						case .SampledImage:
							descriptor.type = .SAMPLED_IMAGE
						case .StorageImage:
							descriptor.type = .STORAGE_IMAGE
						case .UniformBuffer:
							if strings.has_suffix(common.get_string(descriptor.name), "_Dynamic") {
								descriptor.type = .UNIFORM_BUFFER_DYNAMIC
							} else {
								descriptor.type = .UNIFORM_BUFFER
							}
						case .StorageBuffer:
							if strings.has_suffix(common.get_string(descriptor.name), "_Dynamic") {
								descriptor.type = .STORAGE_BUFFER_DYNAMIC
							} else {
								descriptor.type = .STORAGE_BUFFER
							}
						case .UniformBufferDynamic:
							descriptor.type = .UNIFORM_BUFFER_DYNAMIC
						case .StorageBufferDynamic:
							descriptor.type = .STORAGE_BUFFER_DYNAMIC
						case:
							assert(false) // Unsupported binding
						}
					}
				}
			}
		}

		defer if create_result == false {
			for descriptor_set in p_shader.vk_descriptor_sets {
				delete(descriptor_set.descriptors, G_RENDERER_ALLOCATORS.resource_allocator)
			}
			delete(p_shader.vk_descriptor_sets, G_RENDERER_ALLOCATORS.resource_allocator)
		}

		// Create the shader module
		{
			shader_code, ok := os.read_entire_file(shader_bin_path)
			if ok == false {
				log.warnf("Failed to read shader code for shader %s", shader_path)
				return false
			}
			module_create_info := vk.ShaderModuleCreateInfo {
				sType    = .SHADER_MODULE_CREATE_INFO,
				codeSize = len(shader_code),
				pCode    = cast(^u32)raw_data(shader_code),
			}
			if create_res := vk.CreateShaderModule(
				G_RENDERER.device,
				&module_create_info,
				nil,
				&p_shader.vk_module,
			); create_res != .SUCCESS {
				log.warnf("Failed to create module for shader %s: %s", shader_path, create_res)
				return false
			}
		}

		return true
	}
	//---------------------------------------------------------------------------//

	@(private)
	backend_destroy_shader :: proc(p_shader: ^ShaderResource) {
		if len(p_shader.vk_descriptor_sets) > 0 {
			for descriptor_set in p_shader.vk_descriptor_sets {
				delete(descriptor_set.descriptors, G_RENDERER_ALLOCATORS.resource_allocator)
			}
			delete(p_shader.vk_descriptor_sets, G_RENDERER_ALLOCATORS.resource_allocator)
		}
		vk.DestroyShaderModule(G_RENDERER.device, p_shader.vk_module, nil)
	}

}
