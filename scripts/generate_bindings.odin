/**
 * Generates VMA bindings from its header files.
 */

package main

import "core:fmt"

import "../src/third_party/odin-binding-generator/bindgen"

main :: proc() {
	// generate_vma_bindings()
	// generate_tiny_obj_loader_bindings()
	// generate_assimp_bindings()
	generate_spirv_reflect_binding()
}
generate_assimp_bindings :: proc() {
	options: bindgen.GeneratorOptions

	// We remove defines' prefix.
	options.defineCase = bindgen.Case.Constant
	options.functionPrefixes = []string{"ai"}
	options.functionCase = bindgen.Case.Snake
	options.enumValueCase = bindgen.Case.Pascal
	options.enumValueNameRemove = true
	options.pseudoTypeTransparentPrefixes = []string{"ai"}
	options.pseudoTypeTransparentPrefixes = []string{"AI_"}
	options.definePrefixes = []string{"AI_"}
	options.pseudoTypePrefixes = []string{"ai"}
	options.functionPrefixes = []string{"ai"}
	options.enumValuePrefixes = []string{"AI_","Ai"}
	options.parserOptions.ignoredTokens = []string {"__cplusplus"}

	bindgen.generate(
		packageName = "assimp",
		foreignLibrary = "assimp-vc143-mt.lib",
		outputFile = "src/third_party/assimp/assimp.odin",
		headerFiles = []string{
			"src/third_party/assimp/external/aabb.h",
			"src/third_party/assimp/external/anim.h",
			"src/third_party/assimp/external/camera.h",
			"src/third_party/assimp/external/cimport.h",
			"src/third_party/assimp/external/color4.h",
			"src/third_party/assimp/external/importerdesc.h",
			"src/third_party/assimp/external/light.h",
			"src/third_party/assimp/external/material.h",
			"src/third_party/assimp/external/matrix3x3.h",
			"src/third_party/assimp/external/matrix4x4.h",
			"src/third_party/assimp/external/mesh.h",
			"src/third_party/assimp/external/metadata.h",
			"src/third_party/assimp/external/pbrmaterial.h",
			"src/third_party/assimp/external/postprocess.h",
			"src/third_party/assimp/external/quaternion.h",
			"src/third_party/assimp/external/scene.h",
			"src/third_party/assimp/external/texture.h",
			"src/third_party/assimp/external/types.h",
			"src/third_party/assimp/external/vector2.h",
			"src/third_party/assimp/external/vector3.h",
			"src/third_party/assimp/external/version.h",
		},
		options = options,
	)
}

generate_spirv_reflect_binding :: proc() {
	options: bindgen.GeneratorOptions

	// We remove defines' prefix.
	options.defineCase = bindgen.Case.Constant
	options.functionCase = bindgen.Case.Snake
	options.enumValueCase = bindgen.Case.Pascal
	options.enumValueNameRemove = true

	bindgen.generate(
		packageName = "spirv_reflect",
		foreignLibrary = "spirv_reflect.lib",
		outputFile = "src/third_party/spirv_reflect/spirv_reflect.odin",
		headerFiles = []string{
			"src/third_party/spirv_reflect/external/spirv.h",
			"src/third_party/spirv_reflect/external/spirv_reflect.h"},
		options = options,
	)
}


generate_tiny_obj_loader_bindings :: proc() {
	options: bindgen.GeneratorOptions

	// We remove defines' prefix.
	options.defineCase = bindgen.Case.Constant
	options.functionPrefixes = []string{"tinyobj_"}
	options.functionCase = bindgen.Case.Snake
	options.enumValueCase = bindgen.Case.Pascal
	options.enumValueNameRemove = true
	options.pseudoTypeTransparentPrefixes = []string{"TINYOBJ_"}

	bindgen.generate(
		packageName = "tiny_obj_loader",
		foreignLibrary = "tiny_obj_loader.lib",
		outputFile = "src/third_party/tiny_obj_loader/tiny_obj_loader.odin",
		headerFiles = []string{"src/third_party/tiny_obj_loader/external/tiny_obj_loader.h"},
		options = options,
	)
}

generate_vma_bindings :: proc() {
	len_if_not_nul_handle :: proc(data: ^bindgen.ParserData) -> bindgen.LiteralValue {
		bindgen.check_and_eat_token(data, "len")
		return ""
	}

	// Original macros:
	// #define VK_DEFINE_HANDLE(object) typedef struct object##_T* object
	macro_define_handle :: proc(data: ^bindgen.ParserData) {
		bindgen.eat_token(data)
		bindgen.check_and_eat_token(data, "(")
		object := bindgen.parse_identifier(data)
		bindgen.check_and_eat_token(data, ")")

		structName := bindgen.tcat(object, "T")

		structNode: bindgen.StructDefinitionNode
		structNode.name = structName
		append(&data.nodes.structDefinitions, structNode)

		sourceType: bindgen.IdentifierType
		sourceType.name = structName

		pointerType: bindgen.PointerType
		pointerType.type = new(bindgen.Type)
		pointerType.type.base = sourceType

		typedefNode: bindgen.TypedefNode
		typedefNode.name = object
		typedefNode.type.base = pointerType
		append(&data.nodes.typedefs, typedefNode)
	}

	options: bindgen.GeneratorOptions

	// We remove defines' prefix.
	options.definePrefixes = []string{"VMA_"}
	options.defineCase = bindgen.Case.Constant

	options.pseudoTypePrefixes = []string{"Vma", "vma"}

	options.functionPrefixes = []string{"vma"}
	options.functionCase = bindgen.Case.Snake

	options.enumValuePrefixes = []string{"VMA_"}
	options.enumValueCase = bindgen.Case.Pascal
	options.enumValueNameRemove = true

	options.parserOptions.customExpressionHandlers["len"] = len_if_not_nul_handle
	options.parserOptions.customHandlers["VK_DEFINE_HANDLE"] = macro_define_handle
	options.parserOptions.customHandlers["VK_DEFINE_NON_DISPATCHABLE_HANDLE"] = macro_define_handle
	options.pseudoTypeTransparentPrefixes = []string{"PFN_"}

	options.parserOptions.ignoredTokens = []string{"VKAPI_PTR", "VKAPI_CALL", "VKAPI_ATTR"}
	// options.parserOptions.ignoredIdentifierDecorators = []string{
	// 	"VMA_CALL_PRE",
	// 	"VMA_CALL_POST",
	// }

	bindgen.generate(
		packageName = "vma",
		foreignLibrary = "vma.lib",
		outputFile = "src/third_party/vma/vma.odin",
		headerFiles = []string{"src/third_party/vma/external/vma_odin.h"},
		options = options,
	)
}
