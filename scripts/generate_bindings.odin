/**
 * Generates VMA bindings from its header files.
 */

 package main

 import "core:fmt"
 
 import "../modules/third_party/odin-binding-generator/bindgen"
 
 main :: proc() {
     
    len_if_not_nul_handle :: proc(data : ^bindgen.ParserData) -> bindgen.LiteralValue {
        bindgen.check_and_eat_token(data, "len")
        return ""
    }

    // Original macros:
    // #define VK_DEFINE_HANDLE(object) typedef struct object##_T* object
    macro_define_handle :: proc(data : ^bindgen.ParserData) {
        bindgen.eat_token(data)
        bindgen.check_and_eat_token(data, "(")
        object := bindgen.parse_identifier(data)
        bindgen.check_and_eat_token(data, ")")

        structName := bindgen.tcat(object, "T")

        structNode : bindgen.StructDefinitionNode
        structNode.name = structName
        append(&data.nodes.structDefinitions, structNode)

        sourceType : bindgen.IdentifierType
        sourceType.name = structName

        pointerType : bindgen.PointerType
        pointerType.type = new(bindgen.Type)
        pointerType.type.base = sourceType

        typedefNode : bindgen.TypedefNode
        typedefNode.name = object
        typedefNode.type.base = pointerType
        append(&data.nodes.typedefs, typedefNode)
    }

    options : bindgen.GeneratorOptions
 
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
     options.parserOptions.customHandlers["VK_DEFINE_HANDLE"] = macro_define_handle;
     options.parserOptions.customHandlers["VK_DEFINE_NON_DISPATCHABLE_HANDLE"] = macro_define_handle;
     options.pseudoTypeTransparentPrefixes = []string{"PFN_"};
     
     options.parserOptions.ignoredTokens = []string{ "VKAPI_PTR", "VKAPI_CALL", "VKAPI_ATTR" };
     options.parserOptions.ignoredIdentifierDecorators = []string{"VMA_CALL_PRE", "VMA_CALL_POST"}
 
     bindgen.generate(
         packageName = "vma",
         foreignLibrary = "vma",
         outputFile = "modules/third_party/vma/vma.odin",
         headerFiles = []string{"modules/third_party/vma/external/vma_odin.h"},
         options = options,
     )
 }
 