package renderer

//---------------------------------------------------------------------------//

import "core:c/libc"
import "core:strings"
import "core:log"
import "core:fmt"
import "core:os"
import vk "vendor:vulkan"

import "../common"
import "../third_party/spirv_reflect"

//---------------------------------------------------------------------------//

when USE_VULKAN_BACKEND {

	//---------------------------------------------------------------------------//

	VulkanShaderBinding :: struct {
		name:    common.Name,
		set:     u32,
		binding: u32,
		count:   u32,
		type:    vk.DescriptorType,
	}

	//---------------------------------------------------------------------------//

	@(private)
	BackendShaderResource :: struct {
		desc_bindings: []VulkanShaderBinding,
		shader_module: vk.ShaderModule,
	}

	//---------------------------------------------------------------------------//

	backend_compile_shader :: proc(p_shader_entry: ShaderJSONEntry, p_ref: ShaderRef) -> (
		shader_resource: ShaderResource,
		compile_result: bool,
	) {
		// Determine shader type
		shader_type: ShaderType
		compile_target: string
		if strings.has_suffix(p_shader_entry.name, ".vert") {
			shader_type = .VERTEX
			compile_target = "vs_6_7"
		} else if strings.has_suffix(p_shader_entry.name, ".frag") {
			shader_type = .FRAGMENT
			compile_target = "ps_6_7"
		} else if strings.has_suffix(p_shader_entry.name, ".comp") {
			shader_type = .COMPUTE
			compile_target = "cs_6_7"

		} else {
			log.warnf("Unknown shader type %s...", p_shader_entry.name)
			return {}, false
		}

		shader_src_path := fmt.aprintf(
			"app_data/renderer/assets/shaders/%s",
			p_shader_entry.path,
		)
		defer delete(shader_src_path)
		shader_bin_path := fmt.aprintf(
			"app_data/renderer/assets/shaders/bin/%s.sprv",
			p_shader_entry.name,
		)
		defer delete(shader_bin_path)

		shader_resource = ShaderResource {
			type = shader_type,
		}

		// Compile the shader
		{
			log.infof("Compiling shader %s...", p_shader_entry.name)

			// @TODO replace with a single command when 
			// https://github.com/microsoft/DirectXShaderCompiler/issues/4496 is fixed
			compile_cmd := fmt.aprintf(
				"dxc -spirv -fspv-target-env=vulkan1.3 -HV 2021 -T %s -Fo %s %s",
				compile_target,
				shader_bin_path,
				shader_src_path,
			)

			if res := libc.system(strings.clone_to_cstring(compile_cmd)); res != 0 {
				log.warnf("Failed to compile shader %s: error code %d", p_shader_entry.name, res)
				return {}, false
			}
		}

		// Use reflection data to gather information about the shader 
		// that will be later used to create the pipeline layouts
		{
			//@TODO Uncomment when compiling and generating reflection data in one command works
			// reflect_data, ok := os.read_entire_file(shader_reflect_path)
			reflect_data, ok := os.read_entire_file(shader_bin_path)
			if ok == false {
				log.warnf("Failed to read reflection data for shader %s", p_shader_entry.name)
				return {}, false
			}
			defer delete(reflect_data)

			shader_module: spirv_reflect.ShaderModule
			if res := spirv_reflect.create_shader_module(
				   len(reflect_data),
				   raw_data(reflect_data),
				   &shader_module,
			   ); res != .Success {
				log.warnf(
					"Failed to create reflection data for shader %s: %s",
					p_shader_entry.name,
					res,
				)
				return {}, false
			}

			// @TODO remove when https://github.com/microsoft/DirectXShaderCompiler/issues/4496 is fixed
			strip_reflect_info_cmd := fmt.aprintf(
				"spirv-opt --strip-nonsemantic %s -o %s",
				shader_bin_path,
				shader_bin_path,
			)

			if res := libc.system(strings.clone_to_cstring(strip_reflect_info_cmd)); res != 0 {
				log.warnf("Failed to strip reflection info %s: error code %d", p_shader_entry.name, res)
				return {}, false
			}

			defer spirv_reflect.destroy_shader_module(&shader_module)

			num_descriptor_sets: u32 = 0
			spirv_reflect.enumerate_descriptor_sets(&shader_module, &num_descriptor_sets, nil)
			descriptor_sets := make([]^spirv_reflect.DescriptorSet, num_descriptor_sets)
			defer delete(descriptor_sets)
			spirv_reflect.enumerate_descriptor_sets(
				&shader_module,
				&num_descriptor_sets,
				raw_data(descriptor_sets),
			)

			// Count how many bindings in total the shader has and allocate memory for them
			{
				total_bindings: u32 = 0
				for i in 0 ..< num_descriptor_sets {
					total_bindings += descriptor_sets[i].binding_count
				}
				shader_resource.desc_bindings = make(
					[]VulkanShaderBinding,
					total_bindings,
					G_RENDERER_ALLOCATORS.resource_allocator,
				)

				defer if compile_result == false {
					delete(shader_resource.desc_bindings)
				}
			}

			// Fill binding information
			{
				curr_binding := 0
				for i in 0 ..< num_descriptor_sets {
					des_set := descriptor_sets[i]
					for j in 0 ..< des_set.binding_count {
						des_binding := des_set.bindings[j]
						shader_binding := &shader_resource.desc_bindings[curr_binding]

						shader_binding.binding = des_binding.binding
						shader_binding.name = common.create_name(string(des_binding.name))

						#partial switch des_binding.descriptor_type {
						case .Sampler:
							shader_binding.type = .SAMPLER
						case .CombinedImageSampler:
							shader_binding.type = .COMBINED_IMAGE_SAMPLER
						case .SampledImage:
							shader_binding.type = .SAMPLED_IMAGE
						case .StorageImage:
							shader_binding.type = .STORAGE_IMAGE
						case .UniformTexelBuffer:
							shader_binding.type = .UNIFORM_TEXEL_BUFFER
						case .StorageTexelBuffer:
							shader_binding.type = .STORAGE_TEXEL_BUFFER
						case .UniformBuffer:
							shader_binding.type = .UNIFORM_BUFFER
						case .StorageBuffer:
							shader_binding.type = .STORAGE_BUFFER
						case .UniformBufferDynamic:
							shader_binding.type = .UNIFORM_BUFFER_DYNAMIC
						case .StorageBufferDynamic:
							shader_binding.type = .STORAGE_BUFFER_DYNAMIC
						case .InputAttachment:
							shader_binding.type = .INPUT_ATTACHMENT
						}

						shader_binding.count = des_binding.count
						curr_binding += 1
					}
				}

				when ODIN_DEBUG {
					defer if compile_result == false {
						for binding in shader_resource.desc_bindings {
							delete(binding.name.name)
						}
					}
				}
			}
		}

		// Create the shader module
		{
			shader_code, ok := os.read_entire_file(shader_bin_path)
			if ok == false {
				log.warnf("Failed to read shader code for shader %s", p_shader_entry.name)
				return {}, false
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
				   &shader_resource.shader_module,
			   ); create_res != .SUCCESS {
				log.warnf(
					"Failed to create module for shader %s: %s",
					p_shader_entry.name,
					create_res,
				)
				return {}, false
			}
		}

		return shader_resource, true
	}

	//---------------------------------------------------------------------------//
}
